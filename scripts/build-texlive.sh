#!/usr/bin/env bash
# Cross-configure TeX Live for RISC OS and build the components Milestone 2
# needs, recording which of them build.
#
# Usage: scripts/build-texlive.sh <texlive-source> <host-tools-prefix> <out-dir>
#
# Runs inside the toolchain image. <host-tools-prefix> comes from
# scripts/build-host-tools.sh: web2c needs tangle, ctangle, tie and otangle
# that run on the build machine.
#
# Components are "required" (Milestone 2 cannot finish without them) or
# "probe" (later milestones need them, and we want to know early whether this
# compiler can build them). Every component is attempted; the script exits 1
# only if a required one fails.
#
# Layout of <out-dir>:
#   build/                    the cross build tree
#   logs/                     configure and make logs, one per component
#   bin/<program>             cross-compiled ELF programs
#   aif/<program>,ff8         the same programs converted by elf2aif
#   results.json              what was attempted and what happened
#
# Environment:
#   TL_VARIANT   code-generation variant from build-toolchain-tests.sh
#                (soft, vfp or a15; default soft)

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if [ $# -ne 3 ]; then
  echo "usage: $0 <texlive-source> <host-tools-prefix> <out-dir>" >&2
  exit 2
fi
src=$(cd "$1" && pwd)
hosttools=$(cd "$2" && pwd)
mkdir -p "$3"
out=$(cd "$3" && pwd)
rm -rf "${out:?}/build" "${out:?}/logs" "${out:?}/bin" "${out:?}/aif" "${out:?}/wrappers"
mkdir -p "$out/build" "$out/logs" "$out/bin" "$out/aif"

target=arm-unknown-riscos
variant=${TL_VARIANT:-soft}
case $variant in
  soft) variant_flags= ;;
  vfp) variant_flags="-mfpu=vfp -mfloat-abi=softfp" ;;
  a15) variant_flags="-mfpu=vfp -mfloat-abi=softfp -mcpu=cortex-a15" ;;
  *) echo "error: unknown TL_VARIANT '$variant'" >&2; exit 2 ;;
esac
elf2aif=
for name in elf2aif "$target-elf2aif"; do
  if command -v "$name" > /dev/null; then elf2aif=$name; break; fi
done

revision=$(git -c safe.directory='*' -C "$src" rev-parse HEAD)
build_triplet=$("$src/build-aux/config.guess")
jobs=$(nproc)

# Compiler wrappers that always link statically. GCCSDK links against shared
# libraries by default, and putting -static in CC or LDFLAGS is not enough:
# kpsewhich, linked through libtool, still came out dynamically linked. A
# wrapper is invisible to libtool, so -static always reaches the compiler.
wrappers="$out/wrappers"
mkdir -p "$wrappers"
for tool in gcc g++; do
  real=$(command -v "$target-$tool")
  printf '#!/bin/sh\n# Written by scripts/build-texlive.sh: always link statically.\nexec %s -static "$@"\n' \
    "$real" > "$wrappers/$target-$tool"
  chmod +x "$wrappers/$target-$tool"
done

# Wrappers first, then host tools, so configure finds tangle and friends for
# the build machine rather than trying to run cross-compiled ones.
export PATH="$wrappers:$hosttools/bin:$PATH"
# Answers for configure tests that cannot run when cross-compiling.
export CONFIG_SITE="$root/riscos/compatibility/config.site"

configure_args=(
  --host="$target"
  --build="$build_triplet"
  --disable-all-pkgs
  --enable-pdftex
  --enable-luahbtex
  --disable-xetex
  --disable-synctex
  --without-x
  --enable-missing
  --disable-shared
  --disable-native-texlive-build
  # The static-linking wrappers above. -std=gnu++11: GCC 4.7 defaults to
  # C++98, and the C++ libraries (xpdf, HarfBuzz, graphite2) need C++11.
  CC="$target-gcc"
  CXX="$target-g++ -std=gnu++11"
  # AR, RANLIB and STRIP are left for configure to find from --host. Passing
  # them explicitly also reaches web2c's helper programs, which are built for
  # the build machine: their library then had no symbol index, and the host
  # linker refused it.
  BUILDCC=gcc
  BUILDCXX=g++
  "CFLAGS=-O2 $variant_flags"
  "CXXFLAGS=-O2 $variant_flags"
)

# A git checkout gives every file the same timestamp, so make may think the
# generated Info manuals are out of date; regenerating them needs makeinfo,
# which the build does not otherwise use.
make_vars=(MAKEINFO=true)

records="$out/records.jsonl"
: > "$records"
required_failures=0

