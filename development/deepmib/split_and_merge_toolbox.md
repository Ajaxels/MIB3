# Instance editor - split and merge toolbox

Working reference for `controllers.InstanceEditor` and `MibModel.editInstanceObjects`. Implemented
2026-08-29, refined through 2026-09-12. Read this before changing any of the files below.

Manual (mouse/visual) checklist: [`instance_editor_manual_tests.md`](instance_editor_manual_tests.md)
- still pending on real data. Background on the stitcher this proofreads:
[`instance_3d_plan.md`](instance_3d_plan.md). Decision history: git before `0581b63a`.

## What it is

An editor that lists the objects of an instance model and applies split / merge / connect / delete,
backed by a cached per-object index so each action touches only the affected bounding boxes instead
of scanning a multi-GB volume. It is the manual proofreading step after
`utils.instances.stitch2Dto3D`, whose residual errors are structural rather than threshold-tunable.

**Scope.** 65535 and 4294967295 instance models on `Standard` datasets only. `Virtual` and `BigData`
are rejected with a message (BigData labels are `core.MibBigDataLabels < core.MibLabels63`, capped at
63 packed materials, so they cannot hold an instance model at all). Not in scope: seeded watershed,
isolate/show-only rendering, 63/255-material models, mask-layer objects.

## Files

| File | Role |
|---|---|
| `mib/+utils/+instances/objectIndex.m` | pure: label volume in, per-object index out. Full build and bbox-scoped refresh |
| `mib/+utils/+instances/cleanup.m` | pure: absorb-fragments + min-voxels + min-slices. Extracted from the stitcher, called by both |
| `mib/+core/@MibDataset/buildInstanceIndex.m` + `instanceIndex` property | owns the cache for one time point |
| `mib/+models/@MibModel/editInstanceObjects.m` | all ten actions, BatchOpt-driven. Undo, progress, notifications, incremental index update |
| `mib/+controllers/@InstanceEditor/` (14 files) | window, object list, click picking, highlighting |
| `mib/+views/InstanceEditorGUI.mlapp` | **author-built - never edit it** |
| `tests/utils/InstanceObjectIndexTest.m` (18) · `tests/utils/InstanceCleanupTest.m` (15) · `tests/models/EditInstanceObjectsTest.m` (38) | 71 cases |

Wired into the ribbon from `addRibbonModel.m` (`"Model tools"` section) -> `MibRibbon.m` ->
`model_Callbacks.m` -> `startController('controllers.InstanceEditor')`. The ribbon is built at
startup, so a new button needs a MIB restart. User docs:
`docs/docs/user-interface/ribbon/model/model-instance-editor.md`, in the `nav` of
`docs/zensical.toml`.

**Every operation lives in `MibModel.editInstanceObjects`, not the controller**, so it is driveable
from batch protocols and testable headlessly through `mibtest.helpers.buildSyntheticModel`. Keep it
that way - the controller is thin UI.

---

## Rules that fail silently

**Never allocate an index via `MibDataset.addMaterial`.** Its large-model branch calls
`MibLabels.countMaterials()`, a full-volume `max()` per time point, on every call. Take from
`index.freeIndices` first, else `index.maxIndex + 1`, and refuse past `labels.maxMaterials`.

**`PixelIdxList` is time-point-blind.** `MibImage.setPixelIdxList` writes into `obj.data`, which is
`[H W Z 1 T]`, while `convertPixelIdxListCrop2Full` produces indices into `[H W Z]`. Anything past
the first time point needs the frame offset added - `localCropToFull` does this.
`segmentationObjectPicker` has the same latent bug.

**Acting on a stale bounding box writes the wrong voxels, silently.** `MibDataset.maskStats` is the
existing precedent for a cache that is never invalidated - do not copy it. The controller listens to
`SetData` (on the **dataset**) and `Undo` (on `MibModel`) and sets `stale = true` unless the write
came from the editor itself. An operation started against a stale index rebuilds it first.

**A refresh never shrinks the index space.** When an edit removes the highest label value, a full
rebuild sizes its arrays to the new maximum while a refresh keeps the old one and marks the vacated
entry free. Those gaps are what the next split allocates from. Tests assert "equal over the shared
range, with the refreshed tail free", **not** element-for-element equality against a rebuild.

**A refresh unions its region with the object's previous bounding box**, so what survives outside the
refreshed box is recounted rather than forgotten. This is what makes 2D deletion correct.

**A widget backing a BatchOpt field must be named exactly as the field** -
`utils.updateBatchOptFromGUI_Shared` writes `BatchOpt.(hObject.Tag)`.

**Modifiers come from `obj.mibController.currentModifier`**, never `hFig.CurrentModifier`.

**A modal with no parent hangs the session.** `utils.dlgs.inputUniversalDlg` still builds a dialog
with no parent figure and nothing can dismiss it (this cost one test suite 250 s instead of 1 s, and
wedged MATLAB). `localComplain` / `localReport` check for a usable parent and fall back to
stderr/stdout. The message must go *somewhere* - a silent return reports success for work that never
happened - but it must not block.

