# Alignment for BigData mode — implementation plan

Status: **planned, not started** (2026-07-03). Decisions confirmed with IB; codebase facts verified against source (file:line cited throughout).

## 1. Context

Alignment (`mib/+controllers/@Alignment`) is hard-blocked for BigData datasets at `Alignment.m:134-144`
(`if any(dataset.datasetType(1) == ['V' 'B'])` → warning dialog + `StopProtocol`).

BigData = disk-backed pyramidal OME-Zarr v3 image + packed-63 labels pyramid:

- **Image** — `core.MibBigDataImage` (< `MibVirtualImage`), **read-only**; reads via `getDataZarr`
  (`getDataZarr.m:58-68`: `options.pyramidLevel` 1-based, 1 = finest, overrides `magFactor`;
  `levelScaleFactors(levelIdx,:) = [sfY sfX sfZ]`). Source pixels are never edited; canvas size is
  fixed at store creation (zarr3 arrays pre-allocated, no resize machinery exists anywhere).
- **Labels/mask/selection** — all three live in one packed-63 uint8 pyramid managed by
  `core.MibBigDataLabels` (`Labels_<stem>.zarr3`): bits 1–6 material, bit 7 mask, bit 8 selection.
  Read/write via `getData63`/`setData63` (both accept `options.pyramidLevel` + `.x/.y/.z`,
  `getData63.m:46-58`, `setData63.m:51`; layer `'everything'` moves raw packed bytes). Edits write
  the working level + propagate to coarser levels; finer levels are tracked dirty in the per-tile
  level map `matLevel` and materialized lazily (`materializeForRead`); persisted via
  `materializeAll()` / `saveLevelMap()` to the `.levelmap` sidecar.

Because the image is read-only and the canvas cannot grow, **BigData alignment must write a new
aligned zarr3 store** (image + labels) and then swap the active buffer to it. This is the same
pattern already proven by `MibDataset.cropToBigData` + `CropDataset.m:932-968` and by the
ImageConverter (`ImageConverter.m:713` uses `Zarr3Saver.patchMetadata`).

### Confirmed decisions (IB, 2026-07-03)

1. **Output = new aligned OME-Zarr v3 store**, never in-place. Supports both `cropped` and
   `extended` TransformationMode (extended canvas size is known after shift computation, before
   writing). Source store stays intact and acts as the backup.
2. **Scope**: Drift correction / Template matching, Automatic feature-based **v2**, Landmark modes
   (single / three / multi-point). Feature-based v1 and AMST remain blocked in BigData.
3. **Shift computation at a user-selectable pyramid level** — dropdown in the dialog (BigData
   only), default = level nearest ~3000 px wide; shifts/tforms computed at level L, scaled to
   level 0, applied at full resolution.
4. **All layers**: labels/mask/selection warped with the same transforms into a new
   `Labels_<stem>.zarr3` (nearest-neighbor on packed bytes).

## 2. Design principles

1. **Never in-place.** Every BigData alignment writes a new image `.zarr3` and, if a model exists,
   a sibling `Labels_<stem>.zarr3`, then reopens and swaps the active buffer.
   `mibModel.backup(...)` is **skipped** in all BigData paths (matches
   `alignDriftCorrectionHDD_Alignment`, which takes no backup either).
2. **Two-pass streaming.** Pass 1 reads slices at a coarse analysis pyramid level L and computes
   shifts/tforms — the existing math helpers (`utils.align.calcShifts`, `detectFeatures`,
   `estgeotform2d`, `subtractRunningAverage`, `runningAverageSmoothPoints`) are reused unchanged
   because they operate on small level-L arrays/vectors. Pass 2: a slice provider re-reads each
   **level-0** slice via `getDataZarr`, applies the scaled transform into the (possibly extended)
   output canvas, and hands it to `Zarr3Saver.saveStream`. The full-resolution stack is never
   resident in RAM.
3. **Transform scaling L → 0.** XY scale `s = levelScaleFactors(L,1)` (≈ `2^(L-1)`).
   - Translation: `shift0 = round(shiftL * s)` (rounding keeps drift shifts integer →
     resample-free placement).
   - Affine: conjugate with `S = diag([s, s, 1])`: `T0 = S * TL * inv(S)` — linear block
     unchanged, translation column ×s.
