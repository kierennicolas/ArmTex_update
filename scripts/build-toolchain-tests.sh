#!/usr/bin/env bash
# Build the Milestone 1 toolchain test programs for each code-generation
# variant, convert them to AIF, compile the C++ feature probes, and record
# every result in <out-dir>/results.json.
#
# Usage: scripts/build-toolchain-tests.sh <out-dir>
#
# Runs inside the toolchain image, which puts the GCCSDK cross tools on PATH.
# Layout of <out-dir>:
#   elf/<variant>/<program>       statically linked ELF from the compiler
#   aif/<variant>/<program>,ff8   the same program converted by elf2aif
#   logs/<variant>-<program>.log  compiler and elf2aif output
#   logs/probe-<name>.log         compiler output for each probe
#   results.json                  machine-readable record of all of the above
#
# Exits 1 if any required program fails to build. Probes (programs and feature
# tests whose support we are measuring) never fail the script; their results
# are recorded instead.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/tests/toolchain"

if [ $# -ne 1 ]; then
  echo "usage: $0 <out-dir>" >&2
  exit 2
fi
out=$1
rm -rf "$out"
mkdir -p "$out/elf" "$out/aif" "$out/logs"
out=$(cd "$out" && pwd)

target=arm-unknown-riscos
cc="$target-gcc"
cxx="$target-g++"
elf2aif=
for name in elf2aif "$target-elf2aif"; do
  if command -v "$name" > /dev/null; then elf2aif=$name; break; fi
done
if [ -z "$elf2aif" ]; then
  echo "error: elf2aif not found on PATH" >&2
  exit 1
fi

# Variants: name|extra compiler flags|description
variants=(
  "soft||UnixLib default: soft-float, generic ARM code"
  "vfp|-mfpu=vfp -mfloat-abi=softfp|VFP floating point, softfp calling convention"
  "a15|-mfpu=vfp -mfloat-abi=softfp -mcpu=cortex-a15|VFP, code generated for the Cortex-A15"
  "a15noua|-mfpu=vfp -mfloat-abi=softfp -mcpu=cortex-a15 -mno-unaligned-access|As a15, with unaligned loads disabled"
)

# Programs: name|source|language standard|required or probe|variants
programs=(
  "hello|hello.c|gnu99|required|soft vfp a15"
  "float|float.c|gnu99|required|soft vfp a15"
  "unaligned|unaligned.c|gnu99|required|soft vfp a15 a15noua"
  "cxx11|cxx11.cc|c++11|required|soft vfp a15"
  "cxx17|cxx17.cc|c++17|probe|soft vfp a15"
)

# Older GCC releases spell newer standards differently.
std_candidates() {
  case $1 in
    c++11) echo "c++11 c++0x" ;;
    c++14) echo "c++14 c++1y" ;;
    c++17) echo "c++17 c++1z" ;;
    *) echo "$1" ;;
  esac
}

variant_flags() {
  local v
  for v in "${variants[@]}"; do
    IFS='|' read -r name flags _ <<< "$v"
    if [ "$name" = "$1" ]; then echo "$flags"; return; fi
  done
  echo "unknown variant $1" >&2
  exit 1
}

# Link with -lm only if the toolchain has a separate maths library; UnixLib
# may provide the maths functions itself.
libm=
if [ "$("$cc" -print-file-name=libm.a)" != "libm.a" ]; then libm=-lm; fi

records="$out/records.jsonl"
: > "$records"
required_failures=0

