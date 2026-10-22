#!/usr/bin/env python3
"""Read files from an ISO 9660 image, such as the TeX Live DVD image.

Supports what the TeX Live image needs: the primary directory tree with Rock
Ridge names (the NM entries, continued through CE areas when long), Joliet
names when there is no Rock Ridge, and plain ISO 9660 names as a last resort.
Files may span several extents. The image is only read, never mounted, so
this works in an unprivileged container.

References: ECMA-119 (ISO 9660), section 9 (directory records) and 8.4 (the
primary volume descriptor); IEEE P1281 (SUSP) and P1282 (Rock Ridge); the
Joliet specification (supplementary volume descriptor, UCS-2 names).

Usage:
    iso9660.py ls IMAGE DIR             list a directory
    iso9660.py extract IMAGE PATH DEST  copy one file out of the image
    iso9660.py size IMAGE               print the image's size in bytes

IMAGE is a file, or an http(s) URL: then only the parts needed are fetched,
with HTTP range requests (HttpRangeFile), instead of the whole image.

Exits 1 if a path is not in the image or the image cannot be read.
"""

import collections
import struct
import sys
import time
import urllib.request

SECTOR = 2048
DESCRIPTORS_START = 16
JOLIET_ESCAPES = (b"%/@", b"%/C", b"%/E")


class IsoError(Exception):
    pass


