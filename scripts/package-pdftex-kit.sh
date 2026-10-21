#!/usr/bin/env bash
# Package pdfTeX for RISC OS with a texmf tree and the test documents, as a
# RISC OS zip: the Milestone 3 kit.
#
# Usage: scripts/package-pdftex-kit.sh <tl-out-dir> <tree-out-dir> <docs-out-dir> <full|emulator>
#
# <tl-out-dir> is scripts/build-texlive.sh's output (aif/pdftex,ff8 and
# aif/kpsewhich,ff8), <tree-out-dir> is scripts/build-texmf-tree.sh's (tree/),
# and <docs-out-dir> is scripts/test-documents.sh's (the .fls lists of files
# each test document reads).
#
#   full      the whole tree (texmf-dist/, texmf-var/), for hardware: the
#             Gate 3 kit. Writes <tl-out-dir>/TLPdfTeX.zip.
#   emulator  only the files the test documents read, plus texmf.cnf, so the
#             upload to the emulator service stays small. Writes
#             <tl-out-dir>/TLPdfTeXmini.zip and pdftex-emulator-commands.txt.
#
# The kit is laid out as TeX Live is: the programs in bin/riscos/, so the kit's
# top directory is kpathsea's SELFAUTOPARENT and texmf.cnf is found unchanged.
# Files carry ,xxx filetype suffixes: Text (fff) for files people read, Data
# (ffd) for the rest. ls-R is regenerated for what is in the kit.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if [ $# -ne 4 ]; then
  echo "usage: $0 <tl-out-dir> <tree-out-dir> <docs-out-dir> <full|emulator>" >&2
  exit 2
fi
tlout=$(cd "$1" && pwd)
tree=$(cd "$2/tree" && pwd)
docs=$(cd "$3" && pwd)
kind=$4
case $kind in
  full) name=TLPdfTeX ;;
  emulator) name=TLPdfTeXmini ;;
  *) echo "error: kind must be full or emulator" >&2; exit 2 ;;
esac

for program in pdftex kpsewhich; do
  if [ ! -f "$tlout/aif/$program,ff8" ]; then
    echo "error: $tlout/aif/$program,ff8 not found; $program did not cross-compile" >&2
    exit 1
  fi
done
commit=${BUILD_COMMIT:-$(git -c safe.directory='*' -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)}
epoch=$(jq -r .source_date_epoch "$docs/documents.json")

kit="$tlout/kit/$name"
zip="$tlout/$name.zip"
rm -rf "${kit:?}" "$zip"
mkdir -p "$kit/bin/riscos" "$kit/Tests"
cp "$tlout/aif/pdftex,ff8" "$tlout/aif/kpsewhich,ff8" "$kit/bin/riscos/"

# The files to ship, relative to the tree.
list="$tlout/kit/$name-files.txt"
if [ "$kind" = full ]; then
  (cd "$tree" && find texmf-dist texmf-var -type f ! -name ls-R | LC_ALL=C sort) > "$list"
else
  # Every file a test document read from the tree, by the -recorder lists.
  {
    sed -n "s#^INPUT $tree/##p" "$docs"/*.fls
    echo texmf-dist/web2c/texmf.cnf
  } | grep -v '/ls-R$' | LC_ALL=C sort -u > "$list"
fi

filetype() {
  case $1 in
    *.tex | *.sty | *.cls | *.clo | *.cfg | *.def | *.fd | *.ldf | *.ltx | *.ini | \
      *.cnf | *.map | *.enc | *.dat | *.lua | *.tcx | *.txt | *.md | *.pl | *.lco | \
      *README* | *readme*) echo fff ;;
    *) echo ffd ;;
  esac
}

files=0
while IFS= read -r path; do
  [ -f "$tree/$path" ] || { echo "error: $path is not in the tree" >&2; exit 1; }
  mkdir -p "$kit/$(dirname "$path")"
  cp "$tree/$path" "$kit/$path,$(filetype "$path")"
  files=$((files + 1))
done < "$list"

# ls-R for each tree in the kit, listing it as kpathsea sees it through
# UnixLib: Unix-style names, without the ,xxx suffixes.
for texmf in texmf-dist texmf-var; do
  [ -d "$kit/$texmf" ] || continue
  # Listed in itself, as mktexlsr's ls-R is; written outside the tree first.
  : > "$kit/$texmf/ls-R,fff"
  (
    cd "$kit/$texmf"
    echo "% ls-R -- filename database for kpathsea; do not change this line."
    find . -type d | LC_ALL=C sort | while read -r d; do
      echo
      if [ "$d" = . ]; then echo "./:"; else echo "$d:"; fi
      find "$d" -mindepth 1 -maxdepth 1 | sed -e 's#.*/##' -e 's#,[0-9a-f]\{3\}$##' | LC_ALL=C sort
    done
  ) > "$tlout/kit/ls-R.tmp"
  mv "$tlout/kit/ls-R.tmp" "$kit/$texmf/ls-R,fff"
done

