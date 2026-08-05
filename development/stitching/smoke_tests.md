# Stitching — GUI smoke tests

Datasets to exercise the Stitching tool by hand in a running MIB. Each dataset has a
generator under `development\stitching\NN_stitch_smoke*\`; running it writes the tiles into
`<repoRoot>\temp\stitching_test\NN_stitch_smoke*\`. In both places `NN` is the test number
from the table below (zero-padded), so the generator folders and the generated data sort in
test order and line up name-for-name. The `temp\` tree is untracked, so regenerate freely.

Datasets shared by several tests carry the LOWEST test number that uses them, so tests 2, 8,
9, 10 and 14 have no folder of their own: `01_stitch_smoke` serves tests 1, 2, 8, 9 and 14,
and `06_stitch_smoke_feature` serves 6, 10 and 14.

Most generators write one image file per tile. Test 16 is the exception — a SerialEM montage is
one MRC stack whose SLICES are the tiles — so its folder holds two files, not nine.

## Generate the data

Run once from MATLAB (each generator `cd`s nowhere — it resolves its own output path):

```matlab
run('development\stitching\01_stitch_smoke\generateSmokeTiles.m')
run('development\stitching\03_stitch_smoke_3d\generateSmokeTiles3D.m')
run('development\stitching\04_stitch_smoke_folders\generateSmokeFolders.m')
run('development\stitching\05_stitch_smoke_pattern_folders\generateSmokePatternFolders.m')
run('development\stitching\06_stitch_smoke_feature\generateSmokeFeatureTiles.m')
run('development\stitching\07_stitch_smoke_bioformats\generateSmokeBioFormatsTiles.m')   % needs Bio-Formats Java
run('development\stitching\11_stitch_smoke_affine\generateSmokeAffineTiles.m')
run('development\stitching\12_stitch_smoke_sabotage\generateSmokeSabotageTiles.m')  % needs mib on path (measures + saves a project)
run('development\stitching\13_stitch_smoke_affine3d\generateSmokeAffine3DTiles.m')
run('development\stitching\15_stitch_smoke_atlas\generateSmokeAtlasTiles.m')
```

Or regenerate everything at once, in test order (run from the repo root):

```matlab
folders = dir(fullfile('development', 'stitching', '*_stitch_smoke*'));
folders = folders([folders.isdir]);
for k = 1:numel(folders)
    script = dir(fullfile(folders(k).folder, folders(k).name, 'generateSmoke*.m'));
    run(fullfile(script.folder, script.name));
