#!/usr/bin/env bash
# Check that build outputs are correctly targeted RISC OS executables.
#
# Usage:
#   scripts/check-binaries.sh <out-dir>        check everything a build recorded
#   scripts/check-binaries.sh --elf FILE...    check ELF files only
#   scripts/check-binaries.sh --aif FILE...    check AIF files only
#
# ELF checks (compiler output, before conversion): 32-bit, little-endian, ARM,
# an executable, statically linked, and built by GCCSDK's compiler.
# AIF checks (after elf2aif): the ,ff8 filetype suffix and the header checks
# in scripts/lib/aifcheck.py.
#
# With <out-dir>, every successful build listed in <out-dir>/results.json must
# have both its ELF and its AIF file, and every file present is checked.
# Prints one PASS or FAIL line per check. Exits 1 if any check failed.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
readelf=${READELF:-readelf}
failed=0

pass() { echo "PASS $1: $2"; }
fail() { echo "FAIL $1: $2"; failed=$((failed + 1)); }

expect() {
  # expect <file> <description> <command...>: PASS if the command succeeds.
  local file=$1 what=$2
  shift 2
  if "$@" > /dev/null 2>&1; then pass "$file" "$what"; else fail "$file" "$what"; fi
}

check_elf() {
  local f=$1 header segments sections comment
  if ! header=$(LC_ALL=C "$readelf" -h "$f" 2>&1); then
    fail "$f" "readable as an ELF file"
    return
  fi
  pass "$f" "readable as an ELF file"
  expect "$f" "ELF32" grep -qE 'Class:[[:space:]]+ELF32$' <<< "$header"
  expect "$f" "little-endian" grep -qE "Data:[[:space:]]+2's complement, little endian" <<< "$header"
  expect "$f" "machine is ARM" grep -qE 'Machine:[[:space:]]+ARM$' <<< "$header"
  expect "$f" "OS/ABI is ARM (elf2aif requires it)" grep -qE 'OS/ABI:[[:space:]]+ARM$' <<< "$header"
  expect "$f" "executable (not an object or shared library)" grep -qE 'Type:[[:space:]]+EXEC' <<< "$header"

  segments=$(LC_ALL=C "$readelf" -lW "$f" 2>&1 || true)
  sections=$(LC_ALL=C "$readelf" -SW "$f" 2>&1 || true)
  if grep -q 'INTERP' <<< "$segments"; then
    fail "$f" "statically linked (no program interpreter)"
  else
    pass "$f" "statically linked (no program interpreter)"
  fi
  if grep -qE '[[:space:]]\.dynamic[[:space:]]' <<< "$sections"; then
    fail "$f" "statically linked (no .dynamic section)"
  else
    pass "$f" "statically linked (no .dynamic section)"
  fi

  comment=$(LC_ALL=C "$readelf" -p .comment "$f" 2>/dev/null || true)
  expect "$f" "built by GCCSDK GCC (.comment)" grep -q 'GCCSDK GCC' <<< "$comment"
}

check_aif() {
  local f=$1
  case $f in
    *,ff8) pass "$f" "has the ,ff8 (Absolute) filetype suffix" ;;
    *) fail "$f" "has the ,ff8 (Absolute) filetype suffix" ;;
  esac
  local report n
  if report=$(python3 "$root/scripts/lib/aifcheck.py" "$f"); then
    echo "$report"
  else
    echo "$report"
    n=$(grep -c '^FAIL' <<< "$report" || true)
    [ "${n:-0}" -gt 0 ] || n=1
    failed=$((failed + n))
  fi
}

summary() {
  echo
  if [ "$failed" -gt 0 ]; then
    echo "check-binaries: $failed check(s) failed"
    exit 1
  fi
  echo "check-binaries: all checks passed"
  exit 0
}

case ${1:-} in
  --elf)
    shift
    for f in "$@"; do check_elf "$f"; done
    summary
    ;;
  --aif)
    shift
    for f in "$@"; do check_aif "$f"; done
    summary
    ;;
  "" | -h | --help)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac

out=$1
results="$out/results.json"
if [ ! -f "$results" ]; then
  echo "error: $results not found; run scripts/build-toolchain-tests.sh first" >&2
  exit 2
fi

checked=0
while IFS=$'\t' read -r program variant; do
  elf="$out/elf/$variant/$program"
  aif="$out/aif/$variant/$program,ff8"
  if [ -f "$elf" ]; then check_elf "$elf"; else fail "$elf" "ELF output exists"; fi
  if [ -f "$aif" ]; then check_aif "$aif"; else fail "$aif" "AIF output exists"; fi
  checked=$((checked + 1))
done < <(jq -r '.builds[] | select(.status == "ok") | [.program, .variant] | @tsv' "$results")

if [ "$checked" -eq 0 ]; then
  fail "$results" "at least one successful build to check"
fi
echo
echo "check-binaries: checked $checked program(s)"
summary
