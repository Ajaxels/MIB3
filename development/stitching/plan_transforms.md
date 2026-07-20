# Stitching — transform-model expansion (design)

Design for expanding registration beyond translation-only. Companion to
[`plan_stitching.md`](plan_stitching.md); references its solver
(`utils.stitch.solveGlobalLeastSquares`), fusers (`fuseInMemory`/`fuseStreaming`),
and measurement (`measureAllPairs` / `featureShift` / `pairwiseShift`).

**Status (2026-07-15): Phase 1 (2D affine) IMPLEMENTED and verified.**

- `featureShift` — `options.transformType` (`estgeotform2d` model), full fitted matrix
  in `debugInfo.tformA`.
- `measureAllPairs` — `options.transformType`; non-translation forces the feature-based
  estimator; edges carry the tile-local i→j map in `.tform` (crop-offset composed);
  z-pairs stay translation.
- `utils.stitch.solveGlobalAffine` — NEW: 6 params/tile (`L` 2x2 + `p`), edge rows
  `L_i = L_j*M` and `p_i − p_j − L_j*c = 0`, one sparse weighted LS; anchor/springs
  mirror the translation solver; z via the scalar solver. **Pitfall found & fixed:**
  the dimensionless L-rows must be weighted by `linearScale²` (a residual r in L costs
  `linearScale*r` PIXELS) — with only `linearScale¹` the solver tilts L (the `L*c`
  lever arm ≈ tile pitch) to trade measurement-exactness for spring satisfaction
  (0.6 px position bias; correctly weighted: ~5e-3 px).
- `planCanvas` — `options.tforms` → warped-corner union canvas, `canvas.tforms`
  (canvas frame) + `canvas.tileBounds`; no-tforms path untouched.
- `fuseSliceComposite` — per-tile `imwarp` branch (slice + blend weights warped
  together, coverage-masked Max/Overwrite); integer-translation tiles and all
  no-tforms plans take the unchanged placement fast path. In-memory / streaming /
  SliceProvider inherit via the shared kernel.
- Controller — `TransformType{2} = {'Translation','Affine'}`, solver dispatch in
  Optimize/Stitch, 2D-only gating (dialog/`error` for multi-layer or depth>1),
  transform-change invalidates edges; sidecar (`saveProject`/`loadProject`) persists
  per-tile `solvedTform` + per-edge `tform`.
- Verification — `StitchCoreTest` 32/32 (5 new: exact-recovery, translation-collapse,
  integer-tform canvas parity, ground-truth warp-fuse milestone, full measured chain);
  GUI smoke dataset `stitch_smoke_affine` (see `smoke_tests.md` test 11).

**Status (2026-07-16): Phase 2 (rigid/similarity + AllowRotation) IMPLEMENTED and verified.**

- `utils.stitch.projectLinearPart` — NEW shared projection (polar/SVD): Rigid → `R`
  (or `I`), Similarity → `s*R` with the Frobenius-optimal `s = trace(R'*L)/2`
  (or `s*I`, `s = trace(L)/2`), Affine+noRotation → symmetric stretch `P`;
  reflection-guarded sign correction.
- `solveGlobalAffine` — `options.transformType` / `options.allowRotation`: linear
  affine solve → per-tile projection → **translation refinement with the projected
  linear parts fixed**, reusing `solveGlobalLeastSquares` on synthesized edge offsets
  anchored at the OVERLAP centroid (exact for group-consistent data; seam-centred
  compromise under model mismatch).
- `featureShift` — `options.allowRotation`: rigid+noRotation downgrades to the
  translation fit; similarity/affine+noRotation projects the fitted matrix and
  re-estimates the translation over the RANSAC inliers (in double — Locations are
  single, a class leak the tests caught). `measureAllPairs` forwards the flag.
- Controller — `TransformType{2} = {'Translation','Rigid','Similarity','Affine'}`,
  `BatchOpt.AllowRotation` (default **false** per the design prior), guarded checkbox
  wiring (enable only for non-translation; RegistrationMethod disabled then — feature
  measurement is implied), edges invalidated on transform OR rotation-lock change;
  spec for the mlapp checkbox in `mlapp_widgets.md`.
