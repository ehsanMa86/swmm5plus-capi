/*
 * swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
 * https://github.com/ehsanMa86/swmm5plus-capi
 *
 * File:    src/s5p_console.c
 * Purpose: Redirects the console output of SWMM5+ and EPA SWMM while the C interface runs them.
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

/* SWMM5+ (Fortran) and EPA SWMM (C) print progress and diagnostics to
 * standard output, also when they are embedded in another program. A host
 * that uses its standard output itself (for example a solver process that
 * talks to a user interface) asks for that text to go to standard error or
 * nowhere with s5p_set_console. The interface then points file descriptor 1
 * elsewhere while SWMM5+ code runs, and restores it before every callback and
 * before returning, so text the host writes always reaches its own output.
 * Buffers are flushed before each switch; the Fortran side flushes its own
 * standard output unit before calling these functions. */

#if defined(_WIN32)
#include <fcntl.h>
#include <io.h>
#define S5P_DUP _dup
#define S5P_DUP2 _dup2
#define S5P_CLOSE _close
#define S5P_NULL_DEVICE "NUL"
#define S5P_OPEN_WRITE(path) _open(path, _O_WRONLY)
#else
#include <fcntl.h>
#include <unistd.h>
#define S5P_DUP dup
#define S5P_DUP2 dup2
#define S5P_CLOSE close
#define S5P_NULL_DEVICE "/dev/null"
#define S5P_OPEN_WRITE(path) open(path, O_WRONLY)
#endif
#include <stdio.h>

enum
{
    CONSOLE_STDOUT = 0,
    CONSOLE_STDERR = 1,
    CONSOLE_NONE = 2
};

static int console_mode = CONSOLE_STDOUT;
static int saved_stdout = -1; /* copy of the original descriptor 1 while captured */

int s5p_console_set_mode(int mode)
{
    if (mode < CONSOLE_STDOUT || mode > CONSOLE_NONE)
        return -1;
    console_mode = mode;
    return 0;
}

/* Points standard output at the configured destination. */
void s5p_console_capture(void)
{
    if (console_mode == CONSOLE_STDOUT || saved_stdout >= 0)
        return;
    fflush(stdout);
    int target = -1;
    int opened = 0;
    if (console_mode == CONSOLE_STDERR)
    {
        target = 2;
    }
    else
    {
        target = S5P_OPEN_WRITE(S5P_NULL_DEVICE);
        opened = target >= 0;
    }
    if (target < 0)
        return;
    saved_stdout = S5P_DUP(1);
    if (saved_stdout >= 0 && S5P_DUP2(target, 1) < 0)
    {
        S5P_CLOSE(saved_stdout);
        saved_stdout = -1;
    }
    if (opened)
        S5P_CLOSE(target);
}

/* Restores the host's standard output. */
void s5p_console_release(void)
{
    if (saved_stdout < 0)
        return;
    fflush(stdout);
    S5P_DUP2(saved_stdout, 1);
    S5P_CLOSE(saved_stdout);
    saved_stdout = -1;
}
