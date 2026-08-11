# BigData — implementation status & remaining work

Companion to `bigdata_logic.md` (how it works). This is the **roadmap**: what is complete, what is
still open, and the concrete next steps. **No git commits** (project rule: edit local files only).
Every change ends with `check_matlab_code` clean + an MCP verification snippet on the real model
(`C:\Matlab2\Data\FileFormats\czi\CMU-1.ndpi` opened as BigData).

---

## 1. Status at a glance

| Area | State |
|------|-------|
| Open & browse a pyramidal OME-Zarr v3 as BigData (pan/zoom/orient, bounded memory) | ✅ DONE |
| Disk-backed packed-63 model: create-on-demand, getData63/setData63, pyramid + propagation | ✅ DONE |
| Model overlay (`getRGBimage`), segmentation UI re-enable, store-location prompt | ✅ DONE |
| Model reopen (`openStore`), load-model UI, material name/colour persistence | ✅ DONE |
| All segmentation tools made BigData-correct (display-vs-full-res fixes) + WSI-safe (footprint-bounded) | ✅ DONE |
| ZX/ZY orientation switching for BigData | ✅ DONE |
| Smooth coarse→fine up-propagation (SDF), dual zarr backend (native/python) | ✅ DONE |
| **Level map** (`matLevel`) + sidecar: interactive & correct at any zoom; halo=0 | ✅ DONE |
| Backup/undo coordinate fix; selection-footprint scoping (a/s/r/c fast) | ✅ DONE |
| Imported-model precision fix (fallback = precise) | ✅ DONE |
| Save model: full vs sidecar, confirmation dialog, Help button | ✅ DONE |
| WSI direct read (BioFormats/OpenSlide) as BigData — Phases A–D | ✅ DONE (headless) |
| Zarr3 ingest writer + streaming + generic Save dialog registration | ✅ DONE |
| Streaming export of a chosen pyramid level → standard formats — Phases 1–4 | ✅ DONE |
| **3D volume rendering (VolRenApp)** of BigData via pyramid level + live overlay updates | ✅ DONE (code + headless); App Designer widgets + live-GUI pending (see §8) |
| **Live in-GUI validation** of WSI open + segmentation + export | ✅ DONE (2026-06-30, see §4) |
| **Alignment for BigData** (new-store output + buffer swap): drift, feature-v2 affine, landmarks (annotation-driven), packed-63 warp | ✅ DONE (headless + e2e; see `alignment_plan.md`, `bigdata_logic.md` §13); live-GUI acceptance still open |
| Streaming export plan — remaining per-format deep streaming + mask path | ⏳ OPEN (see §2) |
| Backlog (T>1, removeMaterial renumber, remote zarr, etc.) | ⏳ DEFERRED (see §5) |
| Audit findings — correctness/perf/tool-coverage gaps not yet acted on | ⏳ OPEN (see §9) |

Tests: `tests/core/MibBigDataLevelMapTest.m` — 9/9 pass; `tests/controllers/AlignmentBigDataTest.m` — 9/9 pass.

---

## 2. Streaming export: chosen pyramid level → standard formats

Export a chosen pyramid **level** of a BigData/Virtual dataset to MIB's ordinary formats, streaming
z-by-z so the full volume is never resident. Backend-neutral (routes through the polymorphic
`MibImage.getData`, never `getDataZarr` directly) so future BioFormats/OpenSlide BigData readers
work unchanged.

**Done:** `BaseSaver.saveStream`/`MibImageSliceProvider` streaming contract; level dropdown UI +
`BatchOpt.PyramidLevel` (image + model); truly streaming TIFF, PNG, JPG, HDF5, `.model`, OME-TIFF
(incl. 5D via the Bio-Formats Java writer); zarr3 registered in the generic Save dialog with true
streaming ingest; units normalization (`utils.normalizeUnits`) unblocking OME-TIFF/TIFF resolution
export of zarr/BigData datasets; BigData **mask** export streams through `MibImageSliceProvider`
at a chosen level.

> **Memory-axis caveat:** SliceProvider streaming bounds memory along **Z** only — a single
> gigapixel WSI plane (Z=1, huge XY) is still held whole; tiled-BigTIFF output for that case is
> the open item below.

