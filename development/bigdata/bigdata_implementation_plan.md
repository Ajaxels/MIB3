# BigData — implementation status & remaining work

Companion to `bigdata_logic.md` (how it works). This is the **roadmap**: what is complete, what is
still open, and the concrete next steps. **No git commits** (project rule: edit local files only).
Every change ends with `check_matlab_code` clean + an MCP verification snippet on the real model
(`C:\Matlab2\Data\FileFormats\czi\CMU-1.ndpi` opened as BigData).

> Consolidated 2026-06-25 from `plan_bigdata.md`, `bigdata_levelmap_spec.md`,
> `bigdata_levelmap_plan.md`, `bigdata_brush_performance.md`, `plan_wsi_readers.md`,
> `wsi_livetest_checklist.md`. Those remain as the dated detail log.

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
| **Alignment for BigData** (new-store output + buffer swap): drift, feature-v2 affine, landmarks (annotation-driven), packed-63 warp | ✅ DONE (headless + e2e; plan `alignment_plan.md`, logic `bigdata_logic.md §13`); AppDesigner panel + live-GUI acceptance pending |
| Streaming export plan — remaining per-format deep streaming + mask path | ⏳ OPEN (see §3) |
| Backlog (T>1, removeMaterial renumber, remote zarr, etc.) | ⏳ DEFERRED (see §5) |

Tests: `tests/core/MibBigDataLevelMapTest.m` — 9/9 pass; `tests/controllers/AlignmentBigDataTest.m` — 9/9 pass.

---

## 2. Streaming export: chosen pyramid level → standard formats (the active plan)

Export a chosen pyramid **level** of a BigData/Virtual dataset to MIB's ordinary formats, **streaming
z-by-z** so the full volume is never resident. Backend-neutral (routes through the polymorphic
`MibImage.getData`, never `getDataZarr` directly) so future BioFormats/OpenSlide BigData readers work
unchanged. User decisions: explicit level dropdown; per-slice streaming; **all** formats stream
eventually.

**Architecture (DONE):** `BaseSaver.saveStream(provider, metadata, filename, options)` is the per-slice
primitive; `save(data,…)` is a wrapper over `InMemorySliceProvider` so unmigrated savers still work
(bounded by the *selected level*). `MibImageSliceProvider` reads one slice via
`src.getData(layerType, 3, col, opt)` with `opt.pyramidLevel` + `opt.z`. **Coordinate gotcha:**
`getData` reads `options.z` in **full-res** coords and divides by the level Z-scale, so the provider
maps level-slice `k` → full-res `z=(k-1)*zScale+1`.

**Done:** Phases 1–4 — providers + streaming contract; level dropdown UI + `BatchOpt.PyramidLevel`
(image + model); truly streaming **TIFF, PNG, JPG, HDF5, `.model`, OME-TIFF**; zarr3 registered in the
generic Save dialog with true streaming ingest + settings dialog (auto-levels description, sharding).

**Done (2026-06-30) — OME-TIFF streaming + units fix + BigData mask:**
- **Units normalization** — new `utils.normalizeUnits` maps long OME spellings (`'micrometers'`,
  `'nanometers'`, …) to MIB's short codes; wired into `utils.calculateResolution` **and**
  `io.BioFormats.mibImage2ometiff` (whose two `switch` blocks had **no `otherwise`** → a zarr/BigData
  dataset with `units='micrometers'` *errored* on an undefined `scaleFactor`, not merely fell back to
  72 dpi). This unblocks correct OME-TIFF / TIFF-resolution export of every zarr/BigData dataset.
  Tests: `tests/utils/PureUtilsTest` (units cases).
- **`OmeTiffSaver.saveStream`** — true streaming override. **5D**: builds OME-XML from provider
  dimensions (`MetadataTools.populateMetadata`, no full array) and writes planes in XYCZT order via the
  Bio-Formats Java writer (`OMETiffWriter.saveBytes`), one `[H W C]` slice pulled per `(z,t)`. **2D
  sequence**: one `.ome.tiff` per Z×T slice. Peak memory ≈ one XY plane. Tests:
  `tests/io/OmeTiffStreamTest` (5D round-trip, stream==gather, multichannel Z/C order, 2D sequence).
