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

# Include the SharedUnixLibrary module from the toolchain, so the programs can
# start even though the emulated system does not provide it. UnixLib's build
# installs the module as a program called "sul" (arm-unknown-riscos-sul in the
# cross toolchain's bin directory); take the shortest path that contains the
# module's title and is not an ELF file.
sul=
while IFS= read -r candidate; do
  if grep -aq 'SharedUnixLibrary' "$candidate" && ! head -c 4 "$candidate" | grep -aq 'ELF'; then
    sul=$candidate
    break
  fi
done < <(find "${GCCSDK_PREFIX:-/opt/riscos-gccsdk}" -type f \( -name sul -o -name '*-sul' -o -iname 'SharedULib,ffa' -o -iname 'SharedULib' \) 2>/dev/null | awk '{ print length, $0 }' | sort -n | cut -d' ' -f2-)
if [ -n "$sul" ]; then
  echo "Including SharedUnixLibrary module from $sul"
  cp "$sul" "$work/stage/SharedULib,ffa"
else
  echo "No SharedUnixLibrary module found in the toolchain; relying on the service"
  echo "Files under ${GCCSDK_PREFIX:-/opt/riscos-gccsdk} with names like the module's:"
  find "${GCCSDK_PREFIX:-/opt/riscos-gccsdk}" \( -iname '*sul*' -o -iname '*sharedul*' \) 2>/dev/null | head -20 || true
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
  # The service stops at the first failure, and it has no VFPSupport module,
  # so run everything soft-float first.
  for variant in soft vfp a15 a15noua; do
    for program in hello float cxx11 unaligned; do
      if [ -f "$kit/$variant/$program,ff8" ]; then
        echo "      - Echo ===== $variant $program ====="
        echo "      - Run $variant.$program"
      fi
    done
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
