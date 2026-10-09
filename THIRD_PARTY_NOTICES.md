# Third-party notices

swmm5plus-capi is Copyright (C) 2026 Ehsan Madadi and licensed under GPL-3.0-or-later. The build downloads the following projects; each keeps its own copyright and license.

## SWMM5+ (CIMM, University of Texas at Austin)

- Source: https://github.com/CIMM-ORG/SWMM5plus, commit `afd44de9ea359ce298dff7aa63b0e77485ccb6b8` (version 1.0.3)
- License: The Unlicense (public domain dedication).
- SWMM5+ was developed under Cooperative Agreement No. 83595001 awarded by the U.S. Environmental Protection Agency to the University of Texas at Austin. It has not been formally reviewed by EPA.
- The build copies the sources into the build tree and inserts the hooks described in `cmake/SourceHooks.cmake`.

## EPA SWMM 5.1.13 (U.S. EPA)

- Source: https://github.com/USEPA/Stormwater-Management-Model, tag v5.1.13
- License: public domain.
- Combined at build time with the SWMM5+ interface files `api.c`, `api_error.c` and the additions to `controls.c`, `funcs.h`, `lid.c` and `lid.h`, as in the upstream SWMM5+ build.

## json-fortran 8.3.0

- Source: https://github.com/jacobwilliams/json-fortran, commit `3ab8f98209871875325c6985dd0e50085d1c82c2`
- License: BSD-style license, Copyright (c) 2014-2022 Jacob Williams. See the LICENSE file in the json-fortran repository.

## HDF5 (The HDF Group)

- Source builds link the HDF5 found on the system. The prebuilt release libraries link HDF5 1.14.6 statically, downloaded from https://github.com/HDFGroup/hdf5.
- License: BSD-style HDF5 license, Copyright 2006 by The HDF Group. The full text is in the COPYING file of the HDF5 distribution.

## GNU Fortran runtime (prebuilt release libraries only)

- `libgfortran` and, where needed, `libquadmath` from GCC are included with the prebuilt libraries.
- License: GPL-3.0 with the GCC Runtime Library Exception, version 3.1 (`libgfortran`), and LGPL-2.1 (`libquadmath`). Source code is available from https://gcc.gnu.org.
