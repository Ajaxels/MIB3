# Serial-section stacks: stitch and register in one pass - PLAN (partly implemented)

Status: design agreed 2026-10-12. DONE 2026-10-12: steps 1-4 (single-slice dz, split into
sections, stage prior + robust solve, GUI + inspector + drift check), the Fix Z table quick win, and
guided re-measurement of rejected section seams. The two dialog widgets are in `StitchingGUI.mlapp`.
Benchmark: smoke test 19
(`19_stitch_smoke_z_dirs_displacement`, see `smoke_tests.md`).

## Use case

A serial-section montage (SBEM, array tomography, FIB-SEM montages) as the acquisition writes it:

- **one folder per tile** = one stage position, holding that tile's image of every section;
- **every folder has the same number of images** - slice *s* of every folder is section *s*;
- the stage revisits each position on every section and **backlash** puts the imaged area 1-3 px
  off each time, independently per slice (no accumulation).

Goal: the Stitching tool outputs one dataset that is both stitched AND registered in Z, without a
separate pass through the Alignment tool.

## Why it fails today

The tool gives each folder ONE position, and measures a seam on the AVERAGE of all the folder's
slices. With backlash that average is blurred (a spread of offsets, not a fixed one), so on test 19
all 4 seams are rejected (quality <= 0.08). Even a perfect match could not remove per-slice offsets
(median seam break 6.3 px).

## Measured on test 19 (headless prototype, 2026-10-12)

Each folder was split into single-slice tiles, one `zLayer` per section, and fed to the EXISTING
`findNeighborPairs` -> `measureAllPairs` -> `solveGlobalLeastSquares` -> `planCanvas`:

| variant | per-slice XY error | depth |
|---|---|---|
| split, nothing else | max 5.6 px, rms 1.6 px | **5** (should be 24) |
| + dz kept at 1 between sections | max 5.6 px, rms 1.6 px | 24 |
| + stage prior, weight 0.002 / 0.01 / 0.05 / 0.2 | max 3.1 / **1.3** / 2.6 / 3.3 px | 24 |
| reference: exact section-to-section shifts | max 0.3 px | 24 |

- In-plane seams per section: 96, 75 valid, valid ones within 0.01 px of truth.
- Section-to-section seams (slice *s* -> *s+1* of one tile): 92, all valid, error median 0.11 px,
  max 1.04 px - small, but they chain through 24 sections and the error accumulates.
- Stage prior = a spring between every pair of slices of one tile, target `[0 0 dz]`, weight
  as listed. Helps, but the optimum is weight-dependent.
- Test 19's features move 1-2 px per section. Content that really changes with Z cannot be told
  apart from drift by pixels alone, so the realistic target is sub-pixel to ~1 px, not 0.3 px.

## Implementation steps

1. **DONE - single-slice dz bug** (`measureAllPairs.m` `measureZShift`, `scoreSeams.m`). With one
   slice per tile the dz scan could only find overlap at dz = 0, so every section collapsed onto
   one plane (24 -> 5 on test 19). Now, when BOTH tiles are a single slice, no scan runs: dz stays
   at nominal and XY is measured between the two images. Restricted to both-single on purpose -
   a single slice against a stack still scans, because locating a slice inside a stack is real
   information. `scoreSeams` scores tiles that TOUCH in Z on their two facing slices instead of
   `NaN` ("no overlap"), which would otherwise rank every section-to-section seam worst.
   Test: `StitchCoreTest.fullChain_singleSliceSectionsKeepTheirDepth`.
   Still open: multi-slice stacks that merely touch (nominal dz = depth) - the scan forces at
   least one shared slice; not needed for the folder-per-tile case.
