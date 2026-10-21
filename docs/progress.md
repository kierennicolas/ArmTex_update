# Progress

**Current milestone:** M1 — toolchain, C/C++ capability and first hardware artifact.

Status levels are defined in [`CLAUDE.md`](../CLAUDE.md#status-levels). "Local" notes describe checks run on a development machine; they do not count towards a status level.

## Components

| Component | Status | Evidence and notes |
|---|---|---|
| Repository layout and documentation | Implemented | Pull request for Milestone 1 |
| GCCSDK pin (`upstream/manifest.json`) | Implemented | GCCSDK `main` at `33cb00db1e0a` (11 October 2026) |
| Toolchain image (`toolchain.yml`, `scripts/build-toolchain.sh`) | Implemented | Not yet built in CI |
| Test programs (`tests/toolchain/`) | Implemented | Local: compile and pass with the host compiler |
| C++ feature probes (`tests/toolchain/probes/`) | Implemented | Local: all compile with a modern host compiler |
| Test build script (`scripts/build-toolchain-tests.sh`) | Implemented | Local: exercised with a stand-in compiler |
| Binary checks (`scripts/check-binaries.sh`, `scripts/lib/aifcheck.py`) | Implemented | Local: pass on an ARM ELF fixture converted by GCCSDK's `elf2aif`; negative tests reject damaged copies |
| RISC OS zip tool (`riscos/packaging/rozip.py`) | Implemented | Local: unit tests pass; `zipinfo` recognises the Acorn extra fields |
| Test kit (`scripts/package-testkit.sh`) | Implemented | Local: packaged from stand-in build output |
| Emulator evaluation (`scripts/run-emulator.sh`) | Implemented | Not yet run |
| Claude Code workflow (`claude.yml`) | Implemented | Needs the GitHub app and a secret; see [`building.md`](building.md#setting-up-the-claude-code-workflow) |

## Known failures

None recorded yet.

## Untested

- Everything on RISC OS. Gate 1 is the first hardware test.
- The toolchain build, the cross-compiled programs and the emulator run, until the first CI run completes.

## Next priorities

1. First CI run: build the toolchain image, cross-compile the test programs, record the C++ probe results in [`architecture.md`](architecture.md#decision-records).
2. Commit `toolchain/gccsdk/source-checksums.sha256` from the first toolchain build.
3. Open the Gate 1 `needs-hardware-test` issue with the kit and the procedure in [`testing.md`](testing.md#gate-1-toolchain-test-kit-on-titanium).
4. Meanwhile, Milestone 2 host-side preparation: identify the TeX Live 2026 release branch and pin it.