end
```

All generators embed randomly-oriented lines + circles (or tilted planes in 3D): a broken
line/circle at a tile seam is the at-a-glance sign of a bad stitch.

## Tests

Open the tool from **Ribbon → Dataset → Stitching**. Unless noted, finish each with
*Measure overlaps → Optimize positions → Stitch* and check the mosaic has continuous
lines/circles across every seam and the status label reports a low RMSE.

"Browse to `…\tiles`" means: press the Input **…** button and multi-select the tile
image files in that folder (Ctrl+A) — with *Tiles are folders* off the picker selects
FILES, not a folder. Pasting the folder path into the Input path field still works too.

| # | Dataset (`temp\stitching_test\…`) | Layout source | Settings | What it checks |
|---|--------------------|---------------|----------|----------------|
| 1 | `01_stitch_smoke\tiles` | Grid | Rows 3, Cols 3, tick **Estimate overlap** | Baseline 2D grid + overlap auto-estimation. |
| 2 | `01_stitch_smoke\tiles` | Grid | Rows 3, Cols 3, untick Estimate, Overlap X/Y = 15 | Grid with a manually entered overlap. |
| 3 | `03_stitch_smoke_3d\positions.txt` | Position file | — | 3D joint solve from a position file (scroll Z; planes must line up across layers). Since 2026-07-17 the seam check is Z-aware: the chip verifies per-slice at the solved dz and cross-layer seams are dz-scanned — a Z misalignment shows as orange "Check Z alignment"; in the inspector the offset readout shows dz + any "pixels prefer dz±k" hint (diagnostic — re-measure or exclude the seam if the Z overlap is wrong). `Q`/`W` browse slices like the main MIB — ALWAYS view-only (verify a few presses never change dz or the chip). A cross-layer XY misalignment is fixed on the z-edge seam itself in Fix XY (Shift+click / drag): the re-solve shifts the whole upper stack AND every layer above it (verified by `zBoundaryFix_shiftsAllLayersAbove`). **Fix mode = Fix Z (match slices)** is the PER-SLICE mosaic check: one tile at slice z-1 (cyan) vs slice z (magenta), fully overlapping, mostly white when aligned; `Q`/`W` moves the boundary, drag or Shift+click aligns slice z — the fix shifts that slice AND every mosaic slice above it (no re-solve; applied at Re-fuse/Stitch; `Z` removes it; persisted in the sidecar — core verified by `planCanvas_zSliceFixesShiftMosaicAboveBoundary`). On a 2D dataset Fix Z flips back to Fix XY with an explaining dialog. Since 2026-07-19 the **seam table is split by fix mode**: Fix XY lists the in-plane `x`/`y` seams, Fix Z lists the cross-layer `z` seams (the old combined list was confusing). Switching the Fix-mode dropdown re-filters the table and lands on a seam of that kind; the table highlight, `N`/`P`, mini-map jumps and the initial pick all stay within the shown set. The cross-layer XY fix is therefore reached from the **Fix Z** table (that is where the `z` seam now appears) — select it, then use Fix XY to Shift+click/drag its in-plane offset. |
| 4 | `04_stitch_smoke_folders` (4 folders / parent) | Grid | tick **Tiles are folders (Z-stacks)**, Rows 2, Cols 2 | Folder-Z-stack tiles with the Grid source. |
| 5 | `05_stitch_smoke_pattern_folders` (4 folders / parent) | Filename pattern | tick **Tiles are folders**, Overlap X/Y ≈ 22 (or Estimate) | Filename-pattern `_Z##-X##-Y##` + folder tiles + overlap. |
| 6 | `06_stitch_smoke_feature\tiles` | Grid | Rows 3, Cols 3, Overlap 25, **untick Estimate** | **Method comparison** — run twice (see below). |
| 7 | `07_stitch_smoke_bioformats\tile_01..04.ome.tiff` | Bio-Formats metadata | multi-select the 4 files | Stage coordinates read from OME metadata — jittered, so Optimize is what makes it exact (see below). |
| 8 | any of 1/6 | Grid | tick **Edit layout** on the preview | Phase 3 drag placement: drag a tile, re-Measure/Optimize. |
| 9 | any of 1/6 | Grid | Output mode = **OME-Zarr (BigData)**, pick a path | Streaming fuse → reopens as a BigData dataset. |
| 10 | `06_stitch_smoke_feature\tiles` | Grid | Registration = Feature-based → **Settings** (gear button) | Feature preview: changing a detector param pops the matched-features figure. |
| 11 | `11_stitch_smoke_affine\tiles` | Grid | Rows 2, Cols 2, Overlap 25, **untick Estimate** | **Transform comparison** — run twice (see below). |
| 12 | `12_stitch_smoke_sabotage\sabotage.mibstitch.json` | — (Load project) | **Inspect and fix...** after loading | **Seam inspector** — the residual-invisible corrupted edge (see below). |
| 13 | `13_stitch_smoke_affine3d\positions.txt` | Position file | Transform = Affine, tick **Allow rotation** | **3D affine** — in-plane affine on Z-stack tiles across 2 layers (see below). |
| 14 | `01_stitch_smoke\tiles` + `06_stitch_smoke_feature\tiles` | Grid | **Save project**, then **Load project** twice | **Project save/load** — settings round-trip + the load-mode question (see below). Needs no new data. |
| 15 | `15_stitch_smoke_atlas\MosaicInfo_SMOKE.ve-mif` | Position file | pick the `.ve-mif`, answer the import dialog | **Fibics Atlas** — an Atlas mosaic under the Position file source; the three import modes (see below). |
| 16 | `16_stitch_smoke_mdoc\Montage_SMOKE.mrc.mdoc` | Position file | pick the `.mdoc` (or the `.mrc`), answer the import dialog | **SerialEM** — tiles are SLICES of one MRC stack; the three import modes and the float rescale (see below). |
| 17 | `01_stitch_smoke\tiles` | Grid | Rows 3, Cols 3, Estimate on; then **Canvas color** / **Autocrop** | **The uncovered frame** — see below. Needs no new data. |

