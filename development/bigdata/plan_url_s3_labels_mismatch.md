# Plan: label pyramids that do not match the image - honest dataset mode, and a view-only BigData overlay

**Status:** Stages A, B, C and D done. Written 2026-09-17, D landed 2026-09-18. What remains is the
manual in-a-running-MIB checklist under [Verification](#verification), most of which no offline test
can reach.

> **A2/A3 were pulled forward** from their planned position after Stage C. Reported from the GUI:
> with `Dataset mode = BigData` selected, Open went straight to the instance question - asking how
> to handle objects for a buffer the user had not agreed to, in a mode that was about to be
> overridden anyway - and no level selector appeared at all. Doing A2 first makes the flow honest
> immediately; the refusal wording will need one revision when Stage C makes BigData a real answer
> rather than an impossible one.
**Follows on from** [`plan_url_s3.md`](plan_url_s3.md) step 21, which paired a coarse label pyramid
with its image but delivered the result as an in-memory Standard dataset. This plan covers what that
step got wrong and the BigData path it did not attempt.

## Context

Opening `recon-1/labels/inference/segmentations/nuc` from a Janelia container currently produces the
wrong *shape* of result. `jrc_mus-kidney`'s EM has 12 pyramid levels from 8 nm; `nuc` has 5 starting
at 128 nm, which is the EM's `s4`. Step 21 taught the crop route to pair those levels, but that route
reads everything into memory: the buffer silently became **Standard, 505 MB at 128 nm**, while the
Datasets panel still said BigData, and the override note called a whole volume "a crop".

Two problems, and they are different in kind:

1. **The dataset mode is dishonest.** `Dataset mode` is silently overridden, the panel shows the old
   value, and the message describes something that did not happen. This time it fitted in RAM; a
   larger store would be refused only after the user committed.
2. **The wanted behaviour does not exist.** The goal is to browse the EM as **BigData at 8 nm** with
   the labels rendered per slice as they are read - matching pyramid levels served directly, missing
   fine levels upsampled from the finest label level, nothing bulk-downloaded. Instance
   segmentations need a single-material rendering option because MIB's BigData label class is the
   packed 63-material scheme and cannot hold object ids.

### Decisions taken

- **Mode mismatch refuses and instructs.** Open stays disabled and the info panel says to set
  `Dataset mode = Standard` and try again. `ensureDatasetMode`'s silent override is removed, so the
  control always means what it says and there is no hidden special case left to document.
- **Instances render as a single material by default**, with per-object as an opt-in.
  *Reversed when Stage D landed* - see "What Stage D actually changed".
- **Both routes are kept.** Standard = an editable in-memory copy (the right thing for a ground-truth
  crop, since remote label stores are read-only). BigData = the view-only overlay. `Dataset mode`
  selects between them.

---

## What the research settled

These are the findings that shape the design; each removes a design option or a risk.

| Finding | Consequence |
|---|---|
| `MibImage.getData:66` dispatches to `getData63` on `isa(obj,'core.MibLabels63')`; otherwise it reads the in-memory `obj.data` | The new class **must override `getData`**, or a disk-backed layer returns empty. It must **not** subclass `MibLabels63`, or every `isa` branch in the codebase fires wrongly. |
| `MibDataset.getData2D:101` gates the zero-copy fast path on `datasetType == 'Standard'` | A BigData buffer never reaches it. No action needed. |
| Compositing is `labeloverlay(img, M, 'Colormap', materialColors)` at `getRGBimage.m:454` - O(pixels), not O(materials) | 864 materials repaint at the same cost as 8. Per-object rendering is viable. |
| `getRGBimage.m:426-436` (`ShowAsContours` + `ThicknessRendering='quality'`) is one `imerode` **per material**, and is already broken above 255 (`M2`/`M3` hardcoded `uint8` at `:429,:431`; `numel(sList)==2`) | Gate that branch on `maxMaterials < 256`. Default for labels is `ShowAsContours=false`, so this is a latent bug being closed, not a regression. |
| A coherent >255 convention already exists: 2-row materials table (`updateMaterialsTable.m:81-83,114-135`), material index carried **in the name string** and parsed by `getSelectedMaterialIndex`, `rand(65535,3)` cyclic palette (`createModel.m:175-177`) | The new layer **joins the existing convention**. No new Segmentation-panel UI. |
| Instance models already live in the `MibLabels` 65535/4294967295 family (`InstanceEditor`, `stitchModelInstances.m:95`, `startPredictionInstances.m:306-308` - "never type 63/255") | The new class belongs under `core.MibLabels`, alongside them. |
| `buildInstanceIndex.m:89-90` reads the whole labels volume via `getData3D` | Must be blocked for this layer. |
| `openBtn_Callback.m:140-156` already syncs `Sets.datasetTypes` + notifies `DatasetsPanelUpdate`, with the reasoning in a comment; `ensureDatasetMode` does not | The stale panel is exactly this block missing on the crop path. Move it **into** `ensureDatasetMode` (two real call sites). |

---

## Stage A - make the dataset mode honest

Independent of everything else, and worth landing first because the override becomes actively wrong
once BigData is a real option.

**A1. Sync the Datasets panel.** Move the `Sets.datasetTypes` write plus the
`notify(obj.mibModel, 'DatasetsPanelUpdate')` from `@SelectFromUrl/openBtn_Callback.m:148-156` into
`@SelectFromUrl/ensureDatasetMode.m`, after the successful `switchDatasetMode`. Two call sites
(`openBtn_Callback` image branch, `openLabelCrop`), so it earns the move. Keep the existing comment -
it already explains that the dropdown reads the cache, not `I{id}.datasetType`, and that `NewDataset`
repaints it only on a set change.

**A2. Remove the silent override.** Delete the `ensureDatasetMode(datasetId, 'Standard')` call and
the `modeNote` from `@SelectFromUrl/openLabelCrop.m`. `resolveLabelRoute` instead refuses when the
route needs a mode the user has not chosen:

```
Cannot load as Labels in BigData mode.
These labels start at 128 nm while the image goes to 8 nm, so they cannot be
attached to the full-resolution pyramid.
Set Dataset mode = Standard and press Open to read the matching region into memory.
```

After Stage C this message becomes conditional: BigData is refused only when the overlay route is
also unavailable (no integer level offset, or world boxes disagree).

**A3. Ask which level.** The level is currently forced by the pairing (`cropPlan.imageLevel` ->
`loadOptions.ZarrLevel`). Replace with a picker over **valid pairs only** - image levels that have a
matching label level. For `jrc_mus-kidney` that is EM `s4..s8`; `s0..s3` have no counterpart and must
not be offered.

Use `utils.dlgs.inputUniversalDlg` mirroring the existing level dialog at
`Zarr2VirtualSetupLoader.loadImagesStandardV2:557-583`. `SelectFromUrlGUI.mlapp` is an App Designer
binary that cannot be authored as text, so this is a runtime dialog, not a canvas widget - same
constraint that left `ImageGroupPath` batch-only. Each row shows level name, voxel size, dimensions
and **the memory it will cost**, computed from `cropPlan.requiredBytes` arithmetic already in
`planLabelCrop.m:129-133`. A batch protocol sets `ZarrLevel` and never sees the dialog.

**Files:** `@SelectFromUrl/ensureDatasetMode.m`, `openBtn_Callback.m`, `openLabelCrop.m`,
`SelectFromUrl.m` (`resolveLabelRoute`), `planLabelCrop.m` (return all valid pairs, not just the
finest).

---

## Stage B - register the label pyramid against the image's scale space

The shared prerequisite. Today `MibBigDataLabelsZarr2.openStore:210-218` normalises
`modelScaleFactors` against the **label store's own level 0**, giving `[1 2 4 8]` where the image's
magnification space runs `[1 2 4 ... 4096]`. That is a silent 16x scale error - the failure
[`plan_url_s3.md`](plan_url_s3.md) already calls "worse than a hard failure".

Registration takes the image's level-0 voxel size (available from the open dataset's `pixSize`, and
from `readGroupPyramid().levelVoxelSizesXYZ` for the candidate image group) and expresses every label
level as a scale factor in that space: `nuc s0 -> 16`, `s1 -> 32`, ... Then:

