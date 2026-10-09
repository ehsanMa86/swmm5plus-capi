/*
 * swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
 * https://github.com/ehsanMa86/swmm5plus-capi
 *
 * File:    src/s5p_fs.c
 * Purpose: Portable folder and file operations that replace the shell commands (mkdir, cp, rm) run by SWMM5+.
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
#else
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#endif
#include <stdio.h>
#include <string.h>

/* SWMM5+ originally runs "mkdir", "cp" and "rm" through the shell. Those
 * commands do not exist on Windows (and "mkdir" there treats "/x" as an
 * option), and starting a shell from a library is fragile everywhere, so the
 * build replaces each call with one of the functions below (see
 * cmake/SourceHooks.cmake). They return 0 on success and a non-zero system
 * error code on failure. Paths use the same narrow encoding as the rest of
 * SWMM5+ and EPA SWMM. */

static int is_separator(char c)
{
#if defined(_WIN32)
    return c == '/' || c == '\\';
#else
    return c == '/';
#endif
}

int s5p_fs_folder_exists(const char* path)
{
    if (!path || !*path)
        return 0;
#if defined(_WIN32)
    const DWORD attributes = GetFileAttributesA(path);
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) ? 1 : 0;
#else
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode) ? 1 : 0;
#endif
}

static int make_one_folder(const char* path)
{
    if (s5p_fs_folder_exists(path))
        return 0;
#if defined(_WIN32)
    if (CreateDirectoryA(path, NULL))
        return 0;
    const DWORD error = GetLastError();
    return error == ERROR_ALREADY_EXISTS && s5p_fs_folder_exists(path) ? 0 : (int)error;
#else
    if (mkdir(path, 0777) == 0)
        return 0;
    return errno == EEXIST && s5p_fs_folder_exists(path) ? 0 : errno;
#endif
}

/* Creates @p path and any missing parent folders (like "mkdir -p"). */
int s5p_fs_make_folder(const char* path)
{
    if (!path || !*path)
        return 1;
    char buffer[4096];
    const size_t length = strlen(path);
    if (length >= sizeof buffer)
        return 1;
    memcpy(buffer, path, length + 1);
    /* Remove trailing separators, but keep a root such as "/" or "C:/". */
    size_t end = length;
    while (end > 1 && is_separator(buffer[end - 1]) && buffer[end - 2] != ':')
        buffer[--end] = '\0';

    /* Skip the root: "/", "C:/" or the "//server/share/" of a UNC path. */
    size_t start = 0;
#if defined(_WIN32)
    if (end >= 2 && buffer[1] == ':')
        start = 2;
    else if (end >= 2 && is_separator(buffer[0]) && is_separator(buffer[1]))
    {
        int parts = 0;
        start = 2;
        while (start < end && parts < 2)
        {
            if (is_separator(buffer[start]))
                ++parts;
            ++start;
        }
    }
#endif
    while (start < end && is_separator(buffer[start]))
        ++start;

    for (size_t i = start; i <= end; ++i)
    {
        if (i == end || is_separator(buffer[i]))
        {
            const char saved = buffer[i];
            buffer[i] = '\0';
            const int rc = make_one_folder(buffer);
            buffer[i] = saved;
            if (rc != 0)
                return rc;
        }
    }
    return 0;
}

int s5p_fs_copy_file(const char* from, const char* to)
{
    if (!from || !to || !*from || !*to)
        return 1;
#if defined(_WIN32)
    return CopyFileA(from, to, FALSE) ? 0 : (int)GetLastError();
#else
    FILE* in = fopen(from, "rb");
    if (!in)
        return errno ? errno : 1;
    FILE* out = fopen(to, "wb");
    if (!out)
    {
        const int rc = errno ? errno : 1;
        fclose(in);
        return rc;
    }
    char chunk[65536];
    size_t n;
    int rc = 0;
    while ((n = fread(chunk, 1, sizeof chunk, in)) > 0)
    {
        if (fwrite(chunk, 1, n, out) != n)
        {
            rc = errno ? errno : 1;
            break;
        }
    }
    if (ferror(in))
        rc = rc ? rc : 1;
    fclose(in);
    if (fclose(out) != 0 && rc == 0)
        rc = errno ? errno : 1;
    return rc;
#endif
}

int s5p_fs_delete_file(const char* path)
{
    if (!path || !*path)
        return 1;
#if defined(_WIN32)
    return DeleteFileA(path) ? 0 : (int)GetLastError();
#else
    return unlink(path) == 0 ? 0 : errno;
#endif
}
