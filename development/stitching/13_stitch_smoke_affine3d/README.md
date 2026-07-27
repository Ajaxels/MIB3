# 13_stitch_smoke_affine3d — 3D affine (in-plane affine on Z-stack tiles)

The 3D counterpart of `11_stitch_smoke_affine`: the in-plane 2D affine model running on
**multi-layer / depth>1 data**. Each Z-stack tile is warped by its single 2D affine
applied to every slice, while Z stays translational. Use it to check that a
non-translation transform works across layers after the Phase-3 gate relaxation.

## What it exercises

- Non-translation `TransformType` on 3D data (the 2D-only gate is gone).
- Within-layer edges fit the 2D affine on the depth-flattened tiles; cross-layer (`z`)
  edges stay translation-only — `measureOne` forces this.
- `solveGlobalAffine` in-plane affine + scalar-z path; `planCanvas` warped-footprint plan
  + per-slice `imwarp` fusion across depth (no `imwarp3` in this scope).
- The cross-layer `M = I` coupling: a tile's linear part is pinned to its partner in the
  adjacent layer, so the truth shares the linear part **per grid slot across layers**
  (per-position distortion, not per-section — matching what the solver can observe).

## Dataset

- 640×640×30 volume: one strong 2D texture shared across slices (lines + circles) + a
  z-varying component (sharpens the dz NCC scan) + 4 tilted planes (break at a Z seam).
- 2×2 XY grid over 2 Z-layers = 8 multi-page-TIFF Z-stack tiles (16 slices each); every
  tile except the anchor warped by ±1° rotation, ±1 % scale, ±8 px jitter (same 2D warp
  per slice); layer 2 Z-jittered ±2 slices.
- Outputs to `temp\stitching_test\13_stitch_smoke_affine3d\`: `tiles\tile_01..08.tif`, `positions.txt`
  (0-based nominal grid), `truth.mat` (`trueTforms` {8×1}, `trueLayerZ` [1×2]).

## Run

```matlab
run('development\stitching\13_stitch_smoke_affine3d\generateSmokeAffine3DTiles.m')
```

Stitch ribbon → Layout source = **Position file** → browse to
`temp\stitching_test\13_stitch_smoke_affine3d\positions.txt`.

- **A) Transform type = Translation** → seams show rotated/doubled lines on every slice.
- **B) Transform type = Affine**, tick **Allow rotation** → Measure overlaps (feature-based)
  → Optimize positions → Stitch: scroll Z — lines/circles continuous across every seam on
  every slice, planes continuous across the layer boundary.

Expected: 12 edges valid, matrix max-abs ≤ 0.39, RMSE ≈ 0.09 px, layer dz exact.
Verified headlessly by `StitchCoreTest.fullChain3DAffine_measureSolveFuseAcrossLayers`.
See `smoke_tests.md` test **13** and the Phase-3 block in `plan_transforms.md`.
