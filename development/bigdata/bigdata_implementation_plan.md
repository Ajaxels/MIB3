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
| **Live in-GUI validation** of WSI open + segmentation + export | ⏳ PENDING (see §4) |
| Streaming export plan — remaining per-format deep streaming + mask path | ⏳ OPEN (see §3) |
| Backlog (T>1, removeMaterial renumber, remote zarr, etc.) | ⏳ DEFERRED (see §5) |

Tests: `tests/core/MibBigDataLevelMapTest.m` — 9/9 pass.

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
(image + model); truly streaming **TIFF, PNG, JPG, HDF5, `.model`**; zarr3 registered in the generic
Save dialog with true streaming ingest + settings dialog (auto-levels description, sharding).

**Still open (lower priority):**
1. **Deep per-slice streaming for the remaining savers** — OME-TIFF, Amira, NRRD, MRC, IMOD `.mod`,
   STL, and the non-`.model` Matlab formats currently use the bounded gather-fallback (they delegate to
   shared low-level writers that consume the full array). Per-format notes:
   - OME-TIFF: incremental plane writes via `bfsave` per-plane or raw `Tiff` + hand-written OME-XML.
   - NRRD: text header then append raw body per slice (`gzip` via Java `GZIPOutputStream` or two-pass).
   - MRC: 1024-byte header, append slices, patch min/max/mean at close.
   - Amira: ASCII/binary header then append per slice (RLE variant compresses per slice).
   - Matlab `.mask`/`.mibCat`/`.mat`: writable `matfile` partial assignment per slice (confirm
     categorical partial-write for `.mibCat`).
   - IMOD `.mod`: accumulate **contours only** per slice, write at close.
   - STL: 2-slice sliding-window marching cubes (inherently needs neighbours; labels-only, small).
2. **Mask export of BigData** — `MibDataset.saveImage` `'mask'` branch still does `getData3D('mask')`
   (full level-0 load); give it the provider too. Low priority (mask lives in packed bit 7).
3. **`'micrometers'` units alias** in `utils.calculateResolution` (zarr datasets carry
   `pixSize.units='micrometers'`, unmapped → TIFF Resolution tag falls back to 72 dpi; voxel size still
   round-trips via the BoundingBox tag). One-line shared fix, helps all zarr saves.

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

## 4. Pending live (in-GUI) validation

Headless MCP paths pass; these confirm the real File→Open / display / segmentation / export flow.
Full matrix in the (now-superseded) `wsi_livetest_checklist.md`. **Restart MIB first** — registry
extension sets, the reader dropdown keys and the 3-slot file filter load at start-up.

- [ ] Reader dropdown `Default | BioFormats | OpenSlide` repopulates the file filter per type, no
      crash (incl. the former BigData+BioFormats `.Items` crash); each reader remembers its filter.
- [ ] **Standard** baseline unchanged (CZI channel colours correct; plain TIFF opens).
- [ ] **BigData / BioFormats engine = MIB**: CMU-1.ndpi auto-loads; pan/zoom switches levels;
      orientation XY/ZX/ZY renders; Zeiss-5-JXR.czi shows the scene dialog; Clim_10BDE_5.czi (Z=111,
      C=4) scrolls Z with correct colours; DMSO LUT colours correct.
- [ ] **BigData / BioFormats engine = MATLAB**: CMU-1.ndpi identical; Clim Z-scroll + 4 channels OK.
- [ ] **BigData / OpenSlide**: CMU-1.ndpi opens (9 levels); CZI falls back to BioFormats; a real `.svs`.
- [ ] **Model + segmentation on a WSI BigData set** (key unproven area): Create Model → disk-backed
      store beside the slide; brush at high zoom → Ctrl+Z restores exactly; brush zoomed-out → edit
      lands in the right place; Magic Wand/Region Growing radius stays bounded; save model + reopen →
      labels intact.
- [ ] **Save model dialog** (3-way Finalize/Sidecar/Cancel) + Help button on a real CMU-1 model; verify
      sidecar-only save writes `Labels_CMU-1.levelmap` and a reopen restores precisely.
- [ ] **Export** a BigData WSI level → TIFF/HDF5 → reopen → dims match the chosen level; voxel scaled.

Report per failure: file, dataset type, reader, BioFormats library, the DeveloperMode
`[type/reader/engine]` console line, and the full error stack.

---

## 5. Deferred backlog (prioritised)

1. **`removeMaterial` pixel renumbering on the disk-backed model** — today only the material-name list
   is persisted; on-disk indices are not renumbered.
2. **T>1 (time-series) BigData model** — `MibBigDataLabels` assumes a single time point; `getData4D`
   squeezes singleton dims (grayscale T>1 would misread time as colours).
3. **Whole-volume backup/clear** still materialises a full-res block (fine per-slice/interactive; heavy
   for 3D/4D ops).
4. **Migrate ImageConverter's writer onto `io.zarr`** — `ImageConverter.generateZarr` is still its own
   Python pipeline (Zarr v2/v3, sharding, out-of-core z-chunk streaming). Blockers: the native `io.zarr`
   writer needs out-of-core streaming + Zarr v2 + sharding before switching. Until then ImageConverter
   (batch file→zarr) and Zarr3Saver (in-app dataset→BigData) coexist by scope.
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
