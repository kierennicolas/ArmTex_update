#!/usr/bin/env bash
# Run a RISC OS kit's programs on the build.riscos.online service, which
# executes commands under RISC OS Pyromaniac (a reimplementation of RISC OS,
# not RISC OS 5.30 itself).
#
# Usage: scripts/run-emulator.sh <kit-dir> <commands-file> <work-dir>
#
# <kit-dir> is a kit tree with ,xxx filetype suffixes (from one of the package
# scripts). <commands-file> holds RISC OS commands, one per line, run in order
# with the kit as the current directory; blank lines and lines starting with
# '#' are ignored. The service's output goes to <work-dir>/output.txt.
#
# The service client is downloaded at the version and checksum pinned in
# upstream/manifest.json. The service has no SharedUnixLibrary module, so the
# toolchain's own copy is uploaded with the kit and loaded first.
#
# Results are Emulator-tested at most. The service stops at the first command
# that returns a non-zero status or an error, so order the commands with that
# in mind. Exits with the service's status. With ROBUILD_DRY_RUN=1 it prepares
# the upload but neither downloads the client nor contacts the service.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest="$root/upstream/manifest.json"
if [ $# -ne 3 ]; then
  echo "usage: $0 <kit-dir> <commands-file> <work-dir>" >&2
  exit 2
fi
kit=$(cd "$1" && pwd)
commands=$2
mkdir -p "$3"
work=$(cd "$3" && pwd)

rm -rf "${work:?}/stage" "$work/input.zip" "$work/output.txt"
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
cp "$commands" "$work/stage/Commands,fff"

# UnixLib's build installs the SharedUnixLibrary module as a program called
# "sul" (arm-unknown-riscos-sul in the cross toolchain's bin directory); take
# the shortest path that contains the module's title and is not an ELF file.
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
fi

{
  cat <<'YAML'
%YAML 1.0
---
jobs:
  build:
    script:
YAML
  if [ -n "$sul" ]; then
    echo '      - RMEnsure SharedUnixLibrary 1.13 RMLoad SharedULib'
  fi
  echo '      - Help SharedUnixLibrary'
  while IFS= read -r line; do
    case $line in
      '' | '#'*) continue ;;
    esac
    # Quote each command as a YAML string.
    printf '      - %s\n' "$(jq -Rn --arg v "$line" '$v')"
  done < "$commands"
  echo '      - Echo ===== all commands ran ====='
  echo '    artifacts:'
  echo '      - path: Commands'
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