- Verification — StitchCoreTest **36/36** (4 new: rigid recovery with exact
  orthogonality `R'R = I`/`det = 1`; AllowRotation off → linear parts EXACTLY identity
  on the same rotated set; similarity `s*R` recovery; featureShift rotation-lock
  projection + unlocked 2° recovery). GUI variations added to `smoke_tests.md` test 11.

**Status (2026-07-19): Phase 3 (3D affine) IMPLEMENTED and verified.** Scope as planned:
the **in-plane 2D affine model running on multi-layer / depth>1 data** — each z-slice of a
tile warped by that tile's 2D affine, z composed additively. This is NOT full 12-param
volumetric affine with tile-to-tile 3D rotation/shear (rare for stage-translated stacks;
deferred until a real rotated-3D dataset exists). What it took:

- **Gating removed** — the "2D transforms only" blocks in `measureOverlaps_Callback` and
  `stitchBtn_Callback` (batch path) are gone; the `TransformType` tooltip updated. The
  feature-based forcing needed no extra gate: `measureAllPairs` already implies the
  feature estimator for any non-translation model, and `updateWidgets` already locks the
  RegistrationMethod dropdown.
- **Measurement / solver / fuser — verified, no changes.** x/y edges fit the 2D affine on
  the depth-flattened (mean-projection) full tiles; z-edges stay translation
  (`measureOne` forces it). `solveGlobalAffine` z path is the scalar solver;
  `planCanvas`+`fuseSliceComposite` warp per output slice with the tile's single 2D
  tform, so depth>1 needed nothing (no `imwarp3` in this scope).
- **Cross-layer L coupling (found in testing, by design):** z-edges enter the affine
  system with `M = I`, i.e. a tile's linear part is pinned to its partner's in the
  adjacent layer. A layer's COMMON linear factor is unobservable from translation-only
  z measurements, so this is the "lens/stage distortion is per-position, not
  per-section" prior — synthetic truths must share the linear part per grid slot across
  layers or the solve compromises (≈2.4 px error on an inconsistent truth vs 0.38 on a
  consistent one). Per-section warps are the elastic phase's job.
- **Verification** — `StitchCoreTest` 38/38; new `fullChain3DAffine_measureSolveFuseAcrossLayers`
  (2x2 grid x 2 layers of Z-stack tiles, in-plane affine per slot + Z jitter: measure →
  solve → warp-fuse; transforms ≤ 0.5 max-abs, layer dz within 1 slice, mid-layer mosaic
  slices ≤ 4 grey levels off). GUI smoke dataset `stitch_smoke_affine3d`
  (`smoke_tests.md` test 13): 12/12 edges valid, matrix max-abs 0.38, RMSE 0.09 px,
  layer dz exact.

3D rigid deferred until a real rotated-3D dataset exists.

## Future directions (from the 2026-07-19 TrakEM2 evaluation)

Target use case: detail-rich **volume EM** where the operator supplies rough tile
positions, so the coarse global-search / no-prior-SIFT tier of TrakEM2 is irrelevant.
The value is in the *refinement* tier. Ranked by quality-per-effort for that case:

1. **Non-rigid / elastic refinement (highest quality ceiling; biggest lift).** Per-tile
   affine treats each tile as a rigid parallelogram; real EM sections have lens distortion
   and local tissue deformation that vary *within* a tile. TrakEM2's `ElasticMontage` /
   `ElasticLayerAlignment` lay a grid of **block-matched correspondences** and relax a
   **spring mesh** so each tile deforms locally. New phase: a mesh model + a block-match
   measurer + a warp fuser (shares the resampling infrastructure with 3D affine). This is
   the single capability we structurally cannot do today and the biggest win for EM.
