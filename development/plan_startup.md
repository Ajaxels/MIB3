# MIB3 Startup Speed-Up — Plan & Status

**Status: implemented (all phases), 2026-06-12.**
Warm steady-state startup: **13.35 s → 6.34 s (−52%)**, measured in the live
R2026a dev session. Cold-start test in a fresh MATLAB session: pending.

## Context

Startup was audited (code trace + live-MATLAB measurements). The suspicion was
eager Java library linking; that was confirmed, but the biggest costs were
elsewhere. Measured hotspots and fixes:

| # | Hotspot | Where | Cost | Fix | Status |
|---|---------|-------|------|-----|--------|
| 1 | Hardcoded `pause(2)` before layout restore | `mib\+views\@MibView\doPostInitializationTasks.m` | 2000 ms | Poll `gui.State == RUNNING` (5 s timeout fallback) | ✅ done |
| 2 | `ver('matlab')` | `mib\+models\@MibModel\initialize.m` | 908 ms (warm!) | `str2double(regexp(version, '^\d+\.\d+', 'match', 'once'))` — identical numeric semantics | ✅ done, value verified = 26.1 |
| 3 | Blocking update check (`urlread`, 4 s timeout) | `mib\+controllers\@MibController\initialize.m` | 0–4000 ms | One-shot timer `MIB-DeferredStartup` (StartDelay 8 s) → `deferredStartupTasks` → `checkForUpdate` (`webread`); timer stored in `MibController.updateCheckTimer`, cleaned up in `exitProgram` | ✅ done, fired once, no errors |
| 4 | 10× dummy `MibDataset` ctor | `mib\+models\@MibModel\datasetsSetsOps.m` | ~800 ms | Hoisted `imread(default.png)`+`meta` out of the loop; lazy `Lines3D.nodeStrel` (built on first `addLinesToImage`, invalidated by `setOptions`/`clearContents`) | ✅ done |
| 5 | Eager Java libs (`javaaddpath` ×5-8, Fiji dir scans) | `mib\+controllers\@MibController\initializeLibraries.m` | 100-300+ ms (more cold/with Fiji) | New `utils.ensureJavaLibraries` lazy gateway; **no JARs load at startup** | ✅ done |
| 6 | `parcluster('local')` in `utils.getMaxParpoolWorkers` | `mib3.m` | 150–250 ms | `MibModel.cpuParallelLimitMax` is now a lazy `Dependent` property; warmed by the deferred timer | ✅ done |

Already optimal (no change): ribbon tabs incl. Plugins are lazy
(`addRibbonTabs.m` `lazyInit=true`), icon cache `mib_icons.res` built once,
`io.ExtensionRegistryLoad` only 38 ms.

## Implementation details

### Phase 0 — instrumentation
`[startup] <phase>` `fprintf` markers (guarded by a `MIB_STARTUP_VERBOSE` env
var) were added to `mib3.m` and `MibController\initialize.m` for the A/B
measurements and **removed again after verification** — only the original
`tic`/`toc` total remains. Re-add temporarily if a new startup audit is needed.

### Phase 3 — deferred startup timer
- New `mib\+controllers\@MibController\deferredStartupTasks.m`: guards on valid
  view, warms `cpuParallelLimitMax` (try/catch), then `checkForUpdate()`.
- New `mib\+controllers\@MibController\checkForUpdate.m`: moved update-check
  logic, `urlread` → `webread(link, weboptions('Timeout',4,'ContentType','text'))`,
  early-return when MIB already closed or recheck period not elapsed.
- `exitProgram.m` stops/deletes `obj.updateCheckTimer`.

### Phase 5 — lazy cpuParallelLimitMax
- `MibModel`: `cpuParallelLimitMax` → `Dependent`; private backing
  `cpuParallelLimitMaxCached = []`; getter computes `utils.getMaxParpoolWorkers()`
  on first access **and clamps `preferences.System.cpuParallelLimit`** (prefs
  file may come from a machine with more workers — `parpool(N)` errors if N >
  cluster limit, so the clamp must survive).
- Constructor arg kept as optional override (default `[]`,
  `mustBeScalarOrEmpty`) — tests calling `models.MibModel(1, mibFolder)` still
  work; when an explicit value is passed, the clamp runs in
  `initializePreferences` (guarded on non-empty cache).
- `mib3.m` no longer calls `getMaxParpoolWorkers()` eagerly.
- `Preferences.m`: spinner `Value` clamped with `min(...)` because its local
  `systemPrefs` copy may predate the lazy clamp.

