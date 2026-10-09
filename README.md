# swmm5plus-capi

A C interface for [SWMM5+](https://github.com/CIMM-ORG/SWMM5plus), the finite-volume dynamic-wave solver for the EPA Storm Water Management Model developed by CIMM at the University of Texas at Austin.

SWMM5+ is a Fortran program. This project builds it as a shared library with a small, stable C API (`include/swmm5plus.h`), so that applications written in any language can load it like the other SWMM and EPANET engines. [Anahita](https://github.com/ehsanMa86/Anahita) uses it to offer SWMM5+ next to EPA SWMM 5.2.

```c
#include "swmm5plus.h"

s5p_open("model.inp", "output", NULL, "/path/to/libs");
s5p_initialize();
s5p_set_progress_callback(on_step, &state);   /* called once per time step */
s5p_run();
s5p_finalize();
s5p_close();
```

Inside the callback, `s5p_get_value` reads node depth and head, and link flow, depth, velocity and area. Return a non-zero value to stop the run. See [docs/api.md](docs/api.md).

## How it works

- The SWMM5+, EPA SWMM 5.1.13 and json-fortran sources are downloaded at pinned commits with SHA-256 checksums. Upstream files are never edited in place.
- At configure time the sources are copied into the build tree, where three small hooks are added: an API mode that skips command-line parsing, a progress and cancellation call once per time step, and a portable library loader (`dlopen` or `LoadLibrary`) for the EPA SWMM library. Every edit is anchored on exact upstream text, and configuration fails if an anchor is missing.
- SWMM5+ creates folders and copies or deletes files by running `mkdir`, `cp` and `rm` through the shell. The build replaces each of these calls, and the Intel-only `INQUIRE(DIRECTORY=)` folder tests, with small portable C functions ([src/s5p_fs.c](src/s5p_fs.c)), and lets SWMM5+ recognise Windows drive-letter paths as absolute. No shell is started on any platform.
- For compilers other than Intel Fortran, a set of anchored edits replaces Intel-only extensions with standard Fortran that keeps the Intel behaviour (range array constructors, DEC component separators, non-integer kind arguments, rank-2 initializers, logical and integer mixing, and writes to unallocated boundary arrays). The list is in [cmake/SourceHooks.cmake](cmake/SourceHooks.cmake).
- The result is two libraries: `swmm5plus_capi` (the solver and the C API) and `swmm5plus_swmmc` (EPA SWMM 5.1.13 with the SWMM5+ additions, used for input parsing and hydrology). Keep them in the same folder.

## Installing

Each [release](https://github.com/ehsanMa86/swmm5plus-capi/releases) carries prebuilt libraries for `windows-x86_64`, `linux-x86_64`, `macos-arm64` and `macos-x86_64`, built by [.github/workflows/release.yml](.github/workflows/release.yml). For each platform there is a manifest, `swmm5plus-capi-<platform>.json` (format `anahita-engine/1`), listing the files, their sizes and SHA-256 checksums. The libraries need no Fortran compiler: HDF5 is linked statically everywhere. On Linux and macOS the GNU Fortran runtime is included and found next to the libraries (`$ORIGIN` on Linux, `@loader_path` on macOS). On Windows the GCC and Fortran runtimes are linked into the two DLLs, which depend on Windows system DLLs only, so they cannot clash with the MinGW runtime DLLs of a host application.

- **With Anahita:** *Tools > Simulation engines > Install SWMM5+*, or `anahita-cli engines install swmm5plus-capi-<platform>.json` with the files in the same folder as the manifest.
- **Other applications:** put all files of one platform into one folder, dropping the `swmm5plus-capi-<version>-<platform>-` prefix of the asset names (the manifest gives each file's `name`), and load `libswmm5plus_capi` (`swmm5plus_capi.dll` on Windows) from there.

To publish a release, push a tag such as `v0.1.0`. The workflow builds and tests every platform, runs `tools/package_release.py`, and attaches the files to the GitHub release.

## Building

Requirements: CMake 3.21+, a C compiler, a Fortran compiler (Intel ifx/ifort or GNU gfortran 11+), and HDF5 with Fortran support.

```
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=/path/to/hdf5
cmake --build build
ctest --test-dir build --output-on-failure
cmake --install build --prefix /opt/swmm5plus
```

On Ubuntu, `sudo apt install gfortran libhdf5-dev` provides the dependencies.

On Windows, build in the MINGW64 environment of [MSYS2](https://www.msys2.org) (`pacman -S mingw-w64-x86_64-gcc-fortran mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja`), with HDF5 built from source as a static library with Fortran support. The Windows job in [.github/workflows/release.yml](.github/workflows/release.yml) shows the exact commands, including two settings HDF5 1.14.6 needs with GCC 14 or later. MinGW builds link the GCC and Fortran runtimes statically and export the functions of `swmm5plus.h` only. The SWMM5+ command-line program is not built on Windows, because it would share Fortran module variables with the DLL.

The build runs SWMM5+ in single-image coarray mode (`-fcoarray=single` or `-coarray=single`). Parallel runs on several images still use the SWMM5+ executable and its coarray launcher; the shared library is meant for single-process embedding.

## Status

| Platform | Compiler | State |
|---|---|---|
| Linux | gfortran 13 | Builds and passes the test: the EXTRAN example runs all 8 simulated hours (241,045 time steps) through the C API, with progress callbacks and clean finalization. |
| Linux | Intel ifx | Supported by SWMM5+ upstream; built in CI. |
| macOS | gfortran (Homebrew) | Built and tested by the release workflow on Apple silicon and Intel runners. |
| Windows | MinGW-w64 gfortran 16 | Builds and passes the same EXTRAN test through the C API. Release builds use MSYS2 (MINGW64). |
| Windows | Intel ifx | Not tested. |

**SWMM5+ bugs fixed by the build.** Making SWMM5+ run under gfortran exposed two memory errors in SWMM5+ itself that the Intel build happens to survive. Both are corrected for every compiler and should be reported upstream:

- the time-step limiter for inflow boundaries applies a WHERE mask over all elements to arrays sized by the boundary elements, writing past their end (`timeloop.f90`);
- the static-output header copies N+1 names and units into N slots (`output.f90`).

Test models that point to absolute Windows paths in their `[FILES]` section (for example the SWMM5+ test case `extran4_no_surcharge.inp`) make EPA SWMM 5.1 overflow a buffer on other systems; remove those lines first.

## Notes for host applications

- **One model per process.** SWMM5+ keeps its state in Fortran module variables.
- **Run it in a separate process.** On fatal input errors SWMM5+ executes Fortran `STOP`, which ends the whole process with exit code 0. Anahita runs every engine in its own solver process for this reason.
- **Model limits.** SWMM5+ supports `INERTIAL_DAMPING NONE` only, always uses dynamic-wave routing, does not route pollutants, and requires subcatchment outlets to drain into storage nodes or conduit-connected junctions.

## License

Copyright (C) 2026 Ehsan Madadi. The C interface, build system and hooks in this repository are licensed under the GNU General Public License, version 3 or later ([LICENSE](LICENSE)).

SWMM5+, EPA SWMM and json-fortran are downloaded at build time and keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). This project is not affiliated with or endorsed by CIMM or the U.S. EPA.
