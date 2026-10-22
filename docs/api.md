# SWMM5+ C interface reference

All functions return `S5P_OK` (0) on success or an error code. `s5p_last_error` describes the last error. Indices are zero-based and follow the order of the objects in the input file. Times are seconds from the simulation start. Values are in the units of the input file: US units for `FLOW_UNITS` CFS, GPM and MGD, SI units for CMS, LPS and MLD, with flows in the flow units, as in EPA SWMM's results. (SWMM5+ itself computes in SI units and writes its own output files in SI units.)

The interface version is 2 (`S5P_API_VERSION`, `s5p_api_version()`). Version 2 only adds functions and enumerators; the functions of version 1 keep their signatures. Functions and values marked *v2* need a version 2 library.

## Lifecycle

```
s5p_open -> s5p_initialize -> s5p_run                -> s5p_finalize -> s5p_close
s5p_open -> s5p_initialize -> s5p_step ... s5p_step  -> s5p_finalize -> s5p_close   (v2)
```

| Function | Purpose |
|---|---|
| `int s5p_api_version(void)` | Interface version: `2`. |
| `int s5p_version(char* buf, int len)` | SWMM5+ version string, for example `1.0.3`. |
| `int s5p_set_console(int mode)` | *v2.* Where the text SWMM5+ and EPA SWMM print goes while the interface runs them: `S5P_CONSOLE_STDOUT` (default), `S5P_CONSOLE_STDERR` or `S5P_CONSOLE_NONE`. Allowed at any time, also before `s5p_open`. |
| `int s5p_open(const char* inp, const char* output_dir, const char* settings, const char* swmm_library_dir)` | Prepares a run. Paths may be relative; they are made absolute. `output_dir`, `settings` and `swmm_library_dir` may be `NULL`. |
| `int s5p_set_progress_callback(s5p_progress_fn fn, void* user)` | Registers the per-step callback. `NULL` removes it. |
| `int s5p_set_report_callback(s5p_report_fn fn, void* user)` | *v2.* Registers the reporting callback. `NULL` removes it. Allowed at any time. |
| `int s5p_set_quiet(int quiet)` | Non-zero turns off the per-step console output of SWMM5+. Call before `s5p_initialize`. |
| `int s5p_initialize(void)` | Reads the input through EPA SWMM, partitions the network and sets initial conditions. |
| `int s5p_run(void)` | Runs the time loop. Returns `S5P_ERR_CANCELLED` when a callback asked to stop. |
| `int s5p_step(double* now)` | *v2.* Runs one time step instead of `s5p_run`; the first call also starts the loop (and any spin-up). Stores the time reached in `now` (may be `NULL`). Returns `S5P_OK` while steps remain, `S5P_END` once the end has been reached (by this call or before), or `S5P_ERR_CANCELLED`. The host may stop at any time and finalize. |
| `int s5p_finalize(void)` | Writes the SWMM5+ output files. Allowed after `s5p_run` and after any `s5p_step`. |
| `int s5p_close(void)` | Releases the interface. A process can run one model only. |

## Queries

| Function | Purpose |
|---|---|
| `int s5p_get_count(int object, int* count)` | Number of objects: `S5P_NODE`, `S5P_LINK`, `S5P_SUBCATCH` (v2), `S5P_SYSTEM` (v2, always 1). |
| `int s5p_get_name(int object, int index, char* buf, int len)` | ID of an object; `"System"` for `S5P_SYSTEM`. Valid from `s5p_initialize` until `s5p_finalize`. |
| `int s5p_get_value(int object, int index, int property, double* value)` | Current value of one object's property. |
| `int s5p_get_values(int object, int property, double* values, int count)` | *v2.* Current values of a property for every object of a type, in index order. `count` is the capacity of `values` and must be at least the number of objects. |
| `int s5p_get_times(double* start, double* end, double* report_step)` | Simulation window and reporting interval. |

Values can be read from `s5p_initialize` until `s5p_finalize` (`S5P_ERR_STATE` otherwise), also from inside the callbacks.

### Properties

