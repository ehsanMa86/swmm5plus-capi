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
 * or, with the host driving the time loop (interface version 2),
 *   s5p_open -> s5p_initialize -> s5p_step ... s5p_step -> s5p_finalize -> s5p_close
 *
 * Only one model can be open per process: SWMM5+ keeps its state in Fortran
 * modules. Errors inside SWMM5+ may end the process (Fortran STOP), so host
 * applications should run the solver in a separate process.
 *
 * Indices are zero-based. Times are seconds from the start of the simulation.
 * Values are in the units of the input file (US or SI units, as set by its
 * FLOW_UNITS option), like the results of EPA SWMM. SWMM5+ itself computes in
 * SI units and writes its own output files in SI units.
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

/** Version of this interface. Version 2 only adds functions and enumerators:
 *  every version 1 function keeps its signature and meaning. */
#define S5P_API_VERSION 2

enum s5p_object
{
    S5P_NODE = 0,
    S5P_LINK = 1,
    S5P_SUBCATCH = 2, /**< subcatchments (version 2) */
    S5P_SYSTEM = 3    /**< system-wide totals: one element (version 2) */
};

enum s5p_node_property
{
    S5P_NODE_DEPTH = 0,          /**< water depth above the node invert */
    S5P_NODE_HEAD = 1,           /**< piezometric head */
    S5P_NODE_VOLUME = 2,         /**< stored water volume (version 2) */
    S5P_NODE_LATERAL_INFLOW = 3, /**< external inflow, runoff and other lateral inflow (version 2) */
    S5P_NODE_TOTAL_INFLOW = 4,   /**< lateral inflow plus inflow from links (version 2) */
    S5P_NODE_FLOODING = 5        /**< overflow rate leaving the network or entering a pond (version 2) */
};

enum s5p_link_property
{
    S5P_LINK_FLOW = 0,     /**< flow rate, averaged over the link's finite volumes */
    S5P_LINK_DEPTH = 1,    /**< flow depth, averaged */
    S5P_LINK_VELOCITY = 2, /**< velocity, averaged */
    S5P_LINK_AREA = 3,     /**< flow area, averaged */
    S5P_LINK_VOLUME = 4,   /**< water volume in the link (version 2) */
    S5P_LINK_CAPACITY = 5  /**< conduits: flow area / full area; other links: setting (version 2) */
};

/** Subcatchment properties (version 2), computed by EPA SWMM's hydrology. */
enum s5p_subcatch_property
{
    S5P_SUBCATCH_RAINFALL = 0,     /**< rainfall intensity (in/h or mm/h) */
    S5P_SUBCATCH_EVAPORATION = 1,  /**< evaporation loss (in/day or mm/day) */
    S5P_SUBCATCH_INFILTRATION = 2, /**< infiltration loss (in/h or mm/h) */
    S5P_SUBCATCH_RUNOFF = 3,       /**< runoff flow rate */
    S5P_SUBCATCH_AREA = 4          /**< area (acres or hectares) */
};

/** System-wide totals (version 2); the only index is 0. */
enum s5p_system_property
{
    S5P_SYSTEM_RAINFALL = 0,       /**< area-weighted rainfall intensity */
    S5P_SYSTEM_EVAPORATION = 1,    /**< area-weighted evaporation loss */
    S5P_SYSTEM_INFILTRATION = 2,   /**< area-weighted infiltration loss */
    S5P_SYSTEM_RUNOFF = 3,         /**< total subcatchment runoff */
    S5P_SYSTEM_LATERAL_INFLOW = 4, /**< total lateral inflow to nodes */
    S5P_SYSTEM_FLOODING = 5,       /**< total node flooding */
    S5P_SYSTEM_OUTFLOW = 6,        /**< total flow into outfalls */
    S5P_SYSTEM_STORAGE = 7         /**< total water volume in nodes and links */
};

enum s5p_error
{
    S5P_OK = 0,
    S5P_ERR_STATE = 1,     /**< call not allowed in the current lifecycle state */
    S5P_ERR_ARGUMENT = 2,  /**< invalid object type, index, property or buffer */
    S5P_ERR_CANCELLED = 3, /**< a callback requested a stop */
    S5P_ERR_FILE = 4,      /**< a file or folder does not exist */
    S5P_END = 5            /**< s5p_step: the simulation has ended; not an error (version 2) */
};

