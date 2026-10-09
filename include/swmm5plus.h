/*
 * swmm5plus-capi - C interface for the SWMM5+ hydraulic solver
 * https://github.com/ehsanMa86/swmm5plus-capi
 *
 * File:    include/swmm5plus.h
 * Purpose: Public C interface of the SWMM5+ hydraulic solver.
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
#ifndef SWMM5PLUS_H
#define SWMM5PLUS_H

/*
 * Lifecycle
 *   s5p_open -> s5p_initialize -> s5p_run -> s5p_finalize -> s5p_close
 *
 * Only one model can be open per process: SWMM5+ keeps its state in Fortran
 * modules. Errors inside SWMM5+ may end the process (Fortran STOP), so host
 * applications should run the solver in a separate process.
 *
 * Indices are zero-based. Times are seconds from the start of the simulation.
 * Values are in the units of the input file.
 */

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#if defined(SWMM5PLUS_CAPI_BUILD)
#define S5P_API __declspec(dllexport)
#else
#define S5P_API __declspec(dllimport)
#endif
#else
#define S5P_API __attribute__((visibility("default")))
#endif

/** Version of this interface; changes whenever a signature changes. */
#define S5P_API_VERSION 1

enum s5p_object
{
    S5P_NODE = 0,
    S5P_LINK = 1
};

enum s5p_node_property
{
    S5P_NODE_DEPTH = 0, /**< water depth above the node invert */
    S5P_NODE_HEAD = 1   /**< piezometric head */
};

enum s5p_link_property
{
    S5P_LINK_FLOW = 0,     /**< flow rate, averaged over the link's finite volumes */
    S5P_LINK_DEPTH = 1,    /**< flow depth, averaged */
    S5P_LINK_VELOCITY = 2, /**< velocity, averaged */
    S5P_LINK_AREA = 3      /**< flow area, averaged */
};

enum s5p_error
{
    S5P_OK = 0,
    S5P_ERR_STATE = 1,      /**< call not allowed in the current lifecycle state */
    S5P_ERR_ARGUMENT = 2,   /**< invalid object type, index or property */
    S5P_ERR_CANCELLED = 3,  /**< the progress callback requested a stop */
    S5P_ERR_FILE = 4        /**< a file or folder does not exist */
};

/**
 * Called once per time step during s5p_run. Return a non-zero value to
 * stop the simulation at the end of the current step.
 */
typedef int (*s5p_progress_fn)(double now_seconds, double end_seconds, void* user_data);

S5P_API int s5p_api_version(void);
/** Copies the SWMM5+ version (for example "1.0.3") into @p buffer. */
S5P_API int s5p_version(char* buffer, int length);

/**
 * Prepares a run. @p inp_file is required. @p output_dir, @p settings_file
 * (a SWMM5+ settings.json) and @p swmm_library_dir (folder of the bundled
 * EPA SWMM library) may be NULL to use defaults.
 */
S5P_API int s5p_open(const char* inp_file, const char* output_dir, const char* settings_file,
                     const char* swmm_library_dir);
S5P_API int s5p_set_progress_callback(s5p_progress_fn callback, void* user_data);
/** Non-zero turns off SWMM5+'s per-step console output (call before s5p_initialize). */
S5P_API int s5p_set_quiet(int quiet);
/** Reads the input, partitions the network and sets initial conditions. */
S5P_API int s5p_initialize(void);
/** Runs the time loop to the end of the simulation (or until cancelled). */
S5P_API int s5p_run(void);
/** Writes the SWMM5+ output files and the final report. */
S5P_API int s5p_finalize(void);
S5P_API int s5p_close(void);

S5P_API int s5p_get_count(int object, int* count);
S5P_API int s5p_get_name(int object, int index, char* buffer, int length);
/** Current value of a node or link property (valid after s5p_initialize). */
S5P_API int s5p_get_value(int object, int index, int property, double* value);
/** Simulation start, end and reporting interval, in seconds. */
S5P_API int s5p_get_times(double* start_seconds, double* end_seconds, double* report_step_seconds);
/** Copies the last error message into @p buffer. */
S5P_API int s5p_last_error(char* buffer, int length);

#ifdef __cplusplus
}
#endif

#endif /* SWMM5PLUS_H */
