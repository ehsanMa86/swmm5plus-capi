# swmm5plus-capi

[![CI](https://github.com/ehsanMa86/swmm5plus-capi/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ehsanMa86/swmm5plus-capi/actions/workflows/ci.yml) [![Release](https://img.shields.io/github/v/release/ehsanMa86/swmm5plus-capi)](https://github.com/ehsanMa86/swmm5plus-capi/releases/latest) [![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue)](LICENSE) [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23678730.svg)](https://doi.org/10.5281/zenodo.23678730)

A C interface for [SWMM5+](https://github.com/CIMM-ORG/SWMM5plus), the finite-volume dynamic-wave solver for the EPA Storm Water Management Model developed by CIMM at the University of Texas at Austin.

SWMM5+ is a Fortran program. This project builds it as a shared library with a small, stable C API (`include/swmm5plus.h`), so that applications written in any language can load it like the other SWMM and EPANET engines. [Mirab](https://github.com/ehsanMa86/Mirab) uses it to offer SWMM5+ next to EPA SWMM 5.2.

```c
#include "swmm5plus.h"

s5p_set_console(S5P_CONSOLE_STDERR);           /* keep standard output for the host */
s5p_open("model.inp", "output", NULL, "/path/to/libs");
s5p_initialize();
s5p_set_report_callback(on_report, &state);    /* called at every reporting time */
double now;
while (s5p_step(&now) == S5P_OK)               /* or s5p_run() for the whole loop */
    ;                                          /* the host may pause here */
s5p_finalize();
s5p_close();
```

Inside the reporting callback, `s5p_get_values` reads a property of every node, link or subcatchment at once, or a system total, with exactly the values SWMM5+ stores in its own output at that time, in the units of the input file. Subcatchment rainfall, losses and runoff come from the EPA SWMM hydrology that SWMM5+ runs. See [docs/api.md](docs/api.md).

Interface version 2 adds the reporting callback, bulk values, subcatchments, system totals, node volume, inflows and flooding, link volume and capacity, host-driven stepping (`s5p_step`) and console redirection (`s5p_set_console`). Every version 1 function keeps its signature, so version 1 hosts keep working; values are now in the units of the input file, as version 1 documented, where version 1 libraries returned SI values for models with US flow units.

## How it works

- The SWMM5+, EPA SWMM 5.1.13 and json-fortran sources are downloaded at pinned commits with SHA-256 checksums. Upstream files are never edited in place.
- At configure time the sources are copied into the build tree, where small hooks are added: an API mode that skips command-line parsing, a progress and cancellation call once per time step, a reporting call wherever SWMM5+ stores a level of its output, a step mode in which the unchanged body of the time loop runs one iteration per `s5p_step`, and a portable library loader (`dlopen` or `LoadLibrary`) for the EPA SWMM library. Every edit is anchored on exact upstream text, and configuration fails if an anchor is missing.
- SWMM5+ creates folders and copies or deletes files by running `mkdir`, `cp` and `rm` through the shell. The build replaces each of these calls, and the Intel-only `INQUIRE(DIRECTORY=)` folder tests, with small portable C functions ([src/s5p_fs.c](src/s5p_fs.c)), and lets SWMM5+ recognise Windows drive-letter paths as absolute. No shell is started on any platform.
- For compilers other than Intel Fortran, a set of anchored edits replaces Intel-only extensions with standard Fortran that keeps the Intel behaviour (range array constructors, DEC component separators, non-integer kind arguments, rank-2 initializers, logical and integer mixing, and writes to unallocated boundary arrays). The list is in [cmake/SourceHooks.cmake](cmake/SourceHooks.cmake).
- The result is two libraries: `swmm5plus_capi` (the solver and the C API) and `swmm5plus_swmmc` (EPA SWMM 5.1.13 with the SWMM5+ additions, used for input parsing and hydrology, plus [src/s5p_hydrology.c](src/s5p_hydrology.c), which reads subcatchment results and unit factors for the C API). Keep them in the same folder.
- `s5p_set_console` points file descriptor 1 at standard error or the null device while SWMM5+ code runs, and restores it before every callback and before each function returns ([src/s5p_console.c](src/s5p_console.c)), because SWMM5+ and EPA SWMM print to standard output regardless of their quiet settings.

## Installing

Each [release](https://github.com/ehsanMa86/swmm5plus-capi/releases) carries prebuilt libraries for `windows-x86_64`, `linux-x86_64`, `macos-arm64` and `macos-x86_64`, built by [.github/workflows/release.yml](.github/workflows/release.yml). For each platform there is a manifest, `swmm5plus-capi-<platform>.json` (format `mirab-engine/1`), listing the files, their sizes and SHA-256 checksums. The libraries need no Fortran compiler: HDF5 is linked statically everywhere. On Linux and macOS the GNU Fortran runtime is included and found next to the libraries (`$ORIGIN` on Linux, `@loader_path` on macOS). On Windows the GCC and Fortran runtimes are linked into the two DLLs, which depend on Windows system DLLs only, so they cannot clash with the MinGW runtime DLLs of a host application.

- **With Mirab:** *Project > Simulation engines > Install SWMM5+*, or `mirab-cli engines install swmm5plus-capi-<platform>.json` with the files in the same folder as the manifest.
- **Other applications:** put all files of one platform into one folder, dropping the `swmm5plus-capi-<version>-<platform>-` prefix of the asset names (the manifest gives each file's `name`), and load `libswmm5plus_capi` (`swmm5plus_capi.dll` on Windows) from there.

To publish a release, push a tag such as `v0.1.0`. The workflow builds and tests every platform, runs `tools/package_release.py`, and attaches the files to the GitHub release, with `swmm5plus-capi-<version>-SHA256SUMS.txt` and a signed build provenance attestation for every file (`gh attestation verify <file> --repo ehsanMa86/swmm5plus-capi`). Releases are immutable once published, so a tag with a hyphen (`v0.3.0-rc1`) becomes a draft prerelease, to be published by hand. Each platform's files include the license texts of json-fortran, HDF5 and the GNU Fortran runtime, and `GCC-RUNTIME-SOURCE.txt`, which names the GCC version of the bundled runtime and where its source code is published.

## Building

Requirements: CMake 3.21+, a C compiler, a Fortran compiler (Intel ifx/ifort or GNU gfortran 11+), and HDF5 with Fortran support.

```
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=/path/to/hdf5
cmake --build build
ctest --test-dir build --output-on-failure
cmake --install build --prefix /opt/swmm5plus
```

On Ubuntu, `sudo apt install gfortran libhdf5-dev` provides the dependencies.

With gfortran, `-DS5P_SANITIZE=ON` builds everything with AddressSanitizer and the Fortran run-time checks (`-fcheck=all`), so that a memory error stops the test at the faulty statement. CI runs the test this way on Linux.

On Windows, build in the MINGW64 environment of [MSYS2](https://www.msys2.org) (`pacman -S mingw-w64-x86_64-gcc-fortran mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja`), with HDF5 built from source as a static library with Fortran support. The Windows job in [.github/workflows/release.yml](.github/workflows/release.yml) shows the exact commands, including two settings HDF5 1.14.6 needs with GCC 14 or later. MinGW builds link the GCC and Fortran runtimes statically and export the functions of `swmm5plus.h` only. The SWMM5+ command-line program is not built on Windows, because it would share Fortran module variables with the DLL.

The build runs SWMM5+ in single-image coarray mode (`-fcoarray=single` or `-coarray=single`). Parallel runs on several images still use the SWMM5+ executable and its coarray launcher; the shared library is meant for single-process embedding.

## Status

| Platform | Compiler | State |
|---|---|---|
| Linux | gfortran 13 | Builds and passes the tests: the EXTRAN example runs all 8 simulated hours (241,045 time steps) through the C API, with progress callbacks and clean finalization; the interface version 2 test runs a model with subcatchments with `s5p_run`, with `s5p_step` and with a stop from the reporting callback, also with `-DS5P_SANITIZE=ON`. |
| Linux | Intel ifx | Supported by SWMM5+ upstream; built in CI. |
| macOS | gfortran (Homebrew) | Built and tested by the release workflow on Apple silicon and Intel runners. |
| Windows | MinGW-w64 gfortran 16 | Builds and passes the same EXTRAN test through the C API. Release builds use MSYS2 (MINGW64). |
| Windows | Intel ifx | Not tested. |

**SWMM5+ bugs fixed by the build.** Making SWMM5+ run under gfortran exposed three memory errors in SWMM5+ itself that the Intel build happens to survive. These and one initialization-order error are corrected for every compiler and should be reported upstream:

- the time-step limiter for inflow boundaries applies a WHERE mask over all elements to arrays sized by the boundary elements, writing past their end (`timeloop.f90`);
- the static-output header copies N+1 names and units into N slots (`output.f90`);
- the static output of node elements copies N+1 rows into an array of N rows (`output.f90`). The value written past the end lands in allocator slack on Linux and Windows but aborts the program on macOS ("Heap corruption detected");
- a subcatchment draining to an upstream end, dead end or outfall is connected to the next conduit element, which is recognised by its element type, but the connection is made before the initial conditions set the element types, so every such model stopped with "USER CONFIGURATION ERROR ... diagnostic elements" (`initialization.f90`). The connection is now made after the initial conditions.

The build also removes backslashes at the end of comment lines: the C preprocessor would join the next line into the comment, which in `utility_files.f90` dropped the assignment of a string index.

Test models that point to absolute Windows paths in their `[FILES]` section (for example the SWMM5+ test case `extran4_no_surcharge.inp`) make EPA SWMM 5.1 overflow a buffer on other systems; remove those lines first.

## Notes for host applications

- **One model per process.** SWMM5+ keeps its state in Fortran module variables.
- **Run it in a separate process.** On fatal input errors SWMM5+ executes Fortran `STOP`, which ends the whole process with exit code 0. Mirab runs every engine in its own solver process for this reason.
- **Model limits.** SWMM5+ supports `INERTIAL_DAMPING NONE` only, always uses dynamic-wave routing and does not route pollutants. A subcatchment may drain to a storage node, a junction with three or more links, or an upstream end or outfall next to a conduit, but not to a junction with exactly two links. Every upstream end junction needs an inflow (`[INFLOWS]` or `[DWF]`; a small base flow is enough), otherwise SWMM5+ stops with "nJ1 should be converted to nBCup or nBCdn".
- **Standard output.** SWMM5+ and EPA SWMM print progress and messages to standard output. A host that uses standard output itself calls `s5p_set_console(S5P_CONSOLE_STDERR)` or `S5P_CONSOLE_NONE` before `s5p_open`.

## Feedback and contributing

Report problems and suggest features in [Issues](https://github.com/ehsanMa86/swmm5plus-capi/issues/new/choose); problems in the Mirab application belong in the [Mirab repository](https://github.com/ehsanMa86/Mirab/issues). Pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). Report security problems privately as described in [SECURITY.md](SECURITY.md). Thanks to Robert Dickinson for the review behind release 0.2.3.

## Citing

Each release is archived on Zenodo. Cite the version you used, or all versions with [10.5281/zenodo.23678730](https://doi.org/10.5281/zenodo.23678730); GitHub's *Cite this repository* button gives the reference from [CITATION.cff](CITATION.cff). Please also cite [SWMM5+](https://github.com/CIMM-ORG/SWMM5plus), the solver this library builds.

## License

Copyright (C) 2026 Ehsan Madadi. The C interface, build system and hooks in this repository are licensed under the GNU General Public License, version 3 or later ([LICENSE](LICENSE)).

SWMM5+, EPA SWMM and json-fortran are downloaded at build time and keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). This project is not affiliated with or endorsed by CIMM or the U.S. EPA.
