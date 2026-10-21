#!/usr/bin/env bash
# Build a TeX Live tree from the pinned support files, with its generated
# configuration, font maps and formats, on the build machine.
#
# Usage: scripts/build-texmf-tree.sh <support-files-dir> <host-tools-dir> <out-dir> [package...]
#
# <support-files-dir> comes from "scripts/fetch-upstream.sh support-files"
# (the pinned database and package containers). <host-tools-dir> comes from
# scripts/build-host-tools.sh: kpsewhich and pdftex built natively from the
# pinned TeX Live source. Packages default to scheme-basic; their
# dependencies are added.
#
# Does what install-tl does after unpacking, with TeX Live's own scripts from
# the tree and the host tools as the engine:
#   1. unpack the packages; write the installation's tlpkg/texlive.tlpdb;
#   2. write language.dat/.def/.dat.lua, fmtutil.cnf and updmap.cfg
#      (scripts/lib/tl-postinstall.pl, using TeX Live's TLUtils);
#   3. mktexlsr; updmap-sys (font maps); fmtutil-sys for the formats in
#      TL_FORMATS (default "pdftex pdflatex"); mktexlsr again.
#
# Writes:
#   <out-dir>/tree/        the tree: texmf-dist/, texmf-var/, tlpkg/, and
#                          bin/host/ with the host programs (build machine only)
#   <out-dir>/tree.json    packages, formats and their sizes
#   <out-dir>/logs/        one log per step, and fmtutil's format logs
#
# Formats are made by a host pdfTeX from the same source and configuration as
# the RISC OS one, relying on Web2c's architecture-independent format files
# (the default in CLAUDE.md, tested in Milestone 3).

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
if [ $# -lt 3 ]; then
  echo "usage: $0 <support-files-dir> <host-tools-dir> <out-dir> [package...]" >&2
  exit 2
fi
sf=$(cd "$1" && pwd)
hosttools=$(cd "$2" && pwd)
mkdir -p "$3"
out=$(cd "$3" && pwd)
shift 3
if [ $# -eq 0 ]; then
  set -- scheme-basic
fi
formats=${TL_FORMATS:-pdftex pdflatex}

tl="$root/scripts/lib/tlpdb.py"
db="$sf/tlpkg/texlive.tlpdb"
tree="$out/tree"
logs="$out/logs"
rm -rf "${tree:?}" "${logs:?}" "${out:?}/tree.json" "${out:?}/home"
mkdir -p "$tree/tlpkg" "$logs" "$out/home"

step() {
  local name=$1
  shift
  echo "== $name"
  if ! "$@" > "$logs/$name.log" 2>&1; then
    echo "error: step '$name' failed; the end of its log:" >&2
    tail -n 40 "$logs/$name.log" >&2
    exit 1
  fi
  tail -n 3 "$logs/$name.log"
}

# 1. Packages.
list=$(python3 "$tl" resolve "$db" "$@")
mapfile -t packages <<< "$list"
echo "${#packages[@]} packages for: $*"
python3 "$tl" check "$db" "$sf/archive" "${packages[@]}"
with_files=()
for p in "${packages[@]}"; do
  if [ -f "$sf/archive/$p.tar.xz" ]; then
    with_files+=("$p")
  fi
done
step unpack python3 "$tl" unpack "$sf/archive" "$tree" "${with_files[@]}"
python3 "$tl" subset "$db" "${packages[@]}" > "$tree/tlpkg/texlive.tlpdb"
printf '%s\n' "${packages[@]}" > "$logs/packages.txt"

# Files the later steps need. For any that is missing, say which package the
# database puts it in, and whether that package is in the list.
missing=0
for need in tlpkg/TeXLive/TLUtils.pm texmf-dist/web2c/texmf.cnf texmf-dist/web2c/fmtutil-hdr.cnf \
  texmf-dist/web2c/updmap-hdr.cfg texmf-dist/tex/generic/config/language.us \
  texmf-dist/scripts/texlive/mktexlsr.pl texmf-dist/scripts/texlive/updmap.pl \
  texmf-dist/scripts/texlive/fmtutil.pl; do
  if [ ! -f "$tree/$need" ]; then
    # The database lists relocatable files as RELOC/..., the rest as they are.
    owner=$(awk -v f="$need" -v r="RELOC/${need#texmf-dist/}" \
      '/^name /{n=$2} $1 == f || $1 == r {print n}' "$db" | head -n 1)
    if grep -qx "${owner:-none}" "$logs/packages.txt"; then where="which is in the list"; else where="which is not in the list"; fi
    echo "error: the tree has no $need; the database puts it in package '${owner:-none}', $where" >&2
    if [ -f "$sf/archive/${owner:-none}.tar.xz" ]; then
      echo "  $owner's container holds:" >&2
      python3 "$tl" members "$sf/archive/$owner.tar.xz" | head -n 12 | sed 's/^/    /' >&2
    fi
    # Anything else with the same name, in case it has moved.
    awk -v b="/${need##*/}" '/^name /{n=$2} /^ / && index($1, b) && substr($1, length($1) - length(b) + 1) == b {print "  " n ": " $1}' "$db" | head -n 5 >&2
    missing=$((missing + 1))
  fi
done
if [ "$missing" -ne 0 ]; then
  echo "The tree's top level: $(cd "$tree" && echo *)" >&2
  echo "Files under tex/generic/config in the tree:" >&2
  find "$tree/texmf-dist/tex/generic/config" -maxdepth 1 -type f 2> /dev/null | sed "s#^$tree/##" >&2 || true
  exit 1
fi

# The host programs go where TeX Live keeps binaries, two levels below the
# root, so kpathsea finds the tree from them as it would in an installation.
bindir="$tree/bin/host"
mkdir -p "$bindir"
for program in kpsewhich pdftex; do
  if [ ! -x "$hosttools/bin/$program" ]; then
    echo "error: $hosttools/bin/$program not found; run scripts/build-host-tools.sh" >&2
    exit 1
  fi
  cp "$hosttools/bin/$program" "$bindir/$program"
done
# The program name selects the format: pdflatex runs pdftex with pdflatex.fmt.
ln -s pdftex "$bindir/pdflatex"

# Only the tree's own settings: nothing from the environment or a home tree.
unset TEXMFCNF TEXMFHOME TEXMFVAR TEXMFCONFIG TEXMFLOCAL TEXMFSYSVAR TEXMFSYSCONFIG \
  TEXINPUTS TFMFONTS T1FONTS ENCFONTS TEXFONTMAPS TEXFORMATS
export HOME="$out/home"
export PATH="$bindir:$PATH"
found=$(kpsewhich -var-value=TEXMFROOT)
if [ "$found" != "$tree" ]; then
  echo "error: kpsewhich places the tree at '$found', not $tree" >&2
  exit 1
fi

scripts="$tree/texmf-dist/scripts/texlive"
# 2. Generated configuration, with TeX Live's own code.
step postinstall perl "$root/scripts/lib/tl-postinstall.pl" "$tree"
# 3. Filename databases, font maps, formats.
step mktexlsr perl "$scripts/mktexlsr.pl" "$tree/texmf-dist" "$tree/texmf-var"
step updmap perl "$scripts/updmap.pl" --sys --nohash
step mktexlsr-maps perl "$scripts/mktexlsr.pl" "$tree/texmf-var"
for fmt in $formats; do
  step "fmtutil-$fmt" perl "$scripts/fmtutil.pl" --sys --byfmt "$fmt"
done
cp "$tree"/texmf-var/web2c/*/*.log "$logs/" 2> /dev/null || true
step mktexlsr-final perl "$scripts/mktexlsr.pl" "$tree/texmf-dist" "$tree/texmf-var"

# Record what was built.
python3 - "$tree" "$out/tree.json" "${packages[@]}" <<'EOF'
import json, os, sys
tree, dest, packages = sys.argv[1], sys.argv[2], sys.argv[3:]
formats = {}
web2c = os.path.join(tree, "texmf-var", "web2c")
for engine in sorted(os.listdir(web2c)) if os.path.isdir(web2c) else []:
    for name in sorted(os.listdir(os.path.join(web2c, engine))):
        if name.endswith(".fmt"):
            formats[name[:-4]] = {"engine": engine,
                                  "size": os.path.getsize(os.path.join(web2c, engine, name))}
files = size = 0
for base, dirs, names in os.walk(tree):
    if os.path.relpath(base, tree).split(os.sep)[0] == "bin":
        continue
    for name in names:
        files += 1
        size += os.path.getsize(os.path.join(base, name))
json.dump({"packages": packages, "formats": formats, "files": files, "bytes": size},
          open(dest, "w"), indent=2)
print(f"{len(packages)} packages, {files} files, {size // 1048576} MiB; formats: "
      + ", ".join(f"{k} ({v['size'] // 1024} KiB)" for k, v in formats.items()))
EOF
for fmt in $formats; do
  if ! compgen -G "$tree/texmf-var/web2c/*/$fmt.fmt" > /dev/null; then
    echo "error: $fmt.fmt was not made" >&2
    exit 1
  fi
done
echo "Tree: $tree"
