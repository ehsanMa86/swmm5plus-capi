/*
 * swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
 * https://github.com/ehsanMa86/swmm5plus-capi
 *
 * File:    tests/test_api.c
 * Purpose: Test of the interface version 2 functions: reporting callback, bulk values, subcatchments, system totals, stepping and console.
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
#include "swmm5plus.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#if defined(_WIN32)
#include <direct.h>
#define MKDIR(p) _mkdir(p)
#else
#define MKDIR(p) mkdir(p, 0755)
#endif

#define MAX_OBJECTS 64

static int failures = 0;

#define EXPECT(cond)                                                                                         \
    do                                                                                                       \
    {                                                                                                        \
        if (!(cond))                                                                                         \
        {                                                                                                    \
            printf("FAILED line %d: %s\n", __LINE__, #cond);                                                 \
            ++failures;                                                                                      \
        }                                                                                                    \
    } while (0)

struct run
{
    int nodes, links, subcatchments;
    int reports;
    int steps;
    int cancel_at; /* report period that asks to stop, or -1 */
    double last_seconds;
    double report_step;
    double peak_rain, peak_runoff, peak_outflow, peak_sub_runoff[MAX_OBJECTS];
    double runoff_volume, outflow_volume;
    double last_flow[MAX_OBJECTS];
    double last_depth[MAX_OBJECTS];
    double last_runoff[MAX_OBJECTS];
};

static double system_value(int property)
{
    double v = -1.0;
    EXPECT(s5p_get_values(S5P_SYSTEM, property, &v, 1) == S5P_OK);
    return v;
}

static int on_progress(double now, double end, void* user)
{
    struct run* r = (struct run*)user;
    (void)end;
    r->steps++;
    EXPECT(now > 0.0);
    return 0;
}

static int on_report(int period, double seconds, void* user)
{
    struct run* r = (struct run*)user;
    double flow[MAX_OBJECTS], depth[MAX_OBJECTS], runoff[MAX_OBJECTS], one = 0.0;
    if (period == 0)
        printf("report callback output is visible\n");
    EXPECT(period == r->reports);
    EXPECT(period == 0 || seconds > r->last_seconds);
    r->reports++;
    const double dt = period == 0 ? 0.0 : seconds - r->last_seconds;
    r->last_seconds = seconds;

    EXPECT(s5p_get_values(S5P_LINK, S5P_LINK_FLOW, flow, MAX_OBJECTS) == S5P_OK);
    EXPECT(s5p_get_values(S5P_NODE, S5P_NODE_DEPTH, depth, MAX_OBJECTS) == S5P_OK);
    EXPECT(s5p_get_values(S5P_SUBCATCH, S5P_SUBCATCH_RUNOFF, runoff, MAX_OBJECTS) == S5P_OK);
    /* The single-value getter agrees with the bulk getter. */
    EXPECT(s5p_get_value(S5P_LINK, r->links - 1, S5P_LINK_FLOW, &one) == S5P_OK);
    EXPECT(one == flow[r->links - 1]);
    EXPECT(s5p_get_value(S5P_SUBCATCH, 1, S5P_SUBCATCH_RUNOFF, &one) == S5P_OK);
    EXPECT(one == runoff[1]);
    EXPECT(s5p_get_value(S5P_SYSTEM, 0, S5P_SYSTEM_RUNOFF, &one) == S5P_OK);

    double sum = 0.0;
    for (int i = 0; i < r->subcatchments; ++i)
    {
        sum += runoff[i];
        if (runoff[i] > r->peak_sub_runoff[i])
            r->peak_sub_runoff[i] = runoff[i];
        r->last_runoff[i] = runoff[i];
    }
    EXPECT(fabs(sum - one) <= 1e-9 * (1.0 + fabs(sum)));
    for (int i = 0; i < r->links; ++i)
        r->last_flow[i] = flow[i];
    for (int i = 0; i < r->nodes; ++i)
        r->last_depth[i] = depth[i];

    const double rain = system_value(S5P_SYSTEM_RAINFALL);
    const double outflow = system_value(S5P_SYSTEM_OUTFLOW);
    EXPECT(system_value(S5P_SYSTEM_STORAGE) >= 0.0);
    EXPECT(system_value(S5P_SYSTEM_FLOODING) >= 0.0);
    EXPECT(system_value(S5P_SYSTEM_LATERAL_INFLOW) >= -1e-9);
    EXPECT(system_value(S5P_SYSTEM_INFILTRATION) >= 0.0);
    EXPECT(system_value(S5P_SYSTEM_EVAPORATION) >= 0.0);
    if (rain > r->peak_rain)
        r->peak_rain = rain;
    if (one > r->peak_runoff)
        r->peak_runoff = one;
    if (outflow > r->peak_outflow)
        r->peak_outflow = outflow;
    r->runoff_volume += one * dt;
    r->outflow_volume += outflow * dt;

    double node_values[MAX_OBJECTS], link_values[MAX_OBJECTS];
    for (int p = S5P_NODE_DEPTH; p <= S5P_NODE_FLOODING; ++p)
        EXPECT(s5p_get_values(S5P_NODE, p, node_values, MAX_OBJECTS) == S5P_OK);
    for (int p = S5P_LINK_FLOW; p <= S5P_LINK_CAPACITY; ++p)
        EXPECT(s5p_get_values(S5P_LINK, p, link_values, MAX_OBJECTS) == S5P_OK);
    for (int i = 0; i < r->links; ++i)
        EXPECT(link_values[i] >= 0.0 && link_values[i] <= 1.0); /* capacity */

    if (period % 6 == 0)
    {
        printf("  period %2d at %6.0f s: rain %.3f in/h, runoff %.3f cfs, outflow %.3f cfs\n", period, seconds,
               rain, one, outflow);
        fflush(stdout);
    }
    return period == r->cancel_at ? 1 : 0;
}

