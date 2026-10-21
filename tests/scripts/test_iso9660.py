"""Unit tests for scripts/lib/iso9660.py, against small images made by an
independent ISO library (see tests/fixtures/make-iso-fixtures.py).

Run with: python3 -m unittest discover -s tests/scripts -p 'test_*.py'
"""

import io
import lzma
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts", "lib"))
FIXTURES = os.path.join(ROOT, "tests", "fixtures")

import iso9660  # noqa: E402

LONG = "a-package-name-long-enough-to-need-rock-ridge-continuation-" + "x" * 150 + ".tar.xz"
TLPDB = b"name 00texlive.config\ndepend release/2026\n"
BIG = bytes(range(256)) * 40


def image(kind):
    with open(os.path.join(FIXTURES, f"{kind}.iso.xz"), "rb") as handle:
        return iso9660.Image(io.BytesIO(lzma.decompress(handle.read())))


def read(img, path):
    out = io.BytesIO()
    size = img.copy(path, out)
    assert size == len(out.getvalue())
    return out.getvalue()


class RockRidgeTest(unittest.TestCase):
    def setUp(self):
        self.img = image("rockridge")

    def test_mode(self):
        self.assertEqual(self.img.mode, "rockridge")

    def test_names(self):
        self.assertEqual(set(self.img.list("/")), {"archive", "big.bin", "tlpkg"})
        self.assertEqual(set(self.img.list("archive")), {"plain.tar.xz", LONG})

    def test_contents(self):
        self.assertEqual(read(self.img, "tlpkg/texlive.tlpdb"), TLPDB)
        self.assertEqual(read(self.img, "archive/plain.tar.xz"), b"plain container\n")
        self.assertEqual(read(self.img, "big.bin"), BIG)

    def test_long_name(self):
        # The name does not fit in the directory record, so pycdlib puts the
        # rest of the Rock Ridge entries in a continuation area (CE).
        self.assertEqual(read(self.img, f"archive/{LONG}"), b"long-named container\n")

    def test_missing(self):
        with self.assertRaises(iso9660.IsoError):
            self.img.lookup("archive/no-such.tar.xz")
        with self.assertRaises(iso9660.IsoError):
            self.img.lookup("big.bin/inside")

    def test_directory_is_not_a_file(self):
        with self.assertRaises(iso9660.IsoError):
            self.img.copy("tlpkg", io.BytesIO())


class JolietTest(unittest.TestCase):
    def setUp(self):
        self.img = image("joliet")

    def test_mode_and_names(self):
        self.assertEqual(self.img.mode, "joliet")
        self.assertEqual(set(self.img.list("/")), {"archive", "big.bin", "tlpkg"})
        self.assertEqual(read(self.img, "tlpkg/texlive.tlpdb"), TLPDB)
        self.assertEqual(read(self.img, "big.bin"), BIG)


class PlainTest(unittest.TestCase):
    def test_level_one_names(self):
        img = image("plain")
        self.assertEqual(img.mode, "iso")
        self.assertIn("TLPKG", img.list("/"))
        self.assertEqual(set(img.list("tlpkg")), {"TEXLIV3.TLP"})
        self.assertEqual(read(img, "tlpkg/TEXLIV3.TLP"), TLPDB)


class NotAnImageTest(unittest.TestCase):
    def test_rejects_other_data(self):
        with self.assertRaises(iso9660.IsoError):
            iso9660.Image(io.BytesIO(b"\0" * 40000))


if __name__ == "__main__":
    unittest.main()
