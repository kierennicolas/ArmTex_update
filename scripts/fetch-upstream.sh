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

if [ -d "$dest/.git" ] && [ "$(git -c safe.directory='*' -C "$dest" rev-parse HEAD 2>/dev/null)" = "$revision" ]; then
  echo "$input: $dest is already at $revision"
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
