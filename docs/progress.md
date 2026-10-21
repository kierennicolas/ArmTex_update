# Progress

**Current milestone:** M1 — toolchain, C/C++ capability and first hardware artifact.

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

## Known failures

- **Emulator, VFP builds:** stop at start-up with "This program requires version 0.02 or later of the VFPSupport module". Pyromaniac does not provide that module, so VFP builds can only be tested on hardware.
- **First toolchain build attempt:** failed after seven minutes in the GCCSDK build. Its log is in storage that could not be read, and the identical rerun succeeded, so the cause is unknown (probably a download). Failures now post the end of the build log as annotations.

## Untested

- Everything on RISC OS. Gate 1 is the first hardware test.

## Next priorities

1. Gate 1 ([#3](https://github.com/kierennicolas/ArmTex_update/issues/3)): waiting for the maintainer's report on Titanium.
2. Meanwhile, Milestone 2 ([#4](https://github.com/kierennicolas/ArmTex_update/issues/4)) host-side preparation: pin the TeX Live 2026 release branch, and try compiling xpdf and HarfBuzz from it with GCC 4.7, since the C++ results put both in doubt.
3. Look for a C++17-capable RISC OS compiler (the GCC 8 and 10 work mentioned in community sources) before Milestone 7 ([#9](https://github.com/kierennicolas/ArmTex_update/issues/9)).

Milestone issues: [#2](https://github.com/kierennicolas/ArmTex_update/issues/2) (M1) and [#4](https://github.com/kierennicolas/ArmTex_update/issues/4)–[#12](https://github.com/kierennicolas/ArmTex_update/issues/12) (M2–M10).