### Test 6 — phase correlation vs feature-based (the key comparison)

The feature dataset has ±55 px jitter against a ~75 px overlap strip, so restricted-search phase
correlation mostly fails while full-tile feature matching recovers it. Verified headlessly:

- **Registration method = Phase correlation** → *Measure overlaps*: ~7/12 edges valid, solve lands
  ~80 px off — seams visibly break after Stitch.
- **Registration method = Feature-based** (SURF) → *Measure overlaps → Optimize → Stitch*: ~11/12
  edges valid, ~0.5 px error, clean seams.

### Test 7 — stage coordinates are never exact

The tiles are cut on a **perfect** grid; the stage coordinates in the OME metadata carry a per-tile,
per-axis error of up to ±5 px (continuous — backlash, drift, encoder error). So this set separates
"reading the metadata worked" from "registration worked":

- Browse the 4 files, then *Stitch* **without** Measure/Optimize → the mosaic is already recognisable
  but every seam is a few pixels off; lines and circles show a visible kink. Metadata-only origin
  error ≈ 4 px.
- *Measure overlaps → Optimize positions → Stitch* → 4/4 edges valid, origin error ≤ 0.02 px, seams
  continuous. Verified headlessly.

`trueOrigins.mat` carries `trueOrigins` (the perfect grid) and `stageJitterPx` (the signed error
baked into the metadata) for headless checks.

### Test 10 — feature-settings preview

With the feature dataset loaded and Registration = Feature-based, press **Settings** (gear button), change a
parameter (e.g. lower the SURF metric threshold), accept. A *MIB: stitch feature preview* figure
opens showing keypoint matches on the first overlapping pair — left = with outliers, right = inliers
only, titled with the inlier ratio and recovered `[dy dx]`. Mirrors the Alignment feature preview.

Then set **Downsampling factor** to 2 and accept again. Downsampling affects DETECTION ONLY: the
composite must stay at full resolution and look the same as at factor 1 (same size, seam still
clean, green/magenta keypoints on top of each other, same recovered shift) — only the inlier COUNT
drops, because fewer blobs survive the resize. The title gains "detected at 1/2 scale". Verified
headlessly: factor 1 → 72/73 inliers, factor 2 → 3/3 inliers, both `[dy -26, dx -186]`, composite
326×486 in both cases and max keypoint tie-line 0.00 px. At factor 4 SURF finds too few blobs on
this set and RANSAC legitimately fails with the "could not fit a translation" dialog.

### Test 11 — Translation vs Affine (rotated tiles)

The affine dataset warps three of the four tiles by ±1° rotation, ±1% scale and ±8 px jitter.

- **Transform type = Translation** → the rating can still look good (on a 2×2 grid the rotation
  hides in the overlaps, not in loop inconsistency), but after *Stitch* the seams show
  rotated/doubled lines.
- **Transform type = Affine** → *Measure overlaps* switches to feature-based automatically
  (phase correlation cannot measure rotation), 4/4 edges valid; after *Optimize positions →
  Stitch* the lines/circles run continuously across every seam. Verified headlessly:
  transforms recovered to ≤ 0.22 (matrix max-abs), solver RMSE ≈ 0.02 px.

Same tiles, more variations (tick **Allow rotation** for the first two — the truth IS rotated):

- **Similarity** + Allow rotation → near-identical to Affine (the truth is rotation+scale, no shear).
- **Rigid** + Allow rotation → slightly worse than Similarity (the ±1% true scale cannot be fitted)
  but seams still visibly better than Translation.
