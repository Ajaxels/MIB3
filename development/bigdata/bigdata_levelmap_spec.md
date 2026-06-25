# Spec: BigData model "level map" manager (interactive, multi-resolution-correct segmentation)

> **Superseded 2026-06-25** — consolidated into `bigdata_logic.md` (how it works) +
> `bigdata_implementation_plan.md` (status & remaining work). Kept as the dated detail log.

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

## Follow-up fix (2026-06-25): undo backup must not force full resolution

**Symptom:** assigning selection to material (a/s/r keys) or any 2D layer move on a BigData
model took 3–4 s even though the edit itself writes only the working pyramid level.

**Root cause:** `MibModel.backup` forced `getDataOptions.magFactor = 1` for all pyramidal
datasets (`datasetType(1) ∈ {'V','B'}`). For a disk-backed BigData level map this read the
**entire full-resolution slice** (CMU-1: 38144×51200 ≈ 1.95 GP, ~8.4 s) and, worse, triggered
`materializeForRead` at level 1 — prematurely upsampling+writing L1 chunks, defeating the lazy
level map. `getData2D`/`setData2D` in `moveLayers` already auto-pick the display level (≈0.48 s),
so backup was the *only* full-res operation in the path.

**Fix (`+models/@MibModel/backup.m`):** split the pyramidal branch by backend.
- **Virtual ('V')** — unchanged: in-memory full-res model, capture at `magFactor=1`.
- **BigData ('B', `core.MibBigDataLabels`)** — capture at the **working level's native scale**:
  `magFactor = modelScaleFactors(pickLevel(magFactor), 1)`. This reads the raw working level with
  no display resize (lossless), is small and fast (8.4 s → 0.48 s, ~17×), and never touches L1.
  The `magFactor` is stored in the undo entry, so `undo`/redo restore via `setData63` at the same
  level (+ coarser propagation + `markTiles`).

**Verified (live MCP, CMU-1 @ level 2):** full-res read 8.435 s vs working-level 0.484 s;
backup now 0.484 s; capture→restore→reread byte-identical at the working level; `matLevel` stays
at the working level (no premature L1 materialization).

**Sidecar file:** the level map persists next to the store as
`<storePath>.levelmap.mat` (e.g. `Labels_CMU-1.zarr3.levelmap.mat`) — a `-v7` MAT file holding
`matLevel`/`mapVersion`/`coarsestSize`; written by `closeStore`/`saveLevelMap` and on model Save.

### Coordinate-unit follow-up (same day): undo restored nothing

After the backup-level change above, **undo of a BigData `s`/move op restored nothing**.
Cause: `MibBackup.store` fills any absent `options.x/y` from the captured data **size**. With the
snapshot now taken at a coarse level, that size is in LEVEL pixels — but
`orientPhysRanges` (shared by `getData63`/`setData63`) interprets `options.x/y` as
**full-resolution** coordinates. So undo passed level-pixel coords as full-res and wrote the
snapshot into a shrunken top-left region → no visible restore. (The earlier direct
capture→restore test passed only because it bypassed `store()`, leaving x/y absent so
`orientPhysRanges` defaulted to the full extent.)

**Fix (`backup.m`, BigData branch):** pin `getDataOptions.x = [1 width]`, `y = [1 height]`
(full-res extent) when block/ROI mode is off, so `store()` records full-res coordinates and
capture/restore use the same units. Block/ROI modes already set full-res x/y and take precedence.

**Verified (live, real `moveLayers('selection','labels','2D,Slice','remove')` + `undo`):**
labels nnz 340015 → 297611 (subtract) → 340015 (undo) — **byte-identical restore**.

## Performance + naming follow-ups (2026-06-25, part 2)

### a/s/r still slow (3–4 s) after the backup fix — two more causes

Profiling the live `a` (add-to-model) path on CMU-1 @ level 2 found:

1. **`setData63` smoothed the whole slice.** `resizeLayerSmooth` (signed-distance, label-aware)
   ran over the entire 122 MP working slice (3.34 s) before the changed-bbox write. Fix: read
   `before`, locate the change with the cheap nearest pass (0.045 s), then smooth **only the
   changed footprint** (display crop → working window at the same global scale, +4 px margin so
   edges stay clean and grid-aligned). Cost now scales with the edit.

2. **No persistent edit box → whole-slice scans.** `moveLayers`/`clearLayer` ran with block mode
   off, so every step (backup + ~3 getData2D + setData2D) read the entire 122 MP slice (~5×0.48 s).
   `setData63` only ever computed a *transient* per-write bbox; nothing was retained.

   **Fix: persistent selection footprint box.** New `MibBigDataLabels.selectionBBoxFull`
   ([y0 y1 x0 x1 z0 z1] full-res), maintained by `setData63` from the **exact written selection
   bits** (reliable for a 1-px stroke): REPLACE when the processed region covers the previous box
   (so clear/consume shrinks/empties it), else UNION. `moveLayers` (selection source, 2D, no
   ROI/block, orientation 3) sets `BatchOptLocal.x/y` to this box so the backup, all reads and all
   writes scope to the footprint; the post-read selection clear writes zeros over the same scoped
   region (which resets the box). Falls back to the old whole-slice path when the box is unknown
   (e.g. a freshly loaded model before any edit) — correct, just slow that once.

   Measured: forcing the equivalent scope (block mode ON) ran the same `a` in **0.188 s** vs
   **4.85 s** — the visible/footprint region is ~1.6 MP vs 122 MP. Semantics preserved: the box
   finds the selection wherever it was drawn, on-screen or off.

