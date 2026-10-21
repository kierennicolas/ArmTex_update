#!/usr/bin/env bash
# Negative and positive tests for scripts/check-binaries.sh, using real build
# output: a check that cannot fail proves nothing.
#
# Usage: tests/scripts/test-check-binaries.sh <out-dir>
#
# Takes one ELF and one AIF from <out-dir>, confirms they pass, then confirms
# that damaged copies and wrong kinds of file are rejected.

set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
check="$root/scripts/check-binaries.sh"
out=$1

aif=$(find "$out/aif" -name '*,ff8' -type f | LC_ALL=C sort | head -1)
elf=$(find "$out/elf" -type f | LC_ALL=C sort | head -1)
if [ -z "$aif" ] || [ -z "$elf" ]; then
  echo "error: no build output in $out" >&2
  exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

expect_pass() {
  if "$check" "$@" > "$work/log" 2>&1; then
    echo "ok   accepted as expected: $*"
  else
    echo "FAIL wrongly rejected: $*"
    sed 's/^/     /' "$work/log"
    failures=$((failures + 1))
  fi
}

expect_fail() {
  if "$check" "$@" > "$work/log" 2>&1; then
    echo "FAIL wrongly accepted: $*"
    sed 's/^/     /' "$work/log"
    failures=$((failures + 1))
  else
    echo "ok   rejected as expected: $*"
  fi
}

# patch <src> <dst> <offset> <32-bit little-endian value>
patch_word() {
  python3 - "$1" "$2" "$3" "$4" <<'EOF'
import struct, sys
src, dst, offset, value = sys.argv[1], sys.argv[2], int(sys.argv[3], 0), int(sys.argv[4], 0)
data = bytearray(open(src, "rb").read())
data[offset:offset + 4] = struct.pack("<I", value)
open(dst, "wb").write(data)
EOF
}

expect_pass --aif "$aif"
expect_pass --elf "$elf"

patch_word "$aif" "$work/bad-exit,ff8" 0x10 0xE1A00000
expect_fail --aif "$work/bad-exit,ff8"

patch_word "$aif" "$work/bad-26bit,ff8" 0x30 26
expect_fail --aif "$work/bad-26bit,ff8"

patch_word "$aif" "$work/bad-base,ff8" 0x28 0x10000
expect_fail --aif "$work/bad-base,ff8"

patch_word "$aif" "$work/bad-entry,ff8" 0x0C 0xE1A00000
expect_fail --aif "$work/bad-entry,ff8"

head -c 64 "$aif" > "$work/truncated,ff8"
expect_fail --aif "$work/truncated,ff8"

cp "$aif" "$work/no-suffix"
expect_fail --aif "$work/no-suffix"

expect_fail --aif "$elf"

# A host executable is ELF, but not 32-bit ARM, and not from GCCSDK.
host_elf=$(readlink -f /usr/bin/env)
if [ ! -f "$host_elf" ]; then
  echo "error: no host executable at /usr/bin/env to test with" >&2
  exit 2
fi
expect_fail --elf "$host_elf"

head -c 100 "$elf" > "$work/truncated-elf"
expect_fail --elf "$work/truncated-elf"

expect_fail --elf "$aif"

echo
if [ "$failures" -gt 0 ]; then
  echo "test-check-binaries: $failures test(s) failed"
  exit 1
fi
echo "test-check-binaries: all tests passed"
