#!/usr/bin/env bash
# Print a Markdown summary of <out-dir>/results.json, for the GitHub Actions
# job summary and for pasting into documentation.
#
# Usage: scripts/summarise-results.sh <out-dir>

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <out-dir>" >&2
  exit 2
fi
results="$1/results.json"

echo "## Toolchain test builds"
echo
echo "Compiler: \`$(jq -r .compiler.gcc "$results")\`"
echo
echo "Commit: \`$(jq -r .commit "$results")\`"
echo
# One row per program, one column per variant.
jq -r '
  (.variants | map(.name)) as $variants
  | (["Program", "Kind"] + $variants | "| " + join(" | ") + " |"),
    (["---", "---"] + ($variants | map("---")) | "| " + join(" | ") + " |"),
    (.builds | group_by(.program)[]
      | . as $rows
      | [$rows[0].program, $rows[0].kind]
        + ($variants | map(. as $v
            | ($rows | map(select(.variant == $v)) | first) as $r
            | if $r == null then "–"
              elif $r.status == "ok" then "built"
              else $r.status end))
      | "| " + join(" | ") + " |")
' "$results"
echo
echo "Variant flags:"
echo
jq -r '.variants[] | "- **\(.name)**: \(.description) (`\(if .flags == "" then "no extra flags" else .flags end)`)"' "$results"
echo
echo "## C++ feature probes"
echo
echo "Compile-only, soft variant. \"Not supported\" means the compiler rejected the probe; the log shows why."
echo
echo "| Probe | Standard | Result | First error |"
echo "|---|---|---|---|"
jq -r '.probes[] | "| \(.name) | \(.std) | \(if .compiled then "supported (`-std=\(.std_flag_used)`)" else "not supported" end) | \(.first_error | gsub("\\|"; "\\\\|") | .[0:120]) |"' "$results"
echo
echo "Builds are **Cross-compiled** only. Nothing here has run on RISC OS yet; that is Gate 1."
