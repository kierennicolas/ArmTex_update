# Compatibility

Known platform limitations, measured behaviour and performance figures. Every entry says where it came from.

## Out of scope

As listed in [`CLAUDE.md`](../CLAUDE.md#out-of-scope-unless-the-maintainer-agrees): xindy (needs GNU clisp), Asymptote, Biber, the LuaJIT engines, X11 programs such as xdvik, and Metafont window support.

## Toolchain

| Item | Status | Source |
|---|---|---|
| Compiler | GCC 4.7.4 (GCCSDK release 6) | GCCSDK sources |
| C++11 | Partial in GCC 4.7; measured feature by feature by the probes in CI | Build job summary |
| C++17 | Not expected with GCC 4.7; measured by the probes | Build job summary |
| Hard-float ABI | Not available; soft-float and softfp with VFP are | `gcc4/STATUS-BRANCH` |
| Wide characters and `thread_local` in C++ | Not expected: GCC is configured with `--disable-wchar_t` and `--disable-tls` | `gcc4/Makefile` |

## Measured on hardware

Nothing yet. Gate 1 will add the floating-point, unaligned-access and filename-translation results here.

## Performance

Nothing yet. Milestone 4 records compile times on Titanium.
