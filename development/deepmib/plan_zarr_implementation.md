# DeepMIB: prediction from OME-Zarr pyramids, output to a BigData model store

> **Status:** phase 1 implemented 2026-10-23, uncommitted. The pieces were checked through the
> MATLAB MCP on synthetic stores (see "Implementation notes" at the end). A full prediction run
> in the GUI has not been done yet, and the settings button is still to be added in App Designer.

## Context

DeepMIB predicts only from files that `imageDatastore` can list (TIF, AM, ...). Large EM/WSI
volumes now live as OME-Zarr pyramids (v2 or v3, opened as BigData), so a user has to export a
level to TIF first, predict, and then convert the result back. The goal is to:

1. take a zarr store directly as a prediction input, at a chosen pyramid level;
2. write the result either in the existing formats (at that level's resolution) or as a
   **BigData model store** that opens as an editable model on the image in BigData mode;
3. write that store where it is used (next to the image by default, confirmed by the user),
   so nothing has to be copied out of `PredictionImages/ResultsModels`.

Decisions made with the user:
- zarr3 output = a `core.MibBigDataLabels` store that mirrors the image pyramid (not a
  standalone label pyramid);
- phase 1 loads the selected level whole into RAM (with a memory check up front); Z-slab
  streaming is a later phase.

Scope of phase 1: the **Blocked-image** prediction mode, workflows 2D / 2.5D / 3D Semantic
(and 2D Patch-wise for input only). Legacy mode, 2D Instance, preprocessing and training stay
TIF-only and refuse ZARR with a clear message.

## What already exists (reuse, don't rewrite)

| Need | Existing code |
|------|---------------|
| v2/v3 detection for a plain `.zarr` folder | `io.ExtensionRegistryLoad.resolveLoader` -> `detectZarrFormatExtension` (`+io/ExtensionRegistryLoad.m:117,482`). `Standard.Default` already accepts `zarr2`/`zarr3` |
| Load one level without the level dialog | `options.ZarrLevel` (1-based) in `Zarr3VirtualSetupLoader.loadImagesStandard` / `Zarr2VirtualSetupLoader.loadImagesStandardV2`, via `OmeZarrMetadataUtils.resolveLevelOption`. **An out-of-range level is ignored and the dialog opens** -> must validate before the loop |
| Read a file through the registry | `io.loadImagesWrapper(fn, opts)` -> returns `[y x z c t]`; `deepmib.storeLoadImages` already forwards to it, so `ZarrLevel` passes straight through |
| Pyramid metadata without pixels | `loader.loadMetadata({path}, opts)` -> `files.nLevels`, `.levelImageSizes`, `.levelScaleFactors`, `.chunkSizes`, `.axisOrder`, `.imgClass`, `.color` |
| Model store mirroring the image pyramid | `core.MibBigDataLabels.createStore(dims, storePath, pyramid, zarrFormat)`; `setLayout('uint16')` for > 63 classes |
| Write one level + coarser levels | `writePackedLevel(L, block, Yl, Xl, Zl)`, `propagateRegion(block, fullY, fullX, fullZ, L, 'coarser')` (strip-wise, memory-bounded) |
| Leave finer levels to the level map | `markTiles(fullY, fullX, fullZ, L)` + `saveLevelMap()`; finer levels are rebuilt on read (`materializeForRead`) or by **Finalize & save** in MIB (`bigdata_logic.md` §5, §9) |
| Material names/colours in the store | set `materialNames`/`materialColors`, then `writeMaterialMetadata()` |

## Changes

### 1. Input extension `ZARR` - `MibDeep.m`, `bioformatsCallback.m`

- Prediction list (`ImageFilenameExtension{2}`, non-BioFormats branch): replace the
  `ZARR2`/`ZARR3` entries that come from `Standard.Default` with a single `ZARR`. It matches
  folders `*.zarr`, `*.zarr2`, `*.zarr3` (`*.ome.zarr` included), and `resolveLoader` picks the
  reader per store. The two places that build this list are the constructor
  (`MibDeep.m:436`) and `bioformatsCallback.m:31`; both get the same one-line edit.
- Training list (`ImageFilenameExtensionTraining{2}`): drop `ZARR2`/`ZARR3`, because they are
  listed today but cannot work (zarr stores are folders). Preferences store one
  `ImageFilenameExtension` for both lists, so the constructor checks membership the way
  `bioformatsCallback` already does and falls back to the first item.
- `bioformatsCallback`: when the prediction extension is `ZARR`, untick and disable the
  `Bioformats` checkbox (zarr is not read through BioFormats).

### 2. `BioformatsIndex` becomes the level - `bioformatsCallback.m`, `updateBatchOptFromGUI.m`

- At the end of `bioformatsCallback` (prediction branch): if the extension is `ZARR`, set
  `IndexEditField_2Label.Text = 'Level'` and the tooltip of `BioformatsIndex` to say
  "pyramid level, 1 = full resolution"; otherwise restore `'Index'` and the original tooltip.
  `bioformatsCallback` already runs on window open (`updateWidgets`) and on a checkbox change,
  so the label also stays right after `loadConfig`.
- `updateBatchOptFromGUI`: add `case 'ImageFilenameExtension'` -> `obj.bioformatsCallback(event)`.
- Update `mibBatchTooltip.BioformatsIndex`: "...or pyramid level (1 = full resolution) for
  ZARR".

### 3. Zarr input in `startPredictionBlockedImage.m`

- **Guard** right after the workflow detection: when the extension is `ZARR`, refuse if
  preprocessing for prediction was requested (`preprocessedSwitch`) or if the workflow is
  `2D Instance`. Also refuse in `startPrediction2D/3D` (Legacy), `startPredictionInstances`
  and `processImages`, with one `inputUniversalDlg` message each.
- **File list**: `imageDatastore` cannot list folders. For `ZARR`, build the list with `dir`
  over the three patterns (folders only), then:
  ```matlab
  imgDS = transform(arrayDatastore(zarrList(:), 'OutputType', 'same'), ...
      @(c) deepmib.storeLoadImages(c{1}, mibDeepStoreLoadImagesOpt));
  ```
  so the `while hasdata(imgDS)` / `read(imgDS)` loop stays as it is. Add `predictionFiles`
  (`= imgDS.Files` for the existing paths, `= zarrList` for zarr) and replace the
  `imgDS.Files{id}` and `numel(imgDS.Files)` uses with it. Strip a trailing `.ome` from the
  stem (`regexprep(fn, '\.ome$', '')`).
- `mibDeepStoreLoadImagesOpt.ZarrLevel = obj.BatchOpt.BioformatsIndex{1}` for zarr. In
  `deepmib.storeLoadImages`, document the `ZarrLevel` field in the docblock (no code change:
  it already forwards the options struct).
- **Pre-flight**, before the network is loaded and before anything is deleted: for each store,
  call `loadMetadata` through `extReg.resolveLoader(path, 'Standard', 'Default')` +
  `io.LoaderFactory.create`. Then:
  - refuse when `level > files.nLevels`, naming the store and its level count (otherwise the
    loader opens a dialog inside the datastore read);
  - refuse non-integer `files.imgClass` (the Standard loader shows a dialog that needs a
    `ParentFigure` that `storeLoadImages` does not pass);
  - estimate memory: `prod(levelImageSizes(L,:)) * colors * bytes * 4` (volume, blocked copy,
    labels, scores). If it exceeds `memory().MaxPossibleArrayBytes` (Windows; skip elsewhere),
    show `uiconfirm` with Continue/Cancel, giving the level size and a suggested coarser level.
  - keep `files` per store: the zarr3 output (step 4) needs the pyramid.

### 4. Output `Zarr3 (BigData model)` - `startPredictionBlockedImage.m`

- `P_ModelFiles{2}` gets a 4th item `'Zarr3 (BigData model)'` (MibDeep.m:461), enabled only
  when the extension is `ZARR` and the workflow is 2D/2.5D/3D Semantic. Otherwise it is refused
  at start with a message. `loadConfig` takes only `{1}` from a saved config
  (`updateBatchOptCombineFields_Shared`), so old configs keep the new list.
- Standard formats with zarr input (request 4) need **no extra code**: the loop already writes
  `Labels_<stem>.model/.tif` from `outputLabels`, which is at the level's resolution.
- New `case 'Zarr3 (BigData model)'` in the save `switch` (`startPredictionBlockedImage.m:550`),
  written inline:
  ```matlab
  labelsStore = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
  if numel(modelMaterialNames) > 63; labelsStore.setLayout('uint16'); end
  labelsStore.createStore(levelSizes(1,:), storePath, pyramid);   % pyramid from step 3 files
  L = obj.BatchOpt.BioformatsIndex{1};
  lv = levelSizes(L,:);  full = levelSizes(1,:);
  labelsStore.writePackedLevel(L, outputLabels, [1 lv(1)], [1 lv(2)], [1 lv(3)]);
  labelsStore.propagateRegion(outputLabels, [1 full(1)], [1 full(2)], [1 full(3)], L, 'coarser');
  labelsStore.markTiles([1 full(1)], [1 full(2)], [1 full(3)], L);
  labelsStore.materialNames = modelMaterialNames; labelsStore.materialColors = ...;
  labelsStore.maxIndexUsed = numel(modelMaterialNames);
  labelsStore.writeMaterialMetadata(); labelsStore.saveLevelMap(); labelsStore.closeStore();
  ```
  `pyramid` is built from that store's `files` (`levelImageSizes`, `levelScaleFactors`,
  `chunkSizes`, `axisOrder`), so the store's level shapes match exactly what the BigData
  image reader shows. When `L == 1` the `markTiles` call is still correct (level 1 =
  materialized). Check the exact property names (`materialNames`, `maxIndexUsed`) against
  `core.MibLabels63` before writing.