2. **DONE - split folder tiles into sections** (`utils.stitch.splitLayoutIntoSections`,
   `BatchOpt.RegisterSlices`, applied at the end of `Stitching.buildLayoutFromBatchOpt` for any
   source). One piece per slice, SECTION-MAJOR; `zLayer` = `nomOrigin(3)` = section,
   `tileSize(3)` = 1, `stageTile` = source folder index.
   - Each piece keeps the FOLDER in `.filename` and reads its image through a one-element
     `.sliceFiles` - so `makeTileReader`, `Stitching.stitchedFilename` (`<folder>_stitch.tif`) and a
     reloaded project's `InputPath` work unchanged.
   - Refuses (with the folder list and counts) unequal slice counts, single-file tiles and folders
     on several layers.
   - `findNeighborPairs` BUILDS the pairs of a section layout (in-plane template of section 1
     repeated per section + same-folder `z` pairs) - identical to the all-pairs search for tile
     overlaps below 50 %; at 50 % or more the search would also pair different tiles across
     sections, which is left out on purpose.
   - `estimateOverlap` now pairs grid neighbours within one `zLayer` only (it took the first
     gridRC match from any layer).
   - `stageTile` round-trips through `saveProject` / `loadProject`.
   - Not yet: multi-page TIFF / MRC stacks as tiles (needs a per-page index in `makeTileReader`).
   - Test 19 headless (Filename pattern, folders, RegisterSlices): 96 pieces, 75/96 in-plane and
     92/92 section-to-section seams valid, canvas 441 x 444 x **24**, per-slice error max 5.4 px /
     rms 1.5 px - the accumulated section-to-section drift that step 3 targets. Timing: measure
     4.9 s, solve + score 1.2 s, fuse 1.1 s.
   - Tests: `StitchLayoutTest` (`splitIntoSections_*`, `findNeighborPairs_sectionLayoutBuilds...`),
     `StitchingControllerTest.registerSlicesStitchesAndRegistersEverySection` (6 sections, +-2 px
     per-slice backlash: every slice within 1 px, depth 6).
3. **DONE - stage prior and robust solve** (`solveGlobalLeastSquares` options `stagePriorSigma`,
   `seamSigma`, `robustLoss`; `BatchOpt.SectionAlignment`, mapped in
   `Stitching.translationSolverOptions`, shared by Optimize and Stitch).
   - **Stage prior as a star, not pairwise springs**: one extra unknown per stage tile (where the
     stage really was), every piece pulled towards it - N rows instead of N^2/2, same optimum.
     Weight `(seamSigma / stageSigma)^2` relative to a quality-1 seam.
   - **Stage repeatability is estimated, and the estimate is good**: a seam between two slices of
     the same tile measures the difference of two stage errors, so
     `sigma = 1.4826 * median|offset| / sqrt(2)` - 2.10-2.18 px on test 19 against a true 2.14.
   - **The remaining error is a SHEAR, not noise.** After step 2 the in-plane seams are exact and
     the error sits in the per-section common mode as a linear trend (~0.2 px per section on test
     19, +2.0 -> -1.9 px in y, -2.9 -> +3.0 px in x): test 19's features move 1-2 px per section,
     and section-to-section registration follows oblique structures. A CONSISTENT bias leaves no
     residual, so no outlier test can see it - only the stage prior counters it, and the prior
     equally counters real sample drift. Hence a user CHOICE, not a tuned default:

     | test 19 / drift variant, max / rms px | backlash only | + 8 px shared drift |
     |---|---|---|
     | step 2 (no handling) | 5.6 / 1.6 | 4.7 / 1.9 |
     | `Follow image content` (Huber, no prior) - default | 3.2 / 0.65 | **1.65 / 0.70** |
     | `Trust stage positions` (prior, `seamSigma` 1 px) | **1.39 / 0.37** | 3.1 / 1.28 |

     (Drift variant: test 19's generator with an 8 px random walk shared by all tiles; scratchpad
     only, not a committed dataset.)
   - **Huber, not a redescending loss.** Cauchy / Tukey reject a 4 px outlier in a 3x3 grid
     exactly (Huber leaves 0.32 px) but on the section chains - few loops - they reject good seams
     and lose: test 19 max 4.0-5.3 px vs Huber 3.4. Huber IRLS converges slowly, so it stops when
     no position moves by 0.01 px (cap 50 rounds) instead of after a fixed count.
   - **Tried and dropped**: estimating `seamSigma` from the z-seam residuals (variance-component
     iteration). It converges to the true seam error (0.42 vs 0.49 px) but a consistent bias is
     not in the residuals, so it lands at 3.3 px on test 19 - no better than Huber.
   - Target "<= 1 px max" not met on test 19: 1.39 px with the stage trusted. The plan's own
     caveat (content that changes with Z is indistinguishable from drift) is the reason.
   - Tests: `StitchCoreTest.solver_stagePriorStopsAConsistentSectionBiasAccumulating`,
     `solver_robustLossDownweightsAConfidentlyWrongSeam`; both modes in
     `StitchingControllerTest.registerSlicesStitchesAndRegistersEverySection`.
   - Translation solve only: `solveGlobalAffine` ignores these options (RegisterSlices with
     Rigid/Similarity/Affine gets neither prior nor robust loss).
