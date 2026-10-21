"""Unit tests for scripts/lib/tlpdb.py, using a small database written in the
format of TeX Live's texlive.tlpdb, containers held in a stand-in for the
image, and the small ISO image in tests/fixtures.

Run with: python3 -m unittest discover -s tests/scripts -p 'test_*.py'
"""

import contextlib
import hashlib
import io
import lzma
import os
import pathlib
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "scripts", "lib"))

import iso9660  # noqa: E402
import tlpdb  # noqa: E402

tlpdb.RETRY_DELAY = 0

# The contents of archive/plain.tar.xz in tests/fixtures/rockridge.iso.xz.
PLAIN = b"plain container\n"
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
runfiles size=1
 texmf-dist/tex/generic/nochecksum/nochecksum.tex
"""


class FakeImage:
    """Files by path, with the copy method of iso9660.Image."""

    def __init__(self, files):
        self.files = files

    def list(self, path):
        prefix = path.strip("/") + "/"
        return {key[len(prefix):]: None for key in self.files if key.startswith(prefix)}

    def copy(self, path, out):
        if path not in self.files:
            raise iso9660.IsoError(f"{path}: not in the image")
        out.write(self.files[path])
        return len(self.files[path])


class TlpdbTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.tmp.name)
        self.db = self.dir / "texlive.tlpdb"
        self.db.write_text(DATABASE)
        self.records = tlpdb.parse(self.db)
        self.image = FakeImage({
            "archive/plain.tar.xz": PLAIN,
            "archive/latex.r70000.tar.xz": LATEX,
        })
        self.dest = self.dir / "dest"

    def tearDown(self):
        self.tmp.cleanup()

    def run_main(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = tlpdb.main(["tlpdb.py", *args])
        return status, out.getvalue()

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
        status, out = self.run_main("size", str(self.db), "plain", "latex", "collection-tiny")
        self.assertEqual(status, 0)
        self.assertEqual(out.strip(), str(len(PLAIN) + len(LATEX)))

    def test_digests(self):
        size, sha256, sha512 = tlpdb.digests(self.db)
        data = DATABASE.encode()
        self.assertEqual(size, len(data))
        self.assertEqual(sha256, hashlib.sha256(data).hexdigest())
        self.assertEqual(sha512, hashlib.sha512(data).hexdigest())

    def test_extract_checks_and_keeps_good_containers(self):
        self.assertEqual(tlpdb.extract(self.records, self.image, str(self.dest), ["plain", "latex"]), 0)
        self.assertEqual((self.dest / "plain.tar.xz").read_bytes(), PLAIN)
        self.assertEqual((self.dest / "latex.tar.xz").read_bytes(), LATEX)
        self.assertEqual(tlpdb.check(self.records, str(self.dest), ["plain", "latex"]), 0)
        # A second run finds them already present and does not read the image.
        self.assertEqual(tlpdb.extract(self.records, FakeImage({}), str(self.dest), ["plain"]), 0)

    def test_extract_rejects_wrong_contents(self):
        self.image.files["archive/plain.tar.xz"] = PLAIN.upper()
        self.assertEqual(tlpdb.extract(self.records, self.image, str(self.dest), ["plain"]), 1)
        self.assertFalse((self.dest / "plain.tar.xz").exists())
        self.assertFalse((self.dest / "plain.tar.xz.part").exists())

    def test_extract_rejects_wrong_size(self):
        self.image.files["archive/plain.tar.xz"] = PLAIN + b"x"
        self.assertEqual(tlpdb.extract(self.records, self.image, str(self.dest), ["plain"]), 1)
        self.assertFalse((self.dest / "plain.tar.xz").exists())

    def test_extract_replaces_a_damaged_local_copy(self):
        self.dest.mkdir()
        (self.dest / "plain.tar.xz").write_bytes(b"damaged")
        self.assertEqual(tlpdb.check(self.records, str(self.dest), ["plain"]), 1)
        self.assertEqual(tlpdb.extract(self.records, self.image, str(self.dest), ["plain"]), 0)
        self.assertEqual((self.dest / "plain.tar.xz").read_bytes(), PLAIN)

    def test_extract_reports_missing_and_unknown(self):
        del self.image.files["archive/latex.r70000.tar.xz"]
        failures = tlpdb.extract(self.records, self.image, str(self.dest),
                                 ["latex", "no-such-package", "nochecksum"])
        self.assertEqual(failures, 3)
        self.assertEqual(tlpdb.check(self.records, str(self.dest), ["latex"]), 1)

    def test_extract_prefers_the_versioned_name(self):
        self.image.files["archive/plain.r57963.tar.xz"] = PLAIN
        self.image.files["archive/plain.tar.xz"] = b"not this one"
        self.assertEqual(tlpdb.extract(self.records, self.image, str(self.dest), ["plain"]), 0)
        self.assertEqual((self.dest / "plain.tar.xz").read_bytes(), PLAIN)

    def test_extract_without_an_archive_directory(self):
        class NoArchive(FakeImage):
            def list(self, path):
                if path == "archive":
                    raise iso9660.IsoError("archive: not in the image")
                return super().list(path)

        image = NoArchive({"tlpkg/texlive.tlpdb": b""})
        self.assertEqual(tlpdb.extract(self.records, image, str(self.dest), ["plain", "latex"]), 2)

    def test_packages_without_files_need_no_container(self):
        self.assertEqual(tlpdb.extract(self.records, self.image, str(self.dest),
                                       ["scheme-tiny", "collection-tiny", "plain"]), 0)
        self.assertEqual(tlpdb.check(self.records, str(self.dest),
                                     ["scheme-tiny", "collection-tiny", "plain"]), 0)
        self.assertFalse((self.dest / "scheme-tiny.tar.xz").exists())

    def test_subset_keeps_whole_records(self):
        status, out = self.run_main("subset", str(self.db), "plain")
        self.assertEqual(status, 0)
        self.assertTrue(out.startswith("name 00texlive.config\n"))
        self.assertIn("name plain\n", out)
        self.assertIn(" texmf-dist/tex/plain/base/plain.tex\n", out)
        self.assertNotIn("name latex\n", out)
        # Records are separated by exactly one blank line, as in TeX Live.
        self.assertIn("depend revision/78500\n\nname plain\n", out)
        subset = self.dir / "subset.tlpdb"
        subset.write_text(out)
        self.assertEqual(set(tlpdb.parse(subset)), {"00texlive.config", "plain"})

    def test_unpack_relocates(self):
        import tarfile
        container = self.dir / "pkg.tar.xz"
        payload = self.dir / "payload"
        (payload / "RELOC" / "tex" / "plain" / "base").mkdir(parents=True)
        (payload / "RELOC" / "tex" / "plain" / "base" / "plain.tex").write_text("\\dump\n")
        (payload / "tlpkg" / "tlpobj").mkdir(parents=True)
        (payload / "tlpkg" / "tlpobj" / "pkg.tlpobj").write_text("name pkg\n")
        with tarfile.open(container, "w:xz") as archive:
            archive.add(payload / "RELOC", arcname="RELOC")
            archive.add(payload / "tlpkg", arcname="tlpkg")
        tree = self.dir / "tree"
        self.assertEqual(tlpdb.unpack(str(container), str(tree)), 2)
        self.assertEqual((tree / "texmf-dist" / "tex" / "plain" / "base" / "plain.tex").read_text(), "\\dump\n")
        self.assertTrue((tree / "tlpkg" / "tlpobj" / "pkg.tlpobj").exists())
        self.assertFalse((tree / "RELOC").exists())

    def test_unpack_refuses_unsafe_paths(self):
        import tarfile
        container = self.dir / "bad.tar.xz"
        with tarfile.open(container, "w:xz") as archive:
            info = tarfile.TarInfo("RELOC/../../escape")
            info.size = 0
            archive.addfile(info, io.BytesIO(b""))
        with self.assertRaises(ValueError):
            tlpdb.unpack(str(container), str(self.dir / "tree"))

    def test_extract_from_a_real_image(self):
        with open(os.path.join(ROOT, "tests", "fixtures", "rockridge.iso.xz"), "rb") as handle:
            iso = io.BytesIO(lzma.decompress(handle.read()))
        image_path = self.dir / "image.iso"
        image_path.write_bytes(iso.getvalue())
        status, out = self.run_main("extract", str(self.db), str(image_path), str(self.dest), "plain")
        self.assertEqual(status, 0, out)
        self.assertEqual((self.dest / "plain.tar.xz").read_bytes(), PLAIN)


if __name__ == "__main__":
    unittest.main()
