# Plan: BigData image type for MIB3 (hybrid blockedImage + Zarr3)

## ⚠ Deferred TODO

- **Processing-tool guard audit for BigData** — ✅ DONE 2026-06-14. Extended every controller that
  guarded only against `'Virtual'` to also cover `'BigData'` via the uniform test
  `any(datasetType(1) == ['V' 'B'])` (and `~any(...)` for the inverse), and generalised the user
  message wording from "virtual stacking mode" to "virtual or BigData mode". Files edited:
  `@ContentAwareFill/applyFilter`, `@ContrastClahe/applyFilter`, `@MorphOps/MorphOps`,
  `@MorphOpsImages/MorphOpsImages`, `@GlobalThresholding/GlobalThresholding`,
  `@ObjectSeparator/ObjectSeparator`, `@Graphcut/Graphcut`, `@ImageFrame/ImageFrame`,
  `@DebrisRemoval/DebrisRemoval`, `@WhiteBalance/WhiteBalance`, `@VolRenApp/VolRenApp`,
  `@Alignment/Alignment`, `@DisplayAdjust/DisplayAdjust` (×4: 2 guards + 2 `~strcmp` stretch
  branches), `@MibController/datasetSlices`, `@MibRibbon/selectionBuffer`,
  `@MibFijiConnect/{importFromFiji,exportToFiji}`, `@MibImageDocument/{segmentBlackWhiteThreshold,
  segmentationSAM,segmentationSAM2}`. `@ResampleDataset/ResampleDataset` (line 591) extended to also
  convert BigData→Standard after the in-memory resample (same path as Virtual). Already-correct
  (handle `'B'` explicitly, left as-is): `@MibController/updateGuiWidgets`,
  `@MibImageDocument/{updateBrushCursor,sliderDragCallback,gui_WinMouseMotionFcn}`,
  `@MibController/gui_WindowKeyPressFcn`. Intentionally skipped: `plugins/Tutorials/PluginWithoutGUI`
  (example code), `@MibDataset/insertSlice` (`(1)=='V'` is a virtual-insert behavioural branch, not a
  processing guard). All edited files pass `check_matlab_code` (no new issues).
- **T>1 (time-series) BigData model** — `MibBigDataLabels` assumes a single time point.
- **Dual zarr backend (`io.zarr` facade)** — ✅ DONE 2026-06-14. Added a backend-selectable OME-Zarr
  v3 I/O layer so reads/writes can use either the native `zarrMex` engine **or** `zarr-python` (v3),
  chosen via `preferences.IO.ZarrLibrary` ('native' | 'python'). New package `mib/+io/+zarr/`:
  - `Config` — process-wide backend + python-interpreter path; set at start-up from
    `initializePreferences` (`io.zarr.Config.setLibrary/setPythonPath`). Preferences dialog wired:
    `controllers.Preferences` `InputOutputPanel` (`ZarrLibrary` dropdown + `ZarrLibraryLabel`),
    inited in `updateWidgets` (panel index 7), described in `InputOutputPanelCallbacks`, committed in
    `ApplyButtonPushedCallback` (mid-session, no restart) via a shared `zarrLibraryDescription` helper.
  - `Array` / `Group` — drop-in facades for `ZarrArray`/`ZarrGroup`. **Metadata** (create array/group,
    attributes, resize) is always written natively for an identical on-disk structure; only **bulk
    read/write/info** honour the backend. HTTP/HTTPS arrays force native (python remote needs fsspec).
  - `PyBackend` — python read/write via numpy, **byte-identical to zarrMex**. Convention (validated
    against zarrMex, transpose-coded & plain, full & partial, incl. bool/uint8 packed):
    read `out = permute(reshape(typecast(region.tobytes,mtype), fliplr(shape)), nd:-1:1)`; write is
    the exact inverse (`permute(data,nd:-1:1)` → C-order bytes → numpy region → `setitem`).
  Routed through the facade: `io.loaders.Zarr3VirtualLoader` (reader), `io.savers.Zarr3Saver`
  (writer), `core.MibBigDataLabels` (disk-backed model store). Verified end-to-end via MCP with both
  backends and full cross-backend interop (native-written/python-read and vice versa). Default
  `'native'`, so existing behaviour is unchanged until the user opts into python. Tested env:
  `D:\Python\Miniforge\envs\sam4mib\python.exe`, zarr 3.1.6, numpy 2.4.3.
  Python-reader perf (2026-06-15): first cut was ~9× slower than native (207 ms vs 23 ms for a
  1024×1024 uint16 region) — OutOfProcess Python makes every `py.*` call an IPC round-trip and the
  payload crosses a process boundary. Optimised to **~30 ms (~1.3× native, ~7× faster)** by:
  (1) doing the whole slice→contiguify→`tobytes` in a SINGLE `pyrun` (slice tuple built in Python
  from numeric start/end vectors — no per-dim `py.slice` round-trips); (2) converting the payload with
  `uint8(py.bytes)` directly instead of routing back through `numpy.frombuffer` (avoids a double
  boundary crossing, ~4×); (3) `Zarr3VirtualLoader` caching the `io.zarr.Array` per pyramid level and
  `io.zarr.Array` caching the py handle + shape/dtype, so neither is reopened/re-queried per slice.
  Writes use the same single-`pyrun` consolidation. (NB: never `clear classes` while OutOfProcess
  Python objects exist — it wedges the interpreter for the whole MATLAB session, restart required.)
  Slider scrolling (`MibImageDocument.sliderDragCallback`): native zarr reads (~7 ms) now render
  **live** during drag via the in-memory wall-clock throttle (40 ms ≈ 25 fps) instead of the 100 ms
  deferred debounce; the debounce is kept only for the slower python backend
  (`io.zarr.Config.isPython()`).
- **Migrate ImageConverter's writer onto `io.zarr`** — `ImageConverter.generateZarr` is still its own
  Python pipeline (`pyrun`+`zarr`+`numpy`, Zarr **v2**/v3, sharding, out-of-core z-chunk streaming from
  a file datastore). Now that `io.zarr` exists, it could become the single writer. Blockers unchanged:
  `io.zarr`/native writer needs out-of-core streaming and lacks Zarr v2 + sharding — port those before
  switching. Until then ImageConverter (batch file→zarr) and Zarr3Saver (in-app dataset→BigData)
  coexist by scope.
