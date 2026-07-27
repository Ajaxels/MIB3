# 12_stitch_smoke_sabotage — the residual-invisible bad edge (seam inspector)

A "confidently wrong edge" dataset for the **seam inspector**. A 1×3 chain has no
loop to contradict a corrupted edge, so the global solve satisfies every edge
exactly (RMSE ≈ 0, green rating) while one tile sits 24 px off. Only re-checking
actual pixels at the solved placement (`utils.stitch.scoreSeams`) catches it.

## What it exercises

- Seam scoring vs solver residuals: the corruption is residual-invisible; the inspector's
  pixel-level seam check ranks the bad edge first (score ≈ 0.1 vs 1.0).
- The Optimize-time seam re-check that turns the lying green chip **red**.
- Every inspector fix path: Exclude + Re-solve (coarse, spring-limited), Shift+click-to-
  correlate (sub-pixel), drag, Two-click match, `Z` undo, then *Stitch* /
  *Save project* in the Stitching window to fuse and keep the corrections.

## Why corrupt the edge, not the imagery

Phase correlation whitens the spectrum and RANSAC ratio-tests repeated descriptors, so
both estimators resist deterministic image-level sabotage. The generator measures the
chain honestly, then injects the failure directly into the 2-3 edge (+24 px, quality
0.95) — reproducing the failure state whatever real content would have caused it.

## Requirements

Needs the `mib` folder on the path (calls `utils.stitch.*` to measure and save a project).

## Dataset

- 1×3 chain of 300×300 tiles, 25 % overlap, small jitter; lines + circles make the
  ~24 px seam break obvious by eye.
- Outputs to `temp\stitching_test\12_stitch_smoke_sabotage\`: `tiles\tile_01..03.tif`,
  `sabotage.mibstitch.json` (corrupted 2-3 edge + solved positions), `groundTruth.tif`,
  `trueOrigins.mat`.

## Run

```matlab
run('development\stitching\12_stitch_smoke_sabotage\generateSmokeSabotageTiles.m')
```

Stitch ribbon → **Load project** → `temp\stitching_test\12_stitch_smoke_sabotage\sabotage.mibstitch.json`
→ Optimize positions (chip comes out **red** — seams disagree) → **Inspect & fix…**
The 2-3 seam ranks first; fix it via Exclude+Re-solve (≤ 6 px) or Shift+click (≤ 1 px).

See `smoke_tests.md` test **12** and `plan_inspector.md`.
