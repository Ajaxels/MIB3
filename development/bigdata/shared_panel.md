# BigData support for Image tools - shared panel and processing engine

> Approved 2026-11-06. Status and "Resume here" (next steps) at the end.

## Context

The Image ribbon tools (Image filters `controllers.ImageFilters.Filter`, Image tools drop-down:
Content-aware fill, Debris removal, Image arithmetics, Intensity projection, Image frame, Sharpness,
White balance; MorphOps; Contrast CLAHE / normalization) were designed for Standard datasets: they
`getData3D` the whole stack, process it in RAM and `setData3D` it back with an undo copy. On BigData
this is refused (`ContentAwareFill`, `DebrisRemoval`, `ImageFrame`, `WhiteBalance`,
`MorphOpsImages`, `ContrastClahe`, `ContrastNormalization`), and until 2026-11-06 it was silently
attempted by Image filters and Image arithmetics (see Status).

The source image of a BigData dataset is read-only (bigdata_logic.md §1), so for an image result the
tool has to write somewhere else. That makes BigData parameters necessary that a Standard dialog does
not have.

---

## 1. Required parameters

### A. Input: what is read
| Parameter | Values | Notes |
|---|---|---|
| **Pyramid level** | `s0` ... `sN` | Named from `s0` (full resolution) as in Crop and Chunking export, without sizes so a protocol recorded on one dataset matches the items of another (the size label shows the size). The engine (`processImageToStore`, `Level`) stays 1-based. |
| **Region** | whole dataset / ROI(s) / current view / current slice (2D) | Whole-dataset at level 1 of a WSI is the costly case. Current view gives quick results at the displayed level. Reuses `restrictToROI` and the existing `DatasetType` (2D slice / 3D stack). |
| **Estimated cost** (read-only label) | output size in voxels / GB, at the chosen level | Lets the user see that level 1 = 40 GB before pressing Apply. Updated when the level or region changes. |

### B. Output: where the result goes
| Result | Allowed destinations |
|---|---|
| image (filters, arithmetics, white balance, morph ops on image, CLAHE...) | **New BigData store** (default) / **Standard dataset in a buffer** (only if the estimated size fits in memory; current, new or an existing buffer) |
| mask / selection / labels (binarization, DistanceMap source...) | **Current model** (written live through `setData63` at the chosen level, with the level map marked; needs a model, honours `lockedState`) |
| measurements only (Sharpness) | none, only A applies |

For **New BigData store**:
| Parameter | Notes |
|---|---|
| **Output path** + *Select...* button | default `<stem>_<tool>.zarr3` next to the source; the button uses `uigetdir` (a store is a folder, which `uiputfile` opens instead of selecting): a picked `*.zarr` / `*.zarr3` folder is the store, any other folder gets the store under its current name; confirm before overwriting an existing store; refuse the path of an open store. |
| **Zarr settings** | `io.savers.Zarr3Saver.reviewOptionsDialog` preset from `optionsFromPyramid(image.pyramid)`, as Alignment and Crop do. A *Zarr settings...* button plus a one-line summary (chunks / shards / codec / levels), not inline widgets. |
| **Open the result in** | current buffer (swap, as Alignment) / new buffer / do not open |
| **Keep the model** | when the output geometry is the same as the source (level 1, no crop/projection): re-attach the existing labels store to the new image. Otherwise the model is not carried over. |

### C. Processing
| Parameter | Notes |
|---|---|
| **Tile size** | default from the store chunk shape (x n). Advanced. |
| **Overlap (halo)** | **derived by the tool** from its parameters (`ceil(3*sigma)`, strel radius, filter size). The user does not set it. 3D filters also need a halo in Z. |
| **Parallel / workers** | existing `UseParallelComputing`; tiles through `saveStreamResumable` with a pool. |
| **Output class** | needed before the store is created (DistanceMap, MathOps change it). Comes from the tool, no widget. |
| **Resume** | `saveStreamResumable` `options.Resume`. Offered when the output path holds a partial store from an interrupted run. |

### D. Not parameters, but must be designed
- **Global statistics.** Contrast normalization, CLAHE limits, Otsu/global thresholds, the auto
  stretch for SLIC/Watershed (`Filter.m`) need statistics of the whole dataset: compute them at a
  coarse level, then apply them per tile at the target level.
- **Undo.** New store: none needed (the source is the backup, as in Alignment). Current model: the
  existing BigData backup path (bbox at the working level). Standard output: as today.
- **Cancel.** Always cancelable. On cancel the partial store is kept for Resume or deleted, and the
  message says which slices were done.
- **Metadata.** Pixel size scaled by the level factor, bounding box, action log.
- **Preview.** At the displayed level over the visible area. Already cheap, no new parameters.
- **Batch.** Every parameter is a `BigData_*` BatchOpt field (Alignment already uses
  `BigData_PyramidLevel`, `BigData_OutputPath`), ignored on Standard datasets.

---

## 2. Implementation options

The real shared need is the **processing engine** more than the widgets: tiled read at level L with a
halo, a per-tile function, writes to a store, buffer or model, cancel, resume. Every option below
assumes it. They differ only in how the parameters reach it.

### Option 1 - Hidden panel in every dialog (the Alignment approach)
- + Best integration; each tool shows only the destinations it supports.
- - About 10 mlapp edits, the same widget and callback code in each controller. Alignment shows the
  cost: about 60 lines plus a re-parenting fallback (`Alignment.m`, `updateWidgets`). Layouts drift
  apart; each fix is made N times.

### Option 2 - Separate shared dialog launched from `startController`
- + No change to the tool dialogs.
- - `startController` is generic (Preferences, About, InstanceEditor...): it would need a list of
  compatible tools.
- - Wrong moment: the tool is opened before the filter is chosen, but the valid destinations depend
  on the choice at Apply (binarization -> model, Gaussian -> new image).
- - Two windows not tied together: a window "under the tool" must follow its moves, resizes, closing
  and raising; MATLAB has no docking for a child uifigure.
- - A batch call carries no BigData fields; batch needs a separate path.

### Option 3 (chosen) - Shared panel injected into the tool's own window
A reusable class `controllers.BigDataOptions`. The tool creates it in its constructor with one call
and declares what it supports:

```matlab
obj.bigDataOptions = controllers.BigDataOptions(obj, ...
    'Destinations', {'NewStore','Buffer'}, 'NeedsGlobalStats', false);
% builds the panel in code (uipanel + uigridlayout) and adds a row to the dialog's
% top grid layout, or extends the figure height when the dialog has no grid
```
- Built **in code**, no mlapp edited. Added only on BigData; rebuilt on `updateWidgets` when the
  active buffer changes type.