- **BigData reads are OME-Zarr v3 only** (confirmed: `ExtensionRegistryLoad` has
  `BigData.Default = {'zarr3'}`, `BigData.BioFormats = {''}`). BioFormats / OpenSlide WSI are NOT
  readable directly in BigData mode (they work in Standard/Virtual). Path to use them: the **ingest
  converter** (read via BioFormats/OpenSlide → write a `.zarr3` pyramid → open as BigData). Broaden
  `BigData.*` registry entries once a streaming reader or the converter exists.

## Context

MIB3 supports two dataset modes — `Standard` (fully in memory) and `Virtual` (read-on-demand). The goal is a third mode, **`BigData`**, for datasets too large to fit in memory, built on pyramidal nD formats for efficient read/write, with segmentation blended in.

**Key finding from exploration: most of the scaffolding already exists.**
- `MibDataset.datasetType` already declares `'BigData'`.
- The extension registry (`io.ExtensionRegistryLoad`, `BigData.Default = {'zarr3'}`) and `io.LoaderFactory` already route `BigData` to `Zarr3VirtualSetupLoader`, which already accepts `options.datasetMode = 'BigData'`.
- A working **pyramidal Zarr3 reader** exists: `io.loaders.Zarr3VirtualLoader` (`readRegion` via `zarrMex`/`ZarrArray`), driven by `core.MibVirtualImage.getDataZarr` with full multiscale level selection (magFactor → level) and orientation handling.
- The only dead-end is `core.MibDataset.initialize` line 102: `error('BigData - not implemented')`, plus `switchDatasetMode` case 3 not wiring segmentation.

**Verified capabilities in this MATLAB (R2026a):**
- `blockedImage`, `images.blocked.Adapter` (methods `openToRead/openToWrite/getInfo/getIOBlock/setIOBlock/close/openInParallelToAppend/alreadyWritten`), and `images.blocked.H5` all present.
- `ZarrArray` (`mib/external/Zarr3Matlab/`) supports **read AND write**: `create`, `createFromData`, `write`, `resize`, `read`, `get/setAttributes`, `info`, `shape`, `dataType`.
- Toolboxes present: Image Processing 26.1, Medical Imaging 26.1, Parallel Computing 26.1.

**Chosen architecture (per user decisions):** Hybrid — use MATLAB `blockedImage` as the unifying abstraction, backed by a **custom Zarr3 adapter** that reuses the existing native zarr engine for I/O. This gives blockedImage's tiling / `apply` / `gather` / memory management / parallel write while keeping zarr as the on-disk format. The segmentation model/mask/selection will be a **disk-backed pyramidal store** (also blockedImage-over-zarr), with cross-level propagation. Delivered in phases; can stop after any phase.

---

## Architecture

```
core.MibDataset (datasetType='BigData')
  ├── image  : core.MibBigDataImage      (subclass of core.MibImage, sibling of MibVirtualImage)
  │              └── blkImg = blockedImage(ZarrBlockedAdapter(rootPath), ...)  // multi-resolution
  └── labels : core.MibBigDataLabels      (63-class packed, disk-backed pyramidal)
                 └── blkModel = blockedImage(ZarrBlockedAdapter(modelPath,'w'), ...)

io.adapters.ZarrBlockedAdapter  < images.blocked.Adapter
   getInfo  -> ZarrArray.info / shape (per pyramid level => blockedImage Levels)
   getIOBlock -> ZarrArray.read(bbox)            // reuses Zarr3VirtualLoader logic
   openToWrite/setIOBlock -> ZarrArray.create/write/resize + setAttributes
```

The adapter is the single new low-level piece; everything else reuses existing patterns (`MibVirtualImage` for the image class shape, `MibLabels63` bit-packing for the model, `getDataZarr` coordinate/orient math).

---

## Phase 0 — Foundations & spike (de-risk first)

Goal: prove the hybrid stack end to end on a throwaway dataset before touching MibDataset wiring.

1. **Zarr write round-trip spike** (MCP `evaluate_matlab_code`): `ZarrArray.create` a small 3-level pyramid, `write` blocks, `read` them back, set OME-Zarr `multiscales` attributes via `setAttributes`. Confirm chunking/shape semantics and axis order vs. `Zarr3VirtualLoader.computePermutation`.
2. **`io.adapters.ZarrBlockedAdapter`** (new, `mib/+io/+adapters/ZarrBlockedAdapter.m`): subclass `images.blocked.Adapter`.
   - `getInfo` → report `Size` per resolution level (from `ZarrArray.shape` of each pyramid level), `IOBlockSize` (= zarr chunk/shard size), `Datatype`, `InitialValue`.
   - `getIOBlock(level, ioBlockSub)` → translate block subscript to a bbox and call the same read path as `Zarr3VirtualLoader.readRegion` (reuse/extract its bbox+permute helper so logic is shared, not duplicated).
   - `openToWrite` / `setIOBlock` / `close` → `ZarrArray.create`/`write`/`resize` for the writable (model) case.
   - `openInParallelToAppend` / `alreadyWritten` → support `parfor` writes for propagation.
3. Spike: wrap a real OME-Zarr pyramid (one of the existing test `.zarr3` datasets) as `blockedImage(ZarrBlockedAdapter(...))`, verify `gather` of a level and `getRegion` of a sub-block match `Zarr3VirtualLoader` output.

Representative files: new `mib/+io/+adapters/ZarrBlockedAdapter.m`; reference `mib/+io/+loaders/Zarr3VirtualLoader.m`, `mib/+core/@MibVirtualImage/getDataZarr.m`, `mib/external/Zarr3Matlab/ZarrArray.m`.

**Exit gate:** blockedImage-over-zarr reads a level and a sub-block correctly; a written zarr array reads back identically.

---

## Phase 1 — Open & browse BigData (read-only)

Goal: open a pyramidal zarr in BigData mode and browse it (no segmentation).