4. **Canvas known before writing.** Extended-canvas size at level 0 computed up front:
   translation → min/max growth formula of `utils.align.crossShiftStack`
   (`deltaX = abs(min(shiftsX)) + max(shiftsX)` etc., `crossShiftStack.m:62-83`);
   affine → corner projection (`AutomaticFeatureBasedV2_Alignment.m:201-220`) at level-0 dims.
   The provider's `OutputSize` is therefore final when `saveStream` starts.
5. **Reuse the math, replace only the I/O.**

## 3. Verified infrastructure to reuse

| What | Where (verified) |
|------|------------------|
| Streaming pyramid writer | `Zarr3Saver.saveStream(provider, metadata, filename, options)` — `mib/+io/+savers/Zarr3Saver.m:280`. Provider must expose `OutputSize [H W D C T]`, `DataClass`, `getSlice(z,t)->[H W C]`. Honours `options.silent`, `.ChunkSize`, `.Compressors`, `.DownsampleMethod`, `.DownsampleStrategy`, `.ShardSize`, `.layerType`, `metadata.pixSize`/`.materialNames`. Cancel via internal progress dialog + `CancelRequested` polling (`:391-398`). |
| Shared level plan | `Zarr3Saver.computeLevelPlan(Y, X, Z, pixSize, options)` — `Zarr3Saver.m:748`, public static. Use ONE plan for both output stores so image and labels pyramids share identical level sizes / scale factors / chunks. |
| Metadata patch | `Zarr3Saver.patchMetadata(zarrPath, pixSize, boundingBox)` — `Zarr3Saver.m:818`; writes `mibBoundingBox` + per-level translation/scale (ImageConverter usage at `ImageConverter.m:713`). |
| Slice provider base | `mib/+io/+savers/SliceProvider.m` — abstract handle; props `OutputSize(1,5)`, `DataClass`, `NumSlices`, `NumChannels`, `NumFrames`, `SliceSize(1,2)`; abstract `getSlice(obj,z,t)`. Concretes: `MibImageSliceProvider.m:59` (reads any MibImage subclass at a pyramid level via `getData(layerType,3,colCh,opt)` with `opt.pyramidLevel`, `opt.z`), `InMemorySliceProvider`, `ImageDatastoreSliceProvider`. |
| New labels store | `MibBigDataLabels.createStore(obj, dims, storePath, pyramid)` — `MibBigDataLabels.m:107`; `pyramid` needs `.levelImageSizes`, `.levelScaleFactors`, `.chunkSizes`, `.axisOrder`. Reopen via `openStore(obj, storePath)` — `MibBigDataLabels.m:230`. Default chunk `[256 256 16]`; Z never downsampled in the model pyramid. |
| Whole-workflow analogue | `MibDataset.cropToBigData` — reads region (`readOpts.pyramidLevel`), writes new image `.zarr3` with `Zarr3Saver().save`, derives `Labels_<stem>.zarr3` (`:115`), builds `newPyramid` from source scale factors (`:120-132`), `createStore` (`:136`), copies packed labels via `getData63('everything',...)`/`setData63('everything',...)` + `materializeAll` (`:143-149`). |
| Buffer switch-over | `CropDataset.m:932-968`: `io.loaders.Zarr3VirtualSetupLoader(lo)` → `loadMetadata`/`loadImages` → `I{id}.initialize(img, imgInfo, 'BigData')` → reattach model via `newLabels.openStore(...)` + restore material names/colors/count → `modelExist=true`, `enableSelection=true` → sync `Sets.datasetTypes` → `notify('NewDataset')`, `notify('ShowImage')`, `notify('UpdateFileList')`. |
| Dispatch insertion point | `continueBtn_Callback.m:88-130` — switches on `BatchOpt.Algorithm{1}`; existing `if obj.BatchOpt.HDD_Mode` sub-branches at `:90-95` (Drift/Template) and `:116-121` (Feature) show the exact pattern for the new `isBigData` sub-branches. |
| BatchOpt UI-only field pattern | HDD fields `Alignment.m:217-226`; widget wiring `addCallbacks:398-419` (`isfield`-guarded); dynamic dropdown refresh `updateWidgets:333-370`. |
| Alignment math helpers | `mib/+utils/+align/calcShifts.m` (FFT pairwise correlation → absolute shifts via cumsum; `options.refFrame`), `crossShiftStack.m` (canvas growth + per-slice placement), `detectFeatures.m` (SURF/SIFT/ORB/FAST/Harris/BRISK/MSER dispatcher), `subtractRunningAverage.m`, `runningAverageSmoothPoints.m`, `windv.m`. |
| In-memory references | `DriftCorrection_Alignment.m` (full-stack `getData4D` → `calcShifts` → `crossShiftStack`; bbox update `:194-211`), `AutomaticFeatureBasedV2_Alignment.m` (per-slice detect → `estgeotform2d` → cumulative tforms; corner projection `:201-220`; background resolution `:79-88`; `warpAndWriteServiceCanvas` `:781-811` — nearest-neighbor warp of packed `'everything'`; annotation warp `:764-776`; `saveV2ToFile`). HDD variants (`alignDriftCorrectionHDD_Alignment.m`, `AutomaticFeatureBasedHDDV2_Alignment.m`) are the streaming-pipeline analogue. |

