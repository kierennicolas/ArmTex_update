# Installation

There is no release yet. CI builds a development version of the `!TeXLive` application on every change, as the artifact `TeXLive-2026-dev-<commit>.zip` of the Build workflow's TeX Live job. It is for testing: until Gate 3 ([#17](https://github.com/kierennicolas/ArmTex_update/issues/17)) passes, nothing in it has run on RISC OS hardware. [`progress.md`](progress.md) says what has been tested where.

## Runtime requirements known so far

| Requirement | Why | Source |
|---|---|---|
| RISC OS 5.30 on Titanium | The target platform | Project definition |
| SharedUnixLibrary 1.07 or later for soft-float builds; 1.13 or later for VFP builds | UnixLib's startup code checks for it and loads `System:Modules.SharedULib` if it is missing | `libunixlib/sys/_syslib.s` in the pinned GCCSDK sources |
| A little over 82 MiB of disc space | The scheme-basic tree and formats are 82 MiB; the programs add to that | Milestone 3 CI, "texmf tree and formats" annotation |

All are unconfirmed on hardware until Gates 1 to 3.

## Installing the development version

1. Install SharedUnixLibrary with PackMan, if it is not already there.
2. Download the artifact and extract `!TeXLive` from it with SparkFS, SparkPlug or Info-ZIP's `unzip`, anywhere on the disc (for example `$.Apps`). The zip records RISC OS filetypes; a tool that does not restore them leaves the Obey files and programs as Data.
3. Double-click `!TeXLive` once. It opens no window: it defines the commands `pdflatex`, `pdftex` and `kpsewhich`. After that the Filer sets them up again whenever it sees `!TeXLive`.

## Using it

At the command line (F12, or a task window), go to the directory holding the document and run the command:

```
*Dir ADFS::HardDisc4.$.Documents
*pdflatex mydoc
```

This typesets `mydoc/tex` and writes `mydoc/pdf`, `mydoc/log` and `mydoc/aux` beside it. `pdftex` is for plain TeX. `!TeXLive.!Help` has more.

## Layout

The provisional layout, and why, is in [`architecture.md`](architecture.md#the-texlive-application-provisional-layout). Briefly: everything is inside `!TeXLive`, laid out as a TeX Live installation, so it works from any location and can be moved. The final layout, with user trees and Choices, comes with the desktop front end in Milestone 8.