# Names that may not survive on a RISC OS filing system: characters that are
# special in RISC OS paths, or two names in a directory that differ only in
# case (FileCore ignores case). Reported, not fixed: it is for Gate 3 to show
# whether any matters.
python3 - "$kit" <<'EOF'
import os, re, sys
kit = sys.argv[1]
special = re.compile(r'[$&@^%#*\\:"|<>\s]')
problems = 0
for base, dirs, files in os.walk(kit):
    seen = {}
    for name in dirs + files:
        plain = re.sub(r",[0-9a-f]{3}$", "", name)
        rel = os.path.relpath(os.path.join(base, plain), kit)
        if special.search(plain):
            print(f"WARNING: {rel}: a character special in RISC OS paths")
            problems += 1
        if len(plain) > 255:
            print(f"WARNING: {rel}: longer than 255 characters")
            problems += 1
        other = seen.setdefault(plain.lower(), plain)
        if other != plain:
            print(f"WARNING: {rel}: differs only in case from {other}")
            problems += 1
print(f"RISC OS name check: {problems} problem(s)")
EOF

cp "$root/tests/documents/storytest.tex" "$kit/Tests/storytest.tex,fff"
cp "$root/tests/documents/test.tex" "$kit/Tests/test.tex,fff"

# The two test runs, as RISC OS commands. pdftex -progname=pdflatex loads the
# pdflatex format, as running it under the name pdflatex would.
runs=(
  "storytest|pdftex|"
  "test|pdflatex|-progname=pdflatex "
)

obey="$kit/RunTests,feb"
{
  echo "| TeX Live for RISC OS: Milestone 3 pdfTeX test kit ($kind)"
  echo "| Built from commit $commit"
  echo "| Run this file. It typesets the documents in Tests, writing the PDFs and"
  echo "| logs there, and saves its own output in the file Results."
  echo "Set TLPdfTeX\$Dir <Obey\$Dir>"
  echo "RMEnsure SharedUnixLibrary 1.07 RMLoad System:Modules.SharedULib"
  echo "RMEnsure SharedUnixLibrary 1.07 Error The kit needs SharedUnixLibrary 1.07 or later. Install it with PackMan, then run RunTests again."
  echo "| Fixed dates, so the PDFs can be compared with the ones made on the build machine."
  echo "Set SOURCE_DATE_EPOCH $epoch"
  echo "Set FORCE_SOURCE_DATE 1"
  echo "Dir <TLPdfTeX\$Dir>.Tests"
  echo "Spool <TLPdfTeX\$Dir>.Results"
  echo "Echo TeX Live for RISC OS: Milestone 3 pdfTeX test, commit ${commit:0:12}"
  echo "Echo Kit location: <TLPdfTeX\$Dir>"
  for r in "${runs[@]}"; do
    IFS='|' read -r doc format option <<< "$r"
    echo "Echo ===== $format $doc.tex ====="
    echo "Run <TLPdfTeX\$Dir>.bin.riscos.pdftex ${option}-interaction=nonstopmode -halt-on-error $doc.tex"
    echo "Echo ===== exit status <Sys\$ReturnCode> ====="
  done
  echo "Echo ===== all tests finished ====="
  echo "Spool"
  echo "Back"
  echo "Echo Results saved in <TLPdfTeX\$Dir>.Results; the PDFs are in <TLPdfTeX\$Dir>.Tests"
} > "$obey"

cat > "$kit/!ReadMe,fff" <<EOF
TeX Live for RISC OS: Milestone 3 pdfTeX test kit ($kind)
Commit ${commit:0:12}

pdfTeX from TeX Live 2026, cross-compiled for RISC OS, with a TeX Live tree
($files files) and formats made on the build machine.

1. Make sure SharedUnixLibrary is installed (PackMan has it).
2. Run RunTests. It typesets Tests.storytest/tex (plain TeX) and
   Tests.test/tex (LaTeX), writing storytest/pdf and test/pdf, with their
   logs, in Tests. Its own output goes in a file called Results here.
3. If RunTests stops with an error, note it, then close Results: press F12,
   type Spool and press Return.
4. Report Results, the two PDFs and the two logs on the Gate 3 issue, as
   described in docs/testing.md in the GitHub repository.
EOF

if [ "$kind" = emulator ]; then
  # The same runs for scripts/run-emulator.sh, with the kit as the current
  # directory; the PDFs and logs go to Out, which the service returns.
  {
    echo "# Run by scripts/run-emulator.sh with the kit as the current directory."
    echo "Set SOURCE_DATE_EPOCH $epoch"
    echo "Set FORCE_SOURCE_DATE 1"
    echo "CDir Out"
    for r in "${runs[@]}"; do
      IFS='|' read -r doc format option <<< "$r"
      echo "Echo ===== $format $doc.tex ====="
      echo "Run bin.riscos.pdftex ${option}-output-directory=Out -interaction=nonstopmode -halt-on-error Tests/$doc.tex"
    done
  } > "$tlout/pdftex-emulator-commands.txt"
fi

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH=$(git -c safe.directory='*' -C "$root" log -1 --format=%ct 2>/dev/null || date +%s)
  export SOURCE_DATE_EPOCH
fi
python3 "$root/riscos/packaging/rozip.py" create "$zip" "$kit"
unzip -tq "$zip"
echo "pdfTeX kit ($kind): $zip, $files tree files, $(wc -c < "$zip") bytes"
