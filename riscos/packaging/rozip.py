#!/usr/bin/env python3
"""Create and list zip archives that carry RISC OS filetypes.

In this repository a RISC OS filetype is written as a ",xxx" suffix on the
filename (for example "!Run,feb" or "pdftex,ff8"). This tool turns a directory
tree that follows that convention into a zip archive whose entries have the
suffix removed and the filetype recorded in the Acorn extra field, which the
RISC OS unzip tools (Info-ZIP, SparkFS) use to restore filetypes.

The extra field follows Info-ZIP's "Acorn SparkFS" layout (header ID 0x4341,
"AC"), as described in Info-ZIP's proginfo/extrafld.txt:

    0x4341  2 bytes  header ID
    TSize   2 bytes  data size, 20
    "ARC0"  4 bytes  signature
    Load    4 bytes  load address: 0xFFFtttdd for filetype ttt, dd = top
                     byte of the 5-byte centisecond timestamp
    Exec    4 bytes  execution address: low 4 bytes of the timestamp
    Attr    4 bytes  RISC OS file attributes
    Zero    4 bytes  reserved, always zero

Archives are deterministic: entries are sorted, and every timestamp comes from
SOURCE_DATE_EPOCH (or --time), so the same tree always gives the same bytes.

Usage:
    rozip.py create OUTPUT.zip DIRECTORY   # DIRECTORY becomes the top level
    rozip.py list ARCHIVE.zip              # prints "<type> <name>" per entry
"""

import argparse
import os
import re
import struct
import sys
import time
import zipfile

ACORN_HEADER_ID = 0x4341
ACORN_SIGNATURE = b"ARC0"
ACORN_DATA_SIZE = 20
HOST_ACORN = 13  # "version made by" host system number for Acorn RISC OS
DEFAULT_ATTRIBUTES = 0x13  # owner read and write, public read
# Seconds from 1900-01-01 (the RISC OS epoch) to 1970-01-01 (the Unix epoch).
RISCOS_EPOCH_OFFSET = 2208988800

FILETYPE_SUFFIX = re.compile(r"^(?P<name>.+),(?P<type>[0-9a-fA-F]{3})$")


class RozipError(Exception):
    pass


def split_filetype(filename):
    """Return (name without suffix, filetype) for a ",xxx"-suffixed name."""
    match = FILETYPE_SUFFIX.match(filename)
    if not match:
        raise RozipError(
            "%r has no ,xxx filetype suffix; every file in a RISC OS "
            "package needs one" % filename)
    return match.group("name"), int(match.group("type"), 16)


def riscos_addresses(filetype, unix_time):
    """Return (load, exec) addresses for a typed file stamped at unix_time."""
    centiseconds = (int(unix_time) + RISCOS_EPOCH_OFFSET) * 100
    if not 0 <= centiseconds < (1 << 40):
        raise RozipError("timestamp out of RISC OS range: %r" % unix_time)
    load = 0xFFF00000 | (filetype << 8) | ((centiseconds >> 32) & 0xFF)
    exec_ = centiseconds & 0xFFFFFFFF
    return load, exec_


def acorn_extra(filetype, unix_time, attributes=DEFAULT_ATTRIBUTES):
    load, exec_ = riscos_addresses(filetype, unix_time)
    return struct.pack("<HH", ACORN_HEADER_ID, ACORN_DATA_SIZE) + \
        ACORN_SIGNATURE + struct.pack("<IIII", load, exec_, attributes, 0)


def parse_acorn_extra(extra):
    """Return the filetype recorded in an extra-field block, or None.

    Returns None for entries without an Acorn block, and for untyped files
    (load addresses that do not start with 0xFFF).
    """
    offset = 0
    while offset + 4 <= len(extra):
        header_id, size = struct.unpack_from("<HH", extra, offset)
        body = extra[offset + 4:offset + 4 + size]
        if header_id == ACORN_HEADER_ID and len(body) >= 12 \
                and body[:4] == ACORN_SIGNATURE:
            load = struct.unpack_from("<I", body, 4)[0]
            if (load >> 20) == 0xFFF:
                return (load >> 8) & 0xFFF
            return None
        offset += 4 + size
    return None


def zip_date_time(unix_time):
    t = time.gmtime(unix_time)
    # Zip timestamps cannot be earlier than 1980.
    if t.tm_year < 1980:
        return (1980, 1, 1, 0, 0, 0)
    return (t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec)


def collect(directory):
    """Yield (archive name, filesystem path or None, filetype) in sorted order.

    Directories yield a path of None and a filetype of None.
    """
    directory = os.path.normpath(directory)
    top = os.path.basename(directory)
    if "," in top:
        raise RozipError("top-level directory name must not contain ','")
    entries = [(top + "/", None, None)]
    for current, dirnames, filenames in os.walk(directory):
        dirnames.sort()
        rel = os.path.relpath(current, directory)
        prefix = top if rel == "." else top + "/" + rel.replace(os.sep, "/")
        for d in dirnames:
            if "," in d:
                raise RozipError("directory %r must not have a filetype "
                                 "suffix" % os.path.join(current, d))
            entries.append((prefix + "/" + d + "/", None, None))
        for f in sorted(filenames):
            name, filetype = split_filetype(f)
            entries.append((prefix + "/" + name, os.path.join(current, f),
                            filetype))
    entries.sort(key=lambda e: e[0])
    names = [e[0].lower() for e in entries]
    if len(names) != len(set(names)):
        raise RozipError("two entries differ only in case or filetype "
                         "suffix; RISC OS cannot hold both")
    return entries


def create(output, directory, unix_time):
    entries = collect(directory)
    with zipfile.ZipFile(output, "w") as archive:
        for name, path, filetype in entries:
            info = zipfile.ZipInfo(name, date_time=zip_date_time(unix_time))
            info.create_system = HOST_ACORN
            if path is None:
                info.external_attr = 0x10  # MS-DOS directory bit
                archive.writestr(info, b"")
                continue
            info.compress_type = zipfile.ZIP_DEFLATED
            info.extra = acorn_extra(filetype, unix_time)
            with open(path, "rb") as handle:
                archive.writestr(info, handle.read())
    return entries


def list_entries(archive_path):
    """Return a list of (filetype string, name) for every entry."""
    result = []
    with zipfile.ZipFile(archive_path) as archive:
        for info in archive.infolist():
            if info.filename.endswith("/"):
                result.append(("dir", info.filename))
                continue
            filetype = parse_acorn_extra(info.extra)
            result.append(("---" if filetype is None else "%03x" % filetype,
                           info.filename))
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    c = sub.add_parser("create", help="create an archive from a directory")
    c.add_argument("output")
    c.add_argument("directory")
    c.add_argument("--time", type=int, default=None,
                   help="Unix timestamp for every entry "
                        "(default: $SOURCE_DATE_EPOCH, else now)")
    l = sub.add_parser("list", help="list entries and their filetypes")
    l.add_argument("archive")
    args = parser.parse_args(argv)

    try:
        if args.command == "create":
            stamp = args.time
            if stamp is None:
                stamp = int(os.environ.get("SOURCE_DATE_EPOCH", time.time()))
            entries = create(args.output, args.directory, stamp)
            files = sum(1 for e in entries if e[1] is not None)
            print("%s: %d files, %d directories" %
                  (args.output, files, len(entries) - files))
        else:
            for filetype, name in list_entries(args.archive):
                print("%s %s" % (filetype, name))
    except (RozipError, OSError, zipfile.BadZipFile) as exc:
        print("rozip: error: %s" % exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
