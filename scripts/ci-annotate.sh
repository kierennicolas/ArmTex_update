#!/usr/bin/env bash
# Copy the end of a text file into GitHub Actions annotations.
#
# Usage: scripts/ci-annotate.sh <error|warning|notice> <title> <file> [lines]
#
# Annotations appear on the workflow run's summary page and through the checks
# API, so a failure's cause can be read without downloading the full job log.
# The text is split into chunks of about 3,500 characters; GitHub shows at most
# ten annotations of each level per step, so only the last nine chunks are
# kept. Prints nothing outside GitHub Actions. Never fails the job itself.

set -uo pipefail

if [ $# -lt 3 ]; then
  echo "usage: $0 <error|warning|notice> <title> <file> [lines]" >&2
  exit 0
fi
level=$1 title=$2 file=$3 lines=${4:-150}

if [ -z "${GITHUB_ACTIONS:-}" ]; then
  exit 0
fi
if [ ! -f "$file" ]; then
  echo "::$level title=$title::$file was not created"
  exit 0
fi

tail -n "$lines" "$file" | python3 -c '
import sys

level, title = sys.argv[1], sys.argv[2]
size = 3500
chunks, current = [], ""
for line in sys.stdin.read().splitlines(keepends=True):
    line = line[:size]
    if current and len(current) + len(line) > size:
        chunks.append(current)
        current = ""
    current += line
if current:
    chunks.append(current)
chunks = chunks[-9:]


def data(text):
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def prop(text):
    return data(text).replace(":", "%3A").replace(",", "%2C")


for number, chunk in enumerate(chunks, 1):
    print("::%s title=%s (%d of %d)::%s"
          % (level, prop(title), number, len(chunks), data(chunk)))
' "$level" "$title"
exit 0
