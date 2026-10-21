#!/usr/bin/env python3
"""Check that a file is a plausible 32-bit RISC OS AIF executable.

The header layout comes from the ARM Image Format (AIF) description in the
RISC OS Programmer's Reference Manual, and matches what GCCSDK's elf2aif
writes (gcc4/riscos/elf2aif/src/elf2aif.c, struct aifheader_t). Offsets are
in bytes; every field is a little-endian 32-bit word:

    0x00  BL decompress code, or NOP for an uncompressed image
    0x04  BL self-relocation code, or NOP
    0x08  BL zero-initialisation code, or NOP
    0x0C  BL image entry point
    0x10  SWI OS_Exit (0xEF000011)
    0x14  read-only area size (includes this header)
    0x18  read-write area size
    0x1C  debug area size
    0x20  zero-initialised area size
    0x24  debug type
    0x28  image base address
    0x2C  workspace size
    0x30  address mode: low byte 26 or 32 (0 means 26 in old images)
    0x34  data base address
    0x38  two reserved words
    0x40  zero-initialisation code, 16 words

Usage:
    aifcheck.py FILE...

Prints one PASS or FAIL line per check and file. Exits 1 if any check failed.
"""

import struct
import sys

HEADER_SIZE = 0x80
NOP = 0xE1A00000          # MOV R0, R0
SWI_OS_EXIT = 0xEF000011  # SWI OS_Exit
BL_ALWAYS = 0xEB          # condition AL, branch with link
APPLICATION_BASE = 0x8000


def is_bl(word):
    return (word >> 24) == BL_ALWAYS


def bl_target(word, at):
    """Byte offset a BL instruction at offset 'at' branches to."""
    imm = word & 0x00FFFFFF
    if imm & 0x00800000:
        imm -= 0x01000000
    return at + 8 + (imm << 2)


def check_aif(data):
    """Return a list of (ok, description) results for one file's bytes."""
    results = []

    def check(ok, what):
        results.append((bool(ok), what))
        return ok

    if not check(len(data) >= HEADER_SIZE,
                 "file is at least %d bytes (AIF header)" % HEADER_SIZE):
        return results

    w = struct.unpack_from("<32I", data, 0)
    (decompress, selfreloc, zeroinit, entry, exit_swi, ro_size, rw_size,
     _debug_size, zi_size, _debug_type, image_base, _workspace, amode,
     _data_base) = w[:14]

    check(decompress == NOP, "no decompression step (word 0x00 is NOP)")
    check(selfreloc == NOP or is_bl(selfreloc), "word 0x04 is NOP or BL")
    check(zeroinit == NOP or is_bl(zeroinit), "word 0x08 is NOP or BL")
    check(exit_swi == SWI_OS_EXIT, "word 0x10 is SWI OS_Exit")
    check((amode & 0xFF) == 32, "address mode is 32-bit")
    check(image_base == APPLICATION_BASE,
          "image base is &%X (application space)" % APPLICATION_BASE)
    check(ro_size >= HEADER_SIZE, "read-only size covers the header")
    check(ro_size + rw_size <= len(data),
          "read-only and read-write areas fit in the file")
    check(ro_size % 4 == 0 and rw_size % 4 == 0 and zi_size % 4 == 0,
          "area sizes are word multiples")
    if check(is_bl(entry), "word 0x0C is BL to the entry point"):
        target = bl_target(entry, 0x0C)
        check(HEADER_SIZE <= target < ro_size,
              "entry point lies in the read-only area after the header")
    if is_bl(zeroinit):
        target = bl_target(zeroinit, 0x08)
        check(target == 0x40, "zero-initialisation BL targets the header code")
    return results


def main(argv):
    if not argv:
        print("usage: aifcheck.py FILE...", file=sys.stderr)
        return 2
    failed = 0
    for path in argv:
        try:
            with open(path, "rb") as handle:
                data = handle.read()
        except OSError as exc:
            print("FAIL %s: cannot read: %s" % (path, exc))
            failed += 1
            continue
        for ok, what in check_aif(data):
            print("%s %s: %s" % ("PASS" if ok else "FAIL", path, what))
            if not ok:
                failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
