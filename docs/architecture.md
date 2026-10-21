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
- **Source archive pins:** GCCSDK downloads GCC, binutils, GMP, MPFR, MPC and the autotools from mirrors without checking them. After the first build, its list of checksums is committed as `toolchain/gccsdk/source-checksums.sha256`; later builds fail if any download differs. Until that file exists, a build prints a warning and the list to commit.
- **Base image:** `ubuntu:24.04`, resolved to a digest at build time and recorded. Setting `toolchain.image.base_image_digest` in the manifest pins it.

#### Deviation from the Milestone 1 issue

The issue text specified a manually triggered toolchain workflow. `toolchain.yml` is instead also a reusable workflow that `build.yml` calls first. It costs a few seconds when the image exists, and it means a change to the toolchain pins is built and tested in the same pull request rather than needing a separate manual step. The rule that ordinary builds never rebuild GCCSDK still holds: the expensive job runs only when the tag is new.

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

## Decision records

| Decision | Status | Evidence |
|---|---|---|
| Compiler | Open (Milestone 1). GCC 4.7.4 (GCCSDK release 6) is the only compiler in the GCCSDK repository. The GCC 8 and 10 work mentioned in community sources was not found there; finding it is the next step if C++17 is needed. | This document |
| C++11 and C++17 support | Open (Milestone 1): measured by the probes in CI | CI job summary, once run |
| Floating-point variant | Open (Milestone 1): decided from Gate 1 results | Gate 1 report |
| Unaligned-access flags | Open (Milestone 1): decided from Gate 1 results | Gate 1 report |
| Emulator testing | Open (Milestone 1) | — |
