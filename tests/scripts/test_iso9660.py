"""Unit tests for scripts/lib/iso9660.py, against small images made by an
independent ISO library (see tests/fixtures/make-iso-fixtures.py).

Run with: python3 -m unittest discover -s tests/scripts -p 'test_*.py'
"""

import contextlib
import http.server
import io
import lzma
import os
import sys
import threading
import unittest
import unittest.mock

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


class RangeHandler(http.server.BaseHTTPRequestHandler):
    """Serves DATA, honouring a single Range header, as mirrors do."""

    data = b""
    ranges = True

    def do_GET(self):  # noqa: N802 - the http.server name
        header = self.headers.get("Range")
        if not self.ranges or not header:
            self.send_response(200)
            self.send_header("Content-Length", str(len(self.data)))
            self.end_headers()
            self.wfile.write(self.data)
            return
        start, _, end = header.removeprefix("bytes=").partition("-")
        start, end = int(start), min(int(end), len(self.data) - 1)
        self.send_response(206)
        self.send_header("Content-Range", f"bytes {start}-{end}/{len(self.data)}")
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        self.wfile.write(self.data[start:end + 1])

    def log_message(self, *args):
        pass


class HttpRangeTest(unittest.TestCase):
    def serve(self, ranges=True):
        with open(os.path.join(FIXTURES, "rockridge.iso.xz"), "rb") as handle:
            data = lzma.decompress(handle.read())
        handler = type("Handler", (RangeHandler,), {"data": data, "ranges": ranges})
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        # Never through a proxy, whatever the environment says.
        self.enterContext(unittest.mock.patch.dict(os.environ, {"no_proxy": "127.0.0.1", "NO_PROXY": "127.0.0.1"}))
        return f"http://127.0.0.1:{server.server_address[1]}/image.iso", data

    def test_reads_files_through_ranges(self):
        url, data = self.serve()
        # Small blocks, so that this small image is not fetched whole.
        self.enterContext(unittest.mock.patch.object(iso9660.HttpRangeFile, "BLOCK", 2048))
        with iso9660.HttpRangeFile(url) as remote:
            self.assertEqual(remote.size, len(data))
            img = iso9660.Image(remote)
            self.assertEqual(img.mode, "rockridge")
            self.assertEqual(read(img, "tlpkg/texlive.tlpdb"), TLPDB)
            self.assertEqual(read(img, "big.bin"), BIG)
            self.assertEqual(read(img, f"archive/{LONG}"), b"long-named container\n")
            # Only the parts read were fetched, not the whole image.
            self.assertLess(remote.fetched, len(data))

    def test_large_reads_are_exact(self):
        url, data = self.serve()
        with iso9660.HttpRangeFile(url) as remote:
            remote.seek(12345)
            self.assertEqual(remote.read(iso9660.HttpRangeFile.BLOCK + 7), data[12345:12345 + iso9660.HttpRangeFile.BLOCK + 7])
            remote.seek(-10, 2)
            self.assertEqual(remote.read(), data[-10:])
            self.assertEqual(remote.read(5), b"")

    def test_server_without_ranges(self):
        url, _ = self.serve(ranges=False)
        with self.assertRaises(iso9660.IsoError):
            iso9660.HttpRangeFile(url)

    def test_command_line_with_a_url(self):
        url, data = self.serve()
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(iso9660.main(["iso9660.py", "size", url]), 0)
        self.assertEqual(out.getvalue().strip(), str(len(data)))


class NotAnImageTest(unittest.TestCase):
    def test_rejects_other_data(self):
        with self.assertRaises(iso9660.IsoError):
            iso9660.Image(io.BytesIO(b"\0" * 40000))


if __name__ == "__main__":
    unittest.main()
