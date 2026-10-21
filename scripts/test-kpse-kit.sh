#!/usr/bin/env bash
# Host-side check of the Gate 2 kit's tree, using the native kpsewhich.
#
# Usage: scripts/test-kpse-kit.sh <kit-dir> <native-kpsewhich>
#
# <kit-dir> is the TLKpse tree from scripts/package-kpse-kit.sh, with ,xxx
# filetype suffixes. The check copies it without the suffixes (the names
# kpathsea sees through UnixLib), puts the native kpsewhich where the RISC OS
# one goes, and asks it for the same files RunKpse does. Every file must be
# found inside the copy. The copy is then moved and the searches repeated, to
# show that nothing depends on where the tree is.
#
# This tests the tree and its ls-R, not the RISC OS program: the native
# kpsewhich is built from the same pinned source, but nothing here runs a
# RISC OS binary. Exits 1 on the first wrong answer.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <kit-dir> <native-kpsewhich>" >&2
  exit 2
fi
kit=$(cd "$1" && pwd)
native=$2
if [ ! -x "$native" ]; then
  echo "error: $native is not an executable" >&2
  exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Copy the tree, dropping the filetype suffixes, and swap in the native program.
copy="$work/first/TLKpse"
mkdir -p "$copy"
(cd "$kit" && find . -type d) | while IFS= read -r d; do mkdir -p "$copy/$d"; done
(cd "$kit" && find . -type f) | while IFS= read -r f; do
  cp "$kit/$f" "$copy/$(sed -E 's#,[0-9a-f]{3}$##' <<< "$f")"
done
rm -f "$copy/bin/riscos/kpsewhich"
cp "$native" "$copy/bin/riscos/kpsewhich"

# Keep the runner's own TeX settings, if any, out of the searches.
unset TEXMFCNF TEXMFHOME TEXMFVAR TEXMFCONFIG TEXMFLOCAL TEXINPUTS TFMFONTS T1FONTS
export HOME="$work/home"
mkdir -p "$HOME"

failures=0
expect() {
  local tree=$1 what=$2 want=$3 got
  got=$("$tree/bin/riscos/kpsewhich" "$what" 2>&1) || true
  if [ "$got" = "$tree/$want" ]; then
    echo "ok: $what -> ${got#"$tree"/}"
  else
    echo "FAIL: $what: expected $tree/$want, got '$got'"
    failures=$((failures + 1))
  fi
}
expect_var() {
  local tree=$1 var=$2 want=$3 got
  got=$("$tree/bin/riscos/kpsewhich" -var-value="$var" 2>&1) || true
  if [ "$got" = "$want" ]; then
    echo "ok: $var = $got"
  else
    echo "FAIL: $var: expected '$want', got '$got'"
    failures=$((failures + 1))
  fi
}

check() {
  local tree=$1
  echo "Checking the tree at $tree"
  expect_var "$tree" SELFAUTOLOC "$tree/bin/riscos"
  expect_var "$tree" SELFAUTOPARENT "$tree"
  expect_var "$tree" TEXMFDIST "$tree/texmf-dist"
  expect "$tree" texmf.cnf texmf-dist/web2c/texmf.cnf
  expect "$tree" article.cls texmf-dist/tex/latex/base/article.cls
  expect "$tree" plain.tex texmf-dist/tex/plain/base/plain.tex
  expect "$tree" cmr10.tfm texmf-dist/fonts/tfm/public/cm/cmr10.tfm
  expect "$tree" cmr10.pfb texmf-dist/fonts/type1/public/amsfonts/cm/cmr10.pfb
  # kpsewhich only searches the disc when ls-R fails it, so the database
  # itself must be the tree's and must be read.
  # (Captured first: grep -q stops reading at the first match, and under
  # pipefail the writer's SIGPIPE would fail the test.)
  local debug
  debug=$("$tree/bin/riscos/kpsewhich" -debug=2 article.cls 2>&1) || true
  if grep -qF "using db file $tree/texmf-dist/ls-R" <<< "$debug"; then
    echo "ok: read texmf-dist/ls-R"
  else
    echo "FAIL: kpsewhich did not read $tree/texmf-dist/ls-R"
    failures=$((failures + 1))
  fi
}

check "$copy"
mkdir -p "$work/second/deeper"
mv "$copy" "$work/second/deeper/Moved"
check "$work/second/deeper/Moved"

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All kit tree checks passed"
