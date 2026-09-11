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
`ConnectMode`, the three cleanup thresholds (`cleanupMinObjectVoxels`, `cleanupMinObjectSlices`,
`cleanupAbsorbFragmentVoxels` - prefixed since 2026-09-08 so they cannot be read as the
same-named-but-unrelated stitching options), `showWaitbar`, `id` (from `obj.getActiveId()`).

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
| `detectionSettings` | button | row cap, list filters and connectivity (2026-09-08) |
| `autoUpdateTable` | checkbox | 2D mode: re-read the list when the slice changes |
| `updateTable` | button | re-read the list now |
| `jumpToIndex` | numeric + button | scroll to a given object |
| `pickByClick` | checkbox | take over the image mouse |
| `useShortcuts` | checkbox | take over the `a` / `s` / ++ctrl+f++ keys (added 2026-09-02) |
| `Mode3D` | checkbox | 3D or current-slice operation; the window opens with it **off** |
| `selectedList` | listbox or label | currently selected objects |
| `mergeButton`, `splitComponentsButton`, `splitBySelectionButton`, `cutAtSliceButton`, `connectButton`, `deleteButton` | buttons | the operations |
| `ConnectMode` | dropdown | `interpolate` / `selection` |
| `cleanupButton`, `cleanupOptions` | buttons | clean the model; set the filters (2026-09-08) |
| `compactButton` | button | renumber indices |
| `indexStatusLabel`, `rebuildButton` | label + button | cache state and rebuild |
| `helpButton`, `closeButton` | buttons | standard |

Labels as set in the `.mlapp`, read out of the app on 2026-09-04 (the names below are the real
component names, not the App Designer defaults an earlier version of this table guessed at). The
buttons whose label is simply the operation name are not repeated here:

| Widget | Label |
|---|---|
| `Mode3D` | `3D (whole object)` |
| `pickByClick` | `Pick objects by clicking` |
| `useShortcuts` | `Shortcuts` - the mapping goes in the tooltip, not the label |
| `autoUpdateTable` | `Update the list on slice change` |
| `updateTable` | `Update list` |
| `GotoobjectLabel` | `Go to object:` |
| `SelectedobjectsLabel` | `Selected objects:` |
| `ConnectModeDropDownLabel` | `Connect Mode` |
| `detectionSettings` | *(no text in the `.mlapp` as of 2026-09-08 - it needs an icon, like `cleanupOptions`)* |
| `cleanupOptions` | *(no text; a `settings_16px` icon beside `cleanupButton`)* |
| `indexStatusLabel` | *(empty; written at runtime)* |

**Tooltips are set in code, in `configureWidgets` via `applyTooltips` (2026-09-04).** The `.mlapp`
carries none, so the explanation of a widget sits next to the code that gives it its behaviour and
cannot promise something the controller stopped doing. A setting and its label share one text -
hovering a spinner is not what a user does when the label is what they are reading - which is why the
table there is `{widgets}, text` rather than one row per widget. Every component of the app is
covered; a name that stops matching errors at construction rather than leaving a silent gap.

**The cleanup filters left the window (2026-09-08).** `MinObjectVoxels`, `MinObjectSlices` and
`AbsorbFragmentVoxels` were three permanent spinners serving the operation used least in a session -
a few hundred merges and splits, and perhaps one cleanup at the end. They are now asked for by
`askCleanupSettings`, a `utils.dlgs.inputUniversalDlg` with the same three prompts the stitching
dialog uses, opened by `cleanupButton` (cancelling cancels the operation) and by `cleanupOptions`,
the gear beside it, which only stores the answer. Sticky through
`MibModel.sessionSettings.instanceEditor`, read back by the constructor, so a reopened editor starts
where the last one left off; deliberately **not** in the preferences file, since a threshold that
suits one model is a poor opening offer for the next dataset. The `BatchOpt` fields carry a
`cleanup` prefix (`cleanupMinObjectVoxels`, ...): they no longer name widgets, so the prefix is what
says which action reads them, and it keeps them apart from `stitchModelInstances`'s identically
named and entirely separate options.

**The list settings followed them (2026-09-08).** `MaxRows`, `filterMaxVoxels`, `filterMaxSlices` and
`Connectivity` are now `askDetectionSettings`, behind the `detectionSettings` button. Same reasoning
and the same `sessionSettings.instanceEditor` key, plus three things worth knowing:

- The row cap and the two filters became `obj.listOptions` (a plain struct property), **not**
  `BatchOpt` fields. Only `updateObjectTable` reads them; they change what is drawn and never what is
  edited. That also retires `rmfield(obj.BatchOpt, 'MaxRows')` in `runOperation`, which existed only
  to keep a rendering setting out of the model's options and the `SyncBatch` payload. `Connectivity`
  stays in `BatchOpt` - the split actions genuinely consume it.
- The dialog follows the mode: in 2D the slice filter is **left out** rather than shown and ignored
  (a slice count is not a property of a row there), so the answers are read by position with the
  connectivity taken from `answer{end}`. `filterMaxSlices` left `applyModeToWidgets` with it.
- Connectivity is stored across sessions as its literal value but restored as a **stance**: the
  window always opens in 2D, so a stored `26` comes back as `8` and a `6` as `4`. `mode3D_Callback`
  does the same translation on every switch, now against `BatchOpt` instead of the dropdown.

Callbacks carry DeveloperMode markers per
[developer_mode_callback_markers.md](../guides/developer_mode_callback_markers.md).
`autoUpdateTable_Callback` exists only to hold one honestly: it fronts `sliceChanged`, which is
otherwise listener-driven. (`objectList_Callback` did the same for the three list widgets and went
with them.) `updateBatchOptFromGUI` takes an optional widget handle and prints only when it was given
one, for the same reason.

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
- Docs: `docs/docs/user-interface/ribbon/model/model-instance-editor.md` - its own page since
  2026-09-04, which is the file `helpButton_Callback` has always pointed at; the ribbon page keeps a
  short entry linking to it. Registered in the `nav` of `docs/zensical.toml`. Plus RST docblocks per
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
| `tests/models/EditInstanceObjectsTest.m` | 38 cases (20 at first build, 7 added 2026-09-01, 5 + 6 on 2026-09-04) |

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
  `localCropToFull`. The pre-existing `segmentationObjectPicker` has the same latent issue.
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
  wedged MATLAB until the dialogs were closed by hand. `localComplain` now checks for a usable parent and
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

- The pan/select rule is restated in `localClickAction`, `System.LeftMouseButton` preference included.
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

### Fixed on the third real run (2026-09-01)

