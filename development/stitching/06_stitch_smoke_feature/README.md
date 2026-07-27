# 06_stitch_smoke_feature — where Feature-based beats Phase correlation

A large-jitter tile set for **comparing the two registration methods** side by
side. Run it twice — the restricted-search phase correlation fails, full-tile
feature matching recovers it.

## What it exercises

- Phase correlation vs Feature-based (SURF) measurement on the same data.
- ±55 px jitter against a ~75 px overlap strip: phase correlation, which searches only
  near the nominal overlap, comes out with few valid / wrong edges; feature matching
  over the full tiles recovers the offsets.
- Also the base dataset for the feature-settings preview (test 10).

## Dataset

- 880×880 uint8 ground truth: 3-scale noise + gradient + 22 lines + 4 circles (blobs
  and crossings give SURF plenty of keypoints across the whole tile).
- 3×3 grid of 300×300 tiles, 25 % nominal overlap, **±55 px jitter**.
- Outputs to `temp\stitching_test\06_stitch_smoke_feature\`: `tiles\tile_01..09.tif`, `groundTruth.tif`,
  `trueOrigins.mat`.

## Run

```matlab
run('development\stitching\06_stitch_smoke_feature\generateSmokeFeatureTiles.m')
```

Stitch ribbon → Layout source = **Grid** → browse to
`temp\stitching_test\06_stitch_smoke_feature\tiles` → Rows 3, Cols 3, Overlap 25, **untick Estimate**.

- **A) Registration = Phase correlation** → Measure: ~7/12 edges valid, solve ~80 px
  off, seams break after Stitch.
- **B) Registration = Feature-based** → Measure → Optimize → Stitch: ~11/12 edges
  valid, ~0.5 px error, clean seams.

Expected origin error ≤ 0.5 px (feature-based). See `smoke_tests.md` tests **6** and **10**.
