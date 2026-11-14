# Isotropic level in the Zarr pyramid

Status: **plan, nothing implemented** (2026-11-14). Audit of the level-map code done, results below.
Design revised the same day: the isotropic level is exact (also for a non-integer ratio) and is built
from level 0.

## Progress

- Step 1 done (2026-11-14, uncommitted): `OmeZarrMetadataUtils.snapRatio`, used by `safeRatio` and the
  labels normalisation; `tests/io/OmeZarrScaleSnapTest.m`. The label-registration path
  (`MibBigDataLabelsIndex/openStore`, `registration.scaleFactorsYXZ`) was not checked for the same
  floating-point noise - check it before an isotropic store is opened with a label overlay.
- Step 2 done (2026-11-14, uncommitted): `Zarr3Saver.computeLevelPlan` with the new strategy, plan
  fields `sourceLevel` / `relXY` (also on the old strategies), `tests/io/Zarr3SaverIsotropicPlanTest.m`.
  Decided while implementing: the 2x levels appended for divisibility ignore `MinLevelSize` down to
  16 px; a non-integer ratio warns (`Zarr3Saver:isotropicLevelNonInteger`) and falls back to
  `'Anisotropy-preserving'` until stage 2; an isotropic level below `MinLevelSize` in auto mode warns
  (`Zarr3Saver:isotropicLevelTooSmall`) and falls back too. **The savers do not build the level yet
  (step 3), so the strategy is not offered in any dialog and must not be passed to a saver.**
- Source rule changed (decided 2026-11-14, supersedes "built from level 0" below): the isotropic level is
  built from the **coarsest finer level whose factor divides F**, so 5x5x30 builds the 30 nm level from
  the 10 nm level (3x step), 5x5x60 the 60 nm level (F = 12) from the 20 nm level, 5x5x35 and 5x5x25 from
  level 0 (7x and 5x steps).
- Step 3 done (2026-11-14, uncommitted): `save`, `saveStream`, `saveStreamResumable` (slices and bands)
  build each level from `plan(L).sourceLevel` with step `plan(L).relXY`. New `Zarr3Saver.resizeXY`
  (`imresize(slice, 1 / relXY, method)`, so a 2x step is the same 0.5 as before, bit for bit; explicit
  size only when the scale gives another size). `writeDirectSlab` and `buildLevelBand` take optional
  trailing arguments (`sourceLevels`, `relSteps` / `relXY`), so `BigDataOptions` still calls
  `buildLevelBand` unchanged. `buildLevelBand` errors for a non-integer step (stage 2).
  `tests/io/Zarr3SaverIsotropicSaveTest.m`: all writers equal for bilinear, bicubic, nearest and mode
  (mode: levels that keep Z only, mode is not associative and `save` reduces 3-D blocks of level 0
  where the streaming writers use the level above - not new), bands equal slices, the 30 nm level
  equals `imresize(level 10 nm, 1/3)`, level sizes and `scale` metadata. All 47 existing and new saver
  tests, `CropToBigDataTest` and `AlignmentBigDataTest` pass; `Zarr3SaverParallelTest` (needs a pool) not run.
- DeepMIB output settings (2026-11-14, uncommitted, added after step 8): `ZarrModelOpt` and
  `ScoreExportOpt` get `DownsampleStrategy` (`'Auto'` default, `'XY only'`, `'Anisotropy-preserving'`,
  `'Anisotropy-preserving + isotropic level'`) in `updateModelOutputSettings` and
  `updateScoreExportSettings`, preferences and `MibDeep` defaults (older saved configs get `'Auto'`).
  **Zarr images ignore it**: model and score levels follow the image (the score store through
  `optionsFromPyramid`, which keeps an isotropic level since step 4). Images without a pyramid (AM, TIF,
  ...) use it: `createModelStore` / `writeModelStore` take the voxel size of the image
  (`deepmib.getSourceBoundingBox`, in `startPredictionBlockedImage` and `startPredictionInstances`) and
  the score save resolves `'Auto'` from `scoreMetadata.pixSize`. `'Auto'` is resolved by the new
  `Zarr3Saver.resolveDownsampleStrategy` (also used by ImageConverter): Z voxel >= 1.5 x XY voxel gives
  Anisotropy-preserving, else XY only, unknown voxel size gives XY only. **Behaviour change**: a
  prediction of an anisotropic non-zarr image used to get an XY-only model pyramid, it now gets
  Anisotropy-preserving by default. Not tested end to end (needs a MibDeep window): syntax checked, the
  resolver unit tested. Unverified: `optionsFromPyramid` on a pyramid cut from the predicted level
  (`startPredictionBlockedImage` ~459) for a zarr image with an isotropic level.

