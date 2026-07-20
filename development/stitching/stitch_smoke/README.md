# stitch_smoke — baseline 2D grid

The plain baseline for the Stitching tool: a single-layer 2D grid with modest
position jitter. Use it to confirm the whole pipeline (measure → optimize →
stitch) works at all, and as the reference for **overlap auto-estimation** vs a
manually entered overlap.

## What it exercises

- Grid layout source, phase-correlation measurement, translation solve.
- `Estimate overlap` on (test 1) vs a manual `Overlap X/Y = 15` (test 2).
- The ±5 px jitter (clamped, so edge tiles drift up to ~42 px from nominal) is a
  gentle stress on the restricted-search measurement — enough to be non-trivial,
  small enough that phase correlation always recovers it.

## Dataset

- 900×1200 uint8 ground truth: two-scale smoothed noise + 22 randomly-oriented
  blended lines + 4 circles (a broken line/circle at a seam = visible bad stitch).
- 3×3 grid of 340×460 tiles, 15 % nominal overlap, ±5 px jitter.
- Outputs to `temp\stitch_smoke\`: `tiles\tile_01..09.tif`, `groundTruth.tif`,
  `trueOrigins.mat` (9×2 `[y x]` true origins).

## Run

```matlab
run('development\stitching\stitch_smoke\generateSmokeTiles.m')
```

Stitch ribbon → Layout source = **Grid** → browse to `temp\stitch_smoke\tiles`
→ Rows 3, Cols 3 → tick **Estimate overlap** (or untick and set Overlap X/Y = 15)
→ Measure overlaps → Optimize positions → Stitch.

Expected origin error ≤ 0.16 px. See `smoke_tests.md` tests **1–2**.