1. **`core.MibBigDataImage`** (new `mib/+core/@MibBigDataImage/`, subclass `core.MibImage`, modeled on `@MibVirtualImage`):
   - `type = 'bigdata'`; holds `blkImg` (blockedImage over `ZarrBlockedAdapter`) + the existing `pyramid` struct (`levelNames/levelImageSizes/levelScaleFactors/...`) populated by the setup loader.
   - `getData(layerType, orient, colChannel, options)` → select pyramid level from `options.magFactor`/`pyramidLevel` (reuse `getDataZarr` math), read the region through `blkImg`/adapter, permute to requested orient. Effectively the `getDataZarr` logic routed through blockedImage.
   - `initialize`, `closeDataset` analogous to `@MibVirtualImage`.
2. **`core.MibDataset.initialize`** (`mib/+core/@MibDataset/initialize.m`): replace the `case 'BigData'` error (line 102) with construction of `core.MibBigDataImage(img, meta)` and a placeholder empty `labels` (full model creation deferred to Phase 2).
3. **`switchDatasetMode`** (`mib/+core/@MibDataset/switchDatasetMode.m`): case 3 already sets `datasetType='BigData'`; set `enableSelection=false` for browse-only (Phase 2 flips this when a model is created).
4. **getData routing** (`mib/+core/@MibDataset/getData2D.m`/`3D`/`4D`): the existing non-Standard slow path already calls `obj.image.getData(...)`; confirm `'BigData'` flows through (it should, since the fast path is gated on `'Standard'`). Add explicit handling only where `datasetType(1)=='V'` checks exclude BigData (e.g. `closeVirtualDataset` calls, `cropDataset`).
5. **Open path**: `Zarr3VirtualSetupLoader` already returns pyramid + Virtual metadata for `datasetMode='BigData'`; verify `LoaderFactory` case `"OmeZarr"` passes the mode through. UI: `controllers/@MibActiveDataset/datasetTypeChange_Callback.m` already handles `newMode=3`.

Representative files: new `mib/+core/@MibBigDataImage/*`; edit `mib/+core/@MibDataset/{initialize,switchDatasetMode,getData2D,getData3D,getData4D}.m`; verify `mib/+io/LoaderFactory.m`, `mib/+io/+loaders/Zarr3VirtualSetupLoader.m`, `mib/+controllers/@MibActiveDataset/datasetTypeChange_Callback.m`.

**Exit gate:** open an OME-Zarr v3 pyramid as BigData, scroll Z, zoom (level switches by magFactor), switch orientation — all read-only, memory stays bounded.

---

## Phase 2 — Segmentation on BigData (disk-backed pyramidal model)

### Design (confirmed during implementation)

**Integration seam:** `MibDataset.getData2D/3D/4D` + `setData2D/...` (slow path) call
`obj.labels.getData(type,orient,col,options)` / `setData(...)`. For a 63-model,
`MibImage.getData` routes non-image layers to `obj.getData63(...)` (and `setData`→`setData63`).
So a `core.MibBigDataLabels < core.MibLabels63` that **overrides `getData63`/`setData63`** to
operate on a disk-backed packed zarr makes ALL of getData2D/3D/4D, setData2D/3D/4D, and every
segmentation tool work unchanged. No tool edits needed.

**Storage:** packed uint8 (bits 1–6 material, bit 7 mask, bit 8 selection — identical to
MibLabels63) in a writable zarr, native MATLAB axis order (transpose codec → no permute),
created via `ZarrArray`/`ZarrBlockedAdapter`. `obj.data` stays empty; dims from
height/width/depth. Default location: temp scratch (`tempname`-based) until Phase 3 "save as".

### Sub-milestones
- **2a (foundation):** `MibBigDataLabels` class; create-on-demand store; `getData63`/`setData63`
  block-wise read/modify/write at a single full-res level; `createModel` BigData branch enables
  selection. Verified by getData2D/setData2D round-trip + on-disk persistence. *(no display/zoom
  compositing, no pyramid yet)*
- **2b:** model pyramid (levels mirror the image) + cross-level propagation; `getRGBimage` model
  overlay for BigData/Virtual so the model shows over the image at any zoom.
- **2c:** mask/selection restrictions, backup/clearLayer coverage, tool guards audit.

### Phase 2a — DONE (2026-06-14)

Disk-backed packed model foundation, verified headlessly via MCP.

New: `mib/+core/@MibBigDataLabels/` — `MibBigDataLabels.m` (class + `createStore`/`closeStore`/
`readPacked`/`writePacked`), `getData63.m`, `setData63.m`. Edited: `@MibDataset/createModel.m`
(BigData branch builds the disk store, sets `enableSelection=true`, `modelExist=true`).

- `MibBigDataLabels < MibLabels63`; packed uint8 stored in a writable zarr (`ZarrArray`, native
  axis order). `obj.data` empty; dims from height/width/depth.
- `getData63`/`setData63` overrides do block read / read-modify-write against the store, with the
  identical bit logic (bits 1–6 material, 7 mask, 8 selection) and orientation handling.
- Single full-resolution level for 2a (`options.magFactor` ignored → pyramid is 2b).

Verified: `createModel(63)` on a BigData set creates the store + enables selection;
`setData2D`/`getData2D` round-trip for selection AND labels(material) with mask/selection
bit-preservation; block isolation across z; raw on-disk zarr shows correct packed bits; store
reopens from disk. All four changed files clean under `check_matlab_code`.

### Phase 2b — DONE (2026-06-14)

Made BigData segmentation usable in the live app: model overlay + UI re-enable.

- `@MibModel/getRGBimage.m`: `imgRAW` now set for BigData (cursor value readout); overlays
  (model/mask/selection) resized to the displayed image size for on-demand pyramidal datasets
  (the model store is full-res while the image shows at pyramid/zoom res → would mismatch).
- `@MibController/updateGuiWidgets.m` + `@MibImageDocument/updateBrushCursor.m`: brush cursor /
  segmentation UI now gated by "browse-only" = Virtual OR (BigData AND no model). A BigData set
  WITH a model behaves like Standard.