static int copy_file(const char* from, const char* to)
{
    FILE* in = fopen(from, "rb");
    FILE* out = in ? fopen(to, "wb") : NULL;
    char buffer[4096];
    size_t n;
    int ok = in && out;
    while (ok && (n = fread(buffer, 1, sizeof buffer, in)) > 0)
        ok = fwrite(buffer, 1, n, out) == n;
    if (in)
        fclose(in);
    if (out)
        ok = fclose(out) == 0 && ok;
    return ok;
}

static int check(int code, const char* what)
{
    if (code != S5P_OK)
    {
        char message[512];
        s5p_last_error(message, (int)sizeof message);
        printf("%s failed (%d): %s\n", what, code, message);
        ++failures;
    }
    return code;
}

int main(int argc, char** argv)
{
    if (argc < 5)
    {
        fprintf(stderr, "usage: s5p_api_test <run|step|cancel> <model.inp> <output folder> <swmm library folder>\n");
        return 2;
    }
    const char* mode = argv[1];
    const int stepping = strcmp(mode, "run") != 0;
    const int cancelling = strcmp(mode, "cancel") == 0;
    printf("interface version %d, mode %s\n", s5p_api_version(), mode);
    EXPECT(s5p_api_version() == 2);

    /* Console: any mode before s5p_open; nothing SWMM5+ prints may reach
     * standard output (the test fails on its texts, see CMakeLists.txt). */
    EXPECT(s5p_set_console(7) == S5P_ERR_ARGUMENT);
    EXPECT(s5p_set_console(S5P_CONSOLE_STDERR) == S5P_OK);
    EXPECT(s5p_set_console(S5P_CONSOLE_NONE) == S5P_OK);
    /* S5P_TEST_STDERR=1 keeps SWMM5+'s messages (on standard error) for debugging. */
    if (getenv("S5P_TEST_STDERR"))
        EXPECT(s5p_set_console(S5P_CONSOLE_STDERR) == S5P_OK);

    double t = -1.0, values[MAX_OBJECTS];
    EXPECT(s5p_step(&t) == S5P_ERR_STATE);
    EXPECT(s5p_get_values(S5P_NODE, S5P_NODE_DEPTH, values, MAX_OBJECTS) == S5P_ERR_STATE);

    /* The model runs from a copy that must be deletable once the model is
     * closed: on Windows a file that SWMM5+ left open cannot be removed. */
    MKDIR(argv[3]);
    char input[1024];
    snprintf(input, sizeof input, "%s/input.inp", argv[3]);
    if (!copy_file(argv[2], input))
    {
        printf("FAILED: cannot copy %s to %s\n", argv[2], input);
        return 1;
    }
    if (check(s5p_open(input, argv[3], NULL, argv[4]), "s5p_open"))
        return 1;
    if (check(s5p_initialize(), "s5p_initialize"))
        return 1;

    struct run r;
    memset(&r, 0, sizeof r);
    r.cancel_at = cancelling ? 3 : -1;
    EXPECT(s5p_get_count(S5P_NODE, &r.nodes) == S5P_OK && r.nodes == 7);
    EXPECT(s5p_get_count(S5P_LINK, &r.links) == S5P_OK && r.links == 6);
    EXPECT(s5p_get_count(S5P_SUBCATCH, &r.subcatchments) == S5P_OK && r.subcatchments == 3);
    int systems = 0;
    EXPECT(s5p_get_count(S5P_SYSTEM, &systems) == S5P_OK && systems == 1);
    EXPECT(s5p_get_count(9, &systems) == S5P_ERR_ARGUMENT);
    if (r.nodes > MAX_OBJECTS || r.links > MAX_OBJECTS || r.subcatchments > MAX_OBJECTS)
        return 1;

    char name[32] = "";
    EXPECT(s5p_get_name(S5P_SUBCATCH, 2, name, (int)sizeof name) == S5P_OK && strcmp(name, "S3") == 0);
    EXPECT(s5p_get_name(S5P_SUBCATCH, 3, name, (int)sizeof name) == S5P_ERR_ARGUMENT);
    EXPECT(s5p_get_name(S5P_SYSTEM, 0, name, (int)sizeof name) == S5P_OK && strcmp(name, "System") == 0);
    EXPECT(s5p_get_name(S5P_LINK, 3, name, (int)sizeof name) == S5P_OK && strcmp(name, "C4") == 0);

    /* Bulk values: argument checks, then static values in the input units. */
    EXPECT(s5p_get_values(S5P_NODE, S5P_NODE_DEPTH, values, r.nodes - 1) == S5P_ERR_ARGUMENT);
    EXPECT(s5p_get_values(S5P_NODE, S5P_NODE_DEPTH, NULL, MAX_OBJECTS) == S5P_ERR_ARGUMENT);
    EXPECT(s5p_get_values(S5P_NODE, 42, values, MAX_OBJECTS) == S5P_ERR_ARGUMENT);
    EXPECT(s5p_get_values(S5P_LINK, S5P_LINK_CAPACITY + 1, values, MAX_OBJECTS) == S5P_ERR_ARGUMENT);
    EXPECT(s5p_get_values(S5P_SUBCATCH, S5P_SUBCATCH_AREA + 1, values, MAX_OBJECTS) == S5P_ERR_ARGUMENT);
    EXPECT(s5p_get_values(S5P_SYSTEM, S5P_SYSTEM_STORAGE + 1, values, 1) == S5P_ERR_ARGUMENT);
    EXPECT(s5p_get_values(5, 0, values, MAX_OBJECTS) == S5P_ERR_ARGUMENT);
    EXPECT(s5p_get_value(S5P_SYSTEM, 1, S5P_SYSTEM_RUNOFF, values) == S5P_ERR_ARGUMENT);
    EXPECT(s5p_get_values(S5P_SUBCATCH, S5P_SUBCATCH_AREA, values, MAX_OBJECTS) == S5P_OK);
    EXPECT(fabs(values[0] - 4.0) < 1e-6 && fabs(values[1] - 6.0) < 1e-6 && fabs(values[2] - 8.0) < 1e-6);

    double start = 0, end = 0;
    s5p_get_times(&start, &end, &r.report_step);
    EXPECT(r.report_step == 300.0 && end == 7200.0);

    EXPECT(s5p_set_progress_callback(on_progress, &r) == S5P_OK);
    EXPECT(s5p_set_report_callback(on_report, &r) == S5P_OK);
    int rc;
    if (!stepping)
    {
        rc = s5p_run();
        EXPECT(rc == S5P_OK);
    }
    else
    {
        double previous = 0.0;
        int calls = 0;
        while ((rc = s5p_step(&t)) == S5P_OK)
        {
            EXPECT(t > previous);
            previous = t;
            ++calls;
        }
        printf("%d calls to s5p_step\n", calls);
        if (cancelling)
        {
            EXPECT(rc == S5P_ERR_CANCELLED);
            EXPECT(s5p_step(&t) == S5P_ERR_CANCELLED);
        }
        else
        {
            EXPECT(rc == S5P_END);
            EXPECT(fabs(t - end) < 1.0);
            EXPECT(s5p_step(&t) == S5P_END);
            EXPECT(calls + 1 == r.steps);
        }
    }

    if (cancelling)
    {
        EXPECT(r.reports == 4);
    }
    else
    {
        /* A level every 5 minutes from 0 to 115 minutes, and the final one. */
        EXPECT(r.reports == 25);
        EXPECT(fabs(r.last_seconds - end) < 1.0);
        /* The values stay those of the final level until s5p_finalize. */
        EXPECT(s5p_get_values(S5P_LINK, S5P_LINK_FLOW, values, MAX_OBJECTS) == S5P_OK);
        for (int i = 0; i < r.links; ++i)
            EXPECT(values[i] == r.last_flow[i]);
        EXPECT(s5p_get_values(S5P_SUBCATCH, S5P_SUBCATCH_RUNOFF, values, MAX_OBJECTS) == S5P_OK);
        for (int i = 0; i < r.subcatchments; ++i)
            EXPECT(values[i] == r.last_runoff[i]);

        /* Plausible hydrology in US units: the storm peaks at 2.8 in/h over
         * 18 acres (at most about 51 cfs of runoff), the most impervious
         * subcatchment (S2) yields more runoff than S1, and most of the
         * runoff volume has left through the outfall after two hours. */
        printf("peak rain %.3f in/h, peak runoff %.3f cfs, peak outflow %.3f cfs\n", r.peak_rain, r.peak_runoff,
               r.peak_outflow);
        printf("runoff volume %.0f ft3, outflow volume %.0f ft3\n", r.runoff_volume, r.outflow_volume);
        EXPECT(r.peak_rain > 1.0 && r.peak_rain <= 2.8 + 1e-6);
        EXPECT(r.peak_runoff > 5.0 && r.peak_runoff < 51.0);
        EXPECT(r.peak_sub_runoff[1] > r.peak_sub_runoff[0]);
        EXPECT(r.peak_outflow > 0.5 * r.peak_runoff);
        EXPECT(r.outflow_volume > 0.6 * r.runoff_volume && r.outflow_volume < 1.1 * r.runoff_volume);
    }

    EXPECT(check(s5p_finalize(), "s5p_finalize") == S5P_OK);
    EXPECT(s5p_get_values(S5P_NODE, S5P_NODE_DEPTH, values, MAX_OBJECTS) == S5P_ERR_STATE);
    EXPECT(s5p_step(&t) == S5P_ERR_STATE);
    s5p_close();
    EXPECT(remove(input) == 0);

    printf("%d reports, %d time steps\n", r.reports, r.steps);
    if (failures == 0)
        printf("interface version 2 test passed\n");
    return failures == 0 ? 0 : 1;
}
