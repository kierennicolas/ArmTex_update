#!/usr/bin/env python3
"""Read a TeX Live package database (texlive.tlpdb) and take packages from
the TeX Live image according to it.

The database is a text file of records separated by blank lines. Each line of
a record is "key value"; lines starting with a space continue the file list
of the "runfiles", "docfiles", "srcfiles" or "binfiles" line above them. The
fields used here:

    name               package name
    depend             another package this one needs (repeatable); names
                       ending in ".ARCH" are per-platform binaries
    containersize      size in bytes of archive/NAME.tar.xz
    containerchecksum  SHA-512 of archive/NAME.tar.xz, in hex

The record named 00texlive.config holds the database's own settings as
"depend key/value" lines, including release/YYYY and frozen/0 or frozen/1.

Usage:
    tlpdb.py download URL DEST
        Download URL to DEST.
    tlpdb.py digests FILE
        Print the size, SHA-256 and SHA-512 of FILE, one "key value" line
        each, reading it once.
    tlpdb.py info TLPDB
        Print the release year, whether the release is frozen, and the
        repository revision, one "key value" line each.
    tlpdb.py resolve TLPDB PKG...
        Print PKG and every package it depends on, recursively, one per line,
        sorted. Platform binaries (.ARCH) are left out: they come from this
        project's own build, not from TeX Live.
    tlpdb.py size TLPDB PKG...
        Print the total size in bytes of the named packages' containers.
    tlpdb.py subset TLPDB PKG...
        Print a database holding only the named packages (and the
        00texlive.config record), as an installation's tlpkg/texlive.tlpdb.
    tlpdb.py unpack DIR TREE PKG...
        Unpack DIR/PKG.tar.xz into the tree TREE for each PKG, putting
        relocatable files (RELOC/...) under texmf-dist/. Exits 1 if a
        container is missing.
    tlpdb.py check TLPDB DIR PKG...
        Check that DIR holds PKG.tar.xz for each PKG, with the size and
        SHA-512 the database gives. A package with no container and no files
        (a scheme or collection, in some databases) needs none. Exits 1 if
        any is missing or wrong.
    tlpdb.py extract TLPDB IMAGE DIR PKG...
        Copy each PKG's container out of the ISO image IMAGE into DIR as
        PKG.tar.xz (no dependency expansion), and check its size and SHA-512.
        In the image it is archive/PKG.rREVISION.tar.xz or archive/PKG.tar.xz.
        A file already in DIR that passes the checks is kept.

Exits 1 if a package is unknown, a download fails, or a check fails.
"""

import hashlib
import os
import sys
import time
import urllib.request

import iso9660  # in this script's directory

ATTEMPTS = 3
RETRY_DELAY = 5  # seconds, multiplied by the attempt number