4. **GUI and inspector - `.m` side DONE 2026-10-12.**
   - **Dialog**: `RegisterSlices` checkbox (below *Tiles are folders*) and `SectionAlignment`
     dropdown (Registration tab), wired in `addCallbacks` / `updateWidgets` /
     `updateBatchOptFromGUI` behind `isfield` guards - they work as soon as the mlapp carries them
     (spec rows in `mlapp_widgets.md`). Toggling *Register slices* rebuilds the layout; a folder set
     that cannot be split is reported and the box unticked. `Stitching.registerSlicesAvailable`
     (folder tiles possible?) drops the option when the source stops offering folders. Changing
     *Section alignment* keeps the measurements and clears the positions.
   - **Fix XY table**: tiles named by FOLDER (`stageTile`), plus a *Section* column.
   - **Fix Z table**: ONE ROW PER SECTION BOUNDARY - `visibleRanking` keeps each boundary's worst
     tile link (first met in the worst-first ranking), so selection, Up/Down and Confirm work
     unchanged; the row shows worst score, median offset over the boundary's links, lowest
     quality, number of links, exclusions. A fix edits that tile link and re-solves (the pieces are
     single slices, so the zSliceFixes boundary view does not engage).
   - **Chip**: `Seam match: stitch 0.78, Z 0.27`. The VERDICT follows the stitch score only -
     adjacent sections are different images, so a section-to-section score runs far below an
     in-plane one (0.27 on test 19 with every section placed right) and the 0.4 / 0.7 thresholds
     would turn every serial-section chip red.
   - **Drift check** (`solverInfo.sectionDrift`, computed in `solveGlobalLeastSquares` from the
     measured section-to-section seams, independent of the chosen solve): whole-section movement
     over the stack vs `3 * sigma * 2/sqrt(K)`, what stage jitter alone stays within. Status line:
     `sections move 12.2 px (drift or oblique content)`; chip tooltip names the choice it supports.
     Test 19: 12.2 px vs bound 6.3 - flagged, correctly, as "drift OR oblique content" (its
     features move 1-2 px per section); drift variant 18.0 px. Also tried: the share of step
     variance common to all tiles of a boundary (backlash 1/K, drift -> 1) - measured accurately
     (0.34 / 0.47 vs truth 0.34 / 0.46) but with 4 tiles too close to separate the cases.
   - Tests: `StitchCoreTest.solver_sectionDriftCheckFlagsWholeSectionMovement`,
     `StitchingControllerTest.sectionDriftCheckReachesTheChip`,
     `StitchingInspectorControllerTest.sectionLayoutTablesNameFoldersAndGroupBoundaries`; shared
     fixture `mibtest.helpers.writeSerialSectionFolders`.
5. **DONE - guided re-measurement of rejected section seams** (`measureAllPairs` options
   `guidedRemeasure` / `guidedExpandPx`, automatic for section layouts). Found from a GUI run of
   test 19: the bottom-left tile was up to 4.5 px off while the others were within 1 px. Both of
   its in-plane seams were REJECTED in 9-12 of the first 13 sections (quality 0.00-0.20) - a
   generated straight line runs along those seams there and correlates along its own length, so
   the wide search finds a ridge, not a peak; some measurements were right but distrusted, some
   44 px off. With its in-plane seams gone, the tile hung on its own section-to-section chain.
   The same two folders meet in every section and their offset changes only by stage jitter, so a
   rejected seam is re-measured in a +-18 px window around the median of that folder pair's
   passing seams: all 21 came back within 0.02 px at quality 1.00. Replaces the original only when
   it passes the threshold. Test: `StitchCoreTest.measureAllPairs_rejectedSectionSeamIs...`.

   **Results after step 5** (controller path, max / rms per-slice error, px):

   | | test 19 (backlash) | drift variant |
   |---|---|---|
   | Follow image content (default) | **0.61 / 0.06** | **1.55 / 0.67** |
   | Trust stage positions | 0.57 / 0.26 | 3.13 / 1.28 |

   Test 19 now meets the original <= 1 px target in both modes, and the default is the better
   choice on drift data - so it stays the default.

   **Caveat - what "Follow image content" really does.** The Huber scale is ONE robust scale over
   all seams, set by the far more numerous and precise in-plane seams (~0.01 px). The
   section-to-section seams (residuals 0.1-0.5 px) are therefore strongly down-weighted, and the
   tiny per-tile nominal springs (`nominalSpringWeight` 0.001) then act as a soft stage prior.
   That is why the mode does so well on test 19. A Huber with a SEPARATE scale per seam class -
   genuinely following the section-to-section seams - was worse on both datasets (4.5 / 6.5 px
   max), and so were the variants without the nominal springs (1.0 / 4.1 px). The behaviour is
   measured, not designed; revisit it before changing either weight.

   - **DONE - Fix Z table quick win**: with no cross-layer seam (all Z-stack tiles on one layer,
     test 19 now) the Fix Z table lists the slice boundaries (`StitchingInspector.listsSliceBoundaries`
     / `syncSliceBoundaryTable`): a row opens the boundary view, Up/Down step it, the Shift column
     shows the stored correction. Test:
     `StitchingInspectorControllerTest.fixZTableListsSliceBoundariesWhenAllStacksShareOneLayer`.
     After step 2 the sections become layers and the boundary rows must then come from the
     section-to-section seams instead.
     The rows carry NO measurement yet - only the stored correction once a boundary is fixed.
     Decided 2026-10-12: do not add a separate measuring pass (it would read every slice of every
     tile); after step 2 each row shows that boundary's section-to-section seams, summarised over
     the tiles (median offset, worst score) and sorted worst first.

