# stitch_smoke_3d — 3D joint solve from a position file

A multi-layer 3D dataset driven by a **position file**. Use it to check the
cross-layer (`z`) measurement and the joint 3-axis solve, and to exercise the
seam inspector's Z-aware checks (Fix XY on a z-edge, Fix Z per-slice).

## What it exercises

- Position-file layout source; nominal grid in the file, jittered true positions.
- `measureZShift` — the joint `[dy dx dz]` measurement for cross-layer stack pairs
  (mean-projection XY + NCC dz scan).
- Slice-unit `nomOrigin(3)` and the z-aware `planCanvas` (overlapping layers give a
  canvas thinner than a naive `3 × tileDepth` stack).
- Seam inspector Z tooling: per-slice seam check, `Q`/`W` slice browsing (view-only),
  Fix XY on a z-edge shifting all layers above, Fix Z per-slice mosaic correction.

## Dataset

- 320×320×70 textured volume + 6 tilted planes (a broken plane at a seam reveals a
  Z or XY misplacement).
- 2×2 XY grid over 3 Z-layers = 12 multi-page-TIFF Z-stack tiles, ±4 px XY jitter,
  ±2-slice per-layer Z jitter, ~60 px XY overlap / 12-slice Z overlap.
- Outputs to `temp\stitch_smoke_3d\`: `tiles\tile_01..12.tif`, `positions.txt`
  (0-based nominal grid), `trueOrigins3D.mat` (12×3 `[y x z]`).

## Run

```matlab
run('development\stitching\stitch_smoke_3d\generateSmokeTiles3D.m')
```

Stitch ribbon → Layout source = **Position file** → browse to
`temp\stitch_smoke_3d\positions.txt` → Measure overlaps → Optimize positions →
Stitch. Output **In memory** gives a 3D dataset to scroll; planes must line up
across layers on every slice.

Expected origin error ≤ 0.03 px (all axes). See `smoke_tests.md` test **3**.