def parse(path):
    """Return {name: {key: [values]}} for every record in the database."""
    records = {}
    current = None
    with open(path, encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if not line.strip():
                current = None
                continue
            if line.startswith(" "):
                continue  # a file in a file list
            key, _, value = line.partition(" ")
            if key == "name":
                current = {}
                records[value] = current
            elif current is not None:
                current.setdefault(key, []).append(value)
    return records


def raw_records(path):
    """Return {name: record text} for every record, file lists included."""
    records = {}
    lines = []
    with open(path, encoding="utf-8", errors="surrogateescape") as handle:
        for raw in list(handle) + ["\n"]:
            if raw.strip():
                lines.append(raw if raw.endswith("\n") else raw + "\n")
                continue
            if lines:
                key, _, value = lines[0].rstrip("\n").partition(" ")
                if key == "name":
                    records[value] = "".join(lines)
                lines = []
    return records


def unpack(container, tree):
    """Unpack a package container into a TeX Live tree. Paths starting with
    RELOC/ belong in texmf-dist/; the rest (tlpkg/, texmf-dist/, bin/) are
    already relative to the tree's root. Returns the number of files."""
    import tarfile

    count = 0
    with tarfile.open(container, "r:xz") as archive:
        members = []
        for member in archive.getmembers():
            name = member.name
            if name == "RELOC" or name.startswith("RELOC/"):
                member.name = "texmf-dist" + name[len("RELOC"):]
            parts = member.name.split("/")
            if member.name.startswith("/") or ".." in parts:
                raise ValueError(f"{container}: unsafe path {name}")
            if member.isfile():
                count += 1
            members.append(member)
        if hasattr(tarfile, "data_filter"):
            archive.extractall(tree, members=members, filter="data")
        else:  # Python before 3.12; the paths were checked above
            archive.extractall(tree, members=members)
    return count


def first(record, key, default=None):
    values = record.get(key)
    return values[0] if values else default


def config(records):
    """The "depend key/value" settings of 00texlive.config, as a dict."""
    settings = {}
    for item in records.get("00texlive.config", {}).get("depend", []):
        key, _, value = item.partition("/")
        settings[key] = value
    return settings


def resolve(records, names):
    """names plus their dependencies, recursively, without .ARCH packages."""
    wanted = set()
    stack = list(names)
    while stack:
        name = stack.pop()
        if name.endswith(".ARCH") or name in wanted:
            continue
        if name not in records:
            raise KeyError(name)
        wanted.add(name)
        stack.extend(records[name].get("depend", []))
    return sorted(wanted)


def download(url, dest):
    """Fetch url to dest, retrying transient failures; write atomically."""
    partial = dest + ".part"
    for attempt in range(1, ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(url, timeout=120) as response, \
                    open(partial, "wb") as handle:
                while True:
                    chunk = response.read(1 << 20)
                    if not chunk:
                        break
                    handle.write(chunk)
                final_url = response.geturl()
                content_type = response.headers.get("Content-Type", "none")
            os.replace(partial, dest)
            # Shown so that a page served in place of a file (an error page,
            # a bot check) is easy to recognise in the log.
            note = "" if final_url == url else f", redirected to {final_url}"
            print(f"downloaded {url}: {os.path.getsize(dest)} bytes, "
                  f"Content-Type {content_type}{note}", file=sys.stderr)
            return
        except OSError as error:  # URLError and HTTPError are OSErrors
            if os.path.exists(partial):
                os.remove(partial)
            status = getattr(error, "code", None)
            if attempt == ATTEMPTS or status in (403, 404, 410):
                raise
            print(f"retrying {url} after: {error}", file=sys.stderr)
            time.sleep(RETRY_DELAY * attempt)


def check_container(path, size, checksum):
    """Return None if path has the given size and SHA-512, else a reason."""
    actual_size = os.path.getsize(path)
    if actual_size != size:
        return f"size {actual_size}, expected {size}"
    digest = hashlib.sha512()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    if digest.hexdigest() != checksum.lower():
        return f"SHA-512 {digest.hexdigest()}, expected {checksum.lower()}"
    return None


def digests(path):
    """(size, SHA-256, SHA-512) of a file, read once."""
    sha256, sha512, size = hashlib.sha256(), hashlib.sha512(), 0
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 22), b""):
            sha256.update(chunk)
            sha512.update(chunk)
            size += len(chunk)
    return size, sha256.hexdigest(), sha512.hexdigest()


NO_FILES = "no files"


def expected(records, name):
    """(size, SHA-512) the database gives for a package's container, or
    (None, reason). The reason is NO_FILES for a package with no container
    and no files, which there is nothing to take."""
    record = records.get(name)
    if record is None:
        return None, "not in the database"
    size = first(record, "containersize")
    checksum = first(record, "containerchecksum")
    if size is None or checksum is None:
        if not any(key in record for key in ("runfiles", "binfiles", "docfiles", "srcfiles")):
            return None, NO_FILES
        return None, "the database gives no container size or checksum"
    return (int(size), checksum), None


def check(records, dest, names):
    """Check DIR/PKG.tar.xz for each name; return the number of failures."""
    failures = 0
    for name in names:
        want, reason = expected(records, name)
        path = os.path.join(dest, f"{name}.tar.xz")
        if want is not None:
            reason = "missing" if not os.path.exists(path) else check_container(path, *want)
        if reason is not None and reason != NO_FILES:
            print(f"FAIL {name}: {reason}")
            failures += 1
    return failures


def container_names(record, name):
    """Names the container may have in archive/: TeX Live's images and
    repositories store NAME.rREVISION.tar.xz, sometimes with NAME.tar.xz
    beside it."""
    revision = first(record, "revision")
    names = [f"{name}.tar.xz"]
    if revision:
        names.insert(0, f"{name}.r{revision}.tar.xz")
    return names


