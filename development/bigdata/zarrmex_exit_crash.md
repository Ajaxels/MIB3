# zarrMex exit crash - investigation and fix

Investigated 2026-10-23/24. Fixed in MIB by pinning the library (`io.zarr.pinNativeLibrary`,
`utils.pinModule`); reported upstream to scalable minds (zarr-matlab) with a suggested `mexLock` fix.

## Symptom

MATLAB dies with `0xc0000005`; Windows Error Reporting names the module `zarrMex.mexw64_unloaded`,
fault offset `0x4f15e3`. Seen at the end of `buildtool test` (all tests passed, the crash comes at
MATLAB exit) and once in a live MIB session running the suite. `_unloaded` means the code that
faulted belonged to a DLL that was no longer mapped.

## Cause

`zarrMex` is a Rust `cdylib` (zarrs 0.23, rayon for chunk parallelism, tokio through
`zarrs_http`). Their worker threads stay alive, parked inside the library, after a MEX call
returns. The gateway never calls `mexLock`, so MATLAB unmaps the library at exit and on
`clear mex` / `clear functions` / `clear zarrMex`. A parked worker that runs again afterwards
executes unmapped code.

The workers stay asleep on their own; what wakes them here is another multi-threaded library:
Computer Vision Toolbox feature matching (SURF, `matchFeatures`, `estgeotform2d`).

## Measurements

Every run is a fresh `matlab -batch` (R2026a, Windows 11); crashed = exit code `-1073741819`.

| Scenario | Crashed |
|---|---|
| zarr write/read only | 0 of 6 |
| CV feature matching only | 0 of 3 |
| zarr, then CV feature matching | 3 of 3 |
| zarr, `clear zarrMex`, CV, 15 s of work | 3 of 3 - alive for 15 s, crash at exit |
| zarr only (StitchCoreTest round trip), pause 2-25 s before exit | 0 of 19 - not a timer |
| same as row 3, `zarrMex` pinned first | 0 of 5 |
| standalone repro without MIB code (zarr-matlab + CV only) | 3 of 3 |

In the suite only `StitchCoreTest` triggers it: its Integration zarr round trip plus the
`featureShift_*` Unit tests (found by bisecting 32 zarr-related classes, then the 60 methods).

Control experiment with a 30-line C MEX that starts one thread looping in its own DLL:

| Mode | At exit | `clear` during the session |
|---|---|---|
| no lock | crash 2 of 2 | immediate crash |
| `mexLock()` | clean 2 of 2 | clean, stays loaded |
| pinned (`GET_MODULE_HANDLE_EX_FLAG_PIN`) | clean 2 of 2 | clean |

So MATLAB never unmaps a locked MEX, at exit included: `mexLock` in the gateway is the upstream fix.

## Fix in MIB

`utils.pinModule(path)` (C, `mib/+utils/pinModule.c`) loads a library and pins it -
`GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_PIN)` on Windows, `dlopen(RTLD_NODELETE)` elsewhere.
`io.zarr.pinNativeLibrary` pins `zarrMex` once; called from `mib3.m` and
`mibtest.fixtures.MibPathFixture`. Cost about 13 ms at startup. Side effect: the binary stays
locked until MATLAB restarts. Only the Windows build of `pinModule` exists yet; the Linux/macOS
branch is untested, and whether the crash happens there is unknown.

Rejected: a MIB-side `mexLock` (only the MEX itself can lock), disabling rayon (it still spawns
workers), and editing the vendored `ZarrArray.m` (lost on the next upstream update).

## Files in [`private/zarrmex_exit_crash/`](../private/zarrmex_exit_crash/) (git-ignored)

| File | What it is |
|---|---|
| `message_to_norman_v2.md` | the report to Norman Rzepka (scalable minds), written for a Rust developer; attachments: the patch, `threadMex.c`, `zarr_exit_crash_repro.m` |
| `zarr_mex_mexlock.patch` | the suggested upstream fix against zarr-matlab branch `zarr` (the only and default branch) at `4a013c9`, 2026-08-11 (`mexLock` once in the gateway); applies cleanly, not compiled |
| `message_to_norman.md` | first draft of the report, with the MATLAB repro inline |
| `zarr_exit_crash_repro.m` | standalone repro, zarr-matlab + Computer Vision Toolbox only (the one in the report) |
| `probe_cv.m` | the same through MIB's `utils.stitch.featureShift`; modes `cv_only`, `zarr_cv`, `clear_cv`, `pin_zarr_cv` |
| `threadMex.c` | the control experiment: a thread looping in its own DLL, modes `none`, `lock`, `pin` |
| `bisect_methods2.ps1`, `run_with_methods.m`, `run_selection.m` | method bisection of `StitchCoreTest` in fresh `matlab -batch` processes; paths point at the session scratch folder, edit `$d` before reuse |

Run every probe as `matlab -batch` and read the process exit code: `-1073741819` is the crash. Never
run them in a MATLAB session that holds work.
