#!/usr/bin/env bash
# Check that the pinned package database was signed by TeX Live.
#
# Usage: scripts/verify-tlpdb-signature.sh <support-files-dir>
#
# <support-files-dir> is where scripts/fetch-upstream.sh support-files put the
# database (tlpkg/texlive.tlpdb, already checked against its SHA-256 pin).
# Every tlnet repository carries tlpkg/texlive.tlpdb.sha512 and a detached
# signature of it, texlive.tlpdb.sha512.asc, made with TeX Live's key. This
# script fetches both from the pinned snapshot and TeX Live's public key from
# the URL in the manifest, then checks that:
#
#   1. the key's primary fingerprint is the one pinned in the manifest;
#   2. the signature is good and made by that key or one of its subkeys;
#   3. the SHA-512 in the signed file is the database's.
#
# The SHA-256 pin is what the build relies on; this shows that the pinned
# database is TeX Live's own and not just what the snapshot host served.
# Needs gpg, so it runs on the GitHub runner, not in the toolchain image.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$root/upstream/manifest.json"
if [ $# -ne 1 ]; then
  echo "usage: $0 <support-files-dir>" >&2
  exit 2
fi
dir=$(cd "$1" && pwd)
db="$dir/tlpkg/texlive.tlpdb"
if [ ! -f "$db" ]; then
  echo "error: $db not found; run scripts/fetch-upstream.sh support-files first" >&2
  exit 1
fi

base=$(jq -r '.texlive.support_files.base_url' "$manifest")
key_url=$(jq -r '.texlive.support_files.signing_key.url' "$manifest")
fingerprint=$(jq -r '.texlive.support_files.signing_key.fingerprint' "$manifest")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"

get() { python3 "$root/scripts/lib/tlpdb.py" download "$1" "$2"; }
get "$base/tlpkg/texlive.tlpdb.sha512" "$work/texlive.tlpdb.sha512"
get "$base/tlpkg/texlive.tlpdb.sha512.asc" "$work/texlive.tlpdb.sha512.asc"
get "$key_url" "$work/texlive.asc"

# 1. Import only the key whose primary fingerprint is pinned.
gpg --batch --quiet --import-options import-show --with-colons --import "$work/texlive.asc" > "$work/import.txt" 2>&1 || true
if ! grep -q "^fpr:::::::::$fingerprint:" "$work/import.txt"; then
  echo "FAIL: $key_url does not hold the key with fingerprint $fingerprint" >&2
  grep '^fpr:' "$work/import.txt" >&2 || true
  exit 1
fi
echo "ok: TeX Live key $fingerprint imported"

# 2. The signature must be good and made by that key (VALIDSIG's last field
# is the primary key's fingerprint, whichever subkey signed).
status=0
gpg --batch --status-fd 3 --verify "$work/texlive.tlpdb.sha512.asc" "$work/texlive.tlpdb.sha512" \
  3> "$work/status.txt" 2> "$work/verify.txt" || status=$?
cat "$work/verify.txt"
primary=$(awk '$2 == "VALIDSIG" { print $NF }' "$work/status.txt")
if [ "$status" -ne 0 ] || [ "$primary" != "$fingerprint" ]; then
  echo "FAIL: texlive.tlpdb.sha512 is not validly signed by $fingerprint (gpg status $status)" >&2
  exit 1
fi
echo "ok: texlive.tlpdb.sha512 is signed by TeX Live's key"

# 3. The signed checksum must be the pinned database's.
signed=$(awk '{ print $1; exit }' "$work/texlive.tlpdb.sha512")
actual=$(sha512sum "$db" | cut -d' ' -f1)
if [ "$signed" != "$actual" ]; then
  echo "FAIL: the signed SHA-512 is $signed, but the pinned database's is $actual" >&2
  exit 1
fi
echo "ok: the pinned database matches the signed SHA-512"
