# Roadmap

Milestones for TeX Live for RISC OS. Each milestone has acceptance criteria that can be checked from CI runs or from a maintainer's hardware report. The rules for gates and status levels are in `CLAUDE.md`.

## How milestones work

- Each milestone has one GitHub issue, which links sub-issues for the individual pieces of work.
- **GATE** steps need the maintainer to run something on Titanium. Work that depends on a gate waits for it; independent work carries on.
- A milestone is complete when every acceptance criterion is met and the milestone issue links the evidence.

### Gate reports

The maintainer reports each gate as a comment on its `needs-hardware-test` issue, including:

- RISC OS version (output of `*FX 0`) and machine
- the artifact name and the CI run it came from
- the commands run, in order
- the output, and any error messages in full
- attached output files (PDFs, logs, spooled output)
- pass or fail for each expected result in the procedure

## Open decisions

| Decision | Options | Settled in | Current default |
|---|---|---|---|
| GCCSDK compiler | GCC 4.7.x (stable); newer GCC 8/10 work, if usable | M1 | None |
| C++17 availability | Needed by the bundled ICU, and so by XeTeX and bibtexu | M1 | Unknown |
| Floating-point ABI | Whatever GCCSDK's libraries support; hardware VFP preferred on Titanium if available | M1 | None |
| Emulator testing | Whether build.riscos.online or Pyromaniac can run UnixLib binaries | M1 | Unknown |
| Filename layout | Suffix swapping off (`article/cls`) or UnixLib suffix directories | M2 | Swapping off |
| Format generation | Host-generated or native | M3 | Host |
| Installation layout | Where binaries, texmf trees, user trees, caches and Choices live | M3 (provisional), M8 (final) | Everything inside `!TeXLive`, as a TeX Live installation (provisional; `architecture.md`) |
| Perl tools | Host-side at packaging time, or a native Perl | M9 | Host |
| Update mechanism | Replacement archives, or a native package tool | M9 | None |

## M1 — Toolchain, C/C++ capability and first hardware artifact

**Goal:** prove the build pipeline and find out exactly what the compiler can do, before any TeX Live code.

**Work**

- Repository layout, `docs/` skeleton, `upstream/manifest.json`.
- GCCSDK toolchain packaged as a container image in GitHub Container Registry, built by a separate manually triggered workflow. Normal builds pull the image.
- Test programs: C basics, C++11, C++17, unaligned memory access, floating point.
- `scripts/check-binaries.sh`: ELF checks before conversion, AIF checks after, filetype and archive checks. Includes a negative test with a deliberately malformed binary.
- Evaluation of build.riscos.online / Pyromaniac for running the test programs.
- `claude.yml` workflow for the Claude Code GitHub Action.
- Issues for M2 to M10, each with its acceptance criteria.

**GATE 1:** the maintainer runs the test programs on Titanium.

**Acceptance**

- [ ] Build workflow green on `main`, producing a downloadable artifact.
- [ ] Compiler decision record merged in `docs/architecture.md`, stating C++11 and C++17 status with CI evidence.
- [ ] Emulator evaluation recorded.
- [ ] Gate 1 passed, or each failure recorded as an issue.

## M2 — Pinned upstream, host tools and cross-configuration

**Goal:** TeX Live 2026 sources configure for RISC OS, the libraries pdfTeX needs cross-compile, and kpathsea finds files on the target.

**Work**

- Identify the TeX Live 2026 release branch or tag. Record it, with checksums, in `upstream/manifest.json`. Do the same for the support-file snapshot (ISO or dated tlnet snapshot).
- Stage A, native host build from the same source: tangle, ctangle, otangle, tie, kpsewhich and pdfTeX. Cross-compiling the WEB programs needs these host tools.
- Stage B, cross-configuration with `--host` and `--build`, plus a `config.site` that supplies answers for configure tests that cannot run when cross-compiling. Build the libraries pdfTeX needs, including kpathsea, zlib, libpng and the modified xpdf.
- `docs/architecture.md`: source structure, pdfTeX's dependency graph, the patch policy in practice.
- Cross-compile `kpsewhich` and package it with a small texmf tree in the default filename layout.

**GATE 2:** `kpsewhich` on Titanium finds `article.cls`, `cmr10.tfm`, a `.pfb` font and `texmf.cnf` in the test tree, from the application's own location, and still finds them after the application is moved to a different directory.

**Acceptance**

- [ ] A clean runner reproduces the build from the manifest alone.
- [ ] Every library pdfTeX needs cross-compiles.
- [ ] Gate 2 passed and the filename layout decision recorded.

## M3 — pdfTeX (the key milestone)

**Goal:** pdflatex produces a valid PDF on Titanium.

**Work**

- Cross-compile pdfTeX.
- A minimal texmf tree from the pinned snapshot (a scheme-basic subset).
- Formats: test host-generated `pdftex.fmt` and `pdflatex.fmt` on the target. If they fail to load, generate them natively with `-ini` and record why.
- Font maps generated on the host with updmap.
- A minimal `!TeXLive` launcher. `!Boot` and `!Run` set things up so `pdflatex` works from the command line with no user configuration.
- `scripts/validate-pdf.sh`: checks a PDF produced on hardware against a host-produced reference, covering structure, embedded fonts, extracted text and page size.
- Test documents: plain TeX (`story.tex`) and the reference LaTeX document below.

