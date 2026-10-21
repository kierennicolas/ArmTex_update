# Progress

**Current milestones:** M1 (waiting for Gate 1, [#3](https://github.com/kierennicolas/ArmTex_update/issues/3)), M2 (waiting for Gate 2, [#14](https://github.com/kierennicolas/ArmTex_update/issues/14)), M3 — pdfTeX (host side done and Emulator-tested; waiting for Gate 3, [#17](https://github.com/kierennicolas/ArmTex_update/issues/17)).

Status levels are defined in [`CLAUDE.md`](../CLAUDE.md#status-levels). "Local" notes describe checks run on a development machine; they do not count towards a status level.

Reference CI runs: [39648204620](https://github.com/kierennicolas/ArmTex_update/actions/runs/39648204620) (toolchain image rebuilt from the pinned inputs; all jobs green) and [39652781660](https://github.com/kierennicolas/ArmTex_update/actions/runs/39652781660) (latest; all jobs green, emulator results below).

## Components

| Component | Status | Evidence and notes |
|---|---|---|
| Toolchain image | Built in CI | `gccsdk:33cb00db1e0a-c0780fe544e6`, digest `sha256:85dd9b88cd833bddad5642af47fbd79fe232cfad7b244aa903c94ed86ff9a678`, 21 minutes. The nine downloaded source archives matched `toolchain/gccsdk/source-checksums.sha256`; GCC came from `gcc-4_7-branch@211571`, now pinned in `toolchain/gccsdk/gcc-svn-revision` |
| Test programs: `hello`, `float`, `unaligned`, `cxx11` | Cross-compiled | All four variants (`soft`, `vfp`, `a15`, plus `a15noua` for `unaligned`) build and convert to AIF |
| `cxx17` probe | Does not compile | GCC 4.7 rejects `-std=c++17` and `-std=c++1z`, as expected |
| C++ feature probes | Measured | 3 of 9 C++11 probes compile; no C++14 or C++17 probe does. Details in [`architecture.md`](architecture.md#decision-records) |
| Binary checks (`check-binaries.sh`, `aifcheck.py`) | Host-tested | Every cross-compiled ELF and AIF passes; damaged copies, host executables and wrong file kinds are rejected |
| RISC OS zip tool (`rozip.py`) | Host-tested | Unit tests pass in CI; the kit's archive is verified against its tree and by `zipinfo` |
| Test kit (`package-testkit.sh`) | Host-tested | Artifact `TLTest-<commit>.zip`, about 1.8 MB, 16 files |
| Soft-float `hello`, `float`, `cxx11`, `unaligned` | Emulator-tested | Every check passes under RISC OS Pyromaniac on build.riscos.online, with the toolchain's own SharedUnixLibrary module uploaded alongside, in [39652781660](https://github.com/kierennicolas/ArmTex_update/actions/runs/39652781660). Indicative only |
| VFP and Cortex-A15 variants | Cross-compiled | Cannot run in the emulator: it has no VFPSupport module |
| Emulator evaluation (`run-emulator.sh`) | Working | Runs every soft-float program; stops at the first VFP one |
| Claude Code workflow (`claude.yml`) | Implemented | Needs the GitHub app and a secret; see [`building.md`](building.md#setting-up-the-claude-code-workflow) |

## Milestone 2 components

Reference CI runs: [39670666067](https://github.com/kierennicolas/ArmTex_update/actions/runs/39670666067), the first with every job green; [39672805395](https://github.com/kierennicolas/ArmTex_update/actions/runs/39672805395), the first in which pdftex cross-compiles; and [39674828080](https://github.com/kierennicolas/ArmTex_update/actions/runs/39674828080), the first with the Gate 2 tree check and the Gate 2 artifact.

| Component | Status | Evidence and notes |
|---|---|---|
| TeX Live source pin (`texlive-2026.1`, commit `6a300188`) | Implemented | Fetched and checked in every CI run |
| Support-file pin (TL2026 image of 1 March 2026) | Host-tested | [Run 39681991714](https://github.com/kierennicolas/ArmTex_update/actions/runs/39681991714): the image's SHA-512 is signed by TeX Live's key and matches the download; `plain`, `latex`, `cm` and `amsfonts` come out of it with the SHA-512 the database gives. `scheme-basic` is 116 packages, 19 MiB of containers ([#15](https://github.com/kierennicolas/ArmTex_update/pull/15)) |
| Host tools: tangle, ctangle, tie, otangle, kpsewhich, pdftex | Host-tested | Native build in CI, cached between runs. The cross build uses tangle, ctangle, tie and otangle; the kit check uses kpsewhich |
| Cross-configure of the whole tree for `arm-unknown-riscos` | Cross-compiled | configure succeeds; no `config.site` answers needed so far |
| zlib, libpng, xpdf, kpathsea | Cross-compiled | xpdf 4.06 builds with GCC 4.7 in C++11 mode |
| kpsewhich | Cross-compiled; Emulator-tested | Statically linked, passes the binary checks. Under the emulator it finds `texmf.cnf`, `article.cls`, `plain.tex`, `cmr10.tfm` and `cmr10.pfb` through `ls-R`, with `SELFAUTOPARENT` set to the kit's directory |
| Probes: FreeType, pplib, zziplib, Lua 5.3, GMP, MPFR | Cross-compiled | Libraries only |
| Probes: graphite2, HarfBuzz | Configure fails | Both stop at configure's C++11 test: GCC 4.7 rejects one of its constructs (a `static constexpr auto` member of a variadic class template, "has no initializer"). Whether the libraries themselves compile is untested; see Milestone 6 ([#8](https://github.com/kierennicolas/ArmTex_update/issues/8)) |
| Probe: pdftex | Cross-compiled | Links statically, converts to AIF and passes the binary checks. Not yet run anywhere: it needs a texmf tree and format files (Milestone 3) |
| Gate 2 kit (`package-kpse-kit.sh`) | Host-tested | [39674828080](https://github.com/kierennicolas/ArmTex_update/actions/runs/39674828080): artifact `TLKpse-327a1e4ce122.zip`; `test-kpse-kit.sh` finds every file through the tree's `ls-R` with the native kpsewhich, in place and moved; the emulator run gives the same answers as before |

## Milestone 3 components

Reference CI runs: [39693205158](https://github.com/kierennicolas/ArmTex_update/actions/runs/39693205158), the first in which the emulator's PDFs match the host's, and [39694425014](https://github.com/kierennicolas/ArmTex_update/actions/runs/39694425014), which made the Gate 3 artifact; all jobs green in both ([#16](https://github.com/kierennicolas/ArmTex_update/pull/16)).

| Component | Status | Evidence and notes |
|---|---|---|
| texmf tree (`build-texmf-tree.sh`) | Host-tested | scheme-basic from the pinned image: 116 packages, 5853 files, 82 MiB. Configuration written by TeX Live's own TLUtils; `mktexlsr`, `updmap-sys` and `fmtutil-sys` from the tree, run with the host tools |
| Formats `pdftex` and `pdflatex` | Host-tested | Made by the host pdfTeX from the pinned source: 173 KiB and 2232 KiB |
| Test documents on the host (`test-documents.sh`) | Host-tested | `storytest.tex` and `test.tex` each give one page, reproducibly (two runs, identical PDFs) |
| pdftex on RISC OS | Cross-compiled; Emulator-tested | Under RISC OS Pyromaniac, loads the host-made formats and typesets both documents. The PDFs are identical to the host's apart from `/ID`, which hashes the working directory. Indicative only: soft-float build, not RISC OS 5.30 |
| Emulator comparison (`compare-emulator-pdfs.sh`) | Host-tested | Blanks `/ID`, compares byte for byte, and shows any other difference in context |
| `validate-pdf.sh` | Implemented | Checks structure, version, producer, page sizes, fonts and text against a reference. Local: tried on identical, re-dated, different and truncated PDFs. Not run in CI (the toolchain image has no qpdf or poppler-utils) |
| Gate 3 kit (`package-pdftex-kit.sh`) | Host-tested | Artifact `TLPdfTeX-f0c69cd3b61b.zip`, 34.8 MB, 5682 tree files, with the reference PDFs; no file names that RISC OS might mangle. Gate 3 is [#17](https://github.com/kierennicolas/ArmTex_update/issues/17); procedure in [`testing.md`](testing.md#gate-3-pdftex-on-titanium) |
| `!TeXLive` launcher | Not started | Milestone 3's remaining work item |

## Known failures

- **Emulator, VFP builds:** stop at start-up with "This program requires version 0.02 or later of the VFPSupport module". Pyromaniac does not provide that module, so VFP builds can only be tested on hardware.
- **First toolchain build attempt:** failed after seven minutes in the GCCSDK build. Its log is in storage that could not be read, and the identical rerun succeeded, so the cause is unknown (probably a download). Failures now post the end of the build log as annotations.

## Untested

- Everything on RISC OS hardware. Gates 1, 2 and 3 are open.
- The VFP and Cortex-A15 builds of TeX Live: only soft-float is built, as the emulator can only run that.

## Next priorities

1. Gate 1 ([#3](https://github.com/kierennicolas/ArmTex_update/issues/3)) and Gate 2 ([#14](https://github.com/kierennicolas/ArmTex_update/issues/14)): waiting for the maintainer's reports on Titanium.
2. Gate 3 ([#17](https://github.com/kierennicolas/ArmTex_update/issues/17)): the pdfTeX kit on Titanium. Meanwhile, the minimal `!TeXLive` launcher, so `pdflatex` works from the command line.
3. Milestone 6 ([#8](https://github.com/kierennicolas/ArmTex_update/issues/8)): supply configure's C++11 answer for graphite2 and HarfBuzz in `config.site`, to find out whether the libraries themselves compile with GCC 4.7.
4. Look for a C++17-capable RISC OS compiler (the GCC 8 and 10 work mentioned in community sources) before Milestone 7 ([#9](https://github.com/kierennicolas/ArmTex_update/issues/9)).

Milestone issues: [#2](https://github.com/kierennicolas/ArmTex_update/issues/2) (M1) and [#4](https://github.com/kierennicolas/ArmTex_update/issues/4)–[#12](https://github.com/kierennicolas/ArmTex_update/issues/12) (M2–M10).