### Phase 6 — lazy Java gateway
- New `mib\+utils\ensureJavaLibraries.m(libList, mibPath, externalDirs)`:
  - persistent registry of initialized libs + cached `mibPath`/`externalDirs`
    (configured at startup by `initializeLibraries({'bm3d'})`; falls back to
    `utils.getInstallationPath('mib3')`).
  - per-lib blocks moved verbatim (incl. `isdeployed` branches and
    `javaclasspath('-all')` double-check); `bfInitLogging()` lives in the
    `'bioformats'` branch.
  - fiji/omero/imaris are only marked initialized when their dir is valid, so
    fixing a path in Preferences allows a retry; Preferences apply refreshes
    the cached `externalDirs`.
- `initializeLibraries.m` is now a thin delegator (empty `initList` still means
  "everything" for back-compat); startup calls `obj.initializeLibraries({'bm3d'})`
  (bm3d/bm4d addpath + HistThresh addpath only — nothing JVM-heavy).
- First-use ensure calls:
  - `bioformats`: `BioFormatsStdLoader` ctor (covers `BioFormatsVirtualSetupLoader`
    via inner loader), `BioFormatsVirtualLoader.openReader`, `bfopen3.m`,
    `bfopen5.m`, `mibImage2ometiff.m`, `SelectLociSeriesDlg.loadBioFormatsLibrary`
    (body replaced), `BatchProcessing\doSeriesLoop.m`.
  - `mij.jar`+`fiji`: `utils.fiji.Miji_wrapper` (single gateway — all Fiji code
    paths route through it; verified by grep).
  - `imageselection`: `Snapshot.m` clipboard copy, `MibRibbon\homeImport_Callback.m`
    clipboard paste.
  - `imaris`: `io.imaris.connectToImaris` (covers `getImarisDataset` and
    `setImarisDataset`).
  - `poi`/`omero`: supported by the gateway; no live MIB call sites yet
    (OMERO import = "Not implemented yet", xlwrite has no callers).

## Measurements (live R2026a session)

Baseline (before changes): 13.35 s. Steady-state after all phases: **6.34 s**:

```
[startup] paths + installation path:  0.507 s
[startup] MibModel created:           0.600 s
[startup]   libraries initialized:    0.029 s
[startup]   MibView created:          0.061 s
[startup]   GUI controllers added:    3.884 s   <-- now the dominant phase
[startup]   GUI visible:              4.687 s
[startup]   post-initialization done: 5.680 s   (~1 s of RUNNING-state poll)
[startup]   image shown:              5.730 s
[startup] MibController created:      6.335 s
```

Micro-measurements that drove decisions: `ver('matlab')` 908 ms warm vs
`version` parse ~1 ms; `parcluster('local')` 150–250 ms; `imread(default.png)`
17 ms ×10; `MibDataset` ctor ~80 ms (Lines3D strel ~30 ms of it);
`ExtensionRegistryLoad` 38 ms (left as-is).

**Caveat:** first restart after classdef edits is 2–5× slower (class reload);
always take the second restart as the steady-state number.

## Verification status

- ✅ Layout restores correctly (state poll instead of pause).
- ✅ Deferred timer fires once; prefs clamp applied (`cpuParallelLimit` = 2).
- ✅ `utils.ensureJavaLibraries({'bioformats'})`: links jar, `loci.formats.*`
  classes resolve; repeat call 0.6 ms.
- ✅ Unit tests: 161 passed / 0 failed / 4 assumption-filtered.
  (Fresh-session quirk: needs `addpath('tests')` before `buildtool test`.)
- ✅ `mib.mibModel.matlabVersion` identical to old value (26.1).
- ⚠️ `buildtool check`: fails on 4 **pre-existing** errors in untouched files
  (`mapRgbaVectorToScalar.m`, `using_hg2.m`, `readMetaDataFromFibicsTIFs.m`,
  `McCalcGUI.mlapp`).
- ⏳ **Cold-start test pending** — fresh MATLAB session, run `mib = mib3;` and
  read the total `toc`. Expect bigger relative win (no warm JIT, JARs never linked).
- ⏳ **Deployed build check pending** — verify lazy `javaaddpath` works in the
  compiled app (open a Bio-Formats file, Fiji connect). Fallback if it
  misbehaves: eager-when-`isdeployed` for `bioformats`/`mij.jar` only.
- ⏳ Functional smoke with a real Bio-Formats file (`.czi`/`.lif`) and Fiji
  connect not yet performed (no test file at hand during implementation).

## Docs / housekeeping

- RST docblocks written for all new methods; `ensureJavaLibraries` added to
  `docs_api/source/api/utils/functions.rst` (`MibController.rst` uses
  `:members:`, picks up new methods automatically).
- graphify refresh skipped (python `graphify` package not installed on this
  workstation; user said skip).

## Possible future work

- `addGuiControllers` (~3.6 s, panel `.mlapp` instantiation) is now the
  dominant startup phase — candidate: lazy/deferred panel creation.
- Lazy creation of dataset slots 2–10 was evaluated and **deliberately
  dropped** (touches split-panel/`MibActiveDataset` logic; high risk vs
  ~0.5 s reward).
