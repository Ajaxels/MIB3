# Image Stitching Tool for MIB3 — Implementation Plan

## Status (2026-07-11)

**Phase 1 implemented and end-to-end verified.** 42/42 tests pass (`tests\utils\StitchLayoutTest.m` 23, `tests\utils\StitchCoreTest.m` 19 incl. zarr→BigData Integration round-trip and a full-chain ground-truth regression test). `StitchingGUI.mlapp` built in App Designer (all 30 widget tags verified; figure property must be named `Figure` — `core.ChildView` detects App Designer apps by `isprop(gui,'Figure')` and auto-copies component names into Tags). Ground-truth smoke test (3×3 jittered+border-clamped grid through the batch controller): measured edges within 0.05 px, solved positions max 0.75 / mean 0.19 px, fused mosaic interior RMSE 5.1 gray on a std-22.5 image, 0.9 s.

### Post-build fixes (parallel-agent seams + registration debugging)

*Controller seams:* lowercase option fields (`qualityThreshold`, `springWeight`, `subpixel`); `fuseInMemory(layout, canvas, options)` / `fuseStreaming(layout, canvas, outputZarrPath, options)` create their own tile reader; RMSE display uses `stats.rmseTotal` (`stats.rmse` is 1×3 per-axis); BigData reopen mirrors `applyAlignmentBigData.m:357-374` incl. slices reset; `uiputfile` two-output form; duplicate inline methods removed from `Stitching.m` (were shadowing the richer separate files); batch path now runs the full pipeline via new `buildLayoutFromBatchOpt.m` + auto measure/solve inside `stitchBtn_Callback` (previously fused at nominal positions without registration).

*Registration bugs found by the ground-truth smoke test (all invisible to solver-only unit tests):*
1. **Sign flip** — with crops at nominally-corresponding windows, `cropB(r)=cropA(r−dy)` ⇒ correction is **−dy**; `measureOne` composed `nominal + shift`. Now: `measured = (bboxA(:,1) − bboxB(:,1)) − [dy dx]`, exact under asymmetric border clamping.
2. **Search window destroyed** — `computeOverlapRegion` clamped the expanded window to the intersection of both tiles, clipping the entire ±expandPx for edge-abutting pairs. Now clamps each crop to its OWN tile only (starts preserved; composition above compensates).
3. **FFT circular aliasing** — border-clamped pairs need raw shifts ≈ −expandPx, outside ±extent/2; peaks aliased by +extent. Fixed with zero-padding (`padPx`) + expected-shift-restricted peak search (`expectedShift`/`searchRadius` options in `pairwiseShift`).
4. **Quality metric** — PSR barely separated true matches (min 5.6) from independent noise (6.5). Replaced with peak-to-second-peak ratio inside the search region (exclusion lobe rWin=17): true pairs ≥0.94 median, noise/flat 0.00. Mapping `(ratio−1.35)/0.65`. Calibration probe: `temp\stitch_smoke\psrProbe.m`.
5. **Adaptive expansion** — `expandPx` per pair capped at `0.75 × overlap extent` (over-expanding fills crops with unshared content, starving the peak).
6. **Diagonal pairs excluded** — `findNeighborPairs` now requires perpendicular overlap ≥50% of tile extent; corner overlaps produced confident-but-wrong shifts and add no information over direct x/y edges.
7. **Solver springs** — pruned-edge nominal springs only added when they restore connectivity to the anchor; between well-connected tiles they only biased the solution toward nominal.
8. `views.StitchingGUI` added to the compiler force-include block in `mib3.m`.

`pairwiseShift` sign convention (load-bearing): if `cropB(r,c) ≈ cropA(r−dy, c−dx)` then `shiftYXZ = [dy dx 0]`; tile displacement composition (with the negation) lives in `measureAllPairs/measureOne`.

**Open items:**
1. ~~GUI click-through test in live MIB~~ **DONE 2026-07-14** (user-verified with 15% and wrong-guess overlaps + estimation).
2. ~~Dedicated `stitch_24px.png` icon~~ **DONE 2026-07-14**.
3. ~~User docs (`docs/`) + RST API entries (`docs_api/`)~~ **DONE 2026-07-14** (`docs/docs/user-interface/ribbon/dataset/dataset-stitch.md` + index entry + nav; RST API entries).
4. `fuseStreaming` chunk-wise fallback (slice > maxSliceBytes) untested against a real huge-slice case.
5. T>1: reader returns first time point only (fine for Phase 1).
6. ~~`buildLayoutPositionFile` uses `java.io.File.isAbsolute()`~~ **DONE 2026-07-14** — replaced with pure-MATLAB regex check (`isAbsolutePath` local function: drive roots, UNC, POSIX).