- Any non-translation model with **Allow rotation UNCHECKED** → rotations locked to zero: the result
  degrades toward the Translation look (that is the point — the lock protects unrotated data from
  spurious rotations; on genuinely rotated data like this set you must tick the box).
- The `AllowRotation` checkbox must be disabled while Transform type = Translation. The
  Registration method dropdown is disabled for any non-translation type AND displays
  "Feature-based" (what actually runs — phase correlation cannot measure rotation); the
  user's own method choice comes back when Transform type returns to Translation.

### Test 12 — seam inspector on the sabotaged chain

The generator measures a 1×3 chain honestly, then corrupts the 2-3 edge by +24 px at
quality 0.95 (emulating a repetitive-content lock — injected directly because phase
correlation/RANSAC resist deterministic image-level sabotage) and saves everything as
`sabotage.mibstitch.json`.

1. **Load project** → the sabotage JSON. *Optimize positions* → the SOLVER part is blind
   (RMSE ≈ 0 — a chain has no loop, the residuals cannot see the corruption), but since
   2026-07-17 Optimize also re-reads the pixels at every solved seam: the chip comes out
   **red "Seams disagree (worst pixel match ≈ 0.1)"** instead of a lying green. The same
   check catches a wrong layout orientation (e.g. the horizontal chain laid out as
   vertical: RMSE 0.09 px, worst seam ≈ 0.07 → red chip).
2. **Inspect and fix...** → the 2-3 seam ranks FIRST with seam score ≈ 0.1 (vs 1.0 for 1-2);
   the pair view shows the COMPLETE pair at the solved offset (title: "Cyan: tile 2;
   Magenta: tile 3") — in the falsecolor overlay tile 2 is cyan, tile 3 magenta, and
   the ~24 px break shows as cyan/magenta ghosting in the overlap instead of white
   (try all overlay modes; Space flickers). The mouse wheel zooms at the cursor —
   zoom into the seam, nudge with the arrows and check the zoom SURVIVES the
   re-render; `F` (or wheeling out) fits the whole pair again.
3. Exclusion (the coarse option): select the bad seam → **Exclude (X)** → **Re-solve** →
   the springs pull tile 3 back to nominal (within the ~5 px cut jitter of truth); the seam
   score improves but stays modest. The button is a TOGGLE: while excluded it stays pressed,
   turns red and reads *Excluded (X)*, and stepping to another seam and back must restore the
   right look for each seam. **Watch the alignment chip in the Stitching window** — it must
   react to the exclusion, not sit on the pre-exclusion verdict: red *"Seams disagree (worst
   pixel match 0.09)"* → on Exclude, orange *"Seams edited — press Re-solve"* → on Re-solve,
   green (worst valid seam is now 1.00, solver ≈ 0.12 px). Press it (or `X`) again to
   re-include the edge, then fix it properly:
4. **Shift+click-to-correlate** (the real fix): with tile size 160 px, first drop *ROI
   size* to ~48 (the ROI must be smaller than the overlap region). Hold `Shift` — the
   cursor becomes a yellow ROI box — and click a distinctive spot inside the seam overlap
   → the pair snaps, the edge turns `user`, auto re-solve fires and the seam score jumps
   to ≈ 1.0 — sub-pixel, unlike the exclusion route.
5. Try the other fixing tools on the same seam: **drag** the overlay (tile j follows at
   50% alpha, release applies), **Two-click match** (click the same landmark in the
   side-by-side tiles). The keyboard never moves a tile — arrows and Q/W are slice
   navigation (on this 2D set they only report "no Z slices"). `Z` undoes back to the
   corrupted automatic edge — handy for repeating the exercise.
6. Check the review keyboard: `Enter` confirm + jump, `N`/`P` navigate, mini-map click jumps
   to a tile's worst seam. The mini-map shows the low-res fused preview behind the score
   tints — after the click-fix the seams in that preview should visibly close up.
