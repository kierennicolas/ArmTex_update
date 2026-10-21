#!/usr/bin/env bash
# Check that the pinned TeX Live image is the one TeX Live signed.
#
# Usage: scripts/verify-iso-signature.sh
#
# TeX Live publishes, next to each DVD image, a file holding the image's
# SHA-512 (<image>.sha512) and a detached signature of that file
# (<image>.sha512.asc), made with TeX Live's key. This script fetches both
# from the first mirror in .texlive.support_files.urls that has them, and
# TeX Live's public key from .texlive.support_files.signing_key.url, then
# checks that:
#
#   1. the key's primary fingerprint is the one pinned in the manifest;
#   2. the signature is good and made by that key or one of its subkeys;
#   3. the signed file names the pinned image, with the pinned SHA-512.
#
# scripts/fetch-upstream.sh checks the downloaded image against the same
# SHA-512 pin, so together they show the image is TeX Live's own. While the
# SHA-512 pin is empty, the signed value is printed for pinning instead.
# Needs gpg, so it runs on the GitHub runner, not in the toolchain image.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$root/upstream/manifest.json"
sf=.texlive.support_files
file=$(jq -r "$sf.file" "$manifest")
pin=$(jq -r "$sf.sha512 // empty" "$manifest")
key_url=$(jq -r "$sf.signing_key.url" "$manifest")
fingerprint=$(jq -r "$sf.signing_key.fingerprint" "$manifest")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"

get() { python3 "$root/scripts/lib/tlpdb.py" download "$1" "$2"; }

found=
while IFS= read -r url; do
  if get "$url.sha512" "$work/image.sha512" && get "$url.sha512.asc" "$work/image.sha512.asc"; then
    found=$url
    break
  fi
done < <(jq -r "$sf.urls[]" "$manifest")
if [ -z "$found" ]; then
  echo "FAIL: no mirror supplied $file.sha512 and its signature" >&2
  exit 1
fi
echo "Checksum file and signature from $found.sha512"
get "$key_url" "$work/texlive.asc"

# 1. The key file must hold the key with the pinned primary fingerprint.
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
gpg --batch --status-fd 3 --verify "$work/image.sha512.asc" "$work/image.sha512" \
  3> "$work/status.txt" 2> "$work/verify.txt" || status=$?
cat "$work/verify.txt"
primary=$(awk '$2 == "VALIDSIG" { print $NF }' "$work/status.txt")
if [ "$status" -ne 0 ] || [ "$primary" != "$fingerprint" ]; then
  echo "FAIL: $file.sha512 is not validly signed by $fingerprint (gpg status $status)" >&2
  exit 1
fi
echo "ok: $file.sha512 is signed by TeX Live's key"

# 3. The signed file must name this image, with the pinned SHA-512.
read -r signed name < "$work/image.sha512"
name=${name#\*}
if [ "$name" != "$file" ]; then
  echo "FAIL: the signed checksum is for '$name', not $file" >&2
  exit 1
fi
echo "Signed SHA-512 of $file: $signed"
if [ -z "$pin" ]; then
  echo "The manifest's SHA-512 pin is empty: pin the signed value above."
elif [ "$signed" != "$pin" ]; then
  echo "FAIL: the signed SHA-512 differs from the manifest's pin $pin" >&2
  exit 1
else
  echo "ok: the manifest pins the signed SHA-512"
fi