**The highlight ate the input of the operation it was there to help.** `Split by selection` reads the
Selection layer as the cut; `highlightObjects` *wrote* the picked objects into that same layer, after
`clearSelection('4D, Dataset')` had emptied it. So the workflow the tool exists for could not
complete: brush the break, pick the object, and the brush was gone and the layer held the whole
object, so `objectMask & ~selection` was empty and the operation reported *"The Selection layer
covers the whole of object N - nothing would be left."* `Connect` in `selection` mode had it too -
the bridge was wiped and the highlight sat where the bridge should be. Reproduced headlessly before
fixing (scratch script, not committed): with the highlight in place the split leaves 1 object, after
the fix 2.

The layer is now **borrowed, not taken**:

- `highlightObjects` stashes what is in the box before painting - `highlightState` carries
  `{id, timePoint, box, stash, painted}` - and no longer clears anything outside it. The
  whole-dataset clear was also a full-layer backup plus copy on *every* pick, which is what
  `clearSelection` does; it is gone.
- `releaseHighlight` puts back `stash | (current & ~painted)` over the same box, in the dataset and
  time point it was painted from. Storing the painted mask rather than recomputing it from the
  labels is what makes the restore exact after the labels have changed underneath.
- It runs before every operation (so the model never sees the highlight), on any outside write to
  the selection layer (the user has started drawing - `SetData` carries `type`), and on close.
- After an applied `SplitBySelection` or `Connect`/`selection`, the drawing that was consumed is
  cleared - in `editInstanceObjects`, so it holds for batch protocols too. Otherwise a cut drawn for
  one object would silently be applied to the next. That clear is deliberately **not** backed up:
  undo brings the object back but not the drawing, which is the price of ++ctrl+z++ staying one step
  for the whole operation.

**The one case that cannot work** is drawing *inside* an already-highlighted object: those voxels are
indistinguishable from the highlight. Nothing is silently lost - the highlight disappears on the
first stroke, so what is on screen is what the operation will use - but the order in the workflow
(draw first, pick second) is now the documented one rather than an accident.

### The drawing chooses the objects (2026-09-01)

Asked by the author straight after the fix above: why does the user have to pick the object at all,
when the drawing already says which one it is? Nothing prevented it. The reasons it was built the
other way were `ObjectIndices` being the one entry point all eight operations share, and the rule
that no read escapes a bounding box - and the second one measured smaller than it looked:

| On a 1078x1380x101 stack | |
|---|---|
| `find` over the whole Selection layer + label lookup + `unique` | 83 ms |
| `any(any(sel,1),2)` to find the slices carrying the drawing | 3 ms |
| the same lookup over those slices alone | ~10 ms total |

So `localObjectsUnderSelection` narrows first and reads the labels only for the slices that carry
something. The Z range is deliberately left off the selection read so `getData3D` keeps its
copy-on-write fast path instead of duplicating the layer.

The rule is **the drawing decides, unless you have said otherwise**: `ObjectIndices` empty means
"everything the drawing covers", and naming objects restricts the action to them, which is what a
line clipping a neighbour needs. Empty stays an error for every other action. Two rejection paths of
its own - nothing drawn, and a drawing that lies only on background - both leaving the layer alone so
the user can move the drawing rather than make it again.

**`a` commits the drawing, whatever it covers** (2026-09-04). `a` in MIB means "add the Selection
layer to the material", and that reading survives here in full. What the drawing covers decides:

| Objects under the drawing | Action | Result |
|---|---|---|
| two or more | `Merge` | they become one, smallest index wins |
| exactly one | `AddToObject` | the object grows by the drawing |
| none | `AddObject` | the drawing becomes an object, next free index |
| nothing drawn | - | *"The Selection layer is empty"* |

Neither of the last two is a merge that came up short, which is how they were first written
(*"The Selection layer covers only object N"*); they are the same gesture over a smaller region.
`localObjectsUnderSelection` therefore reports "drawn, but on background" as a **finding** - empty
`objectIds`, no problem - and the policy sits with the action: Merge falls through, Split by selection
still refuses, because there is nothing there to cut.

Both are named actions as well, so a batch protocol can ask for either directly. They share
`localDrawingToObject`, the only writer here that does not start from a bounding box in the index: the box
comes from three `any()` reductions over the drawn layer, which keeps the backup and the rescan
proportional to the drawing without ever building a full-volume index list. Two boxes, not one -
**the undo covers the drawing, the rescan covers the drawing united with the object's existing
extent**, because `buildInstanceIndex` recomputes an object's statistics from the box it is given and
a box holding only the new part would report only the new part. On the Merge path nothing else can be
overwritten, since it is only reached when the drawing covers no *other* object.

**Merge takes the same form** (asked for in the same conversation): draw one shape across the objects
that belong together and press Merge. Both are gestures over a region, and a region says which
objects it means; the whitelist in the "Objects to act on" block is where a third action would be
added. Merge's own rejection - a shape covering one object - says so rather than repeating "Merge
needs at least two objects", which is true but unhelpful when nothing was typed in. The merge itself
is unchanged: the whole of every object the shape touches is joined, not the part under the shape.

This is also why the consume step moved from the controller into the model: with no pick there is no
highlight box to clear it by, and a leftover drawing is now the input to the *next* action rather
than a harmless smudge. The condition is "the operation used the layer" - as the cut, as the bridge,
or to choose the objects - passed into `localObjectAction` rather than worked out there.

### Keyboard shortcuts (2026-09-02)

Proofreading is two-handed: the mouse stays on the object, and the other hand should not have to
travel to a button. `useShortcuts` puts three keys on the editor for as long as it is ticked:

| Key | Normally (`generateKeyShortcuts`) | While the checkbox is on |
|---|---|---|
| `a`, `shift+a` | Add selection to material | **Merge** / **AddToObject** / **AddObject**, by what the drawing covers |
| `s`, `shift+s` | Subtract from material | **Split by selection** - and when the drawing covers a whole object, that object is removed |
| `c`, `shift+c` | Clear selection | **Clear list and selection** - empties the picked objects, then clears the layer as usual |
| ++ctrl+f++ | Find material under cursor | **Add the object under the cursor to the selection** |

`c` empties the **list** and then clears the Selection layer through
`mibController.cSelection.clearSelection()`, so it is a superset of MIB's own `c` rather than a
replacement for it - including the scope rule, plain for the slice and `shift` for the stack.

*(Reversed on 2026-09-11. It first cleared the list only, on the reasoning that a shape drawn for the
next Merge should survive it. In use that is the wrong way round: once the drawing chooses the
objects, a drawing that picked the wrong ones is exactly what needs taking back, and the key that
looks like "start again" left half the state behind. The list is cleared first so the borrowed
highlight is released before the layer is cleared, or `releaseHighlight` would put its stash back
into a layer that had just been emptied.)*

Both `a` and `shift+a` have to be swallowed: MIB treats them as *one* shortcut with two scopes
(`overrideShift`), so leaving the shift variant through would let it write to the material. Here they
do the same thing - the 2D/3D scope is the `Mode3D` checkbox, not the modifier. `ctrl`+ and `alt`+
variants of `a` and `s` are declined and reach MIB untouched, as does every key when the checkbox is
off or when the dataset in front of the user is not an instance model.

