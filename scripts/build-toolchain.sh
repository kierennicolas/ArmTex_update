#!/usr/bin/env bash
# Build the GCCSDK cross toolchain at the revision pinned in upstream/manifest.json
# and pack the installed tree into a tarball.
#
# Usage: scripts/build-toolchain.sh <gccsdk-checkout> <output-dir>
#
# <gccsdk-checkout> must be a git checkout of the GCCSDK repository at the pinned
# revision. The toolchain is installed under the prefix named in the manifest
# (it contains absolute paths, so it must stay there), then packed as
# <output-dir>/gccsdk-toolchain.tar.xz together with a provenance file and the
# SHA-256 checksums of every source archive GCCSDK downloaded.
#
# Runs on an Ubuntu 24.04 host with GCCSDK's build dependencies installed (see
# .github/workflows/toolchain.yml). It does not run inside the toolchain image.

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$repo_root/upstream/manifest.json"

if [ $# -ne 2 ]; then
  echo "usage: $0 <gccsdk-checkout> <output-dir>" >&2
  exit 2
fi
src=$(cd "$1" && pwd)
out=$2
mkdir -p "$out"
out=$(cd "$out" && pwd)

want_rev=$(jq -r '.toolchain.gccsdk.revision' "$manifest")
prefix=$(jq -r '.toolchain.gccsdk.install_prefix' "$manifest")
target=$(jq -r '.toolchain.gccsdk.target' "$manifest")
checksum_file="$repo_root/$(jq -r '.toolchain.gccsdk.source_checksums' "$manifest")"
gcc_svn_pin="$repo_root/$(jq -r '.toolchain.gccsdk.gcc_svn_revision' "$manifest")"

have_rev=$(git -C "$src" rev-parse HEAD)
if [ "$have_rev" != "$want_rev" ]; then
  echo "error: GCCSDK checkout is at $have_rev but the manifest pins $want_rev" >&2
  exit 1
fi

if [ ! -w "$(dirname "$prefix")" ] && [ ! -w "$prefix" ]; then
  echo "error: install prefix $prefix is not writable; create it and give this user ownership first" >&2
  exit 1
fi
mkdir -p "$prefix"

# GCCSDK's build reads its install locations from gcc4/gccsdk-params. Writing it
# directly replaces the upstream CI's two-pass trick of running build-world once
# just to generate this file.
cat > "$src/gcc4/gccsdk-params" <<EOF
# Written by scripts/build-toolchain.sh (TeX Live for RISC OS)
export GCCSDK_INSTALL_CROSSBIN=$prefix/cross/bin
export GCCSDK_INSTALL_ENV=$prefix/env
EOF

echo "Building GCCSDK $want_rev into $prefix"
start=$(date +%s)
(
  cd "$src/gcc4"
  MAKEFLAGS="-j$(nproc)" ./build-world
)
end=$(date +%s)
echo "GCCSDK build took $(( (end - start) / 60 )) minutes"

# GCCSDK checks GCC itself out of the gcc-4_7-branch in GCC's Subversion
# archive rather than downloading a release archive. That branch is closed, but
# record and verify the revision so a change cannot slip in unnoticed.
gcc_svn="$src/gcc4/srcdir.orig/gcc-trunk"
gcc_svn_revision=
gcc_svn_url=
if [ -d "$gcc_svn/.svn" ]; then
  gcc_svn_revision=$(svn info --show-item last-changed-revision "$gcc_svn")
  gcc_svn_url=$(svn info --show-item url "$gcc_svn")
  echo "GCC source: $gcc_svn_url at revision $gcc_svn_revision"
  echo "$gcc_svn_url@$gcc_svn_revision" > "$out/gcc-svn-revision"
  if [ -f "$gcc_svn_pin" ]; then
    if [ "$(cat "$gcc_svn_pin")" != "$gcc_svn_url@$gcc_svn_revision" ]; then
      echo "error: GCC source is $gcc_svn_url@$gcc_svn_revision but $gcc_svn_pin pins $(cat "$gcc_svn_pin")" >&2
      exit 1
    fi
    echo "GCC source revision matches $gcc_svn_pin"
  else
    echo "warning: $gcc_svn_pin does not exist yet; commit $out/gcc-svn-revision there to pin the GCC source" >&2
  fi
fi

# Record and verify the checksums of everything GCCSDK downloaded.
downloads="$src/gcc4/srcdir.orig"
( cd "$downloads" && find . -maxdepth 1 -type f \( -name '*.tar.*' -o -name '*.tgz' -o -name '*.zip' \) -printf '%f\n' \
    | LC_ALL=C sort | xargs -r sha256sum ) > "$out/source-checksums.sha256"
echo "Source archives downloaded by GCCSDK:"
cat "$out/source-checksums.sha256"
if [ -f "$checksum_file" ]; then
  if ! diff -u "$checksum_file" "$out/source-checksums.sha256"; then
    echo "error: downloaded source archives differ from $checksum_file" >&2
    exit 1
  fi
  echo "Source archive checksums match $checksum_file"
else
  echo "warning: $checksum_file does not exist yet; commit $out/source-checksums.sha256 there to pin these downloads" >&2
fi

# Smoke test the installed compiler before packing it.
cross="$prefix/cross/bin"
for tool in "$target-gcc" "$target-g++" "$target-readelf"; do
  if [ ! -x "$cross/$tool" ]; then
    echo "error: expected $cross/$tool after the build" >&2
    exit 1
  fi
done
# GCCSDK's tool build installs elf2aif either plain or with the target prefix.
elf2aif=
for name in elf2aif "$target-elf2aif"; do
  if [ -x "$cross/$name" ]; then elf2aif="$cross/$name"; break; fi
done
if [ -z "$elf2aif" ]; then
  echo "error: elf2aif not found in $cross" >&2
  exit 1
fi
echo "elf2aif: $elf2aif"
"$cross/$target-gcc" --version | head -1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '#include <stdio.h>\nint main(void){puts("ok");return 0;}\n' > "$tmp/t.c"
"$cross/$target-gcc" -static -O2 -o "$tmp/t" "$tmp/t.c"
"$elf2aif" "$tmp/t" "$tmp/t,ff8"
echo "Smoke test: compiled and converted a C program"

# Provenance, then the tarball. The tarball holds the path relative to /, so it
# unpacks back to the same absolute prefix.
# shellcheck source=/dev/null
os_name=$(. /etc/os-release && echo "$PRETTY_NAME")
cat > "$out/provenance.json" <<EOF
{
  "gccsdk_revision": "$want_rev",
  "prefix": "$prefix",
  "target": "$target",
  "gcc_version_line": $(jq -Rn --arg v "$("$cross/$target-gcc" --version | head -1)" '$v'),
  "gcc_source": $(jq -Rn --arg v "${gcc_svn_url:+$gcc_svn_url@$gcc_svn_revision}" '$v'),
  "built_on": $(jq -Rn --arg v "$os_name" '$v'),
  "host_gcc": $(jq -Rn --arg v "$(gcc --version | head -1)" '$v'),
  "build_minutes": $(( (end - start) / 60 ))
}
EOF
tar --owner=0 --group=0 --numeric-owner -caf "$out/gccsdk-toolchain.tar.xz" -C / "${prefix#/}"
sha256sum "$out/gccsdk-toolchain.tar.xz" | tee "$out/gccsdk-toolchain.tar.xz.sha256"