- **BigData mask export** — `MibDataset.saveImage` `'mask'` branch streams a pyramidal (`MibBigDataLabels`)
  mask through `MibImageSliceProvider(obj.labels,'mask',level,…)` at a chosen `PyramidLevel` (pixSize
  scaled per level), instead of `getData3D('mask')`. Standard datasets keep the gather path. Tests:
  `tests/core/BigDataMaskStreamTest`; `SaveLoadMaskTest` (Standard, no regression).

> **Memory-axis caveat:** SliceProvider streaming bounds memory along **Z** — a real win for tall 3-D
> stacks. A single gigapixel WSI plane (Z=1, huge XY) is still held whole; tiled-BigTIFF output for that
> case is deferred (see below).

**Still open (lower priority):**
1. **Deep per-slice streaming for the remaining savers** — Amira, NRRD, MRC, IMOD `.mod`, STL, and the
   non-`.model` Matlab formats still use the bounded gather-fallback (they delegate to shared low-level
   writers that consume the full array). Per-format notes:
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

Lets a BigData **image layer** read WSI/microscopy files (CZI/NDPI/SVS/…) on demand through the same
`readRegion` seam the zarr3 reader uses — the model/mask/selection stay on the zarr3 store. Source
image is read-only, so no need to duplicate gigapixel pixels into a second zarr3 copy.

**Done (headless, all via MCP, pixel-identical across engines on CMU-1.ndpi):**
- **Phase A** — `io.BioFormats.Config` (`'mib'`|`'matlab'`, default `'mib'`) + preference
  `IO.BioFormats.Library` + `io.BioFormats.Reader` facade; Preferences UI dropdown wired.
- **Phase B** — true pyramid-level reads in the Java backend (`setFlattenedResolutions(false)` +
  `setResolution` + level-local `bfGetPlane`); `pyramidStruct`; associated-image (macro/label) guard.
- **Phase C** — read seam dispatches by `pyramid.sourceType` (`zarr3`|`bioformats`); reader **dropdown**
  (`Default`|`BioFormats`|`OpenSlide`) replacing the old checkbox; open path (registry WSI extensions,
  `LoaderFactory` routing, BigData setup-loader branch: single-scene auto / multi-scene dialog, OME
  voxel size, LUT colours).
- **Phase D** — MATLAB built-in backends `bioformatsread` / `openslideread` via lazy `blockedImage`
  `getRegion`; dimension-aware (Z/C/T from Java metadata) so non-WSI volumes read correctly;
  OpenSlide→BioFormats fallback for formats libopenslide can't open.

**Deferred:** **Phase E** — `io.converters.WSIToZarr3` (convert a WSI to a zarr3 pyramid via
`Zarr3Saver.saveStream`). Only needed when on-demand reading isn't possible/desirable.

**Open questions** (decide at implementation time): formal `io.loaders.RegionReader` base vs duck-typed
`readRegion`; Java reader lifetime vs blockedImage handle caching per buffer; auditing any BigData code
that hard-codes `'zarr3'`/`Zarr3*` when generalising.

---

## 4. Live (in-GUI) validation — ✅ DONE (2026-06-30)

Confirmed working in the real MIB GUI by the user (File→Open / display / segmentation / save / export).
Full matrix in the (now-superseded) `wsi_livetest_checklist.md`.

- [x] Reader dropdown `Default | BioFormats | OpenSlide` repopulates the file filter per type, no
      crash (incl. the former BigData+BioFormats `.Items` crash); each reader remembers its filter.
- [x] **Standard** baseline unchanged (CZI channel colours correct; plain TIFF opens).
- [x] **BigData / BioFormats engine = MIB**: CMU-1.ndpi auto-loads; pan/zoom switches levels;
      orientation XY/ZX/ZY renders; Zeiss-5-JXR.czi shows the scene dialog; Clim_10BDE_5.czi (Z=111,
      C=4) scrolls Z with correct colours; DMSO LUT colours correct.
