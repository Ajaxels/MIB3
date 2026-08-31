# Split and merge toolbox - interactive instance object editor

> Status: **implemented 2026-08-29** (see [What was built](#what-was-built) at the end). Follow-up to
> [`instance_3d_plan.md`](instance_3d_plan.md), which took automatic 2D-to-3D stitching as far as
> geometry allows. This is the manual proofreading step that has to come after it.

## Context

`utils.instances.stitch2Dto3D` now turns 2D DeepMIB predictions into 3D instance models
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
(`utils.instances.stitch2Dto3D` / `MibDataset.stitchModelInstances` / `MibModel.stitchModelInstances`):

| Layer | File | Role |
|---|---|---|
| Pure | `mib/+utils/+instances/objectIndex.m` | label volume in, per-object index struct out. No MIB objects. |
| Pure | `mib/+utils/+instances/cleanup.m` | absorb-fragments + min-voxels + min-slices, **extracted** from the stitcher and called by both. |
| Data | `mib/+core/@MibDataset/buildInstanceIndex.m` + new `instanceIndex` property | owns the cache for the active dataset. |
| Model | `mib/+models/@MibModel/editInstanceObjects.m` | one BatchOpt entry point with an `Action` field; undo, progress, notifications, incremental index update. |
| View | `mib/+controllers/@InstanceEditor/` + `mib/+views/InstanceEditorGUI.mlapp` | object table, click picking, highlighting. |

Putting every operation in `MibModel.editInstanceObjects` (rather than in the controller) means they
are driveable from batch protocols and testable headlessly through
`mibtest.helpers.buildSyntheticModel`, which already returns a live `models.MibModel` with a
`labels65535` dataset. The controller stays thin UI.

---

## 1. The object index (`utils.instances.objectIndex`)

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
already in `stitch2Dto3D.m:386-398`). Memory at 65535 objects is about 3 MB.

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

`utils.instances.objectIndex` also takes a bounding box to **re-index only the region an edit touched**,
which is how every operation repairs the cache without a full rebuild.

### Cache staleness is a correctness issue, not a convenience

Acting on a stale bounding box silently writes the wrong voxels. `MibDataset.maskStats`, the existing
precedent, is never invalidated - do not copy that. The controller listens to `SetData` (on the
**dataset**, which is where that event lives) and to `Undo` on `MibModel`, and sets `stale = true`
unless the change came from the editor itself (a guard flag set around its own writes). The status
line shows the state and offers Rebuild.

*(As built: an operation started against a stale index rebuilds it first rather than being refused -
equally safe, since the rebuild precedes any read of a bounding box, and it does not strand the user
behind a button.)*

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
| **Cleanup** | `utils.instances.cleanup` over the whole volume, cancelable, then full index rebuild. `compact = false` here so indices are not renumbered behind the user's back. |
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

**5. Incremental index repair.** After each write, `utils.instances.objectIndex` re-runs over the union
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

**Labels belong to the `.mlapp`.** The controller sets only what has to agree with the code -
dropdown items, spinner limits, table behaviour - and never a widget's `Text`. The one exception is
`objectTable.ColumnName`, which follows the mode and is therefore set in `updateObjectTable`, and
`indexStatusLabel.Text`, which is runtime content rather than a label.

Widgets the controller expects, by name:

| Name | Type | Purpose |
|---|---|---|
| `objectTable` | uitable | index / voxels / slices / z-range, sortable |
| `MaxRows` | spinner | rows rendered, default 1000 |
| `filterMaxVoxels`, `filterMaxSlices` | numeric | list filters |
| `autoUpdateTable` | checkbox | 2D mode: re-read the list when the slice changes |
| `updateTable` | button | re-read the list now |
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

Labels as set in the `.mlapp` (2026-08-30). The buttons whose label is simply the operation name are
not repeated here:

| Widget | Label |
|---|---|
| `Mode3D` | `3D (whole object)` |
| `pickByClick` | `Pick objects by clicking` |
| `autoUpdateTable` | `Update the list on slice change` |
| `updateTable` | `Update list` |
| `MaxRowsLabel` | `Max rows:` |
| `filterMaxVoxelsEditFieldLabel` | `Max size:` - the column is voxels in 3D and pixels in 2D, so the label names neither |
| `filterMaxSlicesEditFieldLabel` | `Max slices:` |
| `jumpToIndexEditFieldLabel` | `Go to object:` |
| `selectedListListBoxLabel` | `Selected objects:` |
| `ConnectivityDropDownLabel` | `Connectivity:` |
| `ConnectModeDropDownLabel` | `Connect mode:` |
| `MinObjectVoxelsSpinnerLabel` | `Min object size:` - same wording as the stitching dialog |
| `MinObjectSlicesSpinnerLabel` | `Min object depth:` - same wording as the stitching dialog |
| `AbsorbFragmentVoxelsLabel` | `Absorb fragments:` - same wording as the stitching dialog |
| `indexStatusLabel` | *(empty; written at runtime)* |

Callbacks carry DeveloperMode markers per
[developer_mode_callback_markers.md](../guides/developer_mode_callback_markers.md). Two of them
exist only to hold a marker honestly: `objectList_Callback` fronts the three list widgets because
`updateObjectTable` is repainted from a dozen places internally and would report a user action every
time, and `autoUpdateTable_Callback` fronts `sliceChanged`, which is otherwise listener-driven.
`updateBatchOptFromGUI` takes an optional widget handle and prints only when it was given one, for
the same reason.

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
- **The table has two forms, one per mode** - see [The 2D list](#the-2d-list) below. In 3D it lists
  the whole model from the index; in 2D it lists the shown slice, measured from that slice.
- **Pick by click** - while on, sets `mibModel.disableSegmentation = true` and swaps
  `imageDocument.UIFigure.WindowButtonDownFcn` for the controller's handler, restoring both on
  untoggle and in `closeWindow` (the save/restore pattern of `drawROIAndCreateMask` in
  `segmentationObjectPicker.m`; `MeasureTool.closeWindow` shows the `disableSegmentation` reset).
  Plain click replaces the selection, `shift` adds, `control` removes - the convention MIB uses
  elsewhere. Modifiers come from `obj.mibController.currentModifier`, never from
  `hFig.CurrentModifier`. Everything that is not one of those three gestures is handed back to
  `MibImageDocument.gui_WindowButtonDownFcn`, because `WindowButtonDownFcn` is one callback for all
  the buttons and taking it over takes the right-button pan with it.
- **Highlight** - selected objects are written into the Selection layer over their union bbox, the
  approach in `Quantification.highlightSelection`.

### The 2D list

Added after the first run on real data. With `Mode3D` off on an unstitched model, every object was
reported as spanning slices 1-501: the model came straight out of a 2D predictor, where the numbering
restarts from 1 on every slice, so index 5 is a different object on each of them. The whole-volume
index describes their **union**, which is the whole stack for every low index, and is therefore not
something a 2D list can be built from - not a rendering problem but a wrong quantity.

So in 2D the list is measured from the slice instead, by `InstanceEditor.currentSliceStats`:

| | 3D mode | 2D mode |
|---|---|---|
| Source | `MibDataset.instanceIndex` | one `getData2D` of the shown slice |
| Columns | Index, Voxels, Slices, Z range | Index, Pixels (**on this slice**) |
| Slice filter | applies | disabled - a slice count is not a property of a row |
| Needs the index | yes | no, so the list survives a stale index |
| Row click | `moveView` + jump to the object's slice | `moveView` only; the object is already on this slice |
| Highlight | union bbox of the picked objects | the shown slice only |

Measuring one slice is `find` + `unique` + three `accumarray` calls - a few milliseconds on
1078x1380 - deliberately **not** `regionprops` or `accumarray` on the label values, both of which
allocate up to the largest label and would blow up on a 4294967295 model with sparse high indices.

Cheap, but not free on every slice step, which is what `autoUpdateTable` is for. The result is cached
on `(slice, timePoint)` so repeated widget refreshes cost nothing, and dropped by
`invalidateSliceStats` on every write to the model - `SetData` from elsewhere, `Undo`, and the
editor's own operations. Note that the cache key cannot catch an edit: splitting an object changes
neither the slice nor the time point.

Objects picked on one slice are dropped when the list moves to another, because the same number there
is a different object. That is only enforced where the controller knows the list has moved, which is
the automatic refresh and the `updateTable` button; it is one more reason the two are worth having.

Launch: a `Button('Instance editor')` in the `"Model tools"` section of
`mib/+views/@MibView/addRibbonModel.m` (near line 184), `.ButtonPushedFcn = @obj.model_Callbacks` in
`mib/+controllers/@MibRibbon/MibRibbon.m` (Model block, around line 262), and a `case 'Instance
editor'` in `model_Callbacks.m` calling `startController('controllers.InstanceEditor')`. The ribbon is
built at startup, so the button only appears after a MIB restart.

---

## 5. Files

**New**
- `mib/+utils/+instances/objectIndex.m`
- `mib/+utils/+instances/cleanup.m`
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
- `mib/+utils/+instances/stitch2Dto3D.m` - the block at lines 369-410 (`localAbsorbFragments` plus the
  min-voxels / min-slices filters and the relabel) moves into `utils.instances.cleanup` and is called
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

1. `utils.instances.objectIndex` + its tests (pure, no UI).
2. Extract `utils.instances.cleanup`; re-run the stitcher suite to prove nothing moved.
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
  - `utils.instances.cleanup` returns bit-identical results to the pre-extraction stitcher on the
    existing test volumes.
- Interactive, on the 1078x1380x101 salivary-gland stack from
  [`instance_3d_plan.md`](instance_3d_plan.md) (1481 objects at defaults): stitch, open the editor,
  run each operation, undo each, confirm the object count and the rendered model track. Check the
  brush path end to end - brush a break, `i`, `shift+s`, `Split by Selection`.
- Rejection paths: Virtual and BigData datasets, a 63/255 model, no model at all.
- The long-dash check from `CLAUDE.md` (grep for em/en dashes across `*.m`) returns nothing outside
  `deployed/`.

---

## What was built

Implemented 2026-08-29, in the order set out above. The design survived contact with the code; the
notes below are the places where reality differed from the plan.

### Files

| File | Role |
|---|---|
| `mib/+utils/+instances/objectIndex.m` | the per-object index; full build and bounding-box-scoped refresh |
| `mib/+utils/+instances/cleanup.m` | absorb-fragments + the two size filters, extracted from the stitcher |
| `mib/+core/@MibDataset/buildInstanceIndex.m` | owns the cache for one time point |
| `mib/+models/@MibModel/editInstanceObjects.m` | all eight operations, BatchOpt-driven |
| `mib/+controllers/@InstanceEditor/` | 14 files: window, object list, click picking, highlighting |
| `mib/+views/InstanceEditorGUI.mlapp` | **author-built**; the controller only assigns callbacks |
| `tests/utils/InstanceObjectIndexTest.m` | 18 cases |
| `tests/utils/InstanceCleanupTest.m` | 15 cases |
| `tests/models/EditInstanceObjectsTest.m` | 19 cases |

Edited: `+instances/stitch2Dto3D.m` (now calls `utils.instances.cleanup`), `MibDataset.m` (+`instanceIndex`),
`MibDataset/stitchModelInstances.m` (sets `materialsCount`, clears the index),
`MibModel.m`, `addRibbonModel.m`, `MibRibbon.m`, `model_Callbacks.m`, `mib3.m`,
`utils/moveWindowOutside.m`, and the user docs.

### Decided during implementation

- **A refresh never shrinks the index space.** When an edit removes the highest label value, a full
  rebuild sizes its arrays to the new maximum while a refresh keeps the old one and marks the
  vacated entry free. Those gaps are exactly what the next split allocates from, and a rebuild
  cannot know they existed. So the invariant the tests assert is "equal over the shared range, with
  the refreshed tail free", not element-for-element equality.
- **Cleanup does not renumber** (`compact = false`), and Compact is a separate explicit action. A
  user who has been working with object 1299 must still find it under that number.
- **`PixelIdxList` is time-point-blind.** `MibImage.setPixelIdxList` writes into `obj.data`, which is
  `[H W Z 1 T]`, while `convertPixelIdxListCrop2Full` produces indices into `[H W Z]`. Anything past
  the first time point therefore needs the frame offset added, which `editInstanceObjects` does in
  `iCropToFull`. The pre-existing `segmentationObjectPicker` has the same latent issue.
- **A stale index is rebuilt automatically** before an operation runs, rather than the operation
  being refused as originally planned. Equally safe - the rebuild happens before any bounding box is
  read - and it does not strand the user behind a button.
- **New indices are allocated from the index, never via `MibDataset.addMaterial`,** whose large-model
  branch calls `countMaterials()` and rescans every time point per call.

### Fixed along the way

- `utils.moveWindowOutside` referenced `useInnerPosition` before assigning it whenever `mibGUI` was
  empty. Latent in the app (the main window is always there) but it errors in any headless
  construction. Assignment hoisted above the branch.
- `MibDataset.stitchModelInstances` left `labels.materialsCount` at 0, so anything asking for the
  next free index fell back to a full-volume rescan. Now set from the stitcher's own object count.
- Navigating to an object called `moveView` on a dataset that has never been drawn. Its axes limits
  are **NaN**, not empty, so an emptiness guard passes and `diff(NaN)` then hands `setAxesLimits` an
  empty range. `goToObject` now tests for a valid two-element finite range.
- **A message box with no window to sit on blocks the session.** The guard paths originally reported
  through `utils.dlgs.inputUniversalDlg` unconditionally, copying `stitchModelInstances`. With no
  parent figure - a batch protocol, or the test suite - it still builds a modal dialog and nothing is
  there to dismiss it. Measured: `EditInstanceObjectsTest` took **250 s instead of 1 s**, and one run
  wedged MATLAB until the dialogs were closed by hand. `iComplain` now checks for a usable parent and
  writes to the console (stderr) when there is none. The message still has to go *somewhere* - a
  silent return would report success for work that never happened - but it must not block.
  `MibModel.stitchModelInstances` has the same pattern and the same latent hang; its tests simply do
  not reach those paths.

### Found on the first real dataset (2026-08-30)

The 2D mode listed the whole model rather than the shown slice, so on an unstitched model every
object read as spanning slices 1-501. The list, the highlight and the navigation now follow the slice
in that mode: [The 2D list](#the-2d-list). Two widgets were added to the `.mlapp` for it,
`autoUpdateTable` and `updateTable`.

### Fixed on the second real run (2026-08-30)

**`updateGuiWidgets` silently steals the image mouse.**
`MibController.updateGuiWidgets` ends by reinstalling every image document's own
`WindowButtonDownFcn`, unconditionally and with no way to opt out
(`@MibController/updateGuiWidgets.m:543-551`). `editInstanceObjects` fires `UpdateGuiWidgets` when it
finishes, so **pick mode died on the first operation** - and clicking went back to painting with the
active segmentation tool while the checkbox still claimed the editor owned the mouse. Invisible,
because MIB's default pointer over the image is a crosshair too. The DeveloperMode trace is what
pinned it:

```
imageButtonDown: triggered
imageButtonDown: triggered
runOperation(Merge): triggered
MibController.updateGuiWidgets triggered      <- and no imageButtonDown after this
```

`reassertPickMode` renews the takeover after `UpdateGuiWidgets`, after `SliceChanged`, and at the end
of `runOperation`. It also drops the claim when the document it took the mouse from has gone, and
hands the mouse back when a different document has become active, so the state can never describe a
window the user is no longer looking at. The general fix belongs in `updateGuiWidgets` - skipping the
reinstall when a child controller owns the mouse - and would cover the next tool to hit this; not
attempted here because every transient taker in `@MibImageDocument` currently relies on that
reinstall.

**The selection survived the operation it was made for.** Merge left the survivor picked. A plain
click *adds*, so the next pair picked would quietly have been a triple including an object already
finished with. An applied operation now clears the selection and the highlight. Un-picking one object
without starting over is a context menu on `selectedList` (`ItemsData` carries the object index);
a context menu rather than a button so it needed no change to the `.mlapp`.

**A marker that lied.** `updateTable_Callback` was also the automatic slice refresh, so it printed on
every step through the stack - the opposite of what a DeveloperMode marker is for. The work moved to
an unmarked `refreshSliceList`, leaving the marked callback for the button alone.

**Pick mode ate the right-button pan.** `WindowButtonDownFcn` is one callback for every mouse button,
so replacing it took panning with it - and panning is how the user reaches the next object to pick.
`imageButtonDown` now classifies the click first and hands back anything that is not one of the three
picking gestures. Two things make that work:

- The pan/select rule is restated in `iClickAction`, `System.LeftMouseButton` preference included.
  `gui_WindowButtonDownFcn` decides and acts in one pass, with no way to ask it the question alone,
  so the two have to be kept in step by hand. Extracting the decision out of that 580-line handler
  would be the better fix and is a change to shared mouse behaviour, not something to do while
  chasing this bug.
- The pan clears `WindowButtonDownFcn` while it runs, and its `WindowButtonUpFcn` restores the
  *document's* handler, not the editor's. So the delegation chains onto that up-callback and
  reasserts afterwards; without it a single pan would end pick mode, the same silent failure as the
  `updateGuiWidgets` one above but with a different cause.

The modifiers changed at the same time: plain click now replaces the selection, `shift` adds,
`control` removes. That is MIB's convention elsewhere, and it also falls out of the button mapping -
`shift`+click is `SelectionType` `extend` and `control`+click is `alt`, exactly the two the document
treats as selecting gestures.

### Verification

`buildtool check` clean; `buildtool test` green including the 52 new cases. The stitcher's own 25
cases pass unchanged after the cleanup extraction, which is what pins the extraction as
behaviour-preserving. Driven end to end through the controller on a synthetic 65535 model: split,
merge, connect, delete, cleanup, compact, jump-to-object, highlight, stale detection and rebuild.

**Not yet exercised on real data.** The MitoNet benchmark and the salivary-gland stack cited in
`instance_3d_plan.md` are no longer on this machine, so the interactive pass on a real 1481-object
model, and the click-picking path (which needs a live MIB window), remain to be done by hand. The
checklist for that is [Manual test protocol](#manual-test-protocol) at the end of this file.

### Left for later

- Seeded watershed as a further split mode - deferred by the author when the scope was set.
- The parentless-modal hang above is worked around in this one method. The general fix belongs in
  `utils.dlgs.inputUniversalDlg` - refusing to build a modal with no parent, and saying so - which
  would cover `stitchModelInstances` and every other caller at once.
- `editInstanceObjects` builds its progress dialog on `obj.getProgressBarParent()`, which is `[]`
  with no main window, so `Cleanup`/`Compact` error there in a headless run unless `showWaitbar` is
  false. Same as `stitchModelInstances`; unreachable from the running application.

---

## Manual test protocol

What the automated suite cannot reach: the live window, the mouse, and real data. Everything below
needs MIB running. **Restart MIB first** - the ribbon is built at startup, so the button does not
appear in an already-open session.

Use an instance model with a few thousand objects, ideally the output of
*Ribbon -> Model -> Convert type -> Indexed objects -> Stitch 2D instances to 3D* on a real 2D
prediction stack. A small model will not show the things worth checking.

### A. Opening

| # | Do | Expect |
|---|----|--------|
| A1 | *Ribbon -> Model -> Model tools -> Instance editor* | Window opens to the left of MIB |
| A2 | Look at the status line | `N objects, highest index M`, green |
| A3 | Compare N with the object count the stitcher reported | Same number |
| A4 | Note how long the first open took | The index build is one pass over the volume; a few seconds on a 100-slice stack. **If it is much worse than that, say so** - the whole design rests on this being affordable |

Guards, each expecting a message and no change (open the editor with the wrong thing loaded):

- A5 - no model at all
- A6 - a 63 or 255 material model -> *"Not an instance model"*, operations greyed out
- A7 - a **Virtual** dataset, and a **BigData** dataset -> refused with a reason

### B. The object list

In 3D mode; the 2D list is a different thing and has its own group, [I](#i-2d-mode---the-list-follows-the-slice).

| # | Do | Expect |
|---|----|--------|
| B1 | Click a column header | Sorts by it; clicking again reverses |
| B2 | Sort by *Voxels* ascending | The dust is at the top - this is how you find noise objects |
| B3 | Sort by *Slices* ascending | Single-slice objects first |
| B4 | Set **filterMaxVoxels** to 50 | Only objects that small are listed; `0` restores all |
| B5 | Set **Max rows** to 50 on a model with thousands | Only 50 rows; the tool stays responsive |
| B6 | Type a known index into **jumpToIndex** | That object is selected and the view moves to it |
| B7 | Type an index that does not exist | *"There is no object N in this model"*, nothing selected |
| B8 | Click one row | View centres on the object, slice jumps to it, object appears in the Selection layer |
| B9 | Ctrl-click / shift-click several rows | All of them highlighted together |
| B10 | Highlight one entry in **Selected objects**, right-click, *Remove highlighted from selection* | Only that object leaves the selection and the highlight; *Clear the selection* empties it |

### C. Picking by clicking - the part no test covers

| # | Do | Expect |
|---|----|--------|
| C1 | Tick **Pick objects by clicking**, click an object in the image | It is selected and highlighted |
| C2 | Click a second object | Selection *replaces*: only the second one. Plain click starts a new selection, as everywhere else in MIB |
| C3 | **Shift**-click a third | Now two are selected |
| C4 | **Ctrl**-click one of them | Removed from the selection |
| C5 | Click on background | Plain click empties the selection; shift and ctrl clicks there do nothing |
| C5b | **Drag with the right mouse button** | The view pans, as it does with the editor closed. Then click an object: still picks. Panning is how you reach the next object, and taking over the mouse takes the pan with it unless it is handed back |
| C5c | Set *Preferences -> left mouse button* to **pan**, then click | Left drag pans, right click picks. The picking gestures follow the preference, they do not fight it |
| C6 | Zoom out a long way, then click a small object | The *correct* object is picked. This is the check that the click reads full-resolution data rather than the rendered image |
| C7 | Untick the checkbox, then use the Brush | Brush works normally again |
| C8 | Tick it again, then **close the window** with the checkbox still on | Brush and all other segmentation tools work. **This is the one that makes MIB unusable if it is broken** - the editor takes over the image mouse and sets `disableSegmentation`, and both must come back |
| C9 | With pick mode on: run an operation, change slice, switch ribbon tab, then click an object | Still picks. `updateGuiWidgets` reinstalls the image document's own mouse handler whenever it runs, and `reassertPickMode` is what takes it back. Watch for silence in DeveloperMode: no `imageButtonDown` line means the mouse was lost again |
| C10 | With pick mode on, switch to another buffer | The mouse is handed back to the first document; the checkbox clears |

### D. Operations

Undo (++ctrl+z++) after **every** one of these and confirm the model returns exactly as it was.

| # | Do | Expect |
|---|----|--------|
| D0 | After any applied operation | The selection and its highlight are empty, ready for the next pick. A rejected operation leaves the selection alone |
| D1 | Select two objects, **Merge** | One object, carrying the **smaller** of the two indices |
| D2 | Merge three at once | All take the smallest index |
| D3 | Find an object whose index covers two separate blobs, **Split components** | Largest piece keeps the index; the other gets a new one. Both listed |
| D4 | **Split components** on a normal object | Nothing happens, no error |
| D5 | Move to a slice in the middle of an object, **Cut at slice** | Everything from that slice onwards becomes a new object |
| D6 | **Cut at slice** on the object's first slice, and on a slice outside it | Refused with a message naming the object's slice range |
| D7 | Two objects with a Z gap, **Connect** (`interpolate`) | Gap filled, both now one object with the smaller index |
| D8 | **Connect** across a gap that has a *third* object sitting in it | The third object is untouched. Check its voxel count in the list before and after |
| D9 | Brush a bridge into the Selection layer, **Connect** (`selection`) | Only the brushed area is used |
| D10 | **Connect** on three objects | Refused |
| D11 | Select some noise, **Delete** | Gone; index freed and reused by the next split |

### E. The brush workflow

The reason the tool exists. On a false merge - one index covering two mitochondria:

1. Brush the break into the **Selection** layer where the two should separate.
2. In 3D, brush it on a few slices and press ++i++ to interpolate between them.
3. Select the object, press **Split by selection**.

Expect: the brushed voxels are cleared out of the object and the two halves become separate objects,
in **one** ++ctrl+z++ step. Compare against doing it by hand (++shift+s++ to subtract, then
**Split components**) - the result should be the same.

### F. Staleness - the correctness one

| # | Do | Expect |
|---|----|--------|
| F1 | With the editor open, brush on the model in the main window | Status line turns red: *"Index is out of date"* |
| F2 | Now run any operation | It rebuilds the index first, then acts - and acts on the **right** voxels |
| F3 | Press ++ctrl+z++ | Status goes red again |
| F4 | Press **Rebuild** | Green, with the object count matching the model |
| F5 | Change time point on a 4D dataset | The list follows the shown time point |

The failure to watch for: an operation that edits *somewhere other than the object you picked*. That
is what a stale bounding box does, and it is silent.

### G. Cleanup and Compact

| # | Do | Expect |
|---|----|--------|
| G1 | **Min object size** 50, **Cleanup** | Small objects gone; **the survivors keep their numbers** |
| G2 | **Min object depth** 1, **Cleanup** | Single-slice objects gone |
| G3 | **Absorb fragments** 5, **Cleanup** | Object count drops but the labelled voxel total barely moves - specks are handed to their neighbours, not deleted |
| G4 | Press Cancel on the progress dialog mid-run | Model unchanged |
| G5 | **Compact** | Numbering becomes 1..N with no gaps |
| G6 | ++ctrl+z++ after Cleanup and after Compact | Both restore fully |

### H. Persistence and batch

| # | Do | Expect |
|---|----|--------|
| H1 | Save the model, reload it, reopen the editor | Same objects, same indices |
| H2 | Open *Ribbon -> Home -> Batch processing* | *Ribbon -> Model -> Instance editor* is listed with all its options |
| H3 | Run a Merge from a batch protocol | Works without opening the window |

### I. 2D mode - the list follows the slice

Do this group on an **unstitched** model, straight out of the 2D predictor, where the numbering
restarts on every slice. Untick **3D (whole object)** first.

| # | Do | Expect |
|---|----|--------|
| I1 | Look at the list | Two columns, *Index* and *Pixels*. No *Slices*, no *Z range* - those describe the whole stack and mean nothing here |
| I2 | Compare the row count with what is on screen | The list is the objects **on this slice**, not the whole model. This is the bug that prompted the group: it used to report every object as spanning slices 1-501 |
| I3 | **filterMaxSlices** | Greyed out |
| I4 | Status line | *"Slice N: K objects; M in the whole model"* |
| I5 | Move one slice with **Update the list on slice change** ticked | The list re-reads, and the status line names the new slice |
| I6 | Time how long a slice step takes on the full-size stack | Should be unnoticeable. **If scrolling has become sluggish, say so** - that is exactly what the checkbox is there to switch off |
| I7 | Untick it, move several slices | List unchanged; status line turns orange and says which slice it is describing versus where the image is |
| I8 | Press **Update list** | Catches up to the shown slice |
| I9 | Pick an object, then move to another slice with the automatic update on | The selection is dropped - the same number on the new slice is a different object |
| I10 | Pick an object | Only the shown slice is highlighted, not every slice carrying that number |
| I11 | Click a row | The view centres on the object and **stays on the current slice** |
| I12 | **jumpToIndex** with a number that is on another slice but not this one | *"There is no object N on slice M"* |
| I13 | Split or delete an object, without moving slice | The list re-reads by itself and shows the result |
| I14 | Switch **3D (whole object)** back on | The list becomes the whole model again, with all four columns |

### What to report back

- The A4 index-build time and the object count it was measured on.
- **I2** and **I6** - whether the 2D list now describes the slice, and what a slice step costs.
- Anything in **C8** or **F** - those two are the ones that can do real damage.
- Whether the operations are fast enough to work through a model object by object, which is the
  whole point of the bounding-box design.
