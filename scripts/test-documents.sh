#!/usr/bin/env bash
# Compile the test documents on the build machine, with the host pdfTeX and
# the tree from scripts/build-texmf-tree.sh: reference PDFs and logs, and the
# list of files each document reads.
#
# Usage: scripts/test-documents.sh <tree-out-dir> <out-dir>
#
# <tree-out-dir> is build-texmf-tree.sh's <out-dir> (holding tree/). For each
# document in tests/documents, writes <out-dir>/<doc>.pdf, .log and .fls (the
# -recorder list of files read and written), and <out-dir>/documents.json.
#
# Each document is compiled twice; the two PDFs must be identical. Dates and
# the PDF /ID come from SOURCE_DATE_EPOCH (FORCE_SOURCE_DATE=1), so a PDF made
# on RISC OS with the same settings can be compared byte for byte. Fails if a
# document does not compile, its log does not report one or more pages
# written, or the PDF does not start with a PDF header and end with %%EOF.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if [ $# -ne 2 ]; then
  echo "usage: $0 <tree-out-dir> <out-dir>" >&2
  exit 2
fi
treeout=$(cd "$1" && pwd)
tree="$treeout/tree"
mkdir -p "$2"
out=$(cd "$2" && pwd)
bindir="$tree/bin/host"

# The documents, with the program that runs each one. The program name picks
# the format: pdftex loads pdftex.fmt, pdflatex loads pdflatex.fmt.
documents=(
  "storytest pdftex"
  "test pdflatex"
)

# 1 March 2026, the date of the TeX Live 2026 image.
export SOURCE_DATE_EPOCH=${DOCS_DATE_EPOCH:-1772323200}
export FORCE_SOURCE_DATE=1
unset TEXMFCNF TEXMFHOME TEXMFVAR TEXMFCONFIG TEXMFLOCAL TEXMFSYSVAR TEXMFSYSCONFIG \
  TEXINPUTS TFMFONTS T1FONTS ENCFONTS TEXFONTMAPS TEXFORMATS
export HOME="$out/home"
export PATH="$bindir:$PATH"
mkdir -p "$HOME"

failures=0
results=()
for entry in "${documents[@]}"; do
  read -r doc program <<< "$entry"
  digests=()
  for run in 1 2; do
    work="$out/work-$doc-$run"
    rm -rf "$work"
    mkdir -p "$work"
    cp "$root/tests/documents/$doc.tex" "$work/"
    status=0
    (cd "$work" && "$program" -interaction=nonstopmode -halt-on-error -recorder "$doc.tex" > "$work/stdout.txt" 2>&1) || status=$?
    if [ "$status" -ne 0 ] || [ ! -f "$work/$doc.pdf" ]; then
      echo "FAIL $doc: $program exited with status $status; the end of its log:"
      tail -n 20 "$work/$doc.log" 2> /dev/null || tail -n 20 "$work/stdout.txt"
      failures=$((failures + 1))
      continue 2
    fi
    digests+=("$(sha256sum "$work/$doc.pdf" | cut -d' ' -f1)")
  done
  work="$out/work-$doc-1"
  cp "$work/$doc.pdf" "$work/$doc.log" "$work/$doc.fls" "$out/"
  rm -rf "$out/work-$doc-1" "$out/work-$doc-2"

  pages=$(sed -n "s/^Output written on $doc\\.pdf (\\([0-9]*\\) pages\\{0,1\\}, \\([0-9]*\\) bytes).*/\\1/p" "$out/$doc.log" | head -n 1)
  header=$(head -c 7 "$out/$doc.pdf")
  trailer=$(tail -c 7 "$out/$doc.pdf" | tr -d '\r\n')
  problems=()
  [ -n "$pages" ] && [ "$pages" -ge 1 ] || problems+=("the log reports no pages written")
  [ "$header" = "%PDF-1." ] || problems+=("no PDF header")
  [ "$trailer" = "%%EOF" ] || problems+=("no %%EOF at the end")
  [ "${digests[0]}" = "${digests[1]}" ] || problems+=("two runs gave different PDFs")
  if [ ${#problems[@]} -gt 0 ]; then
    echo "FAIL $doc: $(IFS=';'; echo "${problems[*]}")"
    failures=$((failures + 1))
    continue
  fi
  bytes=$(wc -c < "$out/$doc.pdf")
  reads=$(grep -c '^INPUT ' "$out/$doc.fls" || true)
  echo "ok $doc: $program, $pages page(s), $bytes bytes, SHA-256 ${digests[0]}, reads $reads files; identical on a second run"
  results+=("$(jq -n --arg doc "$doc" --arg program "$program" --argjson pages "$pages" \
    --argjson bytes "$bytes" --arg sha256 "${digests[0]}" '{document: $doc, program: $program, pages: $pages, bytes: $bytes, sha256: $sha256}')")
done

printf '%s\n' "${results[@]}" | jq -s --arg epoch "$SOURCE_DATE_EPOCH" '{source_date_epoch: $epoch, documents: .}' > "$out/documents.json"
if [ "$failures" -ne 0 ]; then
  echo "$failures document(s) failed"
  exit 1
fi
echo "All test documents compiled on the host"
