# Split and merge toolbox - interactive instance object editor

> Status: **planned, not implemented.** Follow-up to
> [`instance_3d_plan.md`](instance_3d_plan.md), which took automatic 2D-to-3D stitching as far as
> geometry allows. This is the manual proofreading step that has to come after it.

## Context

`utils.stitchInstances2Dto3D` now turns 2D DeepMIB predictions into 3D instance models
([`instance_3d_plan.md`](instance_3d_plan.md)). The residual errors are measured and structural, and
no threshold fixes them: 13 of 14 false merges on the benchmark are sustained overlaps spanning 7-120
slices, and the remaining false splits are z-disconnected components 52-810 slices apart. The
stitcher has gone as far as geometry allows; what is missing is **manual proofreading**.

This adds an **Instance editor**: a child window that lists the objects of an instance model and
applies split / merge / connect / delete to them, backed by a cached per-object index so each action
touches only the affected bounding boxes instead of scanning a multi-GB volume.

Scope agreed with the author:
- **Model types:** 65535 and 4294967295 instance models on `Standard` datasets only. `Virtual` and
  `BigData` are rejected with a clear message, as `segmentationObjectPicker` already does (BigData
  labels are `core.MibBigDataLabels < core.MibLabels63`, capped at 63 packed materials, so they
  cannot hold an instance model at all).
- **Split:** connected components, cut at a slice, and split by the current Selection (the brush
  workflow below). **Seeded watershed is deferred.**
- **Also in scope:** delete objects, cleanup filters on demand, compact/renumber indices.
- **Not in scope:** isolate/show-only rendering, 63/255-material models, mask-layer objects.

### The brush workflow this must complete

The author's split path is already possible by hand and must be supported as one action: brush the
break into the **Selection** layer (in 3D, brush a few slices and `i` to interpolate), then `shift+s`
("Subtract from material", `utils.defaults.generateKeyShortcuts` entry 7) removes it from the model.
That physically cuts the object but **both halves keep the same index**. The editor supplies the
missing step, and `Split by Selection` folds the whole thing into one undoable action.

---

## Architecture

Three layers, mirroring the existing stitching chain
(`utils.stitchInstances2Dto3D` / `MibDataset.stitchModelInstances` / `MibModel.stitchModelInstances`):

| Layer | File | Role |
|---|---|---|
| Pure | `mib/+utils/instanceObjectIndex.m` | label volume in, per-object index struct out. No MIB objects. |
| Pure | `mib/+utils/instanceCleanup.m` | absorb-fragments + min-voxels + min-slices, **extracted** from the stitcher and called by both. |
| Data | `mib/+core/@MibDataset/buildInstanceIndex.m` + new `instanceIndex` property | owns the cache for the active dataset. |
| Model | `mib/+models/@MibModel/editInstanceObjects.m` | one BatchOpt entry point with an `Action` field; undo, progress, notifications, incremental index update. |
| View | `mib/+controllers/@InstanceEditor/` + `mib/+views/InstanceEditorGUI.mlapp` | object table, click picking, highlighting. |

Putting every operation in `MibModel.editInstanceObjects` (rather than in the controller) means they
are driveable from batch protocols and testable headlessly through
`mibtest.helpers.buildSyntheticModel`, which already returns a live `models.MibModel` with a
`labels65535` dataset. The controller stays thin UI.

---

## 1. The object index (`utils.instanceObjectIndex`)

Index-aligned arrays, so `index.voxels(objId)` is a direct lookup:

```
.exists      logical [maxIndex x 1]
.voxels      uint32  [maxIndex x 1]
.bbox        int32   [maxIndex x 6]   % [yMin yMax xMin xMax zMin zMax]
.centroid    single  [maxIndex x 3]
.sliceCount  uint32  [maxIndex x 1]   % occupied slices, not zMax-zMin span
.maxIndex, .freeIndices, .timePoint, .stale
```

Build: one `regionprops(labelVol, labelVol, {'Area','BoundingBox','Centroid','MinIntensity'})` call -
the idiom `Quantification.quantification_Callback` already uses for indexed models, where
`MinIntensity` recovers the object id - plus one cancelable slice loop for `sliceCount` (the same loop
already in `stitchInstances2Dto3D.m:386-398`). Memory at 65535 objects is about 3 MB.

