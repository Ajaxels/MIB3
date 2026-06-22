# Plan: direct WSI image reading for BigData (BioFormats / OpenSlide), zarr3-like

Status: **Phases A–D DONE; Phase E (WSIToZarr3) deferred** (2026-06-17). Sub-initiative of the
BigData work — see `plan_bigdata.md`.

## Current status (2026-06-17)

A WSI / microscopy file (CZI, NDPI, SVS, …) now **opens, browses, and segments as a BigData dataset**
with on-demand pyramidal image reads; models/mask/selection stay on the disk-backed zarr3 store.

- ✅ **Phase A** — `io.BioFormats.Config` (`mib`|`matlab`) + `preferences.IO.BioFormats.Library` +
  `io.BioFormats.Reader` facade; Preferences UI dropdown wired (`BioFormatsLibrary`/`BioFormatsLabel`).
- ✅ **Phase B** — true pyramid-level reads in the Java backend (`setFlattenedResolutions(false)` +
  `setResolution` + level-local `bfGetPlane`); `pyramidStruct`; associated-image (macro/label) guard.
- ✅ **Phase C** — read seam generalised (`getDataZarr` dispatches by `pyramid.sourceType`
  `zarr3`|`bioformats`); reader **dropdown** migration (`Default`|`BioFormats`|`OpenSlide`, replacing the
  checkbox; `selectedReader` + 3-slot `selectedFileFilter` + `readerToIndex`; `reader_Callback`); open
  path (registry `BigData.BioFormats`/`*.OpenSlide` extensions, `LoaderFactory` routing, setup-loader
  BigData branch with **single-scene auto / multi-scene dialog** selection + OME voxel size). DeveloperMode
  load log `[type/reader] -> file`.
- ✅ **Phase D** — MATLAB built-in backends in `io.BioFormats.Reader`: `matlab` (`bioformatsread`) and
  `openslide` (`openslideread`) via lazy `blockedImage` `getRegion`; backend chosen by reader family +
  `IO.BioFormats.Library`, persisted in `pyramid.sourceReaderLibrary`, re-opened by `getDataZarr`.
  All three engines pixel-identical at full res (verified on CMU-1.ndpi).
  - **Fix (2026-06-17):** the blockedImage backend is now **dimension-aware**. `bioformatsread`
    returns `[Y X Z C T]` with singleton axes dropped (so dim 3 alone is ambiguous Z-vs-C); the backend
    queries canonical Z/C/T from the Bio-Formats Java metadata (OpenSlide = 2-D RGB), maps the
    requested ranges onto the blockedImage's actual dims for `getRegion`, and reshapes back to
    `[y x z c t]`. Verified on a Z=111, C=4 confocal CZI (matlab backend == Java reference; full
    `getData` slice read no longer errors).
- ⏳ **Phase E** — `io.converters.WSIToZarr3` (convert a WSI to a zarr3 pyramid via
  `Zarr3Saver.saveStream`) — **deferred**; only needed when on-demand reading isn't possible/desired.

**Drive-by fixes** (surfaced during testing): `getAllowedExtensions` cellstr/missing-key crash on the
reader dropdown (R7); pre-existing multichannel-`viewPort` crash in `MibVirtualImage.initialize`
(regenerate when length ≠ colors).

**Pending / for the user:** restart MIB so the running session loads the new registry extensions +
reader-dropdown keys; live File→Open test of a WSI as BigData (single-scene auto-load; Zeiss multi-scene
prompts); confirm model-create + segmentation on a WSI BigData set; optional Phase E.

## Goal & key decision

Let a **BigData** dataset read its **image layer directly** from a WSI / microscopy file
(CZI, SVS, NDPI, LIF, ND2, …) on demand, **without first converting to zarr3**, giving the *same
read experience the zarr3 reader already provides* (pyramid-level selection by magnification, region
reads, orientation switching). The **model / mask / selection / annotation layers stay on the
disk-backed zarr3 store** (`MibBigDataLabels`) exactly as today.

Rationale: the source image is read-only in BigData mode, so there is no need to duplicate gigapixel
pixels into a second zarr3 copy — read them in place. A zarr3 *conversion* (`io.converters.WSIToZarr3`)
remains useful but is **lower priority** (only needed when the source can't be read on demand, or to
relocate/snapshot).

