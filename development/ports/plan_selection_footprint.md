# Selection footprint for 3D layer moves (Shift+A/S, Shift+C)

Goal: a selection made in 3D (e.g. SAM2 *Interactive 3D*) should go to the model with one Shift+A,
and the cost should scale with the selection, not with the volume. Stages:

1. **Standard** - measure the selection's bounding box on demand (done 2026-10-30).
2. **BigData** - level map split per layer (labels / mask / selection), so a coarse selection or
   mask stroke no longer coarsens the labels under it (done 2026-10-30).
3. **BigData** - per-tile selection map `selectionTiles` saved in `.levelmap`, and the moves,
   Shift+R choice and clears built on it (done 2026-10-30). Description:
   `development/bigdata/bigdata_logic.md` sections 5 and 6.

## 1. Standard (done)

`MibDataset.getSelectionBoundingBox(timeRange)` returns `[y1 y2 x1 x2 z1 z2 t1 t2]` or `[]`.
Used by:

- `MibModel.moveLayers` - selection -> labels/mask, `'add'`/`'remove'`, 3D (T = 1) or 4D, no
  ROI/block mode, no caller x/y/z: backup gets the box as x/y/z/t, the fast-path helper gets it as
  `options.box`. An empty box returns before the backup.
- `MibModel.clearSelection` - `'3D, Stack'` on Standard backs up and clears the box only.
- `moveSelectionToModelDataset` / `moveSelectionToMaskDataset` - optional `options.box`; read and
  write only the box via local `readLayer`/`writeLayer`. A box spanning the whole dataset is passed
  as `[]` by `moveLayers`, so the whole-array path stays exactly as before.

**Measured, not tracked.** Tracking the box as edits happen would need every write path to report
its extent; there are ~100 direct writes to `selection.data`/`labels.data` in 20 files, plus the
`setData63` paths, and a missed one silently drops part of the selection. Measuring is cheap
enough that tracking is not worth it.

**Replace stays whole-volume.** `'replace'` clears the destination material/mask everywhere, so it
cannot be limited to the selection's box.

### Measurements

R2026b, 12 threads, separate `matlab -batch` process (not baseline conditions), uint8,
4096 x 4096 x 64 (1 GiB), every other row material 3, selection a 401 x 601 x 21 block.

Reduction costs per GiB (`max`):

| Reduction | Time |
|-----------|------|
| `[1 2]`, `[1 3]` (includes dim 1) | ~16 ms |
| `3` alone | ~90 ms |
| `[2 3]` | ~115 ms |
| per-slice loop with `any` | ~3.1 s |
| `B = A(c{:})` with `c = {':',':',':',':'}` | 0.79 s (copies; literal `A(:,:,:,:)` does not) |
| `A(:,:,:,:) = B` | 0.55 s |

So the box takes the slices from `[1 2]` and X from `[1 3]` over the whole array, and Y from
the slab of the selected columns/slices when the slab is under a quarter of the array, else from
`max(..., [2 3 4])` in place (~0.12 s/GiB; copying a full slab out costs ~0.75 s/GiB). The first
version used `max(..., 3)` for the YX projection and took 0.20-0.26 s for a small selection; the
reordered one 0.07 s; 0.13 s when the box is large.

**Large boxes fall back to the whole-volume pass.** A first version used any box smaller than the
volume and was 2.3-2.5x slower than before for a selection spanning the volume: the box is copied
out and written back, and a backup with x/y/z ranges makes a real copy, whereas a whole-volume
backup shares memory with the layer (the helper builds new arrays, so the share is never broken).
`moveLayers` and `clearSelection` now use the box only when `boxFraction <= 0.25`.

Shift+A, best of two runs, old = whole 3D backup + helper without a box:

| Selection | 63 new | 63 old | 255 new | 255 old |
|-----------|--------|--------|---------|---------|
| small block (0.4 % of the volume) | 0.12 s | 0.77 s | 0.11 s | 1.34 s |
| box 12 % | 0.64 s | 0.77 s | 0.79 s | 1.34 s |
| box 25 % (boxed, at the threshold) | 1.08 s | 1.12 s | 1.43 s | 1.68 s |
| box 50 % (falls back) | 1.45 s | 1.33 s | 2.05 s | 1.97 s |
| whole volume (falls back) | 1.76 s | 1.71 s | 2.37 s | 2.23 s |
| two dots in opposite corners (falls back) | 1.10 s | 0.95 s | 1.63 s | 1.50 s |

The fallback cost is the box measurement, 0.13 s/GiB: 3-15 % on top of the old time. Shift+C,
small block: 0.10 s against 1.37 s (63) and 0.09 s against 0.78 s (255).

**Tracking instead of measuring** (asked 2026-10-30, not done): would remove the 0.07-0.13 s/GiB
measurement, but Standard has no single write funnel (BigData has `setData63`, which is why
`selectionBBoxFull` works there). A `set.data` hook would break in-place indexed writes. Every
write path would have to grow the box, and a missed one makes Shift+A silently leave part of the
selection unmoved; erasing can only shrink the box by measuring again.

Tests: `tests/models/SelectionBoundingBoxTest.m` (box exactness and time range for 63/255/16383;
boxed helpers equal the whole-volume pass for add/remove x every restriction; `moveLayers` and
`clearSelection` 3D results and undo).

## 2-3. BigData (done; the notes below are the plan as it was)

Decisions taken with the author: Shift+R asks between local and whole-volume replace; moves work
at the finest level holding data in the footprint; the coarse-stroke damage is fixed; the tile map
persists; undo is kept for 3D moves with a question above 2 GB. Not done: a performance
measurement on a real large store, and a test of the cancel-restore path in `moveLayers` (it needs
a progress dialog; `moveSelection`'s own cancel is tested).

Before this work Shift+A on BigData took the fast path, which edits `labels.data` - empty on a
disk-backed model - so the move did nothing.

- Stage 2: loop z1..z2 of `selectionBBoxFull`, apply the 2D move to the y/x box per slice, one
  backup of the box, cancelable progress bar.
- Work at the finest `matLevel` inside the footprint, not the display level, so a Shift+A made
  while zoomed out does not coarsen finer labels in those tiles. Shift+C on BigData currently
  clears the whole volume at the display level and probably has this problem (unverified).
- Stage 3: a logical map on the coarsest grid x Z (Z is not downsampled), set by `setData63` from
  the selection bits it already computes in `updateSelectionBBoxFromWrite`. Adding the property is
  a classdef change (MATLAB restart).
- Open questions for the author: Shift+R semantics on BigData (needs the material's footprint, or
  "replace inside the footprint"); whether the tile map persists in `.levelmap`.
