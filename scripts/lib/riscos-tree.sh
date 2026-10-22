# shellcheck shell=bash
# Shell functions for copying a TeX Live tree into a RISC OS package, shared
# by scripts/package-pdftex-kit.sh and scripts/package-release.sh. Source this
# file; it defines functions only.
#
# In the package, files carry ,xxx filetype suffixes (rozip.py turns them into
# RISC OS filetypes): Text (fff) for files people read, PDF (adf), and Data
# (ffd) for the rest. Each texmf tree gets an ls-R listing it as kpathsea sees
# it through UnixLib: Unix-style names, without the suffixes.

# riscos_filetype <path>: the filetype, as three hex digits, for a tree file.
riscos_filetype() {
  case $1 in
    *.tex | *.sty | *.cls | *.clo | *.cfg | *.def | *.fd | *.ldf | *.ltx | *.ini | \
      *.cnf | *.map | *.enc | *.dat | *.lua | *.tcx | *.txt | *.md | *.pl | *.lco | \
      *README* | *readme*) echo fff ;;
    *.pdf) echo adf ;;
    *) echo ffd ;;
  esac
}

# tree_file_list <tree> <full|DOCS-DIR>: print the files to package, relative
# to <tree>. "full" lists texmf-dist and texmf-var whole; a directory instead
# lists only the files its -recorder lists (*.fls, from
# scripts/test-documents.sh) show the test documents reading, plus texmf.cnf.
# ls-R files are left out: packages get their own.
tree_file_list() {
  local tree=$1 what=$2
  if [ "$what" = full ]; then
    (cd "$tree" && find texmf-dist texmf-var -type f ! -name ls-R | LC_ALL=C sort)
  else
    {
      sed -n "s#^INPUT $tree/##p" "$what"/*.fls
      echo texmf-dist/web2c/texmf.cnf
    } | grep -v '/ls-R$' | LC_ALL=C sort -u
  fi
}

# copy_tree_files <tree> <list-file> <dest>: copy each listed file from
# <tree> to <dest>, adding its filetype suffix. Prints the number copied.
copy_tree_files() {
  local tree=$1 list=$2 dest=$3 path count=0
  while IFS= read -r path; do
    if [ ! -f "$tree/$path" ]; then
      echo "error: $path is not in the tree" >&2
      return 1
    fi
    mkdir -p "$dest/$(dirname "$path")"
    cp "$tree/$path" "$dest/$path,$(riscos_filetype "$path")"
    count=$((count + 1))
  done < "$list"
  echo "$count"
}

# write_ls_r <dest>: write ls-R,fff in <dest>/texmf-dist and <dest>/texmf-var
# (where present), listing each as kpathsea sees it through UnixLib. The file
# lists itself, as mktexlsr's ls-R does.
write_ls_r() {
  local dest=$1 texmf tmp
  tmp=$(mktemp)
  for texmf in texmf-dist texmf-var; do
    [ -d "$dest/$texmf" ] || continue
    : > "$dest/$texmf/ls-R,fff"
    (
      cd "$dest/$texmf" || exit 1
      echo "% ls-R -- filename database for kpathsea; do not change this line."
      find . -type d | LC_ALL=C sort | while read -r d; do
        echo
        if [ "$d" = . ]; then echo "./:"; else echo "$d:"; fi
        find "$d" -mindepth 1 -maxdepth 1 | sed -e 's#.*/##' -e 's#,[0-9a-f]\{3\}$##' | LC_ALL=C sort
      done
    ) > "$tmp"
    cp "$tmp" "$dest/$texmf/ls-R,fff"
  done
  rm -f "$tmp"
}

# check_riscos_names <dir>: report names that may not survive on a RISC OS
# filing system: characters special in RISC OS paths, names over 255
# characters, and names in one directory that differ only in case (FileCore
# ignores case). Reports; does not fail.
check_riscos_names() {
  python3 - "$1" <<'EOF'
import os, re, sys
top = sys.argv[1]
special = re.compile(r'[$&@^%#*\\:"|<>\s]')
problems = 0
for base, dirs, files in os.walk(top):
    seen = {}
    for name in dirs + files:
        plain = re.sub(r",[0-9a-f]{3}$", "", name)
        rel = os.path.relpath(os.path.join(base, plain), top)
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
}