## Context

MIB3 has no tool to stitch a collection of 2D image tiles into a mosaic. The user's existing panorama script (`c:\MATLAB\Data\Panorama_stitching\FeatureBasedPanoramicImageStitchingExample.m`) does sequential pairwise chaining — fine for camera sweeps, unstable for microscopy tile grids. The new tool stitches tiles from rough initial positions (grid arrangement, coordinate text file, later interactive placement), refines them by pairwise registration, and solves **one global optimization** so that for 3D data the within-layer (2D) and between-layer (Z) constraints are jointly minimized (MIST/BigStitcher approach — *not* "stitch 2D, then align 3D").

**Confirmed decisions:**
- **Streaming from day 1** — mosaics routinely exceed RAM; fusion writes chunk-wise to OME-Zarr (BigData), opened back into MIB as a BigData dataset. In-memory fast path for small jobs.
- **Translation-only registration first** (phase correlation on overlap regions + global weighted least squares); rigid/affine as later options.
- **3D = one global solve** over the whole tile graph: within-layer edges + adjacent-layer edges in the same sparse LS system, quality-weighted, with weak "spring" edges to nominal positions as fallback (two-round MIST).
- v1 layout inputs: (a) grid dialog (H/V, line-by-line/snake, overlap %), (b) position file `filename X Y [Z]` (space/tab/comma), plus (c) MIB2 `_Z##-X##-Y##` filename pattern as a cheap win. 3D tiles: one subfolder per tile Z-stack, or Z column in the position file (layers auto-created per distinct Z).
- Later phases: interactive rough-placement canvas; QC/seam checker with manual nudge + re-fuse.
- Tile layout/transforms persist to a sidecar project file (JSON) for reproducibility and the checker.

## Model recommendation per phase

| Work item | Recommended model | Why |
|-----------|-------------------|-----|
| Phase 1 algorithmic core: `pairwiseShift`, `solveGlobalLeastSquares`, `planCanvas`, `fuseStreaming`, `StitchSliceProvider` | **Opus 4.8** | Numerically subtle (FFT peak quality, sparse weighted LS with gauge fixing/springs, chunk-boundary blending). Bugs here are silent and expensive to find later. |
| Phase 1 scaffolding: `@Stitching` controller, `StitchingGUI.mlapp`, ribbon wiring, BatchOpt, layout builders/parsers, `saveProject`/`loadProject` | **Sonnet** | Pure pattern-following against ResampleDataset/CLAUDE.md conventions and simple parsing; well within Sonnet's range, much cheaper. |
| Phase 1 unit tests (`tests\utils\StitchTest.m`) | **Sonnet** | Mechanical once the synthetic `chopIntoTiles` spec is written; conventions documented in `tests\plan_unittests.md`. |
| Phase 2 — 3D joint solve extension (z-edges, cross-layer correlation, Z-aware fusion) | **Opus 4.8** | Extends the solver's math and the streaming fuser; the hardest correctness surface of the project. |
| Phase 3 — interactive rough placement | **Sonnet** | UI work with existing `images.roi.Rectangle` precedents (CropDataset, MeasureTool). |
| Phase 4 — QC/seam checker + re-fuse | **Sonnet**, escalate to Opus 4.8 only if re-fusion integration misbehaves | Mostly UI + reuse of `loadProject`/fusers. |

Rule of thumb: anything touching `solveGlobalLeastSquares` or `fuseStreaming` internals → Opus 4.8; everything else → Sonnet.

## Verified reusable infrastructure