- `@MibModel/createModel.m`: BigData allowed through the `enableSelection==0` gate (creating the
  model is what enables segmentation — chicken/egg) and forced to the 63-material packed type
  (skips the type dialog).

Verified on the live pyramidal dataset: createModel builds the store + enables selection;
selection round-trips at full-res; `getRGBimage` composites the overlay at both full-image and
zoomed/block-mode views with NO size-mismatch error; live state restored after the test.

### Model store location prompt (2026-06-14)

Per request, the BigData model store is no longer silently placed in temp — the user is asked.
- `@models/@MibModel/createModel.m`: added `BatchOpt.ModelStorePath` (+tooltip); for BigData,
  forces type 63, skips the model-type dialog, and shows a `uiputfile('*.zarr3', ...)` prompt
  (default `Model_<imageStem>.zarr3` next to the image) when interactive; threads the chosen path
  into `obj.I{id}.createModel(63, names, storePath)`. Cancel → `StopProtocol`, no model.
- `@core/@MibDataset/createModel.m`: 4th arg `modelStorePath`, passed to `createStore`.
- `MibBigDataLabels.createStore(dims, storePath)`: honors an explicit path; empty → temp fallback.
Verified `createStore` path honoring headlessly AND on the live app (model created at the chosen
`.zarr3`, names parsed, selection round-trip) — no MIB restart needed.

**Gotcha learned (important for this port):** MATLAB hot-reloads method *bodies* but NOT
*signature* (parameter-count) changes while the running app holds instances of that class — a
3→4-arg change to `core.MibDataset.createModel` threw "Too many input arguments" live. **Fix:**
keep `MibDataset.createModel` at its original signature; all BigData store-path logic lives in
`MibModel.createModel` (signature unchanged → reloads live) which builds `MibBigDataLabels` +
`createStore(dims, chosenPath)` inline for BigData. Rule: avoid changing core-class method
signatures mid-session; put new params in the (already 4-arg, stable) MibModel wrappers instead.

### Phase 2b-tail — DONE (2026-06-14): pyramid-matched model + propagation

The model now **mirrors the image pyramid** instead of being a single full-res level.
- `MibBigDataLabels.createStore(dims, storePath, pyramid)`: builds a zarr **group** with one
  packed uint8 array per image level (sizes = `levelImageSizes`, chunks derived from the image's
  `chunkSizes` tczyx→yxz), stores `modelLevelSizes`/`modelScaleFactors`/`modelArrays`, writes an
  OME-NGFF `multiscales` attribute. Single-level fallback when no pyramid.
- `getData63`: `pickLevel(options.magFactor)` → reads that level's region, resizes to display
  resolution with the SAME formula as `getDataZarr` (so image and model line up exactly in tools);
  unpacks bits.
- `setData63`: resizes the incoming display-res data to the working level, read-modify-writes that
  level, then **propagates** the edited region to every other level (nearest-neighbour resize of the
  packed bytes via `resizeBlockNearest`/`imresize3` — preserves material/mask/selection bits).
- Both `createModel` callers pass `obj.image.pyramid` to `createStore`.
- Hardening: `closeStore` now also sets `exists=false`; `getData63`/`setData63` no-op when the store
  is absent (avoids crashes on a stale handle).

Verified headlessly (5 levels matching image sizes; finest-level edit → coarse levels get the
downsampled selection on disk; coarse-level edit → finest level upsampled) AND on the live app
(create model builds 5 matching levels; coarsest level received propagation; overlay renders at
full + zoomed views with no error; session restored clean). All files clean under `check_matlab_code`.

### Phase 2c (partial) — DONE (2026-06-14): clear + undo verified

`clearLayer` and backup/undo work for the disk-backed pyramid model **with no code changes** —
both route through `getData2D`/`setData2D` → `getData63`/`setData63`, so clearing a layer writes
zeros through `setData63` (propagated across levels) and undo stores/restores the packed
`'everything'` block. Verified: clear selection (2D) preserves material + propagates to coarse
levels; clear labels (4D) wipes the model; backup→edit→undo restores the prior selection exactly.
Note `backup`'s `'Virtual'` guard (line 143) does NOT catch BigData, which is correct (BigData
should support undo). Memory caveat: a 3D backup/clear of a very large model still materialises a
full-res block — fine interactively (2D/per-slice), heavy for whole-volume ops.

**Still pending (2c):**
- Orientation-switch keys (ZX/ZY) remain disabled for BigData (getData63 supports orient, the key
  nav is gated off like Virtual).
- backup/undo + clearLayer coverage for the disk-backed model; T>1 (time-series) model.
- Audit of processing-tool `datasetType,'Virtual'` guards for BigData.
- (Was the original 2b note:) interactive segmentation in the live app needs (1) `getRGBimage` model overlay
for BigData/Virtual so the model is visible over the image at any zoom, and (2) re-enabling the
segmentation UI for a BigData set that HAS a model — currently `updateGuiWidgets`/`updateBrushCursor`
suppress the brush cursor for all `'B'` datasets (set in the Phase 1 interaction fix); that
suppression must become "browse-only BigData" rather than "all BigData". Also: model pyramid +
cross-level propagation, and backup/clearLayer coverage.



Goal: segment a BigData dataset with a writable, pyramidal, disk-backed 63-class model, propagated across levels.

1. **`core.MibBigDataLabels`** (new, modeled on `core.MibLabels63` packing: bits 1–6 material, bit 7 mask, bit 8 selection): backing store is a writable `blockedImage(ZarrBlockedAdapter(modelPath,'w'))` with the same level grid as the image pyramid.
   - `getData63`/`setData63`-equivalents operate block-wise: read affected blocks, unpack/repack bits, write back. Reuse `@MibLabels63/getData63.m` & `setData63.m` bit logic.