7. **Fusing and saving the corrections**: the inspector has NO *Re-fuse* and NO *Save
   project* button (both duplicates removed 2026-07-26) — its bottom row is Confirm /
   Exclude / Re-solve / Close. With the seam fixed and the inspector still open, use the
   Stitching window:
    - *Stitch* → the fused dataset opens in MIB with lines continuous across every seam.
      Repeat with Output mode = OME-Zarr (BigData) for the streaming path (the pyramid
      settings must NOT be re-asked for the same output path).
    - *Save project* → reload it and confirm the fix survived, i.e. the parent's save
      carries the inspector's edits with no hand-off.
    - The stale-positions guard: untick *Auto re-solve*, apply a nudge, then press *Stitch*
      WITHOUT pressing *Re-solve* — the pending solve must run first, so the result matches
      the fix rather than the pre-nudge positions.

### Test 13 — 3D affine (in-plane affine on Z-stack tiles)

The 3D analogue of test 11: a 2x2 grid over **2 Z-layers** of 16-slice Z-stack tiles; every tile
except the first is warped by its own in-plane ±1° rotation / ±1% scale / ±8 px jitter (the SAME 2D
warp on every slice — z stays translational), and layer 2 is Z-jittered by ±2 slices against the
nominal in `positions.txt`.

- **Transform type = Translation** → seams show rotated/doubled lines on every slice after *Stitch*.
- **Transform type = Affine** + **Allow rotation** → *Measure overlaps* runs feature-based on the
  depth-flattened tiles (within-layer edges carry the affine; cross-layer edges stay translation),
  *Optimize positions* solves in-plane affine + scalar z; after *Stitch*, scroll Z: lines/circles are
  continuous across every seam on every slice, and the embedded tilted planes run continuously across
  the layer boundary (a Z misalignment breaks them — the chip would show "Check Z alignment").
- Verified headlessly by `StitchCoreTest.fullChain3DAffine_measureSolveFuseAcrossLayers`.

### Test 14 — save/load project: state vs settings

A project file carries the STATE of one stitch (tiles, seam measurements, solved positions)
*and* the SETTINGS it was produced with, so **Load project** asks which is meant. No generator
needed — this reuses datasets 1 and 6.

1. Stitch dataset 1 as in test 1 (Grid, Rows 3, Cols 3, **Estimate overlap**) up to
   *Optimize positions*, then **Save project** to any path.
2. Now mess the dialog up: Layout source → *Filename pattern*, untick Estimate and set
   Overlap X/Y = 40, Transform type → *Affine* + **Allow rotation**, Blend mode → *Max*,
   Output mode → *OME-Zarr3 (BigData)*. Closing and reopening the tool is a fair extra step.
3. **Load project** → pick the saved file. A dialog must appear, naming the file and
   summarising it (*"9 tiles, 12 measured seams, solved positions"*).
    - **Cancel** first — nothing may change.
    - Then **Restore everything**: every widget snaps back to the saved values (Grid, 3×3,
      Estimate overlap on, Translation, Overwrite, In memory), the status line reports the tiles /
      edges / solved state, the preview redraws at the **solved** positions, and
      *Inspect and fix...* is enabled **without re-measuring**.
4. Now the "same recipe, other files" case: browse a DIFFERENT set of tiles
   (`06_stitch_smoke_feature\tiles`, 9 files), then **Load project** → the same file →
   **Settings only**. The parameters change but the <span>Input path</span> must still list the
   NEW tiles; the status line reads *"Settings loaded from … — layout rebuilt: 9 tiles,
   re-measure to continue"*, edges/positions are cleared and *Inspect and fix...* is disabled.
   *Measure overlaps → Optimize → Stitch* then runs on the new tiles with the old parameters.
5. Settings-only with an INCOMPATIBLE input: with a folder of tiles selected, load a project
   saved under *Position file*. The layout must be dropped and the status line must ask for a
   re-select — no modal error dialog.
6. Back-compat: test 12's `sabotage.mibstitch.json` is written by a script that stores no
   settings block, so it must load its state **with no dialog at all**. (Any file saved from the
   GUI does show the dialog.)
