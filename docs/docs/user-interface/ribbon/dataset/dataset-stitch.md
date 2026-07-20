# Stitching

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Dataset](index.md)*

---

## Overview

The Stitching tool assembles a collection of 2D image tiles into a single large mosaic.
Starting from a rough initial placement (a regular grid, a position file, or a filename
pattern), the tool measures the true overlap between neighboring tiles using phase
correlation, finds a globally consistent position for every tile, and fuses the tiles
into a new dataset.

Both 2D tile collections and 3D tiles (Z-stacks) are supported: for 3D data the tool
performs a single global optimization that jointly minimizes the within-layer (XY) and
between-layer (Z) constraints, rather than stitching each layer in 2D and aligning the
layers afterwards.

Small mosaics are assembled directly in memory; mosaics that exceed available memory can
be streamed to an OME-Zarr file and opened in MIB as a BigData dataset.

<!-- ![Stitching Window](images/menuDatasetStitch.png){.on-glb align=left width="400"} -->

---

## The stitching pipeline

Stitching runs in four stages, each with its own button. The stages can be triggered one
by one — recommended for the first time, to check intermediate results — or the
<span class="widget widget-button">Stitch</span> button runs any stages not done yet
automatically.

1. <span class="widget widget-button">Preview layout</span> — draws the nominal tile
   arrangement as numbered rectangles on the preview axes. Use it to verify that the
   grid dimensions, tile order, and overlap settings are correct **before** any heavy
   computation: wrong settings show up as an incorrect numbering sequence or as gaps
   between rectangles.

    Tick <label class="widget widget-checkbox">Edit layout (drag tiles)</label> to switch the
    preview into **interactive placement** mode: each tile becomes a draggable rectangle (its size
    is fixed — only the position moves). Drag tiles to a better rough arrangement when there is no
    grid/position file to start from, or to fix a badly-placed tile. Each move updates that tile's
    nominal position and clears any previous measurement, so the next
    <span class="widget widget-button">Measure overlaps</span> / <span class="widget widget-button">Optimize positions</span>
    run starts from the corrected layout. Untick to return to the static view.

2. <span class="widget widget-button">Measure overlaps</span> — for every pair of
   neighboring tiles, the expected overlap region is cut from both tiles and their
   *actual* relative displacement is measured with FFT phase correlation. Each
   measurement gets a quality score from 0 to 1: a crisp, well-textured overlap scores
   close to 1, while a featureless or non-matching overlap scores close to 0.
   Measurements below the quality threshold are marked invalid.