- [x] **BigData / BioFormats engine = MATLAB**: CMU-1.ndpi identical; Clim Z-scroll + 4 channels OK.
- [x] **BigData / OpenSlide**: CMU-1.ndpi opens (9 levels); CZI falls back to BioFormats; a real `.svs`.
- [x] **Model + segmentation on a WSI BigData set**: Create Model → disk-backed
      store beside the slide; brush at high zoom → Ctrl+Z restores exactly; brush zoomed-out → edit
      lands in the right place; Magic Wand/Region Growing radius stays bounded; save model + reopen →
      labels intact.
- [x] **Save model dialog** (3-way Finalize/Sidecar/Cancel) + Help button on a real CMU-1 model;
      sidecar-only save writes `Labels_CMU-1.levelmap` and a reopen restores precisely.
- [x] **Export** a BigData WSI level → TIFF/HDF5 → reopen → dims match the chosen level; voxel scaled.

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
   `Zarr3Saver.patchMetadata` (bounding box + voxel size). No Python on that path (the `pyenv` init in
   `Convert` is skipped). Test: `tests/io/ImageConverterNativeZarrTest` (pixels + dims + voxel +
   mibBoundingBox round-trip), `tests/io/ImageDatastoreSliceProviderTest`. **Still open:** **Zarr v2**
   output and the **python backend** keep the legacy Python pipeline (the native `io.zarr` writer is
   v3-only) — migrating v2 needs a native Zarr-v2 writer first.
5. **Remote OME-Zarr over HTTP/URL** — metadata + native reads work in principle, but: `Import→URL`
   uses `imread` (never routes to the zarr loader); no GUI entry feeds a URL to the Virtual/BigData open
   path; `zarrMex` HTTP Range reads fail on servers without Range support; v3-only engine can't read
   NGFF v0.4 (v2). Future work: an "Open OME-Zarr from URL" entry → `Zarr3VirtualSetupLoader`; a
   whole-chunk GET path for non-Range hosts; an optional Zarr v2 read path.
6. **Interop nicety:** `createStore.writeMultiscales` writes relative factors as the NGFF `scale`; for
   strict OME-NGFF it should write physical voxel sizes. MIB round-trips either way (openStore
   normalises), so cosmetic.
7. **Copy-or-modify image edits** — prompt to modify the underlying zarr in place vs save a Standard
   copy (models never touch the source image).

---

## 6. Documentation — RST docblocks for BigData functions

> **Rule:** whenever a BigData function is added or significantly changed, add or update its
> RST/Sphinx docblock following `development/docs_api_sphinx.md`.

### Done (session 2026-06-26)

- `+controllers/@Snapshot/snapshotBtn_Callback` — full RST docblock covering BigData pyramid-level
  selection (ShownArea / FullImage / ROI), ROI bounding-box scaling, and scale-bar correction logic.
- `+controllers/@MakeMovie/continueBtn_Callback` — same; also documents ``bigDataRoiBB`` pattern
  and the cached scale-bar strip optimisation.
- `+controllers/@MibController/initialize.m` — added comment explaining why `imageselection` is
  in the eager library list (``javaaddpath`` silently blocked after BioFormats Memoizer creation).

### Pending — core BigData pipeline

These functions implement the core read / write / display path and currently have no (or
minimal Doxygen) docblocks.  Document them in priority order:

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

Render a BigData dataset in the 3D viewer (`mib/+controllers/@VolRenApp/`, MATLAB
`viewer3d`/`volshow`) by loading a chosen **pyramid level** (never the full-res gigapixel
volume), and update the model overlay **live** as the user segments in the main MIB window.
Previously the controller hard-blocked Virtual **and** BigData.

**Decisions:** BigData only (Virtual stays blocked); explicit **pyramid-level dropdown** for
resolution; live overlay update = **auto (debounced) + manual** refresh.