## 4. Phases

Each phase is independently testable. **Recommended model per phase** is stated (Opus for novel /
correctness-critical design, Sonnet for mechanical ports, wiring, docs).

---

### Phase 0 — Groundwork: gate relaxation, UI, BatchOpt, stubs → **Sonnet**

*Mechanical UI/dispatch wiring following the existing HDD pattern; no novel logic.*

**Modify `Alignment.m`:**
- `:134-144` — keep rejecting `'V'` unconditionally. For `'B'`: do **not** reject in the
  constructor (BatchOpt is built before the algorithm is chosen); instead set new property
  `obj.isBigData = strcmp(dataset.datasetType, 'BigData')` (optional cache `obj.bigDataPyramid`)
  and defer per-algorithm rejection to the dispatcher.
- Add BatchOpt fields near `:217` (following the HDD block):
  - `BatchOpt.BigData_PyramidLevel = {'<auto>'}` — dropdown; `{2}` built dynamically in
    `updateWidgets` from `dataset.image.pyramid.levelImageSizes`
    (item format e.g. `'2: 12000 x 9000'`); default = level nearest ~3000 px wide.
  - `BatchOpt.BigData_OutputPath = '<pathstr>/<name>_aligned.zarr3'` (string field).
- Extend `defaultTooltips` with the two new fields; extend `addCallbacks` valueTags list
  (`isfield`-guarded, so a not-yet-updated `.mlapp` degrades gracefully); extend `updateWidgets`
  to populate the level list, refresh the default output path per dataset, and show/hide the
  BigData panel.

**Modify `+views/AlignmentGUI.mlapp`** (AppDesigner, user edit):
- New "BigData" panel mirroring the HDD panel: dropdown `BigData_PyramidLevel`, edit field
  `BigData_OutputPath`, browse button `BigData_SelectOutputBtn`.

**Modify `continueBtn_Callback.m`:**
- Add `parameters.isBigData`, resolve `parameters.pyramidLevel` (index parsed from dropdown) and
  `parameters.outputPath` before dispatch.
- Add `isBigData` sub-branches: Drift/Template (`:90-95`) → `DriftCorrectionBigData_Alignment`;
  Feature v2 (`:116-121`) → `AutomaticFeatureBasedV2BigData_Alignment`; Landmarks (`:97-104`) →
  `LandmarksBigData_Alignment`.
- Explicit friendly rejection dialog (mirror `:39-48`) for feature-based **v1** and **AMST** in
  BigData.

