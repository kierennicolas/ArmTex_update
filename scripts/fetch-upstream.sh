#!/usr/bin/env bash
# Fetch a pinned upstream input and verify it.
#
# Usage: scripts/fetch-upstream.sh texlive-source <dest-dir>
#        scripts/fetch-upstream.sh support-files <dest-dir> [package...]
#
# Inputs:
#   texlive-source   the TeX Live source tree at .texlive.source.revision,
#                    fetched with git at depth 1 and checked against the pin.
#                    If <dest-dir> already holds that revision (from a cache,
#                    say), it is left alone.
#   support-files    the package database (texlive.tlpdb) of the pinned
#                    snapshot named by .texlive.support_files, checked against
#                    its SHA-256 pin and its release year against
#                    .texlive.release; then each package named, as
#                    <dest-dir>/archive/<package>.tar.xz, checked against the
#                    size and SHA-512 the database gives. Packages are fetched
#                    as named, without their dependencies; scripts/lib/tlpdb.py
#                    resolve lists those.
#
# Exits 1 if anything differs from its pin.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$root/upstream/manifest.json"

if [ $# -lt 2 ]; then
  echo "usage: $0 texlive-source <dest-dir>" >&2
  echo "       $0 support-files <dest-dir> [package...]" >&2
  exit 2
fi
input=$1
dest=$2
shift 2

fetch_support_files() {
  local base path pin release have db info got_release line
  base=$(jq -r '.texlive.support_files.base_url // empty' "$manifest")
  path=$(jq -r '.texlive.support_files.tlpdb.path // empty' "$manifest")
  pin=$(jq -r '.texlive.support_files.tlpdb.sha256 // empty' "$manifest")
  release=$(jq -r '.texlive.release' "$manifest")
  if [ -z "$base" ] || [ -z "$path" ]; then
    echo "error: upstream/manifest.json pins no support-file snapshot" >&2
    exit 1
  fi
  mkdir -p "$dest/tlpkg"
  db="$dest/tlpkg/$(basename "$path")"
  if [ -f "$db" ] && [ -n "$pin" ] && [ "$(sha256sum "$db" | cut -d' ' -f1)" = "$pin" ]; then
    echo "$input: $db is already the pinned database"
  else
    python3 "$root/scripts/lib/tlpdb.py" download "$base/$path" "$db"
  fi
  have=$(sha256sum "$db" | cut -d' ' -f1)
  echo "$input: $base/$path has SHA-256 $have"
  if [ -z "$pin" ]; then
    echo "error: .texlive.support_files.tlpdb.sha256 is empty; pin the value above after checking it" >&2
    exit 1
  fi
  if [ "$have" != "$pin" ]; then
    echo "error: the database's SHA-256 is $have but the manifest pins $pin" >&2
    exit 1
  fi
  xz -dc "$db" > "$dest/tlpkg/texlive.tlpdb"
  info=$(python3 "$root/scripts/lib/tlpdb.py" info "$dest/tlpkg/texlive.tlpdb")
  while IFS= read -r line; do echo "$input: database $line"; done <<< "$info"
  got_release=$(awk '$1 == "release" { print $2 }' <<< "$info")
  if [ "$got_release" != "$release" ]; then
    echo "error: the database is for TeX Live $got_release, but the manifest pins release $release" >&2
    exit 1
  fi
  if [ $# -gt 0 ]; then
    python3 "$root/scripts/lib/tlpdb.py" fetch "$dest/tlpkg/texlive.tlpdb" "$base" "$dest/archive" "$@"
  fi
}

case $input in
  texlive-source)
    if [ $# -ne 0 ]; then
      echo "error: texlive-source takes no packages" >&2
      exit 2
    fi
    repository=$(jq -r '.texlive.source.repository' "$manifest")
    revision=$(jq -r '.texlive.source.revision' "$manifest")
    ;;
  support-files)
    fetch_support_files "$@"
    exit 0
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
