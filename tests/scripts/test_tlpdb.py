"""Unit tests for scripts/lib/tlpdb.py, using a small database written in the
format of TeX Live's texlive.tlpdb and containers served from a local
directory through file:// URLs.

Run with: python3 -m unittest discover -s tests/scripts -p 'test_*.py'
"""

import contextlib
import hashlib
import io
import os
import pathlib
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts", "lib"))

import tlpdb  # noqa: E402

tlpdb.RETRY_DELAY = 0

PLAIN = b"plain container contents\n"
LATEX = b"latex container contents, a little longer\n"


def sha512(data):
    return hashlib.sha512(data).hexdigest()


DATABASE = f"""name 00texlive.config
category TLCore
shortdesc TeX Live network archive option settings
longdesc Not a real package.
depend container_format/xz
depend frozen/0
depend minrelease/2016
depend release/2026
depend revision/78500

name scheme-tiny
category Scheme
revision 1
depend collection-tiny
depend kpathsea.ARCH

name collection-tiny
category Collection
revision 2
depend latex
depend plain

name latex
category Package
revision 70000
depend plain
depend latex.ARCH
containersize {len(LATEX)}
containerchecksum {sha512(LATEX)}
runfiles size=2
 texmf-dist/tex/latex/base/article.cls
 texmf-dist/tex/latex/base/latex.ltx

name plain
category Package
revision 57963
depend collection-tiny
containersize {len(PLAIN)}
containerchecksum {sha512(PLAIN)}
runfiles size=1
 texmf-dist/tex/plain/base/plain.tex

name nochecksum
category Package
revision 1
"""


class TlpdbTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.tmp.name)
        self.db = self.dir / "texlive.tlpdb"
        self.db.write_text(DATABASE)
        self.records = tlpdb.parse(self.db)
        self.mirror = self.dir / "mirror"
        (self.mirror / "archive").mkdir(parents=True)
        (self.mirror / "archive" / "plain.tar.xz").write_bytes(PLAIN)
        (self.mirror / "archive" / "latex.tar.xz").write_bytes(LATEX)
        self.base = self.mirror.as_uri()
        self.dest = self.dir / "dest"

    def tearDown(self):
        self.tmp.cleanup()

    def test_parse_skips_file_lists(self):
        self.assertEqual(set(self.records), {
            "00texlive.config", "scheme-tiny", "collection-tiny", "latex", "plain", "nochecksum"})
        self.assertEqual(self.records["latex"]["depend"], ["plain", "latex.ARCH"])
        self.assertNotIn(" texmf-dist/tex/latex/base/article.cls", self.records["latex"])

    def test_config(self):
        settings = tlpdb.config(self.records)
        self.assertEqual(settings["release"], "2026")
        self.assertEqual(settings["frozen"], "0")
        self.assertEqual(settings["revision"], "78500")

    def test_resolve_follows_dependencies_and_drops_binaries(self):
        self.assertEqual(tlpdb.resolve(self.records, ["scheme-tiny"]),
                         ["collection-tiny", "latex", "plain", "scheme-tiny"])

    def test_resolve_survives_cycles(self):
        # plain depends on collection-tiny, which depends on plain.
        self.assertEqual(tlpdb.resolve(self.records, ["plain"]),
                         ["collection-tiny", "latex", "plain"])

    def test_resolve_unknown_package(self):
        with self.assertRaises(KeyError):
            tlpdb.resolve(self.records, ["no-such-package"])

    def test_size_command(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = tlpdb.main(["tlpdb.py", "size", str(self.db), "plain", "latex", "collection-tiny"])
        self.assertEqual(status, 0)
        self.assertEqual(out.getvalue().strip(), str(len(PLAIN) + len(LATEX)))

    def test_fetch_checks_and_keeps_good_containers(self):
        self.assertEqual(tlpdb.fetch(self.records, self.base, str(self.dest), ["plain", "latex"]), 0)
        self.assertEqual((self.dest / "plain.tar.xz").read_bytes(), PLAIN)
        self.assertEqual((self.dest / "latex.tar.xz").read_bytes(), LATEX)
        # A second fetch finds them already present and does not download again.
        (self.mirror / "archive" / "plain.tar.xz").unlink()
        self.assertEqual(tlpdb.fetch(self.records, self.base, str(self.dest), ["plain"]), 0)

    def test_fetch_rejects_wrong_contents(self):
        (self.mirror / "archive" / "plain.tar.xz").write_bytes(PLAIN.upper())
        self.assertEqual(tlpdb.fetch(self.records, self.base, str(self.dest), ["plain"]), 1)
        self.assertFalse((self.dest / "plain.tar.xz").exists())

    def test_fetch_rejects_wrong_size(self):
        (self.mirror / "archive" / "plain.tar.xz").write_bytes(PLAIN + b"x")
        self.assertEqual(tlpdb.fetch(self.records, self.base, str(self.dest), ["plain"]), 1)
        self.assertFalse((self.dest / "plain.tar.xz").exists())

    def test_fetch_replaces_a_damaged_local_copy(self):
        self.dest.mkdir()
        (self.dest / "plain.tar.xz").write_bytes(b"damaged")
        self.assertEqual(tlpdb.fetch(self.records, self.base, str(self.dest), ["plain"]), 0)
        self.assertEqual((self.dest / "plain.tar.xz").read_bytes(), PLAIN)

    def test_fetch_reports_missing_and_unknown(self):
        (self.mirror / "archive" / "latex.tar.xz").unlink()
        failures = tlpdb.fetch(self.records, self.base, str(self.dest),
                               ["latex", "no-such-package", "nochecksum"])
        self.assertEqual(failures, 3)


if __name__ == "__main__":
    unittest.main()