**Guard:** `regionprops` allocates for `max(label)`, so a 4294967295-type model with sparse high
indices would explode. If `max(labelVol(:))` far exceeds the number of distinct labels, remap through
`unique` first and keep the mapping, or require Compact.

**PixelIdxList is never cached.** It is derived per object on demand, which is what keeps this
interactive:

```matlab
bb  = index.bbox(objId, :);
sub = labelVolume(bb(1):bb(2), bb(3):bb(4), bb(5):bb(6));
idx = dataset.convertPixelIdxListCrop2Full(find(sub == objId), ...
        struct('y', bb(1:2), 'x', bb(3:4), 'z', bb(5:6)));
```

`utils.instanceObjectIndex` also takes a bounding box to **re-index only the region an edit touched**,
which is how every operation repairs the cache without a full rebuild.

### Cache staleness is a correctness issue, not a convenience

Acting on a stale bounding box silently writes the wrong voxels. `MibDataset.maskStats`, the existing
precedent, is never invalidated - do not copy that. The controller listens to `SetData` and `Undo` on
`MibModel` and sets `stale = true` unless the change came from the editor itself (a guard flag set
around its own writes). While stale, operations are refused and the status line offers Rebuild.

---

## 2. Operations (`MibModel.editInstanceObjects`)

`BatchOpt.Action` = `Merge` | `SplitComponents` | `SplitBySelection` | `CutAtSlice` | `Connect` |
`Delete` | `Cleanup` | `Compact`; plus `ObjectIndices` (string), `Mode3D`, `Connectivity`,
`ConnectMode`, the three cleanup thresholds, `showWaitbar`, `id` (from `obj.getActiveId()`).

Every action: `obj.backup('labels', 1, opts)` restricted to the union bounding box, write through
`setPixelIdxList` / `setData3D(..., options.PixelIdxList)`, update the index over that box,
`notify(obj,'ShowImage')` + `notify(obj,'SyncBatch')`.

| Action | Behaviour |
|---|---|
| **Merge** | `keep = min(objIds)`; each other object's voxels are rewritten to `keep`. Index: union the bboxes, sum voxels, recount `sliceCount` over the union box, release the freed indices. |
| **SplitComponents** | `bwconncomp(sub == objId, conn)` inside the bbox. Largest component keeps `objId`; each other gets the next free index. 3D uses 6/26-conn; 2D mode runs per slice with 4/8-conn, which also gives "explode into per-slice objects" for free. |
| **SplitBySelection** | Clears the current Selection voxels from `objId`, then SplitComponents - the brush workflow in one undo step. |
| **CutAtSlice** | Voxels of `objId` at `z >= currentSlice` take a new index. Targets the dominant measured failure, a merge that runs along Z. |
| **Connect** | See below. |
| **Delete** | Voxels to 0, indices released. |
| **Cleanup** | `utils.instanceCleanup` over the whole volume, cancelable, then full index rebuild. `compact = false` here so indices are not renumbered behind the user's back. |
| **Compact** | `MibLabels.squeezeMaterialLabels(wb)` then full rebuild. Warn that all indices change. |

**Index allocation:** take from `index.freeIndices` first, else `index.maxIndex + 1`, and refuse past
`labels.maxMaterials`. Do **not** call `MibDataset.addMaterial` - its large-model branch calls
`countMaterials()`, a full-volume max scan per time point, on every call.

### Connect

Two modes, both ending in a Merge to `min(A,B)`:

- `interpolate` - build a binary sub-volume over the in-plane union bbox spanning the z-gap, put A's
  facing cross-section on the first plane and B's on the last, run `utils.interpolateShapes`, and
  write the result **only where the label is currently 0** so no third object is overwritten.
- `selection` - take the current Selection layer as the bridge (same background-only guard), for gaps
  whose shape interpolation cannot guess.

If A and B already overlap in z, skip the bridge, merge, and say so.

---

## 3. What actually makes this interactive on a large model

Nothing here is new machinery. Every mechanism below already exists in MIB and is simply used
consistently, so that **no action's cost scales with the size of the dataset** except the two that
genuinely have to (index build, cleanup/compact). The rule for the whole tool: an edit costs what the
edited object costs.