| What | Where |
|------|-------|
| Streaming zarr writer, pyramid plan, bbox metadata | `mib\+io\+savers\Zarr3Saver.m` — `saveStream` (:280), `computeLevelPlan` (:792), `patchMetadata` (:862) |
| Chunk-region zarr writes | `io.zarr.Group.create` / `createArray` / `Array.write(data, bbox)` (`mib\+io\+zarr\Array.m:71`) |
| Slice provider base for saveStream | `mib\+io\+savers\SliceProvider.m` |
| **Write-zarr → reopen-as-BigData recipe** | `mib\+controllers\@Alignment\applyAlignmentBigData.m:352-362`: `patchMetadata` → `io.loaders.Zarr3VirtualSetupLoader(struct('datasetMode','BigData'))` → `loadMetadata`/`loadImages` → `I{id}.initialize(img, imgInfo, 'BigData')` → `notify('NewDataset')` |
| In-memory dataset creation | `mib\+controllers\@ChunkingImport\ChunkingImport.m:448-453`: `core.MibImage.initializeImgInfo(...)` + `core.MibDataset(imgOut, imgMeta, 'Standard', ...)` |
| Any-format tile reader → [H W D C T] | `io.loadImagesWrapper(filename, opts)` |
| Phase-correlation math to adapt | `utils.align.calcShifts` (full-frame; write overlap-aware variant) |
| Feature detectors + estGeomTransform opts (later rigid/affine) | `utils.align.detectFeatures`, `@Alignment\Alignment.m` `defaultAutomaticOptions` (~:490) |
| Controller scaffolding template | `mib\+controllers\@ResampleDataset\` (ChildView, BatchOpt, batch dispatch via `nargin==3` struct/NaN) |
| Ribbon wiring | `mib\+views\@MibView\addRibbonDataset.m` (~:49, next to Alignment button) + `mib\+controllers\@MibRibbon\dataset_Callbacks.m` (~:26 `startController` case) + callback attach in `MibRibbon.m` |
| Interactive rect dragging (Phase 3) | `@CropDataset`, `@MeasureTool\drawROI.m` (`images.roi.Rectangle`) |
| Parallel progress | `core.PoolWaitbar`; sequential `uiprogressdlg` |
| MIB2 filename-grid parser to port | `C:\Matlab\MIB2\Classes\@mibRechopDatasetController` (lines ~175-231) |

## Module layout

### Computational core — `mib\+utils\+stitch\` (controller-independent, headless-testable)

| File | Purpose |
|------|---------|
| `buildLayoutGrid.m` | Grid layout: rows/cols (0=auto), order H/HSnake/V/VSnake, overlap % → nominal origins; natural-sorted files |
| `buildLayoutPositionFile.m` | Parse `filename X Y [Z]`, auto delimiter; Z-layers per distinct Z; subfolder mode = one Z-stack tile per subfolder |
| `buildLayoutFilenamePattern.m` | `_Z##-X##-Y##` grid tokens (MIB2 rechop port) |
| `naturalSortFiles.m` | Natural sort helper |
| `findNeighborPairs.m` | Overlapping pairs from nominal origins + sizes; tag `'x'`/`'y'` within-layer, `'z'` adjacent-layer |
| `computeOverlapRegion.m` | Pixel sub-rectangles of nominal overlap (for PixelRegion sub-reads / crops) |
| `pairwiseShift.m` | Windowed FFT phase correlation on two overlap crops → `[dy dx dz]` + quality (normalized peak height) |
| `measureAllPairs.m` | Loop pairs → edge list; `readerFcn` wraps `loadImagesWrapper` + LRU cache; parfor + PoolWaitbar |
| `solveGlobalLeastSquares.m` | **One sparse weighted LS over the whole graph** (x, y, z as independent block systems); anchor tile 1; prune edges below quality threshold; round 2 re-adds pruned edges as weak springs to nominal offsets |
| `planCanvas.m` | Output `[H W Z C T]`, per-tile integer placement + subpixel residual, physical bounding box |
| `fuseInMemory.m` | Fast path: allocate canvas, place tiles with blend mode → array for `core.MibDataset` |
| `fuseStreaming.m` | Primary path: iterate output chunks, load intersecting tiles (LRU), blend, `Array.write(block, bbox)`; pyramid via block downsample |
| `blendWeights.m` | Feather (linear distance ramp) weight map |
| `tileCacheLRU.m` | Bounded LRU tile cache around readerFcn |
| `saveProject.m` / `loadProject.m` | Sidecar JSON round-trip |

Plus `mib\+io\+savers\StitchSliceProvider.m` (`< io.savers.SliceProvider`) — composites tiles for output slice z, so fusion can delegate to `Zarr3Saver.saveStream` (full pyramid/sharding for free) whenever one output XY slice fits in RAM. `fuseStreaming` is the fallback when even a slice doesn't fit.

### Controller — `mib\+controllers\@Stitching\` + view `mib\+views\StitchingGUI.mlapp`

