#!/usr/bin/env bash
# Build the !TeXLive application and package it as a RISC OS zip.
#
# Usage: scripts/package-release.sh <tl-out-dir> <tree-out-dir> <full|DOCS-DIR>
#
# <tl-out-dir> is scripts/build-texlive.sh's output (aif/pdftex,ff8 and
# aif/kpsewhich,ff8); <tree-out-dir> is scripts/build-texmf-tree.sh's (tree/).
#
#   full      the whole tree. Writes <tl-out-dir>/TeXLive.zip, holding
#             !TeXLive: the development release.
#   DOCS-DIR  only the files the test documents read, by the -recorder lists
#             in DOCS-DIR (scripts/test-documents.sh's output), so the upload
#             to the emulator service stays small. Writes
#             <tl-out-dir>/app-emulator/ (!TeXLive and the test documents,
#             for scripts/run-emulator.sh) and app-emulator-commands.txt,
#             which run the documents through the application's own !Boot,
#             !Run and commands.
#
# The application (riscos/app/!TeXLive) is laid out as a TeX Live
# installation: the programs in bin.riscos, so !TeXLive is kpathsea's
# SELFAUTOPARENT and texmf.cnf is found unchanged; texmf-dist and texmf-var
# beside them. Its !Boot and !Run define the commands pdflatex, pdftex and
# kpsewhich. Tree files carry filetype suffixes and each tree gets its own
# ls-R (scripts/lib/riscos-tree.sh).

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scripts/lib/riscos-tree.sh
. "$root/scripts/lib/riscos-tree.sh"
if [ $# -ne 3 ]; then
  echo "usage: $0 <tl-out-dir> <tree-out-dir> <full|DOCS-DIR>" >&2
  exit 2
fi
tlout=$(cd "$1" && pwd)
treeout=$(cd "$2" && pwd)
tree="$treeout/tree"
if [ "$3" = full ]; then
  kind=full
else
  kind=subset
  docs=$(cd "$3" && pwd)
fi

for program in pdftex kpsewhich; do
  if [ ! -f "$tlout/aif/$program,ff8" ]; then
    echo "error: $tlout/aif/$program,ff8 not found; $program did not cross-compile" >&2
    exit 1
  fi
done
commit=${BUILD_COMMIT:-$(git -c safe.directory='*' -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)}
manifest="$root/upstream/manifest.json"

if [ "$kind" = full ]; then
  stage="$tlout/app"
else
  stage="$tlout/app-emulator"
fi
app="$stage/!TeXLive"
rm -rf "${stage:?}"
mkdir -p "$stage"
cp -R "$root/riscos/app/!TeXLive" "$app"
mkdir -p "$app/bin/riscos"
cp "$tlout/aif/pdftex,ff8" "$tlout/aif/kpsewhich,ff8" "$app/bin/riscos/"

# TeX Live's licence notes, from the root of the tree (texlive.infra).
for f in LICENSE.TL LICENSE.CTAN; do
  if [ ! -f "$tree/$f" ]; then
    echo "error: $tree/$f not found" >&2
    exit 1
  fi
  cp "$tree/$f" "$app/$f,fff"
done

list="$stage/files.txt"
if [ "$kind" = full ]; then
  tree_file_list "$tree" full > "$list"
else
  tree_file_list "$tree" "$docs" > "$list"
fi
files=$(copy_tree_files "$tree" "$list" "$app")
rm -f "$list"
write_ls_r "$app"
check_riscos_names "$app"

{
  echo "TeX Live 2026 for RISC OS: development build"
  echo
  echo "Commit:          $commit"
  echo "TeX Live source: $(jq -r '.texlive.source.ref | sub("refs/heads/tags/"; "")' "$manifest") ($(jq -r .texlive.source.revision "$manifest"))"
  echo "Support files:   $(jq -r .texlive.support_files.file "$manifest"), scheme-basic"
  echo "Compiler:        GCCSDK $(jq -r '.toolchain.gccsdk.revision[0:12]' "$manifest"), soft-float, static, AIF"
  echo "Tree:            $files files$( [ "$kind" = subset ] && echo ' (only what the test documents need)')"
  echo
  echo "Formats, made on the build machine:"
  jq -r '.formats | to_entries[] | "  \(.key) (\(.value.engine)), \(.value.size) bytes"' "$treeout/tree.json"
  echo
  echo "Not tested on RISC OS hardware unless the project's progress page says so:"
  echo "https://github.com/kierennicolas/ArmTex_update/blob/main/docs/progress.md"
} > "$app/BuildInfo,fff"

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH=$(git -c safe.directory='*' -C "$root" log -1 --format=%ct 2>/dev/null || date +%s)
  export SOURCE_DATE_EPOCH
fi

if [ "$kind" = full ]; then
  zip="$tlout/TeXLive.zip"
  rm -f "$zip"
  python3 "$root/riscos/packaging/rozip.py" create "$zip" "$app"
  unzip -tq "$zip"
  echo "!TeXLive (full): $zip, $files tree files, $(wc -c < "$zip") bytes"
  exit 0
fi

# The emulator run: the test documents beside the application, and commands
# that use the application as a person would. The service does not run a
# Filer, so !Boot is run directly; then !Run, as a double-click would.
mkdir -p "$stage/Tests"
cp "$root/tests/documents/storytest.tex" "$stage/Tests/storytest.tex,fff"
cp "$root/tests/documents/test.tex" "$stage/Tests/test.tex,fff"
epoch=$(jq -r .source_date_epoch "$docs/documents.json")
{
  echo "# Run by scripts/run-emulator.sh with app-emulator as the current directory."
  echo "Obey !TeXLive.!Boot"
  echo "Show TeXLive\$Dir"
  echo "Run !TeXLive.!Run"
  echo "Show Alias\$pdf*"
  echo "Show Alias\$kpsewhich"
  echo "Set SOURCE_DATE_EPOCH $epoch"
  echo "Set FORCE_SOURCE_DATE 1"
  echo "CDir Out"
  echo "Echo ===== kpsewhich article.cls ====="
  echo "kpsewhich article.cls"
  echo "Echo ===== pdftex storytest.tex ====="
  echo "pdftex -output-directory=Out -interaction=nonstopmode -halt-on-error Tests/storytest.tex"
  echo "Echo ===== pdflatex test.tex ====="
  echo "pdflatex -output-directory=Out -interaction=nonstopmode -halt-on-error Tests/test.tex"
} > "$tlout/app-emulator-commands.txt"
echo "!TeXLive (subset, for the emulator): $stage, $files tree files"
