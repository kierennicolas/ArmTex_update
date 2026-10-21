#!/usr/bin/env bash
# Check a PDF made on RISC OS against the reference made on the build machine
# from the same document.
#
# Usage: scripts/validate-pdf.sh <pdf> <reference-pdf>
#
# Both should be made with the same SOURCE_DATE_EPOCH and FORCE_SOURCE_DATE=1
# (the Milestone 3 kits and scripts/test-documents.sh do this), in which case
# a correct RISC OS build is expected to produce the same file apart from the
# /ID, which hashes the working directory. If the files differ otherwise, the
# checks below say how much:
#
#   structure  qpdf --check finds no errors in <pdf>
#   version    the same PDF version and producer
#   pages      the same number of pages, each the same size
#   fonts      the same fonts: name, type, encoding, embedded, subset, Unicode map
#   text       the same text, extracted with pdftotext
#
# Prints PASS or FAIL for each, then a verdict. Exits 0 if every check passes
# (identical or not), 1 if any fails, 2 if a tool is missing. Needs qpdf and
# poppler-utils (pdfinfo, pdffonts, pdftotext).

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <pdf> <reference-pdf>" >&2
  exit 2
fi
pdf=$1
ref=$2
for tool in qpdf pdfinfo pdffonts pdftotext; do
  if ! command -v "$tool" > /dev/null; then
    echo "error: $tool not found; install qpdf and poppler-utils" >&2
    exit 2
  fi
done
for f in "$pdf" "$ref"; do
  [ -f "$f" ] || { echo "error: $f not found" >&2; exit 2; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
result() { # result <PASS|FAIL> <check> <detail>
  echo "$1 $2: $3"
  if [ "$1" = FAIL ]; then failures=$((failures + 1)); fi
}

# pdfTeX's /ID hashes the working directory and output file name, so it
# differs between machines even when everything else is the same.
same_but_id() {
  python3 - "$1" "$2" <<'EOF'
import re, sys
def blank(data):
    return re.sub(rb"/ID\s*\[\s*<[0-9A-Fa-f]*>\s*<[0-9A-Fa-f]*>\s*\]",
                  lambda m: re.sub(rb"[0-9A-Fa-f]", b"0", m.group(0)), data)
a, b = (blank(open(path, "rb").read()) for path in sys.argv[1:3])
sys.exit(0 if a == b else 1)
EOF
}

if cmp -s "$pdf" "$ref"; then
  identical=1
  result PASS identical "the two files are the same, byte for byte ($(wc -c < "$pdf") bytes)"
elif same_but_id "$pdf" "$ref"; then
  identical=2
  result PASS identical "the same apart from /ID, which hashes the working directory ($(wc -c < "$pdf") bytes)"
else
  identical=0
  echo "INFO identical: the files differ ($(wc -c < "$pdf") and $(wc -c < "$ref") bytes); comparing their contents"
fi

# structure
if qpdf --check "$pdf" > "$work/check.txt" 2>&1; then
  result PASS structure "qpdf --check finds no errors"
else
  result FAIL structure "qpdf --check: $(grep -v '^checking\|^PDF Version\|^File is not' "$work/check.txt" | head -n 3 | tr '\n' ' ')"
fi

# The tools fail on a damaged file; that is reported as a FAIL, not an exit.
info() { { pdfinfo "$1" 2> /dev/null || true; } | sed -n "s/^$2: *//p"; }

# version and producer
for field in "PDF version" Producer; do
  a=$(info "$pdf" "$field")
  b=$(info "$ref" "$field")
  if [ "$a" = "$b" ]; then
    result PASS "$(tr '[:upper:] ' '[:lower:]-' <<< "$field")" "$a"
  else
    result FAIL "$(tr '[:upper:] ' '[:lower:]-' <<< "$field")" "'$a', reference '$b'"
  fi
done

# pages and their sizes
pages=$(info "$pdf" Pages)
refpages=$(info "$ref" Pages)
if [ -n "$pages" ] && [ "$pages" = "$refpages" ]; then
  { pdfinfo -f 1 -l "$pages" "$pdf" 2> /dev/null || true; } | grep -E '^Page +[0-9]+ size:' > "$work/sizes.txt" || true
  { pdfinfo -f 1 -l "$pages" "$ref" 2> /dev/null || true; } | grep -E '^Page +[0-9]+ size:' > "$work/refsizes.txt" || true
  if cmp -s "$work/sizes.txt" "$work/refsizes.txt"; then
    result PASS pages "$pages, $(head -n 1 "$work/sizes.txt" | sed 's/^Page *1 size: *//')"
  else
    result FAIL pages "page sizes differ: $(diff "$work/refsizes.txt" "$work/sizes.txt" | grep '^[<>]' | head -n 2 | tr '\n' ' ')"
  fi
else
  result FAIL pages "${pages:-none}, reference ${refpages:-none}"
fi

# fonts: drop the object number columns, which may differ harmlessly
fonts() { { pdffonts "$1" 2> /dev/null || true; } | tail -n +3 | awk '{ NF -= 2; print }'; }
fonts "$pdf" > "$work/fonts.txt"
fonts "$ref" > "$work/reffonts.txt"
if [ -s "$work/reffonts.txt" ] && cmp -s "$work/fonts.txt" "$work/reffonts.txt"; then
  result PASS fonts "$(wc -l < "$work/fonts.txt") fonts, all as in the reference: $(awk '{print $1}' "$work/fonts.txt" | sed 's/^[A-Z]\{6\}+//' | tr '\n' ' ')"
else
  result FAIL fonts "differ from the reference: $(diff "$work/reffonts.txt" "$work/fonts.txt" | grep '^[<>]' | head -n 4 | tr '\n' ' ')"
fi
if grep -q ' no ' <(awk '{print " " $(NF-2) " "}' "$work/fonts.txt"); then
  result FAIL embedded "a font is not embedded"
fi

# text
: > "$work/text.txt"
: > "$work/reftext.txt"
pdftotext -enc UTF-8 "$pdf" "$work/text.txt" 2> /dev/null || true
pdftotext -enc UTF-8 "$ref" "$work/reftext.txt" 2> /dev/null || true
if [ -s "$work/reftext.txt" ] && cmp -s "$work/text.txt" "$work/reftext.txt"; then
  result PASS text "$(wc -w < "$work/text.txt") words, as in the reference"
else
  result FAIL text "differs from the reference: $(diff "$work/reftext.txt" "$work/text.txt" | grep '^[<>]' | head -n 3 | tr '\n' ' ')"
fi

if [ "$failures" -ne 0 ]; then
  echo "VERDICT: FAIL ($failures check(s) failed)"
  exit 1
fi
if [ "$identical" = 1 ]; then
  echo "VERDICT: PASS (identical to the reference)"
elif [ "$identical" = 2 ]; then
  echo "VERDICT: PASS (identical to the reference apart from /ID)"
else
  echo "VERDICT: PASS (not identical, but the same structure, pages, fonts and text)"
fi