class HttpRangeFile:
    """A read-only, seekable file over HTTP range requests, so that parts of
    a large image can be read without downloading it. Small reads go through
    a cache of BLOCK-sized pieces (directories are read a sector at a time);
    reads of BLOCK or more are fetched exactly. Each request is retried."""

    BLOCK = 1 << 16
    CACHED_BLOCKS = 256
    ATTEMPTS = 3
    RETRY_DELAY = 5  # seconds, times the attempt number

    def __init__(self, url, timeout=120):
        self.url = url
        self.timeout = timeout
        self.pos = 0
        self.requests = 0
        self.fetched = 0
        self.cache = collections.OrderedDict()
        self.size = None
        _, self.size = self._get(0, 0)
        if self.size is None:
            raise IsoError(f"{url}: the server gave no size (Content-Range)")

    def _get(self, start, end):
        """Bytes start..end inclusive, and the total size from Content-Range."""
        request = urllib.request.Request(self.url, headers={"Range": f"bytes={start}-{end}"})
        for attempt in range(1, self.ATTEMPTS + 1):
            try:
                with urllib.request.urlopen(request, timeout=self.timeout) as response:
                    if response.status != 206:
                        raise IsoError(f"{self.url}: the server does not serve byte ranges "
                                       f"(status {response.status})")
                    data = response.read()
                    total = response.headers.get("Content-Range", "").rpartition("/")[2]
                self.requests += 1
                self.fetched += len(data)
                if len(data) != end - start + 1:
                    raise IsoError(f"{self.url}: asked for {end - start + 1} bytes at {start}, got {len(data)}")
                return data, int(total) if total.isdigit() else self.size
            except OSError as error:
                status = getattr(error, "code", None)
                if attempt == self.ATTEMPTS or status in (403, 404, 410, 416):
                    raise IsoError(f"{self.url}: bytes {start}-{end}: {error}") from error
                time.sleep(self.RETRY_DELAY * attempt)
        raise AssertionError("unreachable")

    def _block(self, index):
        if index in self.cache:
            self.cache.move_to_end(index)
            return self.cache[index]
        start = index * self.BLOCK
        end = min(start + self.BLOCK, self.size) - 1
        data, _ = self._get(start, end)
        self.cache[index] = data
        if len(self.cache) > self.CACHED_BLOCKS:
            self.cache.popitem(last=False)
        return data

    def seek(self, offset, whence=0):
        base = {0: 0, 1: self.pos, 2: self.size}[whence]
        self.pos = base + offset
        return self.pos

    def tell(self):
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        n = max(0, min(n, self.size - self.pos))
        if n == 0:
            return b""
        if n >= self.BLOCK:
            data, _ = self._get(self.pos, self.pos + n - 1)
        else:
            parts = []
            pos, remaining = self.pos, n
            while remaining:
                block = self._block(pos // self.BLOCK)
                piece = block[pos % self.BLOCK:pos % self.BLOCK + remaining]
                parts.append(piece)
                pos += len(piece)
                remaining -= len(piece)
            data = b"".join(parts)
        self.pos += len(data)
        return data

    def close(self):
        self.cache.clear()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def open_image(location):
    """A binary file object for an image path or http(s) URL."""
    if location.startswith(("http://", "https://")):
        return HttpRangeFile(location)
    return open(location, "rb")


class Entry:
    def __init__(self, name, is_dir, extents):
        self.name = name
        self.is_dir = is_dir
        self.extents = extents  # [(byte offset, length)], in order

    @property
    def size(self):
        return sum(length for _, length in self.extents)


class Image:
    def __init__(self, handle):
        self.handle = handle
        self._listings = {}  # (extent offset, size) -> {name: Entry}
        self.block_size = SECTOR
        primary = joliet = None
        sector = DESCRIPTORS_START
        while True:
            data = self._read(sector * SECTOR, SECTOR)
            if len(data) < SECTOR or data[1:6] != b"CD001":
                raise IsoError("not an ISO 9660 image (no volume descriptor)")
            kind = data[0]
            if kind == 255:
                break
            if kind == 1 and primary is None:
                primary = data
            elif kind == 2 and data[88:91] in JOLIET_ESCAPES and joliet is None:
                joliet = data
            sector += 1
        if primary is None:
            raise IsoError("no primary volume descriptor")
        self.block_size = struct.unpack_from("<H", primary, 128)[0]
        root = self._record(primary, 156)
        self.mode = "iso"
        self.root = root
        # Rock Ridge is announced by an SP entry in the root's "." record.
        first = self._records(root)
        if first and first[0][2] and first[0][2][:2] == b"SP":
            self.mode = "rockridge"
        elif joliet is not None:
            self.mode = "joliet"
            self.root = self._record(joliet, 156)

    def _read(self, offset, length):
        self.handle.seek(offset)
        return self.handle.read(length)

    def _record(self, data, at):
        """(identifier bytes, flags, system use bytes, extent offset, length)."""
        length = data[at]
        lba, size = struct.unpack_from("<I", data, at + 2)[0], struct.unpack_from("<I", data, at + 10)[0]
        flags = data[at + 25]
        id_len = data[at + 32]
        ident = data[at + 33:at + 33 + id_len]
        system_use = data[at + 33 + id_len + (1 - id_len % 2):at + length]
        return ident, flags, system_use, lba * self.block_size, size

    def _records(self, directory):
        """Every record in a directory's extent, in order."""
        _, _, _, offset, size = directory
        data = self._read(offset, size)
        records = []
        at = 0
        while at < len(data):
            length = data[at]
            if length == 0:
                at = (at // self.block_size + 1) * self.block_size
                continue
            records.append(self._record(data, at))
            at += length
        return records

    def _rock_ridge_name(self, system_use):
        """The Rock Ridge name in a record's system use area, or None."""
        parts = []
        found = False
        area = system_use
        while area is not None:
            pending, area = area, None
            at = 0
            while at + 4 <= len(pending):
                sig, length = pending[at:at + 2], pending[at + 2]
                if length < 4:
                    break
                body = pending[at + 4:at + length]
                if sig == b"NM":
                    found = True
                    flags = body[0]
                    if flags & 0x06:  # "." or ".." alias
                        return None
                    parts.append(body[1:])
                elif sig == b"CE":
                    block = struct.unpack_from("<I", body, 0)[0]
                    offset = struct.unpack_from("<I", body, 8)[0]
                    size = struct.unpack_from("<I", body, 16)[0]
                    area = self._read(block * self.block_size + offset, size)
                elif sig == b"ST":
                    break
                at += length
        return b"".join(parts).decode("utf-8", "surrogateescape") if found else None

    def _name(self, record):
        ident, _, system_use, _, _ = record
        if self.mode == "rockridge":
            name = self._rock_ridge_name(system_use)
            if name is not None:
                return name
        if self.mode == "joliet":
            name = ident.decode("utf-16-be", "replace")
        else:
            name = ident.decode("ascii", "replace")
        name = name.split(";", 1)[0]
        if name.endswith("."):
            name = name[:-1]
        return name

    def listdir(self, directory):
        """{name: Entry} for a directory record. Each directory is read once:
        TeX Live's archive directory is a few MB, and reading it again for
        every file taken from it costs hundreds of MB over HTTP."""
        key = directory[3:5]
        cache = self._listings
        if key in cache:
            return cache[key]
        entries = {}
        for record in self._records(directory):
            ident, flags, _, offset, size = record
            if ident in (b"\x00", b"\x01"):
                continue
            name = self._name(record)
            entry = entries.get(name)
            if entry is None:
                entries[name] = Entry(name, bool(flags & 0x02), [(offset, size)])
            else:  # a further extent of a multi-extent file
                entry.extents.append((offset, size))
        cache[key] = entries
        return entries

    def _directory_record(self, entry):
        offset, size = entry.extents[0]
        return (entry.name.encode(), 0x02, b"", offset, size)

    def lookup(self, path):
        """The Entry for a path such as "tlpkg/texlive.tlpdb"."""
        directory = self.root
        entry = None
        parts = [part for part in path.split("/") if part]
        for index, part in enumerate(parts):
            entries = self.listdir(directory)
            entry = entries.get(part)
            if entry is None and self.mode == "iso":
                entry = entries.get(part.upper())
            if entry is None:
                raise IsoError(f"{path}: not in the image")
            if index < len(parts) - 1:
                if not entry.is_dir:
                    raise IsoError(f"{path}: {part} is not a directory")
                directory = self._directory_record(entry)
        if entry is None:
            raise IsoError("empty path")
        return entry

    def list(self, path):
        entry = self.lookup(path) if path.strip("/") else None
        directory = self.root if entry is None else self._directory_record(entry)
        return self.listdir(directory)

    def copy(self, path, out):
        """Write a file's contents to the binary file object out."""
        entry = self.lookup(path)
        if entry.is_dir:
            raise IsoError(f"{path}: is a directory")
        for offset, length in entry.extents:
            self.handle.seek(offset)
            remaining = length
            while remaining:
                chunk = self.handle.read(min(remaining, 1 << 20))
                if not chunk:
                    raise IsoError(f"{path}: the image is truncated")
                out.write(chunk)
                remaining -= len(chunk)
        return entry.size


def main(argv):
    try:
        if len(argv) == 4 and argv[1] == "ls":
            with open_image(argv[2]) as handle:
                entries = Image(handle).list(argv[3])
            for name in sorted(entries):
                entry = entries[name]
                print(f"{'d' if entry.is_dir else '-'} {entry.size:>12} {name}")
            return 0
        if len(argv) == 5 and argv[1] == "extract":
            with open_image(argv[2]) as handle, open(argv[4], "wb") as out:
                Image(handle).copy(argv[3], out)
            return 0
        if len(argv) == 3 and argv[1] == "size":
            with open_image(argv[2]) as handle:
                print(handle.seek(0, 2))
            return 0
    except (IsoError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