**Architecture insight that makes this cheap:** the image read path is already reader-agnostic at the
seam. `core.MibVirtualImage.getData` dispatches to `getDataZarr` when `obj.pyramid.levelNames` is
non-empty, and `getDataZarr` does all coordinate/level/orientation math then calls a single primitive:

```
block = obj.loaders{1}.readRegion(levelKey, physYlim, physXlim, physZlim, Clim, Tlim, dataClass)
```

So if a **WSI-backed loader implements that same `readRegion` contract** and the setup loader
**populates `obj.pyramid`** (levelNames / levelImageSizes [N×3 Y X Z] / levelScaleFactors [N×3] /
levelVoxelSizes / axisOrder), then **`getDataZarr` works unchanged** for WSI — identical pan/zoom/
orient/level behaviour, and all the BigData segmentation tooling (which reads the image via the same
path) keeps working. The model store is independent.

---

## Work items (in the user's priority order)

### 1. Make the MIB BioFormats reader support true lazy pyramid-level reads

Today `BioFormatsVirtualLoader.readPlane` is **already lazy + region-based** (`bfGetPlane(reader,
iPlane, x, y, w, h)`), but it reads from a **single resolution** — the `level` in `getDataVirt` is a
naive `2^(level-1)` divide of full-res dims, not a true pyramid level. Bio-Formats exposes WSI
resolution levels via `reader.getResolutionCount()` / `reader.setResolution(level)`.

- **`io.loaders.BioFormatsVirtualLoader`**: add resolution-level awareness —
  `setResolution(levelIdx-1)` before `bfGetPlane`, and a `readRegion(levelKey, physY, physX, physZ,
  Clim, Tlim, dataClass)` method matching the zarr3 loader's contract (levelKey = 1-based resolution
  level). Keep the existing `readPlane` for the legacy Virtual path.
- **`io.loaders.BioFormatsVirtualSetupLoader`**: populate `obj.pyramid` from the reader's resolution
  levels (per-level sizes via `getSizeX/Y` at each resolution; scale factors = level0/levelN; voxel
  size from OME). For non-pyramidal files (most CZI/confocal — single resolution) → single level,
  which still works (BigData with one level = full-res region reads).

Representative files: `mib/+io/+loaders/BioFormatsVirtualLoader.m`,
`mib/+io/+loaders/BioFormatsVirtualSetupLoader.m`; reference `Zarr3VirtualLoader.readRegion`.

### 2. `preferences.IO.BioFormats.Library` — `'mib'` vs `'matlab'`

Mirror `preferences.IO.Zarr.Library`. Choose the BioFormats engine:
- **`'mib'`** — MIB's bundled OME Java reader (`bfGetReader`/`bfopen`/`bfGetPlane`); current default,
  broadest validated coverage in MIB.
- **`'matlab'`** — MATLAB R2026a built-in WSI readers: `bioformatsinfo`/`bioformatsread` (and
  `openslideinfo`/`openslideread` for classic WSI), which return lazy, tiled, pyramid-aware
  `blockedImage` objects (`wsi.blocked.BioFormatsAdapter`, 1024² tiles).

Implementation, paralleling `io.zarr.Config`:
- New **`io.BioFormats.Config`** (process-wide library selection; set at start-up from
  `initializePreferences`, committed live from the Preferences dialog).
- New **`io.BioFormats.Reader`** facade with a uniform `info()` + `readRegion(level, bbox, …)` that
  dispatches to either the MIB Java path (item 1) or the MATLAB `bioformatsread`/`openslideread`
  blockedImage path. Benchmark (2026-06-17, CZI 50 series): the two are the **same speed** (~2.5 s
  full read, pixel-identical), so the choice is about coverage/robustness, not speed; the MATLAB path's
  advantage is the native lazy blockedImage (no Java dependency, tile cache).
- **Preferences UI**: add `BioFormats.Library` dropdown to `controllers.Preferences` Input/Output panel
  (next to the Zarr library dropdown); `generatePreferences` + `initializePreferences` defaults
  (`'mib'`); commit live in `ApplyButtonPushedCallback`.
