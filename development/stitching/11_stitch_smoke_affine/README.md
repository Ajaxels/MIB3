# 11_stitch_smoke_affine — Translation vs Affine (rotated tiles)

Rotated/scaled tiles for **comparing Transform types**. A translation solve cannot
make these tiles agree; Affine (feature-based, resampled) can. Run it twice.

## What it exercises

- `TransformType` = Translation vs Rigid/Similarity/Affine on genuinely rotated data.
- Automatic switch to feature-based measurement for any non-translation model (phase
  correlation cannot measure rotation) and the RegistrationMethod dropdown locking.
- The `AllowRotation` checkbox: on this set the truth IS rotated, so it must be ticked;
  with it unticked, rotations lock to zero and the result degrades toward Translation
  (the intended protection for un-rotated data).
- `solveGlobalAffine` + warped-footprint `planCanvas` + per-tile `imwarp` fusion.

## Dataset

- 640×640 ground truth: 3-scale noise + gradient + 18 lines + 3 circles.
- 2×2 grid of 300×300 tiles, 25 % overlap; every tile except the anchor warped by its
  own ±1° rotation, ±1 % scale, ±8 px jitter.
- Outputs to `temp\stitching_test\11_stitch_smoke_affine\`: `tiles\tile_01..04.tif`, `groundTruth.tif`,
  `trueTforms.mat` (4×1 true tile-local→global 3×3 xy maps).

## Run

```matlab
run('development\stitching\11_stitch_smoke_affine\generateSmokeAffineTiles.m')
```

Stitch ribbon → Layout source = **Grid** → browse to `temp\stitching_test\11_stitch_smoke_affine\tiles`
→ Rows 2, Cols 2, Overlap 25, **untick Estimate**.

- **A) Transform type = Translation** → after Stitch the seams show rotated/doubled lines.
- **B) Transform type = Affine** → Measure (switches to feature-based) → Optimize →
  Stitch: lines/circles continuous across every seam.
- Variations: Similarity/Rigid + **Allow rotation**; any non-translation model with
  Allow rotation UNCHECKED to see the rotation-lock degrade the fit.

Expected: transforms recovered ≤ 0.22 (matrix max-abs), solver RMSE ≈ 0.02 px.
See `smoke_tests.md` test **11**. The 3D counterpart is `13_stitch_smoke_affine3d` (test 13).