### Done (code + headless; static-clean)

- **Gate** (`VolRenApp.m` constructor) — rejects only Virtual (`'V'`); BigData (`'B'`) passes.
- **`grabVolume`** — for BigData shows a **pyramid-level dropdown** built from
  `image.pyramid.levelImageSizes` with a per-level memory estimate (default = finest level under
  a 512 MB budget); stores the choice in new property `obj.pyramidLevel`. Reads via
  `getData3D(..., options)` with `options.pyramidLevel` + `options.blockModeSwitch = 0`; forces
  `obj.volumeScaleFactor = 1` (the pyramid already downsamples — no `resizeImage3d`). **Voxel
  size** comes from `image.pyramid.levelVoxelSizes` (`[y x z]`) — per-level row if present, else
  base row × `levelScaleFactors(L,:)` — because **BioFormats-backed BigData leaves
  `image.pixSize` empty** (voxel sizes live only in the pyramid). Standard datasets keep the
  original downsample-factor dialog unchanged.
- **`modelUpdateOverlay`** — reads the overlay at `obj.pyramidLevel` (same options), with a
  nearest-neighbour `imresize3` fallback if overlay dims differ from the image volume.
- **Live update engine** — new props `overlayMaterialId`, `liveUpdateListener` (cell),
  `liveUpdateTimer`, `liveUpdatePending`; methods `refreshOverlay`, `toggleLiveUpdate`,
  `enable/disableLiveUpdate`, `liveUpdateRequest`, `liveUpdateFire`, `stopLiveUpdateTimer`,
  `refreshOverlayData`.
  - **Event hookup — `SetData`, not `ShowImage`.** `ShowImage` fires on every pan/zoom/slice
    change → needless refetches, so it is **not** used. Two `SetData` listeners cover all edits:
    `SetData` on **`mibModel`** (fired by `MibModel.moveLayers` — add/subtract to model) and
    `SetData` on the **active dataset** `mibModel.I{id}` (fired by the core
    `MibDataset.setData2D/3D/4D`, gated by `event.hasListener` so it costs nothing when nobody
    listens). The dataset-level listener is what catches a **brush selection** commit: the
    `MibModel.setData2D` wrapper's notify is commented out, and the brush paints `CData` directly
    with no `ShowImage`, so the core dataset `SetData` is the only reliable signal.
  - **Debounced** via a one-shot 0.2 s timer (a burst of strokes collapses into one refetch).
  - `refreshOverlayData` is the **lightweight** path (updates only `OverlayData`, preserving
    per-material visibility/colormap/table); `refreshOverlay` (manual button) does a full
    `modelUpdateOverlay` on first use, then lightweight refreshes.
  - **Lifecycle hardening:** the listeners live on the persistent `mibModel`, so they can outlive
    a closed VolRenApp window. Guards use `~isvalid(obj.view)` (note: a *deleted* handle is **not**
    empty, so `isempty(obj.view)` is insufficient) and self-call `disableLiveUpdate()` when the
    view is gone; a `delete(obj)` destructor also releases listeners/timer. `closeWindow` calls
    `disableLiveUpdate`.
- **Docs** — user page `docs/docs/user-interface/ribbon/home/home-mib3Dviewer.md` (Live update +
  Refresh view widgets); RST docblocks on `grabVolume`, `modelUpdateOverlay`, and the new methods.
- **Headless test** — `tests/core/MibBigDataVolRenReadTest.m` (3/3 pass): image/labels reads at a
  level match `levelImageSizes(L)`; voxel-size scaling increases with level. `MibBigDataLevelMapTest`
  stays 9/9.

### Pending / to verify in live GUI

- **App Designer widgets** (binary `.mlapp`, added by the user in App Designer to
  `mib/+views/VolRenAppGUI.mlapp`): `liveUpdateCheckBox` (CheckBox → `toggleLiveUpdate()`, Viewer
  tab) and `refreshViewButton`/`refreshOverlayButton` (Button → `refreshOverlay()`, Model tab).
  Restart MIB so new widgets + the relaxed gate load.
