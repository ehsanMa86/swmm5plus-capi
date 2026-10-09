/*
 * swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
 * https://github.com/ehsanMa86/swmm5plus-capi
 *
 * File:    src/s5p_runtime.c
 * Purpose: Starts the Intel Fortran runtime when the library is loaded by a program that is not written in Fortran.
 *
 * Copyright (C) 2026 Ehsan Madadi
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

/* SWMM5+ uses coarrays. With Intel Fortran (ifx/ifort) the coarray runtime is
 * set up by for_rtl_init_, which the compiler calls from the Fortran main
 * program. When a C or C++ program loads this library there is no Fortran
 * main program, and the first Fortran I/O statement crashes in
 * for_rtl_ICAF_THIS_IMAGE. The library therefore starts the runtime itself
 * when it is loaded. GNU Fortran (-fcoarray=single) needs no such step. */

#if defined(S5P_INTEL_FORTRAN) && !defined(_WIN32)

void for_rtl_init_(int* argcount, char** actarg);

__attribute__((constructor)) static void s5p_start_fortran_runtime(void)
{
    static char name[] = "swmm5plus_capi";
    static char* argv[] = {name, 0};
    int argc = 1;
    for_rtl_init_(&argc, argv);
}

#else

/* Nothing to do for this compiler; keeps the translation unit non-empty. */
typedef int s5p_runtime_unused;

#endif
