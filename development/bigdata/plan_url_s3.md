# Remote OME-Zarr from a URL (S3 / HTTPS)

Working reference for `Home -> Import -> URL / Zarr` - `controllers.SelectFromUrl`, `io.RemoteStore`
and the remote paths through the zarr loaders. Implemented 2026-08-10 through 2026-09-17. Read this
before changing any of it.

Paste a store URL, browse the group tree, open it as BigData / Virtual / Standard, or load a label
group as a model. Supersedes the deferred "Remote OME-Zarr over HTTP/URL" item in
[`bigdata_implementation_plan.md`](bigdata_implementation_plan.md) §5. Step-by-step history: git
before `80801844`.

> **Read [`plan_url_s3_labels_mismatch.md`](plan_url_s3_labels_mismatch.md) alongside this.** It
> supersedes the crop route for label pyramids coarser than their image: `core.MibBigDataLabelsIndex`
> now serves a read-only label overlay per slice over a **BigData** image, so that case is no longer
> a bulk download into a Standard buffer, and `Dataset mode` is no longer silently overridden.
> Everything below still describes the browser, `RemoteStore`, geometry, decoding and the cache,
> which that plan builds on unchanged.

## Files

| Area | Files |
|---|---|
| Object-store plumbing | `mib/+io/RemoteStore.m` (static-only, no zarr knowledge) |
| Format probe | `mib/+io/ExtensionRegistryLoad.m` - `probeRemoteZarr`, `clearRemoteProbeCache` |
| Python dependency check | `mib/+io/+zarr/PyBackend.m` - `hasRemoteSupport`, `ensureRemoteSupport` |
| Chunk cache | `mib/+io/+zarr/ChunkCache.m` |
| Geometry + regions | `mib/+io/+loaders/OmeZarrMetadataUtils.m` - `worldBoundingBox`, `outerBoundingBox`, `regionToVoxelRange`, `applyRegionToLevels`, `applyRequestedRegion`, `applySelectedLevelGeometry`, `resolveRegionOption`, `resolveLevelOption`, `unitToMicrometreFactor`, `buildZarrBbox`, `levelRegionBbox`, `extractTranslationFromCT`, `extractCTVector` |
| Loaders | `Zarr2/Zarr3VirtualSetupLoader.m` (per-level world boxes, region crop, explicit level), `Zarr2/Zarr3VirtualLoader.m` |
| Read path | `+core/@MibVirtualImage/getDataZarr.m`, `+core/@MibImage/initialize.m` |
| Model | `+models/@MibModel/loadImages.m` (`ZarrGroupPath`, `Region`, `ZarrLevel`), `loadModel.m`, `createModel.m`, `+core/@MibDataset/loadModel.m` |
| Label store | `+core/@MibBigDataLabelsZarr2/MibBigDataLabelsZarr2.m` - `valueRemap`, `resolveValueRemap`, `readPackedLevel` |
| Dialog | `+views/SelectFromUrlGUI.mlapp` (**author-built**), `+controllers/@SelectFromUrl/` |
| Ribbon | `@MibRibbon/homeImport_Callback.m` (`case 'URL'`), `mib3.m` compiler-inclusion block |
| Tests | `tests/io/RemoteStoreTest.m`, `ExtensionRegistryRemoteZarrTest.m`, `PyBackendRemoteSupportTest.m`, `OmeZarrGroupResolutionTest.m`, `OmeZarrWorldGeometryTest.m`, `ZarrRegionReadTest.m`, `ZarrChunkCacheTest.m`, `NativeZarrV2Test.m`, `RemoteOmeZarrOpenTest.m`, `tests/controllers/SelectFromUrlTest.m` |
| Docs | `docs/docs/user-interface/ribbon/home/home-importfromurl.md`, `home-preferences.md`, `getting-started/dataset-types/index.md` |

`@SelectFromUrl/` holds: `addCallbacks`, `updateWidgets`, `connectBtn_Callback`,
`treeNodeExpanded_Callback`, `treeSelectionChanged_Callback`, `probeGroup`, `openBtn_Callback`,
`openPlainImageUrl`, `buildLoadImagesBatchOpt`, `readGroupPyramid`, `planLabelCrop`,
`resolveSiblingImageGroup`, `isAnnotationPath`, `imageBoxContains`, `composeLabelModel`,
`labelEncodingValues`, `labelGroupName`, `selectedLabelGroupUrls`, `ensureDatasetMode`,
`openLabelCrop`, `reportCropResult`.

Named `SelectFromUrl`, not anything zarr-specific, because it also handles plain image URLs -
the old `imfinfo`/`imread` route moved verbatim into `openPlainImageUrl`.

