"""Unit tests for riscos/packaging/rozip.py.

Run with: python3 -m unittest discover -s tests/scripts -p 'test_*.py'
"""

import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "riscos", "packaging"))

import rozip  # noqa: E402

STAMP = 1792540800  # 2026-10-20 00:00:00 UTC


class AddressTests(unittest.TestCase):
    def test_load_address_encodes_filetype(self):
        load, _ = rozip.riscos_addresses(0xFF8, STAMP)
        self.assertEqual(load >> 20, 0xFFF)
        self.assertEqual((load >> 8) & 0xFFF, 0xFF8)

    def test_timestamp_is_centiseconds_since_1900(self):
        load, exec_ = rozip.riscos_addresses(0xFFF, STAMP)
        centiseconds = ((load & 0xFF) << 32) | exec_
        self.assertEqual(centiseconds, (STAMP + 2208988800) * 100)

    def test_extra_field_layout(self):
        extra = rozip.acorn_extra(0xFEB, STAMP)
        self.assertEqual(len(extra), 24)
        header_id, size = struct.unpack_from("<HH", extra)
        self.assertEqual(header_id, 0x4341)
        self.assertEqual(size, 20)
        self.assertEqual(extra[4:8], b"ARC0")
        load, exec_, attr, zero = struct.unpack_from("<IIII", extra, 8)
        self.assertEqual((load >> 8) & 0xFFF, 0xFEB)
        self.assertEqual(attr, rozip.DEFAULT_ATTRIBUTES)
        self.assertEqual(zero, 0)
        self.assertEqual(rozip.parse_acorn_extra(extra), 0xFEB)

    def test_parse_skips_other_fields(self):
        other = struct.pack("<HH", 0x5455, 5) + b"\x01abcd"
        extra = other + rozip.acorn_extra(0xFF8, STAMP)
        self.assertEqual(rozip.parse_acorn_extra(extra), 0xFF8)
        self.assertIsNone(rozip.parse_acorn_extra(other))

    def test_split_filetype(self):
        self.assertEqual(rozip.split_filetype("!Run,feb"), ("!Run", 0xFEB))
        self.assertEqual(rozip.split_filetype("pdftex,FF8"), ("pdftex", 0xFF8))
        with self.assertRaises(rozip.RozipError):
            rozip.split_filetype("README")
        with self.assertRaises(rozip.RozipError):
            rozip.split_filetype("bad,xyz")


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.tree = os.path.join(self.tmp, "Kit")
        os.makedirs(os.path.join(self.tree, "soft"))
        self.write("RunAll,feb", b"Echo hello\n")
        self.write("soft/hello,ff8", b"\x00" * 200)
        self.write("!ReadMe,fff", b"Read me\n")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write(self, rel, data):
        with open(os.path.join(self.tree, rel), "wb") as handle:
            handle.write(data)

    def test_create_and_list(self):
        archive = os.path.join(self.tmp, "kit.zip")
        rozip.create(archive, self.tree, STAMP)
        self.assertEqual(rozip.list_entries(archive), [
            ("dir", "Kit/"),
            ("fff", "Kit/!ReadMe"),
            ("feb", "Kit/RunAll"),
            ("dir", "Kit/soft/"),
            ("ff8", "Kit/soft/hello"),
        ])
        with zipfile.ZipFile(archive) as z:
            self.assertEqual(z.read("Kit/RunAll"), b"Echo hello\n")
            self.assertIsNone(z.testzip())

    def test_archive_is_reproducible(self):
        first = os.path.join(self.tmp, "a.zip")
        second = os.path.join(self.tmp, "b.zip")
        rozip.create(first, self.tree, STAMP)
        rozip.create(second, self.tree, STAMP)
        with open(first, "rb") as a, open(second, "rb") as b:
            self.assertEqual(a.read(), b.read())

    def test_untyped_file_is_rejected(self):
        self.write("notype", b"x")
        with self.assertRaises(rozip.RozipError):
            rozip.create(os.path.join(self.tmp, "x.zip"), self.tree, STAMP)

    def test_names_differing_only_in_case_are_rejected(self):
        self.write("runall,feb", b"x")
        with self.assertRaises(rozip.RozipError):
            rozip.create(os.path.join(self.tmp, "x.zip"), self.tree, STAMP)

    @unittest.skipUnless(shutil.which("zipinfo"), "zipinfo not installed")
    def test_zipinfo_sees_acorn_fields(self):
        archive = os.path.join(self.tmp, "kit.zip")
        rozip.create(archive, self.tree, STAMP)
        report = subprocess.run(["zipinfo", "-v", archive], check=True,
                                capture_output=True, text=True).stdout
        self.assertGreaterEqual(report.count("ID 0x4341"), 3)


if __name__ == "__main__":
    unittest.main()
