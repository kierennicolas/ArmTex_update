**Title:** Milestone 1: GCCSDK toolchain in GitHub Actions, C/C++ capability check and first Titanium test artifact

**Labels:** `milestone`, `toolchain`

---

## Goal

Prove that GitHub Actions can produce correctly targeted RISC OS 5.30 executables for Elesar Titanium, and establish exactly what the GCCSDK compiler supports, before any TeX Live code is ported.

`CLAUDE.md` (repository root) and `docs/roadmap.md` are already in the repository. Read both first; their rules apply to everything below.

## Why the C++ check comes first

- pdfTeX links a modified xpdf, which is C++, so C++ is needed from Milestone 3 onwards.
- LuaHBTeX, the engine behind LuaLaTeX, needs HarfBuzz, which needs C++11.
- The ICU bundled with TeX Live (78.x) needs C++17. This decides whether XeTeX and bibtexu are possible.
- GCCSDK's stable compiler is GCC 4.7.x, whose C++11 support is incomplete. Newer GCC work exists in the GCCSDK project and needs evaluating.

The result decides whether Milestone 7 (XeLaTeX) can go ahead, so it must be measured, not assumed.

## Tasks

### Repository

- [ ] Create the layout described in `CLAUDE.md` and `docs/roadmap.md`. Adjust it where the build system justifies a change, and record why in `docs/architecture.md`.
- [ ] Create `docs/progress.md`, `docs/architecture.md` (skeleton plus a decision-record section), `docs/building.md`, `docs/testing.md`, `docs/installation.md` and `docs/compatibility.md`.
- [ ] Create `upstream/manifest.json` with the GCCSDK revision used, and a schema that later milestones extend.
- [ ] Propose a licence for the project's own code in the pull request. The maintainer decides; do not add one without that decision.

### Toolchain

- [ ] Inspect the GCCSDK repository and documentation: available compiler versions and branches, the repository's existing CI workflows, and whether a prebuilt toolchain is already published.
- [ ] Add `.github/workflows/toolchain.yml` (manual trigger only). It builds the pinned GCCSDK revision into a container image and pushes it to GitHub Container Registry, tagged with that revision.
- [ ] If more than one compiler version is viable, build both and compare them in the decision record.

### Test programs (`tests/toolchain/`)

Each program prints one clear `PASS` or `FAIL` line per check and exits non-zero if any check fails.

- [ ] `hello.c`: prints output, reads an environment variable, writes a file using a Unix-style path and reads it back, and returns a requested exit code (checked through `Sys$ReturnCode`).
- [ ] `cxx11.cc`: `auto`, lambdas, range-based `for`, `std::unique_ptr`, standard containers, exceptions thrown and caught, static initialisation order, iostream output.
- [ ] `cxx17.cc`: `std::optional`, `std::string_view`, structured bindings, `if constexpr`, inline variables. This may not compile with GCC 4.7; record the result either way.
- [ ] `unaligned.c`: reads multi-byte values from unaligned addresses (packed structures, casts into byte buffers). Compilers targeting ARMv7 may emit unaligned loads, so we need to know how RISC OS 5.30 on Titanium handles them, and which compiler flags are required.
- [ ] `float.c`: arithmetic, `printf` of doubles, `strtod` round trips, exercising the chosen floating-point ABI.

### Build workflow (`.github/workflows/build.yml`)

- [ ] Triggers: pull requests, pushes to `main`, manual dispatch.
- [ ] Pulls the toolchain image, builds the test programs statically and converts them to AIF with `elf2aif`.
- [ ] Packages them, with an Obey file that runs each program and saves the combined output to a text file for the gate report, in a RISC OS-aware zip placed inside the uploaded artifact.
- [ ] Minimal `permissions:`, third-party actions pinned to commit SHAs.

### Automated checks (`scripts/check-binaries.sh`)

- [ ] Before conversion: each ELF file is 32-bit ARM, little-endian, from the expected toolchain.
- [ ] After conversion: each AIF header is valid. Write the checks against the AIF specification and cite the specification in the script.
- [ ] Filetype suffixes are correct, and the RISC OS zip records the expected filetypes.
- [ ] A negative test: a deliberately malformed binary must make the script fail.
- [ ] The build workflow fails if any check fails.

### Emulator evaluation

- [ ] Try running the test programs through build.riscos.online or the RISC OS Pyromaniac container. Record what works, what fails, and whether UnixLib binaries run at all. Results count as Emulator-tested at most.

### Claude Code workflow

- [ ] Add `.github/workflows/claude.yml` using the current release of `anthropics/claude-code-action`, pinned to a commit SHA, authenticated through a repository secret, and responding only to collaborators with write access.

### Documentation and issues

- [ ] `docs/testing.md`: the Gate 1 procedure. Cover downloading the artifact (the GitHub download is a plain zip containing the RISC OS zip), extracting it on RISC OS with filetypes intact, running the Obey file, the expected output, and how to report results using the template in `docs/roadmap.md`.
- [ ] `docs/architecture.md`: the compiler decision record, covering compiler version, C++11 and C++17 status, floating-point ABI and unaligned-access flags, each with CI evidence.
- [ ] `docs/progress.md`: the status level of each component, using the terms in `CLAUDE.md`.
- [ ] Open issues for Milestones 2 to 10 from `docs/roadmap.md`, each with its acceptance criteria.

## GATE 1

When the artifact and procedure are ready, open an issue labelled `needs-hardware-test` containing the artifact link, the procedure and the expected results, then stop work that depends on the result. Host-side preparation for Milestone 2 (identifying the TeX Live 2026 release branch, the native host-tools build) may continue.

## Acceptance criteria

- [ ] `build.yml` is green on `main` and produces a downloadable artifact.
- [ ] `check-binaries.sh` runs in CI, and its negative test fails as intended.
- [ ] Compiler decision record merged, with C++11 and C++17 results and CI links.
- [ ] Emulator evaluation recorded.
- [ ] Gate 1 report received from the maintainer: every test program runs correctly on Titanium, or each failure has its own issue.
- [ ] Issues for Milestones 2 to 10 exist.

## Out of scope

- Any TeX Live source code.
- The desktop application.

## References

- GCCSDK: https://github.com/riscos-dot-info/gccsdk and https://www.riscos.info/index.php/Autobuilder
- Building TeX Live: https://www.tug.org/texlive/doc/tlbuild.html
- TeX Live library versions: https://github.com/TeX-Live/texlive-source/blob/trunk/libs/README
- RISC OS build service client: https://github.com/gerph/robuild-client
- RISC OS build container (points to the Pyromaniac container for execution): https://hub.docker.com/r/gerph/riscos-build
- Claude Code GitHub Action: https://github.com/anthropics/claude-code-action
