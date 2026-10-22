/*
 * swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
 * https://github.com/ehsanMa86/swmm5plus-capi
 *
 * File:    src/s5p_hydrology.c
 * Purpose: Subcatchment results and unit factors from EPA SWMM, built into the EPA SWMM library used by SWMM5+.
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

/* SWMM5+ computes hydrology by calling EPA SWMM's runoff routines and keeps no
 * subcatchment results of its own. These functions read the subcatchment
 * state in EPA SWMM the way EPA SWMM's binary output does (rainfall at the
 * reporting time, losses, runoff interpolated between the last two runoff
 * times), in the units of the input file. SWMM5+ loads this library at run
 * time; the C interface finds the functions with s5p_dlsym. */

#include <stdlib.h>
#include <string.h>

#include "headers.h"

#if defined(_WIN32)
#define S5P_SWMMC_EXPORT __declspec(dllexport)
#else
#define S5P_SWMMC_EXPORT __attribute__((visibility("default")))
#endif

/* Property codes, the same as enum s5p_subcatch_property in swmm5plus.h. */
enum
{
    PROP_RAINFALL = 0,
    PROP_EVAPORATION = 1,
    PROP_INFILTRATION = 2,
    PROP_RUNOFF = 3,
    PROP_AREA = 4
};

S5P_SWMMC_EXPORT int s5p_swmmc_subcatch_count(void)
{
    return Nobjects[SUBCATCH];
}

/* Copies the ID of subcatchment @p j into @p buffer (zero-terminated). */
S5P_SWMMC_EXPORT int s5p_swmmc_subcatch_name(int j, char* buffer, int length)
{
    if (j < 0 || j >= Nobjects[SUBCATCH] || !buffer || length <= 0)
        return -1;
    const char* id = Subcatch[j].ID ? Subcatch[j].ID : "";
    strncpy(buffer, id, (size_t)length - 1);
    buffer[length - 1] = '\0';
    return 0;
}

/* Factors from EPA SWMM's internal units (feet, cfs, cubic feet) to the units
 * of the input file. */
S5P_SWMMC_EXPORT int s5p_swmmc_unit_factors(double* flow, double* length, double* volume)
{
    if (flow)
        *flow = UCF(FLOW);
    if (length)
        *length = UCF(LENGTH);
    if (volume)
        *volume = UCF(VOLUME);
    return 0;
}

/* Fills @p values[0..count-1] with property @p property of every
 * subcatchment at @p elapsed_seconds after the simulation start. Returns the
 * number of subcatchments, or -1 for an invalid argument. */
S5P_SWMMC_EXPORT int s5p_swmmc_subcatch_values(double elapsed_seconds, int property, double* values, int count)
{
    const int n = Nobjects[SUBCATCH];
    if (!values || count < n || property < PROP_RAINFALL || property > PROP_AREA)
        return -1;
    if (n == 0)
        return 0;
    if (property == PROP_AREA)
    {
        for (int j = 0; j < n; ++j)
            values[j] = Subcatch[j].area * UCF(LANDAREA);
        return n;
    }

    /* As output_saveSubcatchResults: the rainfall of each gage at the
     * reporting time, and the position of that time between the last two
     * runoff times. */
    const double msec = elapsed_seconds * 1000.0;
    const DateTime when = getDateTime(msec);
    for (int k = 0; k < Nobjects[GAGE]; ++k)
        gage_setReportRainfall(k, when);
    double f = 1.0;
    if (NewRunoffTime > OldRunoffTime)
    {
        f = (msec - OldRunoffTime) / (NewRunoffTime - OldRunoffTime);
        if (f < 0.0)
            f = 0.0;
        if (f > 1.0)
            f = 1.0;
    }

    const int nResults = MAX_SUBCATCH_RESULTS + Nobjects[POLLUT];
    float* x = (float*)calloc((size_t)nResults, sizeof(float));
    if (!x)
        return -1;
    for (int j = 0; j < n; ++j)
    {
        subcatch_getResults(j, f, x);
        switch (property)
        {
        case PROP_RAINFALL:
            values[j] = x[SUBCATCH_RAINFALL];
            break;
        case PROP_EVAPORATION:
            values[j] = x[SUBCATCH_EVAP];
            break;
        case PROP_INFILTRATION:
            values[j] = x[SUBCATCH_INFIL];
            break;
        default:
            values[j] = x[SUBCATCH_RUNOFF];
            break;
        }
    }
    free(x);
    return n;
}
