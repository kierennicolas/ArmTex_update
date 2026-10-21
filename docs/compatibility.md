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
| Soft-float test programs on build.riscos.online (RISC OS Pyromaniac) | All checks pass, once the toolchain's SharedUnixLibrary 1.16 module is uploaded with them; the service has none of its own | [39652781660](https://github.com/kierennicolas/ArmTex_update/actions/runs/39652781660), emulator annotation |
| VFP test programs on the same service | Do not start: no VFPSupport module | Same run |
| Layout of a `double` in memory, soft-float build | FPA word order (`00 00 f0 3f 00 00 00 00` for 1.0), not little-endian IEEE | Same run, `float` INFO line |
| UnixLib filename translation | `article.cls` becomes `article/cls` with or without suffix swapping; `foo.c` becomes `c.foo` with it and `foo/c` without; dots in directory names become `/`; `/tmp` maps to `<Wimp$ScrapDir>` | Same run, `hello` INFO lines |

## Measured on hardware

Nothing yet. Gate 1 will add the floating-point, unaligned-access and filename-translation results here.

## Performance

Nothing yet. Milestone 4 records compile times on Titanium.