**Still open (lower priority):**
1. **Deep per-slice streaming for the remaining savers** — Amira, NRRD, MRC, IMOD `.mod`, STL, and
   the non-`.model` Matlab formats still use the bounded gather-fallback (they delegate to shared
   low-level writers that consume the full array). Per-format notes:
   - NRRD: text header then append raw body per slice (`gzip` via Java `GZIPOutputStream` or two-pass).
   - MRC: 1024-byte header, append slices, patch min/max/mean at close.
   - Amira: ASCII/binary header then append per slice (RLE variant compresses per slice).
   - Matlab `.mask`/`.mibCat`/`.mat`: writable `matfile` partial assignment per slice (confirm
     categorical partial-write for `.mibCat`).
   - IMOD `.mod`: accumulate **contours only** per slice, write at close.
   - STL: 2-slice sliding-window marching cubes (inherently needs neighbours; labels-only, small).
2. **Tiled BigTIFF for gigapixel single planes** — XY-tile-by-tile OME-TIFF write so a full-res WSI
   plane (Z=1) also exports memory-bounded. Breaks the SliceProvider Z-only contract → separate feature.

**Exit gate per format:** export a BigData level streams with peak memory ≈ one slice (array-size
instrumented) and the output round-trips vs a direct level read.

---

## 3. WSI direct reading for BigData (BioFormats / OpenSlide)

Lets a BigData **image layer** read WSI/microscopy files (CZI/NDPI/SVS/…) on demand through the
same `readRegion` seam the zarr3 reader uses — model/mask/selection stay on the zarr3 store.

**Done (headless, pixel-identical across engines on CMU-1.ndpi):** `io.BioFormats.Config`
(`'mib'`|`'matlab'`) + `io.BioFormats.Reader` facade; true pyramid-level reads in the Java backend;
read-seam dispatch by `pyramid.sourceType` (`zarr3`|`bioformats`); reader dropdown
(`Default`|`BioFormats`|`OpenSlide`); MATLAB built-in backends `bioformatsread`/`openslideread` via
lazy `blockedImage`, with OpenSlide→BioFormats fallback for formats libopenslide can't open.

**Deferred:** **Phase E** — `io.converters.WSIToZarr3` (convert a WSI to a zarr3 pyramid via
`Zarr3Saver.saveStream`). Only needed when on-demand reading isn't possible/desirable.

**Open questions** (decide at implementation time): formal `io.loaders.RegionReader` base vs
duck-typed `readRegion`; Java reader lifetime vs blockedImage handle caching per buffer; auditing
any BigData code that hard-codes `'zarr3'`/`Zarr3*` when generalising.

---

## 4. Live (in-GUI) validation — ✅ DONE (2026-06-30)

Confirmed working in the real MIB GUI by the user (File→Open / display / segmentation / save /
export): reader dropdown repopulates correctly per type; Standard baseline unchanged; BigData with
BioFormats (MIB and MATLAB engines) and OpenSlide all open CMU-1.ndpi + assorted CZI files
correctly (pan/zoom/orientation/scenes/channels/LUT); model+segmentation on a WSI BigData set
(brush at any zoom, undo exact, radius-bounded tools, save+reopen intact); Save model 3-way dialog;
export a BigData level → reopen with matching dims/voxel size.

---

## 5. Deferred backlog (prioritised)

1. **`removeMaterial` pixel renumbering on the disk-backed model** — today only the material-name list
   is persisted; on-disk indices are not renumbered.
2. **T>1 (time-series) BigData model** — `MibBigDataLabels` assumes a single time point; `getData4D`
   squeezes singleton dims (grayscale T>1 would misread time as colours).
3. **Whole-volume backup/clear** still materialises a full-res block (fine per-slice/interactive; heavy
   for 3D/4D ops).
