# BigData — logic & architecture reference

**Read this first whenever you touch BigData.** It explains *how* the BigData dataset type works
(image reads, the disk-backed segmentation model, the level map, coordinate conventions, the
WSI-safe editing rules) and the invariants you must preserve. For *what is done / still to do*, see
the companion `bigdata_implementation_plan.md`.

> Consolidated 2026-06-25 from `plan_bigdata.md`, `bigdata_levelmap_spec.md`,
> `bigdata_levelmap_plan.md`, `bigdata_brush_performance.md`, `plan_wsi_readers.md`,
> `wsi_livetest_checklist.md`. Those remain as the dated detail log (superseded by these two docs).

---

## 1. What BigData is, and when to use it

MIB has three dataset types (`MibDataset.datasetType`):

| Type | Pixels held | Editable model | Use |
|------|-------------|----------------|-----|
| **Standard** | whole volume in RAM | ✅ full | small–medium datasets |
| **Virtual** | read on demand | ❌ browse-only | browse datasets too large for RAM |
| **BigData** | read on demand, **pyramidal** | ✅ **disk-backed** model | **segment** datasets far larger than RAM |

BigData = "Virtual that you can also segment." The **image** is a pyramidal, chunked store read on
demand (zoom picks the resolution level; pan reads only the visible chunks). The **segmentation
model** is a separate disk-backed pyramidal packed-63 store that mirrors the image pyramid, written
live as you edit. Cost of every operation scales with the **size of the edit**, not the slide.

**Single time point only** (T=1). 63 materials max (packed model). Source image is read-only — you
edit the model, never the image pixels.

---

## 2. Class architecture & data flow

```
core.MibDataset (datasetType = 'BigData')
  ├── image  : core.MibBigDataImage   < core.MibVirtualImage < core.MibImage
  │              reads via getData → getDataZarr (pyramid level + region + orient math)
  │              backend chosen by pyramid.sourceType: 'zarr3' | 'bioformats' | 'openslide'
  │              obj.data is EMPTY (on-demand); dims from height/width/depth/pixSize
  └── labels : core.MibBigDataLabels   < core.MibLabels63
                 packed-63 model in a writable OME-Zarr v3 group (one array per pyramid level)
                 obj.data EMPTY; getData63/setData63 read/modify/write the store block-wise
```

**The integration seam that makes BigData work with every tool unchanged:**
`MibDataset.getData2D/3D/4D` (+ `setData…`) slow path calls `obj.labels.getData(type,…)` /
`setData(…)`. `MibImage.getData` routes non-image layers to `getData63`/`setData63`. Because
`MibBigDataLabels` **overrides `getData63`/`setData63`** to operate on the disk store, every
segmentation tool, backup/undo, and clearLayer works without per-tool edits — they all funnel through
this pair.

**Reader-agnostic image seam:** `getDataZarr` does all coordinate/level/orientation math then calls a
single primitive `loader.readRegion(levelKey, physY, physX, physZ, Clim, Tlim, dataClass)` returning
a MIB `[y x z c t]` block. Any backend that implements `readRegion` + populates `obj.pyramid`
(`levelImageSizes [N×3 Y X Z]`, `levelScaleFactors [N×3]`) works unchanged — that is how zarr3,
BioFormats and OpenSlide all drive the same path.

---

## 3. The image pyramid (read path)

- A pyramid stores the same picture at several resolutions: `s0` = full res, `s1` … `sN` = coarsest,
  each split into chunks. **Finer = smaller level index; level 1 = full resolution; level N =
  coarsest.** (Note scale steps are format-dependent — NDPI ×4/level, zarr typically ×2.)
- **Level selection:** `getData2D` auto-injects the display `magFactor`; `pickLevel(magFactor)` picks
  the nearest level. `getData3D`/`getData4D` do **not** inject magFactor → they read full res.
- **`orientPhysRanges`** (shared by image and model) maps screen axes `options.x/y/z`
  (horizontal/vertical/slice) to physical data axes per orientation, scales **each axis by its own
  pyramid factor**, clamps each to **its own** physical dimension. `options.x/y/z` are always
  **full-resolution coordinates** even when reading a coarse level. Orientation: `3` = XY (default),
  `1` = ZX, `2` = ZY.
- The Z axis is **not** downsampled in the model pyramid; image pyramids *may* downsample Z at coarse
  levels (the export path handles per-axis `levelScaleFactors`).

---

## 4. The segmentation model: packed-63 disk pyramid

- Packed `uint8` per voxel, identical bit layout to `MibLabels63`:
  `bitand(x,63)` = material index, `bitand(x,64)` = mask (bit 7), `bitand(x,128)` = selection (bit 8).
