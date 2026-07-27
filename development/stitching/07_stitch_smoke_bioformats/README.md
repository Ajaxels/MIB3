# 07_stitch_smoke_bioformats — stage coordinates from OME metadata

OME-TIFF tiles whose **OME metadata carries stage coordinates** (Plane
PositionX/PositionY in µm) plus the physical pixel size. Use it to exercise the
**Bio-Formats metadata** layout source, which reads tile positions straight from
the embedded metadata instead of a grid or a position file.

## What it exercises

- `utils.stitch.buildLayoutBioFormats` reading `PositionX/Y` + `PhysicalSizeX/Y`.
- **Imperfect stage coordinates.** The tiles are cut on a PERFECT grid; the stage
  coordinates written into the metadata are that grid plus a per-tile, per-axis
  error of up to ±5 px (continuous, not whole pixels) — the backlash/drift/encoder
  error every real stage has. So the layout built straight from the metadata is
  already *good* (≈ 4 px off, seams look nearly right) but *not perfect*, and only
  Measure overlaps + Optimize positions recovers the exact grid.

## Requirements

Needs the Bio-Formats Java library (bundled in `mib\external\bioformats`); the
generator adds it to the path and calls `utils.ensureJavaLibraries` automatically.

## Dataset

- 560×560 ground truth: 3-scale noise + gradient + 16 lines + 4 circles.
- 2×2 grid of 240×240 tiles cut at exactly 25 % overlap (step 180 px = 90 µm at
  0.5 µm/px); stage coordinates jittered by up to ±5 px.
- Outputs to `temp\stitching_test\07_stitch_smoke_bioformats\`: `tile_01..04.ome.tiff`,
  `trueOrigins.mat` (`trueOrigins` = the perfect grid Optimize must recover,
  `stageJitterPx` = the signed error baked into the metadata).

## Run

```matlab
run('development\stitching\07_stitch_smoke_bioformats\generateSmokeBioFormatsTiles.m')
```

Stitch ribbon → Layout source = **Bio-Formats metadata** → browse (multi-select the
four `tile_0#.ome.tiff`) → Measure overlaps → Optimize positions → Stitch.

Expected origin error: ≈ 4 px straight from the metadata, ≤ 0.02 px after Optimize
(4/4 edges valid). See `smoke_tests.md` test **7**.