Standard child-controller set (`Stitching.m`, `addCallbacks.m`, `updateWidgets.m`, `updateBatchOptFromGUI.m`, `returnBatchOpt.m`, `closeWindow.m`, `helpBtn_Callback.m`) plus workflow callbacks:
- `selectInputBtn_Callback.m` — pick folder/subfolders/position file → build layout
- `previewLayoutBtn_Callback.m` — draw nominal tile rectangles/thumbnails on preview axes
- `measureOverlaps_Callback.m` — `measureAllPairs` with progress (button "Measure overlaps")
- `optimizePositions_Callback.m` — global solve + `planCanvas`; show RMSE/residual stats (button "Optimize positions")
- `stitchBtn_Callback.m` — fuse (in-memory → `core.MibDataset` | zarr → BigData reopen recipe); save sidecar; **single batch entry point**
- `saveProjectBtn_Callback.m` / `loadProjectBtn_Callback.m`

GUI groups: Input (LayoutSource dropdown, path pickers, SubfolderMode), Grid (Rows/Cols spinners 0=auto, TileOrder dropdown, OverlapX/Y), Registration (TransformType {Translation}, QualityThreshold, SpringWeight, Subpixel), Output (OutputMode {In memory, OME-Zarr (BigData)}, path, BlendMode {Feather, Average, Max, Overwrite}), preview axes, buttons, RMSE readout.

## Data structures

```matlab
% layout(i): .index .filename .sliceFiles{} .zLayer .gridRC [r c]
%            .nomOrigin [y x z] .tileSize [H W D C] .dataClass
% edges(k):  .i .j .direction 'x'|'y'|'z' .measured [dy dx dz]
%            .nominal [dy dx dz] .quality [0..1] .valid
```

Sidecar `<name>.mibstitch.json`: schemaVersion, layoutSource, pixSize, canvasSize, boundingBox, tiles (with `solvedOrigin`), edges, solver settings + RMSE, blend, output. `loadProject` restores everything; the checker later edits `solvedOrigin` and re-fuses.

## BatchOpt (MIB3 conventions)

`LayoutSource` {Grid, Position file, Filename pattern}; `InputPath`; `SubfolderMode` logical; `GridRows`/`GridCols` `{0,[0 10000],'on'}`; `TileOrder` dropdown; `OverlapX/Y` `{10,[0 90],'off'}`; `TransformType` {Translation}; `QualityThreshold` `{0.30,[0 1],'off'}`; `SpringWeight` `{0.10,[0 1],'off'}`; `Subpixel`; `OutputMode` dropdown; `OutputPath`; `BlendMode` dropdown; `SaveProject`; `showWaitbar`; `mibBatchSectionName = 'Ribbon -> Dataset'`. `BatchOpt.id = obj.mibModel.getActiveId()` at point of use. Batch dispatch identical to ResampleDataset.

## Phasing

**Phase 1 — 2D single layer (grid + position file + filename pattern; in-memory + zarr outputs)** — core: Opus 4.8; scaffolding/tests: Sonnet
All `utils.stitch` core (2D solve), `StitchSliceProvider`, controller + mlapp, ribbon button.
Existing files touched: `addRibbonDataset.m`, `dataset_Callbacks.m`, `MibRibbon.m`, new `stitch_24px.png` icon (reuse an existing icon until drawn).
Milestone: headless test — chop a known image into jittered overlapping tiles, layout→measure→solve→fuse, origins within ±1 px, RMSE below threshold; zarr round-trip read-back matches in-memory fuse.

