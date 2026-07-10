# Alignment for BigData mode — implementation plan

Status: **All phases (0–4) done** (2026-07-05). Decisions confirmed with IB; codebase facts verified against source (file:line cited throughout). Remaining: the AppDesigner `.mlapp` BigData panel is a manual edit (done by IB), and the final live-GUI acceptance run on real data (checklist §8).

**Perf fix (2026-07-09) — labels store write ~15× faster.** The labels branch of
`applyAlignmentBigData` used a per-slice `setData63('everything', ..., z)` loop, which for every
slice did a read-before + diff + **eager cross-level propagation to all coarser levels** + selection-
bbox scan, and wrote one Z-slice at a time into a Z-chunk of 16 (so each zarr chunk was
compress/decompress'd up to 16× — a partial-chunk read-modify-write). Measured on a 887×813×171,
3-level model: **89 s** for the labels vs a fast image stream (the reported 5–10× gap). Replaced with
a two-pass writer: **Pass A** warps each source slice into level 1, buffered and written in Z-chunk
strips (one write per chunk); **Pass B** builds every coarser level from level 1 in a single bulk
nearest pass using global index maps (strip-independent, exact packed-byte copy — same convention as
`propagateRegion`'s inline formula), then `markTiles(...,1)` over the whole volume (all levels written
explicitly, so `materializeAll` is skipped). Verified: level 1 **bit-identical** to the old output;
coarser levels a clean deterministic nearest downsample; new time **~6 s (35× on the store-write
portion)**; all 9 `AlignmentBigDataTest` tests green. Bounded memory (~one chunk) — scales to gigapixel
slides.

**Bug fix (2026-07-09) — SaveShiftsToFile / loadShiftsCheck broken in BigData.** Two defects:
(1) **Drift/Template BigData** stored *level-L* shifts in `obj.shiftsX` on a fresh run but scaled by
`scaleX` only when applying, while `saveShiftsBigData` wrote the *level-0* shifts. On reload
(`loadShiftsCheck` → `obj.shiftsX` = level-0), the apply step re-multiplied by `scaleX` → **double-
scaled** canvas whenever the analysis level > 1 ("align another dataset" gave wrong results). Fix:
scale to level 0 immediately after `calcShifts`, so `obj.shiftsX/Y` (previewed, running-averaged,
applied, saved) always hold **level-0** shifts; apply is now `round(obj.shiftsX)` with no re-scale
(mirrors the in-memory path). Added a slice-count guard for mismatched loaded files.
(2) **Feature-based v2 BigData** never saved at all (no `SaveShiftsToFile` block) and never replayed a
loaded struct (no `shiftsLoaded` branch). Fix: added a local `saveV2ToFile` (writes the level-0
`cumulativeTforms` struct, same format as the in-memory v2) and a replay branch that skips
detection/fit/smoothing/conjugation and uses the loaded level-0 cumulative tforms directly.
Verified live end-to-end on a **2-level** synthetic (scaleX=2): align at level 2 → save → reload into a
fresh dataset at level 2 → canvas 676×666 == first run (old code would give ~712×692). Tests added:
`driftSaveShiftsWritesLevel0File` (level-0 file predicts the grown canvas) and
`featureV2SaveShiftsWritesStruct` (v2 writes a `cumulativeTforms` struct). All 11 tests green. (Note:
the `.coefXY` reload path is GUI-only — `loadShiftsCheck_Callback` populates `obj.shiftsX`; batch mode
has no load hook, unchanged.)
(3) **Load preview/confirm at Apply** — `loadShiftsCheck_Callback` loads silently (and clears the
stored coefficients when the box is unchecked); the preview + confirm happens on the **Apply button**
(`continueBtn_Callback` → `private/previewConfirmLoadedShifts`), where the selected algorithm is known.
It classifies the loaded coefficients (numeric → drift; struct w/ `cumulativeTforms` → feature-v2; cell
→ legacy v1), plots them (drift → X/Y displacement; v2 → cumulative translation + rotation; legacy →
translation), and asks "Align the dataset using these coefficients?". If the coefficient type does not
match the selected algorithm it **aborts with a mismatch error** ("produced by X, but the selected
algorithm is Y — select X or load matching coefficients") instead of silently recomputing or crashing.
GUI only (batch has no load hook). Shared by in-memory and BigData.
(4) **Detected-displacement preview for landmark modes** — landmark alignment previously applied
without showing the user the detected displacements (only in-memory single-landmark and drift did).
Added a shared `private/plotAlignmentTransforms` (plots shift vectors, or per-slice cumulative
translation + rotation for a tform cell; handles `affinetform2d`/`affine2d`/3×3) and
`private/confirmDetectedTransforms` (preview + "Apply current values / Quit alignment", batch-guarded by
the caller). Wired into **BigData landmarks** (all 3 modes in `LandmarksBigData_Alignment`) and the
**in-memory** `ThreeLandmarks`, `LandmarkMultiPoint`, `LandmarkMultiPointColor` (fresh compute only —
`~shiftsLoaded`, since loaded coefficients are already previewed at Apply). `previewConfirmLoadedShifts`
refactored onto the shared plotter. Also fixed the coefficient/algorithm compatibility sets there:
numeric shifts are valid for drift/template **and** single-landmark; a tform cell is valid for
feature-v1 **and** the multi-point/colour landmark modes (the earlier strict 1:1 map would have wrongly
rejected those replay flows).

**UX fix (2026-07-09) — single/three-landmark TransformationMode was stuck on cropped.**
`algorithm_Callback` left the `TransformationMode` dropdown **disabled** for `Single landmark point` and
`Three landmark points` (only the default disable-all loop ran), so its value was sticky from a prior
algorithm (AMST / Color-channels force `cropped`) with no way to change it. The BigData apply path *does*
honour the mode, so single-landmark silently produced a cropped canvas. Fix: for these two modes,
default `TransformationMode` to `extended` and **enable the dropdown for BigData** (the in-memory
single/three paths always extend via `crossShiftStack`, so the choice is only exposed where it is
honoured). Verified the BigData single-landmark apply respects both modes (extended 268×258 vs cropped
240×240 on a 240² synthetic). Tests: `landmarkSingleCroppedKeepsCanvas` + an extended-grows assertion in
`landmarkSingleTranslation` (12/12 green).

**Consistency fix (2026-07-09) — aligned store now mirrors the source pyramid.** `applyAlignmentBigData`
previously wrote every aligned store with hardcoded saver options (`[256 256 16]` chunks, up to 8 levels,
`XY only`, bilinear) regardless of the input. Now it derives the options from `ds.image.pyramid`:
level-0 **ChunkSize** (mapped from `chunkSizes{1}` via `axisOrder`), the exact source **level count**
(`saverOpts.Levels = size(levelImageSizes,1)`), the **DownsampleStrategy** (`Anisotropy-preserving` iff
the source ever halves Z, else `XY only`), and **ShardSize** (only when the source shard spans more than
one chunk). The labels store inherits the same via a `chunkSizes` built from the final chunk + the shared plan, so
image and labels co-register with matching chunk/level structure. Verified live on a distinctive source
(chunk `[64 64 2]`, 3 levels): the aligned image **and** labels reproduced 3 levels with the same chunk
(canvas grown for `extended`). Test: `pyramidSettingsMatchSource` (13/13 green).

**Silent vs GUI (2026-07-09).** Per IB: **silent/batch** runs use the source-matched settings directly
(no dialog); **GUI** runs open the shared `Zarr3Saver.optionsDialog` **pre-filled from the open dataset**
so the user can review/adjust before writing. `optionsDialog` gained an optional `presetDefaults`
argument (backward-compatible, `nargin<5`) that overrides the dimension-heuristic defaults with the
dataset's actual `Levels`/`ChunkSize`/`ShardSize`(→per-axis chunk multipliers)/`DownsampleStrategy`/
`DownsampleMethod`/`Compressors`. `applyAlignmentBigData` builds the preset from the source pyramid,
shows the dialog (`~parameters.useBatchMode`), merges the result over the source-matched base (auto
level count / no-sharding honoured when the user picks 0), and cancel aborts before any write. No
"keep existing" checkbox — the dialog simply opens on the current dataset's values.

**Bug fix (2026-07-09) — aligned model lost material names/colours.** `applyAlignmentBigData` created
the new labels store with `createStore` (which starts with an empty material list) but never persisted
the source names/colours to it. In-session the swap restored them on the reopened object, but the
on-disk `Labels_<stem>.zarr3` had no `mibMaterials` attribute, so reopening the aligned file later came
back unnamed/greyed. Fix: copy `materialNames`/`materialColors`/`materialsCount` onto `newLabels` after
`createStore` and call `newLabels.writeMaterialMetadata()` before `closeStore()` (same convention as
`Zarr3Saver.exportModel`). The **bounding box is correct** — `patchMetadata` writes `mibBoundingBox` to
the *image* store (the only store that carries one; `exportModel` doesn't bbox the model either), and
the labels pyramid inherits the image frame on reopen. `packed63BitsPreservedAcrossLevels` now also
asserts on-disk material persistence (fresh `openStore` of the aligned labels store).

**Phase 4 completed** — headless-batch hardening + formal tests + docs. Fixed a real headless bug:
the labels-warp `uiprogressdlg` crashed when `mibGUI` is empty (bare-model batch runs) — now guarded.
Added `tests/controllers/AlignmentBigDataTest.m` (9 Integration tests, all pass in ~2 s against a bare
`models.MibModel(1, mibFolder)`, no live session): drift extended/cropped canvas, feature-v2 rotation
correction, packed-63 bit preservation across levels, bbox/pixSize propagation, no-model path, single &
multi landmark, and the empty-output-path abort guard. Batch round-trip is exercised by every test
(`controllers.Alignment(model, [], BatchOpt)`). Docs: alignment section added to `bigdata_logic.md`
(§13) + File map; BigData section added to the user docs alignment page
(`docs/.../dataset-alignment.md`); status updated in `bigdata_implementation_plan.md`.

**Phase 3 completed** — landmark modes (single / three / multi) for BigData, **annotation-driven**
(the practical source for gigapixel slides; selection-layer extraction bounded by `selectionBBoxFull`
is a later add). `LandmarksBigData_Alignment.m` branches on `parameters.method`: single → per-slice
cumulative **translation** (`mode='translation'`); three → first slice pair with 3+ matching-labelled
annotations → one **affine** broadcast to the tail; multi → per-slice cumulative **affine**
(`fitgeotrans`, matched by label). Points are level-0 → no scaling. Canvas via corner projection
(`transformPointsForward`, transform-type-agnostic); a **world-limited `imref2d` OutputView** is used
so raw (unbaked) `affine2d`/`projective2d` tforms place correctly. To support this the provider now
accepts an `imref2d` OutputView, and `applyAlignmentBigData` builds ONE `ref0` (default for
translation/affine-baked callers, world-limited for landmarks) used for **both** image and labels.
Annotations warped via `transformPointsForward` + `worldToIntrinsic(outputView)`. End-to-end test
(`scratchpad/test_phase3_e2e.m`, all three modes on spare buffers): single → aligned model-blob
centroid spread 0.00 px; multi → landmark spread 0.00 px + image residual **0.003°** (injected 12°);
three → tail residual **0.173°** (was 8°). Phase 2 e2e re-run green after the provider refactor.
(Note: `imrotate(+a)` moves an (x,y) feature by `R(-a)` — image Y points down — a test-setup detail.)

**Phase 2 completed** — feature-based v2 affine for BigData. Extracted the 4 shared v2 helpers to
`utils.align.*` (`fitPerSliceV2`, `smoothCumulativeV2`, `interactiveSmoothingV2`, `plotCumulativeV2`)
so the in-memory and BigData paths share one source; `fitPerSliceV2` now takes a caller-supplied
`readSliceFcn` (in-memory → `getData2D`; BigData → `ds.image.getData(...,'pyramidLevel',L,'z',[n n])`,
reading the FULL level-L slice — `getData2D` returns only the visible viewport for a pyramid, so it
must be bypassed). `AutomaticFeatureBasedV2BigData_Alignment.m`: fit at level L (force analysis
factor = 1 when L>1 to avoid double-downsampling), compose cumulative, smooth, **conjugate L→0**
(`T0.A(1:2,3) *= scale`), corner-projection canvas at level-0, bake origin offset into the tforms
(so the provider uses a unit-pixel default OutputView), `applyAlignmentBigData` with `mode='affine'`.
`applyAlignmentBigData` gained a `result` flag + a warped-annotation writeback (positions `[z x y t]`,
warped via the baked level-0 tforms → `replaceLabels` on the swapped dataset). The v2 caller captures
source annotations (`getLabels`), warps them, and passes them through `tformInfo.annotations`.
End-to-end test (`scratchpad/test_phase2_e2e.m`, synthetic per-slice rotation + model + annotations,
spare buffer): canvas extends, buffer swaps, model reattaches + follows, display renders, an injected
**8° rotation is corrected to 0.08° residual**, and the 3 annotations are preserved (count + values)
with positions warped in-bounds and canvas-consistent. All files pass `check_matlab_code`.
**In-memory v2 regression PASSED** (`scratchpad/regress_v2_tif.m`): a real multipage TIF loaded via
`MibModel.loadImages` (genuine Standard `MibImage`), in-memory v2 rigid corrected an injected 10°
rotation to **0.04° residual** with the canvas extending 320→372 — confirming the `utils.align`
extraction + `readSliceFcn` refactor did not regress the resident path. (Note: v2 needs
feature-rich slices; smooth-blob synthetics yield `ok=0` from `fitPerSliceV2` — a detector/data
limit, not a code bug.) Live-GUI acceptance on a real rotated `.zarr3` still recommended.

**Phase 1 completed** — implemented `DriftCorrectionBigData_Alignment.m` (pass-1 shifts at analysis
level, scale to level 0, resolve background), `applyAlignmentBigData.m` (canvas math, shared
`computeLevelPlan`, streamed image store via `saveStream`, packed-63 nearest-warp labels store +
`materializeAll`/`closeStore`, `patchMetadata` bbox, buffer swap-over per CropDataset), and
`io.savers.AlignedImageSliceProvider` (level-0 read → imwarp into OutputView; `nearest` for integer
translation, parametrised interp for affine). All pass `check_matlab_code`. Headless synthetic test
(`scratchpad/test_phase1_bigdata_align.m`) proves: aligned canvas == predicted; **provider output
pixel-identical to `crossShiftStack`**; packed-63 material/mask/selection bits preserved across all
pyramid levels. Translation is `affinetform2d`; drift uses `nearest` (exact integer placement).
**Phase 1 end-to-end verified** — `scratchpad/test_phase1_e2e.m` runs the FULL controller in batch
mode on a spare live-session buffer (synthetic multi-slice BigData + attached model): dispatch →
`DriftCorrectionBigData` → `applyAlignmentBigData` → `saveStream` → labels warp → `patchMetadata` →
reopen → **buffer swap** → model reattach. Asserts pass: buffer becomes BigData, canvas grows
(extended), model reattached as `MibBigDataLabels` with names preserved, material/mask/selection
follow, and `getRGBimage` renders the swapped buffer (529×531×3) with no manual fixup.

**Swap bug found + fixed:** `MibDataset.initialize` leaves `slices` at `[1 1]` and (for an off-screen
buffer) `axesX/axesY` at `NaN`; the display read then crashed in `getDataZarr:104`. `applyAlignmentBigData`
now resets `slices` to the new full extent (mirrors `cropDataset`) and defensively seeds `axesX/axesY`
when uninitialised. In the GUI the active buffer already has a valid pan window (listener_newDataset
zoom-to-fit), so the seed is a no-op there; the `slices` reset is required in all cases.

**Phase 1 limitations:** (a) Subarea by Mask/Selection rejected for BigData drift (Full image /
Manually specified only); (b) XY orientation (3) only. **Final live-GUI acceptance** (open Alignment
on a real displayed multi-slice `.zarr3`, click Apply, watch the swap) still recommended.

**Phase 0 completed** — gate relaxed (BigData no longer rejected in the constructor; virtual still is),
`isBigData`/`bigDataPyramid` props added, BigData BatchOpt fields (`BigData_PyramidLevel`,
`BigData_OutputPath`) with dynamic level dropdown + `<auto>` (~3000 px) default, tooltips,
`addCallbacks`/`gui_Callbacks` browse wiring (all `isfield`-guarded), `continueBtn_Callback`
BigData dispatch sub-branches + friendly rejection for feature-v1 / AMST / color-channels-multi,
and 6 stub files (3 algorithm entries, `applyAlignmentBigData`, 2 slice providers). All files pass
`check_matlab_code`; class + provider classes resolve in the live session.
**Still pending for Phase 0:** the `+views/AlignmentGUI.mlapp` "BigData" panel is a manual
AppDesigner edit (dropdown `BigData_PyramidLevel`, edit `BigData_OutputPath`, button
`BigData_SelectOutputBtn`, container `BigDataPanel`); until added, the controller degrades
gracefully but the panel is invisible. The live-GUI acceptance check awaits that edit.

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

## 8. Phase 1 live-GUI acceptance checklist (drift correction)

Run in the real GUI on a **displayed, multi-slice** pyramidal `.zarr3` (BigData) — depth ≥ 2. The
headless + end-to-end tests already pass; this confirms the interactive path on real data.

- [ ] Open a multi-slice `.zarr3` BigData dataset (ideally with a painted model + mask + selection).
- [ ] Open **Ribbon → Dataset → Alignment**. The **BigData panel** is visible (replaces the HDD panel);
      pyramid-level dropdown lists all levels with the `<auto>` (~3000 px) default; output path is
      prefilled `<name>_aligned.zarr3`.
- [ ] Choose **Drift correction**, **TransformationMode = extended**, background = White. Click **Apply**.
- [ ] Preview plot of detected shifts appears → **Apply current values** (or **Fix drifts** to smooth).
- [ ] Progress bar runs (streaming image, then labels). On completion the **active buffer swaps** to the
      aligned store; the image renders immediately (no manual zoom needed).
- [ ] Image + model + mask + selection are all shifted identically at multiple zoom levels (overlay
      stays registered when zooming, exercising the shared pyramid).
- [ ] **Directory Contents** highlights the new `<name>_aligned.zarr3`; a sibling `Labels_<name>_aligned.zarr3`
      exists on disk; the **source store is untouched** (acts as the backup).
- [ ] Bounding box / pixel size sensible (check the Dataset info panel).
- [ ] Re-open Alignment → **cropped** mode → canvas dimensions unchanged.
- [ ] **Cancel** mid-write (progress dialog) → partial `.zarr3` stores deleted, source dataset still
      active and intact, no buffer swap.
- [ ] On a BigData dataset, **AMST** and **Automatic feature-based (v1)** → friendly
      "not supported in BigData" dialog; **Color channels, multi points** likewise rejected.
- [ ] Subarea = **Mask**/**Selection** on BigData drift → friendly "use Full image / Manually specified"
      dialog (Phase 1 limitation).