**1. The index removes the full-volume scans.** Everything the UI asks per object - where it is, how
big it is, how many slices it spans, what index is free next - is an O(1) lookup into an
index-aligned array. Without it each of those is a volume pass. The worst offender is the next free
index: `MibDataset.addMaterial` on a large model calls `MibLabels.countMaterials()`, which does
`max(...)` over `obj.data(:,:,:,1,t)` **for every time point, on every call**. Splitting 50 objects
would mean 50 full scans. The editor allocates from `index.freeIndices` / `index.maxIndex` instead.

**2. Bounding-box scoped reads.** Objects are small relative to the volume. A crop through
`getData3D('labels', t, 3, NaN, options)` with `options.x/.y/.z` from `index.bbox` reads only that
box. On the 1078x1380x101 reference stack a typical mitochondrion box is well under 0.1 % of the
volume, so merge, split and cut are sub-second whatever the total size. This is the same trick
`segmentationObjectPicker` uses for its label-matrix path and `Quantification.highlightSelection` for
its union box.

**3. Sparse writes by linear index.** Results go back through
`setData3D(values, 'labels', t, [], [], struct('PixelIdxList', idx))`, which routes to
`MibDataset.setPixelIdxList` and touches exactly the object's voxels - no read-modify-write of a
sub-volume. `convertPixelIdxListCrop2Full` maps the crop-local indices up to full-volume indices.

**4. Bounding-box scoped undo - the one that decides whether the loop is usable at all.**
`backup('labels', 1, struct('x',...,'y',...,'z',...))` stores only the union box, so an action costs
kilobytes on the undo stack rather than the whole model. With a whole-volume backup, `MibBackup`'s
`max3d_steps` would be spent after a couple of clicks and each click would pause for a full copy.
(`stitchModelInstances` uses `'modelLayers'` because it replaces the labels object and changes model
type; the editor never does, so plain `'labels'` with a box is correct and far cheaper.)

**5. Incremental index repair.** After each write, `utils.instanceObjectIndex` re-runs over the union
bounding box only and patches the affected rows. Cost is proportional to the edit. A full rebuild
happens only after Cleanup, Compact, or an external change that marked the cache stale.

**6. Click resolution reads one pixel.** The index under the cursor comes from a 1x1
`getData2D('labels', z, [], [], options)` with `options.x = [x x]`, `options.y = [y y]` - the same
single-pixel read `MibController.findMaterialUnderCursor` (Ctrl+F) already does. (`mibModel.IrawModel`,
the rendered viewport index raster kept by `showImage`, is the alternative, but it is at display
resolution and would mis-pick when zoomed out.)

**7. Reading the volume without copying it.** Where an operation does need the whole array
(`SplitComponents` on an object whose bbox is most of the volume, Cleanup), `getData3D` on a
Standard, XY-orientation, single-timepoint dataset with `blockModeSwitch = 0` and
`col_channel = NaN` hits its fast path and returns a copy-on-write alias of `labels.data` rather than
a copy. It must be treated as read-only; any write to it materialises the full duplicate.

**8. The table never renders the model.** Sorting and filtering are vectorised over the index arrays
(65535 elements), and at most `MaxRows` rows are pushed to the `uitable`. An App Designer table with
tens of thousands of rows is unusable regardless of how fast the data behind it is.

**9. Cancelable progress only where it is real.** Index build and Cleanup/Compact get a cancelable
`uiprogressdlg` polled per slice, with cleanup and no partial write on cancel, per the repo rule.
Everything else is fast enough that a progress bar would be the slowest part of it.

Expected costs on the 1078x1380x101 / 1481-object reference stack: index build a few seconds (one
`regionprops` C call plus one slice loop - the same order as
`MibImageDocument.recalculateObjects`, which is already accepted for the Object picker); every
per-object edit in the millisecond range.

**Known ceiling, not solved here.** Instance models are memory-only: `Virtual` is rejected by the
stitcher and BigData labels are `core.MibBigDataLabels < core.MibLabels63`, capped at 63 packed
materials. "Large" therefore means a large in-RAM `uint16`/`uint32` array. Because every access in
this design is already bounding-box scoped, the same index and `PixelIdxList` structure would port to
a chunked on-disk store; that is the trigger for Phase D of `instance_3d_plan.md`, not work for now.

---

## 4. The window (`controllers.InstanceEditor`)

