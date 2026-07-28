# Image Stitching Tool for MIB3 — Reference

**Status: IMPLEMENTED and verified.** All phases done: 2D translation/affine/rigid/similarity
registration, 3D (multi-layer joint solve + in-plane affine on Z-stacks), streaming zarr→BigData
fusion, interactive rough placement, and the seam inspector (manual QC). See companion docs:
[`plan_transforms.md`](plan_transforms.md) (transform models), [`plan_inspector.md`](plan_inspector.md)
(seam inspector), [`mlapp_widgets.md`](mlapp_widgets.md) (widget spec, needed if the GUI is extended),
[`smoke_tests.md`](smoke_tests.md) (GUI regression checklist).

## What it does

Stitches a collection of 2D/3D image tiles into a mosaic: rough initial positions (grid, position
file, `_Z##-X##-Y##` filename pattern, or Bio-Formats stage coordinates) → pairwise registration
(phase correlation or feature-based) → **one global sparse least-squares solve** over the whole tile
graph (all axes, all layers jointly — not "stitch 2D then align 3D") → fuse (in-memory or streaming
to OME-Zarr, reopened as a BigData dataset). Ribbon → Dataset → Stitching.

## Architecture

**Computational core — `mib\+utils\+stitch\`** (controller-independent, headless-testable):
`buildLayoutGrid`/`buildLayoutPositionFile`/`buildLayoutFilenamePattern`/`buildLayoutBioFormats` (nominal
origins) → `findNeighborPairs` → `pairwiseShift` (phase correlation) / `featureShift` (feature-based,
also handles affine/rigid/similarity) → `measureAllPairs` (edge list) → `solveGlobalLeastSquares`
(translation) / `solveGlobalAffine` (affine/rigid/similarity) → `planCanvas` → `fuseInMemory` /
`fuseStreaming` (+ `mib\+io\+savers\StitchSliceProvider.m` delegating to `Zarr3Saver.saveStream` when a
slice fits in RAM). Plus `estimateOverlap`, `resolveTileEntry`, `blendWeights`, `tileCacheLRU`,
`saveProject`/`loadProject` (sidecar JSON), `scoreSeams`/`localCorrelate` (inspector core).

**Controller — `mib\+controllers\@Stitching\`** + view `mib\+views\StitchingGUI.mlapp`. Standard
child-controller set + workflow callbacks (`selectInputBtn`, `previewLayoutBtn`, `measureOverlaps`,
`optimizePositions`, `stitchBtn` — single fuse+save entry point, `saveProjectBtn`/`loadProjectBtn`).
Sibling child controller **`@StitchingInspector`** (manual seam QC, see `plan_inspector.md`).

```matlab
% layout(i): .index .filename .sliceFiles{} .zLayer .gridRC [r c]
%            .nomOrigin [y x z] .tileSize [H W D C] .dataClass
% edges(k):  .i .j .direction 'x'|'y'|'z' .measured [dy dx dz] .tform
%            .nominal [dy dx dz] .quality [0..1] .valid .source .seamScore
```

Sidecar `<name>.mibstitch.json` (schema v3): tiles (+`solvedOrigin`/`solvedTform`), edges, solver
settings+RMSE, blend, output, `zSliceFixes`, optional `project.settings` block (dialog state — see
"Project files" below). `loadProject`/`saveProject` round-trip all of it; v1/v2 files load with
defaulted fields.

**BatchOpt** (MIB3 conventions): `LayoutSource` {Grid, Position file, Filename pattern, Bio-Formats
metadata}; `InputPath`; `SubfolderMode` (tiles are folders/Z-stacks); `GridRows`/`GridCols` (0=auto);
`TileOrder`; `OverlapX/Y`; `EstimateOverlap`; `TransformType` {Translation, Rigid, Similarity, Affine};
`AllowRotation`; `RegistrationMethod` {Phase correlation, Feature-based}; `FeatureDetectorType`;
`QualityThreshold`; `NominalPositionWeight`; `SubpixelPlacement`; `OutputMode` {In memory, OME-Zarr3
(BigData)}; `OutputPath`; `BlendMode` {Feather, Average, Max, Min, Overwrite}; `SaveProject`;
`showWaitbar`. `BatchOpt.id = obj.mibModel.getActiveId()`. Batch dispatch as ResampleDataset.

## Load-bearing facts (do not re-break these)

- **`pairwiseShift` sign convention:** if `cropB(r,c) ≈ cropA(r−dy, c−dx)` then `shiftYXZ = [dy dx 0]`;
  `measureOne` composes `measured = (bboxA(:,1) − bboxB(:,1)) − [dy dx]` (exact under asymmetric border
  clamping). Full-tile overlap estimation (`estimateOverlap`) uses the OPPOSITE sign composition and NO
  Hann window (small overlaps put shared content at the tile edges, which a window zeroes).
- `computeOverlapRegion` clamps each crop to its OWN tile only (not the pair intersection) — clamping to
  the intersection destroys the search window for edge-abutting pairs.
- Border-clamped pairs need zero-padding + expected-shift-restricted peak search (raw shifts can exceed
  ±extent/2 and alias). `expandPx` per pair is capped at 0.75× overlap extent (over-expanding starves
  the peak with unshared content).
- **Quality metric** is peak-to-second-peak ratio inside the search region (exclusion lobe), mapped
  `(ratio−1.35)/0.65` — plain PSR barely separates true matches from noise.
- **Diagonal tile pairs are excluded** (`findNeighborPairs` requires ≥50% perpendicular overlap) — corner
  overlaps give confident-but-wrong shifts.
- Solver: pruned edges only re-added as springs when they restore anchor connectivity; the always-on
  per-tile rank-guarantee self-spring (`nominalSpringWeight`) must stay tiny (0.001) or it biases
  border-clamped tiles.
- **Cross-layer (`'z'`) edges** are kept only between tiles at ~same XY position (≥50% overlap both
  dims) — thin-strip/corner cross-layer overlaps give unreliable dz and are redundant; dropping them
  took a 3D smoke solve from 33 px error to 0.03 px. Within-layer tiles share one focal plane (dz
  constrained to 0); only cross-layer pairs measure dz.
- **Affine solver:** L-rows (linear-part residuals) must be weighted by `linearScale²`, not
  `linearScale¹` — a residual `r` in `L` costs `linearScale·r` PIXELS; underweighting lets the solver
  trade measurement-exactness for spring satisfaction (0.6 px bias vs ~5e-3 px correctly weighted).
- **3D affine cross-layer coupling:** z-edges enter the affine system with `M = I` (a tile's linear part
  is pinned to its partner's in the adjacent layer) — a layer's common linear factor is unobservable
  from translation-only z measurements. Synthetic test truths must share the linear part per grid slot
  across layers or the solve compromises.
- **`rotationInvariance` (a.k.a. `Upright`) is inverted from its name** — `true` means orientation is
  NOT estimated (not rotation-invariant). Stitching derives it as `~BatchOpt.AllowRotation` in
  `buildFeatureOptions` (one checkbox, not two) rather than exposing the raw field.
- **Filename-pattern tokens:** order and separators are irrelevant (found by last occurrence of the
  letter), uppercase only, indices 1-based. `Z001-X002-Y003` silently parses as `00/00/00`
  (`str2double` reads exactly 2 chars) — a known limitation, not a bug to "fix" without a user call.
- **Alignment quality chip:** `solverInfo` must be a controller property (not a callback-local) and
  `refreshQualityChip` must be called from `updateWidgets`, so every edge edit (exclude, undo, inspector
  fixes) refreshes the chip — a solve's residual can read "Excellent" while a pixel-based seam score
  disagrees; the chip always re-derives from the worst VALID edge's seam score, not just the solver RMSE.
- **Fix-Z model** (seam inspector, see `plan_inspector.md`): each mosaic OUTPUT SLICE is a "layer" — a
  fix shifts that slice and every slice above it; slices below stay put. This is a per-slice mosaic
  correction outside the tile/solver model (`Stitching.zSliceFixes`), not a per-tile dz edit.
- **Keyboard never mutates alignment** — all fixes are mouse-only (drag / Shift+click / two-click);
  arrow/Q/W/PgUp/PgDn keys are view-only navigation in every mode. See
  [[ux-navigation-keys]] (memory) for why this rule exists.
- **`Stitch` is the single fuse+save entry point** — the inspector has no Re-fuse/Save button;
  `stitchBtn_Callback` runs any pending inspector re-solve first (`resolvePending` guard) so it never
  fuses stale positions.
- **Min blend mode** needs the fresh-pixel mask (same as Max) or a zero background wins every
  singly-covered pixel.

## Project files (save/load)

Sidecar v3 adds an optional `project.settings` block (the dialog's BatchOpt, reduced to plain values).
**Load project** asks "Restore everything" (widgets + layout + solved state) vs "Settings only" (keep
the newly-selected input, rebuild the layout, clear edges/positions) vs Cancel; pre-v3 files load their
state with no dialog. `Stitching.projectSettingFields()` is the single field list shared by save/load so
they cannot drift; `applyProjectSettings` skips/clamps unknown fields or type mismatches instead of
raising (an old project must load into a newer dialog).

## Verification

- `tests\utils\StitchCoreTest.m`, `StitchLayoutTest.m`, `StitchInspectorTest.m` — `Unit`/`Integration`
  tagged (`matlab.unittest`, conventions in `tests\plan_unittests.md`); `Integration` includes a
  `fuseStreaming` → zarr → `Zarr3VirtualSetupLoader` reopen round-trip.
- `tests\controllers\StitchingControllerTest.m` / `StitchingInspectorControllerTest.m` — controller-level
  tests driving the real classes headlessly (`controllers.Stitching(mibModel, [], NaN)` builds full
  default state with no window; `StitchingInspector(..., struct('createView', false))` skips the window).
- Run via `buildtool test` (needs `addpath('tests')`) / `buildtool check`, or MATLAB MCP
  `run_matlab_test_file` / `check_matlab_code` for iteration.
- GUI regression: [`smoke_tests.md`](smoke_tests.md) — 14 numbered datasets/checklists covering every
  layout source, transform model, blend mode, and the seam inspector.

## Risks / notes

- **Slice-exceeds-RAM mosaics**: `fuseStreaming` (chunk-wise, manual block-downsample pyramid) is the
  fallback when even one output slice doesn't fit in RAM.
- **Low-texture overlaps**: quality threshold + springs; fall back to nominal offset on flat peaks.
- **Multi-channel/time**: registers on one channel, applies to all C/T; shared layout across T.
- **Per-tile pixel-size mismatch**: assumed uniform (from the first tile); not warned otherwise.
