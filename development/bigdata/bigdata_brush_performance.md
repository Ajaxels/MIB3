# BigData segmentation performance — interactive brush at any zoom

> **Superseded 2026-06-25** — consolidated into `bigdata_logic.md` (how it works) +
> `bigdata_implementation_plan.md` (status & remaining work). Kept as the dated detail log.

Make the brush and other segmentation tools responsive on disk-backed BigData models
(`core.MibBigDataLabels`), at any zoom and slide size. Companion to `plan_wsi_readers.md` /
`wsi_livetest_checklist.md`. **Status: RESOLVED 2026-06-17.**

> **Superseded (2026-06-24) by the level-map manager** — see `bigdata_levelmap_spec.md` /
> `bigdata_levelmap_plan.md`. The `reconstructFinerFill` on-read reconstruction below produced a
> coarse-block **halo** around strokes at non-coarsest zooms (measured ~1.8 k spurious px) and broke
> the a/s/r/c/f operations. It was replaced by a per-tile **`matLevel`** map: edits write
> working+coarser and mark the tile; reads recompute finer-than-materialized tiles **from their own
> source level** (no echo halo), cache them, and a **Save** step materializes every level. The
> magFactor fix below (the original 11 s → ms win) is unchanged and still in force. The dead
> deferred-queue machinery and `reconstructFinerFill` have now been **removed**.

## Root cause (the real fix)

A brush stroke at low magnification took ~11 s. DeveloperMode per-stage timing of the brush commit
(`gui_WindowButtonUpFcn`) isolated it to **`write selection: 11 s`** while the read was 6 ms — an
asymmetry. Cause: **`core.MibDataset.setData2D` never set `options.magFactor`** (unlike `getData2D`), so
`MibBigDataLabels.setData63`'s `pickLevel` defaulted to `magFactor = 1` → the **full-resolution** level.
Every stroke, at any zoom, up-sampled the small display block to the whole slide and wrote ~2 GB at full
res. The same gap broke **`clearLayer`** (built a full-res zero block, cleared the full-res level while the
display reads the coarse level → selection never cleared; the leftover green overlay blended with the
material colour and looked like "another material").

**Fixes (both = thread the display magFactor so 2D writes land on the level being viewed):**
- `MibDataset.setData2D` mirrors `getData2D`: sets `options.magFactor = obj.magFactor`
  (or `1` when `resizeToMagnification=false`).
- `MibDataset.clearLayer` passes `obj.magFactor`; `MibImage.clearLayer` (BigData branch only) sets
  `getDataOptions.magFactor` and sizes the zero block at display resolution (no full-res allocation).
- Safe for non-pyramidal models — base `MibLabels63.setData63` / `MibImage.setData` ignore `magFactor`.
- 2D read+write are now both magFactor-aware; 3D `getData3D`/`setData3D` are both full-res (consistent,
  left as-is).

## Storage model (how finer pyramid levels work now)

To keep writes cheap and avoid ever materialising a full-res copy of a coarse edit:
- **`setData63`** writes each edit only at its **drawn (working) level + coarser** levels (cheap
  downsample via `propagateRegion(...,'coarser')`), restricted to the **changed bounding box** (diff vs
  pre-merge; no-op early-out when nothing changed). It **never writes finer levels** and uses no
  queue/timer/drain.
- **`getData63`** reconstructs finer-level reads on the fly: read the level, then fill empty voxels from
  the **coarsest** level (which holds every edit) via `reconstructFinerFill`, which **coverage-masks**
  coarse cells overlapping any fine data so a fine edit's own coarse echo cannot dilate it. Bounded to the
  read window.
- `propagateRegion` is memory-bounded (tiled index-nearest in Y-strips; signed-distance smoothing only for
  upsample targets ≤ 4 MP — and finer upsampling no longer happens, so this path is downsample-only now).

Net: every edit is persisted at its drawn resolution + coarser (durable; reopen reconstructs); finer views
are on-demand reconstructions. No background work.

## Verification (MCP, native zarr, real CMU-1.ndpi BigData model)

- Brush commit timing (DeveloperMode): `write selection` now ms (was 11 s).
- Huge 2 % strokes: **5–9 ms** each; a crisp full-res edit reads back **exactly** (no dilation); coarse
  edits reconstruct at full res on zoom-in; durable across `closeStore`/`openStore`.
- 3 × draw→add-to-material→clear cycles at 2 %: selection **clears** (nonzero 0), labels hold only
  material `1` (no spurious material / wrong colour).
- `check_matlab_code` clean on all changed files.

## Changed files

- `+core/@MibDataset/setData2D.m` — thread `magFactor` (primary fix).
- `+core/@MibDataset/clearLayer.m`, `+core/@MibImage/clearLayer.m` — thread `magFactor` for BigData clear.
- `+core/@MibBigDataLabels/setData63.m` — changed-region only; coarser-only propagation.
- `+core/@MibBigDataLabels/getData63.m` + `MibBigDataLabels.m` (`reconstructFinerFill`) — on-read finer
  reconstruction.
- `+controllers/@MibImageDocument/gui_WindowButtonUpFcn.m` — DeveloperMode per-stage brush timing.
- `+models/@MibModel/createModel.m` — explainer text (live-save, finer levels reconstructed on read).

## Follow-ups (not blocking)

- **Dead code:** the deferred-propagation machinery (`enqueuePropagation` / `buildFinerJobs` /
  `drainPropagation` / `onPropagationTimer` / `propagationQueue` / timer) is now unused — `closeStore`'s
  `flushPropagation` is a no-op over the empty queue. Remove in a later cleanup.
- **Known limitation:** a single viewport mixing a fine edit and a *separate* coarse-only edit shows the
  coarse one at coarse-cell granularity (acceptable for low-mag annotation).
- Earlier superseded approaches (kept here only as rationale): Phase 1 changed-region; Phase 2
  eager-coarse/lazy-fine with a deferred queue; Phase 2b cooperative background drain. All were replaced by
  the magFactor fix + on-read reconstruction above, which removed the need for any deferred propagation.
