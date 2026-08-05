# Image Stitching Tool for MIB3 — Reference

**Status: IMPLEMENTED and verified.** All phases done: 2D translation/affine/rigid/similarity
registration, 3D (multi-layer joint solve + in-plane affine on Z-stacks), streaming zarr→BigData
fusion, interactive rough placement, the seam inspector (manual QC), and the Fibics Atlas / SerialEM
layout sources with optional import of the vendor's own stitch. See companion docs:
[`plan_transforms.md`](plan_transforms.md) (transform models), [`plan_inspector.md`](plan_inspector.md)
(seam inspector), [`mlapp_widgets.md`](mlapp_widgets.md) (widget spec, needed if the GUI is extended),
[`smoke_tests.md`](smoke_tests.md) (GUI regression checklist).

## What it does

Stitches a collection of 2D/3D image tiles into a mosaic: rough initial positions (grid, position
file — a text file OR a Fibics Atlas `.ve-mif` OR a SerialEM `.mdoc`, `_Z##-X##-Y##` filename
pattern, or Bio-Formats stage coordinates) → pairwise registration (phase correlation or
feature-based) → **one global sparse least-squares solve** over the whole tile graph (all axes,
all layers jointly — not "stitch 2D then align 3D") → fuse (in-memory or streaming to OME-Zarr,
reopened as a BigData dataset). Ribbon → Dataset → Stitching. An Atlas `.ve-mif` or a SerialEM
`.mdoc` can additionally **import** the acquisition's own finished stitch and skip the
registration/solve stages entirely (see "Fibics Atlas" / "SerialEM" below).

## Architecture