- **Live test:** open CMU-1.ndpi as BigData → Render → pick a level → renders in µm; create a
  model, brush with Live update on → 3D overlay refreshes within ~0.25 s (incl. **selection**
  overlay); Refresh view forces a pull; Standard datasets unchanged.
- **Close-path wiring:** confirm `VolRenAppGUI.mlapp`'s `CloseRequestFcn` actually calls the
  controller's `closeWindow` — the orphaned-listener symptom suggests it may not, which would also
  leak `listener{1..3}`, the child 3D-viewer window, and the preferences save. The defensive
  guards above make the live-update feature safe regardless, but wiring `closeWindow` fixes the
  broader leak.

### Deferred — adaptive (view-dependent) detail

Optional follow-up: load finer detail when the camera settles. `volshow` renders one resident
array (no native streaming/LOD), so this must be a **debounced "load on camera-settle"** via the
existing `CameraMoving` listener — not continuous tracking. Heuristic: pick level from
`viewer.CameraZoom`/distance, load a **memory-budgeted** sub-volume centred on
`viewer.CameraTarget` via region reads (`pyramidLevel` + `x/y/z`), rebuild `volume.Data`, and
update the `affinetform3d` **translation** so the crop sits at its correct world position;
co-fetch the overlay at the same level/region. Needs an `adaptiveDetailCheckBox` widget. A
frustum-accurate bbox mapping is a later refinement over the centred-budget heuristic.

### Files

`+controllers/@VolRenApp/VolRenApp.m` (gate, `grabVolume`, `modelUpdateOverlay`, live-update
engine, `closeWindow`, `delete`); `+views/VolRenAppGUI.mlapp` (widgets — user/App Designer);
`docs/docs/user-interface/ribbon/home/home-mib3Dviewer.md`; `tests/core/MibBigDataVolRenReadTest.m`.

---

## 9. Audit findings (2026-07-03) — assumptions, performance, tool coverage

Design review of the plan vs. the implementation. The architecture is sound; these are the gaps and
headroom items, ranked by impact on **efficient BigData segmentation with as many tools as possible**.
Nothing here is committed yet — this is the backlog for the next pass.

### 9.1 Correctness / fragile assumptions

1. **`getData63` is read-*write* (single-threaded by construction) — promote to a first-class invariant.**
   `getData63.m:105` → `materializeForRead` (`MibBigDataLabels.m:462-506`) writes upsampled tiles to
   disk **and** mutates the shared `matLevel` array during a *read*. Implications the docs never state:
   - The read path **cannot be `parfor`-parallelised** as-is (races on the zarr store + `matLevel`).
     Any future speed-up of export / DeepMIB prediction / 3D-render fetches must account for this.
   - A plain **zoom-in on an imported model grows the store** (browsing materialises finer tiles).
   - **Export before "Finalize & save" mutates the store it reads** (`MibImageSliceProvider` →
     `getData63`). Works, but the coupling is undocumented — finalise first for a pure read.
   → Add this to `bigdata_logic.md` §5/§12 as an explicit invariant.

2. **"Latest-edit-wins per tile" can clobber neighbouring fine detail.** `markTiles` rounds the changed
   bbox **up to whole coarsest tiles** (`tilesForFullRegion`, `ceil`, tile = `sfN` full-res px, e.g.
   256). A thin stroke drawn zoomed-out marks entire 256-px tiles authoritative-at-coarse; the next
   zoom-in upsamples coarse data over those tiles and **overwrites pre-existing fine detail in the
   up-to-256-px margin around the stroke the user never touched.** Framed as intended in the docs, but
   the data-loss risk on mixed-zoom workflows is not warned about. Options: document the warning, or use
   a finer `matLevel` grid than the coarsest level.