- Cut pyramid finding (2026-11-14): a zarr image predicted at a level whose Z/XY ratio is 1.5 or less
  (5x5x30 nm cut at 20 nm) was rebuilt by the planner as plain 1, 2, 4 halving, no warning, because
  `computeLevelPlan` adds an isotropic level only for ratio > 1.5. Fix (option 2): new saver option
  `LevelFactors` ([N x 3] [y x z], first row [1 1 1]) makes the plan exactly those levels;
  `startPredictionBlockedImage` passes the image levels from the predicted level down (cut at `Levels`
  when set). Later the option moved into `optionsFromPyramid` itself (source factors divided by the first
  level, two or more levels, equal Y and X factors), so crop, alignment, image filters/morph ops
  (`processImageToStore`), `BigDataOptions` and DeepMIB all keep the source levels. A smaller `Levels`
  cuts the factors to the finest ones; `reviewOptionsDialog` drops them when the user changes the strategy
  or the level count. Not run in the GUI: alignment dialog and crop dialog paths.
  Resample and tools run from a coarser level: `optionsFromPyramid(pyramid, firstLevel)` describes the
  levels from that level down; a resample drops `LevelFactors` (new size and voxel size, the saver plans
  its own levels), covered by `ResampleDatasetBigDataTest/resampledStoreGetsItsOwnLevelsNotTheSourceOnes`.

- DeepMIB score resampling method (2026-11-14, uncommitted): the "Downsampling method" of `updateScoreExportSettings`
  is now "Resampling method" with items cubic (default, was bilinear), bilinear, nearest, max pooling; a saved
  `bicubic` reads as cubic. The saver got `DownsampleMethod = 'max'` (`resizeXY` block maximum, `reduceZBuffer`
  maximum of the slice group): vectorised for integer steps, works in bands (they start on the step grid) and for
  the isotropic step; tested against a block-maximum reference in all four writers. Applies to zarr and non-zarr
  images. Not run in the GUI.

- Step 8 done (2026-11-14, uncommitted): user docs, one entry each, in `docs/docs/user-interface/ribbon/home/index.md`
  (Export to Zarr3 strategy list), `plugins/file-processing/image-converter.md` (**Downsample strategy**) and
  the NEXT RELEASE block of `getting-started/releasenotes/index.md`; `computeLevelPlan` docblock now
  covers the non-integer `F`. The docs HTML is not rebuilt (the author does that).
  **All 8 steps are done.** Open: `BigDataOptions.overwriteRegion` for a non-integer step (needs a
  non-integer band in `buildLevelBand`), `fuseStreaming` (stitching hides the strategy), the
  `*Parallel*` tests were not run, nothing is committed.