## The three section modes (2026-10-12, after the widgets were built)

`Stitching.sectionMode` turns the two widgets into one of three behaviours; layout build,
pairing (`neighborPairOptions`) and solve (`translationSolverOptions`) all read it:

| Register slices | Section alignment | mode | what happens |
|---|---|---|---|
| off | (disabled) | `unrelated` | split; in-plane pairs only (`findNeighborPairs` `linkSections = false`); every section its own group |
| on | Prealigned *(default)* | `prealigned` | NO split - each stack one block (the pre-2026-10 behaviour, incl. Z-stacks overlapping across layers) |
| on | Follow image content / Trust stage positions | `aligned` | split + section-to-section seams, solved as in step 3 |

- **Default = ticked + Prealigned**, so every existing 3D project and protocol stitches exactly as
  before (smoke tests 3, 4, 5, 13); 2D mosaics have nothing to split and are identical in all.
- **Only folder tiles can be split.** Without them (`registerSlicesAvailable` false) the GUI holds
  the settings at ticked + Prealigned; a batch protocol asking for another mode on single-file
  stacks gets `splitLayoutIntoSections:notFolders` - no silent fallback to a block.
- **Solver change for `unrelated`** (general, not mode-specific): a group the valid edges leave
  disconnected from the anchor gets ONE bridge spring on its first tile instead of one per tile, and
  a pruned edge re-enters as a spring only when it joins two groups. The per-tile springs bent a
  multi-tile group against its own seams. Test: `solver_disconnectedGroupKeepsItsOwnGeometry`.
- **Chip**: in `unrelated` mode one group per section is the design, so only groups beyond the
  section count count as unmeasured; no Z score is quoted.
- Tests: `StitchingControllerTest.unrelatedSlicesAreStitchedOneByOne`,
  `prealignedFoldersStayOneBlockEach`.

## Fix Z works on the stitched mosaic (2026-10-12)

Decided with the user: in Fix Z the tiles are taken as correctly stitched and only Z needs
correcting, so a correction is ONE rigid shift of mosaic slice z (and above) against z-1 - option
(a), a mosaic-level shift on top of the solve, the same in every section mode. Before, Fix Z
measured on ONE tile (Prealigned) or edited ONE folder's section link and re-solved (serial
sections) - the latter moved every tile of the section by a solver compromise with the boundary's
other links.

