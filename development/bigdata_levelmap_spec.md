# Spec: BigData model "level map" manager (interactive, multi-resolution-correct segmentation)

Date: 2026-06-24. Supersedes the reconstruct-on-read approach in `bigdata_brush_performance.md`.
Companion: `plan_wsi_readers.md`, `wsi_livetest_checklist.md`. Plan: `bigdata_levelmap_plan.md`.

**Status: IMPLEMENTED 2026-06-24** (headless-verified via `development/verify_levelmap.m` +
`tests/core/MibBigDataLevelMapTest.m`, 8/8 Unit tests pass). Pending: live in-GUI re-test of
brush + a/s/r/c/f at low mag, and the Save button on a real session.

## Goal

On a disk-backed BigData model (`core.MibBigDataLabels`, packed-63 pyramid), make brush + the
selection operations (`a` add, `s` replace, `r` remove, `c` clear, `f` fill) **interactive at any zoom**
and **visually correct at every zoom**, with a **Save** step that finalizes the full-resolution model.

## Problem with the current approach

`reconstructFinerFill` (stateless "fill empty voxels of a finer read from the coarsest level") cannot tell
a coarse *echo* of this level's own stroke from a genuinely coarser-drawn edit. Measured result: a stroke
painted at a non-coarsest level reads back with ~1.8 k spurious "cubic block" pixels around it (a halo),
and downstream operations are corrupted. Root: reconstruction must come from the level the data was
actually drawn at, not the coarsest — which requires tracking, per region, where the authoritative data
lives.

## Design overview

Keep the existing packed pyramid on disk (`modelArrays{L}`, all levels allocated). Change the write/read
rules and add one small piece of state:

- **`matLevel`** — a small per-tile array over the **coarsest** level's pixel grid (`uint8`,
  `[coarseY × coarseX × coarseZ]`, `0` = empty). `matLevel(tile)` = the **finest pyramid level index that
  holds materialized data** for that tile (finer = smaller index; level 1 = full resolution). Because the
  coarsest level is small, this array is small (≲1 MB) and cheap to scan.

### Write (edit / operation at working level x)
1. Merge the change into level **x** and **all coarser levels** (x…N) over the changed bounding box — the
   existing cheap downsample (`propagateRegion(...,'coarser')`). Zoom-out is therefore always current.
2. Set `matLevel(tiles touched) = x`. Finer levels (`< x`) are now implicitly **dirty** for those tiles
   (they are not written and `matLevel` says the authoritative data is at x).
3. A coarser later edit (working `x2 > x1`) over the same tile sets `matLevel = x2`, which **invalidates**
   any finer materialized data there (reads finer than x2 will recompute) — "latest edit wins" per tile.

