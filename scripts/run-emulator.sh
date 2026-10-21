#!/usr/bin/env bash
# Milestone 1 emulator evaluation: run the test kit's programs on the
# build.riscos.online service, which executes commands under RISC OS
# Pyromaniac (a reimplementation of RISC OS, not RISC OS 5.30 itself).
#
# Usage: scripts/run-emulator.sh <out-dir>
#
# Needs <out-dir>/kit/TLTest from scripts/package-testkit.sh. Downloads the
# service's client at the version and checksum pinned in upstream/manifest.json,
# uploads the kit with a .robuild.yaml that runs the programs, and writes the
# service's output to <out-dir>/emulator/output.txt.
#
# Results are Emulator-tested at most. The service stops at the first command
# that returns a non-zero status, so a failure early on hides later results.
# Exits with the service's status. With ROBUILD_DRY_RUN=1 it prepares the
# upload but neither downloads the client nor contacts the service.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$root/upstream/manifest.json"
out=$(cd "$1" && pwd)
kit="$out/kit/TLTest"
work="$out/emulator"

rm -rf "$work"
mkdir -p "$work/stage"

dry_run=${ROBUILD_DRY_RUN:-0}
url=$(jq -r '.tools.robuild_client.url' "$manifest")
sha256=$(jq -r '.tools.robuild_client.sha256' "$manifest")
client="$work/riscos-build-online"
if [ "$dry_run" != 1 ]; then
python3 - "$url" "$client" <<'EOF'
import sys, urllib.request
url, dest = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(url, timeout=60) as response, open(dest, "wb") as handle:
    handle.write(response.read())
EOF
echo "$sha256  $client" | sha256sum -c -
chmod +x "$client"
fi

cp -R "$kit/." "$work/stage/"

# Include the SharedUnixLibrary module from the toolchain if it ships one, so
# the programs can start even if the emulated system does not provide it.
sul=$(find "${GCCSDK_PREFIX:-/opt/riscos-gccsdk}" -type f \( -iname 'SharedULib,ffa' -o -iname 'SharedULib' -o -iname 'SharedUnixLibrary,ffa' \) 2>/dev/null | head -1 || true)
if [ -n "$sul" ]; then
  echo "Including SharedUnixLibrary module from $sul"
  cp "$sul" "$work/stage/SharedULib,ffa"
else
  echo "No SharedUnixLibrary module found in the toolchain; relying on the service"
fi

{
  cat <<'YAML'
%YAML 1.0
---
jobs:
  build:
    env:
      "TLTest$Var": expected
      "TLTEST_PLAIN": expected-plain
    script:
YAML
  if [ -n "$sul" ]; then
    echo '      - RMEnsure SharedUnixLibrary 1.13 RMLoad SharedULib'
  fi
  echo '      - Help SharedUnixLibrary'
  for variant in soft vfp a15; do
    for program in hello float cxx11; do
      if [ -f "$kit/$variant/$program,ff8" ]; then
        echo "      - Echo ===== $variant $program ====="
        echo "      - Run $variant.$program"
      fi
    done
  done
  for variant in soft vfp a15 a15noua; do
    if [ -f "$kit/$variant/unaligned,ff8" ]; then
      echo "      - Echo ===== $variant unaligned ====="
      echo "      - Run $variant.unaligned"
    fi
  done
  echo '      - Echo ===== all programs ran ====='
  echo '    artifacts:'
  echo '      - path: BuildInfo'
} > "$work/stage/.robuild.yaml"
cat "$work/stage/.robuild.yaml"

(cd "$work/stage" && zip -q -r "$work/input.zip" . -x '.robuild.yaml' && zip -q "$work/input.zip" .robuild.yaml)

if [ "$dry_run" = 1 ]; then
  echo "Dry run: prepared $work/input.zip; not contacting the service"
  exit 0
fi
status=0
"$client" -i "$work/input.zip" -t 300 -b "$work/output.txt" -o "$work/result" || status=$?
echo "build.riscos.online finished with status $status"
exit "$status"
