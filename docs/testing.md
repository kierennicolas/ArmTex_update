# Testing

Testing happens at the levels defined in [`CLAUDE.md`](../CLAUDE.md): host-side tests and cross-compilation in CI, an optional emulator run, and hardware gates that the maintainer runs on Titanium.

## In CI

Every pull request and every push to `main` runs [`build.yml`](../.github/workflows/build.yml):

| Job | What it checks |
|---|---|
| Host-side tests | Unit tests for the packaging and AIF tools; shellcheck; manifest pins; the test programs compile with the host compiler |
| Toolchain | The GCCSDK image for the current pins exists, building it first if not |
| Cross-compile and package | Builds the test programs in every variant, checks every ELF and AIF, confirms the checks reject damaged files, packages the TLTest kit, and runs the emulator evaluation |

The job summary of the last job shows which programs built in which variant and which C++ features the compiler supports.

To run the host-side tests locally:

```
python3 -m unittest discover -s tests/scripts -p 'test_*.py'
shellcheck scripts/*.sh tests/scripts/*.sh
```

## Emulator evaluation

The build job uploads the test kit to [build.riscos.online](https://build.riscos.online/), which runs commands under RISC OS Pyromaniac, and records the output in the job summary and the `build-record` artifact. `scripts/run-emulator.sh` does the work. The step is allowed to fail.

Pyromaniac reimplements RISC OS; it is not RISC OS 5.30 and does not model Titanium's processor. A result here is **Emulator-tested** at most and never replaces a gate.

The service has no SharedUnixLibrary module of its own, so the script uploads the toolchain's (`cross/bin/arm-unknown-riscos-sul`). It also has no VFPSupport module, so it runs every soft-float program first and stops at the first VFP one.

## Gate 1: toolchain test kit on Titanium

Gate 1 confirms that programs built by the project's toolchain run on Titanium, and measures what Milestone 1 needs to decide: which floating-point variant to use, and how unaligned memory access behaves.

### What you need

- Titanium running RISC OS 5.30.
- SharedUnixLibrary 1.13 or later. Check with `*Help SharedUnixLibrary`. PackMan installs and updates it.
- A zip tool that restores RISC OS filetypes: SparkFS, SparkPlug, or Info-ZIP's `unzip` from PackMan.

### Steps

1. **Download the kit.** Open the Build run named in the `needs-hardware-test` issue, scroll to **Artifacts**, and download `TLTest-<commit>.zip`. It is uploaded unwrapped, so the download should be the RISC OS zip itself. If you get a zip containing `TLTest-<commit>.zip`, extract that outer layer first, on any computer.
2. **Copy it to Titanium.** If it arrives as a Data file, set its type to Zip: `*SetType TLTest-<commit>/zip A91`, or use the Filer's Set type menu.
3. **Extract it** with SparkFS or SparkPlug (open it and drag the `TLTest` directory out), or with `*unzip` from Info-ZIP.
4. **Check the filetypes.** In the extracted `TLTest` directory, `RunAll` should show as an Obey file, `!ReadMe` and `BuildInfo` as Text, and the programs inside `soft`, `vfp`, `a15` and `a15noua` as Absolute. If the programs show as Data, the zip tool did not restore filetypes: stop and report that.
5. **Note the RISC OS version.** Press F12, type `FX 0` and press Return. The version appears as a message. Press Return again to get back to the desktop.
6. **Run the tests.** Double-click `RunAll`. It runs every program in turn and saves the output in a new file called `Results` in the `TLTest` directory. It should take under a minute.
7. **If it stops with an error**, note the exact message. Then press F12, type `Spool` and press Return, which closes the `Results` file so it keeps the output so far.
8. **Report** as below.

### Reporting

Comment on the Gate 1 `needs-hardware-test` issue with the items in [the gate report template](roadmap.md#gate-reports):

- the RISC OS version from step 5, and the machine
- the artifact name and the CI run it came from
- what you did, if it differed from the steps above
- the `Results` file, attached or pasted
- any error message in full, and the last lines of `Results` before it
- anything odd you noticed (icons, filetypes, the time it took)

### What the results should show

| Test | Expected |
|---|---|
| `hello`, `float`, `cxx11` in `soft`, `vfp` and `a15` | Every check PASS; exit status 0 after each |
| `soft hello --exit 3` | Exit status 3 |
| `unaligned`, every variant | The memcpy and packed-structure checks PASS. The pointer-load checks are measurements: PASS or FAIL both tell us something |
| `cxx17` | Probably not in the kit, because GCC 4.7 predates C++17 |

INFO lines record behaviour with no fixed expectation, such as how UnixLib translates filenames and whether an Obey-file variable without `$` is visible to programs. Report them as they are.

If a `vfp` or `a15` program stops with an "undefined instruction" error, the VFP build does not suit this machine: report it, and the `soft` results still count.

## Gate 2: kpsewhich on Titanium

Gate 2 checks that kpathsea, cross-compiled from TeX Live 2026, finds files in a TeX Live-style tree from wherever the tree is installed. It settles the filename layout for Milestone 2 and shows whether kpathsea's self-location works under UnixLib.

### The kit

`TLKpse-<commit>.zip`, an artifact of the Build run named in the Gate 2 `needs-hardware-test` issue (from the `TeX Live cross build` job). It holds:

| Path in the kit | What it is |
|---|---|
| `bin.riscos.kpsewhich` | kpsewhich, soft-float, statically linked |
| `texmf-dist.web2c.texmf/cnf` | kpathsea's own `texmf.cnf`, unchanged |
| `texmf-dist.ls-R` | the filename database for the tree |
| `texmf-dist.tex.latex.base.article/cls` and others | stand-ins with the right names; Gate 2 tests finding files, not reading them |
| `RunKpse` | Obey file that runs the searches and saves `Results` |

This is the layout TeX Live uses on other systems: the program sits two levels below the kit's top directory, which kpathsea calls `SELFAUTOPARENT`, and everything else is found from there.

### Steps

1. Download, copy and extract the kit as for Gate 1 (steps 1 to 4 of Gate 1), using `TLKpse` in place of `TLTest`. Check that `RunKpse` is an Obey file and `bin.riscos.kpsewhich` is Absolute.
2. Double-click `RunKpse`. It saves its output in `Results` in the `TLKpse` directory.
3. Copy the whole `TLKpse` directory to a different place, for example the RAM disc or another directory on the hard disc. Run `RunKpse` in the copy and keep that `Results` too.
4. If it stops with an error, note the message, then press F12, type `Spool` and press Return.
5. Report both `Results` files, the two locations, and any error on the Gate 2 issue.

### What the results should show

| Query | Expected |
|---|---|
| `--version` | `kpathsea version 6.4.2`, exit status 0 |
| `-var-value=SELFAUTOPARENT` | the kit's top directory, as a Unix-style path |
| `-var-value=TEXMFDIST` | that path followed by `/texmf-dist` |
| `texmf.cnf`, `article.cls`, `plain.tex`, `cmr10.tfm`, `cmr10.pfb` | a path inside the kit for each, exit status 0 |
| `-must-exist article.cls` | the same path as `article.cls` |
| The copy | the same results, with the copy's location |

The CI job also runs the same queries under the emulator; see the job's annotations. That is indicative only.