for p in "${programs[@]}"; do
  IFS='|' read -r prog source std kind prog_variants <<< "$p"
  case $source in
    *.c) compiler=$cc ;;
    *) compiler=$cxx ;;
  esac
  for variant in $prog_variants; do
    flags=$(variant_flags "$variant")
    mkdir -p "$out/elf/$variant" "$out/aif/$variant"
    elf="$out/elf/$variant/$prog"
    aif="$out/aif/$variant/$prog,ff8"
    log="$out/logs/$variant-$prog.log"
    compiled=false
    converted=false
    used_std=
    : > "$log"
    for s in $(std_candidates "$std"); do
      # shellcheck disable=SC2086  # flags are deliberately word-split
      if { echo "+ $compiler -std=$s -O2 -Wall -static $flags -o $elf $src/$source $libm"
           "$compiler" -std="$s" -O2 -Wall -static $flags -o "$elf" "$src/$source" $libm; } >> "$log" 2>&1; then
        compiled=true
        used_std=$s
        break
      fi
    done
    if $compiled; then
      if { echo "+ $elf2aif $elf $aif"; "$elf2aif" "$elf" "$aif"; } >> "$log" 2>&1; then
        converted=true
      fi
    fi
    status=ok
    if ! $compiled; then status=compile-failed; elif ! $converted; then status=convert-failed; fi
    printf '%-10s %-8s %-9s %s\n' "$prog" "$variant" "$kind" "$status"
    if [ "$status" != ok ] && [ "$kind" = required ]; then
      required_failures=$((required_failures + 1))
      echo "---- $log ----"
      tail -n 30 "$log"
    fi
    jq -cn --arg program "$prog" --arg variant "$variant" --arg kind "$kind" \
      --arg source "tests/toolchain/$source" --arg std "$used_std" --arg flags "$flags" \
      --arg status "$status" --argjson compiled "$compiled" --argjson converted "$converted" \
      --arg log "logs/$(basename "$log")" \
      '{type: "build", program: $program, variant: $variant, kind: $kind, source: $source,
        std: $std, flags: $flags, status: $status, compiled: $compiled,
        converted: $converted, log: $log}' >> "$records"
  done
done

# Compile-only probes: one language or library feature each, built for the
# default variant. The first line of each probe names its standard.
for probe in "$src"/probes/*.cc; do
  name=$(basename "$probe" .cc)
  std=$(sed -n '1s#^// std: ##p' "$probe")
  description=$(sed -n '2s#^// ##p' "$probe")
  log="$out/logs/probe-$name.log"
  compiled=false
  used_std=
  : > "$log"
  for s in $(std_candidates "$std"); do
    if { echo "+ $cxx -std=$s -c -o /dev/null $probe"
         "$cxx" -std="$s" -c -o /dev/null "$probe"; } >> "$log" 2>&1; then
      compiled=true
      used_std=$s
      break
    fi
  done
  first_error=
  if ! $compiled; then
    first_error=$(grep -m1 -E 'error|unrecognized' "$log" || true)
  fi
  printf '%-32s %-6s %s\n' "$name" "$std" "$($compiled && echo supported || echo 'not supported')"
  jq -cn --arg name "$name" --arg std "$std" --arg used "$used_std" \
    --arg description "$description" --argjson compiled "$compiled" \
    --arg first_error "$first_error" --arg log "logs/$(basename "$log")" \
    '{type: "probe", name: $name, std: $std, std_flag_used: $used,
      description: $description, compiled: $compiled, first_error: $first_error,
      log: $log}' >> "$records"
done

commit=${BUILD_COMMIT:-${GITHUB_SHA:-$(git -c safe.directory="*" -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)}}
jq -s --arg gcc "$("$cc" --version | head -1)" --arg gxx "$("$cxx" --version | head -1)" \
  --arg commit "$commit" --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg libm "$libm" \
  --argjson variants "$(printf '%s\n' "${variants[@]}" | jq -R 'split("|") | {name: .[0], flags: .[1], description: .[2]}' | jq -s .)" \
  '{commit: $commit, generated: $date, compiler: {gcc: $gcc, gxx: $gxx}, maths_library_flag: $libm,
    variants: $variants,
    builds: [.[] | select(.type == "build") | del(.type)],
    probes: [.[] | select(.type == "probe") | del(.type)]}' \
  "$records" > "$out/results.json"
rm -f "$records"

echo
if [ "$required_failures" -gt 0 ]; then
  echo "error: $required_failures required build(s) failed" >&2
  exit 1
fi
echo "All required programs built and converted."
