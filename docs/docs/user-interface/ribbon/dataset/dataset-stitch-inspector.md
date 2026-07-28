# Stitching: seam inspector

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Dataset](index.md) | [Stitching](dataset-stitch.md)*

---

## Overview

Automatic stitching can fail **silently**: a measurement that locked onto repetitive content
one period off satisfies the solver perfectly on sparse tile arrangements — the quality
rating stays green while a tile sits a full period out of place. The seam inspector re-reads
the actual pixels at every solved seam, ranks the seams worst-first, and gives you the tools
to correct the ones the automatic pass got wrong.

Open it with <span class="widget widget-button">Inspect and fix...</span> in the
[Stitching](dataset-stitch.md) window — enabled once *Measure overlaps* and
*Optimize positions* have run.

---

## What the inspector shows

- Every tile pair gets a **seam score** — how well the actual pixels agree at the solved
  placement — and the seams are listed worst-first. This catches wrong-but-confident
  measurements that the residual rating cannot see.
- The **mini-map** shows the layout with tiles coloured by their worst seam
  (green → red); <mouse class="left"></mouse> click to jump to the review — the seam
  **nearest the click point** is selected, so clicking near a tile's right edge opens
  its seam with the tile on that side, and clicking near its bottom edge opens the seam
  below, even when a tile has neighbours on several sides. For datasets of reasonable
  size a **low-res fused preview** is drawn behind the colouring at the current solved
  positions — it follows every re-solve, so a grossly misplaced tile is visible in the
  actual image content.
- The **pair view** shows the **complete tile pair** composited at the solved offset
  (downsampled for display when the tiles are large; the title is the colour legend,
  e.g. *Cyan: tile 2; Magenta: tile 4*). Overlays: falsecolor — tile *i* **cyan**, tile *j*
  **magenta**, so aligned structures add up to **white** while misaligned ones split
  into cyan/magenta ghosts — flicker (++Space++ toggles the two tiles), checkerboard,
  or difference. The **mouse wheel zooms** the pair view at the cursor — the zoom is
  kept through nudges, drags and fixes of the same seam;
  <span class="widget widget-button">Fit view (F)</span> (or zooming all the way out)
  restores the full-pair view. **Holding <mouse class="right"></mouse> and dragging pans**
  the view instead of zooming — it never edits alignment, so it works in every mode
  (Fix XY, Fix Z, two-click) and cannot be mistaken for a tile-fix drag.

---

## Mouse reference (pair view)

| Action | Effect |
|--------|--------|
| <mouse class="left"></mouse> drag | Move tile *j* over tile *i* (Fix Z: the magenta slice over the cyan one); release applies the fix |
| <mouse class="left"></mouse> click, no movement | Nothing — stray clicks never move a tile |
| ++shift++ + hover | Shows the correlation ROI box at the cursor (no click needed) |
| ++shift++ + <mouse class="left"></mouse> click | Click-to-correlate: cuts the ROI box and auto-snaps to a confident sub-pixel match |
| ++shift++ + wheel | Resizes the correlation ROI box |
| Wheel | Zooms the pair view at the cursor |
| <mouse class="right"></mouse> drag | Pans the view (no zoom change); clamped to the rendered tile extent |
| <mouse class="left"></mouse> click (two-click match) | Sets a landmark point on whichever tile was clicked |

---

## Reviewing the ranking

- <span class="widget widget-button">Confirm (Enter)</span> marks the current seam reviewed
  and jumps to the next worst.
- <span class="widget widget-button">Exclude (X)</span> removes its measurement from the
  solve — the tile is then held near its nominal position. This is the coarse option; a
  proper fix (below) is sub-pixel. It is a **toggle**: while the seam is excluded the button
  stays pressed and turns red, reading *Excluded (X)*; press it (or ++x++) again to put the
  measurement back. The seam's *Used* column reads `EXCLUDED` and its table row greys out to
  match.
- <span class="widget widget-button">Re-solve</span> recomputes all positions and re-ranks.
- ++N++ / ++P++ step through the ranking.

Review decisions are saved with the [project file](dataset-stitch.md#project-files) and
survive re-measuring.

---

## Fixing a bad seam

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
- <span class="widget widget-button">Two-click match</span> — when the offset is hopeless
  (e.g. a tile locked a full texture period off, beyond any search radius): both full tiles
  are shown side by side; click the same landmark once in each, and the click difference
  becomes the offset (sharpened by a local correlation).
- ++z++ / <span class="widget widget-button">Undo fix (Z)</span> — restores the original
  automatic measurement of the current seam.

---

## 3D pairs: browsing slices and the Fix mode

**3D pairs** are shown one **slice pair** at a time (the title's second line names the
shown slices, e.g. *Slice 5/8 — Q/W browses*, or per colour when the two tiles show
different slices), browsed with ++q++ / ++w++ or ++down++ / ++up++ — previous / next,
exactly like the main MIB window (++shift++ = 5) — always view-only, browsing never
moves a tile.

The <span class="widget widget-dropdown">Fix mode</span> dropdown decides what a fix edits:

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
  mosaic** — the slices below stay put — and is applied by *Stitch* in the main
  window (the tiles' solved positions are untouched; no re-solve involved). Corrections
  accumulate per boundary, are saved with the project, and ++z++ removes the one
  at the boundary on screen.

!!! note
    On a 2D dataset there are no Z slices to align, so the mode stays at Fix XY (a dialog
    explains). For deeper, non-rigid per-slice registration use the
    [Alignment tool](dataset-alignment.md) on the fused dataset.

---

## Re-solving and re-fusing

With <span class="widget widget-checkbox">Auto re-solve</span> on (default), every fix
immediately re-solves all positions, re-scores and re-ranks — work worst-first until the
top of the list is green.

To bake the corrections into a mosaic, press <span class="widget widget-button">Stitch</span>
in the [Stitching window](dataset-stitch.md); to keep them on disk, press
<span class="widget widget-button">Save project</span> there. The inspector has neither
button of its own — both windows stay open and usable side by side, so a copy would only be
the same action under a second name.

Nothing needs to be handed over first. Fixes are written straight into the stitch as you make
them, so *Save project* always carries the current state, and if a fix is still awaiting its
re-solve (<span class="widget widget-checkbox">Auto re-solve</span> off) *Stitch* runs that
solve before fusing — the mosaic is never built from stale positions.

---

*Back to [MIB](../../../index.md) | [User interface](../../index.md) | [Ribbon](../index.md) | [Dataset](index.md) | [Stitching](dataset-stitch.md)*