**Phase 1.5 — robustness & input extensions** — **DONE 2026-07-14** (overlap estimation + feature-based registration + Bio-Formats source all landed; 26/26 core + 24/24 layout tests pass)
- ~~Overlap auto-estimation~~ **DONE 2026-07-14**: `utils.stitch.estimateOverlap` (MIST-style median over grid pairs; unrestricted full-tile phase correlation + top-K NCC peak verification, BigStitcher-style) + `@Stitching\runOverlapEstimation.m`, `BatchOpt.EstimateOverlap` (default true), `EstimateOverlap` checkbox in Grid panel. See Status log for the two full-tile findings (NO Hann window; opposite sign composition vs crop path).
- ~~**Feature-based registration option**~~ **DONE 2026-07-14** — `utils.stitch.featureShift` (SURF detect/match + `estgeotform2d 'translation'`, RANSAC inlier-ratio quality, SAME sign convention as `pairwiseShift`); `measureAllPairs` gains `options.registrationMethod` {Phase correlation, Feature-based} + a `shiftFcn` threaded through `measureOne`/`measureZShift`. `BatchOpt.RegistrationMethod` dropdown wired in `measureOverlaps_Callback`/`stitchBtn_Callback` (widget guarded with `isfield` until added to the mlapp). **Key finding:** feature-based within-layer pairs read the **FULL tiles**, not the thin overlap strip (a ~40 px strip has too few scale-space blobs for RANSAC's ≥8 inliers). This makes the two methods COMPLEMENTARY: at 10 %% overlap + small jitter phase correlation wins 11/12 vs feature-based 1/12; at 25 %% overlap + 55 px jitter (beyond the restricted phase-corr search) feature-based wins 10/12 @ 0.41 px vs phase-corr 3/12 @ 95 px. Document weakness: feature-poor/repetitive content.
  - **2026-07-14 follow-up (user request): make it work "the same way as controllers.Alignment"** — feature-based now has a **detector selector + configurable settings dialog + downsampling**, matching the Alignment tool. Extracted Alignment's feature-settings dialog into a shared `utils.align.detectorSettingsDlg` (downsampling row + rotation-invariance + per-detector params + RANSAC), and **refactored `Alignment.updateAutomaticOptions` to call it** (its ~175-line inline feature branch → one call; AMST branch + v1/v2 downsampling-field selection kept). `featureShift` now consumes the full `automaticOptions` shape (per-detector sub-structs, `estGeomTransform`, `rotationInvariance`) plus `downsampleFactor` (resize by 1/factor for detection, scale point locations back before fitting — like `fitPerSliceV2`). Controller: `BatchOpt.FeatureDetectorType` (8 detectors, same list as Alignment), `automaticOptions` property (`defaultFeatureOptions`: factor 1 for stitch precision, SURF MetricThreshold 500), `buildFeatureOptions` → `measureOptions.featureOptions` → `measureAllPairs` merges into `shiftOptions`; `configureFeaturesBtn_Callback` opens the shared dialog. FeatureDetectorType dropdown + Settings button enabled only for Feature-based (guarded with `isfield`). Verified: Harris+downsample×2 recovers the shift; large-jitter chain 10/12 @ 0.33 px. Tests: `featureShift_honorsDetectorAndDownsampling` (Unit). 27/27 core pass.
- ~~**4th layout source: Bio-Formats metadata**~~ **DONE 2026-07-14** — `LayoutSource` += `'Bio-Formats metadata'`; `utils.stitch.buildLayoutBioFormats` opens each file with a Memoizer'd `bfGetReader`, reads per-series `Plane PositionX/Y/Z` (µm, null→0) + `PixelsPhysicalSize`, and delegates the µm→px/slice conversion to the pure, unit-testable `utils.stitch.stageCoordsToOrigins` (min-shift to 1, distinct-Z→layer ranking like the position file). Multi-series files carry a per-tile `seriesIndex` now honoured by `makeTileReader` (forces Bio-Formats + `BioFormatsIndices`; skips the imread PixelRegion fast path). `selectInputBtn_Callback` multi-selects Bio-Formats files; `buildLayoutFromBatchOpt` branches to it; SubfolderMode disabled for this source. **Verified end-to-end** via a synthetic OME-TIFF round-trip (`createMinimalOMEXMLMetadata` + `setPlanePositionX/Y` + `bfsave`): 4 tiles, origins match the true grid, full chain solves to ≤0.03 px. Tests: `StitchCoreTest.stageCoordsToOrigins_convertsMicronsAndRanksZ` (Unit) + `buildLayoutBioFormats_fullChainFromStageCoords` (Integration, self-skips when Bio-Formats can't load). Assumption to note: stage X→columns, Y→rows, same direction as pixels (`stageCoordsToOrigins` has `flipX`/`flipY` for vendors that invert an axis); pixSize assumed uniform (taken from the first tile).

