# Stitching

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Dataset](index.md)*

---

## Overview

The Stitching tool assembles a collection of 2D image tiles into a single large mosaic.
Starting from a rough initial placement (a regular grid, a position file, or a filename
pattern), the tool measures the true overlap between neighboring tiles using phase
correlation, finds a globally consistent position for every tile, and fuses the tiles
into a new dataset.

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
   their nominal grid positions. The remaining disagreement is reported as **RMSE** —
   sub-pixel values indicate mutually consistent measurements.

4. <span class="widget widget-button">Stitch</span> — fuses the tile pixels into the
   output mosaic at the optimized positions, blending the overlap regions according to
   the selected blend mode, and opens the result as a new dataset in MIB.

---

## Input panel

- <span class="widget widget-dropdown">Layout source</span>: how the initial (rough) tile placement is defined
    - **Grid**: tiles form a regular grid; specify rows, columns, acquisition order, and overlap in the Grid panel.
    - **Position file**: a text file with one line per tile: `filename X Y` or `filename X Y Z`
      (space-, tab-, or comma-separated). Tiles with different Z values are placed on separate layers.
    - **Filename pattern**: tile positions are parsed from `_Z##-X##-Y##` tokens in the filenames
      (the pattern produced by the MIB dataset chunking tool).
- <span class="widget widget-edit">Input path</span>: the tile folder (Grid, Filename pattern) or the position file. Use the <span class="widget widget-button">...</span> button to browse, or type/paste the path directly.
- <label class="widget widget-checkbox">Subfolder mode</label>: each subfolder holds one tile as a Z-stack (position-file mode).

---

## Grid panel

Active when *Layout source* is **Grid**. Any change here immediately rebuilds the layout
and refreshes the preview.

- <span class="widget widget-edit">Rows</span> / <span class="widget widget-edit">Cols</span>: grid dimensions; `0` derives the value automatically from the number of tiles.
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

- <span class="widget widget-dropdown">Transform type</span>: **Translation** (rigid and affine planned for later versions).
- <span class="widget widget-edit">Quality threshold</span>: minimum quality score (0–1, default 0.30) to accept a pairwise measurement.
  Increase it when wrong matches slip through (e.g. repetitive patterns); decrease it for low-contrast data where valid overlaps score low.
- <span class="widget widget-edit">Nominal position weight</span>: how strongly tiles with weak or rejected
  measurements are pulled back toward their nominal grid positions (0–1, default 0.10). With `0` such
  tiles are positioned only through their other, valid measurements.
- <label class="widget widget-checkbox">Sub-pixel placement</label>: refine the measured shifts to sub-pixel
  precision (the final placement is currently rounded to whole pixels; the sub-pixel residual is stored in the project file).

---

## Output panel

- <span class="widget widget-dropdown">Output mode</span>:
    - **In memory**: the mosaic is assembled in RAM and replaces the current dataset. Use for mosaics that comfortably fit into memory.
    - **OME-Zarr (BigData)**: the mosaic is streamed chunk-by-chunk to an OME-Zarr file on disk and opened as a BigData dataset. Use for mosaics of any size.
- <span class="widget widget-edit">Output path</span>: destination of the OME-Zarr file (OME-Zarr mode only).
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
