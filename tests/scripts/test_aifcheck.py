"""Unit tests for scripts/lib/aifcheck.py, using synthetic AIF headers built
the way GCCSDK's elf2aif builds them. The CI build also checks real elf2aif
output and damaged copies of it (tests/scripts/test-check-binaries.sh).

Run with: python3 -m unittest discover -s tests/scripts -p 'test_*.py'
"""

import os
import struct
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts", "lib"))

import aifcheck  # noqa: E402

ENTRY_OFFSET = 0x100
RO_SIZE = 0x1000
RW_SIZE = 0x200


def make_aif(**overrides):
    words = [0] * 32
    words[0] = aifcheck.NOP
    words[1] = aifcheck.NOP
    words[2] = 0xEB00000C  # BL to the zero-init code at 0x40
    words[3] = 0xEB000000 | ((ENTRY_OFFSET - (0x0C + 8)) >> 2)
    words[4] = aifcheck.SWI_OS_EXIT
    words[5] = RO_SIZE
    words[6] = RW_SIZE
    words[10] = 0x8000
    words[12] = 32
    for index, value in overrides.items():
        words[int(index[1:], 16) // 4] = value
    header = struct.pack("<32I", *words)
    return header + b"\x00" * (RO_SIZE + RW_SIZE - len(header))


def failures(data):
    return [what for ok, what in aifcheck.check_aif(data) if not ok]


class AifCheckTests(unittest.TestCase):
    def test_well_formed_image_passes(self):
        self.assertEqual(failures(make_aif()), [])

    def test_bl_target(self):
        self.assertEqual(aifcheck.bl_target(0xEB00000C, 0x08), 0x40)
        self.assertEqual(aifcheck.bl_target(0xEBFFFFFE, 0x10), 0x10)

    def test_missing_exit_swi_fails(self):
        self.assertTrue(failures(make_aif(w10=aifcheck.NOP)))

    def test_26_bit_image_fails(self):
        self.assertTrue(failures(make_aif(w30=26)))
        self.assertTrue(failures(make_aif(w30=0)))

    def test_wrong_image_base_fails(self):
        self.assertTrue(failures(make_aif(w28=0x10000)))

    def test_entry_must_be_a_branch_into_the_image(self):
        self.assertTrue(failures(make_aif(w0C=aifcheck.NOP)))
        self.assertTrue(failures(make_aif(w0C=0xEB000000 | (RO_SIZE >> 2))))

    def test_compressed_image_fails(self):
        self.assertTrue(failures(make_aif(w00=0xEB000010)))

    def test_sizes_larger_than_file_fail(self):
        self.assertTrue(failures(make_aif(w14=RO_SIZE * 4)))

    def test_short_file_fails(self):
        self.assertTrue(failures(make_aif()[:64]))


if __name__ == "__main__":
    unittest.main()