**Phase 2 — 3D multi-layer global solve** — **DONE 2026-07-14**
Slice-unit `nomOrigin(3)` (position-file Z + subfolder stacking); cross-layer dz measurement in `measureAllPairs/measureZShift` (XY from mean-projection correlation, dz by NCC scan over real overlapping voxels — mean-projection is z-blind, a thick-slab correlation scores every dz alike and biases to smaller dz); z-aware `planCanvas` (uses `positions(:,3)`, canvas Z = max(placementZ + tileD − 1)); solver already solved all 3 axes; fusers already keyed off `tilePlacement(:,3)`.
Milestone met: `StitchCoreTest.fullChain3D_recoversJittered3DLayerStack` — 2×2×3-layer stack with 3D jitter, all axes within 1.5 px, canvas accounts for Z-overlap, fused interior RMSE < 6; streaming byte-identical to in-memory on a multi-layer case. 21/21 core + 23/23 layout pass.
Key findings: within-layer tiles share one focal plane (dz constrained to 0); only cross-layer (`'z'`) pairs measure dz. `zSearchRadius` internal default 8, no new BatchOpt. **Cross-layer pairing rule** (`findNeighborPairs`): keep a `'z'` edge only between tiles at ~same XY position (overlap ≥50% in BOTH dims). Thin-strip / corner cross-layer overlaps give unreliable dz from their narrow projected crops; they are redundant since within-layer edges connect each layer and one same-position z-edge per stacked tile connects the layers (fully connected graph). Dropping them took the 3D smoke solve from 33 px → 0.03 px.

3D GUI smoke example: `temp\stitch_smoke_3d\generateSmokeTiles3D.m` — 2×2×3 Z-stack tiles (multi-page TIFF) + `positions.txt` (nominal grid, jittered truth). Load via Layout source = Position file.

**Filename-pattern overlap support** — **DONE 2026-07-15** (user request while testing Filename pattern + folder tiles)
`buildLayoutFilenamePattern` gained an optional `options.overlapX/overlapY` (default 0 = abutting, backward-compatible): XY step = `tileSize*(1-overlap/100)` like `buildLayoutGrid`; Z always abuts. `buildLayoutFromBatchOpt` passes `BatchOpt.OverlapX/OverlapY` for the Filename-pattern branch; `runOverlapEstimation` now runs for `{Grid, Filename pattern}` (both carry `.gridRC`, which `estimateOverlap` uses); Overlap X/Y spinners + `EstimateOverlap` + SubfolderMode enabled for both sources (`usesOverlap = ismember(...,{'Grid','Filename pattern'})`) while Rows/Cols/TileOrder stay Grid-only. Verified: overlapping pattern-named tiles → 4/4 valid edges @ 0.02 px; default (no options) still abuts (0 pairs, step = full tile). Test `filenamePattern_overlapShrinksStep` (25/25 layout). Smoke: `temp\stitch_smoke_pattern_folders\generateSmokePatternFolders.m` (2×2 folder Z-stacks named `stack_Z01-X0i-Y0j`, ~22%% overlap). **Root cause of the user's error**: folders named grid-style (`tile_r1c1`) carry no `_Z##-X##-Y##` tokens — the Filename-pattern source needs the tokens in the file/folder name.

