# Compatibility

Known platform limitations, measured behaviour and performance figures. Every entry says where it came from.

## Out of scope

As listed in [`CLAUDE.md`](../CLAUDE.md#out-of-scope-unless-the-maintainer-agrees): xindy (needs GNU clisp), Asymptote, Biber, the LuaJIT engines, X11 programs such as xdvik, and Metafont window support.

## Toolchain

| Item | Status | Source |
|---|---|---|
| Compiler | GCC 4.7.4 (GCCSDK release 6) | GCCSDK sources |
| C++11 | Partial. Missing: `alignas`, `[[...]]` attributes, inheriting constructors, ref-qualifiers, `thread_local`, `std::to_string` | C++ probes, [CI run 39648204620](https://github.com/kierennicolas/ArmTex_update/actions/runs/39648204620) |
| C++14, C++17 | Not supported: the compiler rejects the standard flags | Same run |
| Hard-float ABI | Not available; soft-float and softfp with VFP are | `gcc4/STATUS-BRANCH` |
| Wide characters and `thread_local` in C++ | Not expected: GCC is configured with `--disable-wchar_t` and `--disable-tls` | `gcc4/Makefile` |

## Measured in emulation

| Item | Result | Source |
|---|---|---|
| UnixLib programs on build.riscos.online | Do not start: no SharedUnixLibrary module | Same run, emulator annotation |

## Measured on hardware

Nothing yet. Gate 1 will add the floating-point, unaligned-access and filename-translation results here.

## Performance

Nothing yet. Milestone 4 records compile times on Titanium.