Unit coverage: `tests/core/MibBigDataLevelMapTest.m` → `testSelectionBBoxTracking` (set on write,
untouched by a material write, reset on clear). Full suite 9/9.

### Sidecar naming

Renamed from `<store>.zarr3.levelmap.mat` to **`<store-without-ext>.levelmap`** via the new static
`core.MibBigDataLabels.levelMapPathFor` (e.g. `Labels_CMU-1.levelmap`). The file is MAT-format,
saved/loaded with the `'-mat'` key (no `.mat` extension). NOTE: it is written only by `closeStore`
/ Save — it does **not** exist mid-session until you save or close the model.

## Correctness fix (2026-06-25, part 3): imported models must load precise

User concern: "a loaded model should always be precise — e.g. when you import an existing model."
Correct, and the old no-sidecar fallback violated it.

**The pyramid's finer levels are precise in two cases** — an imported/externally-written model (all
levels properly downsampled) and any model MIB saved fully. They are *deferred/virtual* only during a
live interactive session, and that state is always captured in the sidecar (written on closeStore).

**Bug:** `initLevelMapFallback` (run when no sidecar) set `matLevel = N` (coarsest) for data tiles —
declaring every finer level virtual. For an imported model the first zoom-in past the coarsest then
triggered `materializeForRead`, which upsamples the coarsest and **overwrites the precise finer
levels** → silent degradation.

**Fix:** `initLevelMapFallback` now sets `matLevel = 1` everywhere (assume fully precise). Reads go
straight to the requested level; editing still degrades only the touched tiles (markTiles), rebuilt
lazily on read or on Save. A missing sidecar legitimately means "nothing deferred" because MIB always
writes the sidecar on close. Test `testFallbackWhenSideFileMissing` rewritten to write at the finest
level (emulating an import), drop the sidecar, reopen, and assert the finest level is byte-identical
(no coarsest upsample) and `matLevel` is all 1. Suite 9/9.

## Save confirmation dialog

Pressing Save model on a BigData dataset (`MibRibbon/model_Callbacks`, `Save\nmodel` case) now asks
first via `utils.dlgs.inputQuestDlg` ("Finalize the model now?" — explains it materializes every level
and can take a while; default Cancel). Only "Finalize & save" runs `saveBigDataModel`.

## Sidecar lifetime (answer): keep it, never delete after Save

After `materializeAll`, `matLevel` is all 1 and `saveLevelMap` persists exactly that ("all levels
valid"). Deleting the sidecar would force `initLevelMapFallback` on reopen — which (now) assumes
precise, so it would be harmless for a fully-saved model, but the sidecar is the only durable record
that distinguishes a fully-materialized model from one closed mid-edit with deferred finer levels.
It is tiny (one uint8 per coarsest tile) and should always be kept.

## Crash-safety + UX + docs (2026-06-25, part 4)

**Sidecar-only save (crash safety).** Pixel edits are written to the zarr live; only the in-memory
level map is volatile. `saveBigDataModel(obj, id, mode)` gained a `mode`:
- `'full'` (default) — `materializeAll` + `saveLevelMap` (consistent at all levels; can be slow).
- `'sidecar'` — `saveLevelMap` only (fast). A crash checkpoint: a reopen then reconstructs deferred
  finer levels correctly instead of showing stale data.

`MibRibbon/model_Callbacks` (`Save\nmodel`, BigData branch) now offers a 3-way choice via
`inputQuestDlg`: **Finalize & save** / **Save sidecar** (default) / **Cancel**.

**Help button on dialogs.** `utils.dlgs.inputQuestDlg` gained `options.HelpUrl` (+ `HelpBtnText`):
when set, a Help button appears bottom-left and opens the URL/.html in the browser (mirrors
`inputUniversalDlg.onHelp`). The Save-model dialog wires it to
`https://mib.helsinki.fi/help/main3/getting-started/dataset-types/index.html` (page to be published).

**Docs.** Moved the "Dataset types" section out of
`docs/docs/user-interface/panels/datasets/index.md` (left a short summary + link) into a new
`docs/docs/getting-started/dataset-types/index.md`, expanded with a "How BigData works" section
(image/model pyramids, live writes + coarser propagation, lazy finer reconstruction + cache, the level
map & `.levelmap` sidecar, selection-footprint scoping, and the two Save options incl. crash recovery).
Registered in `docs/zensical.toml` under Getting Started. Build clean (the relative-`.md` "page does
not exist" warnings are the repo's pre-existing build characteristic, shared by all existing pages).

Tests: MibBigDataLevelMapTest 9/9.
