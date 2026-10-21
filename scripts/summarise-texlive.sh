#!/usr/bin/env bash
# Print a Markdown summary of the TeX Live cross build's results.json.
#
# Usage: scripts/summarise-texlive.sh <out-dir>

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <out-dir>" >&2
  exit 2
fi
results="$1/results.json"

echo "## TeX Live cross build"
echo
echo "Source: \`$(jq -r .texlive_revision "$results")\`; variant \`$(jq -r .variant "$results")\`; compiler \`$(jq -r .compiler "$results")\`"
echo
echo "| Component | Kind | Result | First error |"
echo "|---|---|---|---|"
jq -r '.components[] | "| \(.name) | \(.kind) | \(.status) | \(.detail | gsub("\\|"; "\\\\|") | .[0:160]) |"' "$results"
echo
echo "Required components must build for Milestone 2; probes show what later milestones face. Nothing here has run on RISC OS."