- **Cancel**: check `pwb.CancelRequested` before `createStore`, which deletes an existing folder
  with `rmdir`. On a cancel or error after `createStore`, close the store and remove that
  partial store. At the end, list which stores were written and which were not.
- **ResultsModels cleanup**: the existing "folder not empty -> `delete(...*)`" only counts and
  removes files. Zarr stores written there are folders, so the count and the delete need to
  include `*.zarr2`/`*.zarr3` folders (`rmdir(..., 's')`).

### 5. Confirm the output location - `startPredictionBlockedImage.m`

When the output is `Zarr3 (BigData model)`, after the pre-flight and before the network loads:
- default destination = **next to each source store**, as `Labels_<stem>.zarr3` (or `.zarr2`).
  That is the name BigData uses for a new model (`bigdata_logic.md` §4), so the user loads it
  with no copying;
- `uiconfirm` names the destination (the folder, or "next to each image" for several files):
  **Write here** / **Choose folder...** (`uigetdir`) / **Cancel**;
- then list the destinations that already exist and ask once to overwrite them all, or cancel.
  This is required because `createStore` silently `rmdir`s an existing folder.

### 6. Settings button - `updateModelOutputSettings.m` (new method)

The user adds the button (`P_ModelFilesSettings`, next to `P_ModelFiles`) in App Designer
later. The controller side:
- new property `ZarrModelOpt` in `MibDeep.m`, initialised from
  `preferences.Deep.ZarrModelOpt` with the `isfield` fallback used for `OverlapInstancesOpt`:
  `.ZarrFormat = 'v3'` (`'v3'|'v2'`, which picks the `.zarr3`/`.zarr2` extension and the format
  passed to `createStore`) and `.Location = 'Next to images'` (`'Next to images'|'ResultsModels'`,
  the default offered in step 5);
