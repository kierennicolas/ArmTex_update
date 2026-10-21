#!/usr/bin/env bash
# Native (Linux) build of the TeX Live programs that the cross build runs on the
# build machine, from the same pinned source.
#
# Usage: scripts/build-host-tools.sh <texlive-source> <prefix>
#
# Installs into <prefix>/bin:
#   tangle, ctangle, tie, otangle   needed by web2c when cross-compiling, which
#                                   cannot run the programs it builds
#   kpsewhich                       for building and checking texmf trees
#   pdftex                          for generating format files on the host
#                                   (Milestone 3)
# and writes <prefix>/host-tools.json recording the source revision and the
# configure command. Logs go to <prefix>/logs.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <texlive-source> <prefix>" >&2
  exit 2
fi
src=$(cd "$1" && pwd)
mkdir -p "$2/bin" "$2/logs"
prefix=$(cd "$2" && pwd)
work="$prefix/build"
rm -rf "$work"
mkdir -p "$work"

revision=$(git -c safe.directory='*' -C "$src" rev-parse HEAD)
jobs=$(nproc)

configure_args=(
  --disable-all-pkgs
  --enable-pdftex
  --disable-synctex
  --disable-xetex
  --without-x
  --enable-missing
  --disable-shared
  --disable-native-texlive-build
)

cd "$work"
echo "Configuring the host build of TeX Live $revision"
if ! "$src/configure" -C "${configure_args[@]}" CFLAGS=-O2 CXXFLAGS=-O2 \
    > "$prefix/logs/configure.log" 2>&1; then
  tail -n 40 "$prefix/logs/configure.log"
  exit 1
fi

# The first make configures every module and builds the libraries the
# enabled programs need.
echo "Building libraries"
if ! make -j"$jobs" > "$prefix/logs/make.log" 2>&1; then
  tail -n 60 "$prefix/logs/make.log"
  exit 1
fi

echo "Building tangle, ctangle, tie, otangle, pdftex and kpsewhich"
if ! make -j"$jobs" -C texk/web2c tangle ctangle tie otangle pdftex \
    > "$prefix/logs/web2c.log" 2>&1; then
  tail -n 60 "$prefix/logs/web2c.log"
  exit 1
fi
if ! make -j"$jobs" -C texk/kpathsea kpsewhich > "$prefix/logs/kpathsea.log" 2>&1; then
  tail -n 60 "$prefix/logs/kpathsea.log"
  exit 1
fi

for program in tangle ctangle tie otangle pdftex; do
  cp "texk/web2c/$program" "$prefix/bin/$program"
done
cp texk/kpathsea/kpsewhich "$prefix/bin/kpsewhich"

{
  printf '{\n'
  printf '  "texlive_revision": "%s",\n' "$revision"
  printf '  "configure_args": %s,\n' "$(printf '%s\n' "${configure_args[@]}" | jq -R . | jq -s -c .)"
  printf '  "host_gcc": %s,\n' "$(gcc --version | head -1 | jq -R .)"
  printf '  "programs": %s\n' "$(find "$prefix/bin" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort | jq -R . | jq -s -c .)"
  printf '}\n'
} > "$prefix/host-tools.json"

echo "Host tools installed in $prefix/bin:"
for program in "$prefix"/bin/*; do
  version=$("$program" --version 2>/dev/null | head -1) || true
  printf '  %-10s %s\n' "$(basename "$program")" "$version"
done
rm -rf "$work"
