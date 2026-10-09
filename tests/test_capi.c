/*
 * swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
 * https://github.com/ehsanMa86/swmm5plus-capi
 *
 * File:    tests/test_capi.c
 * Purpose: End-to-end test of the SWMM5+ C interface: runs a model and checks the routed flows.
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

#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#if defined(_WIN32)
#include <direct.h>
#define MKDIR(p) _mkdir(p)
#else
#define MKDIR(p) mkdir(p, 0755)
#endif

struct probe
{
    int links;
    long steps;
    double peak_flow;
    double last_report;
};

static int on_progress(double now, double end, void* user)
{
    struct probe* p = (struct probe*)user;
    double largest = 0.0;
    p->steps++;
    for (int i = 0; i < p->links; ++i)
    {
        double flow = 0.0;
        if (s5p_get_value(S5P_LINK, i, S5P_LINK_FLOW, &flow) == S5P_OK)
        {
            if (flow < 0)
                flow = -flow;
            if (flow > largest)
                largest = flow;
        }
    }
    if (largest > p->peak_flow)
        p->peak_flow = largest;
    if (now - p->last_report >= 3600.0)
    {
        printf("  t = %7.0f of %7.0f s, largest link flow %.4f\n", now, end, largest);
        fflush(stdout);
        p->last_report = now;
    }
    return 0;
}

static int check(int code, const char* what)
{
    if (code != S5P_OK)
    {
        char message[512];
        s5p_last_error(message, (int)sizeof message);
        fprintf(stderr, "%s failed (%d): %s\n", what, code, message);
    }
    return code;
}

int main(int argc, char** argv)
{
    if (argc < 4)
    {
        fprintf(stderr, "usage: s5p_test <model.inp> <output folder> <swmm library folder>\n");
        return 2;
    }
    char version[32];
    s5p_version(version, (int)sizeof version);
    printf("SWMM5+ %s, C interface version %d\n", version, s5p_api_version());
    if (s5p_api_version() != S5P_API_VERSION)
        return 1;

    MKDIR(argv[2]);
    if (check(s5p_open(argv[1], argv[2], NULL, argv[3]), "s5p_open"))
        return 1;
    if (check(s5p_initialize(), "s5p_initialize"))
        return 1;

    int nodes = 0, links = 0;
    s5p_get_count(S5P_NODE, &nodes);
    s5p_get_count(S5P_LINK, &links);
    double start = 0, end = 0, step = 0;
    s5p_get_times(&start, &end, &step);
    char first_node[64] = "", first_link[64] = "";
    s5p_get_name(S5P_NODE, 0, first_node, (int)sizeof first_node);
    s5p_get_name(S5P_LINK, 0, first_link, (int)sizeof first_link);
    printf("%d nodes (first %s), %d links (first %s), %.0f to %.0f s, report step %.0f s\n", nodes, first_node,
           links, first_link, start, end, step);
    if (nodes <= 0 || links <= 0 || end <= start)
        return 1;

    struct probe probe = {links, 0, 0.0, 0.0};
    s5p_set_progress_callback(on_progress, &probe);
    if (check(s5p_run(), "s5p_run"))
        return 1;

    double depth = 0.0;
    s5p_get_value(S5P_NODE, 0, S5P_NODE_DEPTH, &depth);
    printf("final depth at %s: %.4f\n", first_node, depth);
    check(s5p_finalize(), "s5p_finalize");
    s5p_close();

    printf("%ld time steps, peak link flow %.4f\n", probe.steps, probe.peak_flow);
    return (probe.steps > 0 && probe.peak_flow > 0.01) ? 0 : 1;
}