- Stored as an OME-Zarr v3 **group**, one packed array per image level (`modelArrays{L}`,
  `modelLevelSizes`, `modelScaleFactors` — normalised to level-0-relative factors on open). Native
  MATLAB axis order (transpose codec → no permute for MIB-written stores).
- Created on demand (browse-only until a model exists). Default store name `Labels_<imageStem>.zarr3`
  next to the image; the user is prompted for the location (`uiputfile`).
- Written **live**: every `setData63` writes to disk, so "save" happens continuously — the only thing
  a Save finalizes is the deferred finer levels + the level map (see §6/§9).
- Material names/colours persist in a `mibMaterials` zarr attribute (`writeMaterialMetadata`),
  restored by `openStore`; rewritten on every add/rename/remove material.

---

## 5. The level map (`matLevel`) — the core of correct multi-resolution editing

The level map solves the central problem: an edit drawn at one zoom must read back correctly at every
zoom, without re-materializing the whole slide on every stroke.

**`matLevel`** — a small `uint8` array over the **coarsest** level's pixel grid
(`[coarseY × coarseX × coarseZ]`, Transient). `matLevel(tile)` = the **finest pyramid level that holds
materialized data** for that tile. `0` = empty. Because the coarsest level is tiny, this map is ≲1 MB.

**Write rule (`setData63`, edit at working level x):**
1. Merge the change into level **x** and **all coarser levels** (cheap downsample via
   `propagateRegion(…, 'coarser')`), restricted to the changed bounding box.
2. Set `matLevel(touched tiles) = x` (`markTiles`). Finer levels (`< x`) are now implicitly dirty.
3. A later coarser edit over the same tile (working `x2 > x1`) sets `matLevel = x2` → invalidates any
   finer materialized data there (latest edit wins per tile).

**Read rule (`getData63`, request level L):** for tiles where `matLevel > L` (L finer than
materialized), `materializeForRead` reads the source level, upsamples to L, **writes it down**, and
sets `matLevel = L` (cache). Then a normal read returns correct data. Tiles where `matLevel <= L` read
straight from disk. Bounded to the read window → a zoom/pan pays at most one viewport of recompute,
once.

**Why this matters:** reading a clean level returns stored data unchanged → the editing zoom is sharp
with **no halo**; recompute only happens for finer levels not yet visited, sourced from the nearest
clean coarser level. (The old `reconstructFinerFill` approach produced a ~1.8k-px coarse-block halo
and is fully removed.)

### Sidecar file — persisting the level map

- `matLevel` persists in a side-file **next to the store**, named `<store-without-ext>.levelmap`
  (e.g. `Labels_CMU-1.levelmap`) via the static `core.MibBigDataLabels.levelMapPathFor`. It is a
  **MAT-format file saved/loaded with the `'-mat'` key** (note: no `.mat` extension).
- Written **only** by `closeStore` and by Save — it does **not** exist mid-session until you save or
  close. Holds `matLevel` / `mapVersion` / `coarsestSize`. Tiny (one uint8 per coarsest tile); keep it
  always (never delete after Save).
- **A loaded model is always treated as precise.** `initLevelMapFallback` (run when no sidecar) sets
  `matLevel = 1` everywhere — an imported/externally-written pyramid has all levels properly
  downsampled, so deferral is purely a within-session optimisation captured in the sidecar. (The old
  fallback set `matLevel = N` and silently degraded imported models on first zoom-in — fixed.)

---

## 6. Operations (a/s/r/c/f) & the selection footprint

Selection ops route through `getData63`/`setData63` like everything else, so they are multi-resolution
correct automatically. Two pieces keep them **fast** on gigapixel slides:

- **`setData63` smooths only the changed footprint.** It reads `before`, locates the change with a
  cheap nearest pass, then runs the label-aware signed-distance `resizeLayerSmooth` over only the
  changed display crop → working window (+4 px margin), not the whole slice.
- **Persistent selection footprint** `selectionBBoxFull` (`[y0 y1 x0 x1 z0 z1]` full-res, Transient,
  maintained by `setData63` from the exact written selection bits): REPLACE when the processed region
  covers the previous box (clear/consume shrinks/empties it), else UNION. `moveLayers` (selection
  source, 2D, no ROI/block, orient 3) sets `BatchOptLocal.x/y` to this box so backup + all reads/writes
  scope to the footprint, and the post-read selection clear writes zeros over the same scoped region.
  Falls back to whole-slice when the box is unknown (freshly loaded model). Measured: `a` (add-to-model)
  **4.85 s → 0.188 s**.

---

## 7. Backup / undo — the coordinate-unit invariant

Undo routes through `getData2D`/`setData2D` (→ `getData63`/`setData63`) so it works with no special
code — **but** `MibModel.backup` must capture at the right level and in the right coordinate units:

