# Progress

**Current milestone:** M1 — toolchain, C/C++ capability and first hardware artifact.

Status levels are defined in [`CLAUDE.md`](../CLAUDE.md#status-levels). "Local" notes describe checks run on a development machine; they do not count towards a status level.

Reference CI run: [39648204620](https://github.com/kierennicolas/ArmTex_update/actions/runs/39648204620) (all jobs green; toolchain image rebuilt from the pinned inputs).

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
| Emulator evaluation (`run-emulator.sh`) | Ran; programs did not start | build.riscos.online has no SharedUnixLibrary, and UnixLib programs refuse to start without it. The toolchain does not appear to install the module; see Known failures |
| Claude Code workflow (`claude.yml`) | Implemented | Needs the GitHub app and a secret; see [`building.md`](building.md#setting-up-the-claude-code-workflow) |

## Known failures

- **Emulator:** every program stops at start-up with "This application requires at least version 1.07 of the SharedUnixLibrary module". The next step is to build the module from GCCSDK's `libunixlib/module/sul.s` and upload it with the kit. This does not block Gate 1.
- **First toolchain build attempt:** failed after seven minutes in the GCCSDK build. Its log is in storage that could not be read, and the identical rerun succeeded, so the cause is unknown (probably a download). Failures now post the end of the build log as annotations.

## Untested

- Everything on RISC OS. Gate 1 is the first hardware test.

## Next priorities

1. Gate 1: open the `needs-hardware-test` issue with the kit from the reference run and the procedure in [`testing.md`](testing.md#gate-1-toolchain-test-kit-on-titanium).
2. Meanwhile, Milestone 2 host-side preparation: pin the TeX Live 2026 release branch, and try compiling xpdf and HarfBuzz from it with GCC 4.7, since the C++ results put both in doubt.
3. Look for a C++17-capable RISC OS compiler (the GCC 8 and 10 work mentioned in community sources) before Milestone 7.