3. **`removeMaterial` on-disk renumbering (backlog §5.1) is a *correctness* bug, not a nicety.** Deleting
   a material persists only the name list; on-disk packed indices are not renumbered, so remaining
   materials visibly remap on reload. Promote above the cosmetic backlog items.

4. **SAM v1 BigData block is intentional (performance), not a gap** — SAM2 covers the same interactive/
   landmark modes faster. Doc wording in `bigdata_logic.md` §6 tightened (2026-07-03) so it is not
   mis-filed as missing coverage. No code change needed.

### 9.2 Performance headroom

5. **`setData63` footprint-bounding kicks in *after* a full-viewport pass.** It resizes the whole
   incoming display block (`resizeBlockNearest(dataset, wSize)`, `setData63.m:128`), merges, and diffs
   over the entire viewport (`:129-135`) **before** locating the tiny changed bbox. Per-stroke cost is
   **O(viewport), not O(footprint)** — a 4k×4k window does ~16M-element `imresize`+`merge`+`diff` on
   every stroke regardless of stroke size. Likely the top interactive hot-spot on large windows.
   **Next step:** bound the nearest/diff pass to the display-space bbox of the incoming change; profile
   on CMU-1 via MCP before/after.

6. **No viewport/chunk read cache.** Every `setData63` re-reads `before` from disk
   (`readPackedLevel`, `setData63.m:113`); every `ShowImage` re-reads the overlay via `getData63`.
   `io.zarr.Array` caches only the python handle, not tiles (`Array.m:41-43`). A small LRU of the
   current working-level viewport would cut round-trips during stroke bursts and pans — minor on
   NVMe+zstd, significant on network/rotational storage.

7. **`getDataZarr` image resize is a serial per-Z `imresize('nearest')` triple loop**
   (`getDataZarr.m:202-208`). Usually skipped (level ≈ display mag → `resizeFactor≈1`); low priority.

### 9.3 Tool coverage — the biggest wins toward the goal

Current: Brush / Spot / Lasso / Rect / Ellipse / Wand / RegionGrow / Drag&Drop / ClickTracker and
**SAM2** (interactive / 3D / landmarks) are ✅ footprint-bounded. Blocked: Graphcut/SLIC
(`Graphcut.m:122`), SAM v1 (intentional, §9.1.4), Object Picker / BW-Threshold / SAM-auto (63-material
or whole-slice limits), Alignment (planned — `alignment_plan.md`).

8. **DeepMIB → BigData model write-back — the highest-value gap.** DeepMIB
   (`@MibDeep/processBlocksBlockedImage.m`, `startPredictionBlockedImage.m`) already predicts
   memory-bounded via `blockedImage`, but has **no path to write predictions into the disk-backed
   `MibBigDataLabels` model** — it targets files, not the live BigData model. The compute half is solved;
   what's missing is a sink that streams per-block output into the model via
   `setData63('everything', …, pyramidLevel=1, x/y/z=block)` + `materializeAll` — the exact pattern
   `MibDataset.cropToBigData` already uses. This would let a user train on a WSI region and predict the
   whole slide straight into the live model. **Rank above alignment** for the segmentation goal.

9. **Graphcut/SLIC on BigData** — never designed for tiled/pyramidal data; would need a bounded-region
   (ROI/viewport) variant. Lower priority than DeepMIB.

### 9.4 Alignment plan (`alignment_plan.md`) — one soft spot before Phase 1

10. **The "full-resolution stack never resident in RAM" claim is Z-bounded only.**
    `AlignedImageSliceProvider.getSlice` reads a full level-0 slice and `imwarp`s it **whole** (Phase 1,
    §4). Bounded along Z, but **each slice is the entire XY plane** — for serial sections at, e.g.,
    20k×20k×RGB that is ~1.2 GB/slice + the output canvas. This is the same memory-axis caveat the
    streaming-export plan already documents (§2 "Memory-axis caveat"), but the alignment plan repeats
    "never resident." **Before implementing Phase 1:** inherit that caveat explicitly, cap per-slice
    size, and note tiled warp as the escape hatch for very large sections.
