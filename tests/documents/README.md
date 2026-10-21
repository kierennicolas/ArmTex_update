# Test documents

| File | Format | What it tests |
|---|---|---|
| `storytest.tex` | `pdftex` (plain TeX with e-TeX) | Knuth's `story.tex`: plain TeX, Computer Modern Type 1 fonts, PDF output |
| `test.tex` | `pdflatex` | The reference LaTeX document from `docs/roadmap.md` (Milestone 3): `article`, `amsmath`, display maths |

`test.tex` is copied verbatim from the roadmap; keep the two the same.

`scripts/test-documents.sh` compiles both on the build machine with the host pdfTeX and the tree from `scripts/build-texmf-tree.sh`, to give reference PDFs and the list of files each one reads. The same documents run on RISC OS in the Milestone 3 kits.
