# 19_stitch_smoke_z_dirs_displacement - serial-section folder stacks with stage-backlash jitter

A serial-section montage in its natural layout: a 2x2 grid of tiles, each a **folder** holding the
whole series of sections imaged at that stage position, all in one Z-layer (`stack_Z01-X##-Y##`).
Unlike `05_stitch_smoke_pattern_folders`, the slices inside a folder are **not registered**: the
stage returns to each position on every section and backlash makes it land slightly off each time.

## Displacements

| Level | What moves | Size |
|-------|------------|------|
| Tile | fixed offset from the nominal grid, the same on every slice | up to ±4 px |
| Slice | backlash: ±2 px per axis, sign set by the side the stage approached from (random per slice), plus ±1 px repeatability | 1-3 px per axis, no accumulation |

Open one folder as a stack in MIB and scroll: the content jumps by a few px from slice to slice.

## Dataset

- Volume = z-constant 2D texture + z-varying 3D texture + lines and circles that move 1-2 px per
  slice (tilted planes and cones).
- 4 tiles, 240x240x24 each, ~22 % XY overlap; four `stack_Z01-X##-Y##` folders of `slice_###.tif`.
- `trueOrigins3D.mat`: `trueOrigins` (`[y x z]` of each tile's window before backlash),
  `sliceOffsets` (`[4 x 24 x 2]`, the backlash shift of every slice), `tileNames`.
- `backlashPx` / `repeatabilityPx` at the top of the generator set the jitter.
- Outputs to `temp\stitching_test\19_stitch_smoke_z_dirs_displacement\`.

## Run

```matlab
run('development\stitching\19_stitch_smoke_z_dirs_displacement\generateSmokeZDirsDisplacement.m')
```

Stitch ribbon -> Layout source = **Filename pattern**, tick **Tiles are folders (Z-stacks)** -> Overlap
X/Y = 22 -> browse (multi-select the four `stack_...` folders, or pick the parent) -> Measure
overlaps -> Optimize positions -> Stitch, output **In memory**.

## What to expect (headless: `buildLayoutFilenamePattern` -> measure -> solve -> `scoreSeams`)

The tool does **not** stitch this dataset today. It places each folder rigidly, and it measures a
seam on the average of all the folder's slices.

- **All 4 seams rejected** (quality 0.00-0.08): averaging slices that sit at different offsets
  smears out the fine detail phase correlation needs. Tiles therefore stay on the nominal grid,
  up to 5 px from their average true position.
- Solver RMSE 0.000 px, because no seam is left to disagree with. Seam scores are 0.14-0.32.
- Per-slice seam break after stitching: median 6.3 px, max 12.1 px; 92 of 96 slice-seams are off
  by more than 2 px.

Where it breaks (same volume, varying the jitter):

| per-slice offsets | seam quality |
|-------------------|--------------|
| none | 1, 1, 1, 1 |
| ±1 px (backlash 2, no repeatability) | 1, 1, 1, 1 |
| ±2 px (backlash 4, no repeatability) | 1, 1, 0.19, 1 |
| -2..+2 px (backlash 2, repeatability 1) | 0, 0.17, 0, 0 |
| 1-3 px (default: backlash 4, repeatability 1) | 0, 0, 0.08, 0 |

Two fixed offsets only make the average a sharp double image, which still matches. A spread of
offsets blurs it, and the match fails.

See `smoke_tests.md` test **19**.