++ctrl+f++ **adds** rather than replaces, which is the opposite of a plain click. Picking from the
keyboard exists to collect the two objects a Merge needs; replacing would make that impossible.
Clearing is the right-click menu on the *Selected objects* list.

**The takeover is a hook, not a callback swap.** `MibController.keyPressOverride` holds
`{owner, fcn}`; `gui_WindowKeyPressFcn` offers the key to `fcn` before looking it up in the shortcut
table and returns if it says it used it, and drops the claim by itself when `owner` is no longer
valid. Replacing the figure's `WindowKeyPressFcn` instead - the way pick mode replaces
`WindowButtonDownFcn` - would not survive: `@MibImageDocument` reinstalls that handle from five
places (after every pan, brush stroke and drag-and-drop), which is the same trap that killed pick
mode before `reassertPickMode`. The hook is empty for everyone else, so MIB's key handling is
unchanged until a child asks for it, and the next tool that needs a key can use the same door.

`closeWindow` gives the keys back, for the reason pick mode does: three keys held off their normal
duty across the whole application is not something the user can diagnose from the screen. The
checkbox follows `shortcutModeActive` rather than the other way round, so a takeover dropped from
anywhere cannot leave it claiming the editor still owns the keys.

The label is just `Shortcuts`; the mapping belongs in the tooltip, which is the .mlapp's:

> `a` = Merge, `s` = Split by selection, `c` = clear the list, `Ctrl+F` = pick the object under the
> cursor. While ticked these keys no longer add to or subtract from the material.

**Found while wiring it: the window was deaf to MIB's own shortcuts - twice over.**

The first fault was the payload. `MibController.listner_ModelEvent` unpacks the re-broadcast as
`evnt.Parameters.eventdata`, so what goes into `core.ToggleEventData` has to be a **struct carrying
the event under `.eventdata`** - which is what `DebrisRemoval`, `ImageFrame`, `ContentAwareFill` and
the rest all build by hand. `figureKeyPress` passed the `KeyData` object itself, so the listener
threw `MATLAB:nonExistentField` for *every* key pressed in this window, from the day it was written.
An error inside a listener is quiet enough that the window simply looked like it had no shortcuts.

The second was the callback. Keys were forwarded from `KeyPressFcn`, which on a `uifigure` fires only
while the figure *itself* has the focus, so even with the payload right it would have gone dead after
the first click on a button or a row. It is `WindowKeyPressFcn` now, and `figureKeyPress` gained the
edit-field guard that
`gui_WindowKeyPressFcn` cannot apply for a re-broadcast (it is handed no `CurrentObject` to look at),
so typing into `Go to object` no longer fires shortcuts. A key that is only a modifier is dropped,
but `Character` is **not** tested the way the other controllers test it: that would throw away the
arrow keys, and stepping through slices from this window is exactly what 2D mode is for. The
alternative, `utils.childWindowKeyPressFcn`, was not used: it whitelists Undo and Escape only, and
this window wants the whole set - ++i++ to interpolate the brushed break is half of the workflow it
exists for.

Reading the object under the cursor moved into `pickObjectUnderCursor`, now shared by the click and
the key - two call sites, so it earns its own file; `imageButtonDown` keeps only the part that works
out what the click *is*.

### Undo no longer throws the index away (2026-09-11)

Reported in use: ++ctrl+z++ after an edit turned the index red, and the next operation paid a
whole-volume rebuild. On the 624x1380x501 test model that is 1.5 s; on real data it is the one cost
in this tool that scales with the **dataset** rather than with the edit, which is exactly what the
bounding-box design exists to avoid everywhere else.

It never needed to. An edit here backs up **one bounding box**, `MibModel.undo` restores exactly that
box, and `buildInstanceIndex` already takes a box and a list of objects. Both halves existed; what
was missing was the region at undo time.

**The note rides with the undo entry.** `MibBackup.store` keeps the caller's options struct beside
the stored data, so an extra field put there by `localUndoRepairOptions` travels with the entry - through
the shifts of the ring buffer, and into the redo slot, because `MibModel.undo` passes the *same*
options to `replaceItem` when it fills it. `repairIndexAfterUndo` reads it back from
`Backup.undoList(Backup.undoIndex).options`.

Three things fall out of that choice, and they are why it beats the two obvious alternatives:

- **No parallel stack in the controller.** A shadow stack would have to stay aligned with an undo
  history the editor does not own - brush strokes, other tools, the ring buffer dropping its oldest
  entry, undoing past the editor's first operation - and misalignment fails by repairing the *wrong*
  box, which is the one failure this whole design exists to prevent. Nothing to align here: the note
  is attached to the thing it describes.
- **No change to `undo.m`, `backup.m` or `MibBackup`.** The first sketch added the region to the
  `Undo` event payload, which would have been wrong twice over: `Lines3dDialog` does
  `strcmp(evnt.Parameters, 'lines3d')` on that event, so a struct payload would have silently
  returned false and killed its refresh.
- **One note serves both directions.** Re-measuring a region is direction-agnostic. Storing a copy
  of the index rows instead - the cheaper option on paper, needing no volume read at all - would have
  had to know whether it was undoing or redoing, and MIB's undo is a swap that toggles.

The box carried is the **rescan** box, not always the backed-up one: growing an object writes only
the drawing but has to be measured over the whole of the object, which `localDrawingToObject` already
knew and now shares with the undo path.

Failure is always towards a full rebuild: no note, a note from another dataset or time point, or an
index already stale for some other reason, and `repairIndexAfterUndo` returns false. `Cleanup` and
`Compact` deliberately leave no note - no box describes them - and a brush stroke on the model layer
never had one. Being slow is acceptable; acting on a region that does not describe what was restored
is not.

**The first version of that last guard defeated the whole thing.** It refused to repair a stale
index, on the reasoning that staleness from an unrelated earlier change is not covered by one box.
Correct in itself, and wrong here: `MibModel.undo` writes the restored voxels **before** it fires its
`Undo` event, so `dataChangedElsewhere` has already marked the index stale by the time the handler
runs - marked it for the very write the handler is there to account for. Every repair therefore
refused, and the status went red exactly as before. Measured rather than reasoned about, since the
ordering is the whole point:

```
event order during undo:   SetData(labels) -> Undo
```

So `markIndexStale` now records the **fresh-to-stale transition** in `indexFreshBeforeWrite`, and the
handler repairs a stale index only when that transition is the one this undo caused. Writes arriving
while the index is already stale leave the flag alone, so a burst still describes the first
transition. The flag is cleared by the Undo handler whatever it decides, which is what closes the
hole the guard was written for: an undo that could not be repaired leaves the index stale *and*
unclaimed, so stepping further back onto an entry that does carry a note cannot mistake that older
staleness for its own.