- **View** (`buildZMosaicCrops`): the same rectangle of mosaic slices z-1 / z, fused with
  `utils.stitch.fuseSliceRegion` - Stitch's blend mode, drawing order and corrected tiles, only the
  tiles under the crop read. Composed from `zViewCanvas` (the plan WITHOUT `zSliceFixes`); the
  boundary's own correction is applied as the offset of slice z (`boundaryDelta`), the frame drag and
  click-correlate always used. Crop = the current seam tile's size, at most 1024 x 1024, centred on
  `zMosaicCenter` (a mini-map click, `fixZSelectPoint`; default the current seam's tile centre).
- **Fix**: drag / Shift+click on the crops -> `applyZBoundaryFix` -> `zSliceFixes` (no re-solve,
  tiles untouched; Stitch applies, project saves, `Z` removes). Verified end to end: a [4 -6]
  content jump at slice 4 was measured as a [-4 5.91] correction; fused slices 3 vs 4 then differ
  by 0.6 grey levels against 16.4 before.
- **Scores follow the corrections** (found in a live session: a boundary moved off by hand kept
  its old score 0.57-0.68, stayed yellow at rank 7 of 23, and its *Offset* column - the links'
  measured stage jitter - read as an error). Seams are now scored at
  `Stitching.scoringPositions` (solved positions + each tile's `zFixTileShifts`); the score stamp
  includes `zSliceFixes`; when only the corrections changed, `ensureSeamScores` re-scores just the
  links whose two tiles moved relative to each other (the links across the changed boundary). The
  inspector calls it after every Fix Z set / removal (`rescoreAfterZFix`), re-ranks, and tells the
  parent. The serial-section Fix Z table shows the stored *Correction* instead of the measured
  offset. Test: `StitchingInspectorControllerTest.fixZCorrectionReratesItsBoundaryOnTheCorrectedMosaic`.
- **Ctrl+Shift+click = the whole stack** (`correlateStackAtPoint`): the Shift+click correlation at
  EVERY boundary at the clicked spot of the crop on screen; each slice composed once
  (`fuseZMosaicSlice`) from the uncorrected plan, so each boundary is measured on its own raw
  offset; confident matches replace that boundary's correction, the rest keep theirs; cancelable,
  nothing stored on cancel. Ctrl is tracked by the inspector's key handlers (`ctrlDown`) because a
  Ctrl+click reports SelectionType 'alt', like the right-click pan. Test:
  `ctrlShiftClickCorrelatesEveryZBoundaryOfTheStack`.
- **Ctrl+Z = Fix Z undo history** (`zFixHistory`, `pushZFixHistory` / `undoLastZFix`): every Fix Z
  action - drag, Shift+click, Z (remove), Ctrl+Shift+click - records the corrections just before it;
  Ctrl+Z restores the last record. So a stack run comes back as one step (every boundary), a single
  fix returns its boundary to the PREVIOUS value (not none), and a removal is undone. LIFO restores
  of whole states stay consistent under any mix of actions (the first version, one undo point for
  the stack run that refused after any later edit, was replaced at the user's request). Last 100
  actions; Fix XY keeps its per-seam `Z`. Test: `ctrlZReturnsABoundaryToItsPreviousCorrection`.
- **Boundary**: a selected cross-layer seam brings its boundary (`zBoundaryOfEdge`: the slice its
  upper tile starts on); Q/W browse it; for serial sections the current row follows the browsed
  boundary.
- **Fix Z engages** when the mosaic has more than one slice, except for unrelated slices
  (Register slices off); the per-seam "has a Z-stack tile" test is gone (section pieces are single
  slices).
- `fuseSliceRegion` is bit-identical to cropping a full fuse - every blend mode, `zShifts`, warped
  tiles (`StitchCoreTest.fuseSliceRegion_equalsTheCropOfAFullFuse`). It re-frames the canvas to the
  region rather than adding a region branch to `fuseSliceComposite`.
- Superseded and removed: the tile-pick version of this section (`zViewTile`, `zBoundaryTile`,
  `tileAtMiniMapPoint`, `fixZSelectTile`, `boundaryTileOf`).
- Tests: `StitchingInspectorControllerTest.fixZViewIsTheStitchedMosaicAroundTheChosenPoint`,
  `fixZBrowsingSectionsKeepsTheBoundaryRowInStep`.

## Output

Covered by the existing output modes: In memory, OME-Zarr (BigData), and Image files as a 2D
sequence (TIF / PNG / Amira, one stitched and Z-registered section per file) or an Amira 3D stack.
A multi-page 3D TIF output was considered and DROPPED (2026-10-12, not needed).

## Open questions

- Prior weight: DECIDED - repeatability estimated; the user chooses content vs stage
  (`SectionAlignment`). A numeric repeatability override exists in the solver only.
- Whether section-to-section seams should also skip a section (*s* -> *s+2*) for redundancy.
- Memory / time on a real dataset: measuring scales with sections (3.3 s for 188 seams here).