**New stub files** (signatures added to the methods list at `Alignment.m:99-111`):
- `mib/+controllers/@Alignment/DriftCorrectionBigData_Alignment.m`
- `mib/+controllers/@Alignment/AutomaticFeatureBasedV2BigData_Alignment.m`
- `mib/+controllers/@Alignment/LandmarksBigData_Alignment.m`
- `mib/+controllers/@Alignment/applyAlignmentBigData.m` (shared apply pipeline)
- `mib/+io/+savers/AlignedImageSliceProvider.m`
- `mib/+io/+savers/AlignedLabels63SliceProvider.m`

**Edge cases:** BigData placeholder/no store → dialog opens but Apply disabled; `time > 1`
already blocked (`updateWidgets:322-331`).

**Verify:** `mcp__matlab__check_matlab_code` on edited files. Live: dialog opens on a `.zarr3`
dataset, level dropdown lists all levels with ~3k default, output path prefilled,
AMST / feature-v1 Apply politely rejected.

---

### Phase 1 — Drift correction / Template matching + shared apply pipeline → **Opus**

*The novel, correctness-critical core: provider design, canvas math, packed-63 warp, dual-store
creation, buffer switch-over. Get this right once — Phases 2–3 become ports.*

**`DriftCorrectionBigData_Alignment.m`:**
1. Resolve `id`, `ds`, analysis level `L`, scale `s = levelScaleFactors(L,1)`.
2. **Pass 1 at level L**: read the level-L stack in one call
   (`ds.image.getData('image', 3, colCh, struct('pyramidLevel', L))`) when it fits in RAM,
   else per-slice via `MibImageSliceProvider`. Apply the same Subarea / IntensityGradient
   preprocessing as `DriftCorrection_Alignment.computeShifts`, then `utils.align.calcShifts`.
   Subarea coordinates (minX/maxX/minY/maxY, Selection/Mask footprints) must be divided by `s`
   for level-L reads.
3. **Preview / running-average** loop reused verbatim (`DriftCorrection_Alignment.m:60-105`) —
   operates on the small level-L shift vectors.
4. **Scale to level 0**: `shiftX0 = round(shiftXL * s)`, `shiftY0 = round(shiftYL * s)`
   (integer → resample-free placement).
5. Call `obj.applyAlignmentBigData(parameters, tformInfo)` with `mode = 'translation'`.

**`applyAlignmentBigData.m`** (shared by phases 1–3):
1. **Level-0 canvas**: translation → `crossShiftStack` min/max growth formula
   (`deltaX/deltaY` from shift extremes); affine → corner projection. Yields
   `newH0/newW0` + placement offset `(minX0, minY0)`. `cropped` mode keeps original dims.
2. **One level plan**: `plan = io.savers.Zarr3Saver.computeLevelPlan(newH0, newW0, depth, pixSize, opts)`
   so the image store (built internally by `saveStream`) and the labels store (built by
   `createStore`) share identical level sizes / scale factors. Copy `axisOrder` and chunk sizes
   from the source pyramid into `newPyramid`.
3. **Write image store**: `Zarr3Saver(struct('ParentFigure', ...)).saveStream(imgProvider, meta, outputImagePath, saverOpts)`
   with `silent=true` (own PoolWaitbar/uiprogressdlg outside), chunking copied from source,
   `meta.pixSize = ds.image.pixSize`.
4. **Write labels store** (only if `ds.labels` exists / `modelExist`): derive
   `Labels_<stem>.zarr3` from the output image path (naming per `cropToBigData.m:115`);
   `newLabels.createStore([newH0 newW0 depth], modelStorePath, newPyramid)`; per-slice loop:
   read packed `'everything'` at level 0 from source, `imwarp(..., 'nearest', 'OutputView', ref0, 'FillValues', 0)`,
   `setData63('everything', ..., struct('pyramidLevel', 1, 'z', [z z]))`; finish with
   `materializeAll()` + `saveLevelMap()` + `closeStore()` (mirrors `cropToBigData.m:143-150`).
   **Deliberately NOT via `saveStream`** — the packed pyramid must go through the
   materialize/level-map path so bit semantics and coarse levels stay correct.
5. **Metadata**: `Zarr3Saver.patchMetadata(outputImagePath, ds.image.pixSize, newBoundingBox)` —
   bounding box shifted orientation-aware exactly as `DriftCorrection_Alignment.m:194-211`
   (pixel shifts × pixSize.x/y, orientation remap XY/ZX/ZY).