4. **Migrate ImageConverter's writer onto `io.zarr`** — **Zarr v3 done (2026-06-30):** when
   `io.zarr.Config` = native and output = Zarr v3, `ImageConverter.generateZarr` routes through
   `ImageConverter.convertToZarr3Native` → new `io.savers.ImageDatastoreSliceProvider` (one file per
   Z-slice) → `Zarr3Saver.saveStream` (shared level/chunk/shard logic, out-of-core) →
   `Zarr3Saver.patchMetadata` (bounding box + voxel size). No Python on that path. **Still open:**
   **Zarr v2** output and the **python backend** keep the legacy Python pipeline (the native
   `io.zarr` writer is v3-only) — migrating v2 needs a native Zarr-v2 writer first.
5. **Remote OME-Zarr over HTTP/URL** - **planned in detail: see [`plan_url_s3.md`](plan_url_s3.md).**
   Metadata over HTTP now works end to end for both versions (verified live against Janelia
   OpenOrganelle), and the NGFF v0.4 / v2 gap noted here was closed by `Zarr2VirtualSetupLoader`.
   What remains: `Import→URL` still uses `imread` and never routes to the zarr loaders; no GUI entry
   feeds a URL to the Virtual/BigData open path; `detectZarrFormatExtension` cannot probe a URL and
   mis-routes v2 stores to the v3 loader; remote group discovery bails out on HTTP; and remote v2
   pixel reads need `aiohttp`/`requests` in the python env. `zarrMex` HTTP Range reads still assume
   Range support (S3 has it) - a whole-chunk GET path for non-Range hosts remains future work.
6. **Interop nicety:** `createStore.writeMultiscales` writes relative factors as the NGFF `scale`; for
   strict OME-NGFF it should write physical voxel sizes. MIB round-trips either way (openStore
   normalises), so cosmetic.
7. **Copy-or-modify image edits** — prompt to modify the underlying zarr in place vs save a Standard
   copy (models never touch the source image).

---

## 6. Documentation — RST docblocks for BigData functions

> **Rule:** whenever a BigData function is added or significantly changed, add or update its
> RST/Sphinx docblock following `development/guides/docs_api_sphinx.md`.

**Done:** `Snapshot.snapshotBtn_Callback`, `MakeMovie.continueBtn_Callback` (BigData pyramid-level
selection, ROI scaling, scale-bar logic), `MibController.initialize` (eager-library-list comment).

**Still open — core BigData pipeline** functions with no (or minimal) docblocks, in priority order:

1. `+core/@MibBigDataImage/MibBigDataImage.m` — constructor + key properties
   (`pyramid`, `levelScaleFactors`, `levelImageSizes`).
2. `+core/@MibBigDataImage/getDataZarr.m` — `options.pyramidLevel` vs `options.magFactor`
   precedence; level-selection formula; `options.blockModeSwitch`.
3. `+core/@MibBigDataImage/getData2D.m` — `resizeToMagnification=false` auto-injection of
   `magFactor=1`; `panModeException` for pyramidal datasets.
4. `+core/@MibBigDataLabels/MibBigDataLabels.m` — constructor, `createStore`, packed-63 layout.
5. `+core/@MibBigDataLabels/getData63.m` / `setData63.m` — chunk coords, bit-packing contract.
6. `+models/@MibModel/getRGBimage.m` — `panModeException=1` branch for pyramidal datasets.

---

## 7. Verification approach (for any change here)

- **MCP** `evaluate_matlab_code` / `run_matlab_file` on the real model (CMU-1.ndpi as BigData), native
  zarr backend: per-level read == reference; level-selected export dims == `pyramid.levelImageSizes(L)`
  and voxel size scaled by `levelScaleFactors(L)`; peak slice memory ≈ one slice; level-map halo == 0;
  capture→undo byte-identical.
- **Static** `mcp__matlab__check_matlab_code` on every changed/new file (pre-existing warnings
  excepted); `buildtool check`.
- **Tests** under `tests/` following existing patterns; keep `MibBigDataLevelMapTest` green.
- **Docs** — update `docs/docs/getting-started/dataset-types/index.md` (user) + RST docblocks (API)
  when public methods/UI land.