`undoWritesTheVoxelsBeforeAnnouncingItself` pins the ordering, because the handler cannot check it
for itself and the failure is silent in both directions - a reversal would either strand the repair
again or, worse, let it run against staleness it does not cover.

### Compact says what it did (2026-09-11)

Asked for after a run: `Compact` changed every number in the list and said nothing. It is the one
action that rewrites what the user has been navigating by while changing nothing they can see, so it
now reports what it did.

**In a message box, not the command window.** It first went to `fprintf` like `Cleanup`, and the
answer from the first use was *"ohh, I see it is in the terminal"* - which is the whole objection:
MIB runs in an AppContainer and the command window is behind it, so a line there is a line nobody
reads at the moment it matters. `localReport` is the counterpart of `localComplain` for a result rather than
a refusal, and differs from it in exactly two ways:

- the no-parent fallback goes to **stdout**, not stderr. Work done is not an error, and the tests
  read the figures from there
- callers pass `allowDialog`, which `Compact` sets from `~batchModeSwitch`, so a protocol looping
  over datasets is not stopped by a box per iteration

```
3D  Renumbered 1 of 3 objects.
        2 objects already had their final number.
        Highest index: 5 -> 3
        2 unused indices reclaimed.

2D  Renumbered 2 of 3 slices with objects.
        1 slices were already numbered 1, 2, 3...
        4 slices in the stack.
        Highest index: 6 -> 3
        Each slice is numbered on its own, so one index means a different object on each.
```

The headline carries the figure that answers *"did it do anything"*; everything else sits under it.

**`Cleanup` followed immediately**, through the same helper:

```
    1 objects removed, 0 fragments absorbed.
        0 voxels were handed to neighbouring objects.
        2 objects left in the model.
        Object numbers are unchanged - use Compact to renumber.
```

Its report moved out of the `switch` to sit beside Compact's, after `delete(wb)`: a modal box raised
while the progress dialog is still up goes *behind* it. That the last line repeats what
`askCleanupSettings` already says is deliberate - the two are read minutes apart, and the question
after a cleanup is whether the numbers in the list still mean what they did.

Both **cancel** paths stay on `fprintf`. Cancelling is the user's own action and the box would be a
second click to dismiss something they already know; what matters there - that the model was not
changed - is true of every cancel in this file.

Everything reported is derived from the index **taken before** the renumbering: the new number of an
object is its rank among the values in use, so `oldIds == 1:n` is exactly the set that kept its
number, and `oldMax - newMax` is the reclaimed space. No extra pass over the volume.

**Compact follows the mode** (asked for straight after, and the reason the first answer asked for a
count of slices). `squeezeMaterialLabels` is one `unique()` pass over the whole label space, which is
right for a stitched model and does nothing useful on an unstitched one: there the numbering restarts
on every slice, so every value is in use *somewhere* and a global squeeze closes no gap at all. The
gaps on such a model are per-slice gaps. So in 2D each slice is now tightened on its own - a slice
holding 1, 3, 5 becomes 1, 2, 3, independently of what its neighbours hold - which leaves the model
exactly as it already was in kind, one numbering per slice.

The loop is the only place in this file that walks the volume slice by slice, so it carries the
obligations that go with it: a determinate cancelable progress bar, mutation of a **local copy** with
a single `setData3D` at the end, and therefore no partial write on cancel. A slice already at 1..n is
skipped, which is what makes "slices renumbered" a real number rather than the depth of the stack.

The reported figures differ with the mode, because the quantity differs. Per slice there is no single
object count - the same index is a different object on each slice, which is the whole reason this
mode exists - so what is counted is slices with gaps and the drop in the highest index. The 3D branch
keeps the object-level figures and the count assertion below.

**The denominator is slices carrying objects, not the depth of the stack.** An empty slice is not a
slice that was already in place; there is nothing on it to number. Counting it as one would report
*"renumbered 2 of 501"* on a stack whose objects sit on forty slices - a ratio that describes the
dataset rather than the work. The stack depth is still given, in brackets, because the difference
between the two numbers is itself worth seeing. The test keeps one slice deliberately empty for this.

Two things fall out of writing it:

- **The object count is asserted, not assumed.** Renumbering must not add or remove objects, so a
  disagreement between the old count and the rebuilt index goes to stderr. Nothing has produced it;
  it is there because this is the operation whose damage would be hardest to recognise.
- **`squeezeMaterialLabels` renumbers each time point independently** - its `unique()` runs inside
  the `for t` loop - so on a 4D instance model whose time points hold different label sets, object 7
  at t=1 and object 7 at t=2 can map to different new numbers. The message says which time point its
  figures describe when there is more than one, but the underlying behaviour is left alone: instance
  models are single-time-point in every path that reaches here today, and fixing it means deciding
  what object identity across time should mean. Worth knowing before that decision is made.

### `s` over a whole object removes it (2026-09-11)

Found in use: a drawing covering the whole of object 51 was refused with *"The Selection layer covers
the whole of object 51 - nothing would be left"*, when what the user meant was plainly "remove this".

The refusal came from reading the action as a *split*, which has to leave two pieces. But `s` is
`Subtract from material` - that is the key it takes over and the sense it keeps - and subtracting a
drawing that covers everything leaves nothing. It is the same shape of decision as the `a` table
above: the gesture is fixed and **what the drawing covers** decides the outcome. Refusing the
degenerate case made the one gesture meaning "delete this" unreachable from the key the user already
had a hand on, with **Delete** and a pick as the only way round.

Deleting the guard is the whole change. `localComponentMasks` returns `{}` for an empty mask, so the
removal write that was already queued below it becomes the entire operation, and the index refresh
does the rest: in 3D the object loses every voxel and its index is freed for the next split; in 2D
the box is clipped to the shown slice, but `utils.instances.objectIndex` unions the refresh region
with the object's **previous** bounding box, so what survives on the other slices is recounted rather
than forgotten. That union was written for a different reason and is what makes the 2D case correct
for free.

Two cases pinned in `EditInstanceObjectsTest`: the object gone and its index free in 3D, and the
object still present with one slice cleared in 2D.

**The pick is the selection when nothing is drawn.** Reported straight after: picking an object by
click and pressing `s` left it there. It fell through to a split that found nothing to cut, queued an
empty write, and reported success - the worst of the possible answers, since it also spent an undo
step. The reading that was missing is the one the screen was already showing: `highlightObjects`
paints the picked objects **into the Selection layer**, so a pick and a drawing covering the whole
object are the same picture, and the case above had just made the second of them remove the object.
The refusal message for the empty case had been promising this all along - *"Draw the break into it
first, or pick the objects from the list"* - and picking alone did nothing.

So `SplitBySelection` with objects named and **nothing drawn anywhere** becomes `Delete`, decided
once at dispatch rather than per object:

```matlab
if strcmp(action, 'SplitBySelection') && ~derivedFromDrawing && ...
        isempty(localDrawingExtent(obj, id, dataset, timePoint, BatchOpt.Mode3D))
    action = 'Delete';
end
```