6. **Switch over** per `CropDataset.m:932-968`: capture source material names/colors/count →
   `Zarr3VirtualSetupLoader.loadMetadata`/`loadImages` on the new image store →
   `I{id}.initialize(img, imgInfo, 'BigData')` → if labels store written,
   `newLabels.openStore(...)` + restore material metadata, `modelExist = true`,
   `enableSelection = true` → sync `Sets.datasetTypes` → `notify('NewDataset')`,
   `notify('ShowImage')`, `notify('UpdateFileList')`.
7. Action-log entry + optional `SaveShiftsToFile` (reuse existing code paths).

**`AlignedImageSliceProvider < SliceProvider`:**
- Props: source `MibBigDataImage` handle, per-slice level-0 tform array, `OutputView`
  (`imref2d([newH0 newW0], xWorldLimits, yWorldLimits)`), background fill, colCh list.
- `OutputSize = [newH0 newW0 depth C 1]`; `getSlice(z, t)` reads the level-0 source slice via
  `getData('image', 3, [], struct('pyramidLevel', 1, 'z', [z z]))`, then
  `imwarp(slice, tform0{z}, 'cubic', 'OutputView', ref0, 'FillValues', bg)`.
  Translation is expressed as an affine `transltform2d`/`affinetform2d` so ONE code path serves
  both modes. Background resolved as in `AutomaticFeatureBasedV2_Alignment.m:79-88`
  (White/Black/Mean/Custom).