- Step 7 done (2026-11-14, uncommitted), stage 2: non-integer `F` (5x5x13 nm: 5, 10, 13, 26, 52):
  - **Design change against the plan above.** The planned "integer `tileSize` plus per-pixel tile
    mapping and no whole-box shortcut" is not needed. `MibBigDataLabels.tileSizeForFactors` picks, per
    axis, the smallest whole multiple of the coarsest factor that every level factor divides (52 for
    1, 2, 2.6, 5.2, 10.4; 12 for 1, 4, 6; the coarsest factor itself for every power-of-2 and every
    stage-1 store, so those are unchanged). A tile is then a whole number of pixels of every level, no
    level pixel straddles a tile border, and `materializeForRead`, `propagateRegion`, `tilesCovered`
    stay exact as they are, including the `all(boxTiles)` shortcut.
  - New property `tileSize` (set by `refreshTileSize`, called first by `initLevelMapEmpty` and
    `loadLevelMap`, so `MibBigDataLabelsZarr2` needs nothing); `matLevel` / `selectionTiles` have
    `ceil(volume / tileSize)` tiles per axis (`tileGridSize`). Every use of `modelScaleFactors(end, :)`
    as a tile edge now reads `tileSize` (`setData63`, `moveSelection`, `eraseEverywhere`,
    `clearSelectionTiles`, `MibModel.undo`, `MibModel.moveLayers`).
  - `.levelmap` is `mapVersion 3` with `tileSize`; a file of another tile size is ignored (falls back
    to "all levels precise"), older files hold power-of-2 pyramids and load as before.
  - `createStore` / `openStore` refuse a pyramid with no whole tile up to 64 coarsest pixels
    (`core:MibBigDataLabels:levelFactors`). This replaces the divisibility check of step 6: a 1, 4, 6
    pyramid is now accepted with tile 12 instead of refused.
  - `ceil(full / factor)` in `regionForLevel`, `physLimits` and `MibVirtualImage.getDataZarr` got a
    `- 1e-9` guard, and `tileIndexOfLevelPixels` too: 52 / 2.6 must be 20, not 21.
  - Planner: `F` is accepted when `F * d` is a whole number for some `d` up to 20 (13/5, 7/2, 53/20);
    any other ratio warns `isotropicLevelNonInteger` and falls back. The stage-1 divisibility
    extension applies to integer `F` only (it keeps 5x5x35 at 35, 70, 140). `levelSourcesFromFactors`
    now falls back to **level 1** (was the level above): the isotropic level of 2.6 is built from level
    0 in one 2.6 step (the writers already handled a non-integer step through `resizeXY`; the iso level
    has `cumZ = 1`, so it is a direct level and never goes through `buildLevelBand`).
  - Not done: a **band** with a non-integer step (`buildLevelBand` still needs an integer `relXY`, it
    is only reached by Z-reduced levels, which always step 2, and by `BigDataOptions.overwriteRegion`).
    That overwrite refuses a store with a non-integer step through its `sameLayout` check
    (`overwriteSliceLayout`), as before step 4.
  - Tests: `Zarr3SaverIsotropicPlanTest` (plan 5x5x13, 13.37 falls back), `Zarr3SaverIsotropicSaveTest`
    (all writers equal, 13 nm level from level 0, scale 13), `MibBigDataLevelMapTest` (tile size
    rules, edit at 2.6 read at 1 and 10.4 to the voxel, edit at level 0 read at every coarser level on
    exactly its pixels, reopen), `IsotropicLevelBigDataTest` (opens as BigData, factors 2.6, model
    store tile 52 x 52 x 4).

- Step 6 done (2026-11-14, uncommitted):
  - Level-map tests on a store with factors 1 2 4 7 14 28 (`MibBigDataLevelMapTest`): an edit at the 7x
    level across tile borders reads correctly at level 0 and untouched tiles stay empty; a whole-tile
    edit at level 0 appears on exactly the expected pixels at the 7x and 14x levels and marks only its
    tiles in `matLevel`; close and reopen keeps the factors and the edit. The level map code needed no
    change: tile = coarsest factor already works for 28.
  - `MibBigDataLabels.checkLevelFactorsDivide` (static), called by `createStore` and `openStore`:
    error `core:MibBigDataLabels:levelFactors` when the coarsest factor is not a whole multiple of the
    factor of every other level (e.g. 1, 4, 6). Before this such a pyramid was accepted and edited
    with wrong tile borders. To be relaxed in stage 2 (step 7).
  - Registration path (`MibBigDataLabelsIndex.openStore`, labels registered onto an open image):
    checked, no change. `scalesAgainstVoxelSize` already snaps within 1e-3 of a whole number. It does
    not call the divisibility check (stage 2 will decide for it).

- Step 5 done (2026-11-14, uncommitted):
  - `Zarr3Saver.optionsDialog` lists the third strategy plus a header line; new optional 6th argument
    `offerIsotropicLevel` (default true). Stitching passes `false` (its writer cannot build the level),
    and a preset with the strategy then shows `Anisotropy-preserving`.
  - ImageConverter: BatchOpt `ZarrDownsampleStrategy` (`Auto`, `XY only`, `Anisotropy-preserving`,
    `Anisotropy-preserving + isotropic level`), tooltip added; `convertToZarr3Native` reads it with an
    `isfield` guard, `Auto` (or absent) keeps the old rule. Widget to add to the `.mlapp`: a drop-down
    named `ZarrDownsampleStrategy`; its Items come from `BatchOpt.ZarrDownsampleStrategy{2}`.
  - Test: `ImageConverterNativeZarrTest/nativeZarr3_downsampleStrategyOptionReachesTheWriter`. Note that
    a very small `ZarrDownsampleLimitXYZ` makes the auto rule extend the pyramid until the 16 px floor
    rejects the isotropic level (warning, fallback), so tiny test volumes need a limit near the size.

