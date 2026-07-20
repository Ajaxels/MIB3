# stitch_smoke_folders — folder-per-tile Z-stacks (Grid source)

Each tile is a Z-stack stored as a **folder of single-slice images**. Use it to
exercise the *Tiles are folders (Z-stacks)* modifier together with the **Grid**
layout source (folders named grid-style, no filename tokens).

## What it exercises

- Grid layout source with `SubfolderMode` on: tiles collected as folders, each read
  slice-by-slice and stacked into the depth dimension by `makeTileReader`.
- A single Z-layer where every tile spans the full Z range (unlike `stitch_smoke_3d`,
  which has multiple layers) — the folder-reading path, not cross-layer solving.

## Dataset

- 300×300×40 textured volume + 6 tilted planes.
- 2×2 XY grid, ±4 px jitter, ~60 px overlap; four folders of `slice_###.tif`.
- Outputs to `temp\stitch_smoke_folders\`: `tile_r1c1 … tile_r2c2` folders.

## Run

```matlab
run('development\stitching\stitch_smoke_folders\generateSmokeFolders.m')
```

Stitch ribbon → Layout source = **Grid**, tick **Tiles are folders (Z-stacks)** →
browse (multi-select `tile_r1c1 … tile_r2c2`, or pick the parent folder) →
Rows 2, Cols 2 → Measure overlaps → Optimize positions → Stitch.

See `smoke_tests.md` test **4**.
