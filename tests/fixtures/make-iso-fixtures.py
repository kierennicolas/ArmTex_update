#!/usr/bin/env python3
"""Write the small ISO 9660 images that tests/scripts/test_iso9660.py reads.

The images are made with pycdlib, an ISO library written independently of
scripts/lib/iso9660.py, so the tests check the reader against another
implementation's output rather than against itself. pycdlib is not needed to
run the tests; only to remake the images:

    pip install pycdlib==1.14.0
    python3 tests/fixtures/make-iso-fixtures.py tests/fixtures

Each image is stored xz-compressed (they are mostly zeros). Each holds the
same files, laid out like the TeX Live image:

    tlpkg/texlive.tlpdb
    archive/plain.tar.xz
    archive/<a name longer than Joliet's 64 characters>.tar.xz  (Rock Ridge only)
    big.bin   (several sectors, to check reads across sector boundaries)

and differ in how names are recorded: Rock Ridge with Joliet (as the TeX Live
image is expected to be), Joliet only, and plain ISO 9660 level 1.
"""

import io
import lzma
import os
import re
import sys

import pycdlib

LONG = "a-package-name-long-enough-to-need-rock-ridge-continuation-" + "x" * 150
FILES = {
    "tlpkg/texlive.tlpdb": b"name 00texlive.config\ndepend release/2026\n",
    "archive/plain.tar.xz": b"plain container\n",
    f"archive/{LONG}.tar.xz": b"long-named container\n",
    "big.bin": bytes(range(256)) * 40,  # 10240 bytes: five sectors
}


def iso_name(path, index):
    """A level-1 name (8.3, upper case) for a path component."""
    stem, _, ext = path.partition(".")
    stem = re.sub(r"[^A-Z0-9]", "_", stem[:6].upper())
    ext = re.sub(r"[^A-Z0-9]", "_", ext[:3].upper()) or "X"
    return f"{stem}{index}.{ext};1"


def build(kind):
    iso = pycdlib.PyCdlib()
    options = {"interchange_level": 1}
    if kind in ("rockridge", "joliet"):
        options["joliet"] = 3
    if kind == "rockridge":
        options["rock_ridge"] = "1.09"
    iso.new(**options)
    dirs = {}
    for index, (path, data) in enumerate(sorted(FILES.items())):
        parts = path.split("/")
        iso_path = ""
        joliet_path = ""
        for depth, part in enumerate(parts[:-1]):
            iso_dir = part.upper()[:8]
            iso_path += "/" + iso_dir
            joliet_path += "/" + part
            if iso_path not in dirs:
                kwargs = {"iso_path": iso_path}
                if kind == "rockridge":
                    kwargs["rr_name"] = part
                if kind in ("rockridge", "joliet"):
                    kwargs["joliet_path"] = joliet_path
                iso.add_directory(**kwargs)
                dirs[iso_path] = True
        name = parts[-1]
        kwargs = {"iso_path": f"{iso_path}/{iso_name(name, index)}"}
        if kind == "rockridge":
            kwargs["rr_name"] = name
        if kind in ("rockridge", "joliet") and len(name) <= 64:
            kwargs["joliet_path"] = f"{joliet_path}/{name}"
        iso.add_fp(io.BytesIO(data), len(data), **kwargs)
    out = io.BytesIO()
    iso.write_fp(out)
    iso.close()
    return out.getvalue()


def main(argv):
    dest = argv[1] if len(argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    for kind in ("rockridge", "joliet", "plain"):
        data = build(kind)
        path = os.path.join(dest, f"{kind}.iso.xz")
        with open(path, "wb") as handle:
            handle.write(lzma.compress(data, preset=9))
        print(f"{path}: {len(data)} bytes uncompressed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