2. **Create-model-on-demand workflow**: when the user starts segmentation on a browse-only BigData set, prompt to create a new 63-material model; allocate the disk-backed pyramidal model store (zarr root next to the image, or a temp/scratch location), flip `enableSelection=true`, set `modelExist`.
3. **Cross-level propagation**: edits happen at the current working level. Maintain a **dirty-region queue**; propagate modified blocks to other levels by `imresize`/`nearest` down/up-sampling, executed on the Parallel pool (`parfor` via `openInParallelToAppend`) or a `parfeval` background task so the UI stays responsive. Coarser levels update immediately for display; finer levels can lag. Document consistency model (display-level authoritative until propagation completes).
4. **Segmentation tools**: brush/threshold/region-growing already call `getData2D/setData2D('selection'|'mask'|'labels', ...)`. Ensure these route to `MibBigDataLabels` block-wise and respect the working level. Add guards where a tool needs the full volume in memory (offer "process current level/region only").
5. **Copy-or-modify image edits**: when an operation would modify *image* pixels (not the model), prompt: (a) make a copy (convert region/dataset to Standard), or (b) modify the underlying zarr in place (write-back via adapter). Models never touch the source image, so no prompt there.

Representative files: new `mib/+core/@MibBigDataLabels/*`; reference `mib/+core/@MibLabels63/{getData63,setData63}.m`; edit `mib/+core/@MibDataset/{initialize,createModel,getData2D,setData2D,getData3D,setData3D}.m`; segmentation tools under `mib/+controllers/@MibImageDocument/segmentation*.m`.

**Exit gate:** create a model on a BigData set, brush/threshold at a working level, see coarser levels update, model persists to disk and survives reopen.

---

### Phase 3a — DONE (2026-06-14): model reopen (openStore)

The BigData model is persisted live (every `setData63` writes to its `.zarr3`), so "save" already
happens continuously; the missing piece was **reattaching** to a saved store. Added
`MibBigDataLabels.openStore(storePath)`: opens the existing OME-NGFF group, restores
`modelLevelSizes`/`modelScaleFactors`/`modelArrays` from the `multiscales` metadata + array shapes
(no pixels read into memory), sets state from level 0. Verified close→reopen: 3 levels with sizes
& scales restored, selection + material + coarse-level propagation all persisted, reads work at
every magnification. Clean under `check_matlab_code`.

### Phase 3b — DONE (2026-06-14): load-model UI wiring + "saved live" dialog

- **Load model (BigData)**: `@MibModel/loadModel.m` now has a BigData branch *before* the
  enableSelection guard (browse-only chicken/egg): a `.zarr3` model is a folder, so GUI mode uses
  `uigetdir` to pick the store (batch/drag-drop uses `BatchOpt.Filenames`), then builds
  `MibBigDataLabels` + `openStore` and attaches it **by reference** (no full-array load), validating
  that the model's finest level matches the image. Body-level branch only (no signature change).
  Verified live: create model → write selection → drop to browse-only → loadModel(store) → selection
  returns exactly; labels=MibBigDataLabels, 5 levels, modelExist/enableSelection set.
- **"Saved live" explainer**: `@MibModel/createModel.m` BigData branch shows a one-time info dialog
  ("the model is written to disk continuously … 'save' happens live") with a **Do not show again**
  checkbox persisted in `sessionSettings.DoNotShowDialogs.BigDataModelCreated` (same convention as
  `MeasureLength`). Interactive-only (`nargin<4`), so batch/headless paths skip it.

### Phase 3c — DONE (2026-06-14): persistent "do not show again" + material persistence

- **"Do not show again" moved to preferences** (was session-scoped, erased each session). Added
  `Prefs.DoNotShowDialogs = struct()` to `generatePreferences`; both the BigData "saved live"
  dialog (`@MibModel/createModel`) and the existing MeasureLength hint
  (`@MibController/measureLength`) now read/write `preferences.DoNotShowDialogs.<Name>` (isfield-
  guarded for old prefs). Removed the orphaned `sessionSettings.DoNotShowDialogs` init.
- **Material names/colours persistence**: `MibBigDataLabels.writeMaterialMetadata()` saves a
  `mibMaterials` attribute (names + colours, alongside `multiscales`); `openStore` restores it.
  Persisted at model creation (`createModel`) and on every material mutation
  (`@MibModel/addMaterial`, `renameMaterial`, `removeMaterial` now call it for BigData);
  `loadModel` uses the restored names/colours. Verified headless: create with named materials →
  reopen → names + colours + count restored, multiscales intact.
  NOTE: `removeMaterial`'s pixel renumbering on a disk-backed model is part of the deferred
  segmentation-parity work; only the name list is persisted here.

**Remaining Phase 3:**
- **Zarr3 writer — note on scope (revised 2026-06-14).** A "re-export the BigData image/model to
  zarr3" operation is **NOT needed**: the model is already written live to a valid standalone
  OME-Zarr v3 group (external tools can open it), and the BigData image is read-only from its
  source `.zarr3`. A zarr3 *writer* is only useful for:
  1. **Ingest / convert** — produce a zarr3 BigData pyramid from a **Standard or Virtual** dataset
     (the path to *create* a BigData dataset from one that isn't zarr3 yet; also for future
     BioFormats/OpenSlide BigData reads → convert to zarr3 for editing). This is the real
     justification for `io.savers.Zarr3Saver`.
  2. **"Save As" / relocate** the model (or image) store to another folder (copy). Minor.
- **Standard-format export of any pyramid level (compatibility & reuse).** Let the user pick a
  level (e.g. `s2`) and export that level's **image and/or model** to MIB's standard formats
  (TIFF/OME-TIFF, HDF5, NRRD, MRC, Amira, `.model`, …) by gathering the single level through the
  existing `io.SaverFactory` pipeline. Makes BigData datasets interoperable with the rest of MIB and
  external tools. **Future.**
- **Copy-or-modify** image edits (modify underlying zarr vs save a Standard copy).

### Phase 3 (ingest) — DONE (2026-06-14): Zarr3 pyramid writer

New `mib/+io/+savers/Zarr3Saver.m` — `save(data, metadata, filename, options)` writes a 5D image
``[y x z c t]`` as an **OME-Zarr v3 multiscales pyramid**: native MATLAB axis order (transpose codec),
axes declared `y,x,z` (+`c`/`t` only when >1), level 0 = full res, each further level halves Y/X
(Z kept), per-level `scale` CT = `pixSize × 2^level` in XY. Auto level count
(stop when min(Y,X) < `MinLevelSize`, capped by `MaxLevels`); configurable chunk/codec/downsample.

