#!/usr/bin/env bash
# Fetch a pinned upstream input and verify it.
#
# Usage: scripts/fetch-upstream.sh <input> <dest-dir>
#
# Inputs:
#   texlive-source   the TeX Live source tree at .texlive.source.revision,
#                    fetched with git at depth 1 and checked against the pin
#
# If <dest-dir> already holds a checkout of the right revision (from a cache,
# say), it is left alone. Exits 1 if the fetched revision differs from the pin.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$root/upstream/manifest.json"

if [ $# -ne 2 ]; then
  echo "usage: $0 <input> <dest-dir>" >&2
  exit 2
fi
input=$1
dest=$2

case $input in
  texlive-source)
    repository=$(jq -r '.texlive.source.repository' "$manifest")
    revision=$(jq -r '.texlive.source.revision' "$manifest")
    ;;
  *)
    echo "error: unknown input '$input'" >&2
    exit 2
    ;;
esac

# A checkout writes files in no particular order, so a generated file (a
# parser, an Info manual) can end up a fraction of a second older than its
# source, and make then tries to regenerate it with bison or makeinfo, which
# the build does not have. Giving every file the commit's timestamp makes
# nothing look newer than anything else. Without this, TeX Live's web2c failed
# intermittently trying to run bison on web2c-parser.y.
normalise_timestamps() {
  local stamp
  stamp=$(git -c safe.directory='*' -C "$dest" log -1 --format=%ct)
  find "$dest" -path "$dest/.git" -prune -o -exec touch -h -d "@$stamp" {} +
  echo "$input: timestamps set to $(date -u -d "@$stamp" +%Y-%m-%dT%H:%M:%SZ)"
}

if [ -d "$dest/.git" ] && [ "$(git -c safe.directory='*' -C "$dest" rev-parse HEAD 2>/dev/null)" = "$revision" ]; then
  echo "$input: $dest is already at $revision"
  normalise_timestamps
  exit 0
fi

rm -rf "$dest"
mkdir -p "$dest"
git -C "$dest" init -q
git -C "$dest" remote add origin "$repository"
# GitHub serves a commit by its hash, so the fetch is exactly the pin.
git -C "$dest" -c protocol.version=2 fetch -q --depth 1 origin "$revision"
git -C "$dest" -c advice.detachedHead=false checkout -q FETCH_HEAD

have=$(git -c safe.directory='*' -C "$dest" rev-parse HEAD)
if [ "$have" != "$revision" ]; then
  echo "error: fetched $have but the manifest pins $revision" >&2
  exit 1
fi
echo "$input: fetched $repository at $revision"
normalise_timestamps