- **Migration**: `initializePreferences` adds `IO.BioFormats.Library` if missing (back-compat).

Representative files: new `mib/+io/+BioFormats/{Config,Reader}.m` (existing package, alongside
`bfopen5`); edit
`mib/+models/@MibModel/initializePreferences.m`, `mib/+utils/+defaults/generatePreferences.m`,
`mib/+controllers/@Preferences/Preferences.m`.

### 3. Unified region-reader API → BigData image backed directly by WSI ("zarr3-like")

Generalise the image read seam so the loader behind `getDataZarr` can be the zarr3 reader **or** a WSI
reader, chosen by source type — with no change to the coordinate/level/orient math or any tool.

- **Reader contract** (duck-typed; optionally a thin `io.loaders.RegionReader` base): a class with
  `readRegion(levelKey, physYlim, physXlim, physZlim, Clim, Tlim, dataClass)` returning a MIB3
  `[y x z c t]` block, plus `info`/level metadata. Implemented by `Zarr3VirtualLoader` (today) and the
  new `io.BioFormats.Reader` (item 2).
- **`getDataZarr` decoupling**: the loader is currently lazy-constructed as
  `io.loaders.Zarr3VirtualLoader` and guarded by `~isa(...,'Zarr3VirtualLoader')`. Generalise to
  construct/keep the reader matching `obj.pyramid` source type (store a `obj.pyramid.sourceType` =
  `'zarr3' | 'bioformats' | 'openslide'`); rename the method to a neutral `getDataPyramid` (keep
  `getDataZarr` as a thin alias for back-compat). Everything else (level pick, orientPhysRanges,
  permute, magFactor resize) is unchanged.