> **The author builds `mib/+views/InstanceEditorGUI.mlapp` in App Designer.** Claude does not create
> or edit the `.mlapp`. Claude writes the controller and assigns every callback externally, in
> `@InstanceEditor/addCallbacks.m`, against `obj.view.handles.<Tag>` - the pattern used throughout the
> repo (`DebrisRemoval.addCallbacks`, `MeasureTool.addCallbacks`). `core.ChildView` copies each App
> Designer component's property name into its `Tag` and collects them into `obj.view.handles`, so the
> contract between the two halves is **the component names**. The widget list below is that contract;
> the layout is the author's. Naming rule that fails silently: a widget backing a BatchOpt field must
> be named exactly as the field, because `utils.updateBatchOptFromGUI_Shared` writes
> `BatchOpt.(hObject.Tag)`.

Widgets the controller expects, by name:

| Name | Type | Purpose |
|---|---|---|
| `objectTable` | uitable | index / voxels / slices / z-range, sortable |
| `MaxRows` | spinner | rows rendered, default 1000 |
| `filterMaxVoxels`, `filterMaxSlices` | numeric | list filters |
| `jumpToIndex` | numeric + button | scroll to a given object |
| `pickByClick` | checkbox | take over the image mouse |
| `Mode3D` | checkbox | 3D or current-slice operation |
| `Connectivity` | dropdown | 6/26 in 3D, 4/8 in 2D |
| `selectedList` | listbox or label | currently selected objects |
| `mergeButton`, `splitComponentsButton`, `splitBySelectionButton`, `cutAtSliceButton`, `connectButton`, `deleteButton` | buttons | the operations |
| `ConnectMode` | dropdown | `interpolate` / `selection` |
| `MinObjectVoxels`, `MinObjectSlices`, `AbsorbFragmentVoxels`, `cleanupButton` | spinners + button | cleanup filters |
| `compactButton` | button | renumber indices |
| `indexStatusLabel`, `rebuildButton` | label + button | cache state and rebuild |
| `helpButton`, `closeButton` | buttons | standard |

Standard child-controller shape, copying `controllers.DebrisRemoval`: `core.ChildView(obj,
'views.InstanceEditorGUI')`, `utils.moveWindowOutside`, `utils.fontSizeUpdate`, `addCallbacks`,
`events CloseEvent`, static `ViewListner_Callback2`, listeners on `UpdateGuiWidgets` / `NewDataset` /
`SetData` / `Undo`, and `KeyPressFcn` re-broadcasting to MIB via `notify(mibModel,'KeyPressEvent',
core.ToggleEventData(e))`.

Behaviour:
- **Object table** - index, voxels, slices, z-range. Sortable and filterable (voxels below N, slices
  at most N). A 65535-row `uitable` is unusable in App Designer, so populate at most `MaxRows`
  after sort/filter, always including the currently selected objects, with a jump-to-index box. Row
  click navigates: `dataset.moveView(centroid)` plus the slice/time slider update from
  `Quantification.statTable_CellSelectionCallback`.
- **Pick by click** - while on, sets `mibModel.disableSegmentation = true` and swaps
  `imageDocument.UIFigure.WindowButtonDownFcn` for the controller's handler, restoring both on
  untoggle and in `closeWindow` (the save/restore pattern of `drawROIAndCreateMask` in
  `segmentationObjectPicker.m`; `MeasureTool.closeWindow` shows the `disableSegmentation` reset).
  Plain click adds to the selection, `control` removes, `shift` replaces. Modifiers come from
  `obj.mibController.currentModifier`, never from `hFig.CurrentModifier`.
- **Highlight** - selected objects are written into the Selection layer over their union bbox, the
  approach in `Quantification.highlightSelection`.

Launch: a `Button('Instance editor')` in the `"Model tools"` section of
`mib/+views/@MibView/addRibbonModel.m` (near line 184), `.ButtonPushedFcn = @obj.model_Callbacks` in
`mib/+controllers/@MibRibbon/MibRibbon.m` (Model block, around line 262), and a `case 'Instance
editor'` in `model_Callbacks.m` calling `startController('controllers.InstanceEditor')`. The ribbon is
built at startup, so the button only appears after a MIB restart.

---

## 5. Files

