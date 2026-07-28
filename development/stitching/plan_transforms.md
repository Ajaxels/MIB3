# Stitching — transform models (translation / affine / rigid / similarity)

Companion to [`plan_stitching.md`](plan_stitching.md) (architecture, pitfalls, status).

**Status: IMPLEMENTED and verified**, 2D (Translation/Rigid/Similarity/Affine) and 3D
(in-plane 2D affine per Z-stack tile — see scope note below). 3D rigid and full 12-param
volumetric affine are **deferred** (rare for stage-translated stacks; no dataset needs it yet).

## The load-bearing fact

Translations compose **additively**, so the global solve is three independent linear sparse
least-squares systems (y, x, z) — `solveGlobalLeastSquares.m`. Every model decision here is judged
by whether it preserves that linearity.

## Model staging (not the obvious order)

| Model | Global solve | Notes |
|-------|--------------|-------|
| Translation | linear per-axis, no resampling | fast path, unchanged |
| Affine | **still linear** — LS over the affine matrix coefficients (dimension-agnostic: 6 params/tile in 2D, 12 in 3D) | `solveGlobalAffine.m` |
| Rigid / Similarity | nonlinear (rotation manifold) — solved by **projection**, not a nonlinear optimizer: solve affine globally, then polar/SVD-decompose each tile's linear part (`utils.stitch.projectLinearPart`) → Rigid keeps `R` only, Similarity keeps `s·R`, then re-solve translations with the projected linear parts fixed | 2D-only (3D rotation = SO(3) averaging, out of scope until a real rotated-3D dataset exists) |

Phase-correlation measurement is translation-only; any non-translation `TransformType` forces
feature-based measurement (`estgeotform2d`) and locks the GUI's `RegistrationMethod` dropdown.

## `AllowRotation` (default **unchecked**)

Locks rotation to zero — the `R = I` branch of the same polar decomposition, applied in both
places: the pairwise fit (`featureShift`) and the global projection (`solveGlobalAffine`). Stage-
tiled data doesn't rotate; a richer model without this lock lets a few noisy edges fit spurious
rotation that compounds with distance from the anchor. Disabled when `TransformType = Translation`.
"Rigid + AllowRotation off" ≡ Translation (harmless redundancy, no special-casing).

## 3D affine — scope

"3D affine" = the 2D in-plane affine model running on depth>1/multi-layer data: each z-slice of a
tile is warped by that tile's single 2D affine; **z stays translational** (composes additively
regardless of the in-plane model, so the solver's z path and the fuser's per-slice warp needed no
new machinery — no `imwarp3`). NOT full 3D rotation/shear.

**Cross-layer coupling:** z-edges enter the affine system with `M = I` (a tile's linear part pinned
to its cross-layer partner's) — a layer's common linear factor is unobservable from translation-only
z measurements. This is a "lens/stage distortion is per-position, not per-section" prior;
per-section warps would be the elastic-refinement phase's job (below).

## Future directions (from a 2026-07-19 TrakEM2 evaluation)

Target use case: volume EM with operator-supplied rough tile positions (the coarse-search /
no-prior-SIFT tier of TrakEM2 is irrelevant — the value is in the *refinement* tier). Ranked by
quality-per-effort:

1. **Non-rigid / elastic refinement (highest ceiling, biggest lift).** Per-tile affine treats each
   tile as a rigid parallelogram; real EM sections have lens distortion and local deformation that
   vary *within* a tile. TrakEM2's `ElasticMontage`/`ElasticLayerAlignment` lay a grid of
   block-matched correspondences and relax a spring mesh so each tile deforms locally. New phase: a
   mesh model + block-match measurer + warp fuser (shares resampling infra with 3D affine). The
   single capability we structurally cannot do today.
2. **Regularized transforms (cheap, immediate).** TrakEM2's `RegularizedAffineLayerAlignment` blends
   the fitted affine toward rigid by a lambda to avoid overfitting weak seams. We have the two
   endpoints (`AllowRotation`, `NominalPositionWeight`) but not the continuous dial — a lambda
   pulling each tile's linear part toward rigid/identity would suppress spurious-shear accumulation.
   Small addition on top of `projectLinearPart`.
3. **Keep correspondence sets per seam (enabler for #1).** `featureShift` runs RANSAC then discards
   the inliers, handing the solver one collapsed `[dy dx]` per edge. Persisting the inlier set (and
   weighting by inlier count/spread) makes the global solve more robust AND is the prerequisite the
   spring mesh in #1 consumes.

One infrastructure investment (a streaming warp/resample fuser) unlocks both full 3D affine and
elastic refinement; regularization (#2) is independent and can land anytime.

## Verification

`StitchCoreTest`: affine chop→solve within tolerance; `AllowRotation` off forces exact zero
rotation; rigid projection is orthogonal (`R'R = I`); translation inputs unchanged (fast-path
regression guard); 3D affine multi-layer chop→measure→solve→warp-fuse. GUI smoke:
[`smoke_tests.md`](smoke_tests.md) tests 11 (2D translation vs affine/rigid/similarity) and 13 (3D
affine).
