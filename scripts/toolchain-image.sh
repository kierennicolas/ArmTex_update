#!/usr/bin/env bash
# Print the toolchain image reference for the current pins and build recipe,
# as key=value lines suitable for appending to $GITHUB_OUTPUT:
#
#   image=ghcr.io/<name>:<tag>
#   tag=<first 12 of GCCSDK revision>-<first 12 of recipe hash>
#   recipe_hash=<sha256 prefix>
#
# The recipe hash covers the manifest's toolchain section, the Dockerfile and
# the build script, so changing any of them produces a new tag and the
# toolchain workflow builds a fresh image. An existing tag is never rebuilt.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$root/upstream/manifest.json"

rev=$(jq -r '.toolchain.gccsdk.revision' "$manifest")
registry=$(jq -r '.toolchain.image.registry' "$manifest")
name=$(jq -r '.toolchain.image.name' "$manifest")

recipe_hash=$(
  {
    jq -S -c '.toolchain' "$manifest"
    cat "$root/toolchain/gccsdk/Dockerfile" "$root/scripts/build-toolchain.sh"
  } | sha256sum | cut -c1-12
)

tag="${rev:0:12}-${recipe_hash}"
echo "image=$registry/$name:$tag"
echo "tag=$tag"
echo "recipe_hash=$recipe_hash"