def extract(records, image, dest, names):
    """Copy each package's container out of image (an object with the list
    and copy methods of iso9660.Image) into dest as NAME.tar.xz, checking
    each one. Return the number of failures."""
    os.makedirs(dest, exist_ok=True)
    try:
        archive = set(image.list("archive"))
    except (OSError, iso9660.IsoError) as error:
        print(f"FAIL: the image has no archive directory ({error}); "
              f"its top level holds: {' '.join(sorted(image.list('/')))}")
        return len(names)
    failures = 0
    for name in names:
        want, reason = expected(records, name)
        if reason == NO_FILES:
            print(f"ok {name}: no container, no files")
            continue
        if want is None:
            print(f"FAIL {name}: {reason}")
            failures += 1
            continue
        path = os.path.join(dest, f"{name}.tar.xz")
        if os.path.exists(path) and check_container(path, *want) is None:
            print(f"ok {name}: already present, {want[0]} bytes")
            continue
        candidates = container_names(records[name], name)
        member = next((candidate for candidate in candidates if candidate in archive), None)
        if member is None:
            similar = sorted(entry for entry in archive if entry.startswith(f"{name}."))[:5]
            print(f"FAIL {name}: none of {', '.join(candidates)} is in the image's archive "
                  f"directory; names starting {name}.: {', '.join(similar) or 'none'}")
            failures += 1
            continue
        partial = path + ".part"
        try:
            with open(partial, "wb") as out:
                image.copy(f"archive/{member}", out)
        except (OSError, iso9660.IsoError) as error:
            if os.path.exists(partial):
                os.remove(partial)
            print(f"FAIL {name}: not copied from the image: {error}")
            failures += 1
            continue
        reason = check_container(partial, *want)
        if reason is not None:
            os.remove(partial)
            print(f"FAIL {name}: archive/{member}: {reason}")
            failures += 1
            continue
        os.replace(partial, path)
        print(f"ok {name}: archive/{member}, {want[0]} bytes, SHA-512 matches")
    return failures


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    command, args = argv[1], argv[2:]
    if command == "download" and len(args) == 2:
        try:
            download(args[0], args[1])
        except OSError as error:
            print(f"error: download from {args[0]} failed: {error}", file=sys.stderr)
            return 1
        return 0
    if command == "info" and len(args) == 1:
        settings = config(parse(args[0]))
        print(f"release {settings.get('release', 'unknown')}")
        print(f"frozen {settings.get('frozen', 'unknown')}")
        print(f"revision {settings.get('revision', 'unknown')}")
        return 0
    if command == "resolve" and len(args) >= 2:
        records = parse(args[0])
        try:
            names = resolve(records, args[1:])
        except KeyError as error:
            print(f"error: package {error} is not in the database", file=sys.stderr)
            return 1
        print("\n".join(names))
        return 0
    if command == "size" and len(args) >= 2:
        records = parse(args[0])
        missing = [name for name in args[1:] if name not in records]
        if missing:
            print(f"error: not in the database: {' '.join(missing)}", file=sys.stderr)
            return 1
        print(sum(int(first(records[name], "containersize", 0)) for name in args[1:]))
        return 0
    if command == "digests" and len(args) == 1:
        size, sha256, sha512 = digests(args[0])
        print(f"size {size}\nsha256 {sha256}\nsha512 {sha512}")
        return 0
    if command == "subset" and len(args) >= 2:
        raw = raw_records(args[0])
        missing = [name for name in args[1:] if name not in raw]
        if missing:
            print(f"error: not in the database: {' '.join(missing)}", file=sys.stderr)
            return 1
        names = ["00texlive.config"] if "00texlive.config" in raw else []
        names += sorted(set(args[1:]) - {"00texlive.config"})
        sys.stdout.write("\n".join(raw[name] for name in names))
        return 0
    if command == "unpack" and len(args) >= 3:
        total = unpacked = 0
        for name in args[2:]:
            container = os.path.join(args[0], f"{name}.tar.xz")
            if not os.path.exists(container):
                print(f"error: {container} not found", file=sys.stderr)
                return 1
            total += unpack(container, args[1])
            unpacked += 1
        print(f"unpacked {unpacked} packages, {total} files, into {args[1]}")
        return 0
    if command == "check" and len(args) >= 3:
        records = parse(args[0])
        return 1 if check(records, args[1], args[2:]) else 0
    if command == "extract" and len(args) >= 4:
        records = parse(args[0])
        with open(args[1], "rb") as handle:
            try:
                image = iso9660.Image(handle)
            except iso9660.IsoError as error:
                print(f"error: {args[1]}: {error}", file=sys.stderr)
                return 1
            return 1 if extract(records, image, args[2], args[3:]) else 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
