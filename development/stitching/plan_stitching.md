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
1. GUI click-through test in live MIB (mlapp exists; batch path verified; synthetic tiles ready in `temp\stitch_smoke\tiles`).
2. Dedicated `stitch_24px.png` icon (currently reuses `alignment_24px.png`).
3. User docs (`docs/`) + RST API entries (`docs_api/`).
4. `fuseStreaming` chunk-wise fallback (slice > maxSliceBytes) untested against a real huge-slice case.
5. T>1: reader returns first time point only (fine for Phase 1).
6. `buildLayoutPositionFile` uses `java.io.File.isAbsolute()` — swap for pure-MATLAB check before compiled builds.

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

**Phase 1.5 — robustness & input extensions** (partially done)
- ~~Overlap auto-estimation~~ **DONE 2026-07-14**: `utils.stitch.estimateOverlap` (MIST-style median over grid pairs; unrestricted full-tile phase correlation + top-K NCC peak verification, BigStitcher-style) + `@Stitching\runOverlapEstimation.m`, `BatchOpt.EstimateOverlap` (default true), `EstimateOverlap` checkbox in Grid panel. See Status log for the two full-tile findings (NO Hann window; opposite sign composition vs crop path).
- **Feature-based registration option** — Sonnet (reuse `utils.align.detectFeatures` + `estgeotform2d 'translation'`): new `RegistrationMethod` dropdown {Phase correlation, Feature-based} feeding an alternative `measureOne` path in `measureAllPairs`. For arbitrary/unknown offsets, rotated tiles, and as stepping stone to rigid/affine `TransformType`. Weakness to document: fails on feature-poor/repetitive content where phase correlation still works.
- **4th layout source: Bio-Formats metadata** — Sonnet: `LayoutSource` += `'Bio-Formats metadata'`; new `utils.stitch.buildLayoutBioFormats` reading embedded stage coordinates (OME `Plane.PositionX/Y/Z` / series stage positions) via the BioFormats loader `loadMetadata`; each series/file = one tile, positions converted from stage units to px via pixSize; Z-layers auto-created per distinct Z (same rule as position file).

**Phase 2 — 3D multi-layer global solve** — Opus 4.8
Extend: position-file Z / subfolder tiles, `findNeighborPairs` z-edges, `pairwiseShift` cross-layer, joint x/y/z solve with springs, Z-aware canvas/fusers.
Milestone: synthetic 2×2×3-layer chop with 3D jitter recovered by one global solve; corrupted edge pruned, spring holds tile near nominal.

**Phase 3 — interactive rough placement** — Sonnet
Drag tile rectangles/thumbnails on preview axes (`images.roi.Rectangle`), write back to `nomOrigin`, re-solve. New `dragTile_Callback.m` + mlapp changes.

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