- **matching levels** are read directly
- **missing fine levels** (image `s0..s3` here) fall back to the finest label level plus upsampling
- **label levels coarser than the image's coarsest** are simply never selected

Reuse `OmeZarrMetadataUtils.extractScaleFromCT` / `safeRatio` / `unitToMicrometreFactor`, and the
world-box helpers (`worldBoundingBox`, `outerBoundingBox`) to assert the two pyramids describe the
same extent before accepting the registration. Tolerance must allow a rounded-up downsample to
overshoot by up to one label voxel - the rule already added to `imageBoxContains.m:34`.

### The alignment arithmetic - the one genuinely hard part

Serving image level 0 from label level `L` (image-relative scale `sf`) is **not** a resize. The coarse
block does not start where the requested window starts:

```
requested full-res rows        y1 .. y2
coarse rows                    c1 = ceil(y1/sf),  c2 = ceil(y2/sf)      (clamped to level dims)
those rows represent full-res  (c1-1)*sf + 1  ..  c2*sf
```

A plain `imresize` returns `(c2-c1+1)*sf` rows starting at `(c1-1)*sf+1` - **wrong size and a shifted
origin**. Worked example at `sf=16`: a request for columns 3-34 (32 wide) comes back as 48 columns
starting at column 1. The image path never shows this because its pyramid has a level at every
magnification, so its resize factor is always about 1 and the slop is sub-pixel.

The plan called for **resize-then-crop** in screen space. What was built is the **gather** those two
steps amount to - one source voxel per screen pixel - which is the same arithmetic with the
intermediate array removed and one rounding fewer. See "What Stage B actually changed" below.

Same per axis; `z` picks the nearest label slice with no resize.

**This is the piece that must be tested before the class exists**, against a synthetic pyramid whose
every voxel encodes its own coordinates - the same technique `ZarrChunkCacheTest` uses. A shape-only
test passes while every label sits 15 px to the left.

**Files:** `+io/+loaders/OmeZarrMetadataUtils.m` (registration + the crop-window helper, joining
`buildZarrBbox` / `regionToVoxelRange` as shared geometry), new
`tests/io/OmeZarrLevelRegistrationTest.m`.

### What Stage B actually changed

Three static methods in `OmeZarrMetadataUtils`, plus `tests/io/OmeZarrLevelRegistrationTest.m`
(19 tests, all `Unit`, offline and native-engine only).