- **Open routing**: broaden the registry so WSI extensions can open as BigData —
  `ExtensionRegistryLoad` `BigData.BioFormats` (currently `{''}`) gets the WSI extension set; route to
  a `BigDataVirtualSetupLoader` (or extend `Zarr3VirtualSetupLoader`'s sibling) that builds a
  `MibBigDataImage` whose `pyramid` is populated by the WSI setup loader (item 1) and whose
  `loaders{1}` is the WSI reader. Model creation/segmentation already works once `enableSelection`
  flips on model create.
- **Result**: opening a `.svs`/`.czi`/… as BigData gives on-demand pyramidal image reads (pan/zoom/
  orient identical to a zarr3 BigData set); creating a model allocates the usual disk-backed zarr3
  model store next to it.

**Open UX — series + (optional) level selection (decided direction, 2026-06-17).** A WSI file can hold
several *logical images* (the pyramid series + associated macro/label/overview) and the pyramid series
has multiple resolution levels. The open dialog should let the user choose **which logical image** to
open and (optionally) cap the **base level**:
- Reuse **`utils.dlgs.SelectLociSeriesDlg`** but drive the reader in **un-flattened** mode
  (`setFlattenedResolutions(false)`) so each table row is one logical image (not one row per
  resolution + a macro row, as the current flattened dialog shows). Add a **"Levels"** column
  (= `getResolutionCount` for that series) and show the full-res X/Y. Default-select the largest
  pyramid series (most levels / biggest level-0); the macro/label rows are visible but not the default.
- For BigData the chosen series opens its **full pyramid** (all levels) → zoom-aware reads. *Optionally*
  offer a **base-level** choice (open from level N down) to cap the working resolution / model-store
  footprint — useful when full res is overkill. (A single coarse level alone is better opened as
  Standard/Virtual, not BigData.)
- The dialog returns the chosen **series index** (Phase C setup loader passes it to
  `io.BioFormats.Reader(filename, seriesIndex)`), so the per-series pyramid is what gets wrapped.

**Findings from `Zeiss-5-JXR.czi` (68 MB, multi-scene WSI) — Phase C must handle:**
- **Multiple pyramid series (scenes).** Java unflattened: 4 series — `ScanRegion0` (5 levels, 11323²),
  `ScanRegion1` (5 levels), `label image` (640×515, 1 level), `macro image` (1260×615, 1 level,
  **uint16!**). So a CZI WSI commonly has *several* full-pyramid scenes + label/macro → **series
  selection is required** (can't just auto-take series 0). The uint16 macro confirms why the
  within-series guard checks **bytes-per-pixel**.
- **Backend series-index divergence.** Java (unflattened) numbers ALL logical images (0,1=pyramids;
  2=label; 3=macro). MATLAB `bioformatsinfo` returns `SeriesImages={'scanregion0','scanregion1'}` +
  `AssociatedImages={'label image','macro image'}`, and `bioformatsread` returns **2 blockedImages**
  (pyramids only; NumLevels=5 each). So the open dialog must present a unified "pyramid scenes" list and
  map the choice to the correct per-backend index: **Java** = filter to pyramid series (resolutions>1,
  or name not matching label/macro/overview/thumbnail); **MATLAB** = index into `SeriesImages` /
  the `bioformatsread` array (associated already excluded).
- **Identifying a pyramid series** (Java path): `getResolutionCount > 1`, or — when only one resolution
  — name not in {label, macro, overview, thumbnail}. The largest such series is the default.

Representative files: `mib/+core/@MibVirtualImage/getDataZarr.m` (+ `getData.m` dispatch),
`mib/+core/@MibVirtualImage/MibVirtualImage.m` (pyramid.sourceType), `mib/+io/ExtensionRegistryLoad.m`,
`mib/+io/LoaderFactory.m`, the BigData setup loader.

### (Deferred) `io.converters.WSIToZarr3`

Lower priority. Stream a WSI (via item 2's reader / blockedImage) into a zarr3 pyramid using the
existing `io.savers.Zarr3Saver.saveStream` + `SliceProvider`. Needed only when on-demand reading isn't
possible/desirable (e.g. write-back, relocation, or a source format with no efficient region reader).

---

## Phasing

- **Phase A** — ✅ **DONE 2026-06-17**. `io.BioFormats.Config` (`'mib'`|`'matlab'`, default `'mib'`) +
  `preferences.IO.BioFormats.Library` (generate + initialize migration + live commit) +
  `io.BioFormats.Reader` facade (MIB Java backend: `info()` + `readRegion(level,Y,X,Z,C,T,class)` →
  `[y x z c t]`; `'matlab'` backend errors as not-yet-implemented). **Preferences UI wired** — the
  `BioFormatsLibrary` dropdown (items `MIB`/`MATLAB`) + `BioFormatsLabel` were added to the Input/Output
  `.mlapp` and route through the panel's generic `InputOutputPanelCallbacks`; the controller maps the
  display items ↔ canonical lowercase prefs (`mib`/`matlab`) via `io.BioFormats.Config.normalizeName` +
  a `bioFormatsLibraryItem` helper, shows a live description, and commits in `ApplyButtonPushedCallback`
  → `io.BioFormats.Config.setLibrary`. **No behaviour change** otherwise — nothing in the app calls the
  Reader yet. **Note:** the new classes live in the *existing* `+io/+BioFormats/` package (PascalCase,
  alongside `bfopen5`) — Windows is case-insensitive so `+bioformats` merged into it; canonical name is
  **`io.BioFormats`**. Verified via MCP: Config get/set/normalize; default pref `'mib'`; UI render/read
  mapping (pref↔`MIB`/`MATLAB`, incl. aliases); `Reader.info` on the CZI (1437×1437×3, numLevels=1);
  `readRegion` region pixel-**identical** to the `bioformatsread` ground truth. All files clean under
  `check_matlab_code` (pre-existing warnings only).
- **Phase A** (original spec) — item 2 plumbing without behaviour change: `io.BioFormats.Config` +
  preference key + `io.BioFormats.Reader` facade wrapping today's MIB Java path; default `'mib'`.
- **Phase B** — ✅ **DONE 2026-06-17**. True pyramid-level reads in `io.BioFormats.Reader` (MIB Java
  backend): `openMib` now opens with **`setFlattenedResolutions(false)`** (so a WSI pyramid is exposed
  as multiple *resolutions* of one series, not split into series) using a dedicated Memoizer sub-dir
  (`bfFacade`) to isolate from MIB's flattened readers; `readRegionMib(level,…)` does
  `setResolution(level-1)` and reads **level-local** ranges via `bfGetPlane` (then restores res 0);
  `info()` returns `numLevels` + per-level `[Y X Z]` (`levelYXZ`); new **`pyramidStruct(voxelSize)`**
  builds the MIB `pyramid` struct (`sourceType='bioformats'`, `levelNames`, `levelImageSizes` [Y X Z],
  `levelScaleFactors` level0./levelN, `levelVoxelSizes`, `axisOrder=''`) ready for Phase C to assign to
  `MibBigDataImage.pyramid`. **Decided** to implement in the new facade (the Phase-C read backend), not
  the legacy `BioFormatsVirtualLoader`/`getDataVirt` (left untouched). Validated via MCP: regression —
  level-1 CZI read still pixel-identical to ground truth under unflattened mode; multi-Z/multi-channel
  region read (confocal CZI 748²×111×4); and a genuine **3-level pyramid** via a Bio-Formats `.fake`
  test image (`resolutions=3`) — per-level sizes `[768 1024 3;384 512 3;192 256 3]`, scale factors
  `[1 1 1;2 2 1;4 4 1]`, correct level-local + sub-region + multi-channel reads. Clean under
  `check_matlab_code`.
  - **Validated on a real WSI (CMU-1.ndpi, 198 MB):** un-flattened mode exposes **series 0 = the clean
    4-level pyramid** (38144×51200 → 800×596, uint8 RGB, scale 1/4/16/64) and the **"macro image" as a
    separate series 1** (1191×408, aspect 2.92) — so defaulting to series 0 already excludes the macro.
    A 512×512 tile from the 51200×38144 full-res level reads in ~0.02 s (genuine on-demand, no full
    load); the coarsest level reads in ~0.01 s. (NDPI downsamples ×4 per level, not ×2 — handled
    generically.)
  - **Associated-image guard added** to `info()`: keeps only the leading run of *true* pyramid levels —
    a further resolution is accepted only if it matches level 0 in channel count, **bytes-per-pixel**
    (so a uint16 macro/label is rejected) and aspect ratio (±2 %) and is strictly smaller; it stops at
    the first inconsistent one. This is a safety net for readers that append a macro/label *within* a
    series (in un-flattened mode they're usually a separate series, as in NDPI). Verified it keeps all 4
    NDPI levels and all 3 `.fake` levels, and would trim an odd trailing resolution. (Note for Phase C:
    the setup loader must still pick the **pyramid series** — largest / most-resolutions — not the macro
    series.)
- **Phase C** — item 3: generalise the read seam + route WSI opens to BigData.
  - ✅ **Read seam DONE 2026-06-17.** `core.MibVirtualImage.getDataZarr` now dispatches by
    `pyramid.sourceType` (`'zarr3'` default, or `'bioformats'`): for `'bioformats'` it lazily
    constructs/caches an `io.BioFormats.Reader(filePaths{1}, pyramid.sourceSeries)` and calls
    `readRegion(levelIdx, physY, physX, physZ, Clim, Tidx, class)`; the zarr3 path is unchanged. Both
    return MIB3 `[y x z c t]`, so the existing level-pick / orientPhysRanges / permute / magFactor-resize
    math is shared. Verified via MCP: a hand-built bioformats-backed `MibVirtualImage` for CMU-1.ndpi
    reads through the standard `getData` — explicit level (level-4 full == direct reader), **magFactor
    level selection** (16 → level 3, 2384×3200), and an on-demand **full-res 512×512 tile** (== direct
    reader); zarr3 regression unaffected (trypanosoma 887×813×171 / 444×407×171). Clean under
    `check_matlab_code`. Renaming to `getDataPyramid` deferred (kept `getDataZarr` as the entry to avoid
    churn; the dispatch lives inside it).
  - ✅ **Open path DONE 2026-06-17.** A `.czi`/`.ndpi`/… now opens as **BigData** via BioFormats:
    - **Registry**: `BigData.BioFormats` populated with the full BioFormats extension list (any
      BioFormats file opens on-demand; pyramidal when available). `defaultLoaderId` already routed
      `BigData+BioFormats → BioFormatsVirtual`.
    - **`LoaderFactory`**: the `BioFormatsVirtual` case now injects `datasetMode` into the loader (mirrors
      `OmeZarr`), so the setup loader knows Virtual vs BigData.
    - **`BioFormatsVirtualSetupLoader`**: new BigData branch — `enumeratePyramidScenes` (un-flattened
      series, excludes label/macro/overview/thumbnail by name) → **single scene auto-loads, multiple
      → selection dialog** (or `options.BioFormatsIndices` when scripted/silent); reads OME voxel size;
      builds `io.BioFormats.Reader.pyramidStruct` and sets `imginfo{'Pyramid'}` (sourceType='bioformats',
      sourceSeries) + dims/class/pixSize; returns `img={file}`. `MibVirtualImage.initialize` merges the
      pyramid; `MibDataset` builds a `MibBigDataImage`.
    - **Verified via MCP**: resolveLoader(`.ndpi`,BigData,BioFormats)→`BioFormatsVirtual`; full
      `LoaderFactory.create`→loadMetadata/loadImages path (datasetMode via ctor opts) builds the pyramid
      and `MibBigDataImage.getData` reads (explicit level, magFactor selection, on-demand full-res tile)
      on **CMU-1.ndpi** (4 levels) and **Zeiss-5-JXR.czi** (multi-scene — `BioFormatsIndices='2'` selects
      ScanRegion1). All files clean under `check_matlab_code`.
    - **Remaining**: live File→Open GUI test (needs BigData mode + the reader dropdown set to BioFormats;
      **restart MIB** so the new registry extensions + reader keys load); confirming model
      create/segmentation on a WSI BigData set (model store as a sibling `.zarr3`); **OpenSlide** reader
      is Phase D.
- **Phase D** — ✅ **DONE 2026-06-17**. Added the MATLAB built-in backends to `io.BioFormats.Reader`:
  `'matlab'` (`bioformatsread`) and `'openslide'` (`openslideread`), both returning lazy, tiled,
  pyramid-aware `blockedImage` objects read via `getRegion(b, start, end, Level=L)`. Shared
  `openBlocked`/`infoBlocked`/`readRegionBlocked` (WSI `[Y X (C)]`, Z/T=1); availability guard errors
  clearly if the WSI support package is missing. Backend selection: a new `normalizeBackend` keeps
  `'openslide'` distinct from `'matlab'`; the **OpenSlide reader family → `'openslide'` engine**, the
  **BioFormats family → `io.BioFormats.Config.library()`** (`'mib'`|`'matlab'` preference). The chosen
  engine is recorded in `pyramid.sourceReaderLibrary` (added by `pyramidStruct`), threaded from
  `LoaderFactory` (`readerFamily`) → setup-loader → and re-opened by `getDataZarr`. Verified via MCP on
  CMU-1.ndpi: all three engines yield **pixel-identical** full-res tiles (Java/matlab 4 levels,
  openslide 9 levels — each backend's own pyramid); full open path (LoaderFactory→setup→MibBigDataImage→
  getData) works for OpenSlide and BioFormats+matlab. All files clean under `check_matlab_code`.
  - **Levels come from the blockedImage, not a guard.** Probed on CMU-1.ndpi: `bioformatsread(f)`
    returns a single multi-level `blockedImage` with `NumLevels=4` and `Size` =
    `[38144 51200 3; 9536 12800 3; 2384 3200 3; 596 800 3]` (the pyramid), and `bioformatsinfo` reports
    `SeriesImages` vs `AssociatedImages={'macro image'}` — the macro/label is auto-separated (fetch via
    `bioformatsread(f, ImageType="macro"|"label")`). So the MATLAB backend builds `pyramidStruct`
    directly from `NumLevels`/`Size` and needs **no aspect-ratio guard** (unlike the Java path).
    `readRegion(level,…)` → `getRegion`/`gather` on `b` at that level (blockedImage is tiled/lazy).
    Series selection maps to which `blockedImage` of the returned array to wrap.
- **Phase E (deferred)** — `io.converters.WSIToZarr3`.

## Verification

- Benchmark already done (CZI 50-series): MIB-Java vs `bioformatsread` ≈ tie (~2.5 s), pixel-identical.
- Per phase via MCP: WSI `readRegion` at multiple levels == reference; `getDataPyramid` round-trips
  YX/ZX/ZY; open a real `.svs` as BigData, pan/zoom/level-switch, create a model + segment, reopen.
- `check_matlab_code` on every changed/new file; add `tests/` cases (open-WSI-BigData, level read,
  model-on-WSI).
- Get a true pyramidal WSI sample (SVS/NDPI) — the test CZI is single-level, so it doesn't exercise the
  pyramid/level path.

## Reader-selection UI (decided 2026-06-17)

Replacing the binary **BioFormats checkbox** with a **reader dropdown**
(`dirContents.handles.reader`, items `Default | BioFormats | OpenSlide`). Decisions:
- **R2 = Option A**: dropdown lists reader *families*; the BioFormats **engine** (MIB-Java vs MATLAB)
  stays the global `preferences.IO.BioFormats.Library`, resolved inside the loader.
- **OpenSlide**: `*.OpenSlide` extension sets populated (all modes) with the canonical OpenSlide vendor
  formats (`svs avs dcm vms vmu ndpi tif tiff scn mrxs svslide bif czi`); selecting OpenSlide opens
  through the BioFormats loader family for now (native `openslideread` engine = Phase D).
- Widget already added by the user (`reader` dropdown replaces the removed `bioFormats` checkbox).

**Migration — DONE 2026-06-17.** Implemented the checkbox→dropdown swap end-to-end:
`MibModel.selectedReader` (default `'Default'`) + 3-slot `selectedFileFilter` + static `readerToIndex`
(`Default→1, BioFormats→2, OpenSlide→3`); `useBioFormats` kept as a derived alias. `reader_Callback`
(replaces `bioFormats_Callback`, old file deleted) reads the dropdown, sets state, populates filters,
and defensively grows `selectedFileFilter` for older sessions. Wiring updated in `MibDirContents`
(`reader.ValueChangedFcn`), consumers updated (`fileFilters_Callback`, `fileFilters_ContextMenu`,
`updateGuiWidgets` — also reflects the dropdown value), `loadImages` gains `BatchOpt.Reader` (back-compat
with `UseBioFormats`). **R7 fix** in `getAllowedExtensions`: missing-key guard (`isKey`) + clean cellstr
row with empty placeholders dropped (kills the `.Items` char-collapse crash). Registry gains
`*.OpenSlide` keys (populated with the OpenSlide vendor formats; routed via BioFormats for now). Verified via MCP: all reader×datasetType combos yield valid dropdown
`.Items` (no crash, incl. the former BigData+BioFormats crash); existing sets intact (Standard.Default 48,
Virtual.BioFormats 70); stale live registry degrades gracefully. Default/BioFormats behaviour unchanged;
**OpenSlide opening + BigData WSI routing remain Phase C**. (Original migration note below.)

Original migration note: `MibModel.selectedReader` (string, default `'Default'`) + `selectedFileFilter`
becomes 3-slot (one per reader) with a `readerToIndex` helper; `useBioFormats` kept as a derived
back-compat alias (`~strcmp(selectedReader,'Default')`); `bioFormats_Callback` → `reader_Callback`
(reads the dropdown); wiring in `MibDirContents`; consumers updated (`fileFilters_Callback`,
`fileFilters_ContextMenu`, `updateGuiWidgets`, `loadImages`). **R7 fix**: `getAllowedExtensions` returns
a cellstr robustly (the single-element `{''}` set collapsed to a char and crashed `.Items`). Registry
gains `*.OpenSlide` keys. Default/BioFormats behaviour is preserved exactly; **OpenSlide opening + the
BigData WSI loader routing remain Phase C** (selecting OpenSlide filters files but can't open yet).

## Open questions

1. Reader contract: formal `io.loaders.RegionReader` base class, or keep duck-typed `readRegion`?
2. `pyramid.sourceType` on the image, or infer from the loader class? (sourceType is cleaner.)
3. MATLAB-backend coverage: `bioformatsread` for everything vs `openslideread` for classic WSI — auto-
   pick by extension, or expose both? (propose: auto by extension, OpenSlide for svs/ndpi/mrxs/tiff-WSI.)
4. Memory/perf of switching readers per buffer; Java reader lifetime vs blockedImage handle caching.
5. Does any BigData-specific code assume the image is zarr3 (e.g. closeVirtualDataset, save paths)?
   Audit for `'zarr3'`/`Zarr3*` hard-coding when generalising.
