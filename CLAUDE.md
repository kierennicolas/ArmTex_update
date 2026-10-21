# TeX Live for RISC OS — instructions for Claude Code

This file holds the standing rules for every session. Milestones, acceptance criteria and open decisions are in `docs/roadmap.md`. The current state of the port is in `docs/progress.md`. Read both before starting work.

## The project

A native RISC OS port of **TeX Live 2026**, cross-compiled on Linux with **GCCSDK** in **GitHub Actions**.

| | |
|---|---|
| Target hardware | Elesar Titanium (Cortex-A15, ARMv7-A, 32-bit) |
| Target OS | RISC OS 5.30 |
| Upstream | TeX Live 2026 release branch, pinned |
| First engine | pdfTeX, producing PDF directly |
| Later engines | TeX / e-TeX (DVI), LuaHBTeX (LuaLaTeX), XeTeX (if the toolchain allows) |
| Application | `!TeXLive` |

**Overriding priority:** get pdfTeX running natively on RISC OS and producing a valid PDF before investing in the desktop interface or further engines.

Linux is for building only. Nothing shipped may depend on Linux at run time.

## Hard rules

### Honesty

- Never report a build, test or hardware result that did not happen. Link the CI run for every claim of success.
- Never weaken, skip or replace a failing test to make CI pass. If a test is wrong, fix it in its own commit and say why.
- Only the maintainer can mark anything **RISC OS-tested** or **Titanium-verified**.
- When blocked, record in the relevant issue: the exact obstacle, the evidence (logs, commands), what you tried, and the proposed next step.

### Status levels

Use these terms exactly in `docs/progress.md`, pull requests and issues. Levels are cumulative, except Emulator-tested, which is optional.

| Level | Meaning | Who may claim it |
|---|---|---|
| Implemented | Code written | Claude |
| Cross-compiled | Builds for RISC OS in CI | Claude, with CI link |
| Host-tested | Host-side tests pass in CI (host build, output validation, packaging checks) | Claude, with CI link |
| Emulator-tested | Runs under RISC OS Pyromaniac or build.riscos.online. Indicative only: this is not RISC OS 5.30 | Claude, with CI link |
| RISC OS-tested | Run on real RISC OS 5 hardware by the maintainer | Maintainer |
| Titanium-verified | Passed the documented procedure on Titanium under RISC OS 5.30 | Maintainer |

### Hardware gates

Steps marked **GATE** in `docs/roadmap.md` need execution on real hardware. At a gate:

1. Produce a downloadable CI artifact and a step-by-step procedure in `docs/testing.md`.
2. Open or update an issue labelled `needs-hardware-test` with the artifact link, the procedure and the expected results.
3. Stop work that depends on the gate. Independent work may continue.
4. Resume when the maintainer reports results in the issue. Treat a failure report as the next task.

### Upstream and reproducibility

- Use the TeX Live 2026 **release branch or tag**, never trunk. Trunk is already tracking post-2026 library updates.
- Pin every input (TeX Live source revision, GCCSDK revision, support-file snapshot, anything else downloaded) in `upstream/manifest.json` with a SHA-256 checksum. Build scripts take pins only from the manifest.
- Support files (macros, fonts, configuration) come from a pinned snapshot: the TL2026 ISO or a dated tlnet snapshot. Never build from the live tlnet repository, which changes daily.
- Never mix packages from different TeX Live years.
- Never commit upstream source trees, TeX Live package trees, toolchains or built binaries.

### Changing upstream code

- Never edit upstream sources in place. Each change is a patch in `patches/texlive/`, applied in order from a `series` file, with a header stating the reason and whether it could be sent upstream.
- Put RISC OS-specific code in `riscos/compatibility/` and reach it through as few, small hooks as possible.
- The test of good structure: moving to TeX Live 2027 should mean refreshing pins and rebasing patches, not rewriting the port.

### CI and security

- Jobs must fit within GitHub-hosted runner limits. Normal builds reuse the cached toolchain image; GCCSDK is rebuilt only when its pins or build recipe change, which gives the image a new tag.
- Pin third-party actions to commit SHAs. Give every workflow the minimum `permissions:`.
- Never use `pull_request_target` to run contributor code, and never expose secrets to untrusted pull requests.
- Never run RISC OS binaries on the Linux host as if they were Linux programs.
- Never commit credentials.

## How to work on a task

