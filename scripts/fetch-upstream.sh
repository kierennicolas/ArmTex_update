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
#   support-files    packages from the TeX Live image (the TL2026 ISO) named
#                    by .texlive.support_files: the package database
#                    (tlpkg/texlive.tlpdb, checked against its SHA-256 pin
#                    and its release year against .texlive.release), then
#                    each package named and every package it depends on, as
#                    <dest-dir>/archive/<package>.tar.xz, checked against the
#                    size and SHA-512 the database gives. Name a scheme
#                    (scheme-basic) to get a whole installation's packages.
#
#                    Nothing is fetched when <dest-dir> already holds
#                    everything asked for. Otherwise, by default, only the
#                    parts needed are read from a mirror with HTTP range
#                    requests (SUPPORT_ISO_MODE=ranged). With
#                    SUPPORT_ISO_MODE=full, or when no mirror serves ranges,
#                    the whole image (6.3 GB) is downloaded into
#                    $SUPPORT_ISO_DIR (default <dest-dir>/.iso) and checked
#                    against its SHA-256 and SHA-512 pins; it is deleted
#                    afterwards unless KEEP_ISO=1. While a pin is empty, a
#                    full run prints the values found and fails at the end,
#                    so that a new image can be pinned from one run.
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
  local sf=.texlive.support_files file release tlpdb_pin iso_sha256 iso_sha512 iso_size
  file=$(jq -r "$sf.file // empty" "$manifest")
  if [ -z "$file" ]; then
    echo "error: upstream/manifest.json pins no support-file image" >&2
    exit 1
  fi
  release=$(jq -r '.texlive.release' "$manifest")
  tlpdb_pin=$(jq -r "$sf.tlpdb_sha256 // empty" "$manifest")
  iso_sha256=$(jq -r "$sf.sha256 // empty" "$manifest")
  iso_sha512=$(jq -r "$sf.sha512 // empty" "$manifest")
  iso_size=$(jq -r "$sf.size // empty" "$manifest")
  local tl="$root/scripts/lib/tlpdb.py" db="$dest/tlpkg/texlive.tlpdb" unpinned=0

  # Everything already here (from a cache, say)? Then the image is not needed.
  local wanted=()
  if [ -n "$tlpdb_pin" ] && [ -f "$db" ] && [ "$(sha256sum "$db" | cut -d' ' -f1)" = "$tlpdb_pin" ]; then
    resolve_packages "$@"
    if [ ${#wanted[@]} -eq 0 ] || python3 "$tl" check "$db" "$dest/archive" "${wanted[@]}" > /dev/null; then
      echo "$input: $dest already holds the pinned database and all ${#wanted[@]} packages asked for"
      report_database "$db" "$release"
      return 0
    fi
  fi

  local isodir=${SUPPORT_ISO_DIR:-$dest/.iso}
  local iso="$isodir/$file" have_size have_sha256 have_sha512 url
  mkdir -p "$isodir" "$dest/tlpkg"

  # Read in part: only the database and the packages asked for are fetched,
  # with HTTP range requests, from the first mirror that serves the image at
  # its pinned size. Every byte used is still checked: the database against
  # its SHA-256 pin and each package against the database's SHA-512. The
  # whole-image checksums cannot be computed without the whole image, so
  # they are left to a full run (SUPPORT_ISO_MODE=full) and to
  # verify-iso-signature.sh, which ties the SHA-512 pin to TeX Live's key.
  if [ "${SUPPORT_ISO_MODE:-ranged}" = ranged ] && [ -n "$iso_size" ] && [ -n "$tlpdb_pin" ]; then
    local image=
    while IFS= read -r url; do
      have_size=$(python3 "$root/scripts/lib/iso9660.py" size "$url" 2> "$isodir/size-error.txt") || {
        echo "$input: $url cannot be read in part: $(tail -n 1 "$isodir/size-error.txt")"
        continue
      }
      if [ "$have_size" != "$iso_size" ]; then
        echo "$input: $url is $have_size bytes, not the pinned $iso_size; trying the next mirror"
        continue
      fi
      image=$url
      break
    done < <(jq -r "$sf.urls[]" "$manifest")
    rm -f "$isodir/size-error.txt"
    if [ -n "$image" ]; then
      echo "$input: reading $file in part from $image ($have_size bytes, as pinned)"
      python3 "$root/scripts/lib/iso9660.py" extract "$image" tlpkg/texlive.tlpdb "$db"
      local have_tlpdb
      have_tlpdb=$(sha256sum "$db" | cut -d' ' -f1)
      echo "$input: tlpkg/texlive.tlpdb: SHA-256 $have_tlpdb"
      check_pin "database SHA-256" "$tlpdb_pin" "$have_tlpdb"
      report_database "$db" "$release"
      resolve_packages "$@"
      if [ ${#wanted[@]} -gt 0 ]; then
        echo "$input: taking ${#wanted[@]} packages out of the image"
        python3 "$tl" extract "$db" "$image" "$dest/archive" "${wanted[@]}"
      fi
      return 0
    fi
    echo "$input: no mirror can be read in part; downloading the whole image"
  fi

  if [ ! -f "$iso" ]; then
    local fetched=0
    while IFS= read -r url; do
      echo "$input: downloading $url"
      if python3 "$tl" download "$url" "$iso"; then
        fetched=1
        break
      fi
    done < <(jq -r "$sf.urls[]" "$manifest")
    if [ "$fetched" != 1 ]; then
      echo "error: no mirror in .texlive.support_files.urls supplied $file" >&2
      exit 1
    fi
  fi
  {
    read -r _ have_size
    read -r _ have_sha256
    read -r _ have_sha512
  } < <(python3 "$tl" digests "$iso")
  echo "$input: $file: $have_size bytes, SHA-256 $have_sha256"
  echo "$input: $file: SHA-512 $have_sha512"
  check_pin "image size" "$iso_size" "$have_size"
  check_pin "image SHA-256" "$iso_sha256" "$have_sha256"
  check_pin "image SHA-512" "$iso_sha512" "$have_sha512"

  python3 "$root/scripts/lib/iso9660.py" extract "$iso" tlpkg/texlive.tlpdb "$db"
  local have_tlpdb
  have_tlpdb=$(sha256sum "$db" | cut -d' ' -f1)
  echo "$input: tlpkg/texlive.tlpdb: SHA-256 $have_tlpdb"
  check_pin "database SHA-256" "$tlpdb_pin" "$have_tlpdb"
  report_database "$db" "$release"

  resolve_packages "$@"
  local status=0
  if [ ${#wanted[@]} -gt 0 ]; then
    echo "$input: taking ${#wanted[@]} packages out of the image"
    python3 "$tl" extract "$db" "$iso" "$dest/archive" "${wanted[@]}" || status=$?
  fi
  if [ "${KEEP_ISO:-0}" != 1 ]; then
    rm -f "$iso"
  fi
  if [ "$unpinned" -ne 0 ]; then
    echo "error: $unpinned pin(s) in .texlive.support_files are empty; pin the values above once the image's signature is checked" >&2
    exit 1
  fi
  return "$status"
}

# resolve_packages <package>...: set the caller's "wanted" to the packages
# named and everything they depend on, from the database in $db.
resolve_packages() {
  local list
  wanted=()
  [ $# -gt 0 ] || return 0
  list=$(python3 "$root/scripts/lib/tlpdb.py" resolve "$db" "$@")
  mapfile -t wanted <<< "$list"
}

# check_pin <what> <pinned value> <value found>: fail on a mismatch; count an
# empty pin, so the caller can fail after reporting everything.
check_pin() {
  if [ -z "$2" ]; then
    echo "$input: $1 is not pinned yet; found $3"
    unpinned=$((unpinned + 1))
  elif [ "$2" != "$3" ]; then
    echo "error: $1 is $3, but the manifest pins $2" >&2
    exit 1
  fi
}

# report_database <tlpdb> <release>: print the database's settings and fail
# unless it is for the pinned release year.
report_database() {
  local info got line
  info=$(python3 "$root/scripts/lib/tlpdb.py" info "$1")
  while IFS= read -r line; do echo "$input: database $line"; done <<< "$info"
  got=$(awk '$1 == "release" { print $2 }' <<< "$info")
  if [ "$got" != "$2" ]; then
    echo "error: the database is for TeX Live $got, but the manifest pins release $2" >&2
    exit 1
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