- **`registerLevelScales(levelVoxelSizesXYZ, levelOuterBox, referenceVoxelSizesXYZ, referenceOuterBox)`**
  - everything in micrometres, boxes edge-based, which is the convention `applyRequestedRegion`
  already fixed for cross-pyramid comparison. Returns `scaleFactorsYXZ` (the label levels in the
  image's level-0 voxels - `nuc` registers as `[16 32 64 128 256]`), `referenceScaleFactorsYXZ` (the
  image's own magnification axis), `isIntegerScale`, and `ok`/`reason`.

  Two details earn their place: the **snap** to whole numbers (a store writes `5.24` against `2.62`,
  so the quotient arrives as `1.9999999` and every `ceil` downstream then reads a voxel too far at
  exactly the level boundaries), and the **extent check** with `max(imageVoxel/2, labelVoxel)`
  tolerance - the same double rounding `imageBoxContains` tolerates. A sub-volume is **refused**, not
  placed: nothing here carries an origin offset, so a crop would land at the origin at the wrong
  extent, which is the original bug in a new place.

- **`screenGridForRange(fullRange, levelScaleFactor, magFactor)`** - not in the plan, and the piece
  the plan was missing. It reproduces `getDataZarr:211-217` as arithmetic, because
  `labeloverlay` at `getRGBimage.m:454` composites the two layers directly and needs them the **same
  size exactly** - one row out is an error, not a misplacement. Two outputs matter:

  - `.size`, which the overlay must match, and which depends on the *image's* level scale, not the
    label's: `round(nLevelVoxels / (mf/sfImage))`, with `getDataZarr`'s own `1e-3` no-resize guard
    reproduced so a level already at the requested magnification returns its own voxel count.
  - `.origin`, the full-res coordinate where screen pixel 1 starts. It is **not** `y1`: the image
    snapped the request outward onto its own level's grid first. The plan's `cropOffset` measured
    from `y1`, which leaves the labels up to one screen pixel off - the image's own snap, made
    visible because a second pyramid does not share it.

  A test asserts `.size` against the **real loader** over a local two-level store at three
  magnifications, including a non-integer `mf/sf`. It is a formula copied out of another file, so it
  is pinned against that file rather than against itself.

- **`levelReadWindow(screenGrid, scaleFactor, levelSize)`** - returns `.levelRange` (the voxels to
  read) and `.sourceIndex` (one source voxel per screen pixel). **Gather, not resize-then-crop.**
  The two are the same arithmetic, but the gather has no intermediate to bound (the plan's concern
  about full-res space being unbounded when zoomed out disappears rather than being managed), reads
  only `viewport/sf + 1` voxels, drops the second rounding that resize-then-crop performs, and is
  exact instead of within a pixel. Applying it is `block(windowY.sourceIndex, windowX.sourceIndex, :)`.

  Each pixel takes the level voxel holding its **centre** - what `imresize(..., 'nearest')` does, so
  the two agree wherever the naive path was already right. Two consequences worth knowing:

  - The half-pixel offset keeps every `ceil` clear of an exact voxel boundary, so **no grid
    tolerance is needed** - unlike `regionToVoxelRange`, which needs `1e-6` precisely because it
    works on boundaries.
  - A pixel wider than two label voxels straddles a boundary exactly and covers equal parts of each,
    so which it shows is a choice. The lower voxel wins (`ceil`), matching the rest of the pyramid
    arithmetic. This is not hypothetical: it is every pixel once the view is zoomed out past the
    label pyramid's coarsest level. `aPixelStraddlingABoundaryTakesTheVoxelItStartsIn` pins it.

  `z` needs no special case - pass the image's own z scale as `magFactor` and the same pair of calls
  gives one label slice per image slice.

---

## Stage C - a view-only BigData labels class

```
MibImage
├── MibLabels63 ── MibBigDataLabels ── MibBigDataLabelsZarr2   (packed byte, 63 max, editable store)
└── MibLabels    ── [new] MibBigDataLabelsIndex                 (separate layers, up to 65535, read-only)
```

`core.MibBigDataLabelsIndex < core.MibLabels`. Everything that forces the merge today comes from the
left branch: six bits of material, bit 7 mask, bit 8 selection. The right branch has no packing, so
instance ids up to 65535 pass through untouched and the "no suitable class" problem dissolves.

**Add rather than modify.** `MibBigDataLabels` guards the editable store MIB writes during
segmentation; a view-only path has no business loosening it.

### Store access - follow `MibBigDataLabelsZarr2`, not `MibVirtualImage`

`MibBigDataLabelsZarr2.openStore` / `readPackedLevel` is already the right ~40 lines: parse
multiscales from `.zattrs`, open each level as `io.zarr.Array`, read a bbox through
`io.zarr.ChunkCache.read` keyed on the level path, permute with
`OmeZarrMetadataUtils.computePermutation`. Reusing that keeps the chunk cache (and lets a store opened
both as image and as labels share chunks), needs no invalidation because the store is read-only, and
avoids inheriting `MibVirtualImage.getDataZarr`'s defaults, which assume `levelImageSizes(1,:)` is the
full-resolution extent - untrue for an offset pyramid.

### Members

- `openStore(storePath, imageScaleRef)` - modelled on `MibBigDataLabelsZarr2.openStore`, plus Stage B
  registration. Sets `height/width/depth` to the **image's** full-res dims.
- `getData(type, orient, colChannel, options)` - **override, load-bearing**: pick the label level from
  `options.magFactor` in image scale space, read, apply `valueRemap`, then the Stage B
  resize-and-crop. Returns zeros for `mask` / `selection`.
- `setData(...)` - blocked, with the one-time read-only notice from
  `MibBigDataLabelsZarr2.setData63:411-434` (never per call: `setData` fires on every mouse-move).
- `countMaterials()` - override; `MibLabels/countMaterials.m:44-51` scans pixel data for
  `maxMaterials >= 256` and would read the whole remote volume.
- `obj.type = 'labels'` set explicitly - `MibImage.m:212-223` maps class to type and has no branch for
  a new class, leaving it empty while `getData.m:76` and others test `strcmp(obj.type,'labels')`.
- Materials follow the existing >255 convention: `materialNames = {'1';'2'}` carrying indices,
  `materialColors = rand(65535,3)`, `maxMaterials = 65535`.

### Routing

`resolveLabelRoute` gains a third route, `'overlay'`, chosen when `DatasetMode = BigData`, the label
pyramid registers at an integer level offset, and the world boxes agree. `openBtn_Callback` gains a
third branch beside the existing `crop` / `loadModel` split (`openBtn_Callback.m:104`). Attaching is a
small branch in `MibModel.loadModel` beside the existing `MibBigDataLabelsZarr2` / `MibBigDataLabels`
choice at `loadModel.m:199-205`, with the dims guard at `:218` relaxed to "registers at an integer
level offset over the same world extent".

### Deliberately blocked (view-only scope)

Named explicitly so none of it fails obscurely later: editing (`setData`), undo/backup
(`backup.m:189` tests `isa(...,'core.MibBigDataLabels')`, false here - must not fall through to a
full-volume read), `buildInstanceIndex`, `saveBigDataModel` (`:37-40` requires
`isa(...,'core.MibBigDataLabels')`), `convertModel`, and `'everything'` (structurally unavailable for
non-63 - `getData3D.m:222`). Each gets an explicit guard with a message naming the read-only nature,
not a silent no-op.

**Files:** new `mib/+core/@MibBigDataLabelsIndex/`, `+models/@MibModel/loadModel.m`,
`@SelectFromUrl/SelectFromUrl.m` + `openBtn_Callback.m`, `mib/mib3.m` (compiler inclusion if a view
is involved), new `tests/core/MibBigDataLabelsIndexTest.m`.

### What the class step actually changed

`mib/+core/@MibBigDataLabelsIndex/` (`MibBigDataLabelsIndex.m`, `openStore.m`, `getData.m`) plus
`tests/core/MibBigDataLabelsIndexTest.m` - 16 tests, all `Unit`, offline, over a local v2 pyramid
starting at 128 nm attached to a notional 8 nm image. No view, so no `mib3.m` change: the class is
constructed by name in `loadModel`, which the compiler sees statically.

Members are as planned. Four things the plan did not name:

- **`imageScaleFactors` is a property of its own** - the image pyramid's magnification axis, carried
  beside `modelScaleFactors`. It is not redundant: the overlay has to come back the size the image
  layer came back, and that size follows from the level the **image** is showing, not the one the
  labels are read from. This is the `screenGridForRange` finding from Stage B surfacing as state.
- **`renderPerObject` lives on the class**, applied in `readLevel` after the chunk cache. That makes
  Stage D a pure UI task - a toggle over an existing field - rather than anything touching the read
  path. `countMaterials` reports 1 while it is off. (Default was `false` here; Stage D reversed it.)
- **`setDataFast` is blocked too**, which the plan's list did not include. `MibDataset`'s fast paths
  gate on `datasetType == 'Standard'` so they never reach a BigData buffer, but the inherited version
  writes straight into `obj.data` - empty here - so a stray call would silently **grow** a
  full-resolution array in memory rather than fail. Blocked for that reason, not for symmetry.
- **Model type follows the store's dtype**: 65535/`uint16` normally, 4294967295/`uint32` when the
  declared dtype is wider, so an id past 65535 gets the wider family instead of wrapping. An
  unrecognised dtype is assumed to fit 16 bits, which every published label store does.

Two decisions worth keeping:

- **`materialsCount` comes from the coarsest level**, read whole at open time - one request, a few
  tens of kilobytes, the same trick `MibBigDataLabelsZarr2.resolveValueRemap` already uses. It is a
  **lower** bound: a thin structure can lose its rarest ids to eight rounds of downsampling. The
  alternative was `MibLabels.countMaterials` scanning a 510 GiB remote volume, and nothing needs an
  exact count - it feeds `addMaterial`, which this class blocks.
- **`openStore` probes both zarr formats** rather than being told which. It is reached from a URL the
  user picked and from a batch protocol that records only the path, so the format is not always known
  by the caller; two small metadata reads at worst, and the level arrays go through `io.zarr.Array`,
  which reads either.

`pixSize` and `boundingBox` are deliberately **not** set by `openStore` - they belong to the dataset
and arrive via `MibDataset.setPixSize`, the same way every other model type receives them. That is
the routing step's job.

### What the routing step actually changed

`loadModel.m`, `SelectFromUrl.m`, `openBtn_Callback.m`, `backup.m`, `buildInstanceIndex.m`, plus 5
new tests in `SelectFromUrlTest` and 4 more in `MibBigDataLabelsIndexTest`.

- **The dims guard at `loadModel.m:218` became a fallback rather than an error.** A store whose
  finest level does not match the image, or that fails to open at all, is handed to the overlay
  instead; only if *that* refuses does the error appear, naming both reasons. The mismatch is
  **discovered by opening** rather than predicted from metadata, so the wasted level walk is paid
  only on the path that then needs the overlay - and the `catch` arm means a foreign **v3** label
  store now works too, where before it hit `MibBigDataLabels`'s expectation of MIB's own layout and
  threw.
- **`openBtn_Callback` needed no third branch.** Because the discovery lives in `loadModel`, the
  `overlay` route reaches it by exactly the path `model` already took - and drag-and-drop and batch
  protocols get the overlay for free, which a branch in the controller would not have given them.
  Only its header comment changed.
- **`enableSelection = false` is the read-only guard**, not a class check per tool. Every
  segmentation tool tests it (the rule in CLAUDE.md) and so does `getRGBimage:248` before reading the
  selection, while the model overlay at `getRGBimage:216` needs only `modelExist` and `showModel` -
  so the labels display and nothing can edit them. `convertModel:122` turned out to be guarded by it
  already, and `saveBigDataModel:37-40` refuses a non-`MibBigDataLabels` layer on its own. Two sites
  still needed explicit guards, both because a fall-through means a **full-volume network read**
  rather than a no-op: `backup.m` (nothing to undo) and `buildInstanceIndex.m`.
- **`save` is overridden on the class to throw.** The inherited `MibLabels.save` writes `obj.data`,
  which is empty, so "Save model as..." would have written a valid but **empty** model file and
  reported success. It errors rather than returning quietly, because a save is deliberate and has a
  filename attached, so silence reads as "done".
- **`imageReference` became a static on the class**, shared by `loadModel` and
  `resolveLabelRoute` - two real call sites, and keeping one implementation is what stops the info
  panel promising a route the loader then refuses.
- **`resolveOverlayRoute` refuses a fractional scale** even though it registers. Nothing in the read
  path breaks on 1.5x; a label would be split across an image voxel with no way to say which side it
  belongs to, and the crop route gives an exact answer instead.
- **The A2 refusal is now conditional**, as planned: with `Dataset mode = BigData` it leads with why
  *this* store cannot be shown over the open image (the registration's own reason) before offering
  the Standard route, instead of implying BigData is never possible for a label group.

**Risk 2 did not materialise.** `initialize.m`'s `MibLabels63` placeholder is written when the buffer
is created, before `loadModel` replaces `ds.labels` - so nothing clobbers the attached layer in that
order. A later mode re-switch does drop the overlay, which is correct: it drops any model.

**A correction to the size argument above.** `getRGBimage:272-282` already resizes a Virtual/BigData
overlay to the displayed image size when the two differ, so a wrong size is a silent **stretch**, not
the error claimed earlier. That makes exact sizing more important rather than less - a stretched
overlay reintroduces the shear the gather exists to remove, and nothing reports it - and it is why
`theOverlayIsTheSizeTheImageLayerReturns` checks five magnifications rather than trusting the net.

### Exporting an overlay - "Save model as" writes one chosen level

Requested after the routing landed, and it replaced the `save` override that threw. Read-only is not
the same as un-exportable: the labels are real data, they just have no full-resolution level, so the
level is the one thing the user has to say.

**Almost all of it already existed.** `BatchOpt.PyramidLevel`, the level dialog in
`MibModel.saveImage:338-360`, `io.savers.MibImageSliceProvider` (explicitly backend-neutral: it calls
`getData(layerType, 3, colChannel, options)` with `pyramidLevel` + a full-resolution `z`, and names
no store), and `MatlabSaver.saveStream`'s disk-backed matfile were all built for the BigData *mask*
and *63-model* paths. Four small pieces connected them:

- **`getData` with an explicit level now returns the level's own voxels**, skipping the gather. That
  is the read contract the provider needs, and it also fixes a real edge: a store whose shape rounded
  **down** covers slightly less than the image claims, and the gather would repeat its last row to
  fill the requested extent - right for a display, wrong in a file.
- **`MibLabels/save.m` gained the streaming branch** its sibling `MibLabels63/save.m:116-133,216-222`
  already had, so the metadata assembly (materials, annotations, slice names, `modelType`) is reused
  rather than duplicated. pixSize is scaled by the level's factors; the bounding box is physical and
  identical at every level, so it is left alone.
- **`MibModel.saveImage` sources the level list from the label pyramid** when the layer is an
  overlay. The image's list would be wrong in a way that matters: `nuc` has 5 levels where the EM has
  12, so four of the offered resolutions never existed and picking one would mean upsampling the
  whole volume to write it. Each entry also names the factor against the image voxel, which needs no
  units - the store's own level *names* say nothing about resolution once its `s0` is already a
  downsample.
- **A real pre-existing bug in `MatlabSaver.saveModel3DStream`**, reachable exactly where this
  feature needs it. `m.(labVar)(H, W, 1) = 0` on a writable matfile creates a **2-D** variable
  (matfile drops the trailing singleton), and the next `m.(labVar)(:,:,z)` then errors on the
  dimension count. Any single-slice pyramid level hits it - which the coarsest level of a deep
  pyramid usually is - so the 63-branch model path had it too.

`MibBigDataLabelsIndexTest` is now 25 tests: the exported volume is asserted **value for value**
against the store's own level, a coarser level gives that level's dimensions, an out-of-range level
clamps instead of erroring, `MaterialIndex` exports one object as a binary volume, and `obj.data`
stays empty throughout.

**Docs updated**, since this changes what the UI does: `home-importfromurl.md` (the overlay is now
one of three Load-as outcomes, with a *Saving an overlay* section, and the "whole-volume
segmentations cannot be loaded" and "Dataset mode is overridden" passages were both stale) and
`ribbon/model/index.md` (the existing Pyramid-level tip now covers the overlay's differing level
list).

### Three pre-existing test failures, fixed

`SelectFromUrlTest` was red before this work: Stage A2's mode refusal landed without updating two
`Integration` tests that never set `DatasetMode` (so they inherited the `BigData` default and were
refused, leaving the default 64x64x16 buffer and asserting against it), and
`theCropRouteRefusesAModeItCannotDeliver` still expected a message two revisions old. All three now
pass - 53/53.

---

## Stage D - instance rendering choice

With Stage C there is no need to merge, so this becomes a **display** setting rather than a load-time
one - which is the substantive improvement over what ships today.

- **Default: single material.** `valueRemap` (any non-zero -> 1) already exists in
  `MibBigDataLabelsZarr2:resolveValueRemap` and applies per block read, after the chunk cache.
  **This was reversed on landing** - per object is the default and the merge is the opt-out.
- **Opt-in: per object**, ids passed through. Safe to offer because compositing is O(pixels).
- Gate `getRGBimage.m:426-436`'s per-material contour loop on `maxMaterials < 256` while here.

Surface it next to *Show model* rather than in the import dialog, so it can be toggled after loading.

### What Stage D actually changed

`+views/@MibView/addSelectionViewSettingsPanel.m`, `@MibSelection/MibSelection.m`, two new callback
files, and the contour gate in `getRGBimage.m`. No read-path change, as predicted.

- **The default is reversed: per object, with the merge as the opt-out.** The plan had it the other
  way on the reasoning that a user looking at a segmentation wants to see the structure. Seeing it
  running says otherwise: the object ids are what the store actually holds, the merge is the lossy
  view, and compositing costs the same either way - so defaulting to the merge threw away
  information for nothing and left the feature invisible unless the user happened to right-click.
  `resolveOverlayRoute`'s info-panel note changed with it and now names the control, so the merged
  view is still one gesture away and discoverable before Open.

- **It is a context menu on the `showModel` checkbox, not a checkbox beside it.**
  `SelectionViewSettings.mlapp` is an App Designer binary that cannot gain a widget from a text edit -
  the same constraint that left `ImageGroupPath` batch-only and made `chooseCropLevel` a runtime
  dialog. The panel already builds its `lutTable` context menu programmatically in
  `addSelectionViewSettingsPanel.m`, so the menu joins that block and the controller wires the
  callbacks, keeping the view/controller split the file already has.

- **State is read in `ContextMenuOpeningFcn`, not kept in step by listeners.** The entry is enabled
  and checked from `getActiveId()` at the moment the menu opens, so a buffer switch, a mode change or
  a model being closed reach it without notifying anything. A listener would have been a fourth place
  to keep synchronised for a control that is invisible 99% of the time.

- **The contour gate turned out to need more than a gate.** The plan said "gate
  `getRGBimage.m:426-436` on `maxMaterials < 256`", but falling through to the existing `else` arm
  (`M - imerode(M)`) is wrong for a label matrix: at a boundary between objects 5 and 9 it paints the
  difference, `4`, so contours come out in unrelated colours. The `>= 256` case gets its own arm,
  `M(M == imerode(M, ...)) = 0`, which keeps each object's own index on the pixels the erosion
  removed. Verified live at 486 objects: ids preserved, max id kept 486. The `< 256` arms are
  untouched, so no existing model changes appearance.

  `elseif selectedObject > 0` had the same uint8 bug one line down (`zeros(size(M), 'uint8')` wraps a
  selected object past 255) and is now `'like', M`.

- **Live-verified against `jrc_mus-kidney-2`'s `nuc`** in a running MIB rather than by unit test,
  since both halves need either a window or the network. Registration `[16 32 64 ... 4096]` against
  the image's `[1 2 ... 4096]`; merged gives `unique == [0 1]`, per-object gives 30 distinct ids in
  one view with `max == 486`; the footprints are identical either way; `obj.data` stays empty.

**One thing the live check found, since fixed.** `materialsCount` came back as **1** for this store.
`openStore` probed the **coarsest** level for the highest id, and `nuc`'s coarsest is `3 x 3 x 3` -
by which point every nucleus has been downsampled out of existence. The documented "lower bound"
degenerates to useless on a deep pyramid, which only a 9-level store reveals; the 3-level test
fixture could not.

It now probes the **finest level inside a 2e6-voxel budget** (about 4 MB at uint16) instead of the
last one. Measured against the live store:

| level | voxels | read | max id |
|---|---|---|---|
| `s5` | 15 600 | 0.26 s | 480 |
| `s4` | 129 850 | 0.25 s | 486 |
| `s3` | 1 059 300 | 0.49 s | **489** (chosen) |
| `s8` | 27 | - | 0 (what it used to read) |

So the fix costs about a quarter of a second against `s4`, inside an attach that already takes ~6.6 s
opening nine remote arrays and their metadata - the probe was never the expensive part. The count is
still a lower bound, and still far cheaper than `core.MibLabels.countMaterials` scanning a 510 GiB
volume. The walk towards coarser levels survives as the fallback when a read throws.

`theCountIsNotTakenFromTheCoarsestLevel` is the regression guard: the fixture's coarsest level is
filled with a single id `60000` that appears nowhere else, so reading it instead of a finer level
shows up as a wrong value rather than merely a pessimistic one.

---

## Risks

1. **The alignment crop is the whole feature.** Off-by-N produces plausible, misplaced labels. Tested
   before the class exists, with value-encoding voxels - see Stage B. What is **not** yet covered is
   the one thing a unit test cannot reach: that `pickLevel` hands `levelReadWindow` the same scale
   space the grid was built in. Stage C owns that, and it is the remaining way to get a 16x error.
2. **`maxMaterials ~= 63` on a BigData buffer is a combination that has never existed.** The audit
   above lists the couplings; the view-only scope means most are write paths that get guards rather
   than fixes, but `initialize.m:122,131` hardcode a `MibLabels63` placeholder for Virtual/BigData and
   will need a path that does not clobber the attached layer.
3. **Level registration relies on declared metadata.** Two pyramids can share a scale and still not be
   the same volume; the world-box check is what prevents that, and it needs the one-label-voxel
   tolerance.
4. Stage A's refusal must not strand the user: the message has to name the mode to pick, and the level
   picker has to appear once they do.

---

## Verification

**Offline unit tests** (`buildtool test`, all `Unit`):

- `tests/io/OmeZarrLevelRegistrationTest.m` - **done**, 19 tests. Registration against `jrc_mus-kidney`'s
  level tables (rounded decimals, a fractional scale, a rounded-up shape, a sub-volume, a shifted
  volume); the gather asserted on **values**, not shapes, over a set of windows at several
  `magFactor`s including non-integer ratios and volume edges, with the gathered numbers being the
  source voxel indices themselves and the expected ones worked out from the image's grid; and
  `.size` asserted against the real `getDataZarr` over a local store.
- `tests/core/MibBigDataLabelsIndexTest.m` - **done**, 16 tests, over a local v2 store built with
  `io.zarr.Group.create` (as `ZarrRegionReadTest` does), every voxel of the finest level carrying its
  own coordinates: registration is `[16 32 64]` and not `[1 2 4]`; a matching-level read is
  byte-identical to the raw array; a full-resolution read is the correct upsampled window, asserted
  against `ceil(fullRes/16)` derived in the test; the overlay is the size the image layer returns
  across five magnifications; an XZ slice reads the same voxels transposed; `setData` and
  `setDataFast` are blocked with the store byte-unchanged on disk and `obj.data` still empty; ids
  above 63 survive; the single-material default collapses them; `'everything'` errors; mask and
  selection come back empty at the labels' size.
- `tests/controllers/SelectFromUrlTest.m` - the `overlay` route is chosen for a registrable pyramid;
  BigData is refused with the "set Dataset mode = Standard" message when it is not; the level picker
  offers only valid pairs.

**Live network checks** via the MATLAB MCP against
`https://janelia-cosem-datasets.s3.amazonaws.com/jrc_mus-kidney/jrc_mus-kidney.zarr`
(`nuc`, 5 levels from 128 nm, 864 objects, EM 12 levels from 8 nm) and
`jrc_ctl-id8-1` (`nuc`, 4 levels from 64 nm, EM 6 from 4 nm):

**All four done 2026-09-18** against a live `jrc_mus-kidney-2` buffer (`nuc`, 9 levels from 128 nm,
EM 13 from 8 nm), driven from the MATLAB console rather than the window:

- the EM stays `datasetType = BigData` with **no bulk download** - `numel(image.data) == 0`
  confirmed, and `modelScaleFactors(:,1)'` is `[16 32 64 ... 4096]` against the image's
  `[1 2 ... 4096]`;
- a slice read at 128 nm is **byte-identical** to a direct `io.zarr.Array` read of the same bbox;
- a slice read at 8 nm is the **exact** upsample of that same data
  (`direct(repelem(1:100,16), repelem(1:100,16))`, equal element for element), and an off-origin
  window at `[801 1600]` matches the same grid - the pan-drift check, row 7 below;
- **z alignment is exact**: all sixteen full-resolution slices of label voxel 375 return that
  voxel, and both neighbouring slices across the boundary return a different one. This is row 5,
  the one place a z off-by-one would show;
- the overlay is the size the image layer returns at **seven** magnifications, including the ones
  that round (`188`, `94`, `48`);
- a slice change costs **2.7 ms for the overlay against 4.6 ms for the image itself** with chunks
  warm, so the chunk cache is doing its job.

Between them these close Risk 1's residual - `pickLevel` and `levelReadWindow` demonstrably share a
scale space, since a 16x error could not survive a byte-identical read at one level and an exact
upsample at another.

**Manual, in a running MIB** - open item 10 in [`plan_url_s3.md`](plan_url_s3.md). Nothing below is
covered by the suite, because each item needs either the real network or a window.

**All but three rows are now closed.** Rows 1, 4, 5, 6, 7 and 14 were settled from the console by
the live checks above; 11 and 11b were confirmed at the window. A second pass against a live
`jrc_mus-kidney-2` buffer closed the rest:

| Row | How it was settled |
|---|---|
| 2, 3 | `resolveOverlayRoute` returns `overlayFits = 1` and the exact two-paragraph note, read back verbatim |
| 8 | `enableSelection == 0` on the attached buffer - the flag every segmentation tool returns on |
| 9 | `backup('labels')` and `backup('everything', 3D)` return in **5 ms and 0.9 ms** leaving `undoList` unchanged; `buildInstanceIndex` refuses in 4.5 ms. A missing guard would have been a full-volume network read, so the timing *is* the assertion |
| 10 | the level dialog lists the **labels'** 9 levels with their factor against the image voxel, not the EM's 13 |
| 10b | `s5` exported from the **remote** store in 0.93 s, reopened standalone, identical to the store's own level; `obj.data` empty throughout |

`materialsCount` reads 489 and `renderPerObject` is true on a buffer opened through the real UI, so
both of this session's changes are confirmed end to end rather than only in the fixture.

**What is genuinely left**, and why the console cannot reach it:

- **Row 10c** - cancelling a long save must leave no partial file. The cancel is a
  `uiprogressdlg` button; there is nothing to press headlessly.
- **Row 12** - the Standard crop route. Its level picker is a modal dialog, and the check is that
  the buffer *becomes* Standard and the panel agrees, which is a repaint.
- **Row 13** - the ground-truth crop refusal. It needs `jrc_mus-kidney`'s **own** EM open:
  `jrc_mus-kidney-2` publishes no `groundtruth` group at all, and pointing at another container's
  crop fires a different and earlier branch ("No sibling image pyramid could be found"), not the
  world-box refusal this row is about.

Container: `https://janelia-cosem-datasets.s3.amazonaws.com/jrc_mus-kidney/jrc_mus-kidney.zarr`
(EM `recon-1/em/fibsem-uint8`, 12 levels from 8 nm; labels
`recon-1/labels/inference/segmentations/nuc`, 5 levels from 128 nm, 864 objects). Second case:
`jrc_ctl-id8-1` (`nuc` 4 levels from 64 nm, EM 6 from 4 nm).

| # | Operation | What must happen |
|---|---|---|
| 1 | Open the EM group with `Dataset mode = BigData` | Loads browse-only; Datasets panel says BigData |
| 2 | Select `nuc`, `Load as = Labels`, mode still BigData | Info panel: "Label overlay: these labels start at 128 nm, 16 x the open image's voxel ..." and "cannot be edited". Open **enabled** |
| 3 | Press Open | Labels appear over the EM. Datasets panel still says BigData. No long download |
| 4 | Console: `mibModel.I{1}.labels` | `class` is `core.MibBigDataLabelsIndex`; `numel(data) == 0`; `modelScaleFactors(:,1)'` is `[16 32 64 128 256]` - **not** `[1 2 4 8 16]` |
| 5 | Scrub Z one slice at a time | Labels follow the structures; no jump every 16th slice (a z off-by-one shows exactly there) |
| 6 | Zoom out and in across 8 -> 128 nm | Labels stay on the same structures at every step. A shift appearing at one zoom is the level-boundary bug |
| 7 | Pan at full zoom, far from the origin | Labels stay put. A drift growing with distance is the crop-offset bug |
| 8 | Try to paint / use the brush | Nothing is drawn; the segmentation panel is inert (`enableSelection` is false) |
| 9 | Ctrl+Z | Nothing happens, and no pause (a full-volume read would hang) |
| 10 | Save model as ... | A level list appears, showing the **labels'** 5 levels (not the EM's 12), each with its factor against the image voxel |
| 10b | Pick `s2`, save as `.model`, then open that file on its own | The saved model is that level's own dimensions and values; the write does not need memory to hold it |
| 10c | Pick `s0` on `jrc_mus-liver-6`'s `er` and start the save | It streams; a coarse level finishes quickly. Cancel must leave no partial file behind |
| 11 | Right-click *Show model*, clear **Render instances per object** | Objects fuse into one material; ticking it again restores the individual colours. The entry is greyed for any other model type |
| 11b | Turn on *Show as contours* with per-object on | Each object outlined in its own colour, not in a colour computed from its neighbour's index |
| 12 | Repeat 2 with `Dataset mode = Standard` | The old crop route: level picker appears, region read into memory, buffer becomes Standard and the panel says so |
| 13 | A ground-truth crop group (`recon-1/labels/groundtruth/...`) in BigData mode | Refused, leading with "cannot be shown over the open dataset ... do not describe the same volume", then the numbered Standard steps |
| 14 | Time a slice change with the overlay on versus off | The difference is one small ranged request, not a visible stall - the chunk cache doing its job |

**Build checks:** `buildtool check`; `grep -rn --include=*.m "—\|–" . | grep -v "^./deployed/"` must
return nothing.

---

## Sequence

| # | Stage | Depends on | Why this order |
|---|---|---|---|
| 1 | A1 panel sync | - | **Done.** Standalone bug, one block moved |
| 2 | A2/A3 refusal + level picker | - | **Done**, pulled forward - see the note at the top |
| 3 | B registration + alignment tests | - | **Done.** The risky piece; proved before anything is built on it |
| 4 | C the class + routing | B | **Done** - class, routing and the blocked-path guards |
| 5 | D rendering choice | C | **Done** - context menu on `showModel`, plus the contour gate |

**Carried into Stage C:** the A2 refusal currently says BigData is impossible for a label group.
Once the overlay route exists that is only true when the pyramid does not register, so the message
becomes conditional on that rather than on the mode alone.

### What Stage A actually changed

- `ensureDatasetMode` owns the `Sets.datasetTypes` **write**, so both the image route and the crop
  route keep the panel honest. It runs on the no-op too: the cache can go stale from anywhere and
  this is the one place that knows.

  > **The repaint could not move with it, and moving it crashed every BigData import.**
  > `DatasetsPanelUpdate` reaches `MibActiveDataset.update_fromModel` -> `buffers_Callback` ->
  > `ShowImage`, so it repaints the buffer - which between the mode switch and the load holds only
  > the placeholder. For a Virtual/BigData target that is a path to `default.h5` with no reader
  > attached, and the repaint dies in `MibVirtualImage.getDataVirt:91` on a scalar `Xlim`.
  >
  > Checking that `loadImages` never assigns `datasetType` established that the *value* would be the
  > same either side of the load, and that was true - but the notify is not about the value, it is a
  > full repaint, and the original position after the load was load-bearing for that reason. The
  > write stays in `ensureDatasetMode` (inert: nothing reads the cache until something repaints) and
  > each caller notifies once its own load has finished.
  > `switchingTheModeUpdatesTheDatasetsPanelCache` now asserts the notify count is **zero**.
- `planLabelCrop` returns **every** level pair that lines up (`candidatePairs`), not just the finest,
  each with its shape, voxel size, byte cost and a `fits` flag. The default is the finest pair that
  **fits**, so the preselected row of the dialog is always openable - previously a store whose finest
  pair was too large was refused outright even when a coarser pair would have worked.
- `resolveLabelRoute` refuses a non-Standard mode and names what would be produced, rather than the
  cause. Saying "these labels are 4 nm while the image is 4 nm" was the first wording and it reads as
  nonsense whenever the two agree - which a sub-volume crop at full resolution does.

  The **second** wording was reported as hard to follow: cause, consequence and remedy ran together
  in one paragraph. It is now three blocks - what is wrong, what you would get, numbered steps - and
  `applySummary` splits with `'CollapseDelimiters', false`, or the blank lines between them are
  swallowed and the whole thing arrives as one dense block anyway. Two tests pin the steps, because
  the instructions are the point of the message rather than a decoration.

- **`openPlainImageUrl` had the same stale-cache bug, found separately.** It has always initialised
  the buffer as `'Standard'` (a plain image is one array in memory; there is no pyramid to stream),
  but nothing wrote `Sets.datasetTypes` - so importing a JPEG over an open BigData buffer left the
  panel claiming BigData for a single image. It now goes through `ensureDatasetMode` like everything
  else, forces the `DatasetMode` control to Standard so the dialog agrees, and notifies **after** the
  image is in place. That is a third route needing the same fix, which is the argument for
  `ensureDatasetMode` owning the write.
- `chooseCropLevel` asks which pair, skipping silently for a single candidate or when
  `BatchOpt.ZarrLevel` names one. An unusable `ZarrLevel` is reported, never quietly replaced.
- `chooseInstanceHandling` regained **Cancel**; the two-button form had no way out.
- `updateBatchOptFromGUI` re-probes on `LoadAs` / `DatasetMode` changes so the verdict in the info
  panel follows the setting. Free - the probe is cached per URL for the session.