7. **Loading over a finished job** (regression, 2026-07-26): run test 11 to completion (2×2
   affine grid, Measure → Optimize → Stitch), then **Load project** → test 12's
   `sabotage.mibstitch.json` → *Measure overlaps* → *Optimize positions*. The preview must
   show the sabotage **1×3 chain** throughout. It used to come back as test 11's 2×2 grid:
   the pre-v3 file carries no settings, so the widgets still described job 11, and
   **Estimate overlap** rebuilt the layout from them. <span>Input path</span> must also list
   the three `12_stitch_smoke_sabotage\tiles\tile_0#.tif` after the load, not job 11's files.

### Test 15 — Fibics Atlas: the three import modes

An Atlas mosaic folder can carry Atlas's own finished stitch beside the acquisition record.
The generator writes all three files, with the `.ve-mif` stage grid **deliberately 8 px too
long per row in Y** (1 px per column in X) while the `.ve-tie` / `.ve-updates` describe the
correct placement — the real failure this source exists to cope with.

An Atlas mosaic has **no layout source of its own** — it is a file that says where the tiles
go, so it lives under **Position file** alongside the position text file, told apart by
extension. Set *Layout source* = **Position file**, browse with the Input **…** button and
pick `MosaicInfo_SMOKE.ve-mif` (a single FILE, not a folder). A dialog must appear listing
both sidecars with their counts (*12 measured seams*, *9 solved tile positions*) and offering
three buttons. Run the test once per button; the layout preview must refresh by itself each
time, without pressing *Preview layout*.

1. **Nominal grid only** — status reads `9 tiles | 0 edges measured | solved: no`, the chip is
   blank (`Alignment: —`). *Measure overlaps → Optimize positions* must then pull the mosaic
   into line (chip green, error well under 1 px). Stitching straight from the nominal grid
   instead — press **Stitch** on a fresh import — is the negative control: with *Estimate
   overlap* unticked the seams visibly step by ~8 px per row.
2. **Atlas seam measurements** — status jumps to `9 tiles | 12 edges measured | solved: no`
   with **no progress bar and no image reads**: the seams came from the file. Press
   *Optimize positions* only; the chip must go green and the preview title must say **solved**.
3. **Atlas seams + solved positions** — status reads `solved: yes` immediately and the chip is
   already green (**Excellent alignment**, seam match ≈ 1.00) — MIB re-read the overlap pixels
   at Atlas's positions to earn that rating, so a short progress bar here is expected. Press
   **Stitch** directly: nothing may re-measure or re-solve, and the mosaic must be seamless.

Also check:

- **Tile paths.** The XML records `E:\acquired\session\SMOKE\…`, which does not exist. The
  tiles must still load, because they are looked up by name next to the `.ve-mif`.
- **Disabled settings.** On the *Tile settings* tab, Rows / Cols / Tile order / Overlap X/Y /
  *Estimate overlap* and *Tiles are folders* are all disabled — the Atlas layout is fully
  determined by the file.
- **Project round-trip.** **Save project** after mode 3, then **Load project** →
  *Restore everything*: the layout source must come back as *Position file* with the
  solved positions intact.
- **Re-picking.** Browse the same `.ve-mif` again — the dialog must default to the button you
  chose last time.
- **Sidecar-free folder.** Delete (or rename) the `.ve-tie` and `.ve-updates` and re-pick the
  `.ve-mif`: **no dialog at all** must appear, and the tool behaves like mode 1.
- **Only the `.ve-mif` is offered.** In the picker, the *Fibics Atlas mosaic* filter must list
  the `.ve-mif` alone — the `.ve-tie` / `.ve-updates` are found from it, not chosen. Switching
  to *All files* and selecting `MosaicInfo_SMOKE.ve-tie` anyway must still resolve back to the
  `.ve-mif` and behave identically, not error.
- **A plain position file still works under the same source.** Without changing *Layout
  source*, load test 3's `03_stitch_smoke_3d\positions.txt`: the text form must build its
  layout as before, with no Atlas import dialog and no leftover seams/positions.

### Test 16 — SerialEM: tiles as slices of one MRC stack