- `updateModelOutputSettings.m`: one `utils.dlgs.inputUniversalDlg` with these two dropdowns,
  modelled on `updateScoreExportSettings.m`. There is no chunk/shard/levels/compression: the
  store mirrors the image pyramid, and `createStore` takes no compression option;
- declare it in the methods block of `MibDeep.m`; persist it in `closeWindow.m`,
  `saveConfig.m`/`loadConfig.m` (`utils.concatenateStructures`, as for `ScoreExportOpt`) and
  `importNetwork.m`; add a default to `+utils/+defaults/generatePreferences.m`.

### 7. Preview / evaluate

- `previewModels.m`: add a `'Zarr3 (BigData model)'` case. Phase 1 shows a message: open the
  image in BigData mode, then Model -> Load model and pick `Labels_<stem>.zarr3`. Opening both
  automatically needs `MibModel.loadImages` to accept a dataset mode and a model store; check
  that during implementation and do it only if it is a small change.
- `evaluateSegmentation.m`: for the new item, show "not available for BigData model output".
  Also, `dir('*.zarr')` for images already lists folders, so the image side of the preview is
  fine for the standard formats.

### 8. Documentation

- `docs/docs/deepmib/deepmib-predict.md`: ZARR input + Level, the new Model files item, where
  the store goes and how to open it (BigData mode, Load model; use **Finalize & save** before
  exporting). Short, behaviour only.
