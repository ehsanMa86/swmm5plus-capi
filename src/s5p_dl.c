/*
 * swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
 * https://github.com/ehsanMa86/swmm5plus-capi
 *
 * File:    src/s5p_dl.c
 * Purpose: Portable replacements for dlopen, dlsym and dlclose used by the patched SWMM5+ library loader.
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
#if defined(_WIN32)
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#else
#include <dlfcn.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#endif
#include <stdio.h>

/* SWMM5+ calls these through Fortran interfaces (see c_library.f90). They
 * are used inside this library only; on Windows the exported functions are
 * the ones listed in the generated module-definition file (CMakeLists.txt). */
#if defined(_WIN32)
#define S5P_EXPORT
#else
#define S5P_EXPORT __attribute__((visibility("default")))
#endif

S5P_EXPORT void* s5p_dlopen(const char* filename, int mode)
{
#if defined(_WIN32)
    (void)mode;
    if (!filename)
        return NULL;
    /* LOAD_WITH_ALTERED_SEARCH_PATH requires backslashes. */
    char path[MAX_PATH * 4];
    const size_t n = strlen(filename);
    if (n >= sizeof path)
        return NULL;
    for (size_t i = 0; i <= n; ++i)
        path[i] = filename[i] == '/' ? '\\' : filename[i];
    return (void*)LoadLibraryExA(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
#else
    (void)mode;
    return dlopen(filename, RTLD_NOW | RTLD_LOCAL);
#endif
}

S5P_EXPORT void* s5p_dlsym(void* handle, const char* name)
{
#if defined(_WIN32)
    return (void*)GetProcAddress((HMODULE)handle, name);
#else
    return dlsym(handle, name);
#endif
}

S5P_EXPORT int s5p_dlclose(void* handle)
{
#if defined(_WIN32)
    return FreeLibrary((HMODULE)handle) ? 0 : -1;
#else
    return dlclose(handle);
#endif
}

/* Writes the absolute form of @p path into @p out. SWMM5+ joins relative
 * paths with its working folder incorrectly, so the C interface always hands
 * it absolute paths. The path does not need to exist. Returns 0 on success. */
int s5p_absolute_path(const char* path, char* out, int length)
{
    if (!path || !out || length <= 1)
        return -1;
#if defined(_WIN32)
    if (!_fullpath(out, path, (size_t)length))
        return -1;
    /* SWMM5+ splits and joins paths at "/", which Windows also accepts. */
    for (char* c = out; *c; ++c)
        if (*c == '\\')
            *c = '/';
    return 0;
#else
    if (path[0] == '/')
    {
        if ((int)strlen(path) >= length)
            return -1;
        strcpy(out, path);
        return 0;
    }
    char cwd[PATH_MAX];
    if (!getcwd(cwd, sizeof cwd))
        return -1;
    const char* rel = path;
    while (rel[0] == '.' && rel[1] == '/')
        rel += 2;
    int n = snprintf(out, (size_t)length, "%s/%s", cwd, rel);
    return (n < 0 || n >= length) ? -1 : 0;
#endif
}
