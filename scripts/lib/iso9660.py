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

Exits 1 if a path is not in the image.
"""

import struct
import sys

SECTOR = 2048
DESCRIPTORS_START = 16
JOLIET_ESCAPES = (b"%/@", b"%/C", b"%/E")


class IsoError(Exception):
    pass


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
        """{name: Entry} for a directory record."""
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
    if len(argv) == 4 and argv[1] == "ls":
        with open(argv[2], "rb") as handle:
            try:
                entries = Image(handle).list(argv[3])
            except IsoError as error:
                print(f"error: {error}", file=sys.stderr)
                return 1
        for name in sorted(entries):
            entry = entries[name]
            print(f"{'d' if entry.is_dir else '-'} {entry.size:>12} {name}")
        return 0
    if len(argv) == 5 and argv[1] == "extract":
        with open(argv[2], "rb") as handle, open(argv[4], "wb") as out:
            try:
                Image(handle).copy(argv[3], out)
            except IsoError as error:
                print(f"error: {error}", file=sys.stderr)
                return 1
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
