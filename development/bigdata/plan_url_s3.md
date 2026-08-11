# Plan: open remote OME-Zarr datasets from a URL (S3 / HTTPS)

**Status:** implemented through step 16.
Written 2026-08-10, last updated 2026-08-11.
Steps 0-11 are tracked in the [ordered sequence](#ordered-sequence) table; steps 12-16 are prose
sections following it.
**Supersedes:** the deferred "Remote OME-Zarr over HTTP/URL" item in
[`bigdata_implementation_plan.md`](bigdata_implementation_plan.md) (§5, item 5).

## Context

MIB3 can only open Zarr stores on a local or mounted filesystem. Public EM repositories -
Janelia OpenOrganelle, IDR, MoBIE - publish OME-Zarr in public cloud buckets, and there is
no way to point MIB at one. `Home -> Import -> URL` exists but routes to `imfinfo`/`imread`,
so it handles single ordinary image files only.

Goal: paste a store URL, browse the group tree, and open it as a **BigData** dataset so a
multi-terabyte remote volume can be viewed at any pyramid level and segmented, with the
model store written locally.

### The reference dataset

`https://openorganelle.janelia.org/datasets/jrc_mus-liver-zon-1` is served from the public,
anonymously readable bucket `janelia-cosem-datasets` (us-west-2):

- `s3://janelia-cosem-datasets/jrc_mus-liver-zon-1/jrc_mus-liver-zon-1.zarr`
- HTTPS: `https://janelia-cosem-datasets.s3.amazonaws.com/jrc_mus-liver-zon-1/jrc_mus-liver-zon-1.zarr`
- image group nested at `recon-1/em/fibsem-uint8` - Zarr **v2**, 15 levels `s0..s14`,
  `s0` = `[49645, 21451, 23601]` (z,y,x) uint8, chunks `[64,128,128]`, zstd,
  `dimension_separator: "/"`, axes z,y,x at 8 nm

### Verified live, no code changes

Running the existing loader against the group URL in MATLAB R2026a already returns the
full pyramid:

```
H=21451  W=23601  D=49645  class=uint8  axisOrder=zyx  levels=15  objectType=zarr2
```

Also verified: anonymous `GET` = 200 and `Range` = 206 on the bucket; `webread` +
`matlab.io.xml.dom.Parser` parse a `ListObjectsV2` response correctly from MATLAB;
`Zarr2VirtualSetupLoader` / `Zarr3VirtualSetupLoader` already have `isHttp` branches;
`Zarr2VirtualLoader.readRegion` already joins URL paths with `/`; `io.zarr.Array` already
forces the native `zarrMex` backend for HTTP.

### The four things that actually block it

1. `Home -> Import -> URL` never reaches the zarr loaders.
2. `ExtensionRegistryLoad.detectZarrFormatExtension` probes with `isfile()`, so it cannot
   see a URL and silently falls back to `'zarr3'` - a Janelia **v2** store is handed to the
   v3 loader, which cannot read it.
3. `OmeZarrMetadataUtils.findMultiscalesGroups` bails out on `http`/`https` because it
   cannot list a directory, so nested `recon-1/em/fibsem-uint8` is never found from the root.
4. Zarr v2 pixel reads go through `zarr-python`, which needs `aiohttp` + `requests` for
   remote stores. Verified failure surface: `MATLAB:Python:PyException` /
   `ImportError: HTTPFileSystem requires "requests" and "aiohttp" to be installed`.
   (Remote **v3** needs no python at all - `zarrMex` does Range reads.)

### Decisions taken

- Navigation: **lazy browser dialog**, one S3 LIST per expand. No eager recursive search -
  the label subtree alone is 42 crops x ~40 classes.
- Entry point: **extend the existing `Home -> Import -> URL` item**; the dialog also offers
  what to load the data as - **Image** or **Labels**.
- **No chunk caching** in this work.

---

## Step 0 - de-risking spike: **DONE, passed (2026-08-10)**

The load-bearing assumption was that `zarr-python` 3.3 can actually **read** this store over
HTTPS once `aiohttp` is present - v2-under-zarr3, zstd, `dimension_separator "/"`. Verified
against the live bucket through the existing `io.loaders.Zarr2VirtualLoader`, real pixel data
returned, no code changes:

| Read | Time | Note |
|------|------|------|
| `s7` 128x128 | 2.43 s | cold; includes fsspec/aiohttp session setup |
| `s5` 512x512 | 1.43 s | |
| `s3` 512x512 at volume centre | 1.23 s | |
| `s0` 512x512 at volume centre | 1.91 s | full resolution, `mean=171.8`, 100% non-zero |
| `s0` 512x512 at the **next z slice** | 1.49 s | same chunk re-fetched from scratch |

Two things to carry into the docs and into any later caching decision:

- Cost is **latency-bound, not bandwidth-bound** - roughly 1.2-1.9 s per 512x512 tile at
  *every* pyramid level. Level choice barely changes the per-tile cost; it changes how many
  tiles a view needs.
- The last row is the no-cache penalty made concrete: stepping one z slice inside the same
  `[64,128,128]` chunk costs a near-full re-fetch. This is the strongest argument for
  revisiting the "no chunk caching" decision once the feature is usable.
- Reads outside the imaged region are near-free (unstored chunks return `fill_value` without
  a download), so benchmark at the volume centre - a corner read reports a misleadingly fast
  0.66 s.

---

## Python prerequisite (carry into user docs)

> **Superseded 2026-08-11 by [`plan_native_zarr2.md`](plan_native_zarr2.md).** `zarrMex` now reads
> zarr v2, local and remote, so **no python is required for any zarr dataset**. Everything below
> applies only when the `python` backend is deliberately selected in
> `Preferences -> Input/output -> Zarr library`. The blocker numbered 4 in the section above is
> likewise retired.

Remote **Zarr v2** stores - which is what OpenOrganelle, MoBIE and most published OME-NGFF
v0.4 data are - need two packages **beyond** what local zarr v2 already requires, in the
interpreter set at `Preferences -> External directories -> Python installation path`:

```bash
"<python.exe>" -m pip install aiohttp requests
# or:  conda install -n <env> -c conda-forge aiohttp requests
```

`zarr-python` reaches remote stores through fsspec's `HTTPFileSystem`, which imports these
lazily; without them the failure is `MATLAB:Python:PyException` /
`ImportError: HTTPFileSystem requires "requests" and "aiohttp" to be installed`, raised only
on the first pixel read. Step 3 turns that into an actionable message at open time.

**`s3fs` is deliberately not required.** Normalising `s3://bucket/key` to
`https://bucket.s3.amazonaws.com/key` (Step 1) means public buckets are reached over ordinary
anonymous HTTPS, so there is no credential handling, no region configuration and no extra
dependency. Verified installed and working on this machine:
`zarr 3.3.0, fsspec 2026.4.0, aiohttp 3.14.3, requests 2.34.2, numcodecs 0.16.5` (no `s3fs`).

Remote **Zarr v3** needs none of this - `io.zarr.Array` forces the native `zarrMex` backend
for HTTP and it does its own Range reads.

---

## Implementation

### 1. `mib/+io/RemoteStore.m` (new)

Static-only helper, same shape as `io.ExtensionRegistryLoad`. Object-store plumbing, no
zarr knowledge.

```matlab
tf   = io.RemoteStore.isRemote(path)        % http:// https:// s3://
url  = io.RemoteStore.normalise(path)       % s3://b/k -> https://b.s3.amazonaws.com/k
info = io.RemoteStore.parse(path)           % .bucket .key .listEndpoint .listable .flavour .url
[childUrls, childNames, fileNames] = io.RemoteStore.listChildren(url, options)
tf   = io.RemoteStore.exists(url)
data = io.RemoteStore.readJson(url, timeoutSeconds)   % [] on any failure
url  = io.RemoteStore.join(baseUrl, relativePath)     % '/'-join, never fullfile
rel  = io.RemoteStore.relativePath(rootUrl, url)
```

URL forms recognised, in order: `s3://B/K`; `https://B.s3.amazonaws.com/K`;
`https://B.s3.<region>.amazonaws.com/K` (also `s3-<region>`);
`https://s3[.<region>].amazonaws.com/B/K`; anything else http(s) sets `listable = false`.
Google Cloud Storage uses the marker-based v1 XML API - mark it `listable = false` in v1
and say so in the docs rather than half-supporting it.

`listChildren` calls
`webread(info.listEndpoint, 'list-type','2', 'delimiter','/', 'prefix',[key '/'], 'max-keys','1000', weboptions('ContentType','text','Timeout',30))`.
Do **not** hand-encode the prefix - MATLAB's own `%2F` encoding is accepted by S3
(verified). Loop on `IsTruncated` / `NextContinuationToken`.

Parsing: `matlab.io.xml.dom.Parser().parseString(...)`, verified working. Iterate the
**`CommonPrefixes`** elements and take each one's child `Prefix` - do **not** iterate the
bare `Prefix` tag, because the response echoes the request prefix under that name and it
would be picked up as a phantom child. Files come from `Contents` -> `Key`.

Add `options.fetchFcn` (default the real fetcher) as a seam so unit tests can drive
truncation and continuation offline. Memoise listings per session in a `persistent`
dictionary keyed by prefix - this is a *listing* cache, not a chunk cache, so it stays
inside the "no caching" decision. On `<Code>PermanentRedirect</Code>` parse `<Endpoint>`
and retry once, then degrade to `listable = false` rather than erroring.

`exists` uses `matlab.net.http` HEAD with a 5 s connect timeout, falling back to
`GET Range: bytes=0-0` accepting 200/206 (HEAD from MATLAB is unverified; curl HEAD works).

### 2. URL-aware zarr version detection

**Implemented as described, with one deliberate change:** the new probe is a **public**
static `probeRemoteZarr(url)` rather than a private `detectRemoteZarrFormat`. It has to be
public because `resolveLoader` (and later `loadModel`, step 8) needs the **tri-state** return
- `'zarr2'` / `'zarr3'` / `''` - to tell "not a zarr store" apart from "a v3 store".
`detectZarrFormatExtension` keeps its two-state contract and its `'zarr3'` fallback, so every
existing caller is unaffected. A session cache plus `clearRemoteProbeCache()` was added
alongside.

`mib/+io/ExtensionRegistryLoad.m` - keep the existing `detectZarrFormatExtension(zarrPath)`
signature so all callers are unchanged, and add a remote branch at the top delegating to
`probeRemoteZarr(url)`:

1. session cache hit -> return
2. if `parse(url).listable`: **one** `ListObjectsV2` (`max-keys=20`) and inspect the
   basenames - `zarr.json` gives `'zarr3'`, `.zgroup`/`.zattrs`/`.zarray` give `'zarr2'`.
   Same request the browser dialog already makes.
3. else: `exists(url + '/zarr.json')` then the v2 markers, 5 s timeouts each
4. else `'zarr3'` (unchanged legacy default) plus a `DeveloperMode` note that the probe was
   inconclusive

In `resolveLoader`, reach the probe for extension-less remote roots - a bucket prefix need
not end in `.zarr`:

```matlab
if io.RemoteStore.isRemote(filename)
    if isempty(ext) || strcmp(ext, 'zarr')
        ext = io.ExtensionRegistryLoad.detectZarrFormatExtension(filename);
    end
elseif strcmp(ext, 'zarr')
    ext = io.ExtensionRegistryLoad.detectZarrFormatExtension(filename);   % existing line
end
```

An ordinary remote `.png` probes empty and keeps today's `imread` route.

### 3. Python dependency detection

`mib/+io/+zarr/PyBackend.m` is the right home - every remote v2 consumer funnels through
it. Two new statics:

```matlab
tf = io.zarr.PyBackend.hasRemoteSupport()          % non-throwing, cached per session
     io.zarr.PyBackend.ensureRemoteSupport(path)   % no-op for local paths
```

**Implemented with one addition found during testing.** `hasRemoteSupport` returns a second
output, `diagnostic`, and `ensureRemoteSupport` branches on it: a **dead interpreter** and
**missing packages** both make the check fail, but only one is fixed by installing anything.
Without the split, a Python process that had exited was reported as "aiohttp is missing",
sending the user after the wrong problem - which is exactly what happened here after a
`clear classes` killed the out-of-process interpreter (the hazard in `bigdata_logic.md` §12).
A dead interpreter now raises `io:zarr:PyBackend:pythonTerminated`, says "not running", tells
you to restart, and deliberately contains no `pip install` advice.

`hasRemoteSupport` runs `importlib.util.find_spec` for `aiohttp` and `requests` once.
`ensureRemoteSupport` throws `io:zarr:PyBackend:remoteDepsMissing` naming the configured
interpreter from `io.zarr.Config.pythonPath()`, the exact command
`"<exe>" -m pip install aiohttp requests`, the conda alternative, and the
`Preferences -> Input/output -> Python installation path` pointer. Also wrap `openArray`'s
`z.open` in try/catch and translate the raw python error to the same identifier when the
message contains `aiohttp` or `HTTPFileSystem requires`; rethrow everything else.

Call sites: `Zarr2VirtualSetupLoader.loadMetadata` right after the existing
`ensureLoaded()` (fail fast, once, at open time); `MibBigDataLabelsZarr2.openStore`; and
the dialog's Open handler, which checks before dispatching so the user is not sent through
a load only to fail.

### 4. Remote group resolution in the setup loaders

**Implemented, plus three performance findings that were not in the plan.** The recursive
search now runs for remote listable roots, so `findMultiscalesGroups` resolves the Janelia
image group from a bare store root. Getting it usable took three fixes, all measured:

1. **Test a whole level before expanding any of it.** The naive loop expanded each node as it
   went, so the siblings of a match were expanded moments before the walk would have stopped -
   on OpenOrganelle that meant listing `labels/groundtruth` and probing all 42 crops.
   **27.5 s -> 10.1 s.**
2. **`RemoteStore.exists` no longer retries a clean 404 as a ranged GET**, only a genuine
   method refusal (400/405/501). Every negative probe used to cost two requests, and the walk
   is mostly negative probes.
3. **`RemoteStore.readJson` fetches as text and decodes locally** instead of asking `webread`
   for JSON and retrying as text. Object stores serve `.zattrs` as `binary/octet-stream`, so
   the retry fired constantly and doubled the cost of every miss. Also, classifying a v2 child
   needs only a `.zgroup` probe - an array never has one, so the extra `.zarray` probe was
   pure overhead. **10.1 s -> 2.5 s**, about 15 requests.

Measured end to end: **2.5 s** to resolve the group from the store root, **5.0 s** for a full
`loadMetadata` from the root, **2.6 s** when `ZarrGroupPath` is supplied.

Local behaviour is deliberately unchanged and a test pins it: locally the walk still collects
matches at **every** depth, because each step is a `dir()` call. Only the remote walk stops at
the shallowest level that matches.

Both setup loaders previously fell back to a blind probe of
`{'0','1','s0','s1','cells','nuclei'}` for HTTP roots. Replace that with a real
`io.RemoteStore.listChildren` walk when the host is listable.

Both already honour `options.ZarrGroupPath`, but the HTTP branch reads
`if isHttp || isfolder(requestedGroup); groupPath = requestedGroup;` - which only accepts an
absolute URL. Relax it so a relative path works too, since that is what a human writes into
a protocol:

```matlab
if isHttp
    groupPath = io.RemoteStore.join(rootPath, requestedGroup);
elseif isfolder(requestedGroup)
    ...
```

### 5. `ZarrGroupPath` through `loadImages`

`mib/+models/@MibModel/loadImages.m`:

1. after line 85, `BatchOpt.ZarrGroupPath = '';` plus its `mibBatchTooltip`
2. in the "Define additional options" block (~line 213), forward it into `options` when
   non-empty

`options` is what `io.LoaderFactory.create` and `loader.loadMetadata` already receive. Free
side benefit: the existing batch load action can then open a nested group of a **local**
container without the picker.

The URL survives because `loadImages` line 133 takes the `else` branch when `BatchOptIn`
carries `Filenames` and does no path joining - the `fullfile(BatchOpt.DirectoryName{1}, ...)`
calls only run on the no-`Filenames` paths. This matters: `fullfile` would mangle
`https://host/group` into `https://host\group` on Windows.

**Milestone reached (2026-08-10).** A headless remote open works end to end through
`MibModel.loadImages`, verified against the live OpenOrganelle store:

| Path | Time | Result |
|------|------|--------|
| Open with `ZarrGroupPath` (batch form) | 2.8 s | `BigData`, `[21451 23601 49645 1 1]`, 15 levels, 8 nm, no pixels in RAM |
| Open from the bare container root | 5.1 s | resolves `recon-1/em/fibsem-uint8` by itself |
| `getData2D`, zoomed out (`magFactor` 32) | 1.9 s | 670 x 737 from level `s5` - the pyramid is doing its job |
| `getData2D`, 512x512 at full resolution | 1.1 s | mean 171.8, matching a direct `PyBackend` read of the same region |

That last row is the useful cross-check: the value agrees with a raw read taken outside the
MIB stack, so the level selection, physical-to-level coordinate mapping and axis permutation
are all correct end to end, not merely self-consistent.

The UI comes after.

### 6. The browser dialog

- **View:** `mib/+views/SelectFromUrlGUI.mlapp`
- **Controller:** `mib/+controllers/@SelectFromUrl/` - `SelectFromUrl.m`, `addCallbacks.m`,
  `updateWidgets.m`, `connectBtn_Callback.m`, `treeNodeExpanded_Callback.m`,
  `treeSelectionChanged_Callback.m`, `probeGroup.m`, `openBtn_Callback.m`,
  `openPlainImageUrl.m`, `buildLoadImagesBatchOpt.m`

Named `SelectFromUrl` rather than anything zarr-specific because it also handles plain
image URLs.

BatchOpt-mapped widgets must be named exactly as their field: `Url`, `GroupPath`, `LoadAs`,
`DatasetMode`, `showWaitbar` (lowercase, per the documented exception). Non-BatchOpt
widgets use descriptive lowerCamel: `connectButton`, `groupTree`, `infoTextArea`,
`statusLabel`, `openButton`, `closeButton`, `helpButton`. `core.ChildView.getChildren`
already recurses into `uitree`.

**Connect:** normalise the URL and write it back so the user sees the `s3://` rewrite; probe
the format; if no zarr metadata but `imfinfo` succeeds, switch to plain-image mode and let
Open call `openPlainImageUrl` (today's behaviour, preserved); otherwise seed the tree root.

**Expand** (`NodeExpandedFcn`): reuse the deferred-node pattern already in the repo -
`mib/+controllers/@DatasetInfo/treeNodeExpanded_Callback.m` creates children with a
`'__loading__'` `NodeData.key` and fills them on expand. Exactly one `listChildren` call per
expand. Free decoration at zero extra cost: if the node's own file list has `.zattrs` and
its children are named `s0,s1,...` or `0,1,...`, append `" [pyramid]"`.

**Select** (`SelectionChangedFcn` -> `probeGroup`): read `.zattrs` / `zarr.json`, run
`OmeZarrMetadataUtils.extractMultiscales`; if present read level 0's `.zarray` and fill
`infoTextArea` (levels, axes, s0 shape, dtype, chunk, voxel size, format + whether python is
required), set `GroupPath` via `relativePath`, enable Open. Two small cached GETs per
selection.

**Degradation - must be implemented, not just documented.** Most non-AWS OME-Zarr hosts
(EMBL-EBI, plain nginx) are not listable. When `parse().listable` is false or the first LIST
returns non-XML, hide the tree, enable manual `GroupPath` entry, relabel the button to
"Probe", and run the same `probeGroup` against `join(rootUrl, GroupPath)`. Open still works
with the URL exactly as typed.

`LoadAs = Labels` is disabled with an explanatory tooltip when the active dataset is
Virtual - `MibModel.loadModel` has a hard Virtual-mode guard at line 255 and it should stay.

`DatasetMode` offers `BigData` (default, matching the goal), `Virtual`, and `Standard`.
Worth knowing when writing the tooltip: Virtual and BigData read the image through the
*same* path (`MibVirtualImage.getDataZarr`), so BigData's only added value is the editable
local model store. `Standard` is genuinely right for the small label crops (400^3 = 64 MB).

### 7. Ribbon wiring

`mib/+controllers/@MibRibbon/homeImport_Callback.m` - replace the whole `case 'URL'` body
(lines 81-143) with `obj.mibController.startController('controllers.SelectFromUrl');`. The
`imfinfo`/`imread` logic moves verbatim into `@SelectFromUrl/openPlainImageUrl.m`; the
clipboard pre-fill becomes the `BatchOpt.Url` default. No new ribbon *item*, so no restart
is needed.

`mib/mib3.m` - add `views.SelectFromUrlGUI;` to the `if false` compiler-inclusion block, or
the standalone build will not include the dialog.

### 8. Labels path and the local model store

`mib/+models/@MibModel/loadModel.m`, four edits:

1. line 154 store guard -> `isempty(storePath) || (~io.RemoteStore.isRemote(storePath) && ~isfolder(storePath))`
2. lines 171-172 v2/v3 detection -> `strcmp(io.ExtensionRegistryLoad.detectZarrFormatExtension(storePath), 'zarr2')`, dropping a duplicated heuristic that is now URL-aware
3. lines 426-427 - `fileparts` returns `''` for `.../crop266/all`; probe the remote format before the `Model.Default` membership check (`zarr2`/`zarr3` are already in that set)
4. add `BatchOpt.ZarrGroupPath` + tooltip and forward it into `dsOpts`

`mib/+core/@MibDataset/loadModel.m` line 130 - forward `ZarrGroupPath` into `loaderOpts`
alongside `ParentFigure`/`mibPath`.

`mib/+models/@MibModel/createModel.m` lines 147-160 derive the BigData store default from
`fileparts(image.filename)`, which hands `uiputfile` a URL as its start folder. Fall back to
`obj.currentDirectory` with a stem from the last URL segment. This is what makes "browse a
remote store in BigData mode, segment into a local store" actually work.

---

## Scoped out: overlaying Janelia label crops on the full EM volume

> **Partly superseded by [Step 16](#step-16---loading-a-label-crop-with-its-image-region-planned-2026-08-11).**
> What is scoped out below is overlaying a crop on the *full* BigData volume. Loading the crop
> *region* - the EM sub-volume plus the labels, both cut to the crop extent - avoids all three
> blockers, because after cutting the dims match exactly. That is Step 16.

This does not work today and cannot be made to work by a small change. Verified numbers:
`recon-1/labels/groundtruth/crop266/all` s0 is `[400,400,400]` uint8 at **4 nm** with
`translation [220334, 91822, 89286]` nm, while the EM is `[49645,21451,23601]` at 8 nm - a
200^3 island inside a 25-gigavoxel volume. Three independent blockers:

1. `MibModel.loadModel` lines 189-199 reject any store whose level-0 dims differ from the
   image dims. 200 vs 21451 - immediate error.
2. `core.MibBigDataLabelsZarr2` has no origin concept. `openStore` sets
   `obj.height/width/depth` from the label store itself (lines 194-199) and `readPackedLevel`
   maps limits straight onto the array. Nowhere to put a translation, no zero-fill outside
   the crop.
3. `openStore` normalises `modelScaleFactors` against the label store's *own* level 0, which
   is 4 nm, while the image pyramid is normalised to 8 nm. Level picking would be off by one
   everywhere - a silent 2x scale error, worse than a hard failure.

So `LoadAs = Labels` is for label stores that share the image extent. `probeGroup` must
compute the comparison and surface a specific message naming both sizes and the translation
**before** Open is pressed, suggesting the alternative below - never a silent misalignment.

What works instead, at zero extra cost once the above lands: open `.../crop266/all` **as an
Image in Standard mode** (64 MB, the existing level picker appears) and get a fully
browsable, segmentable crop; then load a per-class group as a Model onto it, where the dims
do match.

A real sub-volume overlay is a separate work item: add `originYXZ` + `imagePyramidRef` to
`MibBigDataLabelsZarr2`, pick label levels by *absolute* scale rather than self-normalising,
intersect-and-zero-pad in `readPackedLevel`, and relax the dims guard to "label extent lies
inside image extent". Do not bundle it.

### Other stated limits

- **No chunk caching, by decision.** `zarr-python` has no default chunk cache, so scrubbing
  re-downloads visible chunks. Related and more important: s0 chunks are 64x128x128, so one
  full-resolution XY slice spans ~31k chunks - full-res viewing is not viable and the
  pyramid plus fast-pan (auto-enabled when `imginfo` has a `Pyramid` key, `loadImages` line
  483) is what makes this usable at all. Measure in Step 0 and put the number in the docs.
- Remote **v3** relies on `zarrMex` Range reads. Range works on S3 (verified 206) but no
  public remote v3 store was found to test the engine end to end.
- Non-S3 hosts cannot be listed; manual path entry covers them.

---

## Batch support

The URL flow has no `BatchOpt` today. Mirror `mib/+models/@MibModel/importDataset.m:89-105`:

```matlab
BatchOpt.Url         = '';          % clipboard pre-fill when it looks like a link
BatchOpt.GroupPath   = '';          % relative to Url, e.g. 'recon-1/em/fibsem-uint8'
BatchOpt.LoadAs      = {'Image'};        BatchOpt.LoadAs{2}      = {'Image', 'Labels'};
BatchOpt.DatasetMode = {'BigData'};      BatchOpt.DatasetMode{2} = {'BigData', 'Virtual', 'Standard'};
BatchOpt.showWaitbar = true;
BatchOpt.id          = obj.mibModel.getActiveId();
BatchOpt.mibBatchSectionName = 'Ribbon -> Home';
BatchOpt.mibBatchActionName  = 'Import from URL';
```

Constructor follows the `ChunkingImport` template: a struct third argument merges and runs
headless then notifies `CloseEvent`; `NaN` returns the BatchOpt; otherwise build the view.
Batch mode never touches the tree - it goes straight from `Url` + `GroupPath` to
`loadImages`/`loadModel`, so a recorded protocol replays without a network browse.

Keep `buildLoadImagesBatchOpt` a pure function so the mapping can be asserted with no
network. Deliberately do **not** set `mibBatchTooltip` in the forwarded options - that keeps
`batchModeSwitch = 0` so the Standard-mode level picker still appears.

---

## Verification

**Offline unit tests**

- `tests/io/RemoteStoreTest.m` - the full URL table incl. `s3://`, trailing slashes, keys
  with dots, non-S3 -> `listable=false`; XML parsing against embedded `ListBucketResult`
  samples, truncated and not; the continuation loop via injected `options.fetchFcn`;
  `join`/`relativePath` never use `fullfile`
- `tests/io/ExtensionRegistryRemoteZarrTest.m` - temp local v2/v3 folders -> `zarr2`/`zarr3`
- `tests/controllers/SelectFromUrlTest.m` - `SelectFromUrl(mibModel, [], NaN)` builds
  view-less and returns the documented fields; `buildLoadImagesBatchOpt` maps
  `Url` + `GroupPath` to `Filenames`/`ZarrGroupPath` with no mangling and no network

**Network tests** (self-skipping; add `tests/+mibtest/+helpers/hasNetwork.m`, which does not
exist yet)

- `tests/io/RemoteOmeZarrOpenTest.m` - open the Janelia group through `MibModel.loadImages`
  with `ZarrGroupPath = 'recon-1/em/fibsem-uint8'`; assert 21451 / 23601 / 49645, uint8,
  15 levels, `pixSize.x == 8`, units `nm`; then a 256x256 read at a coarse level, guarded by
  `assumeTrue(io.zarr.PyBackend.hasRemoteSupport())`

Per `tests/CLAUDE.md`: `mibtest.fixtures.MibPathFixture` in `TestClassSetup`, a fresh
synthetic model per method, `DeveloperMode = false`.

**Manual end to end**

```matlab
cd C:\Matlab\MIB3\mib; mib3
```

1. `Home -> Import -> URL`, paste
   `https://janelia-cosem-datasets.s3.amazonaws.com/jrc_mus-liver-zon-1/jrc_mus-liver-zon-1.zarr`
2. expand `recon-1` -> `em` -> `fibsem-uint8`; confirm 15 levels / `49645 x 21451 x 23601` /
   uint8 in the info pane and one LIST round trip per expand
3. `LoadAs = Image`, `DatasetMode = BigData`, Open; scrub Z and zoom to confirm level switching
4. create a model - confirm the store dialog starts in a local folder, not a URL
5. segment a few slices, save, reopen
6. paste the `s3://` form and confirm it normalises
7. paste a plain image URL and confirm the old `imread` behaviour is intact
8. point `PythonInstallationPath` at an env without `aiohttp` and confirm the error names
   the pip command

**Build checks**

```bash
cd C:\Matlab\MIB3 && buildtool check && buildtool test
grep -rn --include=*.m "—\|–" . | grep -v "^./deployed/"   # must return nothing
```

---

## Docs to update when this lands

**User (`docs/`)**

- new `docs/docs/user-interface/ribbon/home/home-importfromurl.md` - the dialog, the accepted
  URL forms, one-level browsing, the multiscales badge, `Load as`, the three dataset modes,
  the `aiohttp`/`requests` prerequisite with the exact command, the OpenOrganelle worked
  example, the non-listable-host path, and an explicit "no chunk cache yet, zoomed-in panning
  is network-bound" note. Register in `docs/zensical.toml` nav and link from the Home index.
- `docs/docs/getting-started/dataset-types/index.md` - a Remote stores subsection: the model
  store is always local; remote v2 needs python, remote v3 does not; the label-crop limitation.
- `docs/docs/user-interface/ribbon/home/home-preferences.md` - two edits in the
  **Input / output -> Zarr library** section:
    1. line ~452 lists `zarr` + `numpy` as the python-backend requirement. Add `aiohttp` and
       `requests` as additionally required **for remote (HTTP/HTTPS/S3) zarr v2 stores**, with
       the pip and conda commands from the prerequisite section above.
    2. line ~461 currently states *"Remote (HTTP/HTTPS) zarr datasets always use the native
       engine."* That is **incorrect for zarr v2** and must be corrected: it is true of
       `io.zarr.Array`, but `io.loaders.Zarr2VirtualLoader` bypasses that facade and calls
       `io.zarr.PyBackend` directly, because `zarrMex` is v3-only. Reword to "remote **v3**
       datasets always use the native engine; remote **v2** always uses zarr-python".
- point `helpBtn_Callback` at the new page, mirroring `ChunkingImport.helpBtn_Callback`.

**API (`docs_api/`)**

- ~~new `RemoteStore.rst`~~ **DONE** - added inline to `docs_api/source/api/io/index.rst` as a
  "Remote stores" section instead of a standalone page, matching how the other `+io` top-level
  classes (`ExtensionRegistryLoad`, `LoaderFactory`, `SaverFactory`) are already documented there
- new `controllers/SelectFromUrl.rst`
- new `loaders/Zarr2VirtualLoader.rst` and `Zarr2VirtualSetupLoader.rst` - **missing today**
  (only the Zarr3 pair exists) and this work touches both
- RST docblocks on all new public methods, plain-hyphen separators

**Development notes** - mark the deferred "Remote OME-Zarr over HTTP/URL" item in
[`bigdata_implementation_plan.md`](bigdata_implementation_plan.md) as implemented and record
the label-crop limitation plus the follow-up design.

---

## Ordered sequence

| # | Step | Files |
|---|------|-------|
| 0 | ~~Spike: install deps, verify `PyBackend` read on the live store, measure~~ **DONE 2026-08-10, passed** | none |
| 1 | ~~`io.RemoteStore` + offline test~~ **DONE 2026-08-10** - 18/18 tests pass, 0 code issues | `mib/+io/RemoteStore.m`, `tests/io/RemoteStoreTest.m`, `tests/+mibtest/+helpers/hasNetwork.m` |
| 2 | ~~URL-aware `detectZarrFormatExtension` + `resolveLoader` branch~~ **DONE 2026-08-10** - 11/11 tests pass | `+io/ExtensionRegistryLoad.m`, `tests/io/ExtensionRegistryRemoteZarrTest.m` |
| 3 | ~~`hasRemoteSupport` / `ensureRemoteSupport` + `openArray` translation + call sites~~ **DONE 2026-08-10** - 6 tests, both failure modes verified | `+io/+zarr/PyBackend.m`, `Zarr2VirtualSetupLoader.m`, `MibBigDataLabelsZarr2.m`, `tests/io/PyBackendRemoteSupportTest.m` |
| 4 | ~~Remote group resolution + relative `ZarrGroupPath` in both setup loaders~~ **DONE 2026-08-10** - 10/10 tests, 2.5 s to resolve the Janelia group | `OmeZarrMetadataUtils.m`, `Zarr2/Zarr3VirtualSetupLoader.m`, `RemoteStore.m`, `tests/io/OmeZarrGroupResolutionTest.m` |
| 5 | ~~`BatchOpt.ZarrGroupPath` in `loadImages`~~ **DONE 2026-08-10** | `+models/@MibModel/loadImages.m` |
| 6 | ~~**Milestone: headless remote open works** + network test~~ **DONE 2026-08-10** - 3/3 network tests; 25-gigavoxel store opens as BigData in 2.8 s and serves pixels | `tests/io/RemoteOmeZarrOpenTest.m` |
| 7 | ~~`loadModel` remote fixes, `MibDataset.loadModel` forwarding, `createModel` fallback~~ **DONE 2026-08-10** | 3 files, +2 network tests |
| 8 | ~~View + controller; migrate the legacy imread path~~ **DONE 2026-08-10** - 6/6 tests | `+views/SelectFromUrlGUI.m`, `+controllers/@SelectFromUrl/` (8 files), `tests/controllers/SelectFromUrlTest.m` |
| 9 | ~~Ribbon rewire + `mib3.m` inclusion line~~ **DONE 2026-08-10** | 2 files |
| 10 | ~~Docs~~ **DONE 2026-08-10** | new user page + nav, dataset-types, 4 new RST pages |
| 11 | ~~`buildtool check`, `buildtool test`, dash grep~~ **DONE 2026-08-10** - 444/449 Unit, 0 failed; 0 codeIssues; dash clean | - |
| 16 | ~~Label crop + its image region: world boxes, `Region`/`ZarrLevel`, multi-select composition, sibling image pairing~~ **DONE 2026-08-11** - 41 new tests, 0 failed; crop1 opens in 11.7 s with labels on the EM structures | see the file table in [Step 16](#step-16---loading-a-label-crop-with-its-image-region-done-2026-08-11) |

### Step 8: the view

Built first as a programmatic `classdef` (App Designer binaries cannot be authored as text),
then **replaced by a real `+views/SelectFromUrlGUI.mlapp` drawn in App Designer** by the author,
which is now the only view. The swap needed no controller logic changes, only the rename - the
`core.ChildView` contract (a class constructible from the controller, exposing `Figure` plus one
public property per widget) is identical either way.

Named `SelectFromUrlGUI` / `controllers.SelectFromUrl` to sit with the other dataset-selection
dialogs, `SelectHDFSeriesGUI` and `SelectLociSeriesGUI`.

Two things the `.mlapp` made necessary:

- **`showWaitbar` has no widget.** The dialog always shows progress; the BatchOpt field exists
  only so a batch protocol can suppress it. `updateGUIFromBatchOpt_Shared` skips fields with no
  matching property, so nothing else was needed.
- **`SelectFromUrl.resetDialog`** clears the placeholder tree nodes App Designer stores with the
  canvas (`Node`, `Node2..4`) and disables Open at startup. They are useful for laying the dialog
  out, so they are cleared in code rather than deleted in the designer.

One knock-on change: `Zarr2VirtualSetupLoader.zarrV2TypeToMatlabClass` became public, so the
preview panel reports the same data type the loader will produce (`uint8`) rather than the raw
numpy typestring (`|u1`). Duplicating the table in the controller would have let the two drift.

### Step 12 - dialog polish (2026-08-10)

The ribbon item is now **`URL / Zarr`**, and the dialog opens with the URL field focused and the
clipboard pre-fill selected (`focus()` on a `uieditfield` selects its text - verified by robot
keystroke, typing replaces the whole value). ++enter++ then connects, and for a plain image URL it
imports and closes immediately: paste, Enter, done.

Enter is handled in a figure-level `WindowKeyPressFcn`, **not** in the URL field's
`ValueChangedFcn`. Two measured facts forced that, both verified with `java.awt.Robot`:

| Interaction | `ValueChangedFcn` |
|-------------|-------------------|
| Enter on text the user never edited (the clipboard pre-fill case) | **does not fire** |
| Edit, then Enter | fires, *after* the key handler |
| Click away without pressing Enter | fires |

So `ValueChangedFcn` both misses the case this shortcut exists for and fires on cases it must not -
a plain image would have been imported on the way to clicking Close. The key handler calls
`drawnow` first, which flushes a pending commit (confirmed ordering: `key:return -> valueChanged ->
afterDrawnowInKey`), then connects unless `connectedUrl` already matches. That same guard makes
pressing Connect after Enter a 0.001 s no-op instead of a second 1 s probe.

Measured: plain image (270 KB tif) pasted to clipboard, dialog opened, one Enter - dataset open as
`396 x 756` Standard uint8 and the dialog gone, under 0.5 s. Janelia container, one Enter -
`zarr2` detected, one root node seeded, dialog stays open, 1.0 s.

**Bug found and fixed the same day: the tree hung on "loading...".** The root node was seeded with
a deferred placeholder and then expanded with `expand(rootNode)` - but **a programmatic `expand()`
raises no `NodeExpandedFcn`**; only a click on the arrow does. So the root revealed its placeholder
and nothing ever replaced it. `connectBtn_Callback` now fills the root by calling
`treeNodeExpanded_Callback` directly before expanding it; deeper nodes are still lazy, on the real
event.

Worth recording *why the test suite missed this*: the integration test walked the tree by calling
`controller.treeNodeExpanded_Callback(struct('Node', node))` itself, which is precisely the step the
GUI was failing to perform. A test that drives a callback directly cannot tell you the callback is
wired up. The test now asserts the root arrives already listed - non-empty children, none of them
`"loading..."`, `NodeData.expanded` true - before the walk starts.

### Step 13 - listing is not Amazon-only (2026-08-10)

`RemoteStore.parse` only set `listable` for hosts matching `amazonaws.com`, so a path-style
`https://HOST/BUCKET/store.zarr` on a MinIO style endpoint - one that serves a perfectly ordinary
`ListBucketResult` - was reported as unbrowsable. The AWS host patterns are
needed only to tell Amazon's **two** spellings apart (bucket in the host vs bucket in the path);
making them the sole route to `listable` was the mistake. Nothing about `ListObjectsV2` is
Amazon-specific.

`parse` now falls through to a generic `https://HOST/BUCKET/KEY` rule with the endpoint taken from
the URL, flavoured `'s3compatible'` to mark it as a guess. Guessing wrong is already free: a host
that does not speak the API returns no listing, and `listChildren` reports that as empty rather than
as an error, while `probeRemoteZarr` falls through to its marker probes. The one place the guess
mattered was the dialog, which would have shown a tree that could never fill - so
`connectBtn_Callback` now confirms a non-`'s3'` flavour with the root listing (already cached by the
version probe, so no extra request) and degrades to manual group entry if it comes back empty.

The remaining hardcoded `amazonaws.com` is in `normalise`, expanding the `s3://bucket/key`
shorthand. That one is correct: the scheme carries no host, so a default endpoint has to be assumed.

Verified live against a non-public path-style S3 host (deliberately not named here - see the note
below): browses `recon-1 -> em -> fibsem-uint8` in 0.4 s, reports 13 levels of
`5654 x 5253 x 8699` uint8 at 6 nm, opens as BigData in 2.1 s, and returns real pixels
(mean 111.3, 87% non-zero). Same store layout as the local `temp/zarr` example.

> **Do not commit URLs of non-public stores.** The store used for this step and for Step 14 is
> unpublished, so no URL for it appears in this repository. `RemoteStoreTest` reads one from
> `MIB3_S3COMPATIBLE_ZARR_URL` and skips when unset; documentation uses
> `https://HOST/BUCKET/store.zarr`. Only the public OpenOrganelle bucket
> (`janelia-cosem-datasets`) is named in tracked files.

### Step 14 - the chunk cache (2026-08-10). Risk 2 retired.

**The "no chunk caching" decision is reversed.** It was the top remaining usability risk in this
plan, and profiling the non-public path-style store from Step 13 made the case unarguable.

Where the 2 s per slice change actually went, at 100% zoom on a 1137 x 610 viewport:

| | |
|---|---|
| Chunks touched at `s0` | 60, each `[64, 128, 128]` |
| Per chunk | 1.0 MB decoded, **833 KB compressed** - zstd-6 manages only 1.26:1 on EM noise |
| Downloaded per slice change | **~50 MB** |
| Displayed | 0.69 MB - **1.1% useful** |
| zstd decode, all 60 chunks | 0.09 s (1.4 ms/chunk, 723 MB/s) - negligible |
| Single-stream link | 3.9 MB/s, 216 ms/chunk; 60 sequential would be 13 s |

So it is **bandwidth-bound, not latency-bound** (unlike the 512x512 tiles measured in Step 0):
zarr's `async.concurrency` is 10, giving ~6x parallelism and ~25 MB/s, hence ~2 s. Decode and MIB
overhead are noise. The whole cost is the 64x z-overfetch, and the decisive measurement was that
**reading 64 slices costs the same as reading 1** (2.59 s vs 3.00 s) - every z-step inside a chunk
block was being paid for 64 times.

`io.zarr.ChunkCache` caches whole decoded chunks in an LRU against a byte budget
(`Prefs.IO.Zarr.ChunkCacheMB`, default 512 MB, 0 disables). It works in Zarr's C-order index space,
so one implementation serves both the v2 (zarr-python) and v3 (native zarrMex) loaders - which is
also why the cache had to live in MIB rather than in fsspec, since remote v3 never touches Python.

Two design points worth keeping:

- **Whole chunks, not whole requests.** Caching the request would fix scrubbing and do nothing for
  panning. Chunk granularity means a viewport shifted by less than a chunk re-uses everything.
- **All missing chunks of a request are fetched in one call over their bounding box**, never one
  call per chunk. The engines fetch a request's chunks concurrently, so one call for N chunks beats
  N calls for one - by ~6x here. The bounding box may re-pull a few cached chunks; far cheaper than
  a second round trip.

Measured on the live store, same viewport, pixels verified identical with and without:

| | First view | Next slice | Pan < 1 chunk | Pan 128-600 px | Pan back |
|---|---|---|---|---|---|
| Cache off | 3.16 s | **2.06 s** | - | - | - |
| Cache on | 1.96 s | **0.006 s** | 0.01 s | 0.57-0.71 s | 0.01 s |

**~340x on slice changes**, and panning now costs only the new chunk columns. 60 chunks / 63 MB
resident for that viewport, so 512 MB holds about eight screenfuls.

Testing note: `tests/io/ZarrChunkCacheTest.m` asserts **values**, not just shapes - a synthetic
array whose every element encodes its own coordinates, checked over 40 random bboxes, because an
off-by-one when splitting a fetched block or copying an overlap would silently shift pixels rather
than fail loudly. Deliberately **no** `Performance`-tagged timing baseline: the meaningful invariant
is "16 slices in one chunk block provoke exactly one engine call", which the test asserts by
counting calls and is stable offline, unlike a network-dependent timing.

The widget is a `ChunkCacheMB` numeric field in `Preferences -> Input/output -> Zarr library`,
`ValueDisplayFormat = '%d MB'`. Two things about it are worth knowing:

- **Its callback is attached in `Preferences.updateWidgets`, not in App Designer**, unlike every
  other widget on that panel. Assigning `ValueChangedFcn` replaces rather than adds, so wiring it in
  the designer later cannot cause a double fire.
- **The render also forces `Limits = [0 Inf]`.** The field was drawn with `[1 Inf]`, which would
  have made the documented "0 disables the cache" unreachable from the GUI.

Dispatch works because `core.ChildView` copies each component's property name into its `Tag`, so
`event.Source.Tag` is `'ChunkCacheMB'` without anything being set in the designer.

Verified in a live session: the field shows the stored value, an edit updates only the dialog's
working copy, Apply commits it and pushes it into the cache, and Apply with 0 disables the cache and
drops all 60 held chunks immediately (0 chunks, 0 MB).

### Step 15 - the cache is not remote-only; label stores reviewed (2026-08-11)

**Local zarr already uses the chunk cache.** Worth stating plainly because Step 14 was written up
entirely in terms of the remote store, which reads as though the cache were a remote feature. There
is no `isRemote` / `isHttp` gate anywhere: `Zarr2VirtualLoader.m:156` and `Zarr3VirtualLoader.m:193`
both wrap their engine read in `io.zarr.ChunkCache.read` unconditionally, and
`initializePreferences.m:196` applies the budget process-wide at startup. Local v2 and v3 image
stores, Virtual and BigData alike, get the identical LRU. That was the point of writing the cache in
Zarr's C-order index space with no knowledge of transport.

The gaps were the two **label** stores, which read through `readPackedLevel` rather than through the
image loaders.

**`MibBigDataLabelsZarr2` - now cached.** `readPackedLevel` wraps `PyBackend.readArray` in
`ChunkCache.read`, keyed on a new `modelLevelPaths` property filled by `openStore` (the level path
was already being computed there and discarded). Safe with no invalidation because the store is
read-only by construction - `writePackedLevel` errors. Keying on the level path means a store opened
both as an image and as labels shares its chunks instead of holding two copies.

**`MibBigDataLabels` - deliberately NOT cached.** This is the editable store MIB writes during
segmentation, and a read cache over it is a data-loss hazard, not merely a staleness one.
`setData63.m:113` is a read-modify-write: read the chunk, merge the brush stroke, write it back. A
stale read at step 1 means step 3 writes the pre-stroke copy **to disk**, destroying earlier strokes
in that region. The pyramid compounds it - `MibBigDataLabels.m:494` rebuilds coarser levels from
finer ones, so one stroke must invalidate cached chunks at every level `markTiles` touches, not just
the level painted on.

The reward does not justify that. `MibBigDataLabels.m:181-187` copies the **image's** chunk shape
into the model store, defaulting to `[256 256 16]`, so the default local overfetch is 16x rather than
the remote store's 64x; and label indices are uint8 and compress far harder than EM noise (zstd
managed only 1.26:1 on the image). Cost is decode, not I/O. At the measured 1.4 ms/chunk, a ~15-chunk
screenful is an estimated **~20 ms** - almost certainly invisible beside the image read on the same
slice change.

**Gate before revisiting.** Open a BigData dataset with a model and scrub Z with *Show model* on,
then off; the difference is the labels' entire contribution to a slice change. Under ~15% - close the
question. Over ~30% - act, including one model created on a remote image, since that store inherits
the Janelia `z=64` chunking and is the worst realistic case.

**If it ever is worth acting on, build evict-on-write only:** add
`ChunkCache.invalidate(cacheKey, region)` and call it from `writePackedLevel` for the level written
and every coarser level `markTiles` touches. Correct by construction - after a write the affected
chunks are simply gone, so a stale copy cannot exist - and it still helps the common case of moving
around a model you are not currently painting on. **Write-through** (patching the RAM copy to match
the write) keeps the cache warm mid-stroke but is the version that can corrupt a store if the
chunk-boundary arithmetic is wrong, since brush strokes are not chunk-aligned. It must never be the
first attempt; only consider it after evict-on-write has shipped and been measured as insufficient.

### Step 16 - loading a label crop with its image region (**DONE 2026-08-11**)

**Status: implemented and verified against the live store.** Measured end to end: selecting
`crop1/mito_mem` + `mito_lum` + `er_mem` opens a `500 x 500 x 100` Standard dataset at 4 nm with a
three-material model in **11.7 s**, and the labels sit on the EM structures (mean EM intensity
inside `mito_mem` is 136.8 against 155.9 for the crop as a whole - membranes are darker, which a
shape-only check cannot see). The published voxel bounds are reproduced exactly: EM `s0`
x 6466-6966, y 225-725, z 598-698.

Everything below the design section is what the build actually needed. **Read the half-voxel
finding first** - it is the one thing in the original design that was wrong, and it was wrong in the
direction that produces plausible-looking, misplaced labels.

#### Finding: the voxel table is edge-based, the bounding box is centre-based

The design says translations are pixel-centre based and that `MibImage.boundingBox` uses the same
convention, so "the mapping is direct, with no half-voxel correction anywhere". **The first half is
right and the conclusion is wrong.** Both conventions are centre-based, but mapping one *grid* onto
another is not a coordinate conversion - it is an alignment question, and alignment only exists in
edge space.

Concretely, for crop1: its first voxel centre is at `x = 25863 nm` on a 2 nm grid, and
`25863 / 4 = 6465.75`, which reads as a misaligned store. Its *edge* is at `25862 nm`, the EM 4 nm
grid's first edge is at `-2 nm`, and `(25862 + 2) / 4 = 6466` exactly. The grids do line up; centre
space hid it. The table of "integer EM s0 voxel bounds" in the design is edge-based and half-open
throughout.

So the code carries **two deliberately different conventions**, and mixing them is the failure this
work is most exposed to:

| | Convention | Units |
|---|---|---|
| `MibImage.boundingBox`, `worldBoundingBox` | voxel **centres** | the store's own (nm here) |
| `BatchOpt.Region`, `outerBoundingBox` | voxel **edges** (outer extent) | **micrometres** |

`Region` is in micrometres because it is compared across pyramids that may declare different units;
bounding boxes stay in store units because that is what MIB's own default box
(`(dim-1) * pixSize`) already is, so a derived box remains drop-in interchangeable with it.
`OmeZarrMetadataUtils.outerBoundingBox` is the single conversion point and its docblock carries the
crop1 numbers above.

`OmeZarrWorldGeometryTest.cropAndEmGridsAlignOnlyInEdgeSpace` pins this by asserting that the
centre-space index is **not** integral and the edge-space one is.

#### Finding: `crop1/all` defeats every content-based test for "is this the image?"

D.11 says to take "the multiscales group whose world box contains the crop's and which is not under
`labels/`". Both halves are load-bearing and the second is not optional: `crop1/all` is a genuine
multiscales pyramid, carries **no** `cellmap` annotation block, and encloses the crop exactly, so
containment plus "has no annotation" selects it - which is what the first implementation did. It is
the merged ground truth, not the image.

The fix is to reject on the **path**: any candidate with a `labels` component below the container
root is an annotation, per the OME-NGFF container convention. Applied *before* any metadata fetch,
which also keeps the walk cheap - passing back up through `groundtruth` rejects all 26 crops on
their paths alone. Resolving the image group costs ~2 s and about 13 requests.

#### Finding: the Standard-mode level picker had to be suppressed, and was also a 324 s stall

The pairing decides which level to read, so the level picker must not appear for a crop - any other
pick would break the dimension match `planLabelCrop` just asserted. That alone justified
`options.ZarrLevel` (plus `BatchOpt.ZarrLevel` in `loadImages`).

It turned out to matter far more than that. The first working headless open took **324 s**, of which
the zarr loader accounted for 7.7 s and the raw reads for ~10 s; the same dataset opened locally in
0.3 s. The whole difference was the level dialog being raised in a headless session. With
`ZarrLevel` set it is **11.7 s**. Worth remembering as a diagnosis pattern: a remote-only slowdown
that survives a local repro of the same size is not I/O.

#### Fixed on the way: `MibImage.initialize` ignored `imginfo{"BoundingBox"}`

`core.MibVirtualImage.initialize` has always honoured that key, but the Standard-mode path only
ever parsed a `BoundingBox` prefix out of an ImageDescription string. Zarr has no such string, so a
Standard-mode zarr open silently discarded **both** the derived box and MIB's own `mibBoundingBox`
attribute. Pre-existing, and step 16 depends on it, so it is fixed rather than worked around.

#### Found in use: `all` is an index map, and "no encoding" must not mean "binary"

Reported against `jrc_mus-liver-zon-1` `crop266/all` with `Load as = Labels`: the model came out
**empty**, and its single material was named with the group's full URL.

The design's decision "**No special case for `all`.** It is just another selectable node" is right
about the *selection* and wrong about the *decoding*. There are two kinds of group and only one is
binary:

| | `cellmap` block | Values |
|---|---|---|
| `mito_mem` and every other per-class group | yes, declares `present: 1` | `{0, 1}` |
| `all` | **absent entirely** | the publisher's class ids - for crop266: 3, 4, 5, 8, 9, 16, 17, 20-24, 26, 28, 35, 47, 48 |

The first implementation defaulted to `present = 1` for any group that declared nothing, so on
`all` it looked for voxels equal to 1, found none, and produced an empty model **with no error** -
the worst possible failure shape.

`labelEncodingValues` now returns a third output, `isSemantic`, which is true **only when the store
actually declares a `present` value**. Without one the group is treated as an index map and every
distinct non-zero value becomes its own material. Verified: `crop266/all` now yields 17 materials
that reproduce the raw array exactly (`isequal(model, remappedRaw)`), over the correct
`200 x 200 x 200` EM region at 8 nm, with per-class mean EM intensities that separate organelles
(112-127) from cytoplasm and ECS (144-158).

Materials from an index map are named `all_3`, `all_28`, ... by the store's own id. They are
deliberately **not** looked up in the crop's `class_names`: the plan already recorded that "`all`
ids are a canonical COSEM table, not the `class_names` order - `cyto` is 35", so indexing that list
by an id would mislabel every material.

Two smaller faults in the same report:

- **The material name was the whole URL.** The fallback for a group with no declared `class_name`
  was `relativePath(join(url, '..'), url)`, but `io.RemoteStore.join` appends `..` rather than
  resolving it, so `relativePath` found no common prefix and returned the input unchanged. Now
  `labelGroupName` takes the last path segment.
- **`Dataset mode` was silently ignored.** A crop is always opened Standard, by the decision above,
  but a user who picked BigData deliberately got a Standard buffer with no explanation. The
  override is now stated in the post-load report.

The image side was **not** at fault: `resolveSiblingImageGroup` resolves
`recon-1/em/fibsem-uint8` correctly for this store in ~3 s, and `planLabelCrop` pairs label `s1`
(8 nm) with image `s0` (8 nm) for a `200 x 200 x 200` region. What made it look as though the labels
had been opened as the image was an all-zero model sitting on top of the EM.

#### Found in use: risk 3 was real - `switchDatasetMode` back to Standard crashed

Reported when opening a crop with `Dataset mode = Standard` while a Virtual or BigData buffer was
already open:

```
Error using intmax
Class name must be a class that supports INTMAX, such as "int64" or "uint64".
Error in core.MibImage/initialize (line 64)
```

`switchDatasetMode(newMode, enableSelection, initWithImage)` takes a placeholder whose **form
depends on the target mode**, which its own docblock states and the calling code ignored:

| Target | `initWithImage` |
|---|---|
| `Standard` | a **numeric matrix**, or `[]` to let `MibImage.initialize` build its own 512x512 uint8 image |
| `Virtual` / `BigData` | a **cell array of file paths** |

`ensureDatasetMode` reused the cell form for every mode, copied from the pre-existing inline call in
`openBtn_Callback`. For `Standard` that puts a cell in `MibImage.data`, and the next line is
`intmax(class(obj.data))`. The message names neither the dataset mode nor the placeholder and
arrives four frames below the caller.

**The same fault was already latent in `openBtn_Callback`'s image branch** - picking
`Dataset mode = Standard` there while a Virtual buffer was open would have crashed identically. It
predates step 16. Both paths now go through `ensureDatasetMode`, which picks the placeholder form
from the target mode, so there is one copy of the rule.

Pinned by `switchingABufferBackToStandardWorks`, which drives Standard -> Virtual -> Standard and
asserts the resulting image is an integer class rather than a path; the old form was confirmed to
raise the reported error on exactly that call.

This is [risk 3](#risks-ranked) landing more or less where it was predicted - "`switchDatasetMode`
called from the dialog is the most likely thing to need adjustment... it re-initialises the buffer
with a placeholder image".

#### Found in use: a remote import moved `currentDirectory` to a URL

Reported after any remote open: the browsing directory became
`https://janelia-cosem-datasets.s3.amazonaws.com/.../recon-1/em`.

`controllers.MibController.updateGuiWidgets` derives the folder to browse with
`fileparts(dataset.image.filename)` and assigns it to `mibModel.currentDirectory`. `fileparts`
splits a URL perfectly happily, so a remote dataset produced a "directory" that does not exist. It
already guarded the *placeholder* case (`'none.tif'`, which has no path at all); a remote store
needs the same treatment for the same reason.

The blast radius is wider than the Directory Contents panel, which is merely left with nothing to
list: `currentDirectory` is the default starting folder for Save image, Save model, the BigData
model-store picker, and the recent-directories list, all of which inherited the URL.

The fix is a branch beside the existing placeholder guard, in `updateGuiWidgets`. The basename is
cleared alongside the directory: no local file corresponds to a remote group, so matching one by
name would highlight an unrelated file that merely shares it.

**Deliberately not unit-tested.** `updateGuiWidgets` needs a live `MibController` and a window, so
covering this would have meant extracting the branch into `+utils` purely to reach it - which is
what the "keep single-use logic inline" rule in [`CLAUDE.md`](../../CLAUDE.md) now forbids by
default. The guard is four lines beside an identical one that has been correct for years; the
comment carries the reasoning instead.

Note this is **not** specific to crops - it affected every remote open since step 6, including
plain image imports.

#### Deviations from the design

- **Empty classes are reported after composition, not greyed out in the picker.** C.8 wants absent
  groups greyed out, which needs pixel data: nothing in a group's metadata says whether it is empty.
  That is 63 speculative downloads per crop. The voxel counts come free while blending, so the same
  information is delivered at the moment it matters - along with the overlap and `unknown` counts.
- **`ImageGroupPath` has no widget.** `+views/SelectFromUrlGUI.mlapp` is an App Designer binary and
  cannot be authored as text, so the resolved image group is reported in the info panel and the
  override is batch-only. Drawing an edit field named exactly `ImageGroupPath` on the canvas is all
  that is needed to finish it - `updateGUIFromBatchOpt_Shared` skips BatchOpt fields with no
  matching property, so nothing else has to change.
- **`worldBoundingBox` takes a multiscales entry, not `attrs`.** A.2 wrote
  `worldBoundingBox(attrs, levelIdx, shape)`; the loaders already hold `ms`, and re-extracting
  multiscales from attrs there would be a round trip through a form they do not have.
- **Model composition does not go through `loadModel`.** Blending N groups into one index map is not
  something a loader that opens one store as one model can express, so the controller composes and
  assigns directly (`createModel` + `setData3D`). `loadModel` therefore needed no `Region` at all.
- **`buildZarrBbox` was factored out** of `Zarr2VirtualLoader` / `Zarr3VirtualLoader` into
  `OmeZarrMetadataUtils` rather than copied a third time for the whole-level reads.

#### Files

| Area | Files |
|---|---|
| Geometry + region arithmetic | `+io/+loaders/OmeZarrMetadataUtils.m` (`extractTranslationFromCT`, `extractCTVector`, `worldBoundingBox`, `outerBoundingBox`, `regionToVoxelRange`, `applyRegionToLevels`, `applyRequestedRegion`, `resolveRegionOption`, `resolveLevelOption`, `unitToMicrometreFactor`, `buildZarrBbox`, `levelRegionBbox`) |
| Loaders | `Zarr2VirtualSetupLoader.m`, `Zarr3VirtualSetupLoader.m` (per-level world boxes, region crop, `readLevelRegionV2/V3`, explicit level), `Zarr2VirtualLoader.m`, `Zarr3VirtualLoader.m` (bbox dedup) |
| Read path | `+core/@MibVirtualImage/getDataZarr.m` (crop origin), `+core/@MibImage/initialize.m` (BoundingBox key) |
| Model | `+models/@MibModel/loadImages.m` (`Region`, `ZarrLevel`) |
| Dialog | `+controllers/@SelectFromUrl/`: `readGroupPyramid`, `planLabelCrop`, `resolveSiblingImageGroup`, `isAnnotationPath`, `imageBoxContains`, `composeLabelModel`, `labelEncodingValues`, `labelGroupName`, `selectedLabelGroupUrls`, `ensureDatasetMode`, `openLabelCrop`, `reportCropResult` (new); `SelectFromUrl.m`, `openBtn_Callback.m`, `treeSelectionChanged_Callback.m` (edited) |
| Tests | `tests/io/OmeZarrWorldGeometryTest.m` (22 Unit), `tests/io/ZarrRegionReadTest.m` (12 Unit), `tests/controllers/SelectFromUrlTest.m` (+9 Unit, +4 network) |

#### Verification performed

`buildtool test`: 0 failures. `buildtool check`: 4 errors, all pre-existing in files this work never
touched (`mapRgbaVectorToScalar.m`, `using_hg2.m`, `readMetaDataFromFibicsTIFs.m`,
`McCalcGUI.mlapp`). Dash grep clean. Network tests against `jrc_hela-2` pass, including the
end-to-end crop open.

**Not yet done manually in the GUI** - the multi-select tree, the info-panel crop message and the
post-load report have been exercised headlessly but not clicked through in a running MIB.

---

#### Original design (retained for context)

Supersedes the scoped-out overlay above for the case that
actually matters: fetch the crop *region* as an ordinary dataset - EM sub-volume as the image,
selected label groups as the model - instead of trying to place a 200^3 island inside a
25-gigavoxel volume. After cutting, image and label dims are identical, so `loadModel`'s dims
guard, the missing origin in `MibBigDataLabelsZarr2` and the scale-normalisation mismatch all
stop being problems.

Reference store: `s3://janelia-cosem-datasets/jrc_hela-2/jrc_hela-2.n5`. The `.n5` URL that the
OpenOrganelle page hands out is already rewritten to the `.zarr` sibling by `resolveN5Sibling`.

#### The bounding box is exact, and MIB already has somewhere to put it

Each crop's `all/.zattrs` carries ordinary OME-NGFF `coordinateTransformations`:

```
crop1/all/s0:        scale [2.62, 2.0, 2.0]  translation [3132.21, 899.0, 25863.0]  shape [200,1000,1000]
em/fibsem-uint8/s0:  scale [5.24, 4.0, 4.0]  translation [0, 0, 0]                  shape [6368,1600,12000]
```

**Translations are pixel-centre based.** The proof is inside the EM pyramid itself: s1's
translation is `[2.62, 2, 2]`, exactly half of s0's scale, which is where the centre of the first
coarse voxel falls. So `world_centre(i) = translation + i*scale`.

That is the same convention `MibImage.boundingBox` uses - `updateBoundingBox.m:91-93` computes the
extent as `(dim-1)*pixSize`, centre of first voxel to centre of last. So the mapping is direct,
with no half-voxel correction anywhere:

```matlab
% OME axes are (z,y,x); boundingBox is [xmin xmax ymin ymax zmin zmax] in um
xmin = translation(xIdx)/1000;   xmax = xmin + (nx-1)*scale(xIdx)/1000;
```

Today the loaders derive **no** bounding box for a foreign store: `Zarr2VirtualSetupLoader.m:191`
only honours `mibBoundingBox`, a key MIB writes itself. Everything else lands at origin 0.

**Crops are 2 nm, EM s0 is 4 nm, so crop `s1` corresponds to EM `s0` exactly.** All 26 crops were
computed: every one lands on **integer** EM s0 voxel bounds, lies entirely inside the volume, and
its `s1` shape equals the EM extent exactly (spot-checked against the real `.zarray` for
crop1/4/9/155).

| crop | EM s0 z | EM s0 y | EM s0 x | size at 4 nm |
|------|---------|---------|---------|--------------|
| crop1 | 598-698 | 225-725 | 6466-6966 | 500 x 500 x 100 |
| crop9 | 1609-1662 | 420-520 | 2900-3000 | 100 x 100 x 53 |
| crop113 | 2975-3225 | 25-525 | 3125-3625 | 500 x 500 x 250 |
| crop155 | 1415-1815 | 583-983 | 7454-7854 | 400 x 400 x 400 |

Verified with real pixels: EM `s0[648, 225:725, 6466:6966]` overlaid on `crop1/all/s1[50]` is
pixel-perfect - mitochondria, ER, plasma membrane and extracellular space all land on the matching
EM structures.

#### What the label groups actually are

Each crop holds ~65 class subgroups plus `all`. Every group self-describes:

```json
"cellmap": {"annotation": {
    "class_name": "mito_mem",
    "annotation_type": {"type": "semantic_segmentation",
                        "encoding": {"absent": 0, "present": 1, "unknown": 255}}}}
```

Measured over crop1's 63 groups, and across all 26 crops:

| Finding | Consequence for the design |
|---|---|
| **53 groups semantic, 10 instance** (`nuc, ves, endo, lyso, ld, perox, mito, np, mt, cell`), instance encoding is `{absent:0, unknown:255}` with values 1..N as instance ids | An instance group must never be blended into a material index map - it would silently collapse every instance into one material. Offer `Load as -> Image` for these |
| **Semantic classes overlap**: `er` = `er_mem` + `er_lum`, `er_mem_all` contains `er_mem`, likewise `chrom`, `ne_mem_all`, `cent_all`. Probing `er` against `all` gives only 56% purity because it spans two atomic ids | Blending overlapping picks is order dependent. Warn, per the decision below |
| **`unknown = 255` means unannotated, not background** | Must map to material 0 *and* be reported, otherwise anything trained on the result learns false negatives |
| **`class_names` length varies per crop**: 58, 61, 63, 65 | Material names come from the crop's own `.zattrs`, never a global table |
| **Max class id across all 26 crops is 37**, distinct ids per crop 1-23 | 63 materials always suffice for COSEM. Derive the model type, do not ask |
| **Many groups are entirely absent in a given crop** - 40 of 63 for crop1 | Grey them out in the picker so nobody selects an empty material |
| **`all` ids are a canonical COSEM table, not the `class_names` order** - `cyto` is 35, not 34 | Reinforces the decision not to special-case `all` |
| **9 of 26 crops have a constant `all`** - crop54-59 are `1` everywhere, crop94-96 are `37` everywhere. These are genuinely homogeneous crops (entirely extracellular space, entirely nucleus), not corruption | Detect a single-valued result and say so, or the user sees a solid-colour model and blames MIB |

#### Decisions taken

- **Standard mode only, for now.** Every crop in this store fits in RAM (largest is crop155 at
  64 MB, crop113 at 62 MB), and `MibBigDataLabelsZarr2` is read-only by construction
  (`writePackedLevel` errors at `MibBigDataLabelsZarr2.m:278`), so a BigData crop could be viewed
  but never proofread. Crops in **other** datasets can be much larger, so the region read below is
  specified in world units and kept independent of dataset mode - adding BigData later must not
  need a redesign.
- **No special case for `all`.** It is just another selectable node. Whatever the user selects is
  what gets loaded.
- **Overlap is a warning, not a restriction.** The user may combine overlapping materials
  deliberately; say what will happen and let them proceed.
- **Model type is derived, not asked** - `nMaterials > 63` gives `'labels'`, otherwise
  `'labels63'`. Note `labels63` gives up `mask` and `selection` as separate layers
  (`MibDataset.m:219`).
- **`Load as -> Labels` on a sub-extent group fetches the image region too, mandatorily.** Not a
  convenience: load-as-Labels needs an open dataset with matching dims, and when a crop is selected
  the open dataset is the full EM volume, so the dims guard rejects it every time. The combination
  the user could otherwise pick simply has no working outcome.
- **`Load as -> Image` on a label group** keeps working as it does today, and is the route for the
  10 instance groups.

#### Implementation

**A. World coordinates (no UI, useful on its own)**

1. `OmeZarrMetadataUtils.extractTranslationFromCT(ct, nAxes)` - mirror of `extractScaleFromCT`,
   defaulting to zeros so a store without translations behaves exactly as now.
2. `OmeZarrMetadataUtils.worldBoundingBox(attrs, levelIdx, shape)` - returns
   `[xmin xmax ymin ymax zmin zmax]` in um, pixel-centre, ready for `MibImage.boundingBox`.
3. `Zarr2VirtualSetupLoader` / `Zarr3VirtualSetupLoader` - when `mibBoundingBox` is absent, derive
   `imginfo{"BoundingBox"}` from the translation. `mibBoundingBox` still wins where present. For
   the EM volume the translation is `[0,0,0]`, so existing stores are unaffected.

**B. Region reads**

4. `BatchOpt.Region` in `loadImages` - a world box in um, `[xmin xmax ymin ymax zmin zmax]`,
   forwarded into `options` beside `ZarrGroupPath`. **World units, not voxel indices**, because the
   label and image pyramids are on different scales (2 nm vs 4 nm) and a voxel-index region would
   have to name which level it refers to. World units make the level choice the loader's problem.
5. Setup loaders intersect the region with each level's extent, report cropped dims, and set the
   bounding box to the *cropped* extent.
6. `Zarr2VirtualLoader.readRegion` / `Zarr3VirtualLoader` offset reads by the crop origin. The
   existing `io.zarr.ChunkCache` keys on level path plus chunk index, so it needs no change.

**C. Composing the model**

7. `SelectFromUrlGUI` tree gets `Multiselect = 'on'`; `treeSelectionChanged_Callback.m:23`
   currently takes `selectedNodes(1)` and must handle N.
8. Probe each selected group for `class_name`, `annotation_type.type` and `encoding`. Grey out
   groups that are entirely absent; mark instance groups and exclude them from blending.
9. Compose in pick order: `present` becomes the material index, `unknown` becomes material 0 with a
   reported voxel count. Material names come from each group's `class_name`.
10. **Report the actual overlap, not a generic warning.** After composing, count voxels that were
    overwritten and name the pairs. This is exact and costs nothing extra, unlike guessing from
    class names which cannot see how the crop was annotated.

**D. Pairing the image**

11. Resolve the sibling image pyramid by walking to the container root and taking the multiscales
    group whose world box contains the crop's and which is not under `labels/`. Show it in the
    dialog and let the user override.
12. Pick the image level whose scale matches the selected label level (for COSEM: label `s1`,
    image `s0`), then assert the two shapes agree before building the dataset. A mismatch is
    reported, never silently resampled.

#### Verification

**Offline** - `worldBoundingBox` against embedded `.zattrs` samples, including a store with no
translation (must give origin 0) and the 5-axis `tczyx` case; region intersection arithmetic;
composition of overlapping and instance groups from synthetic arrays.

**Network** (self-skipping, `mibtest.helpers.hasNetwork`) - for crop1: assert the derived EM voxel
box is exactly `z 598-698, y 225-725, x 6466-6966`; load image plus labels and assert both are
`500 x 500 x 100`, `pixSize.x == 0.004` um, and that the bounding box matches the crop's world
extent; assert a constant-`all` crop (crop54) is reported as homogeneous rather than loaded
silently.

**Manual** - open the `.n5` URL, confirm the rewrite; expand `recon-1 -> labels -> groundtruth ->
crop1`; multi-select `mito_mem`, `mito_lum`, `er_mem`; confirm the overlap report; load and confirm
labels sit on the EM structures.

#### Docs

`docs/docs/user-interface/ribbon/home/home-importfromurl.md` gains a "Label crops" section: the
crop extent readout, multi-select, the instance-group restriction, the `unknown` value, and the
homogeneous-crop warning. `docs_api/` picks up the two new `OmeZarrMetadataUtils` methods.

---

## Risks, ranked

1. ~~**Step 0 is load-bearing.**~~ **Retired 2026-08-10** - zarr-python reads this store over
   HTTPS correctly; see the Step 0 table.
2. ~~**Performance is now measured and is the main usability risk.**~~ **Retired 2026-08-10 by
   Step 14.** The "no chunk caching" decision was reversed once profiling showed a slice change
   downloads ~50 MB to display 0.69 MB. `io.zarr.ChunkCache` takes slice changes from 2.06 s to
   0.006 s and makes panning cost only the new chunk columns. Note the diagnosis corrected Step 0:
   with a real viewport this is **bandwidth**-bound, not latency-bound. fsspec `simplecache::` was
   rejected as the fix - it only helps v2, because remote v3 never goes through Python.
3. ~~**`switchDatasetMode` called from the dialog** is the most likely thing to need
   adjustment: it re-initialises the buffer with a placeholder image.~~ **Hit 2026-08-11, fixed.**
   The placeholder's form depends on the target mode - numeric for Standard, a cell of paths for
   Virtual/BigData - and the cell form was being used for all three, crashing on
   `intmax(class(data))` whenever the target was Standard. Latent in `openBtn_Callback` since step
   8; both paths now share `ensureDatasetMode`. See the finding in
   [Step 16](#found-in-use-risk-3-was-real---switchdatasetmode-back-to-standard-crashed).
4. **`MibBigDataLabels.createStore` mirroring a 15-level Janelia pyramid** - arrays are
   metadata-only until written and the level map lives on the tiny coarsest level, but nobody
   has created a store with a `49645 x 21451 x 23601` declared level 0. Verify before shipping
   BigData-on-remote.
5. Region redirects, requester-pays and private buckets - handled by the one-shot `<Endpoint>`
   retry, unverified, degrades to not-listable.
6. `obj.id` vs `BatchOpt.id` at `loadImages` line 258 is pre-existing; the dialog sidesteps it
   by only using `getActiveId()`. Do not "fix" it here.

### Added by step 16

7. ~~**`BatchOpt.Region` touches the read path of every zarr loader.**~~ **Retired 2026-08-11.**
   An absent region is a literal no-op by construction: `applyRequestedRegion` returns its inputs
   unchanged with `levelRegionOrigins` all ones, `readLevelRegionV2/V3` calls the same plain
   `read()` it replaced rather than a full-extent bbox, and `getDataZarr` adds an offset of zero.
   `ZarrRegionReadTest` pins the uncropped open as byte-identical, and the full Unit suite passes.
8. ~~**Grid alignment is a property of this store, not of OME-NGFF.**~~ **Retired 2026-08-11** -
   `regionToVoxelRange` rounds outward with a grid tolerance and returns a residual;
   `regionReport.message` names the overshoot in um. Two tests cover it, including the floating-point
   case (`3133.52 / 5.24` is `597.99999...` in binary, and a bare `floor` loses a voxel there).
   **The related trap that was NOT anticipated is the centre/edge distinction** - see the half-voxel
   finding in step 16, which is where a one-voxel shift would actually have come from.
9. ~~**Pyramid level pairing assumes the pyramids share a scale.**~~ **Retired 2026-08-11** -
   `planLabelCrop` picks the label level whose voxel size matches the image's finest to within one
   part in a thousand, then asserts the two shapes agree, and reports both sizes on a mismatch. It
   never resamples.

### Remaining after step 16

10. **The crop path has not been clicked through in a running MIB.** Multi-select on the tree, the
    crop message in the info panel and the post-load report are covered headlessly only. The tree's
    `Multiselect` is set in `addCallbacks` rather than on the canvas, which is the most likely thing
    to behave differently under a real AppContainer.
11. **`ImageGroupPath` needs a widget** drawn in App Designer before the override is reachable
    outside batch mode. Name it exactly `ImageGroupPath` and nothing else changes.