A SerialEM montage is **two files** — `Montage_SMOKE.mrc`, in which every tile is a SLICE, and
`Montage_SMOKE.mrc.mdoc` beside it saying where those slices go. This is the only layout source
where the tiles are not separate files, so it is worth confirming that nothing along the way
assumed they were.

Like Atlas it has **no layout source of its own**: set *Layout source* = **Position file** and
browse with the Input **…** button, then pick `Montage_SMOKE.mrc.mdoc`. The picker offers the
**`.mdoc` alone** — the stack is found from it. A dialog must appear listing what the `.mdoc`
holds (*12 measured seams*, *9 solved tile positions*) and offering three buttons. Run once per
button; the layout preview must refresh by itself each time.

The generator makes the recorded piece grid **4 px too long in X and 6 px in Y** while the edge
shifts and `AlignedPieceCoords` describe the correct placement.

1. **Nominal grid only** — status reads `9 tiles | 0 edges measured | solved: no`, chip blank.
   Pressing **Stitch** straight away (with *Estimate overlap* unticked) is the negative control:
   the lines and circles visibly break at every seam. *Measure overlaps → Optimize positions*
   must then pull it into line (chip green, error well under 1 px).
2. **SerialEM seam measurements** — `9 tiles | 12 edges measured | solved: no` with **no progress
   bar and no image reads**. Press *Optimize positions* only; chip green, preview title *solved*.
3. **SerialEM seams + solved positions** — `solved: yes` immediately, chip already green
   (**Excellent alignment**, seam match ≈ 1.00; a short progress bar is expected, that is the
   pixel verification). Press **Stitch** directly: nothing may re-measure or re-solve.

Also check:

- **Only the `.mdoc` is offered.** In the picker, the *SerialEM montage* filter must list the
  `.mdoc` alone. Switching to *All files* and selecting `Montage_SMOKE.mrc` anyway must still
  resolve to the same montage and behave identically (that path is what batch protocols use).
- **A bare stack is refused with an explanation.** Copy `Montage_SMOKE.mrc` to another folder
  WITHOUT its `.mdoc` and pick it via *All files*: MIB must say no `.mdoc` was found, not try
  to read the binary as a position text file.
- **The image path inside the file is wrong on purpose.** The `.mdoc` records
  `E:\acquired\session\SMOKE\Montage_SMOKE.mrc`; the montage must still open, because the stack
  is found next to the `.mdoc`.
- **Float rescale.** The stack is float32 on an offset range (≈180000–204000). The fused mosaic
  must come out `uint16` and look normal — a black or blown-out result means the header-based
  rescale was skipped. All nine tiles must share one scale.
- **Disabled settings.** On the *Tile settings* tab, Rows / Cols / Tile order / Overlap X/Y /
  *Estimate overlap* and *Tiles are folders* are all disabled.
- **The seam inspector works on slices.** Open **Inspect and fix...** after mode 2 and step
  through the seams — every pair view must render (this reads sub-regions of individual slices
  through the ranged fast path, which is where an index-mirroring bug would surface as a
  vertically flipped or offset crop).
- **Project round-trip.** **Save project** after mode 3, then **Load project** →
  *Restore everything*: source back as *Position file*, solved positions intact.
- **Not every `.mdoc` is a montage.** SerialEM writes the same format for tilt series. There is
  no such file in the smoke data; to check the guard, copy the `.mdoc`, delete every
  `PieceCoordinates` line from the copy, rename the pair, and pick it — MIB must say it is not a
  montage rather than trying to stitch it.
- **A plain position file still works under the same source.** Without changing *Layout source*,
  load test 3's `03_stitch_smoke_3d\positions.txt` — no import dialog, no leftover seams.

