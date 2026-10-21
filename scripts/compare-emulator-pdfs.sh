#!/usr/bin/env bash
# Compare the PDFs that the emulator run of the pdfTeX kit returned with the
# references made on the build machine.
#
# Usage: scripts/compare-emulator-pdfs.sh <emulator-work-dir> <docs-out-dir>
#
# <emulator-work-dir> is where scripts/run-emulator.sh put the service's
# result (result,<filetype>: the kit's Out directory, as a zip). <docs-out-dir>
# is scripts/test-documents.sh's output, holding <doc>.pdf for each document.
# Both sides use the same SOURCE_DATE_EPOCH, so a correct build gives
# identical files. The PDFs are unpacked to <emulator-work-dir>/pdf/.
#
# Prints one line per document: IDENTICAL, DIFFERENT or MISSING, with sizes
# and SHA-256s. Then runs scripts/validate-pdf.sh on each one that differs,
# if its tools are installed. Exits 1 unless every document is identical or
# passes validate-pdf.sh.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if [ $# -ne 2 ]; then
  echo "usage: $0 <emulator-work-dir> <docs-out-dir>" >&2
  exit 2
fi
work=$(cd "$1" && pwd)
docs=$(cd "$2" && pwd)

shopt -s nullglob
results=("$work/result,"*)
if [ ${#results[@]} -eq 0 ]; then
  echo "error: the emulator returned nothing (no $work/result,*)" >&2
  exit 1
fi
result=${results[0]}
echo "Returned: $(basename "$result"), $(wc -c < "$result") bytes"

# The service returns a directory as a zip. RISC OS names may come back as
# storytest/pdf, storytest.pdf or with a ,xxx filetype suffix.
rm -rf "$work/pdf"
mkdir -p "$work/pdf"
python3 - "$result" "$work/pdf" <<'EOF'
import re, sys, zipfile
result, dest = sys.argv[1], sys.argv[2]
if not zipfile.is_zipfile(result):
    sys.exit(f"error: {result} is not a zip")
with zipfile.ZipFile(result) as archive:
    for info in archive.infolist():
        print(f"  {info.filename} ({info.file_size} bytes)")
        match = re.search(r"([A-Za-z0-9_-]+)[./](pdf|log)(,[0-9a-fA-F]{3})?$", info.filename)
        if match and not info.is_dir():
            with archive.open(info) as source, open(f"{dest}/{match[1]}.{match[2]}", "wb") as out:
                out.write(source.read())
EOF

failures=0
for ref in "$docs"/*.pdf; do
  doc=$(basename "$ref" .pdf)
  got="$work/pdf/$doc.pdf"
  if [ ! -f "$got" ]; then
    echo "MISSING $doc.pdf: the emulator returned no such file"
    failures=$((failures + 1))
    continue
  fi
  a=$(sha256sum "$got" | cut -d' ' -f1)
  b=$(sha256sum "$ref" | cut -d' ' -f1)
  if [ "$a" = "$b" ]; then
    echo "IDENTICAL $doc.pdf: $(wc -c < "$got") bytes, SHA-256 $a, the same as the host's"
    continue
  fi
  # pdfTeX's /ID hashes the working directory and output path, which cannot
  # match between machines; compare with it blanked, and show any other
  # difference in context.
  verdict=$(python3 - "$got" "$ref" <<'EOF'
import re, sys
def blank(data):
    return re.sub(rb"/ID\s*\[\s*<[0-9A-Fa-f]*>\s*<[0-9A-Fa-f]*>\s*\]",
                  lambda m: re.sub(rb"[0-9A-Fa-f]", b"0", m.group(0)), data)
a, b = (open(path, "rb").read() for path in sys.argv[1:3])
na, nb = blank(a), blank(b)
if na == nb:
    print("SAME-BUT-ID")
    sys.exit()
print("DIFFERENT")
diffs = [i for i in range(min(len(na), len(nb))) if na[i] != nb[i]]
print(f"  {len(diffs)} differing bytes in the first {min(len(na), len(nb))}; lengths {len(a)} and {len(b)}")
shown = -1000
for i in diffs:
    if i - shown < 64:
        continue
    shown = i
    show = lambda d: d[max(0, i - 40):i + 40].decode("latin-1").encode("unicode_escape").decode()
    print(f"  at byte {i}:\n    RISC OS: {show(a)}\n    host:    {show(b)}")
    if shown >= 0 and len([j for j in diffs if j <= i]) > 200:
        break
EOF
)
  if [ "$(head -n 1 <<< "$verdict")" = SAME-BUT-ID ]; then
    echo "IDENTICAL $doc.pdf apart from /ID: $(wc -c < "$got") bytes; /ID hashes the working directory, so it always differs between machines"
    continue
  fi
  echo "DIFFERENT $doc.pdf: $(wc -c < "$got") bytes, SHA-256 $a; host: $(wc -c < "$ref") bytes, SHA-256 $b"
  tail -n +2 <<< "$verdict" | head -n 40
  if command -v qpdf > /dev/null && command -v pdfinfo > /dev/null; then
    "$root/scripts/validate-pdf.sh" "$got" "$ref" || failures=$((failures + 1))
  else
    echo "  (qpdf and poppler-utils are not installed here; validate-pdf.sh not run)"
    failures=$((failures + 1))
  fi
done
exit $((failures > 0))