- `docs/docs/deepmib/deepmib-options.md` (or the directories page, wherever the extension/
  Index widgets are described): `ZARR` + `Level`.
- Docblocks: `startPredictionBlockedImage` (zarr path, pre-flight, store writing and level-map
  semantics), `updateModelOutputSettings`, `storeLoadImages` (`ZarrLevel`). Add the new method
  to `docs_api/source/api/controllers/MibDeep.rst`.
- `development/deepmib/plan_zarr_implementation.md`: this plan, plus a "Phase 2" section.
- Run the em-dash grep from CLAUDE.md on every touched `.m` file.

### Phase 2 (not now): Z-slab streaming

Read slabs of level L through `loader.readRegion` (2D/2.5D: per Z slab with
`floor(depth/2)` context; 3D: slabs with a Z halo = the network's Z border). Each slab goes
through `processBlocksBlockedImage`, then `writePackedLevel` + `propagateRegion` + `markTiles`
for that slab only. This removes the RAM limit for zarr3 output. XY-giant single slices would
still need an XY-tiled reader (a read-only `images.blocked.Adapter` over `readRegion`).

## Critical files

- `mib/+controllers/@MibDeep/`: `MibDeep.m`, `bioformatsCallback.m`, `updateBatchOptFromGUI.m`,
  `startPredictionBlockedImage.m`, `updateModelOutputSettings.m` (new), `previewModels.m`,
  `evaluateSegmentation.m`, `closeWindow.m`, `saveConfig.m`, `loadConfig.m`,
  `importNetwork.m`, guards in `startPrediction2D.m`, `startPrediction3D.m`,
  `startPredictionInstances.m`, `processImages.m`
- `mib/+deepmib/storeLoadImages.m` (docblock only)
- `mib/+utils/+defaults/generatePreferences.m`
- read-only reuse: `+core/@MibBigDataLabels/MibBigDataLabels.m`,
  `+io/+loaders/Zarr{2,3}VirtualSetupLoader.m`, `+io/ExtensionRegistryLoad.m`

## Verification

Through the MATLAB MCP, as function files (not base-workspace scripts). First check the open
MIB session's active buffer, per memory.
1. **Synthetic input**: write a 3-level zarr3 with `io.savers.Zarr3Saver().save(vol, meta,
   'x.zarr3', struct('Levels',3))`, and a v2 copy saved under a plain `.zarr` name, so the
   auto-detection path is exercised.
2. **Network**: use a small 2D Semantic network the user provides (or train a tiny one on
   synthetic data).
3. **Standard output**: predict at level 2 -> `Labels_x.model` has the level-2 size, the same
   as `loadImagesWrapper(path, struct('ZarrLevel',2))`.
4. **Zarr3 output**: predict at level 2 -> open the store with `core.MibBigDataLabels.openStore`;
   check `modelLevelSizes` against the image pyramid, that level 2 equals the prediction, that
   coarser levels are non-empty, that `matLevel` is all 2, and that reading level 1 via
   `getData63` gives the nearest/smoothed upsample. Material names come back from `mibMaterials`.
5. **Guards**: a level greater than nLevels, a float store, Legacy mode, 2D Instance, and
   preprocessing each give a message, with no dialog left hanging and nothing deleted.
6. **Cancel** during prediction removes the partial store, and an existing store is never
   overwritten without confirmation.
7. **Live GUI (manual, the user's)**: the Index -> Level label switch, the Bioformats checkbox
   disabling, the location dialog, and opening the image in BigData mode + Load model ->
   editable, correct at all zoom levels; Finalize & save.
8. `buildtool check` on the touched files; the em-dash grep returns nothing.

## Implementation notes (2026-10-23)

Where the code differs from the plan above:

- **Store write uses the public `setData63`**, not `writePackedLevel` + `propagateRegion` +
  `markTiles`: `propagateRegion` and `regionForLevel` are private methods of
  `core.MibBigDataLabels`. The call is
  `labelsStore.setData63(outputLabels, 'everything', 3, [], struct('pyramidLevel', L))`. With no
  `x/y/z` the region defaults to the whole level, `'everything'` is written exactly (never
  smoothed), and `setData63` itself propagates to the coarser levels, marks the level map and
  raises `maxIndexUsed`. Background tiles stay `matLevel = 0` (empty), which is correct.
- **Guards are consolidated in `start.m`** (PredictButton case): ZARR input + 2D Instance,
  ZARR input + Legacy engine, Zarr3 output without ZARR input, Zarr3 output with a
  non-semantic workflow. `startPreprocessing.m` refuses preprocessing for prediction of ZARR
  images, and `startPredictionBlockedImage` refuses a ZARR run in a preprocessed mode. Nothing
  was added to `startPrediction2D/3D`, `startPredictionInstances` or `processImages`, because
  the `start.m` guard covers them.
- **Shared methods**: `checkZarrStores`, `selectModelStoreDestination` and `writeModelStore` are
  `@MibDeep` methods (own files), because both `startPredictionBlockedImage` and
  `startPredictionInstances` call them.
- **Model stores are skipped as inputs**: when listing the images, stores with the
  `mibModelStore` attribute are left out, so a second run does not predict on the
  `Labels_*.zarr3` written next to the images by the first run.
- **Nested images in a zarr container**: the check resolves the image group once (the picker
  may appear then). Each store's read then gets `ZarrGroupPath`, so the picker does not open
  again inside the datastore.
- **`importNetwork` is not changed**: `ZarrModelOpt` is an output preference, not a network
  parameter. It is kept in preferences (`closeWindow`, `generatePreferences`) and in configs
  (`saveConfig`/`loadConfig`).
- **`previewModels`** shows how to open the result (BigData mode + Load model) instead of
  loading it. **`evaluateSegmentation`** says it is not available for this output.
- **ResultsModels cleanup** now also removes `*.zarr`/`*.zarr2`/`*.zarr3` folders.
- **The "Zarr3 (BigData model)" item is always in the list**: it is not disabled in the
  dropdown, and `start.m` refuses it with a message when it does not apply.

Checked through the MCP (scratch functions, synthetic data):

- `deepmib.storeLoadImages(path, struct('ZarrLevel', 2))` reads level 2 of a v3 store, a v3
  store named `*.zarr`, and a v2 store named `*.ome.zarr`.
- The store list finds the three image stores and skips the `Labels_*.zarr3` model store; the
  pyramid sizes are right for each.
- The store write on a 3-level 600x500x4 image predicted at level 2: the reopened store has the
  image's level sizes, level 2 equals the prediction exactly, level 3 is filled, `matLevel` is
  all 2, material names come back, and a level-1 read rebuilds 600x500 with 100% agreement with
  nearest-neighbour upsampling.

### 2D Instance (added 2026-10-23, same day)

- `startPredictionInstances` reads ZARR images at the selected level (same check, the same
  `arrayDatastore` + `ZarrGroupPath` read as the Blocked-image path). With "MIB Model format"
  the `.model` file has the size of the predicted level.
- "Zarr3 (BigData model)" writes a **uint16 instance store** through `writeModelStore` with
  `materialNames = {}`: layout `setLayout('uint16')`, names `{'1';'2'}`, generated colours,
  `objects3D = false` (the prediction numbers objects 1..N per slice). More than 16383 objects
  in one slice is refused before the store is created.
- **Limitation:** "Merge 2D to 3D" (`mergeInstancesTo3D`) reads only `.model` files, so the
  slices of a z-stack zarr store stay unlinked. A follow-up could run
  `utils.instances.stitch2Dto3D` on the level in memory before writing, and set
  `objects3D = true`. The 16383 cap then applies to the whole stack.
- `start.m` no longer refuses ZARR input for 2D Instance (its own engine ignores the
  Blocked-image/Legacy choice), and it allows the Zarr3 output for 2D Instance.
- Checked through the MCP with a scratch copy of `writeModelStore`: an instance store with
  indices up to 399 reopens as uint16 / `maxMaterials` 16383 / `objects3D` 0, with level 2 exact;
  20000 objects and a size mismatch are refused and leave no store; a semantic v2 store
  round-trips.

Still to do: a full GUI run with a real network (2D, 2.5D and 3D; standard and Zarr3 output;
Cancel; overwrite prompt; memory warning), the settings button `P_ModelFilesSettings` ->
`obj.updateModelOutputSettings()` in App Designer, and opening the result in BigData mode with
Finalize & save.

### Settings dialog extended (2026-10-23)

`updateModelOutputSettings` now offers every zarr setting a model store can honour, stored in
`obj.ZarrModelOpt` (defaults in the constructor and `generatePreferences`):

- `.ZarrFormat` v3/v2;
- `.Location`: `Next to images` / `ResultsModels` / **`Ask`**. Ask opens `uigetdir` at
  Predict instead of the confirmation dialog;
- `.Levels` (0 = as the image). Fewer levels drop the coarsest ones, and
  `selectModelStoreDestination` refuses the run before it starts if the predicted level would
  be dropped;
- `.ChunkSize` `[y x z]` (0s = the image chunks), placed in the pyramid's axis order for
  `createStore`;
- `.Compressors` + `.CompressionLevel`, in the form `Zarr3Saver.optionsDialog` returns, set on
  `labelsStore.Compressors` before `createStore`.

Not offered, with the reason in the dialog header:
- **Downsampling strategy:** level shapes must be the image's.
- **Downsampling method:** `setData63` propagates with nearest-neighbour. 'mode' would need
  `Zarr3Saver.blockReduce2D/3D`, which are private.
- ~~Sharding~~: added on request, see below.

Checked with a scratch copy of `writeModelStore`, in v3 and v2:
- the defaults give 3 levels with the image chunks and zstd 3;
- `Levels 2` gives 2 levels; chunk `[64 64 2]` and `[100 80 1]` are applied;
- gzip with level 12 is written as gzip 9, and `none` gives no compressor;
- level 2 was exact in every case.

### Sharding (2026-10-23)

- `core.MibBigDataLabels` gained a public property **`ShardFactors`** (chunks per shard
  `[y x z]`, `[]` = off), used by `createStore` for zarr v3 through
  `io.savers.Zarr3Saver.computeShard`. It is ignored for v2, which has no sharding codec. MIB's
  own New model path leaves it off.
- `ZarrModelOpt.ShardSize` (`[0 0 0]` = off, all > 0 to enable, the same rule as the standard
  zarr export dialog) is set as **Shard X-factors** in `updateModelOutputSettings`. The dialog
  refuses v2 combined with shards.
- The trade-off is stated in the dialog header: fewer files for a large store, slower editing
  later (a partial-shard write rewrites the shard, measured 3.4x).
- Checked: chunk `[64 64 1]` + shards `[2 2 2]` gives v3 shard `[128 128 2]`. Level 2 is exact,
  and a 10x10 edit at level 1 writes and reads back. The same settings on v2 give an
  unsharded store.
- **This edits the `MibBigDataLabels` classdef**: in a MATLAB session where MIB was running,
  restart MATLAB before using brush/edit tools (see memory note on classdef edits).

### Default compression level (2026-10-23)

`ZarrModelOpt.CompressionLevel` defaults to **7** (zstd). The "0 = codec default" choice was
removed: the spinner is 1-22, and a 0 saved earlier becomes 7 in the constructor and in
`writeModelStore`. Measured with `ZarrArray` (zarrMex, R2026a, this workstation, chunk
256x256x16) on synthetic labels of 2048x2048x16: semantic = 4 classes from a smoothed random
field; instance = per-slice watershed regions, uint16.

| codec | semantic uint8 (raw 67.1 MB) | write | instance uint16 (raw 134.2 MB) | write |
|-------|------------------------------|-------|--------------------------------|-------|
| zstd 1  | 3.31 MB | 0.28 s | 6.48 MB | 0.30 s |
| zstd 3  | 3.54 MB | 0.26 s | 6.99 MB | 0.29 s |
| zstd 5  | 3.11 MB | 0.27 s | 6.34 MB | 0.32 s |
| zstd 7  | 2.68 MB | 0.28 s | 6.01 MB | 0.33 s |
| zstd 9  | 2.63 MB | 0.30 s | 5.79 MB | 0.35 s |
| zstd 15 | 2.40 MB | 0.47 s | 5.75 MB | 0.57 s |
| gzip 5  | 2.92 MB | 0.28 s | 6.40 MB | 0.33 s |
| gzip 9  | 2.33 MB | 0.37 s | 6.07 MB | 0.46 s |

Reads were 0.15-0.24 s at every level. zstd 7 is the knee: 15-25% smaller than zstd 3 for
5-15% more write time. Level 9 adds 2-4%, and level 15 nearly doubles the write time.
Synthetic data; real predictions with finer boundaries will compress less, but the ranking
should hold.

### Mode downsampling, finished-dialog icon (2026-10-23)

- `ZarrModelOpt.DownsampleMethod`: `'nearest'` (default) or `'mode'`, with the same dropdown
  items as `Zarr3Saver.optionsDialog` for models. With `'mode'`, `writeModelStore` overwrites the
  coarser levels that `setData63` wrote by nearest-neighbour:
  - each coarser level is a majority vote over blocks of the predicted level, computed directly
    from that level rather than cascaded;
  - the predicted level is cropped or padded (replicate) to whole blocks first, so
    `blockReduce2D`/`3D` stay on their vectorised path;
  - `blockReduce2D` reduces each slice on its own; `blockReduce3D` handles levels that also
    halve Z.
  The method applies only at prediction. Later edits in MIB still propagate with nearest.
- `Zarr3Saver.blockReduce2D/blockReduce3D` were moved, unchanged, from
  `methods (Static, Access = private)` to `methods (Static, Hidden)`, so `writeModelStore` can
  call them. The file's sorted lines are identical to HEAD.
- Checked: 601x499x8, isotropic voxels, "Anisotropy-preserving" pyramid (levels
  301x250x4, 151x125x2; the 3D path with odd sizes). Mode output equals an independent
  per-block mode on 100% of pixels at both levels; nearest agrees on about 67%. Write took
  0.20 s for mode against 0.11 s for nearest. A single-slice uint16 instance model (6300 10x10
  objects) keeps all 6300 objects at level 3 (1/4 scale).
- The "Prediction finished" message (both prediction methods) now uses `Icon = 'puffin_info'`.
  A message-only `inputUniversalDlg` defaults to `puffin_error`.
- Found while testing, **fixed** (see below): `io.savers.Zarr3Saver.save` failed on a plain 2D
  `[y x]` array ("array subset [0..700, 0..900] is not compatible with array shape
  [700, 900, 1]", line 297, `arr.write(lvl)`). The array is declared `[Y X 1]`, but MATLAB drops
  the trailing singleton of `lvl`.

### Zarr3Saver.save on a single 2D slice (fixed 2026-10-23)

`save` declares each level as `[Y X 1]` (plus c/t when > 1). For one slice, MATLAB's
`reshape(lvl, keepShape)` drops the trailing singleton, and `arr.write(lvl)` without a region
was refused by zarrMex. The fix: when `ndims(lvl) < numel(keepShape)`, write through the
explicit full-array region `[ones(n,1), keepShape(:)+1]`, the same way `writePackedLevel`
writes 2D blocks into `[Y X 1]` arrays. Other shapes keep the unchanged `arr.write(lvl)` call.
The streaming writers already write through regions and were not affected.

Regression test: `Zarr3SaverTest/save_singleSlice2D_roundTrips` covers a grayscale slice
(interpolating path), a label slice with 'mode' (block-reduction path, which is also the first
test of the moved `blockReduce2D`) and an RGB slice (`[Y X 1 3]`, singleton in the middle, which
worked before). It checks that level 0 round-trips and level 2 is 1/4 size. The whole
`Zarr3SaverTest` passes (11/11).

### Preview of zarr predictions (2026-10-23)

`previewModels` now handles ZARR images in a local function, `previewZarrPrediction`:

- **One image at a time.** Images are listed the same way as `checkZarrStores` does: zarr
  folders, with MIB model stores skipped. Only images with a model are offered, through a
  dropdown when there are several.
- **"Zarr3 (BigData model)" output:** the active buffer is switched to BigData, using the same
  steps as `SelectFromUrl.ensureDatasetMode` (placeholder `default.h5`, and the
  `Sets.datasetTypes` cache updated). Then the image is loaded and the store is attached with
  `loadModel` (`Filenames = {storePath}`).
  - The stores are looked for in `obj.sessionSettings.lastModelStoreFolder`, which
    `selectModelStoreDestination` sets, so the "Ask" destination works.
  - If that is not set, they are looked for where `ZarrModelOpt.Location` puts them.
  - If no store is found, the user is asked for a folder.
- **MIB/TIF output:** the buffer is switched to Standard and the image is loaded with
  `ZarrLevel` set to the predicted level, so it matches `Labels_<name>.model/.tif`.
- **"Load models" only:** loads the model of the open image, matched by name. The open dataset
  must already be in the matching mode.
- The active dataset comes from `getActiveId()`. **Not fixed, noticed in passing:** line 13
  of `updateWidgets.m` uses `obj.mibModel.Id`, which does not exist (`MibModel.id`). It only
  runs when `BatchOpt` has an `id` field, which MibDeep never sets.
- Not run in the GUI yet: Preview loads into the user's active buffer, so the first run is the
  user's.