**`getData3D`'s copy-on-write fast path is easy to lose.** On a Standard, XY-orientation,
single-timepoint dataset with `blockModeSwitch = 0` and `col_channel = NaN` it returns an alias of
`labels.data`, not a copy. Treat it as read-only; any write materialises the full duplicate. Reading
the Selection layer deliberately leaves the Z range off for this reason.

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

Built from one `regionprops(labelVol, labelVol, {'Area','BoundingBox','Centroid','MinIntensity'})`
call - the idiom `Quantification.quantification_Callback` uses, where `MinIntensity` recovers the
object id - plus one cancelable slice loop for `sliceCount`. About 3 MB at 65535 objects.

**Guard:** `regionprops` allocates for `max(label)`, so a 4294967295-type model with sparse high
indices would explode. If `max(labelVol(:))` far exceeds the number of distinct labels, remap through
`unique` first and keep the mapping, or require Compact.

**`PixelIdxList` is never cached** - derived per object on demand, which is what keeps this
interactive:

```matlab
bb  = index.bbox(objId, :);
sub = labelVolume(bb(1):bb(2), bb(3):bb(4), bb(5):bb(6));
idx = dataset.convertPixelIdxListCrop2Full(find(sub == objId), ...
        struct('y', bb(1:2), 'x', bb(3:4), 'z', bb(5:6)));
```

`objectIndex` also takes a bounding box, to re-index only the region an edit touched. That is how
every operation repairs the cache without a full rebuild.

---

## 2. Operations (`MibModel.editInstanceObjects`)

`BatchOpt.Action` = `Merge` | `SplitComponents` | `SplitBySelection` | `CutAtSlice` | `Connect` |
`Delete` | `AddToObject` | `AddObject` | `Cleanup` | `Compact`.