**New**
- `mib/+utils/instanceObjectIndex.m`
- `mib/+utils/instanceCleanup.m`
- `mib/+core/@MibDataset/buildInstanceIndex.m`
- `mib/+models/@MibModel/editInstanceObjects.m`
- `mib/+controllers/@InstanceEditor/` - `InstanceEditor.m`, `addCallbacks.m`, `updateWidgets.m`,
  `updateObjectTable.m`, `objectTable_CellSelectionCallback.m`, `pickMode_Callback.m`,
  `imageButtonDown.m`, `runOperation.m`, `highlightObjects.m`, `closeWindow.m`
- `tests/utils/InstanceObjectIndexTest.m`, `tests/models/EditInstanceObjectsTest.m`

**Author-owned**
- `mib/+views/InstanceEditorGUI.mlapp` - built in App Designer by the author, to the component names
  in section 4. Claude wires the callbacks from `addCallbacks.m` and never edits the `.mlapp`.

**Modified**
- `mib/+utils/stitchInstances2Dto3D.m` - the block at lines 369-410 (`localAbsorbFragments` plus the
  min-voxels / min-slices filters and the relabel) moves into `utils.instanceCleanup` and is called
  from there with `compact = true`. Behaviour must not change; the 25 existing unit cases are the
  guard.
- `mib/+core/@MibDataset/MibDataset.m` - `instanceIndex` property and the `buildInstanceIndex`
  declaration.
- `mib/+core/@MibDataset/stitchModelInstances.m` - set `obj.labels.materialsCount` after building the
  new layer. It is currently left at 0, so anything asking for the next free index falls back to a
  full-volume rescan. Small fix, found while planning, in the same area.
- `mib/+views/@MibView/addRibbonModel.m`, `mib/+controllers/@MibRibbon/MibRibbon.m`,
  `mib/+controllers/@MibRibbon/model_Callbacks.m`
- Docs: user page under `docs/docs/.../ribbon/model/`, RST docblocks per
  [`../guides/docs_api_sphinx.md`](../guides/docs_api_sphinx.md), a status entry in
  [`instance_3d_plan.md`](instance_3d_plan.md), and a line for this file in
  [`../INDEX.md`](../INDEX.md).

## 6. Order of work

1. `utils.instanceObjectIndex` + its tests (pure, no UI).
2. Extract `utils.instanceCleanup`; re-run the stitcher suite to prove nothing moved.
3. `MibDataset.instanceIndex` / `buildInstanceIndex`; the `materialsCount` fix.
4. `MibModel.editInstanceObjects` with Merge, Delete, SplitComponents, CutAtSlice + tests.
5. SplitBySelection, Connect, Cleanup, Compact + tests.
6. Hand over the widget-name contract; the author builds `InstanceEditorGUI.mlapp`.
7. Controller + `addCallbacks.m` against that `.mlapp`; ribbon wiring.
8. Docs.

Steps 1-5 are fully headless and testable and do not depend on the `.mlapp` existing, so the
operations can be finished and proven before the window is drawn.

---

## 7. Verification

- `buildtool check` and `buildtool test` clean; new suites green. Run the new files directly through
  the MATLAB MCP `run_matlab_test_file` while iterating.
- Headless assertions worth pinning down explicitly:
  - Merge assigns **the smallest** index and frees the others.
  - Split gives the new part an index that was genuinely unused.
  - Every operation leaves the index consistent with a full rebuild from the volume (compare
    `buildInstanceIndex` output before and after - the strongest single invariant).
  - `Ctrl+Z` after each operation restores the exact prior volume.
  - Connect writes only into background voxels: seed a third object inside the gap and assert it is
    untouched.
  - `utils.instanceCleanup` returns bit-identical results to the pre-extraction stitcher on the
    existing test volumes.
- Interactive, on the 1078x1380x101 salivary-gland stack from
  [`instance_3d_plan.md`](instance_3d_plan.md) (1481 objects at defaults): stitch, open the editor,
  run each operation, undo each, confirm the object count and the rendered model track. Check the
  brush path end to end - brush a break, `i`, `shift+s`, `Split by Selection`.
- Rejection paths: Virtual and BigData datasets, a 63/255 model, no model at all.
- The long-dash check from `CLAUDE.md` (grep for em/en dashes across `*.m`) returns nothing outside
  `deployed/`.