3. <span class="widget widget-button">Optimize positions</span> — computes the final
   position of every tile. Pairwise measurements are only *relative* statements
   ("tile 5 sits 342.7 px right of tile 4"), and with more measurements than tiles they
   slightly contradict each other. Instead of chaining tiles one after another (which
   accumulates drift), the tool solves one global least-squares problem over the whole
   tile graph: every valid measurement is an equation weighted by its quality, and all
   positions are found at once. Tiles whose measurements were rejected are held near
   their nominal grid positions. The result is summarised by a colour-coded quality
   rating — **Excellent** (green) / **Good** / **Fair** / **Poor** (red) — built from two
   independent checks (both in the chip's tooltip):

    - the **solver residual** — how much the pairwise measurements still disagree at the
      solved positions (RMSE in pixels). Note this is blind on chain-like layouts: with
      no loops in the tile graph the residual is ~0 whatever the measurements claim;
    - the **pixel seam check** — the overlap pixels are re-read at every solved seam and
      cross-correlated (the same score the seam inspector ranks by). If the worst seam
      matches poorly the chip turns orange **Check seams** or red **Seams disagree** even
      when the residual looks perfect — the signature of a wrong layout
      orientation/order or a confidently-wrong measurement. Z-stack tiles are scored
      **slice by slice at the solved Z offset**, and seams between Z-layers are
      additionally re-scored at nearby Z offsets: if the pixels prefer a different Z
      the chip turns orange **Check Z alignment** and the inspector's offset readout
      states the preferred shift (e.g. *pixels prefer dz+2*).

    If any tile has **no valid measurement at all** the chip turns orange —
    **Alignment incomplete** — because such a tile is simply parked at its nominal
    position and neither check covers it; check the grid rows/cols or fix its seams in
    the inspector. The layout preview refreshes automatically after every solve and
    shows the **solved** positions (the title states solved vs nominal).

4. <span class="widget widget-button">Stitch</span> — fuses the tile pixels into the
   output mosaic at the optimized positions, blending the overlap regions according to
   the selected blend mode, and opens the result as a new dataset in MIB.

---

## When automatic stitching fails: Inspect & fix

Automatic stitching can fail silently: a measurement that locked onto repetitive content
one period off satisfies the solver perfectly on sparse tile arrangements — the quality
rating stays green while a tile sits a full period out of place. The
<span class="widget widget-button">Inspect & fix…</span> button (enabled after
*Measure overlaps* + *Optimize positions*) opens the **seam inspector** for a
worst-first manual review:

- Every tile pair gets a **seam score** — how well the actual pixels agree at the solved
  placement — and the seams are listed worst-first. This catches wrong-but-confident
  measurements that the residual rating cannot see.
- The **mini-map** shows the layout with tiles coloured by their worst seam
  (green → red); click a tile to jump to its worst seam. For datasets of
  reasonable size a **low-res fused preview** is drawn behind the colouring at the
  current solved positions — it follows every re-solve, so a grossly misplaced tile
  is visible in the actual image content.
- The **pair view** shows the **complete tile pair** composited at the solved offset
  (downsampled for display when the tiles are large; the title is the colour legend,
  e.g. *Cyan: tile 2; Magenta: tile 4*). Overlays: falsecolor — tile *i* **cyan**, tile *j*
  **magenta**, so aligned structures add up to **white** while misaligned ones split
  into cyan/magenta ghosts — flicker (++Space++ toggles the two tiles), checkerboard,
  or difference. The **mouse wheel zooms** the pair view at the cursor — the zoom is
  kept through nudges, drags and fixes of the same seam;
  <span class="widget widget-button">Fit view (F)</span> (or zooming all the way out)
  restores the full-pair view.
- Per seam: <span class="widget widget-button">Confirm (Enter)</span> marks it reviewed
  and jumps to the next worst; <span class="widget widget-button">Exclude (X)</span>
  removes its measurement from the solve (the tile is then held near its nominal
  position); <span class="widget widget-button">Re-solve</span> recomputes all positions
  and re-ranks. ++N++ / ++P++ step through the ranking.
- Review decisions are saved with the project file and survive re-measuring.

### Fixing a bad seam

A fixed seam becomes a high-weight *user* measurement that steers the global solve (it is
never pruned, and it survives a re-measure). Pick whichever tool fits how wrong the seam is:

- **Hold ++shift++ and click a landmark** in the pair view — the strongest tool for the
  common case. While ++shift++ is held the cursor becomes a box showing exactly the region
  (<span class="widget widget-edit">ROI size</span>; resize it with ++shift++ + mouse
  wheel) that will be used: on click it is cut
  from the first tile and cross-correlated against the second within
  <span class="widget widget-edit">Search radius</span> of the current offset; a confident
  peak snaps the pair to sub-pixel alignment. A weak or ambiguous match only reports why and
  never moves the tile. On small tiles keep the ROI smaller than the overlap region.
- **Drag** the overlay — the second tile follows the pointer at 50% opacity; release applies
  the shift. Offsets are edited **by mouse only** — the keyboard never moves a tile: the
  arrows and ++q++ / ++w++ are slice navigation, and fine adjustment is what
  ++shift++-click is for (sub-pixel, both axes at once).
- **3D pairs** are shown one **slice pair** at a time (the title's second line names the
  shown slices, e.g. *Slice 5/8 — Q/W browses*, or per colour when the two tiles show
  different slices), browsed with ++q++ / ++w++ or ++down++ / ++up++ — previous / next,
  exactly like the main MIB window (++shift++ = 5) — always view-only, browsing never
  moves a tile. The
  <span class="widget widget-dropdown">Fix mode</span> dropdown decides what a fix edits:
    - **Fix XY** (default): the in-plane offset. Both tiles browse together, aligned by
      the current Z relation; fix seams with the usual tools on any slice.
    - **Fix Z (match slices)**: for checking that each mosaic slice **continues** the
      slice below it. The view shows **one tile** at two consecutive slices — slice
      *z−1* in **cyan** and slice *z* in **magenta**, fully overlapping, so the image
      is mostly **white** when the mosaic is aligned in Z. ++q++ / ++w++ or ++down++ /
      ++up++ moves the boundary through the stack (view-only). Where the slices jump
      apart (cyan/magenta ghosting), **drag** the magenta slice onto the cyan one, or
      hold ++shift++ and **click a landmark** for the same sub-pixel cross-correlation
      as in XY. **The fix shifts that slice and every slice above it, across the whole
      mosaic** — the slices below stay put — and is applied at *Re-fuse* / *Stitch*
      (the tiles' solved positions are untouched; no re-solve involved). Corrections
      accumulate per boundary, are saved with the project, and ++z++ removes the one
      at the boundary on screen. On a 2D dataset there are no Z slices to align, so
      the mode stays at Fix XY (a dialog explains). For deeper, non-rigid per-slice
      registration use the [Alignment tool](dataset-alignment.md) on the fused dataset.
- <span class="widget widget-button">Two-click match</span> — when the offset is hopeless
  (e.g. a tile locked a full texture period off, beyond any search radius): both full tiles
  are shown side by side; click the same landmark once in each, and the click difference
  becomes the offset (sharpened by a local correlation).
- ++z++ / <span class="widget widget-button">Undo fix (Z)</span> — restores the original
  automatic measurement of the current seam.

With <span class="widget widget-checkbox">Auto re-solve</span> on (default), every fix
immediately re-solves all positions, re-scores and re-ranks — work worst-first until the
top of the list is green, then press <span class="widget widget-button">Re-fuse</span> to
fuse the mosaic with the corrected positions without leaving the inspector (identical to
*Stitch* in the main window, for both output modes; if a fix is still awaiting its
re-solve, the solve runs first). Saving the project persists all fixes either way.

---

## Input panel

- <span class="widget widget-dropdown">Layout source</span>: how the tiles are arranged
    - **Grid**: tiles form a regular grid; specify rows, columns, acquisition order, and overlap in the Grid panel.
    - **Position file**: a text file with one line per tile: `filename X Y` or `filename X Y Z`
      (space-, tab-, or comma-separated). The optional Z column places tiles on distinct layers;
      layers that overlap in Z are refined by the same global solve as the XY overlaps.
    - **Filename pattern**: grid indices are parsed from `_Z##-X##-Y##` tokens in the file (or, for
      folder tiles, the **folder**) names — the pattern produced by the MIB dataset chunking tool.
      Tiles default to abutting (0% overlap, exact reassembly of chunks); set **Overlap X/Y** (or tick
      **Estimate overlap**) when the pattern-named tiles come from an overlapping acquisition and the
      tool will register them like the Grid source.
    - **Bio-Formats metadata**: tile positions are read from the **stage coordinates embedded in the
      image metadata** (OME `Plane PositionX/Y/Z`) — no manual arrangement needed. Point it at one
      multi-series file (each series is a tile) or at several single-tile files; the microscope's
      recorded positions become the nominal layout, converted from micrometres to pixels via the
      stored pixel size. Distinct stage-Z values are placed on separate layers and jointly solved.
- <label class="widget widget-checkbox">Tiles are folders (Z-stacks)</label>: each tile is a **folder of
  slice images** (a Z-stack) rather than a single image file. This is orthogonal to the layout source —
  it changes only how each tile is *provided*, not how tiles are *arranged*:
    - With **Grid** or **Filename pattern**, the <span class="widget widget-button">...</span> button
      multi-selects the tile folders (each a Z-stack). Ideal for 3D acquisitions where every XY tile was
      captured as a folder of slice images.
    - With a **Position file**, simply list folder paths in the `filename` column — folders are detected
      automatically, so this checkbox is not needed (and is disabled) for that source. It is likewise
      disabled for **Bio-Formats metadata**, where each series/file already carries its own stack.
- <span class="widget widget-edit">Input path</span>: the selected tile image files (Grid, Filename pattern — the <span class="widget widget-button">...</span> button opens a multi-select file picker; selection order does not matter, the tiles are natural-sorted by name), the selected tile folders (when *Tiles are folders* is on), the position file, or the selected Bio-Formats file(s). A folder path typed/pasted directly into the field also works for Grid/Filename pattern — all image files in that folder become the tiles.

---

## Grid panel

Rows / Cols / Tile order apply to the **Grid** source. Overlap X/Y and *Estimate overlap* apply to
both the **Grid** and **Filename pattern** sources (both derive tile grid indices). Any change here
immediately rebuilds the layout and refreshes the preview — as does changing the
<span class="widget widget-dropdown">Layout source</span> itself (e.g. from **Grid** to
**Filename pattern** after noticing the grid guess was wrong); if the already-selected input cannot
be used with the new source, the stale layout is dropped and the status line asks you to re-select
the input.

- <span class="widget widget-edit">Rows</span> / <span class="widget widget-edit">Cols</span>: grid dimensions; `0` derives the value automatically from the number of tiles — the closest-to-square arrangement that tiles the count *exactly*, so no phantom grid holes, oriented by the *Tile order*: a Horizontal order gives the wide arrangement (3 tiles → 1×3, 12 → 3×4), a Vertical order the tall one (3 → 3×1, 12 → 4×3). For an intentionally incomplete grid (e.g. 11 tiles of a 3×4 acquisition) enter the rows/cols explicitly.
- <span class="widget widget-dropdown">Tile order</span>: the order in which the tiles were acquired, which defines how the natural-sorted filenames map onto grid cells
    - **Horizontal**: left→right, row by row.
    - **Horizontal snake**: left→right, then right→left on the next row.
    - **Vertical**: top→bottom, column by column.
    - **Vertical snake**: top→bottom, then bottom→top on the next column.
- <span class="widget widget-edit">Overlap X</span> / <span class="widget widget-edit">Overlap Y</span>: nominal overlap between adjacent tiles, in percent of the tile size (0–90). While
  <label class="widget widget-checkbox">Estimate overlap</label> is enabled the spinners are disabled and
  act as a read-only display of the estimated values.
- <label class="widget widget-checkbox">Estimate overlap</label>: determine the actual overlap from the
  images themselves before measuring (*recommended, on by default*). Each sampled neighbor pair is
  registered by unrestricted whole-tile phase correlation with cross-correlation verification of the
  candidate peaks, and the median over all pairs gives a robust estimate of the real grid step — even
  when a fraction of the pairs fails. The *Overlap X/Y* fields are updated with the estimate and only
  serve as a rough starting guess.

!!! tip
    With <label class="widget widget-checkbox">Estimate overlap</label> enabled the entered overlap
    values barely matter — enter any rough guess. Without it, the overlap must be accurate to within
    a few percent: the measurement stage tolerates tile-position jitter of tens of pixels around the
    nominal placement, but not a systematically wrong overlap.

---

## Registration panel

- <span class="widget widget-dropdown">Transform type</span>: the geometric model solved per tile
    - **Translation** (*default*): tiles only shift — the right model for stage-tiled acquisitions,
      where the stage moves but does not rotate. Tiles are placed without resampling, preserving
      the original pixel values exactly.
    - **Rigid**: shift + rotation (no scale change) — tiles that are rotated against each other
      but keep their pixel size.
    - **Similarity**: shift + rotation + one uniform scale factor per tile.
    - **Affine**: the full linear model — rotation, scale, and shear per tile.

    All non-translation models need image features to measure, so they always use the
    feature-based estimator (the *Registration method* dropdown is disabled), and the fused tiles
    are resampled (bilinear) into their transformed positions. On 3D / multi-layer layouts the
    transform acts **in-plane**: every slice of a Z-stack tile is warped by that tile's single 2D
    transform, while Z itself stays translational — cross-layer overlaps are always measured and
    solved as plain Z/XY shifts. Internally the global solve is always the (linear) affine one;
    Rigid/Similarity are obtained by projecting each tile's result onto the smaller model — there
    is no extra cost to the richer models.
- <label class="widget widget-checkbox">Allow rotation</label> *(non-translation models only)*:
  permit per-tile rotation. **Off by default** — microscope stages translate but do not rotate, and
  with rotation locked a few noisy overlap measurements cannot inject small spurious rotations that
  compound across a large mosaic. Leave it off for stage-tiled data even with Similarity/Affine
  (you still get scale/shear); tick it only when the tiles are genuinely rotated against each
  other. With rotation off, *Rigid* becomes equivalent to *Translation*.
- <span class="widget widget-dropdown">Registration method</span>: how each pairwise overlap is measured
    - **Phase correlation** (*default*): FFT phase correlation on the overlap strip. Best for the
      normal case — small-to-moderate overlaps with modest positioning jitter — and robust on
      low-contrast, feature-poor content where feature detectors find nothing.
    - **Feature-based**: detects and matches keypoints over the **whole tiles** and RANSAC-fits
      a translation. Use it when the initial positions are badly wrong or unknown (large jitter,
      arbitrary layouts) — cases where the phase-correlation search, which only looks near the
      nominal position, misses the true offset. Its weakness is feature-poor or strongly repetitive
      content, where too few reliable matches survive; there phase correlation still wins.
- <span class="widget widget-dropdown">Feature detector</span> *(Feature-based only)*: the keypoint
  detector — the same eight choices as the [Alignment](dataset-alignment.md) tool
  (SURF, SIFT, MSER, Harris, BRISK, FAST, Minimum Eigenvalue, ORB). SURF is a good default for
  microscopy blobs.
- <span class="widget widget-button">Settings…</span> *(Feature-based only)*: opens a dialog to tune
  the selected detector's parameters, the **rotation-invariance** flag, the detection **downsampling
  factor** (1 = full resolution; higher is faster but less precise on big tiles), and the RANSAC
  (`estgeotform2d`) trials / confidence / max-distance — identical to the Alignment tool's feature
  settings.

!!! tip
    Keep **Phase correlation** for tidy grid/position-file acquisitions. Switch to **Feature-based**
    when the alignment quality comes out *Poor* with large residuals and you suspect the tiles are
    far from their nominal positions.

- <span class="widget widget-edit">Quality threshold</span>: minimum quality score (0–1, default 0.30) to accept a pairwise measurement.
  Increase it when wrong matches slip through (e.g. repetitive patterns); decrease it for low-contrast data where valid overlaps score low.
- <span class="widget widget-edit">Nominal position weight</span>: how strongly tiles with weak or rejected
  measurements are pulled back toward their nominal grid positions (0–1, default 0.10). With `0` such
  tiles are positioned only through their other, valid measurements.
- <label class="widget widget-checkbox">Sub-pixel placement</label>: refine each pairwise-shift **measurement** to
  sub-pixel precision with a parabolic fit to the correlation peak. Off by default, so the measured shifts are
  whole-pixel unless you tick it.

    !!! note "What it does and does not affect"
        Despite the label, this option controls the **measurement** step, not where the tiles finally land.
        Tile *placement* is always rounded to whole pixels: `planCanvas` places every tile at an integer origin
        and keeps the discarded fraction as a per-tile *sub-pixel residual* in the project file (the fuse step
        does not resample by it yet). Enabling this therefore sharpens the shifts that feed the global solve —
        useful when many small overlaps each carry a fraction of a pixel that accumulates across a large grid —
        but any single tile still snaps to the nearest whole pixel in the output mosaic.

---

## Output panel

- <span class="widget widget-dropdown">Output mode</span>:
    - **In memory**: the mosaic is assembled in RAM and replaces the current dataset. Use for mosaics that comfortably fit into memory.
    - **OME-Zarr3 (BigData)**: the mosaic is streamed chunk-by-chunk to an OME-Zarr v3 file on disk and opened as a BigData dataset. Use for mosaics of any size.
- <span class="widget widget-edit">Output path</span>: destination of the OME-Zarr3 file (OME-Zarr3 mode only).

    !!! info "Pyramid settings dialog"
        When you press <span class="widget widget-button">Stitch</span> in **OME-Zarr3 (BigData)** mode, MIB shows the same
        **Export to Zarr3** settings dialog used by the standard dataset→OME-Zarr export, so the streamed mosaic is written
        as a proper multi-resolution pyramid. You choose:

        - **Pyramid levels** (`0` = auto: add levels while `min(Y,X)/2 ≥ 256 px`, up to 8; or a fixed `1–12`),
        - **Chunk size** `[Y, X, Z]` and **Shard factors** `[Y, X, Z]` (how many chunks to bundle per shard file; `0` = off),
        - **Compression** (`zstd` / `gzip` / `none`),
        - **Downsampling method** and **strategy** (`XY only`, or `Anisotropy-preserving` for anisotropic 3-D stacks).

        Smart defaults are seeded from the mosaic's dimensions and voxel size. The choice is remembered for the current
        output path, so an inspector **Re-fuse** reuses it without re-asking; picking a new output path or switching output
        mode asks again. Batch/headless runs skip the dialog and use the defaults (or values supplied in `BatchOpt`).
- <span class="widget widget-dropdown">Blend mode</span>: how pixel values are combined where tiles overlap
    - **Feather**: weighted blend, weights ramp down toward each tile border — smooth, seam-free transitions (*recommended*).
    - **Average**: plain average of all overlapping tiles.
    - **Max**: maximum intensity of the overlapping tiles.
    - **Overwrite**: the later tile wins; hard seams, but no intensity mixing.
- <label class="widget widget-checkbox">Save project JSON</label>: after stitching, save a project sidecar file next to the input tiles (see below).

---

## Project files

The complete stitching state — tile list, nominal and optimized positions, all pairwise
measurements with quality scores, and output settings — can be saved to a
`*.mibstitch.json` sidecar file with <span class="widget widget-button">Save project</span>
and restored later with <span class="widget widget-button">Load project</span>. This makes
a stitch reproducible and allows re-fusing the same layout with different blend or output
settings without re-measuring.

---

## Batch mode

The tool is compatible with the [Batch processing](../home/home-batchprocessing.md) tool
(*Ribbon → Dataset → Stitch*). In batch mode the whole pipeline runs headlessly from the
specified parameters; the `showWaitbar` option (batch-only) controls whether a progress
bar is displayed.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Dataset](index.md)*