**Multi-folder InputPath: project-save fix + listbox** — **DONE 2026-07-15**
- *Bug:* with a newline-joined multi-folder `InputPath` (SubfolderMode multi-select), `stitchBtn_Callback` did `fileparts` on the whole multi-line string → bogus folder → "project save failed: Unable to find file" (stitch itself already succeeded). Fixed with a local `resolveProjectPath` that picks the first EXISTING entry: single folder → inside it; multi-folder list → common parent; file (position/Bio-Formats) → next to it, named after it; fallback `pwd`. (Also fixed the file's `end` structure — it needed a terminating `end` once a local function was added.)
- *UI:* `InputPath` may now be a `uilistbox` (one path per row, better for multi-folder) instead of a `uieditfield`. New `refreshInputPathWidget` method sets `.Items` (listbox) or `.Value` (editfield) by `isprop(...,'Items')`; `updateWidgets`/`selectInputBtn_Callback` call it; `addCallbacks` only wires `InputPath.ValueChangedFcn` for the editfield (a listbox is Browse-populated display-only). `BatchOpt.InputPath` stays the newline-joined string → batch unaffected. mlapp to-do: swap the InputPath editfield for a listbox (optional; both work).

**Phase 3 — interactive rough placement** — **DONE 2026-07-14**
Edit mode on the preview axes: the `editLayoutCheckbox` toggles `previewLayoutBtn_Callback` between static `patch` rectangles and one draggable `images.roi.Rectangle` per tile (`InteractionsAllowed='translate'` → fixed tile size, `Deletable=false`, index as hover `Label`). A per-ROI `ROIMoved` listener (`tileMoved` local fcn) writes `Position [xMin yMin]` back into `layout(i).nomOrigin([2 1])` and clears `edges`/`positions`/`canvas` so the next Measure/Optimize uses the corrected layout. Only the first Z-layer is editable (layers share the XY grid). Axis limits are fixed with a 25%% margin (`layerBounds`) so dragged tiles stay visible; `daspect [1 1 1]` keeps tiles square. New controller props `tileROIs` / `roiListeners`; `deleteTileROIs` on every redraw + listeners freed in `closeWindow`. Checkbox wired in `addCallbacks` (guarded `isfield`) to just call `previewLayoutBtn_Callback`. mlapp to-do: add `editLayoutCheckbox` ("Edit layout (drag tiles)") near `previewLayoutBtn`. Verified the `images.roi.Rectangle` translate-only API on a uiaxes headlessly (size preserved, ROIMoved attaches); full click-through is a GUI smoke step once the checkbox exists.

**Phase 4 — QC / seam checker + re-fuse** — Sonnet (Opus 4.8 if re-fusion integration misbehaves)
Load sidecar, render seams, nudge per-tile transform, re-fuse. Likely sibling mode in `@Stitching` (or `@StitchingChecker`).

## Verification

- `tests\utils\StitchTest.m` (`matlab.unittest`, `Unit` tag, follow `tests\plan_unittests.md` conventions): test-local `chopIntoTiles` helper; assert grid order for all 4 TileOrder modes; `pairwiseShift` exact on known integer shifts, low quality on flat tiles; global solve ±1 px 2D and 3D; edge-prune + spring behavior; blend-mode seam checks; `saveProject` round-trip.
- `Integration` tag: `fuseStreaming` → TemporaryFolderFixture zarr → reopen via `Zarr3VirtualSetupLoader` (`datasetMode='BigData'`) → region compare vs in-memory fuse.
- Run via `buildtool test` (remember `addpath('tests')` quirk) and `buildtool check`; MATLAB MCP tools (`run_matlab_test_file`, `check_matlab_code`) for iteration.
- GUI smoke test in live MIB: stitch a small tile folder both output modes; confirm BigData buffer opens and bounding box is correct.
- Update docs per repo rule: user docs page under `docs/` + RST entries under `docs_api/` for the new public methods.

## Risks / notes

- **Slice-exceeds-RAM mosaics**: `saveStream`+`StitchSliceProvider` covers slice-fits-in-RAM; `fuseStreaming` (chunk-wise) is the fallback — its pyramid is a manual block-downsample pass.
- **Low-texture overlaps**: quality threshold + springs; windowing in `pairwiseShift`; fall back to nominal offset on flat peaks.
- **Multi-channel/time**: register on one channel (user-chosen or max-projection), apply transform to all C/T; default shared layout across T.
- **Subpixel**: Phase 1 rounds to integer placement, keeps residual in sidecar; resampled placement later.
- **Per-tile pixel-size mismatch**: assume uniform, warn otherwise; result pixSize from first tile.

### 2026-07-14 — line-embedded smoke data + solver spring fix

- `temp\stitch_smoke\generateSmokeTiles.m` (new, rerunnable) replaces the ad-hoc noise tiles: ground truth = 3-scale noise (25% unsmoothed pixel noise + fine + coarse) + 22 random-angle blended lines (opacity 0.45) + 4 circles. Lines make stitching errors visible at seams; random angles avoid periodic-pattern ambiguity.
- Data-design lessons: saturated single lines in thin overlap strips make translation ambiguous ALONG the line (confident-wrong edges, error vector parallel to the line); unsmoothed pixel noise gives the true peak a needle-sharp component no line ridge can beat. With blended lines + pixel noise: 12/12 edges valid, q=1.00, edge error <= 0.01 px.
- `solveGlobalLeastSquares` default `nominalSpringWeight` 0.01 -> 0.001: the always-on per-tile self-spring (rank guarantee) biased border-clamped tiles (42 px from nominal) by up to 1.6 px; with 0.001 the solve lands at max 0.16 px / mean 0.07 px. Keep this weight tiny — it is rank-only.

### 2026-07-14 — overlap auto-estimation (Phase 1.5, first item)

- `utils.stitch.estimateOverlap.m`: grid pairs from `.gridRC` (nominal-independent), full-tile phase correlation zero-padded to 2H×2W, top-5 peaks each verified by NCC of the implied overlap, per-direction median + MAD. Downsamples tiles > `maxDim` (1024). Robust to any claimed overlap: 5–40%% wrong guesses all converge to the same solution on the smoke set (final positions ≤ 0.04 px).
- **Full-tile findings (both load-bearing):** (1) NO Hann window for full-tile correlation — with small overlaps the shared content sits at the tile edges where the window zeroes it; unwindowed+padded has a dominant peak (5–10× runners-up), windowed has NO peak at the true shift at all. (2) Sign composition is OPPOSITE to the crop path: for full tiles the raw peak of `Fa.*conj(Fb)` is `P_j - P_i` directly (crop path negates and adds crop-start offsets).
- `computeOverlapRegion` now rounds crop bboxes (fractional nominal origins from percentage-derived steps crashed the reader; rounding is exact because the composition uses actual crop starts).
- Controller: `runOverlapEstimation.m` (clamps estimate to spinner limits, rebuilds layout, refreshes GUI), invoked from `measureOverlaps_Callback` + `stitchBtn_Callback` when `BatchOpt.EstimateOverlap` (default true, Grid source only). GUI wiring guarded with `isfield` until the `EstimateOverlap` checkbox is added to the mlapp.
- Test: `StitchCoreTest.estimateOverlap_recoversTrueOverlapFromWrongGuess` (claims 10%%, truth 22%%, expects ±3%% + full-chain ≤1.5 px). 20/20 + 23/23 pass.

### 2026-07-14 — Folders (Z-stacks) layout source

- New `LayoutSource` = "Folders (Z-stacks)": each selected folder is one Z-stack tile, folders arranged on the same XY grid as the Grid source (rows/cols/tileOrder/overlap all apply). `buildLayoutGrid` extended to detect folder entries → populate `sliceFiles` (natural-sorted images) and per-tile depth in `tileSize(3)`; single-image tiles unchanged. `makeTileReader` already stacks `sliceFiles` along depth.
- Selection via `mib/external/uigetfile_n_dir.m` (Java multi-dir chooser). GUI stores chosen folders newline-joined in `BatchOpt.InputPath` (uieditfield preserves newlines — verified); `buildLayoutFromBatchOpt` splits them, OR if a single existing folder is given treats its subfolders as tiles (batch-friendly). Grid-panel enable logic now keys on `ismember(LayoutSource,{'Grid','Folders (Z-stacks)'})`.
- Verified: `temp\stitch_smoke_folders\generateSmokeFolders.m` (2×2 folder tiles, 40 slices each) → measure/solve recovers positions to 0.02 px, canvas preserves depth (Z=40), fuses to a 3D volume. Overlap estimate on folder tiles is loose (thick mean-projection over-smooths) but the restricted measure search still recovers exactly. Test `StitchLayoutTest.buildGrid_folderTiles_carrySliceStack`. 24/24 layout + 21/21 core pass.

### 2026-07-14 — refactor: folder tiles as an orthogonal SubfolderMode modifier

Superseded the separate "Folders (Z-stacks)" LayoutSource (previous entry) with the cleaner design the user proposed: the tile PROVIDER (single image vs folder Z-stack) is orthogonal to the ARRANGEMENT (layout source). Changes:
- New `utils.stitch.resolveTileEntry(path)` — single place that auto-detects file-vs-folder and returns `[sliceFiles, tileSize, dataClass]`. All three builders (`buildLayoutGrid`, `buildLayoutFilenamePattern`, `buildLayoutPositionFile`) now use it, so folder Z-stack tiles work in EVERY layout source. Removed the triplicated local `readTileSize` and `buildLayoutGrid`'s `listFolderImages`.
- `buildLayoutPositionFile`: dropped `subfolderMode`/`buildFromSubfolders` (the old "ignore the file, stack subfolders in Z" path). A `filename` column may now name a file or a folder — auto-detected.
- `LayoutSource` back to `{Grid, Position file, Filename pattern}`. `SubfolderMode` is a general "tiles are folders" modifier: for Grid/Filename pattern it multi-selects folders via `uigetfile_n_dir` (newline-joined in InputPath; single folder → its subfolders); for Position file it is n/a (disabled) since folders are named directly in the .txt. `collectTileEntries` local in `buildLayoutFromBatchOpt` centralises entry collection.
- Verified: Grid+folders and Position-file-listing-folders both build depth-40 tiles and run the full chain (4/4 valid, canvas preserves Z). 24/24 layout + 21/21 core pass. Smoke: `temp\stitch_smoke_folders` (Grid + Tiles-are-folders).
