# Start here — 3D-affine stitching implementation

> **DONE (2026-07-19).** Implemented and verified — see the Phase 3 status block in
> [`plan_transforms.md`](plan_transforms.md) for what was done and what testing revealed
> (cross-layer `M = I` coupling). This brief is kept for historical context only.

Single-file brief for a fresh session picking up the **3D-affine** work on the MIB3
stitching tool. Read this, then the linked files, then implement.

## Scope (READ THIS FIRST — it is narrower than it sounds)

"3D affine" here = the **existing 2D in-plane affine model running on depth>1 /
multi-layer data**. Each z-slice of a tile is warped by that tile's single 2D affine;
**z stays translational**. This is NOT full 12-parameter volumetric affine (deferred —
needs `imwarp3` per block, 3D correspondences, SO(3) averaging; see "Future directions"
in `plan_transforms.md`).

## The load-bearing fact

- Translations compose **additively** → per-axis (y, x, z) independent sparse LS.
- **z composes additively regardless of the in-plane model.** So with 2D-in-plane affine
  on 3D data, z stays translational and the solver's z path needs no change.
- The fuser warps **per output slice** with the tile's single 2D tform — the depth loop is
  implicit in the per-`zGlobal` calls, so **no `imwarp3` is needed** for this scope.

## Orientation — read in order

1. `development/stitching/plan_transforms.md` — authoritative plan; Phase 3 STARTED scope
   note (2026-07-19) + "Future directions" deferrals.
2. `development/stitching/plan_stitching.md` — parent plan; architecture, `layout(i)` /
   `edges(k)` data structures, `+utils/+stitch` module map.
3. `CLAUDE.md` stitching + MATLAB coding sections — conversion rules, `dictionary` not
   `containers.Map`, copy-on-write loop rule, live-session class-reload caveat.
4. `development/stitching/smoke_tests.md` Test 11 (Translation vs Affine) + expected-numbers
   table — the behavior to reproduce on 3D data.

## The 4 code sites that matter

| File | What / status | Change? |
|------|---------------|---------|
| `mib/+controllers/@Stitching/measureOverlaps_Callback.m` **:28-42** | THE GATE — throws "2D transforms only" when `is3D` and non-translation. | **YES** — relax to allow affine on 3D. Primary change. |
| `mib/+utils/+stitch/measureAllPairs.m` **:198-287** (`measureOne`) | Already correct for scope: **:210-217** forces z-edges to translation; **:234-239** feature-based reads full tiles for x/y; **:258-274** fits 2D affine on depth-flattened crop, lifts to tile-local. | Verify only. |
| `mib/+utils/+stitch/solveGlobalAffine.m` | 6 params/tile 2D affine; z delegated to `solveGlobalLeastSquares` (additive). | Likely none — verify z path on multi-layer. |
| `mib/+utils/+stitch/planCanvas.m` + `fuseSliceComposite.m` | `useTforms` warped-footprint plan; per-slice `warpTileSlice` (imwarp bilinear). | Verify across depth>1 / multiple z-layers. |

## Design check BEFORE coding

Gate the relaxed 3D path to **feature-based only** — phase correlation cannot measure
rotation, so affine on 3D must force feature-based exactly like the 2D path already does in
`updateWidgets.m:59-83` (RegistrationMethod locks + displays "Feature-based" for any
non-translation transform).

## Implement + verify

1. Relax the gate in `measureOverlaps_Callback.m` (allow non-translation on 3D).
2. Add smoke generator `development/stitching/13_stitch_smoke_affine3d/generateSmokeAffine3DTiles.m`
   (2x2xN-layer chop, tiles rotated +/-1 deg / scaled +/-1%, z jitter) + register in
   `smoke_tests.md`.
3. Add a `tests/utils/StitchCoreTest.m` case: 3D affine chop -> measure -> `solveGlobalAffine`
   -> `planCanvas` -> fuse; assert matrix max-abs + z error within Test-11 tolerances
   (<= 0.22 matrix max-abs, RMSE ~ 0.02 px).
4. `buildtool test` / `buildtool check` (needs `addpath('tests')`), or MATLAB MCP
   `run_matlab_test_file` / `check_matlab_code` for iteration.
5. Update docs: `docs/docs/user-interface/ribbon/dataset/dataset-stitch.md` + the api RST.

## Session caveats

- MATLAB is a **shared live session**: after editing a class method, reload with the
  class-reload recipe (clear the controller instance / `clear classes`) before re-testing —
  a stale class silently runs old code.
- The user does **all git commits himself** — do not commit.
- `.mlapp` files stay layout-only. Navigation keys never mutate state.