- Owns its `BigData_*` BatchOpt fields and merges them into the tool's BatchOpt. Widget names match
  the field names, so `updateBatchOptFromGUI_Shared` works unchanged.
- At Apply the tool calls `obj.bigDataOptions.run(@tileFunction, halo, outputClass)`, which sends the
  work to the engine and returns the destination; the tool can refuse a combination there.
- + One implementation, one look, in the tool's own window; batch works; about 3 call sites per tool
  (constructor, `updateWidgets`, Apply). Alignment and Crop can move to it later.
- - Adding to an mlapp grid at runtime depends on each dialog's top layout; fallback: a strip added
  to the bottom of the figure.

### Option 4 (rejected) - One BigData processing context on the ribbon
- + Almost no per-tool UI.
- - Hidden state: the same Apply does different things depending on a setting not visible in the
  tool; weak where destinations differ (image vs model).

Kept from Option 4: the Zarr settings dialog opens at Apply when the output is a new store.

### Order of work
1. **Engine.** Reuse:
   - `io.savers.Zarr3Saver.saveStreamResumable` (pyramid build, tasks, resume, cancel,
     `BandHeight` bands of rows read through `provider.getSliceRows`)
   - `optionsFromPyramid` / `reviewOptionsDialog` / `computeLevelPlan`
   - `MibBigDataLabels.setData63` with `pyramidLevel` (model output)
   - `Zarr3VirtualSetupLoader` + `I{id}.initialize(...,'BigData')` (buffer swap, as in
     `applyAlignmentBigData` and `CropDataset`)

   New: `io.savers.FilteredSliceProvider`, which reads a band of rows of one level plus a halo,
   applies the tile function and crops the halo. `MibImageSliceProvider` is not usable as the
   source: its constructor probes a whole slice, which at level 1 of a WSI does not fit in memory.
2. **`controllers.BigDataOptions` panel** on top of the engine.
3. **Pilot: Image filters** - local 2D/3D filters (halo), binarization (model destination), class
   change (DistanceMap, MathOps). Then Image arithmetics, MorphOps, White balance; then the global
   statistics tools (normalization, CLAHE); last the geometry-changing tools (Intensity projection,
   Image frame), which need a new level plan.
4. **Compatibility groups** (declared by each tool): pointwise (arithmetics, white balance); local
   neighbourhood (filters, morph ops); global statistics (normalization, CLAHE, global thresholds);
   geometry-changing (projection, frame); analysis only (sharpness); stays blocked (Content-aware
   fill, Debris removal - inpainting of a region; could later become footprint-bounded edit tools).

### Files
- New: `+controllers/@BigDataOptions/`, `+utils/+bigdata/` engine, `+io/+savers/FilteredSliceProvider.m`
- Pilot: `+controllers/@ImageFilters/{ImageFilters,Filter,updateSessionSettings}.m`
- Later: `ImageArithmetics`, `MorphOpsImages`, `WhiteBalance`, `ContrastNormalization`, `ContrastClahe`
- Docs: `bigdata_logic.md` (new section), `docs/docs/getting-started/dataset-types/index.md`

### Verification
- Unit tests in the style of `tests/controllers/AlignmentBigDataTest.m` on a small generated zarr3
  pyramid: a Gaussian at level 1 written in bands equals `imgaussfilt` of the whole array (halo);
  the same at level 2 has the level-2 geometry and a scaled pixel size; binarization into the model
  reads back at every level (as `MibBigDataLevelMapTest`); cancel; batch run with `BigData_*` fields.
- Single test classes only in the live MCP session, never `buildtool`.
- Manual check on a WSI (CMU-1).

---

## Status