- **BigData branch (`backup.m`):** capture at the **working level's native scale**
  (`magFactor = modelScaleFactors(pickLevel(magFactor),1)`), not full res. Forcing `magFactor = 1`
  read the entire full-res slice (CMU-1: ~8.4 s) **and** triggered premature L1 materialization. Fix →
  0.48 s and no L1 touch. (Virtual stays `magFactor = 1`: its model is in-memory full res.)
- **Pin x/y to the full-res extent** (`x = [1 width]`, `y = [1 height]`) when block/ROI mode is off.
  `MibBackup.store` fills absent x/y from the captured data **size** — which at a coarse level is in
  *level* pixels, but `orientPhysRanges` reads x/y as **full-res**. Without pinning, undo wrote the
  snapshot into a shrunken top-left region and restored nothing. With it: byte-identical restore.

---

## 8. WSI-safe editing convention (footprint-bounded)

**Rule: every BigData edit — read, write, AND undo-backup — scales with the edit footprint, not the
slide size.** A single full-res slice can be many GB; never `getData2D`/`poly2mask` a whole gigapixel
slice. Per-tool status:

- **Already footprint-bounded:** Spot (`[x±r,y±r]`), Magic Wand / Region Growing **radius>0**
  (radius window), 3D Ball.
- **Bounded to a bbox:** Lasso / Rectangle / Ellipse — read the polygon bbox, `poly2mask` onto a
  bbox-sized canvas with offset coords, write only the bbox (YX; ZX/ZY keep whole-slice + warn).
- **Bounded to a window:** Drag&Drop — **single object only** on BigData (all-objects drag blocked);
  read/write the visible∪shifted window; live preview in shown coords (not fast-pan).
- **Work at displayed level + propagation:** Brush, Membrane ClickTracker, SAM/SAM2 interactive
  (effectively the reference tools the model was designed around).
- **Guarded (warn, never block):** Magic Wand / Region Growing **radius=0** flood — the only remaining
  whole-slice read; `utils.warnLargeFullResRead(h, w[, budgetMP])` (default 256 MP, throttled once).
- **Blocked on BigData:** Object Picker, Black-and-White Thresholding, SAM *Automatic everything*
  (generates 65535 materials; packed store holds 63).

Undo-backups for Brush / ClickTracker use block mode; Wand / Region Growing back up *after* the radius
window is built; Lasso / Drag&Drop back up their bbox/window.

---

## 9. Saving a BigData model

Pixel edits are already on disk; the only volatile state is the in-memory level map. So
`MibModel.saveBigDataModel(obj, id, mode)` offers two modes (the **Save model** ribbon button shows a
3-way `inputQuestDlg`: **Finalize & save** / **Save sidecar** (default) / **Cancel**, with a Help
button → the dataset-types help page):

| Mode | Action | Speed |
|------|--------|-------|
| `'full'` | `materializeAll` (materialize every level from the level map → `matLevel` all 1) + `saveLevelMap` — consistent at all zooms, required for export / external readers | slower on a large slide |
| `'sidecar'` | `saveLevelMap` only — a fast crash-safety checkpoint; a reopen then reconstructs deferred finer levels correctly instead of showing stale data | fast |

**Workflow:** *Save sidecar* periodically during a long session (cheap insurance against a crash);
*Finalize & save* once at the end or before exporting.

---

## 10. Coordinate conventions — the one recurring bug class

The single most common BigData bug: **mixing full-res click coordinates with display-res
`getData2D` data.** The coordinate conversion (`convertMouseToDataCoordinates`) is shared and always
returns **full-res** dataset coords. But:

- `getData2D` auto-injects `magFactor` → returns the **displayed (downsampled) level**.
- `getData3D` does **not** inject magFactor → returns **full res**.

So any tool doing pixel math (`currImage(y,x)`, `bwselect`, `poly2mask`, shift-indexing) with full-res
coords on a display-res slice lands shifted/mis-scaled. **The fix in every such tool is the same
one-liner:** set `options.magFactor = 1` for `'V'`/`'B'` so the (footprint-bounded) region is read in
full-resolution units. `segmentationClickTracker` keeps its `yx*magFactor` mapping *and* uses
`magFactor=1` — the block-mode `options.x/y` are full-res axes limits, so there is no double-correction.

When adding or porting a click tool, check this first.

---

## 11. Smoothing (coarse→fine up-propagation)