**GATE 3:** the maintainer runs

```
pdflatex -interaction=nonstopmode -halt-on-error test.tex
```

on Titanium for each test document and attaches the PDF and log to the issue. The validation script passes on the attached files.

**Acceptance**

- [ ] Gate 3 passed for the plain TeX and LaTeX tests.
- [ ] Format strategy decided and recorded.
- [ ] Provisional installation layout recorded.
- [ ] A clearly labelled development prerelease published.

**Reference LaTeX test document**

```latex
\documentclass{article}
\usepackage{amsmath}
\begin{document}
\section{Hello from RISC OS}
This PDF was generated using
TeX Live on an Elesar Titanium.
\[
E = mc^2
\]
\[
\int_0^\infty e^{-x^2}\,dx
=
\frac{\sqrt{\pi}}{2}
\]
\end{document}
```

## M4 — Modern LaTeX

**Goal:** representative modern documents compile with pdflatex on Titanium.

**Work**

- Expand the tree to scheme-small, or a documented subset of it.
- A test corpus covering: standard classes; amsmath and amssymb; graphicx with PNG, JPEG and PDF images; hyperref and PDF metadata; fontenc T1 with Latin Modern; babel with at least two languages and their hyphenation; booktabs and longtable; TikZ; microtype; BibTeX bibliographies; MakeIndex; long multi-page documents; a custom class and style file; a basic `\DocumentMetadata` case.
- Every corpus document has a host reference. Validation compares content, not just the existence of an output file.

**GATE 4:** the maintainer runs the corpus on Titanium and attaches the results.

**Acceptance**

- [ ] Every corpus document passes validation on hardware, or has an issue explaining the failure.
- [ ] bibtex and makeindex Titanium-verified.
- [ ] Compile times on Titanium recorded in `docs/compatibility.md`.

## M5 — DVI workflows

**Goal:** traditional DVI output and conversion work alongside direct PDF.

**Work**

- tex, etex and latex (DVI mode), dvipdfmx and dvips.
- Host-side checks: DVI to PDF via dvipdfmx matches the reference; dvips PostScript renders correctly with Ghostscript on the host.

**GATE 5:** the maintainer runs the DVI tests on Titanium.

**Acceptance**

- [ ] Gate 5 passed for DVI generation, dvipdfmx and dvips.

## M6 — LuaLaTeX (LuaHBTeX)

**Goal:** LuaLaTeX processes representative documents on Titanium.

**Work**

- HarfBuzz and Lua 5.3 cross-compiled; LuaHBTeX built. The LuaJIT engines stay out of scope.
- luaotfload's font cache in a writable location that works under RISC OS.
- Memory use measured against RISC OS application-space limits; a documented strategy if large documents exceed them.
- OpenType font tests with fontspec.

**GATE 6:** the maintainer runs the LuaLaTeX tests on Titanium.

**Acceptance**

- [ ] Gate 6 passed.
- [ ] Memory measurements and any limits recorded in `docs/compatibility.md`.

## M7 — XeLaTeX (conditional)

**Precondition:** M1 found a usable C++17 compiler. If it did not, record XeTeX and bibtexu as blocked, with the evidence, and skip this milestone until the toolchain changes.

**Work**

- ICU with its data file, graphite2, fontconfig configured for RISC OS font locations, xdvipdfmx.
- fontspec and Unicode script tests.

**GATE 7:** the maintainer runs the XeLaTeX tests on Titanium.

**Acceptance**

- [ ] Gate 7 passed, or the blocked status recorded with evidence.

## M8 — Desktop application

**Goal:** a user can produce a PDF using only the RISC OS desktop.

**Work**

- The full `!TeXLive` application, following the RISC OS Style Guide: icon, drag-and-drop of source files, output choice (PDF, DVI or Both), progress window, error reporting with line numbers, access to log files, opening the output in the user's PDF viewer, configuration saved in Choices.
- The command-line interface remains available for automation.
- Final installation layout.

**GATE 8:** the maintainer produces a PDF using only the desktop, starting from a fresh install.

**Acceptance**

- [ ] Gate 8 passed.
- [ ] Final installation layout documented in `docs/installation.md`.

## M9 — Fuller distribution

**Goal:** functionality approaches TeX Live on desktop systems, within the documented limitations.

**Work**

- Further package collections, chosen with the maintainer.
- Documentation bundled and reachable from the application.
- Update mechanism and Perl-tools strategy decided and implemented.
- Licence audit of every redistributed component, with notices in `LICENSES/` and source availability for redistributed binaries.

**GATE 9:** the maintainer runs the corpus for the added collections on Titanium and updates an existing install using the new mechanism.

**Acceptance**

- [ ] Gate 9 passed for the added collections and the update mechanism.
- [ ] Licence audit complete.

## M10 — Release

**Goal:** a non-developer can install and use TeX Live on Titanium.

**Work**

- Release workflow triggered by version tags: build from pins, run all automated tests, package with filetypes preserved, generate checksums, include licences, publish a GitHub Release.
- Stable releases only for components that have passed their gates. Anything less is labelled as a prerelease.

**GATE 10:** a non-developer installs the release on Titanium from the published instructions and produces a PDF.

**Acceptance**

- [ ] Gate 10 passed.
- [ ] Release published with binaries, checksums, licences, documentation and test results.
