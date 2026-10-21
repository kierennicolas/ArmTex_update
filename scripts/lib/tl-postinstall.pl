#!/usr/bin/env perl
# Write a TeX Live tree's generated configuration files from its package
# database, with TeX Live's own code, as install-tl does after unpacking the
# packages.
#
# Usage: perl scripts/lib/tl-postinstall.pl ROOT
#
# ROOT/tlpkg/texlive.tlpdb lists the installed packages, and ROOT/tlpkg/TeXLive
# holds TeX Live's Perl modules (from the texlive.infra package). Writes:
#
#   ROOT/texmf-var/tex/generic/config/language.dat     (pdfTeX, e-TeX formats)
#   ROOT/texmf-var/tex/generic/config/language.def     (plain e-TeX formats)
#   ROOT/texmf-var/tex/generic/config/language.dat.lua (LuaTeX formats)
#   ROOT/texmf-dist/web2c/fmtutil.cnf                  (formats to build)
#   ROOT/texmf-dist/web2c/updmap.cfg                   (font maps)
#
# These are the same files, at the same places, as install-tl writes. The
# create_* functions run kpsewhich, so the tree's own kpsewhich must come
# first on PATH.

use strict;
use warnings;

my $root = shift @ARGV;
die "usage: $0 ROOT\n" if !defined($root) || @ARGV;
die "$0: $root/tlpkg/texlive.tlpdb not found\n" unless -r "$root/tlpkg/texlive.tlpdb";
die "$0: $root/tlpkg/TeXLive not found (is texlive.infra installed?)\n"
  unless -d "$root/tlpkg/TeXLive";

unshift(@INC, "$root/tlpkg");
require TeXLive::TLPDB;
require TeXLive::TLUtils;

my $tlpdb = TeXLive::TLPDB->new(root => $root)
  or die "$0: cannot read $root/tlpkg/texlive.tlpdb\n";
printf "%d packages in %s/tlpkg/texlive.tlpdb\n", scalar($tlpdb->list_packages), $root;

my $config = "$root/texmf-var/tex/generic/config";
TeXLive::TLUtils::mkdirhier($config);
TeXLive::TLUtils::create_language_dat($tlpdb, "$config/language.dat", undef);
TeXLive::TLUtils::create_language_def($tlpdb, "$config/language.def", undef);
TeXLive::TLUtils::create_language_lua($tlpdb, "$config/language.dat.lua", undef);
TeXLive::TLUtils::create_fmtutil($tlpdb, "$root/texmf-dist/web2c/fmtutil.cnf");
TeXLive::TLUtils::create_updmap($tlpdb, "$root/texmf-dist/web2c/updmap.cfg");

for my $file ("$config/language.dat", "$config/language.def", "$config/language.dat.lua",
              "$root/texmf-dist/web2c/fmtutil.cnf", "$root/texmf-dist/web2c/updmap.cfg") {
  die "$0: $file was not written\n" unless -s $file;
  print "wrote $file\n";
}