Other fields: `ObjectIndices` (string), `Mode3D`, `Connectivity`, `ConnectMode`, the three cleanup
thresholds (`cleanupMinObjectVoxels`, `cleanupMinObjectSlices`, `cleanupAbsorbFragmentVoxels` - the
prefix keeps them apart from `stitchModelInstances`'s identically named, unrelated options),
`showWaitbar`, `id` (from `obj.getActiveId()`).

**Every action:** `obj.backup('labels', 1, opts)` restricted to the union bounding box, write through
`setPixelIdxList` / `setData3D(..., options.PixelIdxList)`, update the index over that box,
`notify(obj,'ShowImage')` + `notify(obj,'SyncBatch')`.

| Action | Behaviour |
|---|---|
| **Merge** | `keep = min(objIds)`; other objects' voxels rewritten to `keep`. Union the bboxes, sum voxels, recount `sliceCount`, release the freed indices |
| **SplitComponents** | `bwconncomp(sub == objId, conn)` inside the bbox. Largest component keeps `objId`; each other gets the next free index. 3D uses 6/26-conn; 2D runs per slice with 4/8-conn, which also gives "explode into per-slice objects" for free |
| **SplitBySelection** | Clears the Selection voxels from `objId`, then SplitComponents - the brush workflow in one undo step |
| **CutAtSlice** | Voxels at `z >= currentSlice` take a new index. Cuts by Z position, so a tail that is two disconnected lobes keeps **one** index. 3D only |
| **Connect** | `interpolate` or `selection`; see below. 3D only |
| **AddToObject** | The drawing grows one existing object. Asked for by name it writes over whatever lies under it |
| **AddObject** | The drawing becomes a new object |
| **Delete** | Voxels to 0, indices released. Clips to the shown slice in 2D via `localObjectPixels` |
| **Cleanup** | `utils.instances.cleanup` over the whole volume, cancelable, then full rebuild. `compact = false` - someone working with object 1299 must still find it under that number |
| **Compact** | `MibLabels.squeezeMaterialLabels(wb)` in 3D; per-slice squeeze in 2D; then full rebuild |

### Connect

Both modes end in a Merge to `min(A,B)`.

- `interpolate` - binary sub-volume over the in-plane union bbox spanning the z-gap, A's facing
  cross-section on the first plane and B's on the last, `utils.interpolateShapes`, written **only
  where the label is currently 0**. Needs a real Z gap - it has to have two faces to morph between.
- `selection` - the Selection layer is the bridge, same background-only guard. Needs no gap.

If A and B already overlap in Z the bridge is skipped, they are merged, and the user is told. The
test is a bounding-box test, not a proximity test, so `localPlanConnect` returns `bridged`; when that
is false and the boxes cannot touch (`localBoxesCanTouch`, one-way, never cries wolf) the user is
told the objects were joined but nothing was bridged.

> Connect once degenerated into Merge whenever the two bboxes overlapped in Z and said nothing,
> leaving one index over two disconnected pieces - the outcome it exists to prevent. Keep the
> `bridged` reporting.

### The drawing chooses the objects

**`ObjectIndices` empty means "everything the drawing covers"**; naming objects restricts the action
to them, which is what a line clipping a neighbour needs. Empty is an error for every other action.
Two rejection paths, both leaving the layer alone so the drawing can be moved rather than remade:
nothing drawn, and a drawing lying only on background.

`localDrawingExtent` is the single definition of "read the Selection layer, find its extent" - three
copies had already drifted. `localObjectsUnderSelection` narrows to the slices carrying the drawing
before reading labels.

**++a++ commits the drawing, whatever it covers.** Same reading as MIB's ++a++ ("add the Selection
layer to the material"):

| Objects under the drawing | Action | Result |
|---|---|---|
| two or more | `Merge` | they become one, smallest index wins |
| exactly one | `AddToObject` | the object grows by the drawing |
| none | `AddObject` | the drawing becomes an object, next free index |
| nothing drawn | - | *"The Selection layer is empty"* |

The last two are **not** a merge that came up short; they are the same gesture over a smaller region.
`localObjectsUnderSelection` reports "drawn, but on background" as a *finding* - empty `objectIds`,
no problem - and the policy sits with the action: Merge falls through, SplitBySelection still refuses
because there is nothing to cut.

Both share `localDrawingToObject`, the only writer that does not start from a bounding box in the
index. **Two boxes, not one: the undo covers the drawing, the rescan covers the drawing united with
the object's existing extent**, because `buildInstanceIndex` recomputes statistics from the box it is
given. It takes `backgroundOnly` and applies the same guard `localAbsorbDrawing` has.

**`localAbsorbDrawing` writes the drawn background to an object, and every gesture that needs it
calls it.** The drawing is absorbed when it is what *chose* the objects, never when it merely happens
to be lying there - `consumesSelection` means exactly that, and for Merge it is true precisely when
`derivedFromDrawing` is. The consume step lives in the model, not the controller, so it holds for
batch protocols and so a leftover drawing cannot become the input to the next action.

`localMergeWrites` is Merge's whole body and Connect's last step. It takes `use3D` as a parameter -
Connect's old private copy hardcoded it `true`, which is how Connect came to ignore `Mode3D`.

### How far a drawing reaches (3D only)

`localObjectsToJoin` is the counterpart of `localObjectsUnderSelection`, and the difference between
them is the whole of it:

| | asked by | reads |
|---|---|---|
| a **cut** | `SplitBySelection` -> `localObjectsUnderSelection` | what the drawing covers - voxels it merely lies against are not being taken out of anything |
| a **join** | `Merge`, `Connect` -> `localObjectsToJoin` | what the drawing covers, and failing that what lies one slice beyond either end |

In 2D the lookahead is skipped and the two are identical.

Three rules, in the order they are applied:

1. **Two or more objects in-plane win outright**, before anything else is considered. A stroke laid
   across several is the gesture for joining them, and nothing outside the drawing can outvote what
   the user drew over.
2. **Otherwise the larger share of the drawing takes it** - in-plane candidate against the lookahead,
   strictly greater, no threshold. Scored by the fraction of the drawing a candidate covers, measured
   against the **drawn mask** on the outermost plane rather than its bounding box (a bounding box is
   far too generous for a diagonal stroke).
3. **The lookahead names one object in total** - the better covered of the two ends, lowest index on
   a tie. Each end contributes at most one candidate, by footprint under the stroke, and the reach is
   exactly one slice, never two.

> Rule 3 replaced "each end contributes its own object and both are joined". That read a stroke as a
> bridge whenever something happened to continue below it, and in a dense model something usually
> does - producing an unasked-for merge, which is what the whole tool exists to undo. Painting a
> piece in is one gesture; joining two objects is another, and once the piece is painted the two
> touch, so Connect or pick-and-Merge is one press. `interpolate` with two objects picked is the only
> form that joins two objects in one press.
>
> The guard inside `localDominantNeighbour` matters because of this: an end offers one object and
> only one end is taken, so a stroke reaches at most a single object the user cannot see.

**`Connect` with nothing picked is the same code** - it becomes `Merge` at dispatch and
`localPlanConnect` is never reached, which keeps `ConnectMode` out of it. The `BatchOpt` still says
`Connect`, so a protocol replaying it lands here again. The two buttons differ only when objects are
named.

**No report on success** for any of these - they are pressed hundreds of times in a session. The
result is on screen and ++ctrl+z++ is one step. Refusals speak through `localComplain`.

### `s` over a whole object removes it

++s++ is `Subtract from material`, so a drawing covering everything leaves nothing. There is no
"nothing would be left" guard - `localComponentMasks` returns `{}` for an empty mask and the removal
write already queued below it becomes the whole operation.

**With objects named and nothing drawn anywhere, `SplitBySelection` becomes `Delete`**, decided once
at dispatch:

```matlab
if strcmp(action, 'SplitBySelection') && ~derivedFromDrawing && ...
        isempty(localDrawingExtent(obj, id, dataset, timePoint, BatchOpt.Mode3D))
    action = 'Delete';
end
```

`highlightObjects` paints picked objects **into the Selection layer**, so a pick and a drawing
covering the whole object are the same picture. The test is "is anything drawn at all", not "over
this object" - per object it would delete a picked object merely because the drawing lies on a
different one. `consumesSelection` becomes false, correctly: no drawing was used.

A drawing *plus* a pick is untouched - still "cut this object, leave the neighbour the line also
crosses alone".

### Cleanup and Compact report what they did

`localReport` is the counterpart of `localComplain` for a result rather than a refusal. Two
differences: the no-parent fallback goes to **stdout** (work done is not an error, and tests read the
figures from there), and callers pass `allowDialog`, which `Compact` sets from `~batchModeSwitch` so
a protocol is not stopped by a box per iteration.

A message box, not `fprintf` - MIB runs in an AppContainer and the command window is behind it.
Cleanup's report sits beside Compact's, **after `delete(wb)`**: a modal raised while the progress
dialog is up goes behind it. Both **cancel** paths stay on `fprintf`.

Figures are derived from the index **taken before** the renumbering - the new number of an object is
its rank among the values in use, so `oldIds == 1:n` is the set that kept its number and
`oldMax - newMax` is the reclaimed space. No extra pass over the volume.

**Compact follows the mode.** `squeezeMaterialLabels` is one `unique()` over the whole label space -
right for a stitched model, useless on an unstitched one where the numbering restarts per slice, so
every value is in use somewhere and a global squeeze closes no gap. In 2D each slice is tightened on
its own. That loop is the only place here that walks the volume slice by slice, so it carries the
obligations: determinate cancelable progress bar, mutation of a **local copy**, one `setData3D` at
the end, no partial write on cancel.

- **The denominator is slices carrying objects, not stack depth.** An empty slice has nothing to
  number; counting it would report "renumbered 2 of 501" on a stack whose objects sit on forty
  slices. Depth is still given in brackets.
- **The object count is asserted, not assumed.** Renumbering must not add or remove objects; a
  disagreement goes to stderr. Nothing has produced it - it is there because this operation's damage
  would be hardest to recognise.
- **`squeezeMaterialLabels` renumbers each time point independently** (its `unique()` is inside the
  `for t` loop), so on a 4D model object 7 at t=1 and t=2 can map to different new numbers. Left
  alone: instance models are single-time-point in every path reaching here, and fixing it means
  deciding what object identity across time should mean.

---

## 3. Keeping it interactive

The rule: **an edit costs what the edited object costs**. No action's cost may scale with the dataset
except index build and cleanup/compact. Nothing here is new machinery - it is existing MIB mechanism
used consistently.

1. **The index removes full-volume scans.** Where an object is, how big, how many slices, what index
   is free next - all O(1) lookups.
2. **Bounding-box scoped reads.** `getData3D('labels', t, 3, NaN, options)` with `options.x/.y/.z`
   from `index.bbox`. Same trick as `segmentationObjectPicker`'s label-matrix path and
   `Quantification.highlightSelection`'s union box.
3. **Sparse writes by linear index** through
   `setData3D(values, 'labels', t, [], [], struct('PixelIdxList', idx))`, which routes to
   `MibDataset.setPixelIdxList` and touches exactly the object's voxels - no read-modify-write of a
   sub-volume.
4. **Bounding-box scoped undo - the one that decides whether the loop is usable at all.**
   `backup('labels', 1, struct('x',...,'y',...,'z',...))` costs kilobytes. With a whole-volume
   backup, `MibBackup`'s `max3d_steps` would be spent after a couple of clicks and each click would
   pause for a full copy. (`stitchModelInstances` uses `'modelLayers'` because it replaces the labels
   object and changes model type; the editor never does, so `'labels'` with a box is correct and far
   cheaper.)
5. **Incremental index repair** over the union bbox after each write. Full rebuild only after
   Cleanup, Compact, or an external change.
6. **Click resolution reads one pixel** - `getData2D('labels', z, [], [], options)` with
   `options.x = [x x]`, `options.y = [y y]`, as `MibController.findMaterialUnderCursor` does.
   (`mibModel.IrawModel`, the viewport raster kept by `showImage`, is at display resolution and would
   mis-pick when zoomed out.)
7. **The table never renders the model.** Sort and filter are vectorised over the index arrays; at
   most `MaxRows` rows reach the `uitable`.
8. **Cancelable progress only where it is real** - index build, Cleanup, Compact. Everything else is
   fast enough that the progress bar would be the slowest part.

**Known ceiling.** Instance models are memory-only, so "large" means a large in-RAM `uint16`/`uint32`
array. Because every access is already bbox-scoped, the same index and `PixelIdxList` structure would
port to a chunked on-disk store - that is Phase D of `instance_3d_plan.md`, not work for now.

### Undo repairs the index instead of rebuilding it

An edit backs up one bounding box and `MibModel.undo` restores exactly that box, so a full rebuild
after undo is pure waste - and it is the one cost that would scale with the dataset.

**The note rides with the undo entry.** `MibBackup.store` keeps the caller's options struct beside
the stored data, so a field put there by `localUndoRepairOptions` travels with the entry through the
ring buffer and into the redo slot (`MibModel.undo` passes the *same* options to `replaceItem`).
`repairIndexAfterUndo` reads it from `Backup.undoList(Backup.undoIndex).options`. This beats the
alternatives:

- **No parallel stack in the controller.** A shadow stack would have to stay aligned with an undo
  history the editor does not own, and misalignment fails by repairing the *wrong* box.
- **No change to `undo.m`, `backup.m` or `MibBackup`.** Putting the region in the `Undo` event
  payload would break `Lines3dDialog`, which does `strcmp(evnt.Parameters, 'lines3d')` on it.
- **One note serves both directions.** Re-measuring is direction-agnostic; storing index rows would
  have to know whether it was undoing or redoing, and MIB's undo is a swap that toggles.

The box carried is the **rescan** box, not always the backed-up one - growing an object writes only
the drawing but must be measured over the whole object.

**The ordering trap.** `MibModel.undo` writes the restored voxels **before** firing its `Undo` event:

```
event order during undo:   SetData(labels) -> Undo
```

So `dataChangedElsewhere` has already marked the index stale by the time the handler runs - marked it
for the very write the handler accounts for. A guard that refuses to repair a stale index therefore
refuses *every* repair. `markIndexStale` records the fresh-to-stale transition in
`indexFreshBeforeWrite`, and the handler repairs only when that transition is the one this undo
caused. Writes arriving while already stale leave the flag alone. The flag is cleared by the Undo
handler whatever it decides, so an unrepairable undo cannot leave older staleness for a later undo to
mistake as its own. `undoWritesTheVoxelsBeforeAnnouncingItself` pins the ordering.

Failure is always towards a full rebuild: no note, a note from another dataset or time point, or an
index stale for another reason. `Cleanup` and `Compact` deliberately leave no note - no box describes
them - and a brush stroke never had one.

---

## 4. The window (`controllers.InstanceEditor`)

> **The author builds `InstanceEditorGUI.mlapp`. Claude never edits it.** Callbacks are assigned
> externally in `@InstanceEditor/addCallbacks.m` against `obj.view.handles.<Tag>`, the pattern used
> by `DebrisRemoval.addCallbacks` and `MeasureTool.addCallbacks`. `core.ChildView` copies each
> component's property name into its `Tag`, so **the component names are the contract**.

**Labels belong to the `.mlapp`**; the controller sets only what has to agree with the code -
dropdown items, spinner limits, table behaviour - and never a widget's `Text`. Exceptions:
`objectTable.ColumnName` (follows the mode, set in `updateObjectTable`) and `indexStatusLabel.Text`
(runtime content). **Tooltips are set in code**, in `configureWidgets` via `applyTooltips`, so the
explanation sits next to the behaviour and cannot promise something the controller stopped doing; a
name that stops matching errors at construction.

| Name | Type | Purpose | Label |
|---|---|---|---|
| `objectTable` | uitable | index / voxels / slices / z-range, sortable | - |
| `detectionSettings` | button | row cap, list filters, connectivity | *(icon)* |
| `autoUpdateTable` | checkbox | 2D: re-read the list on slice change | `Update the list on slice change` |
| `updateTable` | button | re-read now | `Update list` |
| `jumpToIndex` | numeric + button | scroll to an object | `Go to object:` (`GotoobjectLabel`) |
| `pickByClick` | checkbox | take over the image mouse | `Pick objects by clicking` |
| `useShortcuts` | checkbox | take over ++a++ / ++s++ / ++c++ / ++ctrl+f++ | `Shortcuts` - mapping goes in the tooltip |
| `Mode3D` | checkbox | 3D or current-slice | `3D (whole object)` |
| `selectedList` | listbox | currently selected objects | `Selected objects:` (`SelectedobjectsLabel`) |
| `mergeButton`, `splitComponentsButton`, `splitBySelectionButton`, `cutAtSliceButton`, `connectButton`, `deleteButton` | buttons | the operations | the operation name |
| `ConnectMode` | dropdown | `interpolate` / `selection` | `Connect Mode` (`ConnectModeDropDownLabel`) |
| `cleanupButton`, `cleanupOptions` | buttons | clean; set the filters | *(`cleanupOptions` is a `settings_16px` icon)* |
| `compactButton` | button | renumber | - |
| `indexStatusLabel`, `rebuildButton` | label + button | cache state and rebuild | *(empty; runtime)* |
| `helpButton`, `closeButton` | buttons | standard | - |

Standard child-controller shape, copying `controllers.DebrisRemoval`: `core.ChildView(obj,
'views.InstanceEditorGUI')`, `utils.moveWindowOutside`, `utils.fontSizeUpdate`, `addCallbacks`,
`events CloseEvent`, static `ViewListner_Callback2`, listeners on `UpdateGuiWidgets` / `NewDataset` /
`SetData` / `Undo`. Callbacks carry DeveloperMode markers per
[developer_mode_callback_markers.md](../guides/developer_mode_callback_markers.md) -
`autoUpdateTable_Callback` exists only to hold one honestly, and `updateBatchOptFromGUI` prints only
when given a widget handle, for the same reason. A marker that fires on every slice step is worse
than none: the automatic refresh is the unmarked `refreshSliceList`.

### State and modes

**Settings live in `MibModel.sessionSettings.instanceEditor`, never in preferences** - a threshold
that suits one model is a poor opening offer for the next dataset. That covers the three cleanup
thresholds (`askCleanupSettings`, opened by `cleanupButton` where cancelling cancels the operation,
and by the `cleanupOptions` gear which only stores), the list settings (`askDetectionSettings`), and
`Mode3D` / `autoUpdateTable` / `pickByClick` / `useShortcuts`.

- **The row cap and the two list filters are `obj.listOptions`, not `BatchOpt` fields.** Only
  `updateObjectTable` reads them; they change what is *drawn*, never what is edited. `Connectivity`
  stays in `BatchOpt` - the split actions consume it.
- **Takeovers are restored through `setPickMode` / `setShortcutMode`, never by writing the
  checkbox.** The mouse and keys are owned by controller state and the checkbox follows. A restored
  `pickByClick` that finds no image document must come back **off**, and only the method knows that.
- **Window state is saved from the four callbacks, not from `closeWindow`** - what is kept is what
  the user *chose*. `reassertPickMode` dropping the takeover when another document becomes active is
  not a decision to stop picking.
- **`Connectivity` is stored as its literal value but restored as a stance**: a stored `26` comes
  back as `8` in 2D and `26` in 3D. `mode3D_Callback` does the same translation on every switch, and
  it runs once more at construction.

**First opening is 2D**, `Connectivity` 8/4 to match. Only the editor's default -
`editInstanceObjects` still defaults to 3D, which is right for a programmatic caller and is what
every headless test assumes.

`applyModeToWidgets` switches widgets whose other mode **cannot do this at all**, not those that do
it differently - `cutAtSliceButton`, `connectButton`, `ConnectMode` (+ label) are volume-only;
`autoUpdateTable`, `updateTable` are slice-only. Labels switch with their widgets. `Cleanup` and
`Compact` stay live in both: they read the whole volume regardless, which is what they are.
`updateStatusLine` must report the slice in 2D **without** an index - the 2D list needs none - and
append the model total only when the index is there, in amber when it is not.

### The 2D list

On an unstitched model the numbering restarts on every slice, so index 5 is a different object on
each, and the whole-volume index describes their **union** - the whole stack for every low index.
That is a wrong quantity, not a rendering problem, so in 2D the list is measured from the slice.

| | 3D mode | 2D mode |
|---|---|---|
| Source | `MibDataset.instanceIndex` | one `getData2D` of the shown slice |
| Columns | Index, Voxels, Slices, Z range | Index, Pixels (**on this slice**) |
| Slice filter | applies | not offered - not a property of a row |
| Needs the index | yes | no, so the list survives a stale index |
| Row click | `moveView` + jump to the object's slice | `moveView` only |
| Highlight | union bbox of the picked objects | the shown slice only |

Row click navigates by `dataset.moveView(centroid)` plus the slider update from
`Quantification.statTable_CellSelectionCallback`.

`InstanceEditor.currentSliceStats` is `find` + `unique` + three `accumarray` calls - deliberately
**not** `regionprops`, nor `accumarray` on the label values, both of which allocate up to the largest
label and would blow up on a 4294967295 model with sparse high indices. Cached on
`(slice, timePoint)` and dropped by `invalidateSliceStats` on every write. **That key cannot catch an
edit** - splitting an object changes neither the slice nor the time point.

Objects picked on one slice are dropped when the list moves, since the same number there is a
different object - enforced only where the controller knows the list moved (the automatic refresh and
the `updateTable` button).

### Picking by click

`pickByClick` sets `mibModel.disableSegmentation = true` and swaps
`imageDocument.UIFigure.WindowButtonDownFcn`, restoring both on untoggle and in `closeWindow` (the
save/restore pattern of `drawROIAndCreateMask` in `segmentationObjectPicker.m`;
`MeasureTool.closeWindow` shows the `disableSegmentation` reset). Plain click
replaces, ++shift++ adds, ++ctrl++ removes - which also falls out of the button mapping
(++shift++click is `SelectionType` `extend`, ++ctrl++click is `alt`).

**`updateGuiWidgets` silently steals the image mouse.** It reinstalls every image document's own
`WindowButtonDownFcn` unconditionally with no opt-out
(`@MibController/updateGuiWidgets.m:543-551`), and `editInstanceObjects` fires `UpdateGuiWidgets` on
finishing - so pick mode died on the first operation and clicking went back to painting while the
checkbox still claimed the editor owned the mouse. Invisible, because MIB's pointer over the image is
a crosshair either way; the DeveloperMode trace (no `imageButtonDown` after
`MibController.updateGuiWidgets triggered`) is what pins it.

`reassertPickMode` renews the takeover after `UpdateGuiWidgets`, after `SliceChanged`, and at the end
of `runOperation`; it drops the claim when the document it took the mouse from has gone, and hands
the mouse back when a different document becomes active. **The general fix belongs in
`updateGuiWidgets`** - skipping the reinstall when a child controller owns the mouse - and would
cover the next tool to hit this. Not attempted, because every transient taker in `@MibImageDocument`
relies on that reinstall.

**Pick mode must hand the mouse back.** `WindowButtonDownFcn` is one callback for every button, so
replacing it takes the right-button pan with it - and panning is how the user reaches the next
object. `imageButtonDown` classifies the click first and delegates anything that is not one of the
three picking gestures to `MibImageDocument.gui_WindowButtonDownFcn`. Two things make that work:

- The pan/select rule is restated in `localClickAction`, `System.LeftMouseButton` included.
  `gui_WindowButtonDownFcn` decides and acts in one pass with no way to ask it the question alone, so
  the two are kept in step by hand. Extracting the decision out of that 580-line handler is the
  better fix and is a change to shared mouse behaviour.
- The pan clears `WindowButtonDownFcn` while it runs and its `WindowButtonUpFcn` restores the
  *document's* handler, not the editor's - so the delegation chains onto that up-callback and
  reasserts afterwards. Without it a single pan ends pick mode.

`pickObjectUnderCursor` is shared by the click and ++ctrl+f++; `imageButtonDown` keeps only the part
working out what the click *is*.

### The highlight borrows the Selection layer

`highlightObjects` paints into the same layer `SplitBySelection` reads as its cut, so it must borrow,
not take:

- It **stashes what is in the box before painting** - `highlightState` carries
  `{id, timePoint, box, stash, painted}` - and clears nothing outside it.
- `releaseHighlight` puts back `stash | (current & ~painted)` over the same box, in the dataset and
  time point it was painted from. Storing the painted mask rather than recomputing it from the labels
  is what makes the restore exact after the labels have changed underneath.
- It runs **before every operation** (so the model never sees the highlight), on any outside write to
  the selection layer (`SetData` carries `type`), and on close.
- After an applied `SplitBySelection` or `Connect`/`selection`, the consumed drawing is cleared **in
  `editInstanceObjects`**, so it holds for batch protocols. That clear is deliberately **not** backed
  up - undo brings the object back but not the drawing, the price of ++ctrl+z++ staying one step.

> Before this, picking cleared the whole layer (`clearSelection('4D, Dataset')` - a full-layer backup
> plus copy on *every* pick) and then wrote the object into it, so the brush-then-pick workflow the
> tool exists for could not complete.

**The one case that cannot work** is drawing *inside* an already-highlighted object - those voxels
are indistinguishable from the highlight. Nothing is silently lost (the highlight disappears on the
first stroke, so what is on screen is what the operation uses), but the order is draw first, pick
second.

**An applied operation clears the selection and the highlight**, or the next pick would silently
include an object already finished with. Un-picking one object is a context menu on `selectedList`
(`ItemsData` carries the object index) - a context menu rather than a button so it needs no `.mlapp`
change.

`selectedList` also navigates on `ValueChangedFcn`, and is not a duplicate of the table's: a pick
made by clicking or with ++ctrl+f++ never passed through the table, and the table draws at most
`MaxRows` rows after filtering. Two limits: **it selects nothing** (clicking through to look must not
change the operation's input, and the `'remove'` menu entry must keep meaning what it says), and a
multi-selection is left alone since it names no single place to go. Safe against the repaint that
would undo it - `goToObject` in 3D fires `SliceChanged`, `sliceChanged` returns immediately in 3D, so
`updateSelectedList` (which clears `Value`) is not reached.

### Keyboard shortcuts

`useShortcuts` puts four keys on the editor while ticked:

| Key | Normally | While ticked |
|---|---|---|
| ++a++, ++shift+a++ | Add selection to material | **Merge** / **AddToObject** / **AddObject**, by what the drawing covers |
| ++s++, ++shift+s++ | Subtract from material | **Split by selection** - and a drawing over a whole object removes it |
| ++c++, ++shift+c++ | Clear selection | **Clear list and selection** |
| ++ctrl+f++ | Find material under cursor | **Add the object under the cursor to the selection** |

++c++ empties the **list first** (so the borrowed highlight is released before the layer is cleared,
or `releaseHighlight` would put its stash back into a just-emptied layer) then clears through
`mibController.cSelection.clearSelection()` - a superset of MIB's ++c++, scope rule included.

**Both ++a++ and ++shift+a++ must be swallowed**: MIB treats them as *one* shortcut with two scopes
(`overrideShift`), so leaving the shift variant through would let it write to the material. Here the
2D/3D scope is the `Mode3D` checkbox, not the modifier. ++ctrl++ and ++alt++ variants are declined
and reach MIB untouched, as does every key when the checkbox is off or the dataset is not an instance
model. ++ctrl+f++ **adds** rather than replaces - picking from the keyboard exists to collect the two
objects a Merge needs.

**The takeover is a hook, not a callback swap.** `MibController.keyPressOverride` holds
`{owner, fcn}`; `gui_WindowKeyPressFcn` offers the key to `fcn` before the shortcut table, returns if
it says it used it, and drops the claim when `owner` is no longer valid. Replacing the figure's
`WindowKeyPressFcn` would not survive - `@MibImageDocument` reinstalls that handle from five places
(every pan, brush stroke and drag-and-drop), the same trap that killed pick mode. The hook is empty
for everyone else. `closeWindow` gives the keys back, and the checkbox follows `shortcutModeActive`
rather than the other way round.

**Re-broadcasting keys to MIB, two traps:**

- **The payload must be a struct carrying the event under `.eventdata`**, wrapped in
  `core.ToggleEventData` - `MibController.listner_ModelEvent` unpacks
  `evnt.Parameters.eventdata`. Passing the `KeyData` object itself throws
  `MATLAB:nonExistentField` for every key, and an error inside a listener is quiet enough that the
  window merely looks like it has no shortcuts.
- **Use `WindowKeyPressFcn`, not `KeyPressFcn`** - the latter fires on a `uifigure` only while the
  figure *itself* has focus, so it goes dead after the first click on a button or a row.

`figureKeyPress` carries the edit-field guard `gui_WindowKeyPressFcn` cannot apply for a re-broadcast
(it is handed no `CurrentObject`). A modifier-only key is dropped, but `Character` is **not** tested
the way other controllers test it - that would throw away the arrow keys, and stepping through slices
is what 2D mode is for. `utils.childWindowKeyPressFcn` is not used: it whitelists Undo and Escape
only, and this window wants the whole set (++i++ to interpolate the brushed break is half the
workflow).

---

## 5. Verification

`buildtool check` clean; `buildtool test` green including the 71 new cases. The stitcher's own 25
cases pass unchanged after the cleanup extraction, which is what pins that extraction as
behaviour-preserving - keep them passing.

Invariants the suite pins:

- Merge assigns **the smallest** index and frees the others.
- Split gives the new part an index that was genuinely unused.
- Every operation leaves the index consistent with a full rebuild (modulo the shrink rule above) -
  the strongest single invariant.
- ++ctrl+z++ after each operation restores the exact prior volume.
- Connect writes only into background: a third object seeded inside the gap is untouched.
- `utils.instances.cleanup` is bit-identical to the pre-extraction stitcher.
- `connectFromADrawingUsesWhatItCoversFirst` (stroke across two objects in-plane, a third straddling
  in Z, asserting the third is untouched) and `mergeFromADrawingIn2DStaysOnTheSlice` (same stroke in
  2D, asserting it becomes a new object) - neither reading may drift into the other.
- `undoWritesTheVoxelsBeforeAnnouncingItself` pins the `SetData` -> `Undo` ordering.

New test files can be run through the MATLAB MCP `run_matlab_test_file` while iterating - **but
running the suite while MIB is open in that session gives false failures**: `models.MibModel` cannot
be cleared and the method never reloads. Use a separate `matlab -batch` process to check a model
method while the application is up.

**`InstanceEditor` has no view-less construction path** (`tests/CLAUDE.md` pattern 1), so none of the
controller is reachable headlessly. Adding one means a `createView` opt-out plus `hasWidget` guards
on every widget read - worth doing deliberately, not while fixing something else.

## Left for later

- Seeded watershed as a further split mode - deferred by the author when the scope was set.
- The parentless-modal hang is worked around in this one method. The general fix belongs in
  `utils.dlgs.inputUniversalDlg` - refusing to build a modal with no parent, and saying so - which
  would cover `stitchModelInstances` and every other caller at once.
- `editInstanceObjects` builds its progress dialog on `obj.getProgressBarParent()`, which is `[]`
  with no main window, so `Cleanup`/`Compact` error in a headless run unless `showWaitbar` is false.
  Same as `stitchModelInstances`; unreachable from the running application.
- `MibDataset.stitchModelInstances` once left `labels.materialsCount` at 0, so anything asking for
  the next free index fell back to a full-volume rescan. Fixed here; watch for it returning.