### Read (request level L over a window) — recompute-then-cache
1. Map the window to coarsest tiles. Tiles split into:
   - `matLevel == 0` → empty.
   - `matLevel <= L` (data materialized at L or coarser, present on disk) → **read level L directly**.
   - `matLevel > L` (L is finer than what's materialized) → **dirty**: recompute then read.
2. For each dirty tile group (by `matLevel` value `A`): read level **A** for the region, **upsample A→L**,
   **write it into level L** (materialize), set `matLevel = L` for those tiles. Then read L directly.
3. Reading a clean level returns the stored data unchanged → **the editing zoom is sharp, no halo**;
   recompute happens only for finer levels not yet visited, sourced from the **nearest clean coarser
   level** (`A`, which approaches L as intermediate levels get materialized → minimal upsampling).
4. Recompute is **viewport-bounded** (only tiles in the read window), so a zoom/pan pays at most one
   viewport of recompute, once; subsequent views of the same region are plain reads.

### Operations (a/s/r/c/f)
No special-casing: they already route through `getData63`/`setData63`. With the rules above, the selection
→ mask/labels move runs at the working level + coarser and re-tags finer tiles dirty for the target layer,
so it is consistent at every zoom automatically. (`clearLayer` already threads `magFactor` from the recent
fix and stays compatible.)

### Save (finalize)
A **Save** action materializes every non-empty tile down to level 1 (and ensures all coarser levels are
consistent): for each tile with `matLevel > 1`, recompute levels `matLevel-1 … 1` from `matLevel`, write,
set `matLevel = 1`. Shown with a progress bar. After Save the on-disk pyramid is fully consistent at every
level (correct for export and any external reader). Wire Save to the **Model ribbon → Save** button for a
BigData model, and run it automatically on dataset close / before the store handles are released.

### Persistence — side-file
Persist `matLevel` (+ store geometry: level sizes/scales) in a **side-file next to the store**
(`<storePath>.levelmap.mat`), NOT inside the `.zarr3` group — keeps the OME-Zarr structure byte-standard
and avoids confusing strict readers. On `openStore`:
- side-file present → load `matLevel`.
- missing/older store → **fallback**: treat the coarsest level as the only materialized level
  (`matLevel = N` where the coarsest has data, else 0) so finer levels recompute lazily; correctness
  preserved, just some redundant first-visit recompute.
Write the side-file on Save and on `closeStore`.

### Model-type extensibility (future)
The manager (matLevel + write/read/recompute/Save) is **layer/format-agnostic**: it operates on packed
bytes via the existing `readPackedLevel`/`writePackedLevel` + resample helpers. Non-packed model types
(255 = uint8, 65535 = uint16, 4294967295 = uint32) would reuse the same `matLevel` logic with a
different per-level array dtype and a trivially different "merge"/resample (label-nearest, no bit
packing). **Not built now** — design interfaces so adding them is a storage backend, not a rewrite.

## Components / files to change

- `+core/@MibBigDataLabels/MibBigDataLabels.m` — add `matLevel` property + helpers
  (`tileGrid`, `markTiles`, `materializeTiles`, `saveLevelMap`/`loadLevelMap`); remove dead deferred-queue
  machinery (`enqueuePropagation`, `buildFinerJobs`, `drainPropagation`, `onPropagationTimer`,
  `propagationQueue`, timer, `flushPropagation`’s queue path).
- `+core/@MibBigDataLabels/setData63.m` — write working+coarser (keep), set `matLevel`; drop finer
  propagation/enqueue.
- `+core/@MibBigDataLabels/getData63.m` — replace `reconstructFinerFill` with the matLevel
  recompute-then-cache read; remove `reconstructFinerFill`.
- `+core/@MibBigDataLabels/` — `createStore`/`openStore`/`closeStore`: init/load/save the side-file;
  `closeStore` triggers Save (full materialize) or at least persists `matLevel`.
- A **Save** entry point: `models.MibModel` method (e.g. `saveBigDataModel`) + wire into
  `controllers.MibRibbon.model_Callbacks` (Model → Save) for BigData; progress dialog.
- Verification scripts + `tests/` cases.

## Edge cases / decisions

- **Empty tiles** never recompute (matLevel 0).
- **Mixed-zoom in one tile**: latest edit's level wins (its data, resampled); finer detail from an earlier
  different-level edit in the same tile is superseded. Tunable via tile size; coarsest-pixel grid is the
  default (small map, per-coarse-pixel fidelity).
- **Crash before Save**: working+coarser levels are durable; finer levels recompute from `matLevel` on
  reopen (side-file restores state). No data loss of the drawn annotation (it lives at its drawn level).
- **`getData3D`/`setData3D`** remain full-res (consistent pair) — out of scope; this spec is the 2D
  interactive path.

## Verification (MCP, native zarr, real CMU-1.ndpi)

- Halo: paint at a non-coarsest level, read back at that level → **0 halo pixels** (vs ~1.8 k today).
- Sharpness: read at the painting zoom == drawn (exact); zoom-in shows honest upsample (no halo); zoom-in
  twice = plain read (cached, no second recompute).
- Operations: a/s/r/c/f at low mag → correct model at editing zoom and after zoom change; clear removes;
  add uses the right material; "paint over material" leaves material intact.
- Save: after Save, every level read directly == the resampled model (fully materialized); reopen via
  side-file restores; missing side-file falls back without error.
- Bounded cost: edit + each zoom/pan = one viewport of work; peak memory bounded; no full-res write except
  during Save. `check_matlab_code` clean on all changed files.

## Implementation phases + recommended model

Ordered; each independently verifiable. **Model column = the cheapest model that can do that part well**,
to optimize token spend.

| # | Task | Model |
|---|------|-------|
| 1 | Remove dead deferred-queue machinery (`enqueuePropagation`/`buildFinerJobs`/`drainPropagation`/`onPropagationTimer`/queue/timer) and the `flushPropagation` queue path. Pure deletion + keep `propagateRegion('coarser')`. | **Sonnet** |
| 2 | Add `matLevel` property + tile-grid helpers (coarsest-grid indexing, full-res↔tile mapping) + `saveLevelMap`/`loadLevelMap` side-file (`.mat`) with fallback. | **Sonnet** |
| 3 | `setData63`: keep working+coarser write (changed-bbox), set `matLevel` for touched tiles; drop finer enqueue. | **Sonnet** |
| 4 | `getData63`: matLevel recompute-then-cache read (group dirty tiles by source level, upsample, materialize, mark clean, then read). **Coordinate/resample correctness-critical.** | **Opus** |
| 5 | `createStore`/`openStore`/`closeStore` integration (init/load/save side-file; closeStore persists). | **Sonnet** |
| 6 | Save path: `MibModel.saveBigDataModel` (materialize all tiles → level 1, progress bar) + wire Model→Save button + auto-on-close. | **Sonnet** |
| 7 | MCP verification script (halo=0, sharpness, ops, save/reopen, bounded cost). **Design the assertions.** | **Opus** |
| 8 | `tests/` unit tests (round-trip per level, ops, save/reopen, fallback). | **Sonnet** |
| 9 | Remove `reconstructFinerFill`; update docs (`createModel` explainer mentions Save) + this plan’s status. | **Sonnet** |

Opus only for #4 (the read/recompute coordinate math — the one subtle, correctness-critical piece) and #7
(deciding what to assert). Everything else is well-specified mechanical work for Sonnet.

## Out of scope (now)
255/65535/4294967295 model types; `getData3D`/`setData3D` lazy levels; per-layer (vs per-tile) source
tracking; chunk-grid-aligned (vs coarsest-pixel) tiles.