Three things make this the right shape:

- **The test is "is anything drawn at all", not "is anything drawn over this object".** Per object it
  would delete a picked object merely because the drawing lies on a different one, which is a
  reading nobody asked for. `localDrawingExtent` answers the question for the whole layer in 3 ms.
- **`Delete` already does the 2D case**, clipping to the shown slice through `localObjectPixels`, so the
  mode is respected without new code.
- **`consumesSelection` becomes false**, which is correct: no drawing was used, so there is none to
  use up. It follows from the action name alone and needed no extra condition.

A drawing plus a pick is untouched: that is still "cut this object and leave the neighbour the line
also crosses alone", and it has its own test so the two readings cannot drift.

### The drawing reaches the next slice (2026-09-11)

First real 3D use case, reported by the author: brush the gap, then join the object on `z-1` to the
object on `z+1`. That was already possible - `Connect` in `selection` mode - but it cost **three**
manual steps where the drawing had already answered two of them: pick A, pick B, press the button.

The gesture was already there - it is the 2D one. A stroke drawn across two objects and committed
with ++a++ joins them, and has done since [the drawing chose the objects](#the-drawing-chooses-the-objects-2026-09-01).
What broke in a volume is not the gesture but the **question asked of the stroke**:
`localObjectsUnderSelection` reads the labels at the drawn voxels, and the object being joined to is
on the next slice, where nothing is drawn at all. A same-slice test, in a mode whose whole subject is
3D objects.

So the reach changed, not the gesture. `localObjectsToJoin` is the counterpart of
`localObjectsUnderSelection`, and the difference between the two is the whole of it:

| | asked by | reads |
|---|---|---|
| a **cut** | `SplitBySelection` | what the drawing covers - voxels it merely lies against are not being taken out of anything |
| a **join** | `Merge`, `Connect` | what the drawing covers, and failing that what lies one slice beyond either end of it |

In 2D the second half is skipped and the two are identical, which is right: there is no next slice in
a single-slice mode.

**What you can see, you get all of; what you cannot see, you get one of.** Contact on a slice the
user drew on is deliberate and on screen, so every object there counts, as it always has. The slice
beyond the stroke is neither drawn nor visible: a stroke clipping the corner of a neighbour there is
the ordinary case, and silently swallowing that neighbour is the one outcome this must not produce.
Each end therefore contributes at most one object, by footprint under the stroke - not by total size,
which would let something large elsewhere in the box beat the one being pointed at. Two details
follow: the overlap is measured against the **drawn mask** on the outermost plane rather than its
bounding box, which a diagonal stroke would make far too generous; and it is exactly one slice, never
two, so the drawing has to abut what it joins and the choice stays something the user can see before
pressing anything.

**`Connect` with nothing picked is now the same code.** Joining two objects and giving them the
background drawn between them is a drawing-driven `Merge` exactly - `localMergeWrites` +
`localAbsorbDrawing` against `localAbsorbDrawing` + `localMergeWrites`, the same two writes in the
other order over disjoint voxel sets. So the action becomes `Merge` at dispatch and
`localPlanConnect` is never reached, which is what keeps `ConnectMode` out of it: the alternative was
forcing the dropdown to `selection`, which would either have gone out on `SyncBatch` and silently
changed what the user was looking at, or needed a tenth argument threaded through the dispatch to say
so. The `BatchOpt` still says `Connect`, so a protocol replaying it lands here again. The two buttons
differ only when objects are named - which is where `interpolate` lives, and it is the one form that
needs no drawing at all.

The three-way outcome needed no new branch, `Merge`'s existing one already reading it: two objects
join, one object grows by the drawing (`AddToObject`), none makes the drawing a new object
(`AddObject`).

**The argument against putting it on ++a++, and why it lost.** `a` also means *"paint what the
prediction missed and commit it"* (D1d, J3a), so a lookahead risks gluing a newly painted object to
whatever sits above or below it - which the user cannot see, those slices not being drawn. The reason
that is weak: in an instance model an object at the same XY one slice away is usually the *same*
object continuing. `stitch2Dto3D` is built on precisely that premise - overlap between adjacent
slices **is** its definition of one object - so gluing is right far more often than it is wrong, and
where it is wrong the object count moves in the list and ++ctrl+z++ is one step. Against that, the
cost of keeping it off `a` was a second gesture for the same intention, and a mode in which the key
already under the user's hand quietly did the wrong thing.

*(This section first recorded the opposite decision - `Connect` only - on that risk. The author's
objection was that the 2D and 3D cases are one gesture and should not be two buttons.)*

**No report on success.** Unlike `Compact`, this is a per-object action pressed hundreds of times in
a session, and a modal box per press is what the cleanup filters were moved out of the window to
avoid. The result is on screen and ++ctrl+z++ is one step. Reconsider if the automatic choice turns
out to surprise in use; the refusals already speak through `localComplain`.

Nine cases in `EditInstanceObjectsTest`. The two that pin the shape of it:
`connectFromADrawingUsesWhatItCoversFirst`, a stroke laid across two objects in-plane with a third
straddling it in Z, asserting the third is untouched; and `mergeFromADrawingIn2DStaysOnTheSlice`, the
same stroke in 2D asserting it becomes a new object instead. Neither reading can drift into the other.

### The window reopens as it was left (2026-09-11)

`Mode3D`, `autoUpdateTable`, `pickByClick` and `useShortcuts` now live in
`sessionSettings.instanceEditor` beside the cleanup and list settings, read back by
`storedWindowState` and written by `rememberWindowState`. The defaults below are unchanged, so the
first opening on a machine is exactly what [the section after this one](#the-window-opens-in-2d-2026-09-02)
describes; it is the second that differs.

Three things decide whether this is right or merely convenient:

- **The takeovers are restored through `setPickMode` / `setShortcutMode`, never by writing the
  checkbox.** The mouse and the keys are owned by controller state and the checkbox follows it. A
  restored `pickByClick` that found no image document has to come back **off**, and only the method
  knows that. It also means opening the window can set `disableSegmentation` and swap the image
  document's `WindowButtonDownFcn` as a side effect of construction - accepted deliberately, because
  the alternative is a checkbox that says the editor owns the mouse when it does not.
- **The state is saved from the four callbacks, not from `closeWindow`.** What is kept is what the
  user *chose*. `reassertPickMode` drops the takeover when a different document becomes active, and
  that is not a decision to stop picking; saving at close would record it as one. It also survives a
  window that goes away without closing cleanly.
- **`Connectivity` is still restored as a stance, but now against the restored mode** rather than
  against a window that always opened in 2D. The mode is read first, the item list follows it, and a
  stored `26` comes back as `26` when the editor reopens in 3D and as `8` when it reopens in 2D.
  This is the rule `mode3D_Callback` applies on every switch; it now runs once more, at construction.

Deliberately **not** in the preferences file, for the reason the cleanup thresholds are not: these
are how one proofreading run is being done, and a poor opening offer for the next dataset.

### The window opens in 2D (2026-09-02)

*(Still the first-opening default; from 2026-09-11 a later opening restores the mode it was left in -
see the section above.)*

`Mode3D` now starts **off** in the controller, with `Connectivity` starting at 8/4 to match - the
dropdown otherwise offers 26/6 while the operations run per slice. Only the editor's default moved;
`editInstanceObjects` still defaults to 3D, which is right for a programmatic caller ("act on the
whole object unless told otherwise") and is what every headless test and batch protocol assumes.

It exposed one thing in `updateStatusLine`: it refused to say anything without a usable index, in
either mode. The index is a whole-volume pass and is never built behind the user's back, so the
window would now open reading *"Objects not indexed yet"* while a perfectly good 2D list sat under
it. The 2D branch is measured from the slice and needs no index, so it now reports the slice either
way and appends the model total only when the index is there - and says so, in amber, when it is not,
which keeps the staleness signal of group **F** visible in this mode too.

Untested by the suite: `InstanceEditor` has no view-less construction path (`tests/CLAUDE.md`
pattern 1), so none of the controller is reachable headlessly. Adding one means a `createView` opt-out
plus `hasWidget` guards on every widget read - a change worth making deliberately, not while fixing
this.

### Widgets follow the mode (2026-09-04)

`applyModeToWidgets` grew from two lines to two lists. The test for membership is *"the other mode
cannot do this at all"*, not *"the other mode does it differently"*:

| Group | Widgets | Why |
|---|---|---|
| volume only | `cutAtSliceButton`, `connectButton`, `ConnectMode` (+ label) | Cut at slice refuses a single slice outright; Connect works along Z |
| slice only | `autoUpdateTable`, `updateTable` | the 2D list follows the shown slice; in 3D the list comes from the index and `Rebuild` is what renews it |

**Connect was the one that mattered.** It was not merely useless in 2D - it was actively dishonest.
`localPlanConnect` ends with `localObjectPixels(obj, id, index, other, timePoint, 0, true)`: `use3D` is
hardcoded `true`, so the merge takes the **whole** of both objects through the entire stack whatever
the checkbox says. An operation that appears to obey the mode and does not is worse than one that
refuses, and unlike `CutAtSlice` there was no guard in `editInstanceObjects` to catch it. Disabling
the button is the fix at the level the user meets it; a guard in the model would be the belt to that
brace, and is not there.

`Cleanup` and `Compact` deliberately stay on in both modes. They read the whole volume regardless of
`Mode3D` - that is what they are - and someone working slice by slice on a stitched model still has
every reason to reach for them. Their filters are asked for in full in both modes for the same
reason: `minObjectSlices` is a Z-span filter, and Cleanup is always a Z operation.

Labels are switched with their widgets (`ConnectModeDropDownLabel`), so a greyed setting no longer
keeps a live-looking caption beside it. `filterMaxSlices` had that fault since it was written; it has
since left the window altogether, and the 2D list settings dialog simply does not ask the question.

### Are Connect and Cut at slice redundant in 3D? (2026-09-04)

Asked by the author: does `Merge` already cover `Connect`, and `SplitBySelection` already cover
`CutAtSlice`, once `Mode3D` is on? Measured on synthetic models rather than argued:

| Case | Result |
|---|---|
| Connect vs Merge, two objects **overlapping in Z** | **identical volumes**. `overlapInZ` is true, the whole bridge block is skipped, and the only write left is `other -> survivor` - which is Merge's write exactly |
| Connect vs Merge, two objects with a **real Z gap** | different: 294 -> **441** voxels vs 294 -> 294. Connect leaves **one** connected piece, Merge leaves **two** sharing an index |
| CutAtSlice vs SplitBySelection over one slice | different: 294 -> **294** voxels vs 294 -> **245**. The cut is lossless; the split destroys the drawn voxels by design |
| CutAtSlice on a tail that is two disconnected lobes | the tail keeps **one** index. `CutAtSlice` cuts by Z position (`componentMasks = {objectMask & tail}`); `SplitBySelection` runs connected components and would give the lobes separate indices |

So both buttons earn their place - but the question found something. **`Connect` degenerated into
`Merge` whenever the two bounding boxes overlapped in Z, and said nothing about it.** The test at the
top of `localPlanConnect` is a bounding-box test, not a proximity test, so two objects in opposite corners
of the volume that merely share a Z range took the degenerate path: measured, 490 -> 490 voxels,
index 4 gone, and object 1 left as **two disconnected pieces**. That is the one outcome the operation
exists to prevent, produced silently under the name "Connect".

### The unification (2026-09-04)

Author's call after the measurements above: share the code, and fix the one place where the same
gesture had two rules.

**One definition of "the drawing".** `localDrawingExtent` replaces three copies of "read the Selection
layer, find its extent". They had already drifted - `localObjectsUnderSelection` narrowed to the slices
carrying the drawing and read labels across the full XY plane, `localDrawingToObject` computed the whole
box. Now both take the box, so the labels read is narrower than it was, and there is one place where
the copy-on-write fast path of `getData3D` has to be preserved instead of three.

**One rule for what a drawing means.** `localAbsorbDrawing` writes the drawn **background** to an object,
and both gestures that need it now call it:

| Gesture | Before | After |
|---|---|---|
| Merge over one object, from a drawing | drawn background joined the object | unchanged |
| Merge over 2+ objects, from a drawing | drawn background stayed background - one index, two pieces | joins the survivor |
| Connect, `selection` mode | its own read of the layer, restricted to the Z-gap band | the same call, no band restriction |
| Merge over objects picked **by name** | drawing untouched | unchanged - absorption follows the *input*, not the layer |

That last row is the line: the drawing is absorbed when it is what chose the objects, never when it
merely happens to be lying there. `consumesSelection` already means exactly that, and for `Merge` it
is `true` precisely when `derivedFromDrawing` is - so no new argument was needed to say it.

**One merge.** `localMergeWrites` is Merge's whole body and Connect's last step. Connect had its own copy
with `use3D` hardcoded `true`, which is what made it ignore `Mode3D`; it now takes the parameter, and
`localPlanConnect` refuses 2D outright with the same message shape `CutAtSlice` uses.

**Consequences worth knowing:**

- `selection` mode no longer needs a gap in Z. Its bridge is what the user drew, so nothing about how
  the two objects lie is asked; the pair that overlaps in Z but lies side by side is now reachable,
  and it is the answer to the defect above. `interpolate` still needs a gap - it has to have two
  faces to morph between.
- The drawing is read twice on a drawing-driven Merge: once to find the objects, once to absorb it.
  Both are the 3 ms reduction, not the 83 ms `find()`, and the alternative was threading the box
  through the dispatch as a tenth argument.
- `localPlanConnect` returns `bridged`. When it is false and the two boxes cannot touch
  (`localBoxesCanTouch`, a one-way test that never cries wolf), the user is told the objects were joined
  but nothing was bridged. Not a refusal: two objects that genuinely touch have no gap to fill and
  joining them is the right answer.

### Verification

`buildtool check` clean; `buildtool test` green including the 71 new cases (18 + 15 + 38). The stitcher's own 25
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
| A1 | *Ribbon -> Model -> Model tools -> Instance editor*, first time in this MIB session | Window opens to the left of MIB, in **2D** mode: `3D (whole object)` unticked, connectivity 8/4 |
| A1a | Tick `3D (whole object)`, `Shortcuts` and `Pick objects by clicking`, untick the automatic list refresh, close the editor, reopen it | All four come back as they were. Then check the two takeovers really are live, not just ticked: press ++a++ over a selection and click an object. A checkbox that is on while the mouse or the keys are not actually held is the failure to watch for |
| A1b | Reopen it with the image document closed, or on a buffer with no model | `Pick objects by clicking` comes back **off** rather than ticked-but-dead |
| A1c | Set connectivity to the full neighbourhood in 3D, close, reopen | Still 3D and still full - `26`. Untick 3D, close, reopen: 2D and `8`, the same stance in the other mode's numbers |
| A2 | Look at the status line | `Slice N: K objects...` - the list is the shown slice, and it says so without an index having been built |
| A3 | Tick **3D (whole object)**, press **Rebuild**, look again | `N objects, highest index M`, green. Compare N with the object count the stitcher reported: same number |
| A4 | Note how long that Rebuild took | The index build is one pass over the volume; a few seconds on a 100-slice stack. **If it is much worse than that, say so** - the whole design rests on this being affordable |

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
| B4 | **Max size** 50 in the settings dialog | Only objects that small are listed as soon as it is accepted; `0` restores all |
| B5 | **Max rows** 50 on a model with thousands | Only 50 rows; the tool stays responsive |
| B5a | Reopen the dialog | It opens on the values just entered, and again after closing and reopening the editor |
| B5b | Open it in 2D mode | No **Max slices** question, and the connectivity offers 8/4 rather than 26/6 |
| B6 | Type a known index into **jumpToIndex** | That object is selected and the view moves to it |
| B7 | Type an index that does not exist | *"There is no object N in this model"*, nothing selected |
| B8 | Click one row | View centres on the object, slice jumps to it, object appears in the Selection layer |
| B9 | Ctrl-click / shift-click several rows | All of them highlighted together |
| B10 | Highlight one entry in **Selected objects**, right-click, *Remove highlighted from selection* | Only that object leaves the selection and the highlight; *Clear list* empties it |

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
| D1b | Brush one shape across two objects, pick nothing, **Merge** | Same result. The whole of both objects is joined, not just the part under the shape, and the shape is gone afterwards |
| D1c | Brush a shape half over one object and half onto background, pick nothing, **Merge** | The object grows by the new part, keeps its index, and no new index is handed out. Check its voxel count in the list before and after |
| D1d | Brush a shape on empty background, pick nothing, **Merge** | It becomes a new object with the next free index, listed with exactly the drawn voxels, and the shape is used up. ++ctrl+z++ removes it |
| D2 | Merge three at once | All take the smallest index |
| D3 | Find an object whose index covers two separate blobs, **Split components** | Largest piece keeps the index; the other gets a new one. Both listed |
| D4 | **Split components** on a normal object | Nothing happens, no error |
| D5 | Move to a slice in the middle of an object, **Cut at slice** | Everything from that slice onwards becomes a new object |
| D6 | **Cut at slice** on the object's first slice, and on a slice outside it | Refused with a message naming the object's slice range |
| D7 | Two objects with a Z gap, **Connect** (`interpolate`) | Gap filled, both now one object with the smaller index |
| D7a | In 3D, brush the gap between an object on z-1 and one on z+1, pick nothing, press ++a++ (or **Merge**) | The two are joined and the brushed area is part of them - one connected object with the smaller index. The same gesture as D1b, one slice further |
| D7b | The same with the stroke slightly too wide, clipping the corner of a neighbour on z-1 | Only the object it mostly lands on is taken. Check the neighbour's voxel count in the list before and after |
| D7c | Brush a shape whose far end reaches nothing, pick nothing, ++a++ | The object at the near end grows by the shape and keeps its index - no new index handed out. On empty space at both ends it becomes a new object instead (D1d) |
| D7d | Brush a stroke straight across two objects **on the same slice**, pick nothing, ++a++ | Those two are joined, not whatever lies above and below the stroke. What the drawing covers is asked first |
| D7e | The **same drawing as D7a**, but in 2D mode | It becomes a new object on that slice. The reach is a property of 3D mode, not of the gesture |
| D7f | Repeat D7a with **Connect** instead of ++a++, nothing picked | Identical result - the two are the same code once nothing is picked, and `Connect Mode` is not consulted. Pick the two objects and it becomes the `interpolate`/`selection` operation again |
| D8 | **Connect** across a gap that has a *third* object sitting in it | The third object is untouched. Check its voxel count in the list before and after |
| D9 | Brush a bridge into the Selection layer, **Connect** (`selection`) | Only the brushed area is used |
| D10 | **Connect** on three objects | Refused |
| D11 | Select some noise, **Delete** | Gone; index freed and reused by the next split |

### E. The brush workflow

The reason the tool exists. On a false merge - one index covering two mitochondria:

1. Brush the break into the **Selection** layer where the two should separate.
2. In 3D, brush it on a few slices and press ++i++ to interpolate between them.
3. Press **Split by selection**. Nothing needs to be picked - the drawing says what to cut. Pick an
   object only to keep the cut off a neighbour the line also crosses.

Expect: the brushed voxels are cleared out of the object and the two halves become separate objects,
in **one** ++ctrl+z++ step. Compare against doing it by hand (++shift+s++ to subtract, then
**Split components**) - the result should be the same.

The editor borrows the Selection layer for its highlight, so the drawing and the highlight share it.
What that has to look like:

| # | Do | Expect |
|---|----|--------|
| E0 | Brush a break, pick nothing, **Split by selection** | The object under the drawing is split. No *"pick the objects to work on first"* |
| E0b | Brush a line that crosses two objects, pick nothing, split | Both are cut. Then pick one of them first and repeat: only that one is cut |
| E0c | Brush somewhere on background only, split | *"The Selection layer does not cover any object"*, and the drawing is still there to be moved |
| E0d | Brush over the **whole** of one object, pick nothing, split | The object is removed and its index freed - no *"nothing would be left"*. ++ctrl+z++ brings it back |
| E0e | The same in 2D, on an object spanning several slices | It goes from the shown slice only; the list still has it on the others, under the same number |
| E0f | Pick an object by clicking, draw **nothing**, press ++s++ | The object is removed - the highlight in the Selection layer is what the key subtracts. It used to sit there unchanged while the operation reported success |
| E0g | Pick an object, brush a break across it and a neighbour, press ++s++ | Only the picked one is cut, and it is **cut**, not removed. The pick stands in for the drawing only when there is no drawing |
| E1 | Brush a break, then pick the object | The object lights up. The break is underneath it and the split below still works - this is the sequence that used to fail with *"the Selection layer covers the whole of object N"* |
| E2 | Draw somewhere else in the dataset, then pick an object | The drawing is still there. Picking used to clear the whole layer, on every click |
| E3 | Split by selection, then look at the Selection layer | The drawing that was used is gone; the rest of the layer is untouched |
| E4 | Pick an object, then start brushing on it | The highlight disappears at the first stroke and drawing behaves normally from then on. The stroke that cleared it is not kept - draw first, pick second |
| E5 | Pick an object, close the editor | The Selection layer is what you drew, not the object that was highlighted |
| E6 | Brush a bridge in a Z gap, pick two objects, **Connect** (`selection`) | The bridge is used, not the highlight. Same failure as E1 before the fix |

### F. Staleness - the correctness one

| # | Do | Expect |
|---|----|--------|
| F1 | With the editor open, brush on the model in the main window | Status line turns red: *"Index is out of date"* |
| F2 | Now run any operation | It rebuilds the index first, then acts - and acts on the **right** voxels |
| F3 | Press ++ctrl+z++ after a **brush stroke on the model** | Status goes red - a stroke leaves no repair note |
| F3a | Press ++ctrl+z++ after an **editor operation** | Status stays green and the object count follows the undo. No rebuild, no pause: the undo entry carried the region. Press it again to redo - still green |
| F3b | Time F3a on the largest model you have | Should be instant whatever the size. If it pauses, the note was not recognised and it fell back to a rebuild - the DeveloperMode line `repairIndexAfterUndo: index repaired over [...]` is what says which happened |
| F4 | Press **Rebuild** | Green, with the object count matching the model |
| F5 | Change time point on a 4D dataset | The list follows the shown time point |

The failure to watch for: an operation that edits *somewhere other than the object you picked*. That
is what a stale bounding box does, and it is silent.

### G. Cleanup and Compact

| # | Do | Expect |
|---|----|--------|
| G1 | **Cleanup**, **Min object size** 50 in the dialog | Small objects gone; **the survivors keep their numbers** |
| G2 | **Cleanup**, **Min object depth** 1 | Single-slice objects gone |
| G3 | **Cleanup**, **Absorb fragments** 5 | Object count drops but the labelled voxel total barely moves - specks are handed to their neighbours, not deleted |
| G3a | Press **Cleanup** again | The dialog opens on the values just used |
| G3b | Cancel the dialog | Nothing runs, and the previous values survive |
| G3c | Set values through the gear button, then press **Cleanup** | The dialog opens on them; accepting cleans with them |
| G3d | Close and reopen the editor | The dialog still opens on the last values - they live in `sessionSettings`, not in the window |
| G3e | Let a cleanup finish | A box reports what was removed, what was absorbed and what is left, and reminds you that the numbers did not change |
| G4 | Press Cancel on the progress dialog mid-run | Model unchanged, and the note goes to the command window rather than a box - you already know you cancelled |
| G5 | **Compact** | Numbering becomes 1..N with no gaps |
| G5a | Read the box it puts up | How many objects were renumbered, how many kept their number, and the highest index before and after. On a model with gaps the reclaimed count should equal the drop in the highest index |
| G5b | **Compact** in 2D mode, then press Cancel on the progress dialog part way | The model is unchanged - the slice loop writes into a copy and only commits at the end |
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
| I3 | Open the detection settings | No slice filter is offered at all - there is no slice count to filter on here |
| I3a | **Cut at slice**, **Connect**, **Connect Mode** | All greyed out - both operations work along Z. Connect in particular used to stay live and merge the whole of both objects through the stack, ignoring the mode |
| I3b | **Cleanup**, **Compact**, the gear button | Still live. They read the whole volume whatever the mode says, which is intended |
| I3d | **Compact** here, on an unstitched model | Each slice is renumbered on its own: a slice holding 1, 3, 5 becomes 1, 2, 3. Check two slices with different gaps. The same press in 3D mode closes nothing on such a model, every value being in use somewhere - that is the difference the mode makes |
| I3c | **Update list**, **Update the list on slice change** | Both live here; both greyed out in 3D mode |
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

### J. The keyboard shortcuts

Group **C** is the same set of hazards for the mouse; this is the one for the keys.

| # | Do | Expect |
|---|----|--------|
| J0 | With the editor focused, press ++ctrl+z++ after any edit | It undoes, checkbox or no checkbox. Then click a button or a table row and try again. Also ++i++ and the arrow keys: **no** key at all used to reach MIB from this window |
| J1 | Tick **Shortcuts**, hover an object, ++ctrl+f++ | It is selected and highlighted |
| J2 | Hover a second object, ++ctrl+f++ | Both are selected - it adds, unlike a plain click |
| J3 | Press ++a++ | They merge, exactly as the button does |
| J3a | Brush on empty background and press ++a++; then brush onto an existing object and press ++a++ again | A new object, then that object grown - D1d and D1c from the keyboard. This is the whole point of the key: paint what the prediction missed and commit it without leaving the brush |
| J3b | Pick two objects with ++ctrl+f++, draw a shape, press ++c++ | The list, the highlight **and** the drawing are all gone - `c` clears the list and the layer. ++shift+c++ clears the layer through the stack, as it does in MIB |
| J4 | Brush a break, press ++s++ | The object under the drawing splits |
| J5 | Press ++shift+a++ and ++shift+s++ | Same as without shift. **Nothing is added to or subtracted from the material** - that is the failure to watch for, and it is silent |
| J6 | Press ++ctrl+a++, ++alt+s++, ++i++, ++c++ | MIB's own behaviour, untouched |
| J7 | Untick the checkbox, press ++a++, ++s++ and ++c++ over a selection | Add to material, subtract from material and clear selection are back |
| J8 | Tick it, then **close the window** | Same as J7. **This is the one that makes MIB confusing if it is broken** |
| J9 | Tick it, then switch to a dataset with no model (or a 63-material one), press ++a++ | MIB's own shortcut runs. The editor declines keys it cannot act on rather than swallowing them |
| J10 | Tick it and type into **Go to object** | The number goes in; the keys are not stolen from the field |

### What to report back

- The A4 index-build time and the object count it was measured on.
- **I2** and **I6** - whether the 2D list now describes the slice, and what a slice step costs.
- Anything in **C8** or **F** - those two are the ones that can do real damage.
- Whether the operations are fast enough to work through a model object by object, which is the
  whole point of the bounding-box design.
