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