**Widget names are the contract.** `core.ChildView` copies each App Designer component's property
name into its `Tag`, and it recurses into `uitree`. BatchOpt-mapped widgets must be named exactly as
their field (`Url`, `GroupPath`, `LoadAs`, `DatasetMode`, `showWaitbar`); non-BatchOpt widgets use
descriptive lowerCamel (`connectButton`, `groupTree`, `infoTextArea`, `statusLabel`, `openButton`,
`closeButton`, `helpButton`, `chunkCacheMB`). `chunkCacheMB` edits the `IO.Zarr.ChunkCacheMB`
preference directly and calls `io.zarr.ChunkCache.setBudgetMB` at once - the same preference as
Preferences -> Input/output, and deliberately not BatchOpt, since the cache is process-wide.
`updateWidgets` widens its canvas `Limits = [1 Inf]` to `[0 Inf]` before assigning, as
`Preferences.updateWidgets` does, so a stored 0 (cache off) does not throw. `SelectFromUrl.resetDialog` clears the placeholder tree nodes App
Designer stores with the canvas (`Node`, `Node2..4`) and disables Open at startup - they are useful
for laying the dialog out, so they are cleared in code rather than deleted in the designer. The tree
fills lazily through the deferred-node pattern of `@DatasetInfo/treeNodeExpanded_Callback`: children
are created with a `'__loading__'` `NodeData.key` and filled on expand, exactly one `listChildren`
per expand.

`Zarr2VirtualSetupLoader.zarrV2TypeToMatlabClass` is public so the preview panel reports the data
type the loader will actually produce (`uint8`) rather than the raw numpy typestring (`|u1`).
Duplicating that table in the controller would let the two drift.

---

## Rules that fail silently

**Never `fullfile` a URL.** On Windows it turns `https://host/group` into `https://host\group`. Use
`io.RemoteStore.join`, which `/`-joins. `loadImages` line 133 takes the `else` branch when
`BatchOptIn` carries `Filenames` precisely so no path joining runs.

**`RemoteStore.join` appends `..`, it does not resolve it.** `join(url,'..')` then `relativePath`
finds no common prefix and returns its input unchanged - which once made a material's name the whole
URL. Take the last path segment instead (`labelGroupName`).

**`strsplit` on a URL needs `'CollapseDelimiters', false`**, or the empty segment between the
scheme's two slashes is dropped and rejoining yields `https:/host`.

**`fileparts` splits a URL happily and produces a directory that does not exist.**
`MibController.updateGuiWidgets` derives `mibModel.currentDirectory` this way; a remote dataset must
be guarded there beside the existing `none.tif` placeholder guard, and the basename cleared with it.
Blast radius is wider than the Directory Contents panel - `currentDirectory` seeds Save image, Save
model, the BigData store picker and the recent-directories list.

**`isfile()` cannot see a URL.** That is why `detectZarrFormatExtension` silently fell back to
`'zarr3'` and handed v2 stores to the v3 loader. `probeRemoteZarr` is **tri-state** (`'zarr2'` /
`'zarr3'` / `''`) and public, because callers need "not a zarr store" distinct from "a v3 store".
`detectZarrFormatExtension` keeps its two-state contract and its `'zarr3'` fallback. The probe is:
session cache, then one `ListObjectsV2` (`max-keys=20`) if listable and inspect the basenames -
`zarr.json` gives `'zarr3'`, `.zgroup`/`.zattrs`/`.zarray` give `'zarr2'` - else `exists()` on those
markers with 5 s timeouts, else the legacy `'zarr3'` default plus a `DeveloperMode` note. In
`resolveLoader`, remote paths reach the probe when the extension is empty *or* `zarr`, since a bucket
prefix need not end in `.zarr`; an ordinary remote `.png` probes empty and keeps the `imread` route.

**In S3 XML, iterate `CommonPrefixes` and take each one's child `Prefix`** - never the bare `Prefix`
tag. The response echoes the *request* prefix under that name and it is picked up as a phantom child.
Files come from `Contents` -> `Key`.