Verified: a Standard image written by `Zarr3Saver` **reopens through the real
`Zarr3VirtualSetupLoader` in BigData mode** — correct `nLevels`/sizes/`levelScaleFactors`/`axisOrder`,
level-0 round-trips exactly, `magFactor` selects the right level. Works for grayscale 3D AND
multichannel (`axisOrder=yxzc`, colours preserved). Clean under `check_matlab_code`.

### Phase 3 (ingest UI) — DONE (2026-06-14): two entry points wired

Native `Zarr3Saver` chosen for ingest (no Python; consistent with BigData reads). Shared helper
`Zarr3Saver.exportDataset(mibModel, id, filename, options)` gathers the active dataset's image and
writes the pyramid. Two UI entry points:
- **Ribbon → Export → "Export to Zarr3"** (`@MibView/addRibbonHome.m` adds the `exportToZarr3`
  ListItem; `@MibRibbon/MibRibbon.m` wires `ItemPushedFcn`; `@MibRibbon/home_Callbacks.m` case
  prompts a `.zarr3` path and calls `exportDataset`). *Writes only* — does not reopen.
  **NOTE: the menu item appears only after a MIB restart** (the ribbon is built at startup; adding a
  widget isn't hot-reloadable). The callback bodies reload live.
- **Datasets panel → type dropdown → BigData** (`@MibActiveDataset/datasetTypeChange_Callback.m`):
  when a real Standard/Virtual dataset is open, offers to **convert** it — prompt `.zarr3` location,
  `exportDataset`, then reopen via `Zarr3VirtualSetupLoader` and `initialize(...,'BigData')` in place;
  updates `Sets.datasetTypes` + fires `NewDataset`. Empty buffers still get the blank-BigData path.
  This is a method-body change → reloads live (no restart needed).
  - **Three-way switch (2026-06-14):** when a real dataset is open, the BigData confirm now offers
    **Convert current** / **New (default)** / **Cancel**. "New (default)" discards the open dataset
    and starts an empty BigData placeholder via `switchDatasetMode(3, …, {default.h5})` (browse-only).

Verified end-to-end: `exportDataset` on the live dataset round-trips through the real BigData loader;
the full convert sequence yields a `MibBigDataImage` (browse-only) whose level 0 matches the source.

### Phase 3 (ingest UI) — extended (2026-06-14): model export + settings dialog

- **Model export**: `Zarr3Saver.exportModel(mibModel, id, filename, options)` gathers the
  material-index label volume (`getData4D('labels')`), writes an OME-Zarr v3 pyramid with
  **nearest** downsampling, and stores material names/colours in a `mibMaterials` attribute. Wired
  to **Ribbon → Model → Export → "Export model to Zarr3"** (`addRibbonModel.m` item +
  `MibRibbon.m` wiring + `model_Callbacks.m` case).
- **Settings dialog**: `Zarr3Saver.optionsDialog(parentFig, mibPath, isModel)` collects pyramid
  levels (0 = auto), chunk size [Y X Z], compression (zstd/gzip/none), and (image only) downsample
  method; returns an options struct or `[]` on cancel. Now shown by all three entry points (image
  Export, model Export, and the type-dropdown Convert-to-BigData).
- Verified: model label volume round-trips exactly through zarr3 with nearest downsampling
  (materials preserved at coarse levels); material names persist. All changed files clean under
  `check_matlab_code` (two pre-existing warnings unrelated).
- **Caveat:** the export helpers read `getData4D`, which squeezes singleton dims — for a **grayscale
  T>1** dataset the time axis would be misread as colours. Fine for T=1 (the norm); tied to the
  deferred T>1 work.

**Ingest follow-ups (not yet):**
- `SaverFactory` registration (so the generic "Save image as…" dialog also offers zarr3).
- **Large/Virtual source** — writer needs the full volume in memory today; stream level-by-level for
  out-of-core sources.
- **Z-downsampling** at coarse levels (currently XY-only) + optional **model export** alongside.

### Bugfix (2026-06-14): BigData opens browse-only (segmentation gated until a model exists)

Symptom: brushing a freshly opened BigData set crashed in `gui_WindowButtonUpFcn`
(`imresize(..., size(currSelection), ...)` with a 0-size `currSelection`). Root cause: the
File→Open path set `enableSelection` from preferences (default on), so segmentation tools activated
on a BigData set **with no model** — `getData2D('selection')` returns empty (placeholder labels) →
crash. Affected ALL selection tools, not just brush.

Fixes:
- **Root** — `@core/@MibDataset/initialize.m`: the BigData branch now forces `enableSelection=false`
  regardless of caller/preferences. BigData is browse-only until a model is created (`createModel`)
  or loaded (`loadModel`), both of which set `enableSelection=true`. This gates every segmentation
  tool (via the `enableSelection==0` guard in `gui_WindowButtonDownFcn`) until a model exists.
- **Defensive** — `@controllers/@MibImageDocument/gui_WindowButtonUpFcn.m`: the brush commit now
  skips (instead of crashing) when `currSelection` is empty, while still restoring callbacks.

Verified: `initialize(...,'BigData',...,true)` yields `enableSelection=0`; with a model present the
brush commits normally. Note this is intentional design (browse-only + create-model-on-demand with
a store-location prompt), not auto-initialisation of a model.

### Bugfix (2026-06-14): closing a BigData/Virtual dataset left a stale type in the Datasets panel

Closing a buffer (`@controllers/@MibActiveDataset/buffers_ContextMenu.m`, `'close'`/`'closeSet'`)
replaces the dataset with a fresh **Standard** one, but never reset `mibModel.Sets.datasetTypes{set,
local}` — which is the cache `buffers_Callback` uses to drive the panel's type dropdown. So after
closing a BigData (or Virtual) set the dropdown kept showing "BigData" while the dataset was actually
Standard. Fixed both close paths to set `Sets.datasetTypes{targetSet, localId} = 'Standard'` after
creating the replacement (`targetSet = floor((globalId-1)/datasetsInSet)+1`). (The `closeVirtualDataset()`
call already released the BigData zarr readers — that part was fine.) Verified the indexing matches
the cell `buffers_Callback` reads; corrected the already-stale live session too.

### Bugfix (2026-06-14): loading an exported zarr3 model crashed (invalid bbox)

Loading a `.zarr3` model written by `Zarr3Saver.exportModel` crashed in `getData63`/`readPackedLevel`
("Bounding box has invalid shape", e.g. `Zl=[467,171]`). Root cause: a **scale-semantics mismatch**
— `Zarr3Saver` writes the OME-NGFF `multiscales.scale` as **physical voxel size** (e.g. 0.013),
while `createStore` wrote it as **relative factors** ([1,2,4]); `openStore` used the raw value as
`modelScaleFactors`, so for an exported model the factors became tiny → `pickLevel` chose a coarse
level and the coordinate scaling produced an out-of-range Z.

Fixes (`@core/@MibBigDataLabels/`):
- `openStore` now **normalises** to level-0-relative factors (`scaleFac ./ scaleFac(1,:)`), matching
  what `Zarr3VirtualSetupLoader` derives for the image — correct for BOTH store formats.
- Added `clampRange` static helper; `getData63` and `setData63` clamp Y/X/Z index ranges to
  `[1, levelSize]` (ascending), so a too-small level can never yield an invalid zarr bbox.
Verified: an exported (voxel-size-scale) model reopens with factors `[1;2;4]`, reads at multiple
magnifications + block mode with no crash, materials preserved. Live class was reloaded (no restart).

**Interop nicety (future):** `createStore.writeMultiscales` writes relative factors as the `scale`;
for OME-NGFF correctness it should write physical voxel sizes (external tools read `scale` as voxel
size). MIB round-trips fine either way thanks to the openStore normalisation.

## Phase 3 — Save / write-back (zarr3)

Goal: persist BigData image and/or model as OME-Zarr v3.

1. **`io.savers.Zarr3Saver`** (new `mib/+io/+savers/Zarr3Saver.m`): use `ZarrArray.create`/`createFromData`/`write`/`resize` + `ZarrGroup` for the multiscales group, and `setAttributes` to write OME-NGFF `multiscales`/axes/datasets metadata matching what `Zarr3VirtualSetupLoader` parses on read (round-trip compatible). Support chunk/shard sizing and a pyramid build (downsample levels).
2. **Register in `io.SaverFactory`**: add the format to `getFormats('image')`, `buildRegistry`, and the `create` switch.
3. **Write-back vs save-copy**: "Save as zarr3" writes a fresh pyramid; "commit to underlying" writes modified blocks back to the source zarr in place (reuse the writable adapter from Phase 2). Model saved as a sibling zarr group.

Representative files: new `mib/+io/+savers/Zarr3Saver.m`; edit `mib/+io/SaverFactory.m`; reference `mib/+io/+savers/HDF5Saver.m` (interface `save(data, metadata, filename, options)`), `mib/external/Zarr3Matlab/{ZarrArray,ZarrGroup}.m`.

**Exit gate:** save a segmented BigData set to zarr3, reopen it (image + model) round-trips correctly.

---

## Cross-cutting concerns

- **Shared bbox/permute logic**: extract the zarr bbox-build + axis-permutation from `Zarr3VirtualLoader.readRegion` into a helper reused by both the loader and `ZarrBlockedAdapter` to avoid divergence.
- **`datasetType(1)=='V'` checks**: several places branch on Virtual via first letter `'V'` (e.g. `cropDataset`, `closeVirtualDataset` guard in `initialize`). Audit each for whether BigData should share or differ; BigData starts with `'B'`, so add explicit handling, don't rely on `'V'`.
- **Memory guardrails**: never call `getData4D`/full-volume gather on a BigData set without a size check; operations default to current level/region.
- **Docs/memory**: keep this file as the running log; add user-doc + API-doc entries per repo rules when public methods/UI land.

## Verification

- **Spike & unit checks** via MCP `mcp__matlab__evaluate_matlab_code` after each phase: zarr write round-trip, adapter read==loader read, blockedImage gather correctness.
- **Static check**: `buildtool check` and `mcp__matlab__check_matlab_code` on new files.
- **Tests**: add cases under `tests/` following existing patterns (`run_matlab_test_file`); reuse the standard-dataset test harness. At minimum: open-BigData test, getData-level-selection test, model write/propagate/reopen test, zarr3 save round-trip test.
- **Interactive**: drive the live `mib` (MibController) in the MATLAB workspace — open a real OME-Zarr pyramid, browse, segment, save.

## Open risks / to validate during Phase 0

- Exact `ZarrArray.create`/`write` chunk & shard semantics and whether per-level groups match OME-NGFF the setup loader expects (round-trip).
- blockedImage `IOBlockSize` alignment with zarr chunks for efficient partial writes.
- Propagation latency vs. interactivity for very deep pyramids — may need a coarser propagation cadence.

---

## Progress log

### Phase 0 — DONE (2026-06-14)

Delivered `mib/+io/+adapters/ZarrBlockedAdapter.m` — an `images.blocked.Adapter`
subclass backed by `ZarrArray`/`zarrMex`. Read + write both validated via the MATLAB MCP.

Key findings (carry into Phases 1–3):
- **Native axis order.** `ZarrArray.create` applies a transpose codec, so arrays we
  create/write round-trip in MATLAB column-major order with **no permutation**. The
  adapter therefore needs no axis remap for MIB-native pyramids (model store, Zarr3
  saver, round-tripped images). External OME-Zarr (C-order `tczyx`) still needs the
  permute path in `io.loaders.Zarr3VirtualLoader` — Phase 1 image browse will either
  reuse that loader or extend the adapter with an `axisOrder` parameter.
- **bbox convention** is `[start, end+1]` (end-exclusive), 1-based.
- **`info` fields**: `shape`, `dataType`, `chunkShape`, `shardShape`. Adapter maps
  `chunkShape` → `IOBlockSize`, clamped to level Size (blockedImage requires
  `IOBlockSize <= Size`; coarse levels can have chunk > size).
- **blockedImage construction**: read = `blockedImage(src, Adapter=adapter)`;
  write = `blockedImage(dest, imageSize, blockSize, initVal, Mode="w", Adapter=adapter)`.
  `getInfo`/`getIOBlock`/`openToRead` are the only required overrides;
  `openToWrite`/`setIOBlock` added for the writable model + saver.
- **`gather(bim)` defaults to the COARSEST level** — always pass `'Level', L` explicitly.
- Adapter `openToWrite` also writes a minimal OME-NGFF v0.5 `multiscales` attribute so
  the group reopens as a pyramid; saver (Phase 3) will enrich it with voxel size / bbox.

Validation evidence: 3-level pyramid round-trips per level; `getRegion` sub-blocks match
MATLAB slicing; writable blockedImage written block-by-block reopens from disk identical
to source. `mcp__matlab__check_matlab_code` clean. Temp spike folders cleaned up.

**Next: Phase 1** — `core.MibBigDataImage` + wire `MibDataset.initialize` / `switchDatasetMode`.

### Phase 1 — DONE (2026-06-14)

Browse-only BigData open path wired and verified. BigData image reads are **byte-identical
to Virtual** (proven), because the reader is inherited verbatim.

Changes:
- **New** `mib/+core/@MibBigDataImage/MibBigDataImage.m` — thin subclass of
  `core.MibVirtualImage`; constructor sets `type='bigdata'`. Inherits the full zarr/virtual
  read path (`getData`→`getDataZarr`/`getDataVirt`, `getOrCreateLoader`,
  `closeVirtualDataset`). `isa(img,'core.MibVirtualImage')` stays true, so existing
  reader-cleanup paths work with no change.
- `mib/+core/@MibImage/MibImage.m` — added `case 'core.MibBigDataImage' -> 'bigdata'` to
  the constructor type switch.
- `mib/+core/@MibDataset/initialize.m` — BigData branch now builds a `MibBigDataImage` +
  placeholder empty `MibLabels63` (was `error('not implemented')`). Close guard widened
  from `=='V'` to `any(...==['V' 'B'])`.
- `mib/+core/@MibDataset/switchDatasetMode.m` — case 1 close guard widened to `['V' 'B']`;
  case 3 sets `enableSelection=false` (browse-only until Phase 2 model creation).
- `mib/+controllers/@MibActiveDataset/datasetTypeChange_Callback.m` — BigData dropdown now
  loads a blank placeholder (mirrors Virtual) instead of doing nothing.

Verification (MCP): built a native 3-level zarr pyramid; `MibDataset.initialize(...,'BigData')`
→ `getData2D` slice equals ground truth and equals the Virtual-mode read; `magFactor=4`
selects the coarse level; BigData↔Standard mode switches work and release readers.
All five changed files clean under `check_matlab_code`.

**Caveat / follow-up:** the controlled test used a MIB-native (MATLAB-order, `axisOrder='yxz'`)
pyramid driven through the identical `getDataZarr`/`Zarr3VirtualLoader` code an external
dataset uses. A File→Open smoke test on a real **external** OME-Zarr (C-order `tczyx`) is
still pending a sample file — the registry/`LoaderFactory`/`Zarr3VirtualSetupLoader` open
path is unchanged from Virtual (which already handles external OME-Zarr), so risk is low.
Orientation 1/2 reads are inherited verbatim (only orient 3 was spot-checked).

**Bugfix (pre-existing, found during Phase 1 testing):**
`mib/+core/@MibVirtualImage/getOrCreateLoader.m` line 31 read `obj.data{fileIdx}` — a stale
reference left over from the `obj.data{}` → `obj.filePaths{}` refactor (the `zarr3` branch
already used `obj.filePaths{1}`; HDF5/BioFormats branch was missed). Since `obj.data` is now
a numeric array, every Virtual HDF5/BioFormats read threw "Brace indexing is not supported
for variables of type double" (triggered e.g. by switching Standard→Virtual). Changed to
`obj.filePaths{fileIdx}`. Verified: Standard→Virtual placeholder (`default.h5`
`/im_browser_dummy`, 512×512) now reads correctly. Affects BigData too (inherited method).

**Bugfix (Phase 1 follow-up — BigData interaction handlers):**
Reported symptom: after opening a zarr3 as BigData, pan/zoom interaction misbehaved
("mouse release not working"). Root cause: several mouse/keyboard browse handlers branch on
`datasetType(1)=='V'` and BigData (`'B'`) wrongly fell into the **Standard** path. The worst
offender was `gui_WinMouseMotionFcn`, which indexed `dataset.image.data(y,x,...)` for the
pixel readout — but BigData (like Virtual) has an empty `image.data`, so it threw
"Index ... exceeds array bounds" on *every* mouse move (swallowed by the handler's `catch`),
and `updateGuiWidgets` left the brush cursor enabled in browse mode. Fixed all browse/interaction
handlers to treat BigData like Virtual:
- `@MibImageDocument/gui_WinMouseMotionFcn.m` (readout → use rendered `Iraw`, not `image.data`)
- `@MibController/updateGuiWidgets.m` (hide brush cursor)
- `@MibImageDocument/sliderDragCallback.m` (zarr debounce)
- `@MibImageDocument/updateBrushCursor.m` (don't show cursor)
- `@MibController/gui_WindowKeyPressFcn.m` (disable orientation-switch keys, x3)

Pattern used everywhere: `datasetType(1)=='V'` → `any(datasetType(1)==['V' 'B'])`. Verified on
the live app: `gui_WinMouseMotionFcn` no longer throws (pixel label updates to coordinates).
Data/pan read paths (full + block-mode + zoomed-in padded) all confirmed working for BigData.
NOTE: when Phase 2 enables BigData segmentation, the brush-cursor suppression in
`updateGuiWidgets`/`updateBrushCursor` will need to be revisited (BigData will then want a cursor).
Also pending: an audit of the many processing-tool `datasetType,'Virtual'` guards (DisplayAdjust,
Alignment, MorphOps, etc.) for whether BigData should share each guard — defer to Phase 2.

**Next: Phase 2** — disk-backed pyramidal 63-class model (`core.MibBigDataLabels` over
`io.adapters.ZarrBlockedAdapter`), create-on-demand, cross-level propagation.