/** Destinations for the text SWMM5+ and EPA SWMM print (version 2). */
enum s5p_console
{
    S5P_CONSOLE_STDOUT = 0, /**< standard output (default) */
    S5P_CONSOLE_STDERR = 1, /**< standard error */
    S5P_CONSOLE_NONE = 2    /**< discarded */
};

/**
 * Called once per time step during s5p_run and s5p_step, not during spin-up.
 * Return a non-zero value to stop the simulation at the end of the step.
 */
typedef int (*s5p_progress_fn)(double now_seconds, double end_seconds, void* user_data);

/**
 * Called at every reporting time, at the moment SWMM5+ stores a time level of
 * its own output files, and once more at the end of the simulation (the level
 * SWMM5+ adds when it finalizes). @p period counts the calls from 0;
 * @p seconds is the time SWMM5+ records for the level. Getters called from
 * the callback return the values of that level. Return a non-zero value to
 * stop the simulation at the end of the current step.
 */
typedef int (*s5p_report_fn)(int period, double seconds, void* user_data);

S5P_API int s5p_api_version(void);
/** Copies the SWMM5+ version (for example "1.0.3") into @p buffer. */
S5P_API int s5p_version(char* buffer, int length);

/**
 * Prepares a run. @p inp_file is required. @p output_dir, @p settings_file
 * (a SWMM5+ settings.json) and @p swmm_library_dir (folder of the bundled
 * EPA SWMM library) may be NULL to use defaults. Returns S5P_ERR_FILE when
 * the input file, the settings file or the library folder does not exist,
 * and S5P_ERR_ARGUMENT when the input name lacks ".inp" or a path is longer
 * than SWMM5+ can hold (256 characters once made absolute).
 */
S5P_API int s5p_open(const char* inp_file, const char* output_dir, const char* settings_file,
                     const char* swmm_library_dir);
S5P_API int s5p_set_progress_callback(s5p_progress_fn callback, void* user_data);
/** Registers the reporting callback; NULL removes it. Allowed at any time (version 2). */
S5P_API int s5p_set_report_callback(s5p_report_fn callback, void* user_data);
/** Non-zero turns off SWMM5+'s per-step console output (call before s5p_initialize). */
S5P_API int s5p_set_quiet(int quiet);
/**
 * Sends the text SWMM5+ and EPA SWMM print to @p mode (enum s5p_console)
 * while the functions of this interface run (version 2). Allowed at any time,
 * also before s5p_open. Standard output is restored while callbacks run and
 * whenever a function returns, so the host can keep using it.
 */
S5P_API int s5p_set_console(int mode);
/** Reads the input, partitions the network and sets initial conditions. */
S5P_API int s5p_initialize(void);
/** Runs the time loop to the end of the simulation (or until cancelled). */
S5P_API int s5p_run(void);
/**
 * Advances the simulation by one time step, as an alternative to s5p_run
 * (version 2). The first call also starts the time loop, including any
 * spin-up. Stores the time reached in @p now_seconds (may be NULL). Returns
 * S5P_OK while steps remain and S5P_END once the end is reached, by this call
 * or an earlier one. The host may stop stepping at any time and finalize.
 */
S5P_API int s5p_step(double* now_seconds);
/** Writes the SWMM5+ output files and the final report. */
S5P_API int s5p_finalize(void);
S5P_API int s5p_close(void);

/** Number of objects of a type (S5P_SYSTEM: 1). */
S5P_API int s5p_get_count(int object, int* count);
S5P_API int s5p_get_name(int object, int index, char* buffer, int length);
/** Current value of a property (valid from s5p_initialize until s5p_finalize). */
S5P_API int s5p_get_value(int object, int index, int property, double* value);
/**
 * Current values of a property for every object of a type, in index order
 * (version 2). @p count is the capacity of @p values; it must be at least the
 * number of objects. Valid from s5p_initialize until s5p_finalize.
 */
S5P_API int s5p_get_values(int object, int property, double* values, int count);
/** Simulation start, end and reporting interval, in seconds. */
S5P_API int s5p_get_times(double* start_seconds, double* end_seconds, double* report_step_seconds);
/** Copies the last error message into @p buffer. */
S5P_API int s5p_last_error(char* buffer, int length);

#ifdef __cplusplus
}
#endif

#endif /* SWMM5PLUS_H */