**Centre space and edge space are both in use, and mixing them misplaces labels plausibly.** See
[Geometry](#geometry-the-half-voxel-trap). This is the single most dangerous thing in this file.

**A group that declares no `present` value is an index map, not a binary mask.** Defaulting to
`present = 1` produced an empty model **with no error** on `crop266/all`. `labelEncodingValues`
returns `isSemantic`, true only when the store actually declares `present`.

**A foreign store's values are not MIB packed bytes.** 255 is `0b11111111`, so an undecoded 0/255
store arrives as material 63 with the mask *and* selection bits set. `resolveValueRemap` decides the
mapping at open time - see [Label decoding](#label-decoding-and-value-remap).

**`switchDatasetMode`'s placeholder form depends on the target mode** - a numeric matrix (or `[]`)
for `Standard`, a cell array of file paths for `Virtual`/`BigData`. The cell form under `Standard`
puts a cell in `MibImage.data` and the next line is `intmax(class(obj.data))`. One copy of the rule,
in `ensureDatasetMode`; both the image branch and the crop branch go through it.

**`pixSize` must follow `ZarrLevel`.** Both setup loaders once updated `Height`/`Width`/`Depth` for
the selected level and left `pixSize` and `BoundingBox` at level 0, so a box and a voxel size
contradicted each other by 16x - and everything physical reads `pixSize` (scale bar, measurements,
the box a model is saved with). `OmeZarrMetadataUtils.applySelectedLevelGeometry` fixes it and is a
deliberate no-op at level 1, so a store carrying `mibBoundingBox` keeps winning.

**A programmatic `expand()` raises no `NodeExpandedFcn`** - only a click on the arrow does. The root
node must be filled by calling `treeNodeExpanded_Callback` directly before expanding it; deeper
nodes stay lazy on the real event.

**`ValueChangedFcn` on a `uieditfield` does not fire for text the user never edited**, and fires when
clicking away. Both wrong for the Enter-to-connect shortcut, so it lives in a figure-level
`WindowKeyPressFcn` that calls `drawnow` first to flush any pending commit.

**Never raise the Standard-mode level picker headlessly** - it stalls, and the stall looks like slow
I/O. One open took 324 s, of which the loader was 7.7 s; with `ZarrLevel` set it was 11.7 s. A
remote-only slowdown that survives a local repro of the same size is not I/O.

**`createModel` ignores material names above type 255** (its docblock says so; line 204 sets
`{'1';'2'}`). A 65535-material model is numeric by design. Do not promise names there.

**Do not commit URLs of non-public stores.** `RemoteStoreTest` reads one from
`MIB3_S3COMPATIBLE_ZARR_URL` and skips when unset; docs use `https://HOST/BUCKET/store.zarr`. Only
the public OpenOrganelle bucket (`janelia-cosem-datasets`) is named in tracked files.

---

## `io.RemoteStore`

```matlab
tf   = io.RemoteStore.isRemote(path)        % http:// https:// s3://
url  = io.RemoteStore.normalise(path)       % s3://b/k -> https://b.s3.amazonaws.com/k
info = io.RemoteStore.parse(path)           % .bucket .key .listEndpoint .listable .flavour .url
[childUrls, childNames, fileNames] = io.RemoteStore.listChildren(url, options)
tf   = io.RemoteStore.exists(url)
data = io.RemoteStore.readJson(url, timeoutSeconds)   % [] on any failure
url  = io.RemoteStore.join(baseUrl, relativePath)
rel  = io.RemoteStore.relativePath(rootUrl, url)
```

URL forms, in order: `s3://B/K`; `https://B.s3.amazonaws.com/K`;
`https://B.s3.<region>.amazonaws.com/K` (also `s3-<region>`); `https://s3[.<region>].amazonaws.com/B/K`;
then a generic `https://HOST/BUCKET/KEY` rule with the endpoint taken from the URL, flavoured
`'s3compatible'`.

**Listing is not Amazon-only.** The AWS host patterns exist only to tell Amazon's two spellings
apart (bucket in the host vs bucket in the path); nothing about `ListObjectsV2` is Amazon-specific,
and MinIO-style hosts serve ordinary `ListBucketResult`. Guessing wrong is free: a host that does not
speak the API returns no listing, `listChildren` reports empty rather than erroring, and
`probeRemoteZarr` falls through to marker probes. The one place it mattered was the dialog showing a
tree that could never fill, so `connectBtn_Callback` confirms a non-`'s3'` flavour against the root
listing (already cached by the version probe) and degrades to manual group entry.

The remaining hardcoded `amazonaws.com` is in `normalise`, expanding the `s3://` shorthand - correct,
since the scheme carries no host. Google Cloud Storage uses the marker-based v1 XML API and is
deliberately `listable = false`.

`listChildren` calls `webread` with `list-type=2`, `delimiter=/`, `prefix=[key '/']`,
`max-keys=1000`, and loops on `IsTruncated` / `NextContinuationToken`. **Do not hand-encode the
prefix** - MATLAB's own `%2F` encoding is accepted. Parsing is `matlab.io.xml.dom.Parser`.
`options.fetchFcn` is a test seam for driving truncation offline. Listings are memoised per session
in a `persistent` dictionary keyed by prefix - a *listing* cache, not a chunk cache. On
`<Code>PermanentRedirect</Code>` parse `<Endpoint>`, retry once, then degrade to not-listable.

Three things make `OmeZarrMetadataUtils.findMultiscalesGroups`'s recursive walk usable, all measured
and all still load-bearing:

1. **Test a whole level before expanding any of it.** Expanding as you go lists siblings of a match
   moments before the walk would have stopped - on OpenOrganelle that meant probing all 42 crops.
2. **`exists` does not retry a clean 404 as a ranged GET**, only a genuine method refusal
   (400/405/501). The walk is mostly negative probes.
3. **`readJson` fetches as text and decodes locally.** Object stores serve `.zattrs` as
   `binary/octet-stream`, so asking `webread` for JSON meant a retry on every miss. Classifying a v2
   child needs only a `.zgroup` probe - an array never has one.

`exists` uses `matlab.net.http` HEAD with a 5 s connect timeout, falling back to
`GET Range: bytes=0-0` accepting 200/206.

**Local behaviour is deliberately different and a test pins it:** locally the walk collects matches
at *every* depth, because each step is a `dir()` call. Only the remote walk stops at the shallowest
matching level.

---

## Geometry: the half-voxel trap

OME translations are **pixel-centre** based (the proof is inside the pyramid: s1's translation is
exactly half s0's scale), and `MibImage.boundingBox` is centre-based too (`updateBoundingBox.m:91-93`
computes `(dim-1)*pixSize`). It does **not** follow that the mapping is direct. Mapping one *grid*
onto another is an alignment question, and **alignment only exists in edge space.**

crop1's first voxel centre is `x = 25863 nm` on a 2 nm grid; `25863 / 4 = 6465.75`, which reads as a
misaligned store. Its *edge* is `25862 nm`, the EM 4 nm grid's first edge is `-2 nm`, and
`(25862 + 2) / 4 = 6466` exactly. The grids do line up; centre space hides it.

So two conventions coexist deliberately:

| | Convention | Units |
|---|---|---|
| `MibImage.boundingBox`, `worldBoundingBox` | voxel **centres** | the store's own (nm here) |
| `BatchOpt.Region`, `outerBoundingBox` | voxel **edges** (outer extent) | **micrometres** |

`Region` is in micrometres because it is compared across pyramids that may declare different units.
Bounding boxes stay in store units because MIB's own default box already is, so a derived box stays
drop-in interchangeable. **`OmeZarrMetadataUtils.outerBoundingBox` is the single conversion point**
and its docblock carries the crop1 numbers.

`OmeZarrWorldGeometryTest.cropAndEmGridsAlignOnlyInEdgeSpace` pins it by asserting the centre-space
index is **not** integral and the edge-space one is.

`regionToVoxelRange` rounds outward with a grid tolerance and returns a residual;
`regionReport.message` names any overshoot in um. Floating point matters here: `3133.52 / 5.24` is
`597.99999...` in binary and a bare `floor` loses a voxel.

An absent `Region` is a no-op by construction - `applyRequestedRegion` returns its inputs unchanged
with `levelRegionOrigins` all ones, `readLevelRegionV2/V3` calls the same plain `read()`, and
`getDataZarr` adds an offset of zero. `ZarrRegionReadTest` pins the uncropped open as byte-identical.

---

## The open routes

`BatchOpt`: `Url`, `GroupPath`, `LoadAs` (`Image`/`Labels`), `DatasetMode`
(`BigData`/`Virtual`/`Standard`), `ImageGroupPath`, `Region`, `ZarrLevel`,
`MergeInstanceObjects` (default **false**), `showWaitbar`, `id` from `getActiveId()`.
Batch mode never touches the tree - it goes straight from `Url` + `GroupPath` to
`loadImages`/`loadModel`, so a recorded protocol replays with no network browse. Keep
`buildLoadImagesBatchOpt` a pure function so the mapping is assertable offline.

Deliberately do **not** set `mibBatchTooltip` in the forwarded options - that keeps
`batchModeSwitch = 0` so the Standard-mode level picker still appears for an ordinary open.

**Image.** `ZarrGroupPath` flows through `loadImages` into `options`, which
`io.LoaderFactory.create` and `loader.loadMetadata` already receive. Free side benefit: the batch
load action can open a nested group of a **local** container without the picker. Virtual and BigData
read through the *same* path (`MibVirtualImage.getDataZarr`), so BigData's only added value is the
editable local model store.

**Labels onto a matching image.** Ordinary `loadModel`. Requires the label store's level 0 to match
the image dims exactly.

**Label crop + its image region.** When a label group's extent is smaller than the open image,
fetching the crop *region* - EM sub-volume as the image, selected label groups as the model - avoids
the three blockers that make a true sub-volume overlay impossible (see [Not
done](#not-done-deliberately)). After cutting, the dims match exactly.

- `resolveSiblingImageGroup` walks to the container root and takes the multiscales group whose world
  box contains the crop's **and whose path has no `labels` component**. The path test is not
  optional: `crop1/all` is a genuine multiscales pyramid carrying no `cellmap` block that encloses
  the crop exactly, so containment-plus-no-annotation selects the merged ground truth instead of the
  image. Rejecting on path also keeps the walk cheap - all 26 crops are rejected without a metadata
  fetch.
- `imageBoxContains` needs **two** tolerances: half the candidate's voxel, *and* one label voxel. A
  label pyramid published as a rounded-up downsample overshoots its image (`18500/16` rounds to 1157,
  claiming 74048 nm against 74000). The label tolerance is passed in, not derived.
- `planLabelCrop` searches image levels **from the finest**, so a ground-truth crop still pairs at
  image `s0` (pinned by `theCropPlanStillPrefersTheFinestImageLevel`) while a coarse label pyramid
  falls through to the level that matches. It asserts the two shapes agree and **never resamples**.
- It **refuses a pair it cannot hold in RAM**, because the crop route is Standard-mode by
  construction. The ceiling is an optional argument with a machine-derived default (60% of
  `MemAvailableAllArrays`, or 8 GiB where `memory` is unavailable) so tests pass an explicit limit and
  the verdict is deterministic. Since `plan_url_s3_labels_mismatch.md` Stage A the mode is refused
  honestly rather than overridden, and Stage C gives the coarse-pyramid case a real BigData answer -
  so a refusal here now means "use the overlay route", not "no route exists".
- The refusal surfaces in the info panel with Open disabled, not at Open, because
  `resolveLabelRoute` calls the planner while the user is still choosing. `applySummary` splits a
  reason on newlines.
- Model composition does **not** go through `loadModel` - blending N groups into one index map is not
  something a one-store-one-model loader can express, so the controller composes and assigns directly
  (`createModel` + `setData3D`).

**A `Match` line plus a green bold tree node** say whether the selected group's finest level matches
the open dataset, while the user is still choosing. Both halves are needed: the colour is the glance,
the line names the size the open dataset actually has. Only the *selection* is marked and the
previous mark is cleared each time - marking siblings means a metadata request each. Recomputed per
selection rather than cached in `probeGroup` (which is keyed by URL for the session), because the
active buffer can change underneath it.

**Pre-fill prefers the open dataset over the clipboard.** `openRemoteContainer` splits
`I{activeId}.image.filename` at the last component naming a store (`.zarr`, `.zarr2`, `.zarr3`,
`.n5`): container becomes `Url`, remainder `GroupPath`. The split is the point - the stored filename
is the *group* URL, so connecting to it whole roots the tree at the image group and the labels next
door are unreachable. It must **not** fire in batch mode (a protocol naming a `Url` but no
`GroupPath` would inherit whatever is open and replay something it never asked for), and a local
file, `none.tif` or a plain image URL all fall back to the clipboard. A pre-filled URL
**auto-connects** - that container is known reachable and known to be a zarr store. A clipboard URL
deliberately does not.

**Degradation is implemented, not just documented.** Most non-AWS hosts are not listable: hide the
tree, enable manual `GroupPath` entry, relabel the button to "Probe", run the same `probeGroup`
against `join(rootUrl, GroupPath)`.

---

## Label decoding and value remap

`resolveValueRemap` decides at open time how a store's values map onto materials:

| Store | Mapping | Materials |
|---|---|---|
| declares `cellmap` encoding | `present` -> 1, everything else -> 0 | one, named by `class_name` |
| binary, declares nothing | any non-zero -> 1 | one, named after the group folder |
| index map inside 1-63 | unchanged | `loadModel`'s 63 slots |

- **`unknown` (255) must reach background, not a material.** It means "not annotated here", so
  treating it as the class teaches anything trained on the result that unlabelled tissue is positive.
  `composeLabelModel` applies the same rule on the crop route.
- **Telling a binary mask from an index map needs pixels**, so the coarsest level is read whole - a
  few tens of kilobytes, one request. When it comes back empty (a thin structure often is after eight
  downsamplings), assume binary: it is the reading that cannot corrupt the mask and selection layers,
  and an index map dense enough to be worth its ids survives downsampling.
- The remap is applied **after** `ChunkCache`, so the cache holds raw chunks keyed by level path and
  a store opened both as image and as labels shares them.

**Index-map materials are named by the store's own id** (`all_3`, `all_28`), deliberately **not**
looked up in the crop's `class_names` - `all` ids are a canonical COSEM table, not the `class_names`
order (`cyto` is 35), so indexing that list by id mislabels every material.

**Instance groups are kept as objects by default**, one material per object named by the store's id.
The old rule "an instance group must never be blended into a material index map" was written about
the **BigData packed 63-material** store, where there is no room; this route builds an ordinary
in-memory model and `createModel` takes up to 4294967295, so 864 objects fit easily. Merging into one
material is offered as the alternative (hundreds of Segmentation-panel entries are their own
problem), asked by `confirmInstanceMerge` only where there is a window. Keeping is lossless so it
needs no consent; headless and batch take it silently. `BatchOpt.MergeInstanceObjects` defaults
false, so a protocol recorded before this refuses rather than merging - consent is not inferable from
silence. `composeLabelModel` errors past 65535 naming the merge as the way out.

Materials are numbered 1..N in the store's id order, **not** by the store's own ids, which need not
be contiguous. Preserving ids would be more faithful; it is not done because ids from two instance
groups would collide and the material accounting is per-index throughout.

**Composition is O(volume), not O(classes x volume).** One mask per class (`block == classValues(k)`)
is invisible at 3 classes and 375 s at 864; a value -> material lookup applied one slice at a time is
53 s. The overlap bookkeeping is a sparse later-x-earlier accumulation, pinned by
`overlapBetweenGroupsIsCountedPerPairInPickOrder` - attributing overlap to the wrong earlier material
is exactly the kind of error that looks fine.

**Overlap is reported after composition, not predicted.** Counting overwritten voxels while blending
is exact and free; guessing from class names cannot see how the crop was annotated. Empty classes are
reported the same way rather than greyed out in the picker, which would need 63 speculative downloads
per crop.

---

## The chunk cache

`io.zarr.ChunkCache` caches whole decoded chunks in an LRU against a byte budget
(`Prefs.IO.Zarr.ChunkCacheMB`, default 512 MB, 0 disables). It works in Zarr's **C-order index
space**, so one implementation serves both the v2 (zarr-python) and v3 (native zarrMex) loaders -
which is also why it lives in MIB rather than in fsspec, since remote v3 never touches Python.

Two design points:

- **Whole chunks, not whole requests.** Caching the request fixes scrubbing and does nothing for
  panning. Chunk granularity means a viewport shifted by less than a chunk re-uses everything.
- **All missing chunks of a request are fetched in one call over their bounding box**, never one call
  per chunk. The engines fetch concurrently, so one call for N chunks beats N calls for one. The
  bounding box may re-pull a few cached chunks; far cheaper than a second round trip.

Remote viewing is **bandwidth**-bound, not latency-bound, and the whole cost is z-overfetch: with
`[64,128,128]` chunks, reading 64 slices costs the same as reading 1. That is what the cache exists
to reclaim. Full-resolution viewing of a large store is not viable regardless - one s0 XY slice can
span ~31k chunks - so the pyramid plus fast-pan (auto-enabled when `imginfo` has a `Pyramid` key,
`loadImages` line 483) is what makes this usable.

**Local zarr uses the cache too.** There is no `isRemote` gate anywhere: `Zarr2VirtualLoader.m:156`
and `Zarr3VirtualLoader.m:193` wrap their engine read unconditionally, and
`initializePreferences.m:196` applies the budget process-wide at startup.
`MibBigDataLabelsZarr2.readPackedLevel` is cached too, keyed on `modelLevelPaths`, safe without
invalidation because that store is read-only by construction (`writePackedLevel` errors).

**`MibBigDataLabels` is deliberately NOT cached.** This is the editable store MIB writes during
segmentation, and a read cache over it is a **data-loss** hazard, not merely staleness:
`setData63.m:113` is a read-modify-write, so a stale read means the pre-stroke copy is written back
**to disk**, destroying earlier strokes. The pyramid compounds it - `MibBigDataLabels.m:494` rebuilds
coarser levels from finer, so one stroke would have to invalidate every level `markTiles` touches.
The reward does not justify it: the model store inherits the *image's* chunk shape (default
`[256 256 16]`, so 16x overfetch not 64x), label indices compress far harder than EM noise, and the
cost is decode rather than I/O - an estimated ~20 ms per screenful.

**If it is ever revisited, build evict-on-write only**: `ChunkCache.invalidate(cacheKey, region)`
called from `writePackedLevel` for the level written and every coarser level `markTiles` touches.
Correct by construction - after a write the affected chunks are simply gone. **Write-through**
(patching the RAM copy) keeps the cache warm mid-stroke but can corrupt a store if the chunk-boundary
arithmetic is wrong, since brush strokes are not chunk-aligned. Never the first attempt. Gate for
revisiting: scrub Z with *Show model* on, then off; under ~15% difference, close the question.

`ZarrChunkCacheTest` asserts **values**, not shapes - a synthetic array whose every element encodes
its own coordinates, over 40 random bboxes, because an off-by-one when splitting a fetched block
would silently shift pixels rather than fail loudly. Deliberately **no** timing baseline: the
meaningful invariant is "16 slices in one chunk block provoke exactly one engine call", asserted by
counting calls, which is stable offline.

The `ChunkCacheMB` widget's callback is attached in `Preferences.updateWidgets`, **not** in App
Designer - assigning `ValueChangedFcn` replaces rather than adds, so wiring it in the designer later
cannot double-fire. The render also forces `Limits = [0 Inf]`; it was drawn `[1 Inf]`, which made the
documented "0 disables" unreachable.

---

## Python, and the native engine

**No python is required for any zarr dataset.** `zarrMex` reads v2 and v3, local and remote
([`plan_native_zarr2.md`](plan_native_zarr2.md)). Everything below applies only when the `python`
backend is deliberately selected in `Preferences -> Input/output -> Zarr library`.

With that backend, remote **v2** needs `aiohttp` + `requests` beyond what local v2 requires - fsspec's
`HTTPFileSystem` imports them lazily and the failure otherwise arrives only on the first pixel read.
`io.zarr.PyBackend.ensureRemoteSupport` fails fast at open time instead, throwing
`io:zarr:PyBackend:remoteDepsMissing` naming the configured interpreter and the exact pip command.
`openArray` translates the raw python error to the same identifier when the message contains
`aiohttp` or `HTTPFileSystem requires`; everything else rethrows.

**A dead interpreter and missing packages are different diagnoses.** `hasRemoteSupport` returns a
second output, `diagnostic`, and a terminated process raises `io:zarr:PyBackend:pythonTerminated`
saying "not running" and telling you to restart - deliberately with **no** `pip install` advice.
Without the split, a process killed by `clear classes` was reported as "aiohttp is missing", sending
the user after the wrong problem.

**`s3fs` is deliberately not required** - normalising `s3://bucket/key` to
`https://bucket.s3.amazonaws.com/key` means public buckets are reached over anonymous HTTPS: no
credentials, no region config, no extra dependency.

**The native engine can refuse a store it should read.** `io.zarr.Array` falls back to `PyBackend`
for **that array** and says so once. Three properties of the mechanism are worth keeping:

- **Triggered by a failure, not predicted.** Loader metadata comes from `.zarray` as plain JSON and
  never fails, so nothing before the first pixel read knows the codec is a problem. Probing at open
  time costs a request per level to answer a question almost always "no".
- **Keys on the message, not the identifier.** Every store-level engine failure is `zarr:error`, so
  `isCodecUnsupported` matches the words serde uses when refusing a configuration. A missing array
  stays a missing array - rerouting it would replace a clear error with a slower one and hide it
  where python is absent. `unrelatedNativeFailuresAreNotReroutedToPython` covers the half that can do
  damage (a false positive rerouting a network error); the uncovered half fails safe to the raw
  engine error.
- **No python, no silence.** When the interpreter cannot take over, the error names both the refused
  codec and why python was unusable, as one `io:zarr:Array:codecUnsupported`.

> The original trigger (`checksum` in a zstd config) was retired 2026-08-15 when `zarrMex` learned
> the field. **A replacement fixture cannot be manufactured**: any field invented to keep the engine
> refusing is equally unknown to numcodecs, so python rejects it too (measured both ways). A working
> fixture needs a field numcodecs accepts and the engine does not - precisely the unanticipated
> real-world divergence. The two tests that needed one were deleted; the mechanism stays.

`Zarr3VirtualSetupLoader` still opens `ZarrArray` directly in three places (lines 395, 672, 928) and
would hit the same wall on a **v3** store with an unfamiliar codec field. Left alone deliberately -
routing those through the facade would change where v3 metadata comes from.

---

## Not done, deliberately

**A true sub-volume overlay** - placing a 200³ label island inside a 25-gigavoxel BigData volume.
Three independent blockers: `loadModel` rejects any store whose level-0 dims differ from the image
dims; `MibBigDataLabelsZarr2` has no origin concept (`openStore` sets `height/width/depth` from the
label store itself and `readPackedLevel` maps limits straight onto the array, with nowhere to put a
translation and no zero-fill outside the crop); and `openStore` normalises `modelScaleFactors`
against the label store's *own* level 0, so a 4 nm label pyramid against an 8 nm image would pick
levels off by one everywhere - a silent 2x scale error, worse than a hard failure. Needs
`originYXZ` + `imagePyramidRef`, level picking by *absolute* scale, intersect-and-zero-pad in
`readPackedLevel`, and a relaxed dims guard. The crop route exists because it avoids all three.

**A label store smaller than its image**, e.g. an inference result at `[8500 8050 8000]` against
`[8501 8050 8000]`. Supporting it means zero-padding the difference, which is a data-integrity
decision (how much smaller is a rounding artefact and how much is the wrong store?).

**`ImageGroupPath` has no widget**, so the resolved image group is reported in the info panel and the
override is batch-only. Drawing an edit field named exactly `ImageGroupPath` on the canvas finishes
it - `updateGUIFromBatchOpt_Shared` skips BatchOpt fields with no matching property. Same reason
`showWaitbar` has no widget: the dialog always shows progress and the field exists only so a protocol
can suppress it.

**`MibBigDataLabels.createStore` mirroring a 15-level Janelia pyramid** is unverified. Arrays are
metadata-only until written and the level map lives on the tiny coarsest level, but nobody has
created a store with a `49645 x 21451 x 23601` declared level 0. Verify before shipping
BigData-on-remote.

**Region redirects, requester-pays and private buckets** - handled by the one-shot `<Endpoint>`
retry, unverified, degrades to not-listable.

**`obj.id` vs `BatchOpt.id` at `loadImages` line 258** is pre-existing. The dialog sidesteps it by
only using `getActiveId()`. Do not "fix" it here.

---

## Verification

`buildtool check` and `buildtool test` clean. Offline suites cover the full URL table, XML parsing
and the continuation loop (via `options.fetchFcn`), `join`/`relativePath` never using `fullfile`,
format detection against temp local v2/v3 folders, geometry against embedded `.zattrs` samples
including a no-translation store and the 5-axis `tczyx` case, region arithmetic, and composition of
overlapping and instance groups from synthetic arrays. Network tests self-skip via
`mibtest.helpers.hasNetwork`. Per `tests/CLAUDE.md`: `mibtest.fixtures.MibPathFixture` in
`TestClassSetup`, fresh synthetic model per method, `DeveloperMode = false`.

Invariants worth knowing:

- An uncropped open is **byte-identical** with and without `Region` (`ZarrRegionReadTest`).
- The chunk cache returns identical pixels with and without, and a chunk block provokes exactly one
  engine call.
- `cropAndEmGridsAlignOnlyInEdgeSpace` - centre-space index not integral, edge-space integral.
- `theCropPlanStillPrefersTheFinestImageLevel` - a coarse label pyramid must not change crop pairing.
- `switchingABufferBackToStandardWorks` - Standard -> Virtual -> Standard yields an integer class,
  not a path.
- `anInstanceGroupBecomesOneMaterialOverEveryObject`, with the same block *without* the instance
  declaration splitting into four materials, so the merge assertions cannot pass on another path.
- `overlapBetweenGroupsIsCountedPerPairInPickOrder`.
- The remap table above has one test per row, each asserting no mask or selection bit is set.

Two lessons from tests that missed real faults:

- **A test that drives a callback directly cannot tell you the callback is wired up.** The tree-hang
  bug survived because the integration test called `treeNodeExpanded_Callback` itself - exactly the
  step the GUI was failing to perform. It now asserts the root arrives already listed before walking.
- **Vary the fixture, not the source under test.** Checking a branch by temporarily breaking it in
  the source left the file broken when the MCP connection dropped mid-run.

**Alignment is verified by comparing declared geometry, never by intensity contrast.** Mean EM
intensity inside a label mask against outside looks like confirmation until the mask is shifted: at
10, 30, 60 and 120 px the separation stayed 28.7-29.4. Large blobs cannot see misregistration at all.
A prevalence-matched Dice peaks cleanly in y but is non-decisive in x where nuclei repeat. Where the
geometry is exact by construction, assert the world box, shape and voxel size come back bit-identical
to the source array's.

**Still to be clicked through in a running MIB:** multi-select on the tree, the crop message in the
info panel, and the post-load report - covered headlessly only. The tree's `Multiselect` is set in
`addCallbacks` rather than on the canvas, which is the most likely thing to behave differently under
a real AppContainer. Also worth a manual pass: the `s3://` rewrite, a plain image URL keeping the old
`imread` behaviour, and the model-store dialog starting in a local folder rather than a URL.