- Step 4 done (2026-11-14, uncommitted):
  - `Zarr3Saver.levelSourcesFromFactors(cumXY, cumZ)`: the source rule stated on stored scale factors
    (coarsest finer level whose XY and Z factors divide the level's); the planner and `BigDataOptions`
    both use it, so a rebuild finds the source the writer used. Tests: agreement with the plan for the
    three strategies and six voxel ratios, and a non-conforming store.
  - `optionsFromPyramid` detects the isotropic level (a level before the first Z-halving one with an XY
    factor off the power-of-2 grid) and returns the new strategy; test: plan -> `pyramidFromPlan` ->
    `optionsFromPyramid` -> plan reproduces the levels (crop, alignment).
  - `BigDataOptions.overwriteRegion` (the "Current overwrite (BigData)" slice / ROI write) rebuilds each
    coarser level from its own source and step (`buildLevelBand(..., relXY)`), with the changed rows
    and slices carried per level. Before this it refused such a store through its `sameLayout` check
    (error `overwriteSliceLayout`), it never wrote wrong data. The changed-row margin is now `relXY`
    source rows on either side (was 2 rows above / 0 below, written for the step of 2), so a few more
    rows can be rebuilt, never fewer. `ImageFiltersBigDataTest/overwriteOfTheShownSlice` has a third
    case, a store with the isotropic level (ratio 6, levels 1 2 4 6 12): every level equals a store
    written from the expected volume.
  - `fuseStreaming` (stitching) raises `fuseStreaming:isotropicLevel` for the new strategy. Its
    `downsampleLevel` builds each level from the level above and does not reduce Z, so it cannot
    build the isotropic level. **Decide before the strategy is offered in the shared Zarr dialog**
    (`reviewOptionsDialog`, used by stitching): either hide the entry there, or teach
    `downsampleLevel` the source and step (and Z).
  - Checked and not affected: `createModelStore`, `startPredictionBlockedImage`, `predictZarrStore`
    (DeepMIB model stores use 'XY only' and explicit factors), `writeModelStoreSlab` (factors relative
    to the predicted level, generic), `MibBigDataLabels` (copies the image pyramid).
  - 67 tests pass: all saver tests, `CropToBigDataTest`, `AlignmentBigDataTest`, `ImageFiltersBigDataTest`,
    `ResampleDatasetBigDataTest`, `MorphOpsImagesBigDataTest`. Not run: `*Parallel*` tests (need a pool).

## Problem

`Zarr3Saver.computeLevelPlan` halves XY at every level and halves Z only once the XY voxel has become
larger than the Z voxel ("Anisotropy-preserving"). For a volume EM stack with 5x5x30 nm voxels:

```
5x5x30  10x10x30  20x20x30  40x40x40  80x80x80
```

The exactly isotropic level 30x30x30 is never produced, so every tool that wants isotropic voxels
(3-D filters, instance segmentation, DeepMIB 3-D, VolRen) must resample on the fly.

## What the standard allows

OME-NGFF only requires the levels to be ordered finest to coarsest; each level carries its own
per-axis `scale` in `coordinateTransformations`. A factor of 2 between levels is a convention, not a
rule, and viewers place a level by its `scale`. MIB writes and reads the `scale` of every level already.

## Design

### New strategy

Third entry of the "Downsampling strategy" list (`Zarr3Saver.optionsDialog`, `strategyItems`) and of
`options.DownsampleStrategy`:

| Name | Levels for 5x5x30 nm |
|------|----------------------|
| `'XY only'` | 5x5x30, 10x10x30, 20x20x30, 40x40x30, ... |
| `'Anisotropy-preserving'` | 5x5x30, 10x10x30, 20x20x30, 40x40x40, 80x80x80, ... |
| `'Anisotropy-preserving + isotropic level'` | 5x5x30, 10x10x30, 20x20x30, **30x30x30**, 60x60x60, 120x120x120, ... |

Internal value is the same string as the list entry, like the existing two.

### Planner rule (`computeLevelPlan`)

Decided 2026-11-14: the isotropic level is **exactly** isotropic, also for a non-integer ratio, and the
usual 2x levels below it stay.

| Voxels (nm) | XY levels (nm) |
|-------------|----------------|
| 5x5x30 | 5, 10, 20, 30, 60, 120 |
| 5x5x35 | 5, 10, 20, 35, 70, 140 |
| 5x5x13 | 5, 10, 13, 26, 52 (factor 2.6, stage 2) |

1. `F = vxZ / vxXY` is the XY factor of the isotropic level, **not rounded**. `F <= 1.5`: no isotropic
   level (the strategy then equals `'XY only'` behaviour of today's default).
2. Levels finer than the isotropic one are the usual 2x cascade (`2^j < F`). No extra in-between level:
   a 9 nm level between 5 and 13 is a non-integer step that a 10 nm level already covers.
3. **The isotropic level is built from the coarsest finer level whose factor divides `F`** (10 nm ->
   30 nm; level 0 -> 35 nm), resized to its target size `ceil(Y / F)`, not from the level above
   (20 -> 30 and 20 -> 35 are not integer steps). **Every following level cascades from it at exactly 2x**
   in XY and Z, so all coarser levels stay isotropic too (`F * 2^k`).
4. It is mandatory: built even when `MaxLevels` / `Levels` would stop earlier (the count is checked
   after it); skipped, with a warning, only below `MinLevelSize`.
5. Level sizes use `ceil(source / step)`, not `round` (equal for 2, not for 3 or 2.6). `ceil` is also
   what `imresize` produces, and `ceil(ceil(Y/a)/b) == ceil(Y/(a*b))` keeps the tile grid consistent.
6. `F` a power of 2: the plan equals `'Anisotropy-preserving'`.

New plan fields: `sourceLevel` (index of the level it is built from: `L-1` for every level except the
isotropic one, which has `1`) and `relXY` (XY step from the source level, may be non-integer), next to
`cumXYFactor`, `cumZFactor`. `relZ` is `cumZ(L) / cumZ(sourceLevel)`.

### Two stages

- **Stage 1 - integer `F`** (30/5 = 6, 35/5 = 7, 15/5 = 3). Every factor is an integer, the level map
  needs one safeguard (divisibility, below).
- **Stage 2 - non-integer `F`** (13/5 = 2.6). Needs the level map to stop using the coarsest scale
  factor as the tile size. Do it only after stage 1 is in and tested.

## Audit of the level map and everything reading a pyramid

Question: does anything assume 2x steps or power-of-2 factors?

**Fine as it is** (per-axis, scale-factor driven; no `2^`, `log2` or `bitshift` anywhere in `+core`,
`+io`, `+utils`, the Chunking and Snapshot controllers):

- `MibBigDataLabels`: `regionForLevel`, `tilesForFullRegion`, `tileIndexOfLevelPixels`,
  `materializeForRead`, `propagateRegion`, `tilesCovered`, `selectionFootprint`, `eraseEverywhere`,
  `moveSelection`, `clearSelectionTiles`. A tile is the coarsest scale factor in full-resolution
  voxels per axis; levels are mapped with `ceil(full / sf)`. The resize helpers take a target size.
- `MibVirtualImage.getDataZarr` / `orientPhysRanges`: per-axis `sf`; level picked by the nearest XY
  factor (`levelScaleFactors(:,1)`), which stays strictly increasing, so no ties.
- `MibBigDataLabels.openStore` / `MibBigDataLabelsIndex`: factors normalised by dividing by level 0.
- Model stores follow the image through `pyramidFromPlan(plan)`, one plan for both.

**Stage 1 invariant**: every level factor divides the coarsest one on each axis, so a tile is a whole
number of pixels of every level. Today it holds because factors are powers of 2. With the isotropic
level branching off level 0 it does not hold by itself: factors 1, 2, 4, 7, 14 have coarsest 14, and 4
does not divide 14. The planner therefore appends 2x levels after the isotropic one until every earlier
factor divides the coarsest (5x5x35: 35, 70, 140, because 4 needs 140). The extra levels are tiny. If
`MinLevelSize` forbids them, the isotropic level is skipped with a warning rather than writing a store
the level map cannot edit correctly. `createStore` / `openStore` get the same check for hand-made
pyramids (open without model editing and say why).

**Stage 2 (non-integer factors) - what breaks.** `tileSize = modelScaleFactors(end, :)` is used as an
integer count of full-resolution voxels (box corners such as `(rows(1)-1)*tileSize(1)+1` in `setData63`,
`selectionFootprint`, `eraseEverywhere`, `clearSelectionTiles`, `moveSelection`, `tilesForFullRegion`,
`tileIndexOfLevelPixels`, and `matLevel` is sized by the coarsest level's pixel grid). With factors 2.6,
5.2, 10.4 the coarsest factor is fractional, so boxes get fractional coordinates and indexing fails.
Fix:

- Give `MibBigDataLabels` its own integer `tileSize` property, decoupled from the scale factors; the
  `matLevel` grid becomes `ceil(volume / tileSize)` per axis. For stores whose factors are all integer
  `tileSize` equals the coarsest factor, so existing stores are unchanged.
- A level pixel straddling a tile border belongs to the tile of its first voxel (the rule
  `tileIndexOfLevelPixels` already uses).
- `materializeForRead` already replaces pixels through that per-pixel tile mapping, but its shortcut
  `if all(boxTiles(:)); block = upsampled;` writes the whole box and would overwrite a straddling pixel
  that belongs to a clean neighbour tile. Drop the shortcut (always use the mapping) when a level's
  factor does not divide `tileSize`.
- `.levelmap` gets `mapVersion 3` with the tile size; older files load as `tileSize = coarsest factor`.
- Guard: `MibBigDataLevelMapTest` and the other BigData tests must pass unchanged on integer stores.

**Needs a fix, the real risks:**

| # | Where | Problem | Fix |
|---|-------|---------|-----|
| 1 | `Zarr3Saver.save` (~262), `saveStream` via `reduceSliceXY` (~2136), `writeDirectSlab` (~1678), `buildLevelBand` (~1757-1788), `saveStreamResumable` task setup (~780-790) | all three savers build level `L` from level `L-1` by `imresize(..., 0.5)`; band halo and row maths assume 2 | Build level `L` from `plan(L).sourceLevel` with `imresize(slice, [Yl Xl], method)` (explicit size: cannot disagree with the plan, works for non-integer steps). `saveStream` keeps the level-0 slice for the isotropic level; `writeDirectSlab` already holds it; `buildLevelBand` reads the source array of `sourceLevel` (its Z slab is the same, `cumZ == 1`). Band rows for an integer step: `rowFirst = relXY*(yOutFirst-1)+1-halo`, `rowLast = min(sourceRows, relXY*yOutLast+halo)`, `halo` a multiple of `relXY` and >= the kernel support, so the band start stays on the output grid. For a non-integer step cut the band with `floor`/`ceil` of the source coordinates and crop after resizing; test it against a whole-slice resize. `rowsPerBand` uses `relXY` instead of 2. Resume keys (level/slab/band) do not change, the plan is rebuilt identically |
| 2 | `Zarr3VirtualSetupLoader` (~474-477), `Zarr2VirtualSetupLoader`, `MibBigDataLabels` (~422) | `levelScaleFactors = level scale / level-0 scale` in floating point. Powers of 2 divide exactly; 3, 7 or 2.6 do not (`0.0053*3/0.0053` can be `2.9999999999999996`), and `ceil(3 / 2.9999999999999996) = 2` puts a voxel in the wrong level pixel | Snap to the nearest multiple of 1/1000 when within `1e-6` relative (`OmeZarrMetadataUtils.safeRatio` and the labels normalisation). Genuine non-integer factors of WSI readers are untouched (they are not within 1e-6 of a multiple of 1/1000 by accident). **Must land before the first non-power-of-2 store is opened** |
| 3 | `blockReduce2D` / `blockReduce3D` for `mode` / `median` | non-integer path uses `round(linspace)` bounds, so edge blocks are redistributed; hit more often at 3x than at 2x | for label `mode` use blocks truncated at the edge; test with `Y = 3k+1` |
| 4 | `optionsFromPyramid` (~1261) | infers `'Anisotropy-preserving'` when Z factors grow, so a derived store (crop, alignment, stitch, DeepMIB model store) would be re-created without the isotropic level | detect the isotropic level: a level with `cumZ == 1` whose XY factor is not a power of 2 and that is followed by a level with `cumZ > 1` -> new strategy |
| 5 | planner `strcmp(options.DownsampleStrategy, 'Anisotropy-preserving')` (~1486), dialog default logic (~1074-1086), header text (~1114-1117) | string compares and help text know two strategies | extend; the default stays `'Anisotropy-preserving'`, the new entry is opt-in |
| 6 | `MibStatusBar.updatePyramidInfoLabel`, `DatasetInfo` | show the factors; check the text copes with 7 and 2.6 | read both, adjust if they format `2^k` or integers |

Everything else that calls `computeLevelPlan` (`cropToBigData`, `fuseStreaming`, `applyAlignmentBigData`,
`MibDeep/createModelStore`) passes the strategy through, so it gets the new strategy without edits,
apart from item 4.

## ImageConverter

Today `ImageConverter.m:873` picks the strategy silently: `pixSize.z >= 1.5 * max(x,y)` ->
`'Anisotropy-preserving'`, else `'XY only'`. Add a user choice that keeps that behaviour by default.

| Widget / BatchOpt field | Type | Items | Default |
|-------------------------|------|-------|---------|
| `ZarrDownsampleStrategy` | dropdown: `BatchOpt.ZarrDownsampleStrategy = {'Auto'}`, `{2} = {'Auto', 'XY only', 'Anisotropy-preserving', 'Anisotropy-preserving + isotropic level'}` | as listed | `'Auto'` |
| `ZarrDownsampleStrategyLabel` (only if the layout has a label beside each Zarr widget; non-BatchOpt name) | label | | |

Place it with the other Zarr settings (near `ZarrDownsampleLimitXYZ`). Tooltip (and
`mibBatchTooltip.ZarrDownsampleStrategy`), one line: `'Auto: Anisotropy-preserving when Z voxel >= 1.5 x XY voxel, else XY only. "+ isotropic level" adds the level where all voxels are equal.'`

Code: replace lines 873-877 by a lookup of `BatchOpt.ZarrDownsampleStrategy{1}`, `Auto` runs the old
rule; guard with `isfield(BatchOpt, 'ZarrDownsampleStrategy')` (saved BatchOpt of older versions lacks
it). The legacy Python path (`Options.zarrFormat`, ~1809) builds its own pyramid: if it is still
reachable, disable the widget there.

`Export to Zarr3` dialog (`optionsDialog`): one more entry in `strategyItems`; header gets one line:
`'"Anisotropy-preserving + isotropic level": also adds the level where XY voxel equals Z voxel (5x5x30 -> 30x30x30).'`

## Implementation steps

1. Loader snap (risk 2) + unit test with scales such as `0.0053*3`, `0.0053*7`, `0.005*2.6`.
2. `computeLevelPlan`: `sourceLevel` / `relXY`, `ceil` sizes, new strategy, level built from level 0,
   mandatory level, stage 1 divisibility extension. Tests: 5x5x30, 5x5x15, 5x5x35, 5x5x20 (power of 2),
   isotropic data, explicit `Levels`, tiny data; invariant "every factor divides the coarsest".
3. Savers (risk 1): `save`, `saveStream`, `saveStreamResumable` must agree voxel for voxel
   (`Zarr3Saver*Test`), bit-identical to today for 2x-only pyramids.
4. `optionsFromPyramid` detection + round trip test (crop and alignment keep the isotropic level).
5. Dialog entry and header text; ImageConverter widget (the `.mlapp` is edited by the author, the plan
   names the widget only) and BatchOpt wiring.
6. Stage 1 level-map test on a store with a 7x step: edit at the coarse level, read at level 0, and
   the reverse, at a tile border (`MibBigDataLevelMapTest` pattern). Divisibility check in
   `createStore` / `openStore`.
7. **Stage 2**: `tileSize` property, `mapVersion 3`, drop the whole-box shortcut, planner accepts a
   non-integer `F`, tests with 5x5x13 (edits near tile borders, save and reopen with `.levelmap`).
8. Docs: `docs/docs/...` (ImageConverter and Export to Zarr3, one line each: what the entry does),
   docblocks of `computeLevelPlan` and `optionsFromPyramid` (full detail), link from
   `bigdata/README.md` (done).

## Open decisions

Decided: exact isotropic level (no rounding of the ratio), built from level 0; 2x levels below it stay;
no extra in-between level.

- Whether VolRen / 3-D tools should prefer the isotropic level when picking a level automatically
  (`pickLevel` uses XY only). Out of scope here.