!!! note "The seams are still visible, and that is not an alignment problem"
    The generator bakes a 6 % per-tile illumination gradient into the tiles, as a poorly centred
    TEM beam produces. Even at the pixel-perfect placement of mode 3 the mosaic shows faint 3×3
    blocking. That is shading, not misalignment — the geometry check is the lines and circles
    running unbroken across every seam, not the brightness.

    Fix it with <span class="widget widget-dropdown">Intensity correction</span> = **Flat-field
    (shared)** and re-Stitch: the blocking must visibly drop while the lines and circles stay
    exactly where they were (the correction changes intensities only, never geometry). Then check
    that **Match tile means** does almost nothing on the same data — that is the point of having
    both. Measured on this dataset, as rms brightness mismatch across the 12 seams: None 3.29 %,
    Match tile means 3.31 %, **Flat-field 1.24 %**.

    Note this generator writes a canvas with **no monotonic ramp**, unlike the others. A ramp is
    indistinguishable from an illumination field to a mean-based estimator, and with one the
    flat-field correction makes this montage *worse* (8.08 %) instead of better — which is the
    documented small-N failure mode, not a bug.

### Test 17 — the uncovered frame (Canvas color / Autocrop)

Any jittered dataset works; dataset 1 is the quickest. Measure → Optimize → Stitch, then read the
mosaic's edges.

1. **Canvas color = white (default).** The ragged frame around the mosaic must be at the class
   ceiling — pure white on the 8-bit smoke tiles, not mid-grey. Check with the pixel-value readout
   at a corner outside the tiles, not by eye: a wrongly-scaled fill would still look bright.
2. **Canvas color = black, Stitch again.** Same geometry, frame now zero. The mosaic INSIDE must be
   bit-identical to run 1 — the fill may never touch a pixel a tile covers.
3. **Tick Autocrop, Stitch again.** The dataset dimensions (Datasets panel) must SHRINK, and no
   background may be left anywhere along the edges. Flip Canvas color between black and white with
   Autocrop on: the two mosaics must now be indistinguishable, which is the real check that the
   frame is gone rather than merely smaller.
4. **Autocrop is a canvas-plan change, not a post-process.** Repeat step 3 with Output mode =
   **OME-Zarr3 (BigData)** — the reopened BigData dataset must have the same cropped dimensions,
   and the pyramid must be built on the cropped mosaic (no frame at the lowest level either).
5. **Toggling Autocrop must re-plan.** With a mosaic already stitched, tick/untick the checkbox and
   press Stitch without touching anything else: the size must change each time. A cached canvas
   surviving the toggle would silently fuse the previous size.

## Expected numbers (from headless validation)

| Dataset | Recovered origin error |
|---------|------------------------|
| `01_stitch_smoke` (2D grid) | ≤ 0.16 px |
| `03_stitch_smoke_3d` | ≤ 0.03 px (all 3 axes) |
| `05_stitch_smoke_pattern_folders` | ≈ 0.02 px |
| `06_stitch_smoke_feature` (feature-based) | ≤ 0.5 px |
| `07_stitch_smoke_bioformats` | ≈ 4 px from the metadata alone, ≤ 0.02 px after Optimize |
| `11_stitch_smoke_affine` (TransformType=Affine) | ≤ 0.22 matrix max-abs, RMSE ≈ 0.02 px |
| `13_stitch_smoke_affine3d` (TransformType=Affine) | 12/12 edges valid; ≤ 0.39 matrix max-abs, RMSE ≈ 0.09 px, layer dz exact |
| `12_stitch_smoke_sabotage` | corrupted seam scores 0.09 vs 1.00; exclude+re-solve → ≤ 6 px; click-fix → ≤ 1 px |
| `15_stitch_smoke_atlas` | nominal grid 16 px off; solve on imported `.ve-tie` → 0.07 px; imported `.ve-updates` → 0.00 px, seam scores 1.00 |
| `16_stitch_smoke_mdoc` | nominal grid 12 px off (seam scores 0.09–0.64); solve on imported edge shifts → 0.05 px; imported `AlignedPieceCoords` → 0.00 px, seam scores 1.00; MIB's own measure+solve from the images → 0.04 px |
| `16_stitch_smoke_mdoc` (Intensity correction) | rms seam brightness mismatch: None 3.29 %, Match tile means 3.31 %, Flat-field (shared) 1.24 %. Real `Cell1.mrc` for comparison: 3.50 / 3.13 / 1.04 % |
