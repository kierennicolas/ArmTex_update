#!/usr/bin/env bash
# Package the Milestone 1 toolchain test programs as a RISC OS test kit.
#
# Usage: scripts/package-testkit.sh <out-dir>
#
# Reads <out-dir>/results.json and the AIF files written by
# scripts/build-toolchain-tests.sh, and produces:
#   <out-dir>/kit/TLTest/          the kit as a tree with ,xxx filetype suffixes
#   <out-dir>/TLTest.zip           the kit as a RISC OS zip with filetypes set
#
# The kit contains every program that built, an Obey file (RunAll) that runs
# them and saves the output to TLTest.Results, a BuildInfo text file and a
# ReadMe. The zip is checked after it is written: every file must carry the
# filetype its suffix named.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if [ $# -ne 1 ]; then
  echo "usage: $0 <out-dir>" >&2
  exit 2
fi
out=$(cd "$1" && pwd)
results="$out/results.json"
kit="$out/kit/TLTest"
zip="$out/TLTest.zip"

rm -rf "$out/kit" "$zip"
mkdir -p "$kit"

commit=$(jq -r .commit "$results")
short=${commit:0:12}

# Copy the programs that built.
jq -r '.builds[] | select(.status == "ok") | [.program, .variant] | @tsv' "$results" |
  while IFS=$'\t' read -r program variant; do
    mkdir -p "$kit/$variant"
    cp "$out/aif/$variant/$program,ff8" "$kit/$variant/$program,ff8"
  done

built() { [ -f "$kit/$2/$1,ff8" ]; }

# The Obey file. RISC OS expands <variables> on each line as it runs, so
# Sys$ReturnCode shows the exit status of the program run just before.
# Risky tests (unaligned access) go last, so a crash there loses nothing else.
obey="$kit/RunAll,feb"
{
  echo "| TeX Live for RISC OS: Milestone 1 toolchain test kit"
  echo "| Built from commit $commit"
  echo "| Run this file (double-click it, or *Obey it). The output is saved"
  echo "| in the file Results in this directory."
  echo "Set TLTest\$Dir <Obey\$Dir>"
  echo "RMEnsure SharedUnixLibrary 1.13 RMLoad System:Modules.SharedULib"
  echo "RMEnsure SharedUnixLibrary 1.13 Error The TLTest kit needs SharedUnixLibrary 1.13 or later. Install it with PackMan, then run RunAll again."
  echo "Set TLTest\$Var expected"
  echo "Set TLTEST_PLAIN expected-plain"
  echo "Dir <TLTest\$Dir>"
  echo "Spool <TLTest\$Dir>.Results"
  echo "Echo TeX Live for RISC OS toolchain test kit, commit $short"
  echo "Help UtilityModule"
  echo "Help SharedUnixLibrary"
  echo "Type <TLTest\$Dir>.BuildInfo"
  for variant in soft vfp a15 a15noua; do
    for program in hello float cxx11 cxx17; do
      if built "$program" "$variant"; then
        echo "Echo ===== $variant $program ====="
        echo "Run <TLTest\$Dir>.$variant.$program"
        echo "Echo ===== $variant $program finished, exit status <Sys\$ReturnCode> ====="
      fi
    done
  done
  if built hello soft; then
    echo "Echo ===== soft hello --exit 3 (exit status should be 3) ====="
    echo "Run <TLTest\$Dir>.soft.hello --exit 3"
    echo "Echo ===== soft hello --exit 3 finished, exit status <Sys\$ReturnCode> ====="
  fi
  for variant in soft vfp a15 a15noua; do
    if built unaligned "$variant"; then
      echo "Echo ===== $variant unaligned ====="
      echo "Run <TLTest\$Dir>.$variant.unaligned"
      echo "Echo ===== $variant unaligned finished, exit status <Sys\$ReturnCode> ====="
    fi
  done
  echo "Echo ===== all tests finished ====="
  echo "Spool"
  echo "Back"
  echo "Echo Results saved in <TLTest\$Dir>.Results"
} > "$obey"

# BuildInfo: what was built, and how.
{
  echo "TeX Live for RISC OS: Milestone 1 toolchain test kit"
  echo "Commit:   $commit"
  echo "Built:    $(jq -r .generated "$results")"
  echo "Compiler: $(jq -r .compiler.gcc "$results")"
  echo
  echo "Variants (directories in this kit):"
  jq -r '.variants[] | "  \(.name): \(.description)\n    flags: \(if .flags == "" then "(none)" else .flags end)"' "$results"
  echo
  echo "Builds:"
  jq -r '.builds[] | "  \(.variant)/\(.program) [\(.kind)]: \(.status)"' "$results"
  echo
  echo "C++ feature probes (compile only, soft variant):"
  jq -r '.probes[] | "  \(.name): \(if .compiled then "supported (-std=\(.std_flag_used))" else "not supported" end)"' "$results"
} > "$kit/BuildInfo,fff"

cat > "$kit/!ReadMe,fff" <<EOF
TeX Live for RISC OS: Milestone 1 toolchain test kit
Commit $short

This kit checks that programs built by the project's GCCSDK cross compiler
run correctly on RISC OS. It is not a TeX installation.

1. Make sure SharedUnixLibrary 1.13 or later is installed (PackMan has it).
2. Run RunAll. It runs every test program and saves the output in a file
   called Results in this directory. It takes under a minute.
3. If RunAll stops with an error, note the error message, then close the
   Results file: press F12 for a command line, type Spool and press Return.
4. Report the Results file, and any error, on the needs-hardware-test issue
   in the GitHub repository, as described in docs/testing.md.

The directories hold the same programs built in different ways; BuildInfo
describes each one.
EOF

# Reproducible timestamps: use the commit time when git can tell us.
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH=$(git -c safe.directory='*' -C "$root" log -1 --format=%ct 2>/dev/null || date +%s)
  export SOURCE_DATE_EPOCH
fi

python3 "$root/riscos/packaging/rozip.py" create "$zip" "$kit"

# Verify the archive: every file must be listed with the filetype its suffix
# named, and an independent tool (zipinfo) must see the Acorn extra fields.
expected=$(cd "$out/kit" && find TLTest -type f | LC_ALL=C sort | sed -E 's#^(.*),([0-9a-f]{3})$#\2 \1#')
actual=$(python3 "$root/riscos/packaging/rozip.py" list "$zip" | grep -v '^dir ' | LC_ALL=C sort -k2)
expected_sorted=$(LC_ALL=C sort -k2 <<< "$expected")
if [ "$expected_sorted" != "$actual" ]; then
  echo "error: archive contents do not match the kit tree" >&2
  diff <(echo "$expected_sorted") <(echo "$actual") >&2 || true
  exit 1
fi
files=$(wc -l <<< "$expected")
unzip -tq "$zip"
if command -v zipinfo > /dev/null; then
  acorn=$(zipinfo -v "$zip" | grep -c 'ID 0x4341' || true)
  # zipinfo reports each extra field twice (local and central headers) or once,
  # depending on version; it must see at least one per file.
  if [ "$acorn" -lt "$files" ]; then
    echo "error: zipinfo found $acorn Acorn extra fields for $files files" >&2
    exit 1
  fi
  echo "zipinfo sees Acorn filetype fields on all $files files"
fi
echo "Test kit: $zip ($files files)"