**Computational core — `mib\+utils\+stitch\`** (controller-independent, headless-testable):
`buildLayoutGrid`/`buildLayoutPositionFile`/`buildLayoutFilenamePattern`/`buildLayoutBioFormats`/
`buildLayoutAtlas` (+`findAtlasSidecars`)/`buildLayoutMdoc` (+`findMdocSidecar`, `mrcTargetClass`)
(nominal origins)
→ `findNeighborPairs` → `pairwiseShift` (phase correlation) / `featureShift` (feature-based,
also handles affine/rigid/similarity) → `measureAllPairs` (edge list) → `solveGlobalLeastSquares`
(translation) / `solveGlobalAffine` (affine/rigid/similarity) → `planCanvas` (+ `autocropCanvas`)
→ `fuseInMemory` /
`fuseStreaming` (+ `mib\+io\+savers\StitchSliceProvider.m` delegating to `Zarr3Saver.saveStream` when a
slice fits in RAM). Plus `estimateOverlap`, `resolveTileEntry`, `blendWeights`, `canvasBackground`, `tileCacheLRU`,
`synthesizeEdgesFromPositions` (shared by every source that imports a placement),
`layoutPixSize` (the acquisition scale, or `[]` when the source does not know it),
`saveProject`/`loadProject` (sidecar JSON), `scoreSeams`/`rankSeams`/`localCorrelate` (inspector core),
`tileCacheBudget` (the reader's cache size).

**Controller — `mib\+controllers\@Stitching\`** + view `mib\+views\StitchingGUI.mlapp`. Standard
child-controller set + workflow callbacks (`selectInputBtn`, `previewLayoutBtn`, `measureOverlaps`,
`optimizePositions`, `stitchBtn` — single fuse+save entry point, `saveProjectBtn`/`loadProjectBtn`,
`askImportMode` — vendor-neutral, dispatches on the picked file). Sibling child controller
**`@StitchingInspector`** (manual seam QC, see `plan_inspector.md`).

```matlab
% layout(i): .index .filename .sliceFiles{} .zLayer .gridRC [r c]
%            .nomOrigin [y x z] .tileSize [H W D C] .dataClass
%            .seriesIndex (Bio-Formats) / .sliceIndex (MRC container) — optional
%            .pixSize .x .y .z .units — optional, only from sources that read a
%                     real acquisition record (mdoc / Atlas / Bio-Formats)
% edges(k):  .i .j .direction 'x'|'y'|'z' .measured [dy dx dz] .tform
%            .nominal [dy dx dz] .quality [0..1] .valid .source .seamScore
```

`Autocrop`/`CanvasColor` decide what happens to the ragged frame the solve leaves around the mosaic -
see "The uncovered frame" below.

Sidecar `<name>.mibstitch.json` (schema v3): tiles (+`solvedOrigin`/`solvedTform`), edges, solver
settings+RMSE, blend, output, `zSliceFixes`, optional `project.settings` block (dialog state — see
"Project files" below). `loadProject`/`saveProject` round-trip all of it; v1/v2 files load with
defaulted fields.

**BatchOpt** (MIB3 conventions): `LayoutSource` {Grid, Position file, Filename pattern, Bio-Formats
metadata}; `InputPath`; `LayoutImport` {Nominal grid only, Vendor seam measurements, Vendor seams +
solved positions — widget-less, set by the import dialog, consulted only when InputPath is a
`.ve-mif` or a `.mdoc`; the retired `AtlasImport` name/values are still accepted on input via
`Stitching.renameLegacyFields`}; `SubfolderMode` (tiles are folders/Z-stacks); `GridRows`/`GridCols` (0=auto);
`TileOrder`; `OverlapX/Y`; `EstimateOverlap`; `TransformType` {Translation, Rigid, Similarity, Affine};
`AllowRotation`; `RegistrationMethod` {Phase correlation, Feature-based}; `FeatureDetectorType`;
`QualityThreshold`; `NominalPositionWeight`; `SubpixelPlacement`; `OutputMode` {In memory, OME-Zarr3
(BigData)}; `OutputPath`; `BlendMode` {Average, Feather, Max, Min, Overwrite *(default)* - the honest one, so a
misalignment is not softened before it has been judged}; `IntensityCorrection`;
`CanvasColor` {black, white *(default)*}; `Autocrop`; `SaveProject`;
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
- **`imread`'s `PixelRegion` takes NUMERIC vectors, not cells.** `makeTileReader`'s sub-region fast
  path built `{r0, r1}`, imread rejected the argument outright ("its type was cell"), and the
  `try`/`catch` fallback swallowed it - so every TIFF overlap read silently decoded the whole file
  from 2026-07 until 2026-08. Measured on a 24000x24000 single-row-strip Deflate tile: a 12 % row
  band is 0.70 s and a 12 % column band 3.55 s against 8.75 s for the whole tile, so seam scoring a
  2x2 mosaic went 54 s -> 17.5 s on the fix alone. **A silent fallback is the failure mode to design
  against here**: the pixels were right either way, so no correctness test could see it. The
  regression test asserts the tile is NOT resident afterwards - only the fallback path caches -
  which is the one observable difference between the two.
- **The tile-cache budget is sized to the layout** (`tileCacheBudget`, the default of
  `makeTileReader`). The old fixed 2 GB could not hold even ONE PAIR of 1.15 GB tiles, so the
  inspector re-decoded both tiles every time the user stepped back to a seam: 17.9 s per revisit
  against 0.00 s once the pair stays resident. Capped at half of what `memory` reports available
  (Windows-only; elsewhere it falls back to the fixed default), never below 2 GB so small-tile jobs
  cannot regress. It is an upper bound, not an allocation. **`measureAllPairs`' `parfor` path
  divides it by the pool size** - each worker builds its own cache, so a budget sized for one reader
  would be claimed once per worker.
- **Seam scores are computed AT MOST ONCE per placement** (`Stitching.ensureSeamScores`, same lazy-
  cache shape as `ensureIntensityCorrection`). Three stages want them - `optimizePositions_Callback`
  after a solve, `buildLayoutFromBatchOpt` after a vendor import, and `StitchingInspector.scoreAndRank`
  on the way in - and before this they read every overlap twice on the two paths that chain
  (import → *Inspect and fix...*, and `resolveBtn_Callback`, which re-solves through the parent and
  then re-ranks). `seamScoresStamp` records `{positions, numEdges, correctionMethod}` and is COMPARED
  against live state rather than explicitly invalidated - there is no single funnel every position
  change goes through, and a rescore that silently did not happen rates the mosaic on the wrong
  pixels. `seamScoresAreCurrent` additionally requires EVERY edge to carry a score, so a cancelled
  pass or a pre-scoring project is redone. Deliberately NOT invalidated by an edge edit that leaves
  the positions alone (excluding a seam, or a fix awaiting its re-solve): no seam's pixels moved.
  A project load adopts the sidecar's scores when the set is complete, stamped AFTER
  `applyProjectSettings` so the correction method recorded is the one in force.
- **`rankSeams` is split out of `scoreSeams` because it reads NO pixels.** That is what lets the
  scoring be skipped while the worst-first order is still re-derived every time (so it follows an
  edge excluded since the last pass). `scoreSeams` ends by calling it, so the two orders cannot drift.
- **Cancelling `scoreSeams` throws the PARTIAL result away** (all `seamScore` cleared, `dzHint`
  zeroed, `ranking` back to input order, third output `cancelled`). Keeping the scores computed so
  far would be worse than keeping none: the chip and the inspector ranking both take a MINIMUM over
  the scored seams, so a half-scored set rates the mosaic on its better half and silently ignores
  the seams nobody read. Stale input scores are dropped too - scoring only ever runs after the
  positions changed, so they describe a different placement. "No score" then reads **"not checked"**
  in the chip and the inspector status line, never `NaN`; `optimizePositions_Callback` appends the
  reason to the status label and does NOT `StopProtocol` (the solve itself stands - only its
  advisory pixel verification was skipped).
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
  `stitchBtn_Callback` runs any pending re-solve first (`Stitching.resolvePending`) so it never
  fuses stale positions — delegating to the inspector's `resolveBtn_Callback` when that window is
  open (it also re-scores and re-ranks the review), and to a plain `optimizePositions_Callback`
  when it is not. **The flag is the CONTROLLER's, not the inspector's**: it used to live on the
  inspector, so closing that window discarded the debt, after which the chip stopped warning and
  Stitch fused the pre-fix placement in silence.
- **The chip must not order the user to press Re-solve.** Because Stitch settles the debt itself,
  the button is a shortcut for refreshing the RATING, not a step in the workflow — the old
  "Re-solve needed to update alignment" sent people to a button they did not need. It now reads
  `Seams edited / Rating stale until re-solved / Re-solve now, or just Stitch`, and that branch
  gets its own tooltip: quoting the cached RMSE there would contradict the line above it.
- **Min blend mode** needs the fresh-pixel mask (same as Max) or a zero background wins every
  singly-covered pixel.

## The uncovered frame (`CanvasColor` / `Autocrop`)

Solved positions never tile the canvas rectangle, so every mosaic carries a ragged frame. Two
independent answers, both wired only through the CONTROLLER - the core functions keep their old
defaults (`background = 0`, no crop), so every existing test and caller is unchanged.

- **`CanvasColor` is a fill value, `Autocrop` is a canvas-plan change.** That is why only Autocrop
  invalidates `obj.canvas` (`updateBatchOptFromGUI`): the colour is read at fuse time, the crop is
  baked into `planCanvas`. Getting this backwards would either re-plan for nothing or fuse a stale
  size.
- **The crop is applied to the PLAN, not to the fused pixels** (`autocropCanvas`, called at the end
  of `planCanvas` when `options.autocrop`). Cropping afterwards would work for `fuseInMemory` and be
  impossible for `fuseStreaming`, which never holds the mosaic - the streaming path would have
  written the frame into the zarr and the pyramid on top of it.
- **`canvasBackground` returns 1, not `realmax`, for float classes.** The literal "maximum the class
  can hold" is useless as a pixel value; MIB carries float image data on the normalised 0..1 scale.
- **The largest covered rectangle is exact and costs no mask.** Tile footprints are rectangles, so
  coverage is piecewise-constant on the grid of their own edges - at most `2N+2` rows/columns for
  `N` tiles, whatever the mosaic's pixel size. Coverage is evaluated there (once per Z-segment;
  the contributing tile set and `zShifts` only change at tile-band boundaries), intersected, then
  read off with the weighted largest-rectangle-in-histogram stack algorithm. A full-resolution
  logical mask would be ~1 GB on a 30k² mosaic. `StitchCoreTest` checks the answer against an
  exhaustive search over a real mask.
- **The affine footprint is deliberately CONSERVATIVE**: the affine image of a tile is a
  parallelogram, and the box spanned by its middle two corner x's and middle two corner y's is
  inscribed in it, minus 1 px for the row `imwarp` blends against its zero fill. Under-claiming
  only shrinks the mosaic slightly; over-claiming puts back the black edge the feature exists to
  remove. Whole-pixel-translation transforms take the exact rectangle, so a translation plan crops
  identically with or without `canvas.tforms` (pinned by a test).
- **Slices no tile reaches are SKIPPED, not intersected in** - one empty slice would otherwise veto
  every crop. Z itself is never cropped: dropping end slices would silently change the depth of the
  stack the user asked for.
- **Autocrop does not remove an interior hole**, only the frame; the kept rectangle has to route
  around a missing tile, which is why a gappy layout can crop far smaller than expected.

## Fibics Atlas (`buildLayoutAtlas`)

**No dropdown entry of its own — it lives under `LayoutSource = 'Position file'`**, which covers
both kinds of file that state where the tiles go and tells them apart by EXTENSION. A `.ve-mif`
answers exactly the same question a position text file does, so a second layout source would have
earned nothing; `findAtlasSidecars` returns an all-empty struct for anything that is not one of the
three Atlas extensions, and its `.mifPath` is the whole "is this an Atlas mosaic?" test.

Atlas writes three XML files sharing one base name — `.ve-mif` (acquisition record: per-tile
`row`/`col` + stage µm, tile size, FOV, pixel size), `.ve-tie` (pairwise seam measurements),
`.ve-updates` (final solved placement). The last two exist only after the mosaic was stitched in
Atlas. `LayoutImport` selects how far down that chain to read; the import happens in
`buildLayoutFromBatchOpt` (not the GUI callback) so batch and dialog share one path.

- **The picker offers the `.ve-mif` alone** — it is the only Atlas file that names the tiles, and
  the other two are DETECTED from it rather than chosen. `findAtlasSidecars` still resolves a
  `.ve-tie` / `.ve-updates` back to the `.ve-mif` (reachable via "All files", a typed path, or a
  batch protocol), so the resolution stays even though the dialog no longer advertises it.
- Everything the Atlas input needs from the enable-state logic it gets for free: `updateWidgets`,
  `updateBatchOptFromGUI` and `runOverlapEstimation` all gate on POSITIVE lists
  (`{'Grid', 'Filename pattern'}`), so Position file already disables Rows/Cols/TileOrder/
  Overlap/Estimate/SubfolderMode. Keep those lists positive.

- **Tie offset composition: `offset = Image1Position − Image2Position + Shift`.** Both positions
  locate the SAME shared strip, each in its own tile's centre-relative frame, so `pos1 − pos2`
  alone reproduces the nominal step exactly (`+329 − −329 = 658`). Writing it `pos2 − pos1`
  flips BOTH axes and every measured offset comes out negated — the one bug found while building
  this; it survives casual inspection because the magnitudes stay plausible.
- **Axis signs are DERIVED per mosaic**, not hard-coded: `deriveAxisSigns` correlates each tile's
  `row`/`col` attribute against its stage coordinate (`signX = sign(cov(col, stageX))`,
  `signY = sign(cov(row, stageY))`). Stage Y points UP, so `signY` normally comes out −1; a
  mirrored stage maps correctly with no flag. Degenerate 1×N / N×1 grids fall back to `[+1, −1]`.
  The `.ve-tie` and `.ve-updates` share the stage frame's orientation, so the same signs apply.
- **All XML lookups must walk DIRECT children.** `<PixelSize>` appears a second time inside
  `TileInfo/AutoTune/AutoStigAndFocus` (1.5 µm, unrelated to the mosaic's 0.5) and
  `<ParentTransform>` a second time inside `<DefaultAlignment>` (the identity-ish default, not the
  solved transform). `getElementsByTagName` crosses those boundaries and silently returns the
  wrong node.
- **Tile files are resolved by BASENAME in the `.ve-mif`'s own folder.** The XML records the
  acquisition machine's absolute paths (`E:\...`), which never exist where the data is analysed.
- **Importing positions without ties synthesises the edges** from `findNeighborPairs` +
  `positions(j) − positions(i)`. Without them `stitchBtn_Callback`'s empty-edge branch runs a full
  measure pass and throws the import away. Belt and braces: that branch is now guarded by
  `isempty(edges) && isempty(positions)` — measuring is pointless once the placement is known,
  because the solve is skipped anyway.
- **Atlas `Confidence` is an unbounded ratio** (observed up to 1.11), MIB `quality` is `[0 1]` →
  clamped, not rescaled. `valid` uses the file's OWN `<ConfidenceThreshold>`, not
  `BatchOpt.QualityThreshold`, so a tie Atlas would have rejected cannot steer MIB's solve.
- **`<User>true</User>` → `source = 'user'`** — it genuinely means a human placed that seam in
  Atlas, which is exactly what MIB's `'user'` means (heavier solver weight, survives a re-measure).
  No new `source` value was introduced; `'atlas'` would have broken
  `advanceToNextUnreviewed`, which treats anything that is not `'auto'` as reviewed.
- **An imported placement gets a synthesised `solverInfo`** (residuals of the imported edges at the
  imported positions) plus a `scoreSeams` pass, so the alignment chip rates it like any solve
  instead of reading "Alignment: —". This is the check that catches a bad Atlas stitch.
- **The nominal stage grid is a rough guess in every mode.** On the reference data the recorded Y
  step is 13–16 µm long (27–33 px, varying by section: 658 µm nominal vs ~642–645 µm real) while X
  is accurate to <1 px — Atlas's own ties agree. Never treat `.ve-mif` positions as final.
- One `.ve-mif` = one mosaic = one section = **one `zLayer`**. Multi-section series are not merged.

## SerialEM (`buildLayoutMdoc`)

**Also under `LayoutSource = 'Position file'`**, told apart by extension like Atlas. A SerialEM
montage is TWO files — an MRC stack whose SLICES are the tiles, and a plain-text `<image>.mdoc`
placing them — and `findMdocSidecar` resolves the pair from either one. Its `.mdocPath` is the
"is this a SerialEM montage?" test; `.isMontage` is a separate flag because SerialEM writes the
same format for tilt series.

- **The picker offers the `.mdoc` alone**, exactly as Atlas offers only the `.ve-mif`: a bare
  stack states no placement, so offering it would let a user pick an `.mrc` with no `.mdoc`
  beside it and fail two steps later — worse, by falling through to the position TEXT parser.
  `findMdocSidecar` still resolves an `.mrc` (typed paths, "All files", batch protocols), and
  `.isMrcImage` is what lets `selectInputBtn_Callback` tell "MRC whose `.mdoc` is missing"
  (explain it) from "not a SerialEM file at all" (fall through) — both leave `.mdocPath` empty.

The `.mdoc` holds all three stitch stages that Atlas splits across three files:
`PieceCoordinates` (nominal) → `XedgeDxy`/`YedgeDxy` (seams) → `AlignedPieceCoords` (solved).
`askImportMode` offers the same three choices for both vendors; only the wording differs.

- **Tiles are SLICES, not files** — the only source where that is true. `layout.filename` is the
  shared container and the new `layout.sliceIndex` (1-based) addresses the tile, following the
  `seriesIndex` precedent. `makeTileReader` is the single choke point that honours it, including
  a ranged `getVolume` fast path for overlap crops (0.007 s for 512² vs 0.11 s for a full 3072²
  slice on the reference data).
- **The MRC is opened afresh on every read**, never cached in the closure: an open file handle
  cannot serialise into a `parfor` worker, and the header read is negligible beside the pixels.
- **Intensity scaling comes from the FILE HEADER** (`getMinAndMaxDensity`), never per-slice
  statistics — a per-slice range would give each tile its own scale and inject exactly the
  tile-to-tile mismatch a stitch must not have. `mrcTargetClass` is the single place the class
  decision lives, so `buildLayoutMdoc` (which sets `dataClass`, and therefore what `planCanvas`
  allocates) and `makeTileReader` (which converts) cannot drift. Float/int16 → `uint16` rather
  than `ImodLoader`'s widest-fitting `uint32`: the mosaic is kept, and the range gets squeezed
  to 16-bit on load anyway.
- **The Y axis is mirrored.** MRC rows are bottom-up and `ImodLoader` flips them, so
  `row = -pieceY`, normalised to min 1 — which is why the montage's overall height never enters
  the arithmetic (`FullMontSize` is read but only informational). Cross-checked against
  SerialEM's own `Cell1.tif`: as-built correlates 0.894, every flip ≤ 0.27.
- **Edge sign convention (the one thing that survives casual inspection if wrong):**
  `XedgeDxy`/`YedgeDxy` are `[dx dy]` stated for the LOWER piece, so the offset is their
  NEGATION; the row component then flips a SECOND time through the Y mirror and comes back
  positive — `measured = nominal + [edgeDxy(2), -edgeDxy(1), 0]`, the same formula for both
  directions.
- **A piece owns the seams to its neighbours at HIGHER X/Y**, so `XedgeDxy` is absent on the last
  column and `YedgeDxy` on the last row. (Decisive evidence on the reference data: the missing
  entries land exactly on max-X / max-Y.)
- **SerialEM records no per-seam confidence** — imported edges get `quality = 1`, `valid = true`,
  `source = 'auto'`, and it is the `scoreSeams` pass that grades them.
- **`AlignedPieceCoords` are whole pixels**, so a re-solve from the imported edges agrees with
  the recorded placement only to ~0.5 px (Atlas, whose transforms are float, agrees to 0.007 px).
  That is rounding in the file, not an error — do not "tighten" it.
- Distinct `PieceCoordinates` Z values map to `zLayer` 1..K exactly as the position-file source
  does, so a multi-section `.mdoc` works for free; one `[MontSection]` gives a single layer.
- **The nominal grid is a rough guess**, as everywhere else: on the reference data it is out by
  up to 5 px, and MIB's phase correlation agrees with `AlignedPieceCoords` to ~1 px instead.

## Intensity correction correction (`estimateIntensityCorrection`)

**The visible seams on TEM montages are NOT a tile-to-tile mean-intensity difference.** Each tile
carries an in-tile shading gradient from the beam profile (left edge +0.6…+3.0 %, right edge
−0.7…−3.9 % on the reference data), so at an X seam a tile's dark right edge meets its neighbour's
bright left edge and they disagree by 4–5 % even when the two tiles' overall means agree to 0.16 %.

`BatchOpt.IntensityCorrection` {None *(default)*, Flat-field (shared), Match tile means}. Measured on
`Cell1.mrc`, rms mismatch across the 12 seams:

| correction | rms | note |
|---|---|---|
| `None` | 3.50 % | |
| `Match tile means` | 3.13 % | ~no help — cannot touch a gradient INSIDE each tile |
| `Flat-field (shared)` | 1.04 % | **3.4×** |
| flat-field + mean matching | 1.36 % | *worse* — equal means fight real content differences |

(Read through `makeTileReader` on the MRC the numbers are ~2.1× larger — the header rescale removes
a large offset, which amplifies ratios. The improvement factor is what carries over: 7.50 → 2.31 %.)

The last row is why the methods are **alternatives, not layers**. `Match tile means` stays because
it is right for a *different* fault: a detector or stain drifting over a long acquisition.

- **Correction is applied in `makeTileReader` and nowhere else.** Every stage passes
  `options.correction`, so measurement, overlap estimation, seam scoring, the inspector and both
  fusers see identical pixels. (`fuseStreaming`'s `streamViaSaver` - the DEFAULT streaming path -
  dropped it out of `providerOptions` until 2026-08; `StitchSliceProvider` then built its own
  uncorrected reader and fused pixels nobody had scored.) Fusing with a correction the seams were not scored with would rate a
  mosaic nobody produced. Four of the six pipeline functions already accepted `options.readerFcn`;
  the field was threaded explicitly anyway so `measureAllPairs` can serialise it into `parfor`.
- **The correction struct is plain numerics** (`.method .field .gain .offset .tileSize`) — no
  handles — precisely so it survives `parfor` and a JSON round-trip.
- **Corrected once on the way into the LRU cache**, and separately for cropped fast-path reads
  (which bypass the cache and must crop the field to match). A size mismatch raises rather than
  silently mis-scaling.
- **Estimated lazily** (`Stitching.ensureIntensityCorrection`), because it costs one read of every tile;
  cached on the controller and dropped when the layout is rebuilt, a project is loaded, or the
  method changes. `ensureIntensityCorrection` also re-checks the method, so a headless BatchOpt change
  self-heals without the GUI callback. `'None'` still returns a struct — distinguishing "estimated,
  answer is none" from "not estimated yet" is what stops a retry per stage.
- **Only the METHOD is persisted** in the sidecar (it is in `projectSettingFields`); the estimate is
  re-derived, being a deterministic function of the tiles. An `[H W]` float has no business in JSON.
- **`Flat-field (shared)` assumes tile CONTENT averages out.** It takes the mean of each tile
  normalised by its own mean, so anything surviving that average is called illumination. True for a
  real mosaic (many tiles, modest overlap, different specimen under each); FALSE for few
  heavily-overlapping tiles, where the specimen's own low-frequency structure is absorbed and the
  result can be worse than no correction. A 3×3 at 10 % overlap estimates cleanly; a 2×2 at 33 %
  over-estimates by >2x. Pinned by `intensityCorrection_fewOverlappingTilesAbsorbTheSpecimen` so it
  cannot become a silent surprise.
- **`Flat-field (overlap-solved)` is the answer to that**, and to the residual the shared field
  leaves even when it works. Where two tiles overlap they image the SAME specimen, so
  `log A - log B = [logF(u_i) - logF(u_j)] + [logG_i - logG_j]` and the specimen cancels EXACTLY,
  whatever it looks like. `logF` is fitted on a degree-4 2-D polynomial (no constant term - it
  cancels in every difference) plus one `logG` per tile, by IRLS with a Huber loss. Samples are
  block-averaged before the ratio, which kills photon noise and the sub-pixel misregistration that
  would otherwise make a per-pixel ratio all edges.
  - **Positions are optional.** Block averaging makes a few px of placement error irrelevant to a
    low-order field, so nominal origins are used when nothing is solved yet - which is what lets
    the method run at `Measure overlaps`, before any solve exists.
  - **Three gauge freedoms, and the choice between them matters.** A common offset on all `logG`
    cancels; and on a REGULAR grid a linear field tilt produces a per-seam-CONSTANT difference,
    exactly like a pair of gains - one ambiguity per axis. Both explanations fit the seams
    identically but give different mosaics, so a weak ridge on the gains resolves all three by
    preferring to explain brightness with the FIELD. Pinning the field instead would leave each
    tile's internal tilt in place and make the mosaic RIPPLE at the tile period. Without the ridge
    the system is rank-deficient by 2 and `\` picks arbitrarily. **The ridge is not the final word
    on the two tilt directions** - it only has to leave a well-posed system; the mosaic's plane is
    decided afterwards by `levelMosaicPlane` (below). Do not tune this ridge to shape the mosaic.
  - **The mosaic must be LEVELLED after solving, and this was a real bug** (`levelMosaicPlane`).
    Matching seams does not make a montage evenly lit: with the gains pinned near 1, each tile keeps
    its own mean, so removing the internal gradient turns a sawtooth into a monotone STAIRCASE - and
    the eye forgives a repeating pattern far more readily than a smooth gradient. Measured as the
    mosaic's fitted brightness plane across x, correcting the tiles made it WORSE in all three
    montages tested:

    | montage | uncorrected | field only | + levelled |
    |---|---|---|---|
    | `Bat0/Cell01` | +4.9 % | **+9.2 %** | +0.5 % |
    | `Bat0/Cell10` | +0.5 % | +3.2 % | +0.3 % |
    | `Bat6/Cell3` | +2.3 % | +4.4 % | +0.1 % |

    `Cell01` merely started highest, so it crossed the visible threshold and was reported as a
    failure - at a 1.02 % seam residual. **The fix is the third gauge, not a better fit.** For any
    plane `a`, `field'(u) = field(u)*exp(a.u)` with `gain'_k = gain_k*exp(-a.c_k)` (`c_k` = tile
    centre in mosaic coords) reproduces every seam difference EXACTLY while multiplying the mosaic
    by `exp(-a.x)`. So the plane is free, and `levelMosaicPlane` spends it on a flat mosaic.
    **Seam rms is bit-identical before and after** (1.024 / 0.131 / 0.644 % on the three above);
    that equality is the regression check that it is a gauge move and not a second fit. Only the
    PLANE is removable this way - a curved trend would need a per-tile spatially varying term the
    correction struct cannot carry. Costs one full pass over the tiles; `levelMosaic = false` opts
    out. A genuine linear trend in the specimen is removed too, and nothing measurable can tell
    them apart.
  - **The tile centre is interpolated, not observed, and a too-flexible fit BOWS there.** This
    shipped once and had to be fixed: at degree 4 the field dipped to 0.87 at the tile centre
    against 1.12 at the edges (37 % span vs the 14 % the whole-tile evidence supports), which
    brightened every tile centre and drew a DARK GRID along the seams - while the seam residual
    read 1.01 %, the best of any method. **The seam metric cannot see this**: it measures exactly
    what the fit minimises.
  - **The degree is CHOSEN, by two tests that both have to pass** (`chooseFieldDegree`):
    k-fold **cross-validation over held-out SEAMS** (whole seams, not random blocks - holding out
    blocks from a seam the fit already saw tests only interpolation; scored on the MEAN-REMOVED
    residual, because the constant belongs to the two tiles' gains and a tile whose only seam is
    held out has none), plus the **interior check**. A parsimony margin
    (`degreeSelectionMargin`, 5 %) makes a higher degree earn its place rather than merely tie.
    `polynomialDegree = []` (default) means "choose"; a forced value is still vetoed if it bows.
  - **Neither test suffices alone, and the reference data proves it.** On `Cell1.mrc` the
    cross-validation PREFERRED degree 4 (held-out error 0.00802 vs 0.00871, ~8 % better) - it is
    the interior check that rejects it at 16.9 % deviation. No seam-based number can ever see that
    failure, because no seam observes the tile interior. CV catches noise-fitting at the borders;
    the guard catches extrapolation into the middle. Auto-selection lands on degree 1 here
    (seam rms 1.02 %, centre/border 0.999), matching hand-tuned degree 2.
  - **Do not add a ridge on the field coefficients.** It looks like the cure for a high degree and
    is a trap: it competes with the gain gauge and past ~0.05 flattens the field completely, so the
    per-tile gains absorb everything. That fits the seams identically (1.02 %) while leaving every
    tile's internal gradient in place - the sawtooth the gain gauge exists to prevent. Measured:
    ridge 0.15 gives field span 0.2 %, i.e. no field at all.
  - Measured on `Cell1.mrc` (rms seam mismatch through `makeTileReader`): none 7.50 %, match means
    6.73 %, shared 2.31 %, **overlap-solved 1.01 %**; worst seam 11.00 -> 1.40 %, worst seam score
    0.701 -> 0.869. On a real Overwrite fuse the visible steps went +2.98 / +1.45 % to
    -0.68 / -0.85 %.
- The `IntensityCorrection` dropdown sits under `BlendMode` in `StitchingGUI.mlapp`; it is read
  unguarded, so an mlapp without it now errors rather than silently running on the default.
- **`smoothSigma` (shared method only) is still a heuristic** - `max(8, 0.02 x min(H,W))`, scaled by
  tile size and nothing else. It is the last hand-tuned shape parameter in the feature; the
  overlap-solved path uses none, which is another reason to prefer it.
- **`imflatfield` is NOT used anywhere here.** It lives only in `utils.doImageFiltering` for the
  Image Filters tool. Neither method calls it: `Flat-field (shared)` smooths an average with
  `imgaussfilt`, and `Flat-field (overlap-solved)` fits a polynomial. Do not "unify" them - the
  overlap-solved model has no per-image smoothing step to unify with.

## The stitched dataset's identity (name + pixel size)

- **Name** (`Stitching.stitchedFilename`): `<source>_stitch.tif`, in the SOURCE folder. The source
  is the position file for a `Position file` layout (it is what the user picked, and for a SerialEM
  montage the "first tile" is a slice index inside one container, not a file), otherwise
  `layout(1).filename`. Compound extensions collapse the way a user reads them: `Cell1.mrc.mdoc` ->
  `Cell1_stitch.tif`, since `fileparts` only strips the last one.
- Extension is **always `.tif`**, whatever the tiles were. A mosaic is one assembled image, not an
  MRC montage container or a `.ve-mif` mosaic record; offering to save it back as a vendor
  acquisition format would be wrong.
- **Why it matters beyond cosmetics:** `MibModel.saveImage` derives the Save As folder from the
  dataset's filename and falls back to `currentDirectory` when it is unset - which meant a stitched
  mosaic opened Save As on MATLAB's working folder. Naming it puts the dialog beside the tiles.
- **Pixel size** flows `buildLayout*` -> `layout(i).pixSize` -> `layoutPixSize` -> `planCanvas`
  (`canvasOptions.pixSize`) -> `canvas.pixSize` -> the dataset's `imageMetadata{'pixSize'}` and the
  Zarr metadata. Only `buildLayoutMdoc` (`PixelSpacing`, Angstroms/10000), `buildLayoutAtlas`
  (`atlasInfo.pixelSizeUm`) and `buildLayoutBioFormats` (OME physical sizes) set it; Grid /
  filename-pattern / position-file layouts have nothing to read.
- **`layoutPixSize` returns `[]`, never a 1 µm default.** `planCanvas` already applies that
  fallback; inventing it in the resolver would make "measured 1 µm" and "no idea" indistinguishable.
  It also skips unusable per-tile entries rather than letting one bad tile veto the rest.
- **Z is set to the in-plane size** for mdoc and Atlas. A montage is one section and neither format
  states a thickness, so an isotropic guess at least keeps XY - which is what montage measurements
  use - correct, rather than silently pairing a correct XY with a fabricated Z.

## Tooltip style

Any tooltip that enumerates options is built with `sprintf` and `\n`, as a lead-in line followed by
`  - Name: what it is` bullets. Applies to `LayoutSource`, `LayoutImport`, `TileOrder`,
`TransformType`, `AllowRotation`, `RegistrationMethod`, `OutputMode`, `BlendMode`,
`IntensityCorrection`.

**One bullet = one `\n`-terminated string, however long.** Do NOT hard-wrap a bullet across several
source strings for source-code tidiness: `\n` is a real line break in the rendered tooltip, so a
wrapped bullet renders as a bullet plus an orphaned fragment, and it wraps at the SOURCE width
rather than the tooltip's. The same goes for a multi-sentence lead-in or trailing line - keep it one
string. Long source lines are the correct trade here.

One-fact tooltips stay plain single-line strings - the bullet form is for choosing BETWEEN things.
Detail beyond "which one do I pick" belongs in
`docs/docs/user-interface/ribbon/dataset/dataset-stitch.md`, not the tooltip.

## PLANNED (not implemented): manual intensity tuning

Agreed in design, deferred to a later session. Two separate pieces, deliberately NOT one:

1. **An `Intensity correction` settings dialog**, behind a gear button beside the dropdown -
   following the `configureFeaturesBtn` precedent already in this dialog (icon-only `uibutton`
   right of the widget it configures, opening a modal that tunes it). Shows the fitted field as an
   image, the per-seam mismatch before/after as a bar chart, the method + chosen degree with the
   `degreeReport` table behind it, and a live before/after strip across one seam.
   **Why a separate window and not the seam inspector:** every inspector action edits ONE edge,
   whereas an illumination change is GLOBAL - adjust it while reviewing seam 3 and seam 7 moves
   underneath you. Mixing the two scopes in the worst-first review loop would mislead. This dialog
   is also the natural place to surface `chooseFieldDegree`'s decision, since everything in it is
   global.
2. **One number added to the seam inspector's existing readout** - that seam's brightness mismatch
   in %, beside the offset and scores. Cheap, and it answers the question the reviewer actually
   has at each seam: *is this bad because it is misaligned, or because it is a brightness step?*
   Today only the qualitative `Difference` overlay hints at it. This is the one cross-link between
   the two tools, and it keeps the inspector about geometry.

Order when picked up: (2) first (a few lines in `renderPairView`'s readout), then (1).

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
- **Canvas frame**: `StitchCoreTest` (6 tests: the class ceilings, the fill in all five blend modes,
  the crop vs an exhaustive largest-rectangle search on a real mask, the multi-layer intersection,
  identity-tform equivalence, warped tiles leaving no background) and `StitchingControllerTest`
  (2 tests: black-vs-white fuses differ on EXACTLY the uncovered pixels; with Autocrop on they are
  bit-identical, which is what proves the frame is gone rather than merely smaller).
- `tests\controllers\StitchingControllerTest.m` / `StitchingInspectorControllerTest.m` — controller-level
  tests driving the real classes headlessly (`controllers.Stitching(mibModel, [], NaN)` builds full
  default state with no window; `StitchingInspector(..., struct('createView', false))` skips the window).
- **Atlas**: `mibtest.helpers.makeAtlasMosaic` writes a synthetic 2×2 mosaic reproducing the
  format's traps (foreign absolute paths, both duplicated tag names, snake tile order, Y-up stage)
  with tiles CUT FROM ONE TEXTURE at the tie/updates offsets — so the imported placement is the
  pixel-correct one (seams score ~1) while the nominal grid is deliberately 4–6 px wrong. Covered
  in `StitchLayoutTest` (12 tests: sidecar resolution from any of the three files, the non-Atlas
  predicate, signs, tie conversion, confidence mapping, provenance, synthesised edges) and
  `StitchingControllerTest` (8 tests: the three import modes, text-file vs mosaic under the one
  source, sidecar-pick resolution, the chip, Stitch skipping measure/solve, overlap estimation
  standing down).
- **SerialEM**: `mibtest.helpers.makeMdocMontage` writes a synthetic 2×2 montage (one real MRC via
  `io.mibImage2mrc` + its `.mdoc`) reproducing the format's traps — Y-up montage frame, slices in
  acquisition order so slice order ≠ grid order, edge shifts stated for the lower piece, seam keys
  absent on the last column/row, `<image>.mrc.mdoc` naming — with tiles CUT FROM ONE TEXTURE at the
  aligned offsets, so the imported placement is pixel-correct (seams score 1.000) while the nominal
  grid is 4 px out in X and 6 px in Y (0.341). Per-axis steps differ deliberately so an axis swap
  cannot pass. Covered in `StitchLayoutTest` (13 tests: sidecar resolution both ways, the
  non-montage predicate, mirror + grid ordering, `sliceIndex`, both edge sign flips, aligned
  placement, solve-from-edges agreement, synthesised edges, header-based float rescale, the ranged
  read vs full-load-then-crop, tilt-series and missing-container rejection) and
  `StitchingControllerTest` (5 tests: the three import modes, `.mrc` vs `.mdoc` equivalence, the
  chip, text-file coexistence, the `AtlasImport` → `LayoutImport` back-compat).
- Cross-validated on real SerialEM data (Hitachi HT7800, 3×3 @ 1.838 nm/px, float32 MRC): MIB's
  `solveGlobalLeastSquares` fed the imported edge shifts reproduces `AlignedPieceCoords` to
  **0.44 px** (the file's whole-pixel rounding), and MIB's independent phase correlation agrees
  with the imported seams to ~0.6 px (worst 1.26) while the nominal grid is 5 px out.
- Cross-validated on real Fibics Atlas data (`Crossbeam 550`, Atlas Engine v5.5.6, 2×2 @ 0.5 µm/px):
  MIB's own `solveGlobalLeastSquares` fed the imported `.ve-tie` reproduces Atlas's `.ve-updates`
  placement to **0.007–0.08 px**, and MIB's independent phase-correlation stitch of the same tiles
  agrees with both to ~1 px.
- Run via `buildtool test` (needs `addpath('tests')`) / `buildtool check`, or MATLAB MCP
  `run_matlab_test_file` / `check_matlab_code` for iteration.
- GUI regression: [`smoke_tests.md`](smoke_tests.md) — 15 numbered datasets/checklists covering every
  layout source, transform model, blend mode, the seam inspector, and the Atlas import modes.

## Risks / notes

- **Slice-exceeds-RAM mosaics**: `fuseStreaming` (chunk-wise, manual block-downsample pyramid) is the
  fallback when even one output slice doesn't fit in RAM.
- **Low-texture overlaps**: quality threshold + springs; fall back to nominal offset on flat peaks.
- **Multi-channel/time**: registers on one channel, applies to all C/T; shared layout across T.
- **Per-tile pixel-size mismatch**: assumed uniform (from the first tile); not warned otherwise.
- **Atlas rotation/scale**: `.ve-updates` transforms carry a tiny skew term and Atlas can in
  principle set `PerTileRotation`/`PerTileScale`; only the translation (`M41`/`M42`) is imported.
  A genuinely rotated Atlas stitch would import as translation-only — no warning is raised.