> **Shared MCP setup helper** (build a fresh BigData model on CMU-1.ndpi):
> ```matlab
> addpath('C:\Matlab\MIB3\mib'); rehash; io.BioFormats.Config.setLibrary('mib'); io.zarr.Config.setSmoothing(false);
> f='C:\Matlab2\Data\FileFormats\czi\CMU-1.ndpi';
> o0=struct('datasetMode','BigData','readerFamily','BioFormats','silentMode',true,'ParentFigure',[],'mibPath','C:\Matlab\MIB3\mib');
> Ld=io.loaders.BioFormatsVirtualSetupLoader(o0);[mi,fl]=Ld.loadMetadata({f},o0);[img,mi]=Ld.loadImages(fl,mi,o0);
> io_=core.MibBigDataImage(img,mi);
> sp=fullfile(tempdir,'lmtest.zarr3'); if isfolder(sp); rmdir(sp,'s'); end
> lmp=core.MibBigDataLabels.levelMapPathFor(sp); if isfile(lmp); delete(lmp); end
> bm=core.MibImage.initializeImgInfo('pixSize',io_.pixSize,'Height',io_.height,'Width',io_.width,'Depth',io_.depth,'Time',io_.time,'Colors',1);
> lb=core.MibBigDataLabels([],bm); lb.createStore([io_.height,io_.width,io_.depth],sp,io_.pyramid);
> H=lb.height; W=lb.width; N=size(lb.modelScaleFactors,1);
> ```

---

## 8. 3D volume rendering (VolRenApp) for BigData

Render a BigData dataset in the 3D viewer (`+controllers/@VolRenApp/`, MATLAB `viewer3d`/`volshow`)
by loading a chosen **pyramid level** (never the full-res gigapixel volume), and update the model
overlay **live** as the user segments in the main MIB window. BigData only (Virtual stays blocked);
explicit pyramid-level dropdown; live overlay update = auto (debounced) + manual refresh.

**Done (code + headless; static-clean):** gate relaxed for BigData; `grabVolume` pyramid-level
dropdown with per-level memory estimate + `getData3D(...,'pyramidLevel',...)` reads (voxel size
from `pyramid.levelVoxelSizes`, since BioFormats-backed BigData leaves `image.pixSize` empty);
`modelUpdateOverlay` reads the overlay at the same level; live-update engine keyed off `SetData`
listeners on `mibModel` and the active dataset (not `ShowImage`, which fires on every pan/zoom) with
a 0.2 s debounce timer; lifecycle-hardened against a closed VolRenApp window. Test:
`tests/core/MibBigDataVolRenReadTest.m` (3/3).

**Still open / pending live-GUI verification:**
- **App Designer widgets** (binary `.mlapp`, added by the user to `+views/VolRenAppGUI.mlapp`):
  `liveUpdateCheckBox` (Viewer tab) and `refreshViewButton`/`refreshOverlayButton` (Model tab).
  Restart MIB so new widgets + the relaxed gate load.
- **Live test:** open CMU-1.ndpi as BigData → Render → pick a level → renders in µm; create a
  model, brush with Live update on → 3D overlay refreshes within ~0.25 s (incl. selection overlay);
  Refresh view forces a pull; Standard datasets unchanged.
- **Close-path wiring:** confirm `VolRenAppGUI.mlapp`'s `CloseRequestFcn` actually calls the
  controller's `closeWindow` — if not wired, `listener{1..3}` + the child 3D-viewer window +
  preferences-save leak (the defensive guards make live-update safe regardless, but the leak itself
  needs the wiring fixed).

**Deferred — adaptive (view-dependent) detail:** `volshow` has no native streaming/LOD, so loading
finer detail on camera-settle would need a debounced "load on camera-settle" via the existing
`CameraMoving` listener: pick level from zoom/distance, load a memory-budgeted sub-volume centred on
`CameraTarget` via region reads, rebuild `volume.Data`, update the `affinetform3d` translation so
the crop sits at its correct world position, co-fetch the overlay at the same level/region. Needs an
`adaptiveDetailCheckBox` widget.

---

## 9. Audit findings (2026-07-03) — not yet acted on

Design review of the plan vs. the implementation. Architecture is sound; these are the gaps and
headroom items, ranked by impact on **efficient BigData segmentation with as many tools as
possible**. **Nothing here is committed yet — this is the backlog for the next pass.**

### 9.1 Correctness / fragile assumptions