record() {
  # record <name> <kind> <status> <log> [detail]
  local name=$1 kind=$2 status=$3 log=$4 detail=${5:-}
  printf '%-12s %-9s %s\n' "$name" "$kind" "$status"
  if [ "$status" != built ] && [ "$kind" = required ]; then
    required_failures=$((required_failures + 1))
    if [ -f "$out/logs/$log" ]; then
      echo "---- $log (last 25 lines) ----"
      tail -n 25 "$out/logs/$log"
    fi
  fi
  jq -cn --arg name "$name" --arg kind "$kind" --arg status "$status" \
    --arg log "logs/$log" --arg detail "$detail" \
    '{name: $name, kind: $kind, status: $status, log: $log, detail: $detail}' >> "$records"
}

first_error() {
  grep -m1 -E 'error:|Error [0-9]|undefined reference|cannot|not found' "$1" 2>/dev/null | cut -c1-200 || true
}

finish() {
  jq -s --arg revision "$revision" --arg variant "$variant" \
    --arg gcc "$("$target-gcc" --version | head -1)" \
    --argjson args "$(printf '%s\n' "${configure_args[@]}" | jq -R . | jq -s .)" \
    '{texlive_revision: $revision, variant: $variant, compiler: $gcc,
      configure_args: $args, components: .}' "$records" > "$out/results.json"
  rm -f "$records"
}

cd "$out/build"
echo "Configuring TeX Live $revision for $target ($variant)"
if "$src/configure" "${configure_args[@]}" > "$out/logs/configure.log" 2>&1; then
  record configure required built configure.log
else
  record configure required failed configure.log "$(first_error "$out/logs/configure.log")"
  finish
  exit 1
fi

# The top-level make configures each module and builds the libraries the
# enabled programs need. Keep going past failures to learn as much as
# possible from one run.
echo "Building libraries (make -k)"
make -k -j"$jobs" "${make_vars[@]}" > "$out/logs/make.log" 2>&1 || true

# Libraries: name|kind|directory under the build tree
libraries=(
  "zlib|required|libs/zlib"
  "libpng|required|libs/libpng"
  "xpdf|required|libs/xpdf"
  "kpathsea|required|texk/kpathsea"
  "freetype2|probe|libs/freetype2"
  "pplib|probe|libs/pplib"
  "zziplib|probe|libs/zziplib"
  "lua53|probe|libs/lua53"
  "graphite2|probe|libs/graphite2"
  "harfbuzz|probe|libs/harfbuzz"
  "gmp|probe|libs/gmp"
  "mpfr|probe|libs/mpfr"
)

for entry in "${libraries[@]}"; do
  IFS='|' read -r name kind dir <<< "$entry"
  log="lib-$name.log"
  if [ ! -f "$dir/Makefile" ]; then
    if [ -f "$dir/config.log" ]; then
      cp "$dir/config.log" "$out/logs/$log"
      record "$name" "$kind" configure-failed "$log" "$(grep -m1 -E 'configure:[0-9]*: error' "$dir/config.log" | cut -c1-200)"
    else
      : > "$out/logs/$log"
      record "$name" "$kind" not-configured "$log"
    fi
    continue
  fi
  # Re-run make in the module on its own so its log is not interleaved.
  if make -C "$dir" "${make_vars[@]}" > "$out/logs/$log" 2>&1 && find "$dir" -name '*.a' -newer "$out/logs/configure.log" | grep -q .; then
    record "$name" "$kind" built "$log"
  else
    record "$name" "$kind" build-failed "$log" "$(first_error "$out/logs/$log")"
  fi
done

# Programs: name|kind|make directory|make target|binary path
programs=(
  "kpsewhich|required|texk/kpathsea|kpsewhich|texk/kpathsea/kpsewhich"
  "pdftex|probe|texk/web2c|pdftex|texk/web2c/pdftex"
)

for entry in "${programs[@]}"; do
  IFS='|' read -r name kind dir make_target binary <<< "$entry"
  log="prog-$name.log"
  if [ ! -f "$dir/Makefile" ]; then
    : > "$out/logs/$log"
    record "$name" "$kind" not-configured "$log"
    continue
  fi
  if ! make -C "$dir" "${make_vars[@]}" "$make_target" > "$out/logs/$log" 2>&1 || [ ! -f "$binary" ]; then
    record "$name" "$kind" build-failed "$log" "$(first_error "$out/logs/$log")"
    continue
  fi
  cp "$binary" "$out/bin/$name"
  if [ -n "$elf2aif" ] && "$elf2aif" "$out/bin/$name" "$out/aif/$name,ff8" >> "$out/logs/$log" 2>&1; then
    record "$name" "$kind" built "$log"
  else
    record "$name" "$kind" convert-failed "$log"
  fi
done

finish

echo
if [ "$required_failures" -gt 0 ]; then
  echo "error: $required_failures required component(s) failed" >&2
  exit 1
fi
echo "All required components built."
