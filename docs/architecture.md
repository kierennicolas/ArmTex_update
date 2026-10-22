# Architecture

How the port is put together, and the record of decisions made along the way. Open decisions and the milestone that settles each are listed in [`roadmap.md`](roadmap.md).

## Layers

| Layer | Responsibility | Where |
|---|---|---|
| TeX Live core | Engines, libraries, macros, fonts, formats, utilities | Pinned upstream sources plus `patches/texlive/` |
| RISC OS integration | Filename and environment adaptation, packaging, the `!TeXLive` application | `riscos/` |
| Build infrastructure | Toolchain, cross-compilation, checks, CI | `toolchain/`, `scripts/`, `.github/workflows/` |

TeX Live changes every year. Keeping RISC OS code out of the upstream tree, apart from small, documented patches, is what makes moving to TeX Live 2027 a matter of refreshing pins.

## Toolchain

### What is used

GCCSDK, from [riscos-dot-info/gccsdk](https://github.com/riscos-dot-info/gccsdk), pinned by commit in `upstream/manifest.json`. That repository's `main` branch builds GCC 4.7.4 and binutils 2.24 as GCCSDK release 6 (`gcc4/setup-gccsdk-params`), for the `arm-unknown-riscos` target with UnixLib as the C library. Its other branches are older releases and developer branches; the newest compiler work there is a `developers/joty/gcc48` branch.

GCCSDK's own CI (`.github/workflows/build.yaml` in that repository) builds the cross compiler on `ubuntu-24.04`. Our build follows the same steps and dependency list.

### How the image is built

`.github/workflows/toolchain.yml` runs `scripts/build-toolchain.sh` on an Ubuntu 24.04 runner, then packs the installed toolchain into a container image based on the same Ubuntu release and pushes it to GitHub Container Registry.

- **Tag:** `<first 12 of the GCCSDK commit>-<first 12 of the recipe hash>`, computed by `scripts/toolchain-image.sh`. The recipe hash covers the manifest's `toolchain` section, `toolchain/gccsdk/Dockerfile` and `scripts/build-toolchain.sh`, so changing any of them produces a new tag.
- **Never rebuilt in place:** if the tag already exists, the workflow skips the build. A rebuild needs a manual run with `force`.
- **Provenance:** each build uploads a record (`toolchain-build-record` artifact) with the compiler version line, build host, build time, the SHA-256 of the toolchain tarball, and the SHA-256 of every source archive GCCSDK downloaded. The job summary shows the image digest and the base image digest.
- **Source archive pins:** GCCSDK downloads binutils, GMP, MPFR, MPC, PPL, CLooG and the autotools from mirrors without checking them. The checksums from the first successful build are committed as `toolchain/gccsdk/source-checksums.sha256`; later builds fail if any download differs.
- **GCC source pin:** GCCSDK does not download a GCC release archive; it checks out the `gcc-4_7-branch` from GCC's Subversion archive (`GCC_USE_SCM=yes` in `gcc4/Makefile`). That branch is closed, but the build records the revision it got, and fails if it differs from `toolchain/gccsdk/gcc-svn-revision` once that file is committed.
- **Base image:** `ubuntu:24.04`, pinned by the digest in `toolchain.image.base_image_digest`. The build runner itself (GitHub's `ubuntu-24.04` image) cannot be pinned; its compiler version is in the provenance record.
- **First image:** `ghcr.io/kierennicolas/armtex_update/gccsdk:33cb00db1e0a-c69b7515511b`, digest `sha256:b6a7f94e24d972040e79cada02e37a4cbfdecb39fe3aefe0abc626e006be5017`, built in 21 minutes with host GCC 13.3.0 ([run 39643442078](https://github.com/kierennicolas/ArmTex_update/actions/runs/39643442078)). An earlier attempt with the same recipe failed after seven minutes; its log could not be read, and the identical rerun succeeded, so the cause is recorded as unknown, probably a download.

#### Deviation from the Milestone 1 issue

The issue text specified a manually triggered toolchain workflow. `toolchain.yml` is instead also a reusable workflow that `build.yml` calls first. It costs a few seconds when the image exists, and it means a change to the toolchain pins is built and tested in the same pull request rather than needing a separate manual step. The rule that ordinary builds never rebuild GCCSDK still holds: the expensive job runs only when the tag is new.

## TeX Live source

The source is the `texlive-2026.1` tag of the [TeX-Live/texlive-source](https://github.com/TeX-Live/texlive-source) mirror, pinned by commit in `upstream/manifest.json`. It is the 2026 release (Subversion r78235) plus the dvipdfmx file-name quoting fix of 17 March 2026 (r78399), the newest update within the 2026 release. The mirror's `branch2026` points at the same fix; `trunk` already carries post-2026 library updates and is not used.

`scripts/fetch-upstream.sh texlive-source <dir>` fetches exactly that commit (GitHub serves a commit by its hash) at depth 1 and checks it.

Library versions in this source, from `libs/README`: zlib 1.3.2, libpng 1.6.55, xpdf 4.06, FreeType 2.14.1, HarfBuzz 12.3.2, graphite2 1.3.14, ICU 78.2, Lua 5.3.6, pplib 2.05.0.

## Support files

Macros, fonts and configuration come from the TeX Live 2026 DVD image, `texlive2026-20260301.iso` (6.3 GB), which holds the whole 2026 release as it was on 1 March 2026: the package database `tlpkg/texlive.tlpdb` and every package as `archive/<package>.tar.xz`.

How the pin works:

- `upstream/manifest.json` pins the image's size, SHA-256 and SHA-512, and the SHA-256 of the database inside it.
- TeX Live publishes the image's SHA-512 in a file signed with its own key. `scripts/verify-iso-signature.sh` checks that signature against the key's fingerprint, also pinned, and that the signed value is the pinned one. It needs gpg, so it runs on the CI runner.
- The database lists every package with the size and SHA-512 of its container, so the pins cover every support file.
- `scripts/fetch-upstream.sh support-files <dir> [package...]` takes the database and the named packages (with their dependencies) out of the image with `scripts/lib/iso9660.py`, a small reader for ISO 9660 with Rock Ridge and Joliet names, so nothing is mounted, and checks the database against its pin and each package against the database.
- By default the image is **read in part** from a mirror, with HTTP range requests: only the directory entries, the database and the packages asked for are fetched (tens of MB, not 6.3 GB). The mirror must serve the image at its pinned size. Every byte used is checked, as above; what cannot be checked without downloading the whole image is the image's own SHA-256 and SHA-512, which is why the database has a pin of its own. `SUPPORT_ISO_MODE=full`, or a mirror without range support, downloads the whole image and checks every pin, as was done to establish them (run 39681279779). CI also caches `<dir>`, but caches are not shared between pull-request branches, so each new branch needed the whole image when only full downloads were possible.
- `scripts/lib/tlpdb.py resolve` lists a package and everything it depends on, leaving out the per-platform binaries (`.ARCH`), which this project builds itself.

The CI job `support-files` runs all of this on every build. Milestone 3 builds the texmf tree from these packages.

**Why the image and not a dated tlnet snapshot.** `CLAUDE.md` allows either. The only archive of dated tlnet snapshots, at texlive.info, now answers automated downloads with a bot-check page instead of the file (an HTML page titled "Oh noes!", [CI job 119495856939](https://github.com/kierennicolas/ArmTex_update/actions/runs/39678137603/job/119495856939)), and getting round that would not be appropriate. The image is fixed, signed and mirrored across CTAN. Its size (6.3 GB) does not matter much, since the build reads only the parts it needs (below).

**When TeX Live 2027 is released** (about March 2027), CTAN's `Images` directory will switch to the 2027 image. The 2026 image stays available from TeX Live's historic archive (tug.org/historic); its URL then needs adding to the manifest, with the same pins.

## Cross-building TeX Live

Two stages, both in the `texlive` job of `build.yml`, inside the toolchain image:

1. **Host tools** (`scripts/build-host-tools.sh`): a native build of tangle, ctangle, tie and otangle, which web2c runs on the build machine when cross-compiling, plus kpsewhich and pdfTeX for preparing texmf trees and formats later. The result is cached on the TeX Live commit, the script and the toolchain image.
2. **Cross build** (`scripts/build-texlive.sh`): configures the whole tree for `arm-unknown-riscos` with `--disable-all-pkgs --enable-pdftex --enable-luahbtex`, runs `make -k` so one run shows every failure, then builds each library and program on its own to get a clean log for it. Answers for configure tests that cannot run when cross-compiling go in `riscos/compatibility/config.site`, each with its reason.

Each component is either **required** for Milestone 2 (zlib, libpng, xpdf, kpathsea, kpsewhich) or a **probe** for later milestones (pdfTeX, FreeType, pplib, zziplib, Lua, graphite2, HarfBuzz, GMP, MPFR). `results.json` records each one's outcome and first error.

### What the first cross builds taught

Each of these cost a CI run to find; the fix is in the scripts.

- **Static linking:** GCCSDK links against shared libraries by default, and libtool does not pass `-static` through from `CC` or `LDFLAGS`. `build-texlive.sh` puts wrappers for `arm-unknown-riscos-gcc` and `-g++` first on `PATH` that always add `-static`.
- **C++ standard:** GCC 4.7 compiles C++98 unless told otherwise, and TeX Live's configure does not add a flag, so xpdf failed inside `<atomic>`. `CXX` includes `-std=gnu++11`; with it, xpdf 4.06 builds.
- **Timestamps:** a git checkout writes files in no particular order, so generated files (web2c's parser, the Info manuals) can look older than their sources, and make tries to regenerate them with bison or makeinfo. `fetch-upstream.sh` gives every file the commit's timestamp.
- **Cross tools:** passing `AR`, `RANLIB` and `STRIP` to configure also reaches web2c's helper programs, which are built for the build machine, and their library ended up without a symbol index. configure finds the cross tools from `--host` without them.
- **Container shell:** steps in a container job run under `sh` unless told otherwise, without `pipefail`; the build job sets `bash`.

### Findings from the emulator runs of kpsewhich

- `SELFAUTOLOC`, `SELFAUTOPARENT` and `TEXMFDIST` come out right, as Unix-style paths, so kpathsea's self-location works under UnixLib and TeX Live's own `texmf.cnf` needs no changes.
- Looking for its `ls-R` database, kpathsea finds both `ls-r` and `ls-R`, because RISC OS filing systems ignore case. It reads the same file twice; harmless, but worth knowing if lookups ever look duplicated.

## The texmf tree and formats (Milestone 3)

`scripts/build-texmf-tree.sh` does on the build machine what install-tl does after unpacking packages, with TeX Live's own code wherever TeX Live has it:

1. Resolve scheme-basic's packages from the pinned database and unpack their containers. A relocatable package's container holds its files relative to `texmf-dist` (the database's file list writes them as `RELOC/...`); its `tlpkg/tlpobj` entry belongs at the root. Write the installation's `tlpkg/texlive.tlpdb` from the same records.
2. `scripts/lib/tl-postinstall.pl` calls TeX Live's `TLUtils::create_language_dat`, `_def`, `_lua`, `create_fmtutil` and `create_updmap`, from the tree's own `texlive.infra`, so `language.dat`, `fmtutil.cnf` and `updmap.cfg` are what install-tl would write.
3. Run the tree's `mktexlsr`, `updmap-sys` and `fmtutil-sys` with the host kpsewhich and pdfTeX copied into `bin/host/`, so kpathsea finds the tree from them exactly as an installation's binaries would.

**Formats.** The default in `CLAUDE.md` is formats made on the build machine. The emulator results support it so far: the RISC OS pdfTeX loads the host-made `pdftex` and `pdflatex` formats and produces the same PDFs as the host, apart from `/ID`. Gate 3 decides it on hardware. The risk noted in Milestone 1 (soft-float `double` in FPA word order) has not shown up in the output. Glue ratios, kept in boxes stored in a format, are the floating-point values a format can hold; these formats probably hold none that are non-zero, but that is an inference from the identical PDFs, not a check of the format files.

**Reproducible PDFs.** The test documents are compiled with `SOURCE_DATE_EPOCH` and `FORCE_SOURCE_DATE=1`, on the host and in the kits, so dates match. pdfTeX's `/ID` hashes the working directory and output file name as well as the date, so it differs between machines; comparisons blank it.

## Executables

The default (to be confirmed at Gate 1): programs are linked statically with UnixLib and converted from ELF to AIF (filetype &FF8) with GCCSDK's `elf2aif`.

`scripts/check-binaries.sh` checks every output:

- **ELF**, before conversion: 32-bit, little-endian, ARM, an executable, no program interpreter or dynamic section, and GCCSDK's compiler tag in `.comment`.
- **AIF**, after conversion: the `,ff8` suffix and the header checks in `scripts/lib/aifcheck.py`, written against the AIF layout in the RISC OS PRM and the header that `elf2aif` writes (`gcc4/riscos/elf2aif/src/elf2aif.c`): no compression, `SWI OS_Exit` at offset &10, 32-bit address mode, image base &8000, area sizes that fit the file, and an entry branch into the read-only area.

`tests/scripts/test-check-binaries.sh` damages copies of real build output (wrong exit instruction, 26-bit flag, wrong base, no entry branch, truncation, missing suffix, wrong file kind) and confirms each is rejected.

### Runtime module

UnixLib programs need the SharedUnixLibrary module. The startup code (`libunixlib/sys/_syslib.s`) checks for it itself and tries `System:Modules.SharedULib`. The minimum version depends on the floating-point variant: 1.07 for soft-float, 1.13 for VFP, 1.16 for EABI builds. The test kit asks for 1.13.

## Code-generation variants

GCCSDK builds multilibs for UnixLib with soft-float (the default), and with `-mfloat-abi=softfp` plus `-mfpu=vfp` or `-mfpu=neon` (`gcc/config/arm/t-arm-riscos-elf`). Hard-float is not available, because it is incompatible with the FPA convention (`gcc4/STATUS-BRANCH`).

Milestone 1 builds each test program in these variants so Gate 1 can compare them on Titanium:

| Variant | Flags | Purpose |
|---|---|---|
| `soft` | none | GCCSDK's default; runs on any RISC OS 5 machine |
| `vfp` | `-mfpu=vfp -mfloat-abi=softfp` | Hardware floating point; GCCSDK defaults the CPU to ARM1176 for this |
| `a15` | as `vfp`, plus `-mcpu=cortex-a15` | Code generated for Titanium's processor |
| `a15noua` | as `a15`, plus `-mno-unaligned-access` | Only for the unaligned-access test |

## Findings from the GCCSDK sources that matter later

Recorded here so later milestones do not have to rediscover them. Each is from reading the pinned sources, not from running anything on RISC OS.

- **Suffix swapping:** UnixLib's default suffix list is `c:cc:f:h:i:ii:l:o:p:s:y` (`libunixlib/common/riscosify.c`). None of TeX's extensions are on it, so by default `article.cls` maps to `article/cls`. The planned default (suffix swapping off for the texmf tree) matches that, but setting `__RISCOSIFY_NO_SUFFIX` explicitly protects against a user's `UnixEnv$...$sfix` setting. The `hello` test prints how UnixLib translates a set of TeX-style names, with and without suffix swapping, for Milestone 2.
- **Environment variables:** UnixLib's `getenv` reads names containing `$` straight from RISC OS system variables, and other names from the program's private environment, which a program started from the command line fills from a subset of the RISC OS variables (`libunixlib/unix/ul_getenv.c`, `unix/unix.c`). kpathsea reads names such as `TEXMFCNF`, so whether `!Boot` can set them as ordinary system variables matters for Milestone 2. The `hello` test reports what a `$`-less variable set by an Obey file looks like.
- **Filetypes of new files:** by default UnixLib sets a new file's type from its extension via MimeMap (`__RISCOSIFY_FILETYPE_NOT_SET` is off by default), so `output.pdf` should get the PDF filetype without extra work.
- **C++ library configuration:** GCC is configured with `--disable-wchar_t`, `--disable-c-mbchar` and `--disable-tls` (`gcc4/Makefile`). Wide-character support in libstdc++ and `thread_local` are therefore not expected to work, which may matter for ICU and HarfBuzz. The C++ probes measure this.

## Packaging

RISC OS needs filetypes, which ordinary zip files do not carry. `riscos/packaging/rozip.py` builds zip files with Info-ZIP's Acorn extra field (ID &4341, "ARC0"), which RISC OS unzip tools use to restore filetypes. In the repository a file's type is its `,xxx` suffix; the tool strips the suffix and records the type. Archives are reproducible: entries are sorted and timestamps come from the commit time.

The test kit is uploaded with `archive: false`, so the artifact is the RISC OS zip itself rather than a zip wrapped in another zip.

## The !TeXLive application (provisional layout)

Milestone 3 settles the installation layout provisionally; Milestone 8 settles it finally, with the desktop front end and Choices.

```
!TeXLive
  !Boot, !Run          Obey files: define the commands (below)
  !Help                how to install and use it
  Resources.Commands   the command definitions, run by !Boot and !Run
  BuildInfo            commit, pins and formats of this build
  LICENSE/TL, LICENSE/CTAN
  bin.riscos           pdftex, kpsewhich (AIF)
  texmf-dist           TeX Live's tree (scheme-basic), runfiles only
  texmf-var            made on the build machine: formats, font maps, language files
```

- **Everything inside the application.** It is TeX Live's own layout, with `!TeXLive` as the installation's root: kpathsea works out `SELFAUTOPARENT` from the program's location, and TeX Live's `texmf.cnf` finds `texmf-dist` and `texmf-var` from there unchanged. Nothing depends on where `!TeXLive` is, and moving it needs no reconfiguration (Gate 2 tests this for kpsewhich).
- **Commands.** `!Boot` (run by the Filer when it first sees the application) and `!Run` (a double-click) set `TeXLive$Dir` and the aliases `pdflatex`, `pdftex` and `kpsewhich`. Each alias runs a program in `bin.riscos`; `pdflatex` is `pdftex -progname=pdflatex`, which loads the `pdflatex` format as the program name would, so the program is not shipped twice. `!Boot` leaves the aliases alone if another copy set them up first; `!Run` always takes over.
- **SharedUnixLibrary** is loaded by the programs' own start-up code when needed, so the aliases do not load it.
- **Not yet decided (Milestone 8):** where a user's own tree (`TEXMFHOME`) and TeX Live's per-user files (`TEXMFVAR`, `TEXMFCONFIG`) go: Choices is the RISC OS place for them. For now they are TeX Live's defaults under `HOME`, which nothing in scheme-basic with pdfTeX writes to.
- **Documentation** (TeX Live's `doc` containers) is left out to keep the download small.

`scripts/package-release.sh` builds the application from `riscos/app/!TeXLive` (the Obey files and help), the cross-compiled programs and the tree, and packages it as `TeXLive-2026-dev-<commit>.zip`.

## Decision records

| Decision | Status | Evidence |
|---|---|---|
| Compiler | Provisional: GCC 4.7.4 (GCCSDK release 6), the only compiler in the GCCSDK repository. It builds all the Milestone 1 test programs. Its C++ support is the limiting factor (below). The GCC 8 and 10 work mentioned in community sources was not found in that repository; finding it is the next step if C++17 is needed. | [CI run 39647972451](https://github.com/kierennicolas/ArmTex_update/actions/runs/39647972451) |
| C++11 | **Partial.** Supported: the core features in `cxx11.cc` (lambdas, `auto`, smart pointers, move semantics, exceptions, variadic templates, `constexpr`, `enum class`, `override`), `std::atomic`, `std::mutex`, user-defined literals. Not supported: `alignas`, the `[[...]]` attribute syntax, inheriting constructors, ref-qualified member functions, `thread_local`, `std::to_string`. | C++ probes, same run |
| C++14 and C++17 | **Not supported**: the compiler rejects `-std=c++14`/`c++1y` and `-std=c++17`/`c++1z`. The bundled ICU (78.x) needs C++17, so XeTeX and bibtexu cannot be built with this compiler. Milestone 7 is blocked unless a newer compiler is found. | C++ probes, same run |
| Floating-point variant | Open: decided from Gate 1 results. All variants build. | Gate 1 report |
| Unaligned-access flags | Open: decided from Gate 1 results | Gate 1 report |
| Installation layout | **Provisional (Milestone 3):** everything inside `!TeXLive`, laid out as a TeX Live installation, with commands defined by `!Boot` and `!Run`; see [the !TeXLive application](#the-texlive-application-provisional-layout). User trees and Choices are for Milestone 8. | [Run 39838947779](https://github.com/kierennicolas/ArmTex_update/actions/runs/39838947779): under the emulator the commands work and the PDFs match the host's apart from `/ID`. Hardware: not yet |
| Emulator testing | **Useful for soft-float builds only.** With the toolchain's SharedUnixLibrary module (`cross/bin/arm-unknown-riscos-sul`) uploaded alongside, the soft-float test programs run and pass on build.riscos.online. VFP builds cannot run there: Pyromaniac has no VFPSupport module. | [39652781660](https://github.com/kierennicolas/ArmTex_update/actions/runs/39652781660) |

### What the emulator results mean

- **Formats:** the soft-float build stores a `double` in FPA word order. Web2c's shareable format files are written for IEEE little-endian or big-endian machines, so a format generated on the Linux host might load wrongly in a soft-float build wherever it holds floating-point values (glue ratios). A VFP build should not have this problem. This bears on both the floating-point decision (Gate 1) and the format decision (Milestone 3).
- **Filenames:** the translations match the planned default. TeX's extensions are not on UnixLib's suffix list, so `article.cls` becomes `article/cls` either way.

### What the C++ results mean for later milestones

- **pdfTeX (Milestone 3)** links xpdf 4.06, which is C++. Whether that code avoids the missing features is unknown until it is compiled; Milestone 2 should try it early.
- **LuaHBTeX (Milestone 6)** needs HarfBuzz 14.x. HarfBuzz requires C++11, and modern releases may use features GCC 4.7 lacks. Also to be tried early in Milestone 2.
- **XeTeX (Milestone 7)** is blocked with this compiler, as the precondition in the roadmap anticipated.