1. Read this file, `docs/roadmap.md`, `docs/progress.md` and the issue.
2. Inspect existing code before changing it.
3. Work on a focused branch. Keep pull requests reviewable. No unrelated refactors.
4. Run the relevant tests.
5. Update `docs/progress.md` and any affected documentation in the same pull request.
6. In the pull request description, state what changed, the status level each affected component reached (with CI links), and what remains untested.

## Technical conventions

These are the current defaults. Open decisions, and the milestone that settles each one, are listed in `docs/roadmap.md`. When a decision is made, record it in `docs/architecture.md` and update this section.

- **Filetypes in the repository** use the `,xxx` suffix (`!Run,feb`, `pdftex,ff8`). Packaging uses `riscos/packaging/rozip.py`, which records filetypes in the zip so they survive. Upload RISC OS zips as artifacts with `archive: false`, so GitHub does not wrap them in a second zip.
- **Executables** are statically linked and converted to AIF (filetype &FF8) with `elf2aif`, unless Milestone 1 finds a better option. Record any runtime modules the binaries need (UnixLib programs normally need SharedUnixLibrary) in `docs/installation.md`.
- **Filenames** (default, confirmed or replaced in Milestone 2): the texmf tree is stored with UnixLib's suffix-directory swapping turned off, so `article.cls` becomes `article/cls`. Lookups rely on kpathsea's `ls-R` database.
- **Formats** (default, confirmed or replaced in Milestone 3): `.fmt` files are generated on the host by a host pdfTeX built from the identical pinned source and configuration, relying on Web2c's default architecture-independent format files. If a host-built format fails to load on RISC OS, generate formats natively.
- **Perl-based tools** (fmtutil, updmap, tlmgr, latexmk) run on the host at packaging time until a native strategy is decided.
- **Installation** must work from any filing-system location, with no manual environment-variable setup by the user. `!TeXLive.!Boot` and `!Run` set whatever kpathsea cannot work out for itself.

## Out of scope unless the maintainer agrees

Document these as known limitations and do not spend time on them: xindy (needs GNU clisp), Asymptote, Biber, the LuaJIT engines (luajittex, luajithbtex), X11 programs such as xdvik, and Metafont window support.

## Scripts

Created as the milestones need them. Keep this table current.

| Script | Purpose | Status |
|---|---|---|
| `scripts/toolchain-image.sh` | Compute the toolchain image tag from the pins and build recipe | M1 |
| `scripts/build-toolchain.sh` | Build GCCSDK at the pinned revision and pack it for the toolchain image (run by `toolchain.yml`) | M1 |
| `scripts/build-toolchain-tests.sh` | Build the Milestone 1 test programs and C++ probes; write `results.json` | M1 |
| `scripts/check-binaries.sh` | Check that outputs are correctly targeted RISC OS executables (uses `scripts/lib/aifcheck.py`) | M1 |
| `scripts/package-testkit.sh` | Package the Gate 1 test kit as a RISC OS zip | M1 |
| `scripts/summarise-results.sh` | Markdown summary of `results.json` for the CI job summary | M1 |
| `scripts/run-emulator.sh` | Run a kit's commands on build.riscos.online (Emulator-tested at most) | M1 |
| `scripts/ci-annotate.sh` | Copy the end of a log into GitHub annotations, which are readable without the full job log | M1 |
| `scripts/fetch-upstream.sh` | Fetch pinned inputs and verify them (TeX Live source by commit) | M2 |
| `scripts/build-host-tools.sh` | Native host build: tangle, ctangle, otangle, tie, kpsewhich, host pdfTeX | M2 |
| `scripts/build-texlive.sh` | Cross-configure TeX Live and build the enabled components; write `results.json` | M2 |
| `scripts/summarise-texlive.sh` | Markdown summary of the TeX Live cross build's `results.json` | M2 |
| `scripts/package-kpse-kit.sh` | Package the Gate 2 kit: cross-compiled kpsewhich with a small TeX Live-style tree | M2 |
| `scripts/test-kpse-kit.sh` | Check the Gate 2 kit's tree and `ls-R` with the native kpsewhich, in place and moved | M2 |
| `scripts/test-build.sh` | Host-side tests and output validation | Planned |
| `scripts/validate-pdf.sh` | Check a PDF produced on hardware against a host-produced reference | Planned |
| `scripts/package-release.sh` | Build the `!TeXLive` archive with filetypes preserved | Planned |