**`AlignedLabels63SliceProvider`** (or inline loop in `applyAlignmentBigData` — decide during
implementation; inline is simpler since labels writing doesn't go through `saveStream`):
- Reads packed `'everything'` at level 0, warps with `'nearest'`, `FillValues = 0`.
- **Packed-byte nearest warp is correct**: nearest-neighbor copies whole bytes, so bits 1–6
  (material), 7 (mask), 8 (selection) transport together with no averaging — same rationale as
  `warpAndWriteServiceCanvas`'s `'nearest'` on `'everything'`. Bitplane-by-bitplane warping would
  be equivalent but ~8× slower.

**Sub-pixel note:** coarse-level shifts quantize to `s` full-res pixels; the ~3k-wide default
level balances speed/precision; pick level 1 for exact shifts. Document in tooltip + user docs.

**Edge cases:**
- No model → image-only output store; skip labels branch.
- `depth < 2` → error dialog.
- **Cancel** (PoolWaitbar/progress `CancelRequested`) → delete partial output stores
  (`rmdir(..., 's')`), no buffer swap, source untouched.
- Output path already exists → warn-then-overwrite (`saveStream`/`createStore` already `rmdir`
  first).
- Progress: `core.PoolWaitbar` with cancel polling at loop tops and before irreversible steps
  (per BigData perf conventions).

**Verify:**
- Synthetic test: build a small `.zarr3` from a known-good stack with injected per-slice shifts;
  run BigData drift correction; assert residual shift ≈ 0 (re-run `calcShifts` on the result)
  and output canvas == predicted `[newH0 newW0]`.
- Packed-63 bit-preservation: paint material 5 + mask + selection blobs, align, assert all three
  bits survive at the shifted location on every pyramid level (read at levels 1..N).
- Headless run via `mcp__matlab__evaluate_matlab_code`.
- Live GUI: buffer swaps to the aligned store, overlay aligns with image, Directory Contents
  shows the new file, cancel mid-write leaves nothing attached.

---

### Phase 2 — Automatic feature-based v2 (affine, extended canvas) → **Opus**

*Tform conjugation and corner projection at scale, plus reuse of the intricate smoothing/replay
loops — correctness-sensitive.*

**`AutomaticFeatureBasedV2BigData_Alignment.m`:**
1. Validate `TransformationType` (reuse `AutomaticFeatureBasedV2_Alignment.m:57-63`).
2. **Pass 1 at level L**: reuse the per-slice fit logic (`fitPerSliceV2`, `:283-455`) but source
   slices via `getData2D('image', slice, [], colCh, struct('pyramidLevel', L))`.
   **Force the v2 `imgDownsamplingFactorForAnalysis = 1` when a coarse level is chosen** — the
   pyramid level already provides the downsampling; double-downsampling would degrade features.
   Surface this coupling in the UI (grey out the factor when level > 1).
3. Smoothing/replay loops (`interactiveSmoothingV2`, `smoothCumulativeV2`) reused unchanged —
   they act on the small level-L tform arrays.
4. **Conjugate cumulative tforms to level 0**: `T0 = S * TL * inv(S)`, `S = diag([s s 1])`
   (translation column ×s; round for pure-translation types).
5. **Extended canvas** via corner projection (`:201-220`) using level-0 dims and level-0 tforms.
6. `obj.applyAlignmentBigData(parameters, tformInfo)` with `mode = 'affine'` — image provider
   warps cubic, labels nearest, **identical `OutputView`** for both stores guarantees
   co-registration.
7. Annotations warped through level-0 tforms + canvas offset (as `:764-776`), written after the
   buffer switch-over. `saveV2ToFile` reused — store **level-0** tforms.

**Edge cases:** feature-detection failure on any slice pair aborts before anything is written;
memory stays one-slice-bounded during apply.

**Verify:** synthetic affine round-trip (known rigid+scale per slice → recovered); compare a
small BigData run vs the in-memory v2 on the same data (shift/tform vectors within quantization
tolerance); live rigid + affine run on a real slide with a model.

---

### Phase 3 — Landmark modes (single / three / multi-point) → **Sonnet**

*Mostly a port — the apply helper and providers exist after Phase 1.*

**`LandmarksBigData_Alignment.m`** (single entry, branch on `parameters.method`):
- Reuse point extraction from `SingleLandmark_Alignment.m`, `ThreeLandmarks_Alignment.m`,
  `LandmarkMultiPoint_Alignment.m`.
- Annotation-based points are already in full-res coordinates → **no scaling needed**; the
  PyramidLevel selector is N/A for landmark modes (hide or disable it).
- Selection-layer landmark extraction: bound the level-0 read by
  `ds.labels.selectionBBoxFull` (`MibBigDataLabels.m:60-65`) so a gigapixel slice is never read
  whole; compute centroids inside the bbox, offset back to global coords.
- Build tforms: single landmark → translation; three/multi → affine via
  `estgeotform2d`/`fitgeotrans` + `controllers.Alignment.findMatchingPairs`
  (`Alignment.m:58-88`). All already level-0 → straight into `applyAlignmentBigData`.
- Existing insufficient-points error dialogs reused.

**Verify:** synthetic annotation pairs encoding a known transform → recovered; live 3-landmark
run with buffer swap and model following.

---

### Phase 4 — Batch mode, docs, tests, polish → **Sonnet**

- **Batch**: new BatchOpt fields round-trip through `utils.updateBatchOptCombineFields_Shared`
  (`Alignment.m:235-250`) and `returnBatchOpt`/`SyncBatch`. Headless BigData run requires
  `BigData_OutputPath` — clear error if missing. Tooltips complete.
- **Docs**:
  - `development/bigdata/bigdata_logic.md` — add an alignment section (two-pass streaming,
    pyramid-level selection, transform conjugation, packed-63 nearest-warp rationale, new-store
    output + switch-over) and update `bigdata_implementation_plan.md` status.
  - User docs (`docs/`, Zensical — see `docs/CLAUDE.md`): alignment page gains a BigData section
    (a new store is written, source is the backup, coarse-level precision trade-off).
- **Tests** (`mcp__matlab__run_matlab_test_file`, follow `tests/plan_unittests.md` conventions):
  translation round-trip, affine round-trip, packed-63 bit preservation across levels,
  extended-vs-cropped canvas sizes, boundingBox/pixSize metadata propagation, no-model path,
  cancel-cleanup.

**Verify:** test file green; headless `controllers.Alignment(mibModel, [], BatchOpt)` on a
BigData buffer; final live-GUI checklist (below).

## 5. Live-GUI checklist (final acceptance)

1. Open a pyramidal `.zarr3` (BigData) with a painted model+mask+selection.
2. Alignment dialog opens; BigData panel visible; level dropdown default ≈3k px; output path
   prefilled `<name>_aligned.zarr3`.
3. Drift correction, extended mode → new store written, buffer swaps, image+model+mask+selection
   all shifted identically at every zoom level; bounding box updated.
4. Same, cropped mode → canvas unchanged.
5. Feature-based v2 rigid on a rotated synthetic stack → straightened; annotations follow.
6. Three-landmark alignment via annotations → correct.
7. Cancel mid-write → partial stores deleted, source dataset still active and intact.
8. AMST / feature-v1 → friendly "not supported in BigData" dialog.
9. Batch Processing: record + replay a BigData drift-correction action headlessly.

## 6. Risks / open questions

1. **FFT precision at coarse level** — shifts quantize to `s` px; default ~3k level; document;
   optional future refinement pass at level 1 over a subarea.
2. **Packed uint8 nearest warp** — sound (whole-byte copy preserves bit semantics); lock with a
   unit test anyway.
3. **Image/labels pyramids must match exactly** — single `computeLevelPlan` for both stores,
   identical chunk/strategy; test overlay registration at multiple zoom levels.
4. **Level-map sidecar** — must `materializeAll()` + `saveLevelMap()` after streaming labels,
   otherwise stale coarse tiles on next open (`cropToBigData.m:148` precedent).
5. **boundingBox/pixSize propagation** — `saveStream` writes only scale; boundingBox +
   translation must be added via `patchMetadata`.
6. **Undo impossible** — no `backup()` for BigData; the untouched source store is the backup;
   state this in a pre-run info line.
7. **Double downsampling in feature-v2** — force `imgDownsamplingFactorForAnalysis = 1` when a
   coarse pyramid level is selected; reflect in UI.
8. **`.mlapp` edits** — AlignmentGUI.mlapp panel must be added in AppDesigner; controller
   degrades gracefully via `isfield` guards until then.
9. **Time dimension** — 5D already blocked (`updateWidgets:322-331`); BigData path asserts
   `time == 1`.
10. **Output buffer** — Phase 1 swaps the current buffer in place; a "write to new buffer"
    Destination option (à la CropDataset) is a later nicety.

## 7. File map

**Modify**
- `mib/+controllers/@Alignment/Alignment.m` — gate, `isBigData` prop, BatchOpt fields, tooltips, callbacks, updateWidgets
- `mib/+controllers/@Alignment/continueBtn_Callback.m` — BigData dispatch sub-branches
- `mib/+views/AlignmentGUI.mlapp` — BigData panel (AppDesigner)

**Create**
- `mib/+controllers/@Alignment/DriftCorrectionBigData_Alignment.m`
- `mib/+controllers/@Alignment/AutomaticFeatureBasedV2BigData_Alignment.m`
- `mib/+controllers/@Alignment/LandmarksBigData_Alignment.m`
- `mib/+controllers/@Alignment/applyAlignmentBigData.m`
- `mib/+io/+savers/AlignedImageSliceProvider.m`
- `mib/+io/+savers/AlignedLabels63SliceProvider.m` (may fold into applyAlignmentBigData)
- test file under `tests/`

**Reference (read-only)**
- `mib/+io/+savers/Zarr3Saver.m` (`saveStream:280`, `computeLevelPlan:748`, `patchMetadata:818`)
- `mib/+io/+savers/SliceProvider.m`, `MibImageSliceProvider.m`
- `mib/+core/@MibBigDataLabels/MibBigDataLabels.m` (`createStore:107`, `openStore:230`), `getData63.m`, `setData63.m`
- `mib/+core/@MibDataset/cropToBigData.m`; `mib/+controllers/@CropDataset/CropDataset.m:932-968`
- `mib/+core/@MibVirtualImage/getDataZarr.m` (`:58-68` level selection)
- `mib/+utils/+align/` — `calcShifts.m`, `crossShiftStack.m`, `detectFeatures.m`, `subtractRunningAverage.m`
- In-memory algorithm references: `DriftCorrection_Alignment.m`, `AutomaticFeatureBasedV2_Alignment.m`, HDD variants
