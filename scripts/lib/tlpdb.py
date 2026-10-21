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
    tlpdb.py check TLPDB DIR PKG...
        Check that DIR holds PKG.tar.xz for each PKG, with the size and
        SHA-512 the database gives. Exits 1 if any is missing or wrong.
    tlpdb.py extract TLPDB IMAGE DIR PKG...
        Copy archive/PKG.tar.xz out of the ISO image IMAGE into DIR for each
        PKG (no dependency expansion), and check its size and SHA-512. A file
        already in DIR that passes the checks is kept.

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


def expected(records, name):
    """(size, SHA-512) the database gives for a package, or a reason why not."""
    record = records.get(name)
    if record is None:
        return None, "not in the database"
    size = first(record, "containersize")
    checksum = first(record, "containerchecksum")
    if size is None or checksum is None:
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
        if reason is not None:
            print(f"FAIL {name}: {reason}")
            failures += 1
    return failures


def extract(records, image, dest, names):
    """Copy archive/PKG.tar.xz out of image (an object with a copy(path,
    file) method, such as iso9660.Image) into dest, checking each one.
    Return the number of failures."""
    os.makedirs(dest, exist_ok=True)
    failures = 0
    for name in names:
        want, reason = expected(records, name)
        if want is None:
            print(f"FAIL {name}: {reason}")
            failures += 1
            continue
        path = os.path.join(dest, f"{name}.tar.xz")
        if os.path.exists(path) and check_container(path, *want) is None:
            print(f"ok {name}: already present, {want[0]} bytes")
            continue
        partial = path + ".part"
        try:
            with open(partial, "wb") as out:
                image.copy(f"archive/{name}.tar.xz", out)
        except (OSError, iso9660.IsoError) as error:
            if os.path.exists(partial):
                os.remove(partial)
            print(f"FAIL {name}: not copied from the image: {error}")
            failures += 1
            continue
        reason = check_container(partial, *want)
        if reason is not None:
            os.remove(partial)
            print(f"FAIL {name}: {reason}")
            failures += 1
            continue
        os.replace(partial, path)
        print(f"ok {name}: {want[0]} bytes, SHA-512 matches")
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
