# Installation

There is nothing to install yet. Milestone 1 produces only a test kit, whose instructions are in [`testing.md`](testing.md#gate-1-toolchain-test-kit-on-titanium).

## Runtime requirements known so far

| Requirement | Why | Source |
|---|---|---|
| RISC OS 5.30 on Titanium | The target platform | Project definition |
| SharedUnixLibrary 1.07 or later for soft-float builds; 1.13 or later for VFP builds | UnixLib's startup code checks for it and loads `System:Modules.SharedULib` if it is missing | `libunixlib/sys/_syslib.s` in the pinned GCCSDK sources |

Both are unconfirmed on hardware until Gate 1.

The final installation layout (where binaries, texmf trees, user trees, caches and Choices live) is an open decision, settled provisionally in Milestone 3 and finally in Milestone 8.
