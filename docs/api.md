# SWMM5+ C interface reference

All functions return `S5P_OK` (0) on success or an error code. `s5p_last_error` describes the last error. Indices are zero-based and follow the order of the objects in the input file. Times are seconds from the simulation start. Values use the units of the input file.

## Lifecycle

| Function | Purpose |
|---|---|
| `int s5p_api_version(void)` | Interface version; currently `1` (`S5P_API_VERSION`). |
| `int s5p_version(char* buf, int len)` | SWMM5+ version string, for example `1.0.3`. |
| `int s5p_open(const char* inp, const char* output_dir, const char* settings, const char* swmm_library_dir)` | Prepares a run. Paths may be relative; they are made absolute. `output_dir`, `settings` and `swmm_library_dir` may be `NULL`. |
| `int s5p_set_progress_callback(s5p_progress_fn fn, void* user)` | Registers the per-step callback. Pass `NULL` to remove it. |
| `int s5p_set_quiet(int quiet)` | Non-zero turns off the per-step console output of SWMM5+. Call before `s5p_initialize`. |
| `int s5p_initialize(void)` | Reads the input through EPA SWMM, partitions the network and sets initial conditions. |
| `int s5p_run(void)` | Runs the time loop. Returns `S5P_ERR_CANCELLED` when the callback asked to stop. |
| `int s5p_finalize(void)` | Writes SWMM5+ output files. |
| `int s5p_close(void)` | Releases the interface. A process can run one model only. |

## Queries

| Function | Purpose |
|---|---|
| `int s5p_get_count(int object, int* count)` | Number of nodes (`S5P_NODE`) or links (`S5P_LINK`) in the input file. |
| `int s5p_get_name(int object, int index, char* buf, int len)` | ID of a node or link. |
| `int s5p_get_value(int object, int index, int property, double* value)` | Current value: `S5P_NODE_DEPTH`, `S5P_NODE_HEAD`, `S5P_LINK_FLOW`, `S5P_LINK_DEPTH`, `S5P_LINK_VELOCITY`, `S5P_LINK_AREA`. |
| `int s5p_get_times(double* start, double* end, double* report_step)` | Simulation window and reporting interval. |

Link values are averages over the finite volumes of the link. Node values come from the junction element, or from the face between two volumes for junctions that connect exactly two links.

## Progress callback

```c
typedef int (*s5p_progress_fn)(double now_seconds, double end_seconds, void* user_data);
```

Called once per time step after the step completes, and not during spin-up. Query functions may be called from inside the callback. Return non-zero to stop at the end of the current step.

## Error codes

| Code | Meaning |
|---|---|
| `S5P_ERR_STATE` (1) | Wrong lifecycle order. |
| `S5P_ERR_ARGUMENT` (2) | Unknown object, property or index. |
| `S5P_ERR_CANCELLED` (3) | The callback asked to stop. |
| `S5P_ERR_FILE` (4) | A required file or folder is missing. |

Fatal input errors inside SWMM5+ end the process with Fortran `STOP`; run the solver in a separate process.