| Step | State |
|---|---|
| Guards in `Filter.m` and `ImageArithmetics.m` tested the MIB2 `Virtual.virtual` property, which `MibDataset` does not have, so they never fired | fixed 2026-11-06 (`ae6099ca`): `any(datasetType(1) == ['V' 'B'])` |
| Image arithmetics: check every buffer the expression names (`I2`, `M3`...), not only the active one | done 2026-11-06 with step 5: checked at each run (the active buffer can change while the dialog is open), so the constructor guard was removed; a Virtual / BigData buffer is refused, except as the target of an image result, which replaces that buffer |
| 1. Engine: `io.savers.FilteredSliceProvider` + `utils.bigdata.processImageToStore` (image -> new store) | done 2026-11-06, `tests/utils/ProcessImageToStoreTest.m` 7/7. Not yet: output to the current model, output to a Standard buffer, global statistics, parallel pool |
| 1b. Opening the store in a buffer | done 2026-11-06: `BigDataOptions.openStoreInBuffer` |
| 2. `BigDataOptions` panel | done 2026-11-06. Level, Open in, size of the result, Output + Select. The Zarr settings are asked at Apply (as Alignment and Crop), so no Zarr button. Checked in the real Image filters window on a headless model: row inserted above the buttons, window grows 90 px, removed and restored when the buffer switches to Standard and back. 2026-11-06: the user added the panel to `ImageFiltersGUI.mlapp` (`BigDataoutputPanel`, row 4 of `mainGridLayout`, 80 px); `BigDataOptions.bindDesignedPanel` wires its widgets, and `showDesignedPanel` sets the row to 0 px and shrinks the window by 80 px for a non-BigData buffer (checked headless: 637 / 557 px, both opening orders). The other tools still get the panel built in code |
| 3. Image filters pilot | done 2026-11-06 for the image layer: Average, Disk, Gaussian, Gradient, LoG, Median, Mode, Motion, Prewitt, Sobel, 2D and 3D, channel choice, Filter and add / subtract; whole dataset at the chosen level. `tests/controllers/ImageFiltersBigDataTest.m` (batch path). Extended 2026-11-06 at the user's question ("why AddNoise is disabled"): AddNoise, MathOps (per pixel), Entropy, Range, Std, SaltAndPepper, Frangi, Bilateral, AnisotropicDiffusion (halo = iterations), Wiener, NonLocalMeans, UnsharpMask, halos in `localFilterHalo`; empty Wiener AdditiveNoise / NLM DegreeOfSmoothing estimated per slice and channel by `localNoiseEstimates` (wiener2's mean local variance; Immerkaer's sum over the full convolution, outer rows read separately); refused: UnsharpMask Threshold > 0 (relative to the global max edge), MathOps output class change; not offered: FastLocalLaplacian, LocalContrast, LocalBrighten, ReduceHaze, FlatfieldCorrection, DistanceMap, ElasticDistortion, BMxD, DNNdenoise (all but DistanceMap and DNNdenoise offered since, see 3d). imnlmfilt needs 21 x 21: a shorter band (the provider's 8-row probe) is padded symmetrically beyond the halo. `localFiltersMatchStandardInBands` (64-row bands via the new `BigDataOptions.BandBytes`). Side fix in Standard: `doImageFiltering` MathOps applied the operation once per channel (Add 5 on RGB added 15) |
| 3b. Level items | done 2026-11-06, user decision: plain `s0`, `s1`... without sizes, in BigDataOptions **and Alignment**, so a protocol recorded on one dataset runs on another of a different size. Alignment still reads protocols with the old `2: X x Y` items (1-based). Alignment no longer shows level sizes anywhere (it has no size label) |
| 3c. `Current overwrite` in Open in | done 2026-11-06, user decision: **first item** of the list, but not the default (default = first empty container, else Do not open). Rewrites the source store: unlocked image, level s0, zarr v3 only; temp store `<stem>.mib_overwrite<ext>`, swap through `<stem>.mib_replaced<ext>`, only `dataset.image` replaced (model, ROIs, annotations, undo of the model kept), `ChunkCache` cleared. First GUI try failed in `getDisplayStretch`: the new image had no `pixSize` (MibDataset.initialize sets it after the constructor) - fixed, `replaceImage` copies `pixSize` and `boundingBox` from the old image; test covers it. The user's `130912_Trypanosoma_crop_Average.zarr3` was overwritten in that failed try and must be reopened |
| 3d. Whole-slice filters, Elastic, BMxD | done 2026-11-06 at the user's request ("can be acquired from the downsampled image"; DNNdenoise not needed). **Guide**: the finest level with at most `BigDataOptions.GuidePixels` (32 Mpx: seconds and < 1 GB) per slice; at ratio 1 the result equals Standard (`wholeSliceFiltersMatchStandard`). Per filter (`localPositionedPlan` docblock): Flatfield - mean from the guide, or from a sampled pass when the guide is coarser (the V of averaged RGB pixels is biased low; the synthetic test was 3.5 off before), shading in the band up to halo 256, else from the guide; LocalBrighten / ReduceHaze - atmospheric light from the guide, simpledcp local (halo 5), global stretching limits from a sampled 2^18-bin histogram pass of the dehazed level (`localSampledLimits`); LocalContrast / FastLocalLaplacian - own Aubry core on the IPT llf builtins, 2 + guide octaves levels in the band (halo 2^(K+1)), the coarser residual from the guide, intensity range from the sampled pass (the guide range alone cost 4.5 grey levels). `FilteredSliceProvider` passes `(block, z, firstRow)` to a 3-input function (positions for Elastic and the BMxD grid). **Measured** mean difference to Standard at s1 / s2, grey levels (AT3_1m4_01 gray, hestain RGB): Flatfield 0; ReduceHaze simpledcp global 0; LocalBrighten 0 / 1.26 (AT3), 1.85 / 0.16 (hestain, p99 up to 20); ReduceHaze with estimated atm 4.1 / 5.2 (AT3), 0.28 (hestain); LocalContrast and FLL 1.0-1.3 / 1.5-2.0 (p99 3-8). Test tolerances: 2.5 LocalBrighten, 2 LLF, 1 others. **Rejected**: approxdcp from a coarse guide (3-12 off; interpolated haze map, guided refinement of the haze and a fast guided filter with a, b from the guide all fail; a dark channel min-pooled from the full level gives 0.1-1.5 but needs a full extra read - user 2026-11-07: not wanted), so approxdcp is refused above the budget; atmospheric light with the quadrant chosen on the guide and the pixel nearest to white read from the level (better in 2 of 6 cases, up to 4.9 off). **Elastic** was always implemented in `doImageFiltering` (a stale comment said otherwise): random field per row from substreams of `threefry4x64_20` seed 0, halo `ScalingFactor` + kernel radius + 1. User decision 2026-11-07: Simard definition in Standard and BigData (no `norm(dx)` normalization, which made displacements 0.1 px at 512 px and shrinking with size; kernel `2*ceil(2*Sigma)+1` from Sigma, HSize dropped: HSize 7 with Sigma 4 tore the image). Timings 591 x 806 / 2048 x 2048: norm 0.09 / 1.05 s, Simard field 0.01 / 0.06 s, Standard griddata warp 2.3 / 21.7 s, interp2 warp (BigData) 0.012 / 0.05 s; griddata vs interp2 mean 2.5 grey levels. User decision 2026-11-07: Standard warps with interp2 too, positions clamped to the image (replicated edges; BigData clamps to the band, which acts only at the image edge); Standard now 0.025 s / 0.19 s per slice; bands equal one band; refused with DistortAllLAyers when a model / mask exists. **BMxD**: halo `2*N1 + floor(Ns/2)` per stage (np 70), top pad to the `lcm(Nstep)` grid. Not bit-exact, and cannot be: the block-matching threshold scales with the intensity range of the image BM3D gets (stage 1 the input, stage 2 the basic estimate), the noise PSD is processed at that size, threads aggregate in any order; which band starts come out exact changes with the thread count. On a micrograph bands differ by mean 0.09, p99 0.6, max 4; rescaling both thresholds to the slice ranges or halos of 35-160 rows change that by < 0.02, so neither is done. Side fix in Standard: ReduceHaze with an empty AtmosphericLight on a gray image errored (`doImageFiltering`) |
| 4. Binarization into the current model | done 2026-11-06: `BigDataOptions.runToModel` + `setModelOutput` (panel: only Level enabled). Edge (Sobel, Prewitt, Roberts halo 3; LaplacianOfGaussian halo `ceil(3*Sigma)+2`; given threshold) into selection or mask, whole dataset at the chosen level, no undo, GUI confirmation; cancel reports the slices done. Bit-exact with 40-row bands. Refused with a reason: Canny/approxcanny, automatic threshold, SLIC, Watershed, no model, read-only model, model level of another size. After a run coarser than s0: info dialog (user decision) - finer levels fill on zoom-in, or everywhere with Save model -> Finalize & save (`materializeAll`); not done automatically |
| 5. Image arithmetics | done 2026-11-06 (my decisions, to review): input only `I` of the active dataset; output `I` -> new store / Current overwrite, `M`/`S` -> `runToModel`; `O`, other buffers and model inputs refused. Band-wise check (`checkBandwise_`) on a test block and its quarters refuses whole-image statistics, flips/shifts in Y/Z, row indices and `rand` before reading any data (see `bigdata_logic.md` §13b). Panel checked in the real window on a headless model: row 5 of 6, Open in / Output disabled for output `M`. Post-run reporting moved to `BigDataOptions.reportStoreResult` / `reportModelResult`, now shared with `Filter.m`. Test fixture moved to `mibtest.helpers.buildBigDataModel` / `attachBigDataLabels`. Side fix in the user docs: the examples used the MIB2 order `I(:,:,2,:)` for the channel; MIB3 is `[y x z color]` |
| 6. Global statistics group | done 2026-11-06 (my design, to review): `utils.bigdata.sampleStripes` / `sliceHistograms` - stripes of whole chunk rows, evenly spaced, same rows in every slice, 256 MB budget, at least 16 stripes, exact when the level fits (see `bigdata_logic.md` §13b). `FilteredSliceProvider` passes the slice index to a `(block, z)` function. Uses: **Global thresholding** (all 12 algorithms into mask / selection, bit-exact with Standard in exact mode, 16-bit scaling as Standard, Preview off on BigData); **Normalize layers** Z stack into a new store (`normalizeBigData.m`; Masked area / Background / Time series refused); **Edge automatic threshold** for Sobel / Prewitt / Roberts / LoG, equal to `edge` per slice. `BigDataOptions` gained `resolveLevel`, `checkModelOutput`, static `reportError`. Not done: CLAHE (ask the user), Canny (hysteresis) |
| 7. MorphOps on the image, White balance | done 2026-11-06 (my scope, to review): MorphOps - the six strel operations in 2D mode into a new store, halos from the strel height (see `bigdata_logic.md` §13b), Preview off on BigData; reconstruction-based ones and 3D refused. White balance - manual white only, into a new store; selection / mask white, Detect and Correct current refused, and disabled in the GUI on BigData. Side fix: the Virtual guard of White balance called `closeWindow` in batch mode, where there is no window |
| 8. "2D, Slice" with Current overwrite, panel component | done 2026-11-07, user decisions: "2D, Slice" is offered for Current overwrite (the open dataset), never for a new store; the slice is written **into** the store (option b, not a rewrite of the whole stack). `BigDataOptions.overwriteSlice`: step 1 processes the slice into a temporary zarr array (cancelable), step 2 writes it into s0 and rebuilds that slice in every coarser level with `Zarr3Saver.buildLevelBand` (bilinear, as the saver), not cancelable (the dialog says so; Cancel is checked before it). Only stores of the MIB layout (`yxz` / `yxzc`, levels halving XY, Z factor 1 or 2); a one-slice dataset takes the whole-store path. Test `overwriteOfTheShownSlice`: every level bit-exact with a store saved from the expected volume, XY-only 2 channels in one band, and anisotropic in 64-row bands. **Panel component**: `views.components.BigDataOutput.mlapp` (made by the user, 2026-11-07) is now the only panel: `attach` inserts it in every tool (Image filters, MorphOps, Global thresholding, Normalize layers, Image arithmetics, White balance), the row takes its designed height (89 px, read from an unparented instance), the component itself is created in the window (unparented, its panel title took the figure defaults, 8 points; the font preference in points then made it 16 px). The code-built widgets, the `PanelComponent` trial flag and the designed-panel path (`bindDesignedPanel`, `showDesignedPanel`) are removed; the user removed the hand-placed panel from `ImageFiltersGUI.mlapp`. `utils.fontSizeUpdate` takes a panel or grid of a uifigure through the App Designer branch. Checked headless in all six windows: row above the buttons, title 12 px like the window's panels, Open in change reaches BatchOpt, panel hidden and window shrunk for a Standard buffer. User request 2026-11-07: the component is created once and then hidden (row 0 px, Visible off, window shorter by 89 px) and shown again (`showPanel`), not deleted and rebuilt; a switch takes 0.15-0.25 s, mostly the waits of `resizeWindow` for a steady window position. Size label `260x300x3, 1 MB` (no spaces around x) |
| 9. Result to a Standard dataset in memory | done in code 2026-11-07, user decisions: a second dropdown **Result** (`BigData_Result`: `OME-Zarr store` / `Standard (in memory)`) rather than prefixed Open in items; a Standard result may replace the BigData dataset in its own buffer (`Current`, after a question). `BigDataOptions.runToStandard`: bands from `FilteredSliceProvider` into one `[H W Z C]` array, `MibDataset.initialize` as Standard with an empty labels63 model, voxel size of the level, bounding-box origin of the source, file name from the Output stem + `.tif`; refused above half of `memory().MemAvailableAllArrays` (image + 1 byte/voxel of model). Open in for a Standard result: `Current overwrite (BigData)`, `Current`, `Container N` (user 2026-11-07: the overwrite item renamed from `Current overwrite` and offered with either Result, where it always rewrites the store; no Do not open; default first empty container, else Current); Output disabled. Shared buffer reset moved from `openStoreInBuffer` to private static `showNewDataset`. Test `ImageFiltersBigDataTest/standardResultInMemory`. The user added the `BigData_Result` dropdown to `BigDataOutput.mlapp` (row 1, column 6, in `handles`), 2026-11-07. **Next:** a GUI check |
| 10. Region smaller than the dataset (Restrict to ROI) | done in code 2026-11-07, user decisions: the ROI only (no "shown view" option: draw a rectangle ROI over the view); a new store / Standard result is **cropped to the ROI box**; all three outputs honour it. Opt-in per tool, `BigDataOptions.RoiAware` (my decision, to review): only Image filters sets it, because on a Standard dataset only Image filters honour Restrict to ROI (Global thresholding, Normalize, arithmetics, MorphOps, White balance ignore it; the statistics tools would also take statistics from the whole dataset and write only the box). `regionOfInterest`: the ROI selected in the list or all XY ROIs (`selectedROI` 0), box = union of the ROI boxes mapped with `ceil(p / scale)`, shape drawn at the level inside the box only (vertices moved by `(p - 0.5) / scale + 0.5`, `RoiRegion.returnMask` on a temporary `RoiRegion`; a full-resolution mask of a slide would not fit); errors `noROI`, `roiOrientation`. `FilteredSliceProvider` options `Region` / `RegionMask`: halo read in X too (a 3-input, position-dependent function gets the full width and is cut), pixels outside a non-rectangular ROI keep the source (result must have the source class and channels, `regionMaskResult`). Store / Standard: bounding box starts at the box. Model: `setData63` over the box, the layer outside the shape read and written back. Current overwrite: `overwriteSlice` became `overwriteRegion` (slices x box; bands start on s0 chunk rows; coarser levels rebuilt over the reached rows, bilinear kernel +1 row, whole chunk rows, **full width**, as `buildLevelBand` takes no column range). The confirmation names the ROI, shows the box size and scales the estimate by the box area. Differs from Standard on purpose: Standard filters the cropped ROI without context (padded at the ROI edge), BigData reads the halo, so the box equals that part of a whole run. Tests `roiCropsTheStore`, `roiPolygonIntoMemory`, `roiOverwriteInPlace` (every level equals a reference store), `roiEdgesIntoTheSelection`, `roiIgnoredWhenUnchecked`. **Next:** GUI check (draw a ROI on a slide, check Restrict to ROI, Filter to a store, to memory, Current overwrite, Edge to selection) |
| 11. Resume in the GUI | done in code 2026-11-07, user request: on Cancel ask Keep / Delete, and say how to finish later. `BigDataOptions.run` (new store only; Current overwrite, model output and a Standard result write no store to resume): Cancel -> "Keep the unfinished result?" (Keep default; Delete removes the folder; headless deletes as before); a failed run keeps the store and its error says how to resume (`runFailed`). A kept or failed store gets `.mib_run_settings.mat` (`ResumeSettingsFile`) with the saver options of the run, because the saver resumes only with the same chunk / shard / level / codec settings and the Zarr settings dialog could give others; after a crash the file is missing and the source-derived defaults are used. A later run finding `.mib_resume.json` at its output path asks Resume / Start over / Cancel (headless `ResumeIncomplete`); Resume skips the run confirmation and the Zarr dialog. Other parameters: the saver's `cannotResume` is reported as `cannotResume` with a hint to Start over (fingerprints of all six tools carry their parameters; `processImageToStore` adds the ROI box). The settings file is deleted when the store completes. Test `resumeAfterAFailedRun` (source chunks of slice 3 corrupted, then restored; another sigma refused; result equals a whole run). The two questions are not tested headless. **Next:** GUI check (Cancel in the progress dialog, Keep, run again, Resume) |
| 12. Parallel processing (pool workers) | done in code 2026-11-07, user decisions: **all** filters (not only the slow ones), opt-in with the existing *use parallel* checkbox of Image filters (`BatchOpt.UseParallelComputing`), the open pool is used as it is (no start-up cost then). `FilteredSliceProvider.Source` is `Transient`; the provider keeps `SourcePath` and its first read on a worker reopens the store (`Zarr3VirtualSetupLoader` + `core.MibBigDataImage`), so a guide reader captured by a band function is reopened the same way and the constructor's probe is not repeated. `BigDataOptions.startPool` (private): `gcp('nocreate')`, else `parpool(cpuParallelLimit)` with a cancelable "Starting a parallel pool" dialog; a thread pool is refused (`threadPool`); `io.zarr.pinNativeLibrary` on every worker; an `onCleanup` clears the chunk cache of every worker after the run (an overwrite changes chunks without changing their cache keys). New store and the whole-store overwrite: `processImageToStore` option `Pool` -> `saveStreamResumable` (read, compute and write on the workers). Model, Standard result and step 1 of `overwriteRegion`: private `processBands` computes the bands on the workers (`parfeval` of the hidden static `workerBandRows`, at most 2 x workers in flight, results in finishing order) and the client writes them; a band error is raised with the worker's identifier (`fetchNext` wraps it in `MATLAB:parallel:future:FetchNextFutureErrored`, and `rethrow` refuses the `ParallelException`, so a new `MException` is thrown). `confirmRun` says "on the N workers of the open pool" or "a pool of N workers is started first" (+15 s), and divides the computing part of the estimate by N. `Filter.m` `localReleaseGuide` frees the cached guide on every worker too. Tooltip of the checkbox updated; one bullet in `image-filters.md`. Test `tests/controllers/ImageFiltersBigDataParallelTest.m` 8/8 in `matlab -batch` (2 workers): new store, a band function that marks where it ran (1 on a worker) in a store and in memory, LocalContrast / FastLocalLaplacian (guide), NonLocalMeans with an estimated DegreeOfSmoothing, 3D Gaussian equal to the client store, Edge into the selection, Standard result, whole and ROI overwrite (a second run reads the new pixels), the error of a band. **Next:** GUI check, and a timing on a real slide with 4-8 workers (gain measured only as compute shares so far) |
| 12b. Start and stop the pool from the ribbon | done in code 2026-11-09, user decision: checkable **Parallel pool** entry in Home ribbon -> Preferences, under "Preferences tools" (not in Development, which is reserved for developer items). `MibRibbon.homeUpdateParallelPool` (`DynamicPopupFcn` of the Preferences split button) reads `gcp('nocreate')` each time the menu opens and sets the tick and the description, because tools and the idle timeout change the pool without the entry; without Parallel Computing Toolbox the entry is disabled. `home_Callbacks` case `Parallel pool`: tick -> `parpool(cpuParallelLimit)` with a cancelable dialog (Cancel is honoured once `parpool` returns, then the pool is deleted); clear -> `delete(pool)`, refused while `pool.Busy`, which is true for `parfeval` and `parfor` of every tool, so no busy flag was needed. An open pool keeps its worker count. The thread-pool refusal of `BigDataOptions.startPool` now names this entry (the compiled app has no command window). Checked in `matlab -batch` with the real `MibRibbon` and toolstrip events (`qeValueChanged`) on a real 2-worker pool: start, refusal while busy with the job still running, stop, failed start. Not checked: the menu in a real window, Cancel in the start dialog. **Next:** GUI check |
| 13. Resample (Dataset ribbon) | done in code 2026-11-13, user decisions: the panel's Level is the level read, and the window's current size, voxel size and percentages are those of the level (`ResampleDataset.readCurrentSize`, refreshed through the new `BigDataOptions.LevelChangedFcn`); image only, the model is not resampled (Labels dropdown disabled); `imresize` function only, methods `ResampleDataset.BigDataMethods` (no spline, osc; interpn / tformarray refused, `controllers:ResampleDataset:bigData`); "Current overwrite (BigData)" refused (`BigDataOptions:resampleOverwrite`). New `io.savers.ResampledSliceProvider`: imresize's contributions built once per axis (sparse, transposed), applied to the rows of a band in imresize's pass order (smallest scale first) with a cast to the class after every pass. Measured against `imresize3` / `imresize` (uint8, 7 kernels x 5 sizes, scratch `resampleWeightsCheck.m`): with the per-pass cast 0 grey levels except linear / triangle (1); rounding only at the end gave up to 29 (cubic), 52 (lanczos3). In the test on the smooth synthetic volume cubic also had a few voxels 1 off (rounding ties, MEX summation order), so the test allows 1 on < 0.1 %. Pooling as `resizeImage3d`, exact. `run` / `runToStandard` / `confirmRun` / `processImageToStore` take `Resample` (struct `OutputSize`, `Method`): voxel size = level voxel x `levelSize ./ OutputSize` (Standard keeps the box, `(N-1)/(n-1)`; under a voxel over the image), saver `Levels = []` (auto from the new size), fingerprint + `resample`; band rows from `provider.bandRows` (source rows under the kernel). Estimate: `estimateResampleSeconds`, two 32 MB bands of the provider, each read through one source chunk depth of slices (from `pyramid.chunkSizes` / `axisOrder`, capped at 128), workers not counted. First version probed one slice: the user got **5.4 days** for max pooling of a 270 GB s0 (10936 x 13424 x 1974) to 1822 x 2237 x 1974, because a one-slice read of a deep chunk decompresses the whole chunk, which the run reads once per slab through the chunk cache. Measured 2026-11-13 (3072 x 2560 x 64 uint8, scratch `resampleEstimateCheck*.m`), estimate / real run: old 1.5 (chunks 256x256x16), 21 (128x128x64), 46 (256x256x64); new 1.11, 1.47, 1.67, cubic 1.16, cubic with Z halved 2.06. Pooling itself costs nothing measurable (reshape + max on a band). Same flaw, not fixed: `estimateRunSeconds` (Image filters etc.) also probes one slice, and takes `chunkSizes{level}(1:2)` as [y x], which holds for MIB's `yxz` stores but not for `zyx` ones. `BigDataOptions.setResultSize` makes the size label show the target; refreshed only while the panel is shown (a Standard buffer has no levels - found by the window check). `ResampleDataset.BatchOpt` gained `id` and the BigData_* fields. Not done: parallel (Resample has no *use parallel* checkbox, so `startPool` returns none), resampling the model store, ROI. Z resampled: each source slice is read by ~4 output slices (cubic), served by the chunk cache, not measured on a real stack. Tests `tests/controllers/ResampleDatasetBigDataTest.m` 8/8 (`-batch`, R2026a), with `ProcessImageToStoreTest`, `ImageFiltersBigDataTest`, `ImageArithmeticsBigDataTest` 57/58 (bm3d skipped, no BM3D on the path). Window checked in `-batch` (script `resampleGuiCheck.m`, scratch): panel row 3 of 4, window 415 -> 499 px, lists switch, level s1 -> 130 x 150 and 0.04 um, DimensionX 65 -> label `65x75x3`, Standard buffer hides it and restores the Standard lists. **Next:** GUI check in a running MIB (a real slide shrunk from s0 and from a coarser level, a Z stack with Z resampled, Standard result, Cancel and Resume) |
| Fixes found by the measurement (2026-11-07) | `Zarr3Saver.computeShard` clamps the shard to the array rounded up to whole chunks (a `ShardSize` given in voxels by mistake asked zarrMex for a 1 TiB shard and aborted MATLAB); `Zarr3VirtualSetupLoader` shows its error dialogs only with a `ParentFigure` (the error paths read `obj.Options.ParentFigure`, absent without one, and reported "Unrecognized field name" instead of the reason). Checked in `-batch`: the crash cases save and read back, a broken store reports the real reason; `Zarr3Saver*Test`, `OmeZarr*Test` 73 passed, 2 skipped by assumption |
| Tests | 2026-11-07 after step 12, all in `matlab -batch`: `ImageFiltersBigDataParallelTest` 8/8 and the nine BigData classes (`ImageFiltersBigDataTest`, `MorphOpsImagesBigDataTest`, `GlobalThresholdingBigDataTest`, `WhiteBalanceBigDataTest`, `ContrastNormalizationBigDataTest`, `ImageArithmeticsBigDataTest`, `AlignmentBigDataTest`, `ProcessImageToStoreTest`, `SampleStripesTest`) 91/91 with BM3D on the path. Earlier: `ImageFiltersBigDataTest` 33/33 (2026-11-07, BM3D on the path; 1 incomplete without it), `SampleStripesTest` 8/8, `ImageArithmeticsBigDataTest` 10/10, `ImageArithmeticsTest` 4/4, `GlobalThresholdingBigDataTest` 5/5, `ContrastNormalizationBigDataTest` 4/4, `ProcessImageToStoreTest` 7/7, `MorphOpsImagesBigDataTest` 6/6, `WhiteBalanceBigDataTest` 3/3 (2026-11-06); `AlignmentBigDataTest` 14/14 (earlier on 2026-11-06) |
| **GUI checks in a running MIB** - tested by the user, 2026-11-07 (list kept for reference) | Filter button on a real BigData slide; the whole-slice filters on a real slide (time of the guide and sampled passes, look of LocalContrast / ReduceHaze from a coarser level), BMxD on a real slide; the run confirmation with its time estimate (`BigDataOptions.confirmRun`, 2026-11-07: checked headless with a stand-in uiconfirm; Cancel in the "Estimating" dialog; estimate vs real time on a multi-GB slide over the network); Dataset type without "2D, Slice" in Image filters and MorphOps on a BigData buffer, back with Open in "Current overwrite" (2026-11-07; then the shown slice is written into the store: check the two-step progress dialog, Cancel in step 1, the view after the run), with a binarization filter or a Standard buffer (`BigDataOptions.updateDatasetType`, 2026-11-07; headless refusal `checkWholeDatasetType` tested); Cancel in the progress dialog (store and model); the overwrite confirmation and the locked notice after the pixSize fix; the binarization panel switch, confirmation and info dialog; Image Arithmetics on a real slide (store and `M = I > ...`), its panel on switching buffers, and a refusal dialog; Global thresholding and Normalize layers windows on a BigData buffer (panel placement, Preview disabled, statistics progress dialog and its Cancel); Edge with an empty threshold on a real slide; **time of the statistics pass on a multi-GB level** (only synthetic levels that fit the budget were run); MorphOps and White balance on a real slide (panel placement and enable states were checked on a headless model only; MorphOps now shows the `BigDataOutput` component: placement, window height, the Select button with its icon); "2D, Slice" into the model (Edge, Global thresholding) on a real slide: only the shown slice changes, and the confirmation names it (fixed 2026-11-06 after the user's GUI test: `runToModel` and the statistics pass take `Slices`, `BigDataOptions.levelSlices` maps the shown slice to the level, a view other than XY is refused; tests `edgesOnTheShownSliceOnly`, `twoDSliceThresholdsTheShownSlice`, `slicesSampleOnlyThoseSlices`. Filtering into a new store still processes the whole dataset); Image filters Preview on BigData at several zooms (fixed 2026-11-06, headless only: Color channel "All" failed in `getDataZarr` with a negative channel index, channel code 0 is now "all" as in `MibImage.getData`; the binarization preview read the colour image at full resolution, now at the display resolution of the filtered block) |

### Resume here (state 2026-11-07)

Nothing of steps 1-12 is committed (the user commits). Files of this work:
`mib/+controllers/@BigDataOptions/BigDataOptions.m`, `mib/+views/+components/BigDataOutput.mlapp`
(the panel, made by the user), `mib/+utils/fontSizeUpdate.m` (panel / grid input),
`mib/+views/ImageFiltersGUI.mlapp` (hand-placed panel removed by the user), `mib/+io/+savers/FilteredSliceProvider.m`,
`mib/+utils/+bigdata/{processImageToStore,isSameStorePath,sampleStripes,sliceHistograms}.m`,
`mib/+controllers/@ImageFilters/{ImageFilters,Filter}.m`,
`mib/+controllers/@ImageArithmetics/ImageArithmetics.m`,
`mib/+controllers/@GlobalThresholding/GlobalThresholding.m`,
`mib/+controllers/@ContrastNormalization/{ContrastNormalization,continueBtn_Callback,normalizeBigData}.m`,
`mib/+controllers/@MorphOpsImages/{MorphOpsImages,Calculate}.m`, `mib/+controllers/@WhiteBalance/WhiteBalance.m`,
`tests/controllers/{MorphOpsImagesBigDataTest,WhiteBalanceBigDataTest}.m`,
`docs/docs/user-interface/ribbon/image/{image-morphops,image-tools-whitebalance}.md`,
`mib/+controllers/@Alignment/{Alignment,continueBtn_Callback}.m` (s0 items),
`tests/controllers/{ImageFiltersBigDataTest,ImageArithmeticsBigDataTest,ImageArithmeticsTest,GlobalThresholdingBigDataTest,ContrastNormalizationBigDataTest}.m`,
`tests/+mibtest/+helpers/{buildBigDataModel,attachBigDataLabels}.m`,
`tests/utils/{ProcessImageToStoreTest,SampleStripesTest}.m`, `tests/controllers/ImageFiltersBigDataParallelTest.m`, `mib/+io/+savers/Zarr3Saver.m` (`computeShard`), `mib/+io/+loaders/Zarr3VirtualSetupLoader.m` (error dialogs), `mib/+controllers/@MibRibbon/{MibRibbon,home_Callbacks,homeUpdateParallelPool}.m`, `mib/+views/@MibView/addRibbonHome.m` (Parallel pool entry),
`mib/+io/+savers/ResampledSliceProvider.m`, `mib/+controllers/@ResampleDataset/ResampleDataset.m`,
`tests/controllers/ResampleDatasetBigDataTest.m`, `docs/docs/user-interface/ribbon/dataset/dataset-resample.md`,
`docs_api/source/api/io/savers/ResampledSliceProvider.rst` (Resample, step 13); docs
`docs/docs/user-interface/ribbon/image/{image-filters,image-tools-arithmetic,normalize}.md`,
`docs/docs/user-interface/ribbon/tools/tools-globalthres.md` (BigData sections),
`docs/docs/getting-started/dataset-types/index.md`,
`docs/docs/user-interface/ribbon/dataset/dataset-alignment.md`, `docs_api/source/api/...`
(BigDataOptions, FilteredSliceProvider, utils.bigdata), `bigdata_logic.md` §13b.

Where things are: `BigDataOptions.run` (new store / Current / Current overwrite ->
`runOverwrite` + `replaceImage`), `BigDataOptions.runToModel` (mask / selection),
`BigDataOptions.reportStoreResult` / `reportModelResult` (after a run);
`Filter.m` local functions `localFilterBigData`, `localBinarizeBigData`, `localFilterHalo`,
`localFilterBlock`, `localEdgeBlock`, `localReportError` (headless -> error);
`ImageArithmetics` private `runExpressionBigData_`, `checkBandwise_`, `parseVariables_`,
`reportError_`, hidden static `evaluateBand_`; `GlobalThresholding` private `applyBigData_`,
`thresholdFromCounts_`, hidden static `binarizeBand_`; `ContrastNormalization.normalizeBigData`;
`Filter.m` `localEdgeThresholds`, `localGradientEnergy` (automatic Edge threshold).

Next, in the order of the plan (ask the user which one):
1. ~~GUI check~~ of the items in "GUI checks in a running MIB" above: tested by the user, 2026-11-07.
2. ~~Global statistics group~~ done (step 6). User decisions 2026-11-06: CLAHE skipped for now;
   the sampling budget stays fixed (256 MB, no widget); the statistics always come from the level
   the user chose to process, never from a coarser one (a coarse level is smoothed, so its
   statistics differ from full resolution) - as implemented.
3. ~~Image arithmetics~~ done. Open: inputs from other BigData buffers of the same level size and
   the mask / selection as input (band-aligned reads), output into the model labels (`O`).
4. ~~MorphOps on the image, White balance~~ done (step 7). Open: White balance with the white from
   the selection / mask (a statistics pass reading the image and the model labels band-aligned),
   and Detect from the shown view. User 2026-11-07: skipped for now.
5. Open items of the engine and panel: ~~output to a Standard buffer~~ (step 9), ~~a
   region smaller than the whole dataset~~ (step 10, Restrict to ROI in Image filters), ~~Resume in the GUI~~ (step 11), ~~pool workers~~ (step 12), Alignment and Crop moved to `BigDataOptions` (now also onto the `BigDataOutput`
   component, so all BigData dialogs share one panel).
6. Offered, not decided: an "Update finer levels" checkbox for model output that runs
   `materializeAll` after a coarse binarization.

### Parallel processing: measurements (2026-11-07)

Question: would pool workers (each band processed on a worker) pay off? Measured in a separate
`matlab -batch` (R2026a, 24 logical cores, local SSD, `C:\HyApp`), scripts
`measureParallelGain.m` / `poolZarrCheck.m` (session scratchpad, not in the repo).

**Method.** A real Image filters run into a new store (`controllers.ImageFilters`, batch path, level
s0, defaults of each filter, after a warm-up run) against an identity run of the same engine
(`processImageToStore` with `@(block) block`: read, write, pyramid, no computing; best of two after a
warm-up). Compute share = (filter - identity) / filter, the part a pool could split.

| Filter | real crop 887 x 813 x 16 (chunks 128x128x16, shards 4x4x1) | | synthetic 4096 x 4096 x 4 (chunks 256x256x1) | |
|---|---|---|---|---|
| | s per slice | compute share | s per slice | compute share |
| identity (engine only) | 0.013 | - | 0.47 | - |
| Gaussian | 0.02 | 48 % | 0.56 | 16 % |
| Median | 0.02 | 42 % | 0.69 | 32 % |
| Bilateral | 0.02 | 32 % | 0.59 | 20 % |
| NonLocalMeans | 0.21 | 94 % | 5.0 | 91 % |
| LocalContrast | 0.13 | 90 % | 5.0 | 91 % |
| FastLocalLaplacian | 0.25 | 95 % | 9.5 | 95 % |
| BMxD (BM3D 4.0.3) | 1.26 | 99 % | 26.5 | 98 % |

Scaled to a 50k x 50k slide (149 x the synthetic slice): BMxD about 66 min per slice, FastLocalLaplacian
24 min, NonLocalMeans and LocalContrast 12 min, Gaussian / Median under 2 min (mostly reading and
writing; on a network share the compute share of these is lower still).

**Expected gain** (Amdahl, `1 / ((1 - p) + p / N)`): compute share 0.95 -> 3.5x with 4 workers,
5.9x with 8; 0.2 -> 1.2x with 8. BM3D and some IPT functions already use several threads, so the real
gain of BMxD can be well below that; to be measured with a pool.

**zarrMex on workers** (4 process workers): pool start 15 s; `io.zarr.pinNativeLibrary` on the workers
0.8 s; each worker opening the store itself and reading bands works (sums equal the client read);
pool closed in 2.7 s and MATLAB exited cleanly, no crash event in the Windows log.

**Conclusion (2026-11-07):** worth it mostly for the compute-heavy filters (NonLocalMeans,
LocalContrast, FastLocalLaplacian, BMxD; probably AnisotropicDiffusion and Wiener too), not for the
cheap ones. User decision: all filters (they share one path), opt-in through the existing *use parallel* checkbox of Image
filters (`BatchOpt.UseParallelComputing`, now used for Standard 2D filters only), a provider rebuilt
on each worker from the store path, `saveStreamResumable` with a pool (it already takes one), the 15 s
pool start counted in the estimate of `confirmRun`, and the filters that carry a guide (whole-slice
filters) checked for the copy of the guide to every worker.

**Incident during the measurement.** The first try ran in the MCP session (the user's MATLAB) and
crashed it: `zarrMex.mexw64`, `0xc0000409`, after Rust's "memory allocation of 1099511627776 bytes
failed". Cause: my script passed `ShardSize = [512 512 16]` as voxels, but `Zarr3Saver` takes it in
**chunks per shard**, so the shard was 65536 x 65536 x 256 = 1 TiB. Reproduced in `-batch` for any
multi-slice chunk with that `ShardSize` (a one-slice chunk gave a 4 GB shard and survived). Not a
zarrMex bug in the sense of wrong output, but zarrMex aborts the process on a failed allocation instead
of raising an error. Guard added the same day (step 12 row): `Zarr3Saver.computeShard` clamps the shard to the array
size rounded up to whole chunks. Also found: the error paths of
`io.loaders.Zarr3VirtualSetupLoader` (lines 140, 172, 430, 717) read `obj.Options.ParentFigure`, which
`BigDataOptions.openStoreInBuffer` does not pass, so a store that fails to open reports "Unrecognized
field name ParentFigure" instead of the real reason (fixed the same day).

### Engine notes (2026-11-06)

- **Bands, not slices.** `saveStreamResumable` with `BandHeight` asks the provider for
  `getSliceRows(z, first, last)` across the full width, so the halo is needed in Y only (and in Z for
  3D functions). The band height is sized from `BandBytes` (default 256 MB, 8 bytes per element for a
  filter working in double) and rounded by the saver to whole chunk rows.
- **Level rows -> `getData` coordinates.** `getData` maps full-resolution `y` to a level with
  `ceil(y / scale)`; level rows `a..b` are requested as `(a-1)*scale+1 .. b*scale`, exact for any
  scale >= 1.
- **Proof of the halo.** A Gaussian (sigma 2, halo 6) in 64-row bands equals `imgaussfilt` of the
  whole slice bit for bit; the same with halo 0 differs. A 3D Gaussian with `HaloZ = 2` equals
  `imgaussfilt3` of the whole volume.
- **Integer output only.** MIB images are integer (a float source is converted at loading), and
  `MibVirtualImage.initialize` calls `intmax` on the class, so a float store cannot be opened.
  `processImageToStore` refuses a non-uint result before writing (`utils:bigdata:outputClass`).
  Side finding: the zarr savers pass `class(data)` to `createArray`, and zarrMex refuses `single` /
  `double` (it wants `float32` / `float64`), so no MIB saver can write a float zarr store today.
- **No pool yet.** The provider holds the image handle with its open readers. Running it on pool
  workers needs a provider that reopens the store from its path on the worker.
- **Resume** goes through `saveStreamResumable`; the fingerprint includes `func2str` of the block
  function and the caller's `Fingerprint`, because an anonymous function's captured values are not
  in `func2str`. Not covered by a test yet, and not offered in the GUI: a cancelled run deletes its
  partial store.

### Panel notes (2026-11-06)

- **Grid insertion order.** Set `RowHeight` first, then move the children down: a child placed past
  the last row makes the grid add a `'1x'` row of its own (the first try produced
  `{'2x' 90 140 25 80 '1x'}`). Removal is the reverse: children up first, then the row.
- **Window resize is asynchronous** (see `bigdata_logic.md` §13b): `resizeWindow` waits for a steady
  position and re-sets until the size holds; about 0.1 s.
- **Not in `view.handles`.** `utils.updateGUIFromBatchOpt_Shared` finds App Designer widgets as
  properties of the app object, so widgets made in code are invisible to it; the panel syncs its own.
- **Filter halo** (`Filter.m`, `localFilterHalo`): half the filter support, rounded up, from the
  filter's own size field (`HSize`, `Radius`, `Length`, `NeighborhoodSize`, `FiltSize`; 3 for
  Prewitt/Sobel/Gradient). `circular` padding is refused (a band cannot see the far side). Gaussian
  with `FilterDomain = 'auto'` may choose the frequency domain for a whole slice and the spatial one
  for a band, which can change a value by rounding; the tests use sizes up to 7, where both are spatial.