Editing zoomed-out captures the edit at the **working (coarse) level**, so reconstruction at full res
can only be as accurate as that coarse mask (±~1 working-level px). To avoid blocky boundaries,
up-sampling uses **label-aware signed-distance smoothing** (`resizeLayerSmooth` /
`smoothLabelUpsampleYX`): per-region SDF `D = bwdist(~M) - bwdist(M)`, bicubic-upsampled + Gaussian
(sigma = up/2), thresholded at 0. Down/equal-size use `resizeBlockNearest`. Gated by
`io.zarr.Config.smoothing()` (preference `IO.Zarr.Smoothing`, default true). `'everything'`/undo blocks
are **never** smoothed (must round-trip exactly). Smoothing cannot invent detail finer than the level
drawn at — for crisp boundaries, draw at higher zoom.

---

## 12. Invariants & gotchas (do not break these)

- **Never change a core-class method *signature* mid-session.** MATLAB hot-reloads method *bodies* but
  not parameter-count changes while the running app holds instances → "Too many input arguments". Put
  new params in the stable `MibModel` wrappers (e.g. all store-path logic lives in `MibModel.createModel`,
  not `MibDataset.createModel`). Ribbon *items* (not callbacks) also need a restart to appear.
- **`datasetType(1)` branching:** Virtual is `'V'`, BigData is `'B'`. Code that means "on-demand /
  browse-style" must test `any(datasetType(1)==['V' 'B'])`, not just `'V'`. Code that means
  "browse-only" is `datasetType(1)=='V' || (datasetType(1)=='B' && ~modelExist)` — BigData with a model
  behaves like Standard.
- **`obj.id` vs `obj.getActiveId()`** — always `getActiveId()` for `BatchOpt.id` defaults (split-panel
  safety).
- **`setData` arg order** — MIB3 is `setData(dataset, type, …)` (data first); `getData` is `type` first.
  Orient `4`→`3`; layer `'model'`→`'labels'`; use `[]` (not `NaN`) for current slice/orient.
- **Python zarr backend:** never `clear classes` while OutOfProcess Python objects exist — it wedges
  the interpreter for the whole session (restart required). The smoothing flag and
  `io.zarr.Config.*` are process-wide; editing them mid-session affects the live app.
- **HTTP/HTTPS zarr arrays force the native backend** (python remote needs fsspec, not wired).
- **`getData4D` squeezes singleton dims** — for a grayscale T>1 dataset the time axis is misread as
  colours. Fine for T=1 (the norm); tied to the deferred T>1 work.
- **Save model never deletes the sidecar.** It is the only durable record distinguishing a
  fully-materialized model from one closed mid-edit with deferred finer levels.

---

## 13. File map

| Concern | File(s) |
|---------|---------|
| BigData image (read) | `+core/@MibBigDataImage/` (thin subclass of `@MibVirtualImage`) |
| Image read seam | `+core/@MibVirtualImage/getDataZarr.m`, `getData.m`, `getOrCreateLoader.m` |
| Disk-backed model | `+core/@MibBigDataLabels/` — `MibBigDataLabels.m` (class + `createStore`/`openStore`/`closeStore`/`readPackedLevel`/`writePackedLevel`/`propagateRegion`/`materializeForRead`/`materializeAll`/`markTiles`/`tilesForFullRegion`/`saveLevelMap`/`loadLevelMap`/`initLevelMapFallback`/`orientPhysRanges`/`levelMapPathFor`/`bboxUnion`/`updateSelectionBBoxFromWrite`/`resizeLayerSmooth`/`resizeBlockNearest`), `getData63.m`, `setData63.m` |
| Dataset wiring | `+core/@MibDataset/{initialize,switchDatasetMode,createModel,getData2D/3D/4D,setData2D/3D/4D,clearLayer}.m` |
| Model create/load/save | `+models/@MibModel/{createModel,loadModel,saveBigDataModel,backup,moveLayers,getRGBimage}.m` |
| Save button | `+controllers/@MibRibbon/model_Callbacks.m` (`Save\nmodel` case, BigData branch) |
| Dialog w/ Help | `+utils/+dlgs/inputQuestDlg.m` (`HelpUrl`/`HelpBtnText`) |
| WSI direct read | `+io/+BioFormats/{Config,Reader}.m`, `+io/+loaders/BioFormatsVirtual*.m`, `ExtensionRegistryLoad.m`, `LoaderFactory.m` |
| Zarr facade (native/python) | `+io/+zarr/{Config,Array,Group,PyBackend}.m` |
| Zarr3 writer / ingest | `+io/+savers/Zarr3Saver.m`, `+io/+adapters/ZarrBlockedAdapter.m` |
| Streaming export | `+io/+savers/{SliceProvider,InMemorySliceProvider,MibImageSliceProvider,BaseSaver}.m` + per-format savers |
| Tests | `tests/core/MibBigDataLevelMapTest.m` |
| User docs | `docs/docs/getting-started/dataset-types/index.md` |