1. **`getData63` is read-*write* (single-threaded by construction) — promote to a first-class
   invariant, document in `bigdata_logic.md` §5/§12.** `materializeForRead` writes upsampled tiles
   to disk **and** mutates the shared `matLevel` array during a *read*. Implications: the read path
   **cannot be `parfor`-parallelised** as-is (races on the store + `matLevel`); a plain **zoom-in on
   an imported model grows the store**; **export before "Finalize & save" mutates the store it
   reads** (works, but undocumented coupling — finalise first for a pure read).
2. **"Latest-edit-wins per tile" can clobber neighbouring fine detail.** `markTiles` rounds the
   changed bbox **up to whole coarsest tiles** (e.g. 256 px). A thin stroke drawn zoomed-out marks
   entire tiles authoritative-at-coarse; the next zoom-in upsamples coarse data over those tiles
   and **overwrites pre-existing fine detail in the untouched margin around the stroke.** Options:
   document the warning, or use a finer `matLevel` grid than the coarsest level.
3. **`removeMaterial` on-disk renumbering (backlog §5.1) is a *correctness* bug, not a nicety** —
   promote above the cosmetic backlog items.
4. SAM v1's BigData block is intentional (performance — SAM2 covers the same modes faster), already
   documented correctly in `bigdata_logic.md` §6; no code change needed, listed here only so it
   isn't mis-filed as a gap during the next audit pass.

### 9.2 Performance headroom

5. **`setData63` footprint-bounding kicks in *after* a full-viewport pass.** It resizes/merges/diffs
   the **whole incoming display block** (`setData63.m:128-135`) before locating the tiny changed
   bbox — per-stroke cost is O(viewport), not O(footprint); a 4k×4k window does ~16M-element
   `imresize`+`merge`+`diff` per stroke regardless of stroke size. Likely the top interactive
   hot-spot on large windows. **Next step:** bound the nearest/diff pass to the display-space bbox
   of the incoming change; profile on CMU-1 via MCP before/after.
6. **No viewport/chunk read cache.** Every `setData63` re-reads `before` from disk; every
   `ShowImage` re-reads the overlay via `getData63`. A small LRU of the current working-level
   viewport would cut round-trips during stroke bursts and pans — minor on NVMe+zstd, significant
   on network/rotational storage.
7. `getDataZarr`'s image resize is a serial per-Z `imresize('nearest')` triple loop — usually
   skipped (level ≈ display mag → resizeFactor≈1); low priority.

### 9.3 Tool coverage — the biggest wins toward the goal

Current: Brush / Spot / Lasso / Rect / Ellipse / Wand / RegionGrow / Drag&Drop / ClickTracker and
**SAM2** (interactive / 3D / landmarks) are ✅ footprint-bounded. Blocked: Graphcut/SLIC, SAM v1
(intentional, §9.1.4), Object Picker / BW-Threshold / SAM-auto (63-material or whole-slice limits).

8. **DeepMIB → BigData model write-back — the highest-value gap.** DeepMIB already predicts
   memory-bounded via `blockedImage` (`processBlocksBlockedImage.m`), but has **no path to write
   predictions into the disk-backed `MibBigDataLabels` model** — it targets files, not the live
   BigData model. What's missing is a sink that streams per-block output into the model via
   `setData63('everything', …, pyramidLevel=1, x/y/z=block)` + `materializeAll` — the exact pattern
   `MibDataset.cropToBigData` already uses. This would let a user train on a WSI region and predict
   the whole slide straight into the live model. **Rank above alignment** for the segmentation goal.
9. **Graphcut/SLIC on BigData** — never designed for tiled/pyramidal data; would need a bounded-region
   (ROI/viewport) variant. Lower priority than DeepMIB.

### 9.4 Alignment plan — one soft spot

10. **The "full-resolution stack never resident in RAM" claim is Z-bounded only.**
    `AlignedImageSliceProvider.getSlice` reads a full level-0 slice and `imwarp`s it **whole** — for
    serial sections at, e.g., 20k×20k×RGB that is ~1.2 GB/slice + the output canvas. Same
    memory-axis caveat §2 already documents for export. Before pushing this further: cap per-slice
    size and note tiled warp as the escape hatch for very large sections.
