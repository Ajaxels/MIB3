# Plan: label pyramids that do not match the image - honest dataset mode, and a view-only BigData overlay

**Status:** Stage A done (A1 + A2 + A3). Stages B, C, D planned.
Written 2026-09-17.

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

Correct form is **resize-then-crop**, and the arithmetic must be done in **screen** space so the
intermediate stays bounded by the viewport (in full-res space it is unbounded when zoomed out - at
`magFactor 32` the full-res window is ~36000 px wide):

```
screenWidth   = round((y2 - y1 + 1) / mf)
blockScreen   = round((c2 - c1 + 1) * sf / mf)
resize coarse block (c2-c1+1 rows) -> blockScreen rows, 'nearest'
cropOffset    = round((y1 - ((c1-1)*sf + 1)) / mf) + 1
take cropOffset : cropOffset + screenWidth - 1   (clamped)
```

Same per axis; `z` picks the nearest label slice with no resize.

**This is the piece that must be tested before the class exists**, against a synthetic pyramid whose
every voxel encodes its own coordinates - the same technique `ZarrChunkCacheTest` uses. A shape-only
test passes while every label sits 15 px to the left.

**Files:** `+io/+loaders/OmeZarrMetadataUtils.m` (registration + the crop-window helper, joining
`buildZarrBbox` / `regionToVoxelRange` as shared geometry), new
`tests/io/OmeZarrLevelRegistrationTest.m`.

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

---

## Stage D - instance rendering choice

With Stage C there is no need to merge, so this becomes a **display** setting rather than a load-time
one - which is the substantive improvement over what ships today.

- **Default: single material.** `valueRemap` (any non-zero -> 1) already exists in
  `MibBigDataLabelsZarr2:resolveValueRemap` and applies per block read, after the chunk cache.
- **Opt-in: per object**, ids passed through. Safe to offer because compositing is O(pixels).
- Gate `getRGBimage.m:426-436`'s per-material contour loop on `maxMaterials < 256` while here.

Surface it next to *Show model* rather than in the import dialog, so it can be toggled after loading.

---

## Risks

1. **The alignment crop is the whole feature.** Off-by-N produces plausible, misplaced labels. Test it
   before the class exists, with value-encoding voxels.
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

- `tests/io/OmeZarrLevelRegistrationTest.m` - registration against a synthetic offset pyramid; and the
  resize-and-crop asserted on **values**, not shapes, over a set of windows at several `magFactor`s
  including non-integer ratios and volume edges.
- `tests/core/MibBigDataLabelsIndexTest.m` - a local v2 store built with `io.zarr.Group.create` (as
  `ZarrRegionReadTest` does): reads at a matching level are byte-identical to the raw array; reads at a
  finer level are the correct upsampled window; `setData` is blocked; ids above 63 survive; the
  single-material remap collapses them.
- `tests/controllers/SelectFromUrlTest.m` - the `overlay` route is chosen for a registrable pyramid;
  BigData is refused with the "set Dataset mode = Standard" message when it is not; the level picker
  offers only valid pairs.

**Live network checks** via the MATLAB MCP against
`https://janelia-cosem-datasets.s3.amazonaws.com/jrc_mus-kidney/jrc_mus-kidney.zarr`
(`nuc`, 5 levels from 128 nm, 864 objects, EM 12 levels from 8 nm) and
`jrc_ctl-id8-1` (`nuc`, 4 levels from 64 nm, EM 6 from 4 nm):

- the EM stays `datasetType = BigData` with all 12 levels and **no bulk download** - assert
  `numel(image.data) == 0`;
- a slice read at 128 nm returns pixels identical to a direct `io.zarr.Array` read of the same bbox;
- a slice read at 8 nm returns the correctly cropped upsample of that same data;
- time a slice change with the overlay on versus off, to confirm the chunk cache is doing its job.

**Manual, in a running MIB** - the part never yet exercised, and open item 10 in
[`plan_url_s3.md`](plan_url_s3.md): open the EM as BigData, select `nuc`, confirm the info panel
wording, Open, scrub Z and zoom across a level boundary, toggle single-material versus per-object,
and confirm the Datasets panel says BigData throughout. Then repeat with `Dataset mode = Standard`
and confirm the level picker appears and the refusal path is gone.

**Build checks:** `buildtool check`; `grep -rn --include=*.m "—\|–" . | grep -v "^./deployed/"` must
return nothing.

---

## Sequence

| # | Stage | Depends on | Why this order |
|---|---|---|---|
| 1 | A1 panel sync | - | **Done.** Standalone bug, one block moved |
| 2 | A2/A3 refusal + level picker | - | **Done**, pulled forward - see the note at the top |
| 3 | B registration + alignment tests | - | The risky piece; prove it before anything is built on it |
| 4 | C the class + routing | B | |
| 5 | D rendering choice | C | |

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