2. **Regularized transforms (cheap, immediate).** TrakEM2's `RegularizedAffineLayerAlignment`
   blends the fitted affine toward rigid by a lambda to avoid overfitting weak seams. We
   have the two endpoints — `AllowRotation` (rotation lock) and the nominal springs
   (`NominalPositionWeight`) — but not the continuous dial. A lambda pulling each tile's
   linear part toward rigid/identity would directly suppress the spurious-shear
   accumulation this doc already warns about. Small change on top of `projectLinearPart` +
   `identitySpringWeight`.
3. **Keep correspondence *sets* per seam (architectural enabler for #1).** `featureShift`
   runs RANSAC then discards the inliers, handing the solver one collapsed `[dy dx]` per
   edge. TrakEM2 optimizes over the surviving point matches themselves. Persisting the
   inlier set (and weighting the solve by inlier count/spread) makes the global solve more
   robust AND is the prerequisite the spring mesh consumes — do this before, or as part of,
   the elastic phase. Requires the edge to carry a correspondence set alongside `.measured`.

Build-order note: one infrastructure investment (streaming warp/resample fuser) unlocks
BOTH 3D affine and elastic. Regularization (#2) is independent and can land anytime.

## The load-bearing fact

The current global solve is trivial **because translations compose by addition**:
each edge is the linear constraint `p_j − p_i = measured`, so the solver runs three
independent linear least-squares systems (y, x, z) — a clean sparse `A\b` with
anchoring + springs (`solveGlobalLeastSquares.m:161-175`). Every transform-model
decision below is judged by whether it preserves that linearity.

## Decision 1 — unify 2D and 3D, do NOT split

One transform concept, shared, parametrized by dimensionality. A pairwise measurement
is a relative transform in the same group; the global solve is the same structure with
a bigger per-tile parameter block. The 3D solve today is literally the 2D solve plus a
z-block — that is the generalization working. Splitting into separate 2D/3D transform
pipelines would duplicate the whole registration→edge→solve→fuse chain (and the sign
conventions / two-round spring logic already paid for) and let the two drift apart.

Keep a single `TransformType` that applies to whatever the dataset's dimensionality is;
where 3D isn't ready for a model, **gate the dropdown**, don't fork the API.

## Decision 2 — stage models by solver tractability, not by dimension

Counterintuitively the models do **not** get harder in the obvious order:

| Model | Global solve | Notes |
|-------|--------------|-------|
| **Translation** (have it) | linear per-axis, no resampling | current fast path |
| **Affine** (add next) | **still linear** — LS over the affine matrix coefficients (d²+d params per tile), à la BigStitcher | dimension-agnostic; slots into the existing sparse-LS with a bigger block |
| **Rigid / Similarity** | nonlinear (rotation-manifold constraint) | do NOT build a separate nonlinear optimizer first — see projection approach below |

**Affine is dimension-agnostic** (6 params in 2D, 12 in 3D); the only thing gating 3D
affine is the fuser, not the math.

**Rigid/similarity via projection** (avoids a nonlinear global optimizer):
1. Solve **affine** globally (linear).
2. **Polar-/SVD-decompose** each tile's linear part into rotation `R` × stretch `S`.
3. Rigid → keep `R`, set `S = I`. Similarity → keep `R`, `S = scalar`. (Optional one
   refinement pass.)

This is clean and robust in 2D (rotation = 1 DOF). In 3D it becomes SO(3) rotation
averaging — a much bigger, research-grade solver — and tile-to-tile rotation in 3D is
rare (stage-translated stacks). So **rigid/similarity are 2D-first / 2D-only** until a
real 3D-with-rotation dataset appears; this is a rollout gate on the shared pipeline,
not a separate 2D implementation.

**Target scope:** translation (2D+3D) · affine (2D now, 3D when the fuser is ready) ·
rigid/similarity (2D, by projection).

## Decision 3 — `AllowRotation` constraint checkbox

Most stage-tiled data is not rotated (stage moves H/V). A rotation-capable model can let
a few noisy edges each fit a small spurious rotation that **accumulates across the
mosaic** (rotation error compounds with distance from the anchor). A checkbox that locks
rotation to zero removes that entire error channel — a robustness prior, not just a
preference.

It fits the projection machinery for free: "disallow rotation" is the `R = I` branch of
the same polar decomposition that already has to compute `R`.

| Model | AllowRotation ✓ | AllowRotation ✗ |
|-------|-----------------|-----------------|
| Translation | (n/a — checkbox disabled) | (n/a) |
| Rigid | `R`·translation | `R = I` → **≡ translation** |
| Similarity | `R`·uniform-scale·t | scale + t, no rotation |
| Affine | full linear part | zero the rotation factor, keep scale/shear |

**Apply in both places** for consistency:
1. Pairwise fit — constrain the `estgeotform2d` model so measured edges carry no rotation.
2. Global projection — force `R = I` per tile.

**Defaults & gating:**
- Disable the checkbox when `TransformType = Translation` (moot).
- **Default unchecked**, matching the "stage doesn't rotate" prior — a richer model then
  gives translation/scale/shear *without* rotation, and rotation is a deliberate opt-in.
- Harmless redundancy: "Rigid + rotation disallowed" ≡ Translation — tooltip, no
  special-casing.

## What the work actually is (the dropdown is the trivial part)

1. **Measurement — nearly free.** `estgeotform2d` already accepts
   `'translation'|'rigid'|'similarity'|'affine'` (the Alignment tool uses them). Thread
   `TransformType` + `AllowRotation` through `featureShift` (and decide the phase-corr
   path stays translation-only — it can only measure translation, so a non-translation
   model implies the feature-based measurer).
2. **Global solver — moderate.** Generalize the edge from a `[dy dx dz]` vector to a
   relative transform, and the solver from per-axis scalars to per-tile parameter blocks.
   **Translation + affine only** at first (both linear). Rigid/similarity = post-solve
   projection.
3. **Fuser — the biggest lift.** Translation = integer/subpixel *placement*, no
   resampling (current fast path). Anything else = every tile `imwarp`'d into the canvas;
   blend weights must follow warped footprints; `fuseStreaming` / `StitchSliceProvider`
   must warp per output chunk (`imwarp3` per block in 3D). **Keep the integer-placement
   fast path as a special case when `TransformType = Translation`.**

## Data-structure / BatchOpt changes (sketch)

- **Edge** — today `.measured = [dy dx dz]`. Generalize to carry a relative transform
  (keep `.measured` as the translation part for the translation fast path + back-compat;
  add the linear part alongside). Keep sign conventions documented in `featureShift.m`.
- **`positions`** — today `N×3` origins. For affine, becomes per-tile transform
  parameters (origin + linear block); provide a helper that collapses back to `N×3`
  origins for the translation case and for `planCanvas`.
- **BatchOpt**
  - `TransformType{2}` grows to `{'Translation','Rigid','Similarity','Affine'}` (Rigid/
    Similarity/Affine gated to 2D initially).
  - New `AllowRotation` logical (default `false`); tooltip; widget handle named exactly
    `AllowRotation`; enable only when `TransformType ≠ Translation`.
- **Solver `options`** — add `transformType` + `allowRotation`; translation path
  unchanged when both are default.

## Phasing

1. **Affine solver + resample-aware fuser** (2D), keeping the translation fast path.
   Milestone: chop a known image with an affine warp per tile; global solve + warp-fuse
   recovers it; translation-only inputs still take the integer-placement path and match
   the current result byte-for-byte.
2. **Rigid/Similarity via projection + `AllowRotation`** (2D). Milestone: rotated-tile
   synthetic set recovered with Rigid; with `AllowRotation` off the same set solves as
   translation and rotation residual is exactly zero.
3. **3D affine** once the streaming warp fuser (`imwarp3` per block) is in. 3D rigid
   deferred until a real rotated-3D dataset exists.

## Verification

- Extend `StitchCoreTest`: affine chop → global solve within tol; `AllowRotation` off
  forces zero rotation; rigid-projection is orthogonal (`R'R = I`); translation inputs
  are unchanged (regression guard against the fast path).
- New smoke generator under `development/stitching/` for a rotated 2D tile set
  (see [`smoke_tests.md`](smoke_tests.md)).
