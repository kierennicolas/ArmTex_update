#!/usr/bin/env bash
# Package the Gate 2 kit: the cross-compiled kpsewhich with a small texmf tree,
# laid out the way a TeX Live installation is, as a RISC OS zip.
#
# Usage: scripts/package-kpse-kit.sh <texlive-source> <tl-out-dir>
#
# Needs <tl-out-dir>/aif/kpsewhich,ff8 from scripts/build-texlive.sh. Writes:
#   <tl-out-dir>/kit/TLKpse/          the kit tree, with ,xxx filetype suffixes
#   <tl-out-dir>/TLKpse.zip           the kit as a RISC OS zip
#   <tl-out-dir>/kpse-emulator-commands.txt   commands for run-emulator.sh
#
# The tree follows TeX Live's layout, so kpathsea's own texmf.cnf works
# unchanged: the program is in bin/riscos/, which makes the kit's top directory
# $SELFAUTOPARENT, and texmf.cnf is in texmf-dist/web2c/. The TeX files are
# stand-ins with the right names: Gate 2 tests finding files, not reading them.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if [ $# -ne 2 ]; then
  echo "usage: $0 <texlive-source> <tl-out-dir>" >&2
  exit 2
fi
src=$(cd "$1" && pwd)
out=$(cd "$2" && pwd)
kit="$out/kit/TLKpse"
zip="$out/TLKpse.zip"
results="$out/results.json"

if [ ! -f "$out/aif/kpsewhich,ff8" ]; then
  echo "error: $out/aif/kpsewhich,ff8 not found; kpsewhich did not cross-compile" >&2
  exit 1
fi
revision=$(jq -r .texlive_revision "$results")
commit=${BUILD_COMMIT:-$(git -c safe.directory='*' -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)}

rm -rf "$out/kit" "$zip"
dist="$kit/texmf-dist"
mkdir -p "$kit/bin/riscos" "$dist/web2c" "$dist/tex/latex/base" "$dist/tex/plain/base" \
  "$dist/fonts/tfm/public/cm" "$dist/fonts/type1/public/amsfonts/cm"

cp "$out/aif/kpsewhich,ff8" "$kit/bin/riscos/kpsewhich,ff8"
cp "$src/texk/kpathsea/texmf.cnf" "$dist/web2c/texmf.cnf,fff"

stand_in() {
  printf '%% Stand-in for %s, for the Gate 2 kpathsea test. Not a real TeX file.\n' "$1"
}
stand_in article.cls > "$dist/tex/latex/base/article.cls,fff"
stand_in plain.tex > "$dist/tex/plain/base/plain.tex,fff"
stand_in cmr10.tfm > "$dist/fonts/tfm/public/cm/cmr10.tfm,ffd"
stand_in cmr10.pfb > "$dist/fonts/type1/public/amsfonts/cm/cmr10.pfb,ffd"

# ls-R lists the tree as kpathsea sees it through UnixLib: Unix-style names,
# without the ,xxx suffixes this repository uses for filetypes.
(
  cd "$dist"
  echo "% ls-R -- filename database for kpathsea; do not change this line."
  find . -type d | LC_ALL=C sort | while read -r d; do
    echo
    if [ "$d" = . ]; then echo "./:"; else echo "$d:"; fi
    find "$d" -mindepth 1 -maxdepth 1 | sed -e 's#.*/##' -e 's#,[0-9a-f]\{3\}$##' | LC_ALL=C sort
  done
) > "$dist/ls-R,fff"

# Searches and variables to report, in order. Each runs as its own command so
# that one failure (exit status 1 for "not found") does not hide the rest.
queries=(
  "--version"
  "-var-value=SELFAUTOLOC"
  "-var-value=SELFAUTOPARENT"
  "-var-value=TEXMFDIST"
  "-var-value=TEXMFCNF"
  "texmf.cnf"
  "article.cls"
  "plain.tex"
  "cmr10.tfm"
  "cmr10.pfb"
  "-must-exist article.cls"
)

obey="$kit/RunKpse,feb"
{
  echo "| TeX Live for RISC OS: Gate 2 kpathsea test kit"
  echo "| Built from commit $commit, TeX Live source $revision"
  echo "| Run this file. The output is saved in the file Results in this directory."
  echo "Set TLKpse\$Dir <Obey\$Dir>"
  echo "RMEnsure SharedUnixLibrary 1.07 RMLoad System:Modules.SharedULib"
  echo "RMEnsure SharedUnixLibrary 1.07 Error The TLKpse kit needs SharedUnixLibrary 1.07 or later. Install it with PackMan, then run RunKpse again."
  echo "Spool <TLKpse\$Dir>.Results"
  echo "Echo TeX Live for RISC OS: Gate 2 kpathsea test, commit ${commit:0:12}"
  echo "Echo Kit location: <TLKpse\$Dir>"
  for q in "${queries[@]}"; do
    echo "Echo ===== kpsewhich $q ====="
    echo "Run <TLKpse\$Dir>.bin.riscos.kpsewhich $q"
    echo "Echo ===== exit status <Sys\$ReturnCode> ====="
  done
  echo "Echo ===== kpsewhich -debug=40 article.cls (search details) ====="
  echo "Run <TLKpse\$Dir>.bin.riscos.kpsewhich -debug=40 article.cls"
  echo "Echo ===== exit status <Sys\$ReturnCode> ====="
  echo "Echo ===== all tests finished ====="
  echo "Spool"
  echo "Echo Results saved in <TLKpse\$Dir>.Results"
} > "$obey"

cat > "$kit/!ReadMe,fff" <<EOF
TeX Live for RISC OS: Gate 2 kpathsea test kit
Commit ${commit:0:12}, TeX Live source ${revision:0:12}

This kit checks that kpsewhich, cross-compiled from TeX Live 2026, finds files
in a TeX Live-style tree from wherever the kit is. The TeX files in it are
stand-ins with the right names; it is not a TeX installation.

1. Make sure SharedUnixLibrary is installed (PackMan has it).
2. Run RunKpse. It saves its output in a file called Results here.
3. Copy the whole TLKpse directory somewhere else (another directory, or
   the RAM disc), run RunKpse in the copy, and keep that Results too.
4. If RunKpse stops with an error, note it, then close Results: press F12,
   type Spool and press Return.
5. Report both Results files on the Gate 2 issue, as described in
   docs/testing.md in the GitHub repository.
EOF

# The same queries for the emulator, run with the kit as the current directory.
{
  echo "# Run by scripts/run-emulator.sh with the kit as the current directory."
  for q in "${queries[@]}"; do
    case $q in
      # Not found is exit status 1, which would stop the service's run.
      -must-exist*) continue ;;
    esac
    echo "Echo ===== kpsewhich $q ====="
    echo "Run bin.riscos.kpsewhich $q"
  done
  echo "Echo ===== kpsewhich -debug=40 article.cls ====="
  echo "Run bin.riscos.kpsewhich -debug=40 article.cls"
} > "$out/kpse-emulator-commands.txt"

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH=$(git -c safe.directory='*' -C "$root" log -1 --format=%ct 2>/dev/null || date +%s)
  export SOURCE_DATE_EPOCH
fi
python3 "$root/riscos/packaging/rozip.py" create "$zip" "$kit"
python3 "$root/riscos/packaging/rozip.py" list "$zip"
unzip -tq "$zip"
echo "Gate 2 kit: $zip"
