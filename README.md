# TeX Live for RISC OS

A native RISC OS port of TeX Live 2026, aimed at the Elesar Titanium running RISC OS 5.30. The port is cross-compiled on Linux with GCCSDK in GitHub Actions.

**Status:** early development. Nothing here is usable as a TeX installation yet. See [`docs/progress.md`](docs/progress.md) for what works and at what level of testing.

## Documents

| Document | Contents |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Standing rules for development, including the status levels used throughout the project |
| [`docs/roadmap.md`](docs/roadmap.md) | Milestones, hardware gates, acceptance criteria and open decisions |
| [`docs/issues/milestone-1.md`](docs/issues/milestone-1.md) | Text of the Milestone 1 issue |

## Priorities

1. pdfTeX running natively on RISC OS and producing a valid PDF.
2. Modern LaTeX documents, then DVI workflows.
3. LuaLaTeX, then XeLaTeX if the toolchain allows.
4. The `!TeXLive` desktop application.

Every milestone that needs real hardware has a gate: a test the maintainer runs on Titanium before dependent work goes ahead.
