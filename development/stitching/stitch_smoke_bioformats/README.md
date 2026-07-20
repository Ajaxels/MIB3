# stitch_smoke_bioformats — stage coordinates from OME metadata

OME-TIFF tiles whose **OME metadata carries stage coordinates** (Plane
PositionX/PositionY in µm) plus the physical pixel size. Use it to exercise the
**Bio-Formats metadata** layout source, which reads tile positions straight from
the embedded metadata instead of a grid or a position file.

## What it exercises

- `utils.stitch.buildLayoutBioFormats` reading `PositionX/Y` + `PhysicalSizeX/Y`.
- Metadata carries the CLEAN nominal grid while tiles are cut at JITTERED positions,
  so measure + optimize have real work to do.

## Requirements

Needs the Bio-Formats Java library (bundled in `mib\external\bioformats`); the
generator adds it to the path and calls `utils.ensureJavaLibraries` automatically.

## Dataset

- 560×560 ground truth: 3-scale noise + gradient + 16 lines + 4 circles.
- 2×2 grid of 240×240 tiles, 25 % overlap (step 180 px = 90 µm at 0.5 µm/px),
  ±5 px jitter.
- Outputs to `temp\stitch_smoke_bioformats\`: `tile_01..04.ome.tiff`,
  `trueOrigins.mat`.

## Run

```matlab
run('development\stitching\stitch_smoke_bioformats\generateSmokeBioFormatsTiles.m')
```

Stitch ribbon → Layout source = **Bio-Formats metadata** → browse (multi-select the
four `tile_0#.ome.tiff`) → Measure overlaps → Optimize positions → Stitch.

Expected origin error ≈ 0.01 px. See `smoke_tests.md` test **7**.