| Object | Property | Value |
|---|---|---|
| node | `S5P_NODE_DEPTH` | water depth above the invert |
| node | `S5P_NODE_HEAD` | piezometric head |
| node | `S5P_NODE_VOLUME` (v2) | stored volume |
| node | `S5P_NODE_LATERAL_INFLOW` (v2) | external inflow, runoff and other lateral inflow |
| node | `S5P_NODE_TOTAL_INFLOW` (v2) | lateral inflow plus inflow from links |
| node | `S5P_NODE_FLOODING` (v2) | overflow rate leaving the network or entering a pond |
| link | `S5P_LINK_FLOW` | flow rate (all barrels) |
| link | `S5P_LINK_DEPTH` | flow depth |
| link | `S5P_LINK_VELOCITY` | velocity |
| link | `S5P_LINK_AREA` | flow area (all barrels) |
| link | `S5P_LINK_VOLUME` (v2) | water volume |
| link | `S5P_LINK_CAPACITY` (v2) | conduits: flow area / full area (at most 1); other links: their setting |
| subcatchment (v2) | `S5P_SUBCATCH_RAINFALL` | rainfall intensity (in/h or mm/h) |
| subcatchment (v2) | `S5P_SUBCATCH_EVAPORATION` | evaporation loss (in/day or mm/day) |
| subcatchment (v2) | `S5P_SUBCATCH_INFILTRATION` | infiltration loss (in/h or mm/h) |
| subcatchment (v2) | `S5P_SUBCATCH_RUNOFF` | runoff flow rate |
| subcatchment (v2) | `S5P_SUBCATCH_AREA` | area (acres or hectares) |
| system (v2) | `S5P_SYSTEM_RAINFALL`, `S5P_SYSTEM_EVAPORATION`, `S5P_SYSTEM_INFILTRATION` | area-weighted averages over the subcatchments |
| system (v2) | `S5P_SYSTEM_RUNOFF` | total runoff |
| system (v2) | `S5P_SYSTEM_LATERAL_INFLOW` | total lateral inflow to nodes |
| system (v2) | `S5P_SYSTEM_FLOODING` | total node flooding |
| system (v2) | `S5P_SYSTEM_OUTFLOW` | total inflow to outfalls |
| system (v2) | `S5P_SYSTEM_STORAGE` | total volume in nodes and links |

How the values are formed:

- **Links** are averages over the link's finite volumes (volume: the sum), as SWMM5+ writes them to its link output files; flow, area and volume include all barrels.
- **Nodes with a volume** (junctions with three or more links, storage nodes) report the junction main element for depth, head, lateral inflow and flooding. Volume is the sum over the junction main and its branches, as in SWMM5+'s output, and total inflow adds the inflows through the branches. SWMM5+'s own node output files average depth and head over the junction main and its branches, whose inverts differ, so they can differ from the junction depth reported here.
- **Nodes that are faces** between finite volumes (junctions with two links, upstream ends, outfalls) report the mean of the two sides of the face for depth and head, no volume and no flooding. Lateral inflow is the external inflow (including the inflow boundary of an upstream end) plus runoff; total inflow adds the flow through the face, except at upstream ends.
- **Subcatchments** are read from the EPA SWMM 5.1 hydrology that SWMM5+ runs, the way EPA SWMM writes its own output: the rain gage value at the reporting time, the current losses, and runoff interpolated between the last two runoff times.

## Callbacks

```c
typedef int (*s5p_progress_fn)(double now_seconds, double end_seconds, void* user_data);
typedef int (*s5p_report_fn)(int period, double seconds, void* user_data);   /* v2 */
```

The progress callback is called once per time step after the step completes, not during spin-up.

The reporting callback is called whenever SWMM5+ stores a level of its multi-level output (also when output files are switched off in the settings), with the time SWMM5+ records for it: at the start, at the first time step that reaches each reporting time, and once more at the end of a completed simulation (the level SWMM5+ adds when it finalizes). `period` counts the calls from 0. The getters return the values of that level, so a host that records them at each call obtains exactly the results SWMM5+ writes, in the units of the input file.

Query functions may be called from inside both callbacks. A non-zero return value stops the run at the end of the current step. Standard output is restored while callbacks run (see `s5p_set_console`).

## Error codes

| Code | Meaning |
|---|---|
| `S5P_ERR_STATE` (1) | Wrong lifecycle order. |
| `S5P_ERR_ARGUMENT` (2) | Unknown object, property or index, or a buffer that is missing or too small. |
| `S5P_ERR_CANCELLED` (3) | A callback asked to stop. |
| `S5P_ERR_FILE` (4) | A required file or folder is missing. |
| `S5P_END` (5) | Returned by `s5p_step` at the end of the simulation; not an error. |

Fatal input errors inside SWMM5+ end the process with Fortran `STOP`; run the solver in a separate process.
