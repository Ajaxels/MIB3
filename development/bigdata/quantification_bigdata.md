# Quantification on BigData

Status: implemented 2026-11-18, uncommitted. The `BigData_PyramidLevel` dropdown (label
"Level") is in `views.QuantificationGUI`; the controller no longer guards for its absence. Its
Tag still has to be set to `BigData_PyramidLevel` in the .mlapp. GUI checks below are open.

Also fixed in the same change: Shape2D Correlation read the slice with `[]` channels (only the
displayed ones) and indexed the result by channel number; it now reads `ColorChannel1` and
`ColorChannel2` by number, as the Shape3D path does.

## Problem

`controllers.Quantification` reads the whole stack with `getData3D` (Shape3D) or every slice with
`getData2D` (Shape2D). On a BigData dataset:

- `getData3D` does not inject `magFactor` (bigdata_logic.md §3), so Shape3D reads the **full
  resolution** level whole - impossible for a slide-sized store.
- `getData2D` injects the display `magFactor`, so Shape2D measured whatever level the zoom
  happened to show, and its slice loop ran over full-resolution Z.
- `PixelIdxList`, `Centroid` and `BoundingBox` are then in the coordinates of that level, while
  navigation, annotations, crop and the selection writes assume full resolution.

## Decisions

1. **The user picks the level.** BatchOpt field `BigData_PyramidLevel = {'s0', {'s0', 's1', ...}}`,
   the same name and item format as `controllers.BigDataOptions`, so protocols look alike and a
   protocol recorded on one dataset matches the items of another. Default `s0`. On a non-BigData
   dataset the field is `{'s0', {'s0'}}` and ignored.
2. **Measurements are in the level's voxels.** `pixels` = pixels of the chosen level; physical
   units use the level voxel size (`pixSize .* levelScaleFactors`). Rescaling every shape property
   to full-resolution pixels is not exact (a perimeter or an Euler number does not scale), so it is
   not attempted. The export records the level.
3. **Coordinates shown to the user are full resolution.** After the run `Centroid` and
   `BoundingBox` are mapped to level 0 (`c_full = (c - 0.5) * s + 0.5`, a box edge the same way,
   widths `* s`), and the table's slice column is the first full-resolution slice of the level
   slice. So jump-to-object, annotations, Crop objects and the export work unchanged.
4. **`PixelIdxList` stays in level-linear indices.** It is needed to write the selection at that
   level. `obj.runPyramidLevel` (level, level size, scale) records the frame; `[]` for a Standard run.
5. **Highlight writes the selection at the measured level.** Union box of the objects in level
   coordinates -> full-resolution request range `floor((a-1)*s)+1 .. floor(b*s)` (inverse of
   getData's `ceil(y/s)`) -> `getData3D('selection', ..., pyramidLevel)` -> set/clear the voxels ->
   `setData3D`. `setData63` propagates to coarser levels and marks the level map; finer levels
   upsample on read, as after any edit at that zoom.
6. **Refused on BigData** (message, `StopProtocol`):
   - a level whose model level size differs from the image level (label overlay with its own
     pyramid; same check as `BigDataOptions.checkModelOutput`);
   - Shape2D when the view is not XY (slices are level XY planes);
   - Shape3D when the level volume does not fit the available memory (labels + image class of the
     channel being read; `PixelIdxList` comes on top, so this is a lower bound);
   - *Objects to a new model* (would create a new BigData model store from the table);
   - highlight on a read-only model or an instance index overlay.
7. **Block mode is ignored on BigData**: the whole level is measured (block mode axes are
   full-resolution screen limits and the per-object index conversion assumes full resolution).

## Changes

| File | Change |
|------|--------|
| `Quantification.m` | property `runPyramidLevel`; BatchOpt `BigData_PyramidLevel` + tooltip; reset on `NewDataset` |
| `updatePyramidLevelOptions.m` (new) | refresh the level items of the active dataset, keep a valid selection (constructor + `updateWidgets`) |
| `updateWidgets.m` | fill/enable the dropdown when it exists |
| `addCallbacks.m` | wire the dropdown when it exists |
| `quantification_Callback.m` | level resolve and checks, level reads, level voxel size, full-resolution centroids/boxes/slice column |
| `highlightSelection.m` | BigData branch (local function) writing at the level |
| `exportButton_Callback.m` | `OPTIONS.pyramidLevel`, level voxel size in the Excel header |
| `docs/.../mask-stats.md` | one paragraph on the level |

## Tests

`tests/controllers/QuantificationBigDataTest.m` (6, Integration, pass 2026-11-18 in `-batch` with
`mib/external/zarr-matlab` on the path): Shape2D Area at s1 against regionprops on the level
labels, full-resolution centroids, physical units with the level voxel size, Shape3D
MeanIntensity against the level image, `2D, Slice` picks the level slice, highlight Add / Remove
writes the selection at s1, Standard dataset gets `{'s0', {'s0'}}`. Not covered: the refusal
dialogs (they open a dialog headless), export, Crop objects.

## Widget to add (author)

Dropdown `BigData_PyramidLevel` (Tag = handle name, the BatchOpt rule), label "Level" (added
2026-11-18; Tag and tooltip not yet set). Suggested tooltip: `BigData: pyramid level to measure; s0 is full resolution, a
coarser level is faster and measured in its own pixels`. Items, value and Enable are set in code.

## GUI checks (open)

- [ ] Shape2D, 2D slice and 3D stack, at s0 and a coarser level: values, table slice column, jump to object
- [ ] Shape3D at a coarse level; memory refusal at s0 of a large store
- [ ] Highlight Add / Remove / Replace at a coarse level; zoom in: selection upsampled at the right place
- [ ] Annotations from the table land on the objects at full resolution
- [ ] Crop objects from a coarse-level run (full-resolution crops around the objects)
- [ ] Batch protocol with `BigData_PyramidLevel = s1`
- [ ] Standard dataset: nothing changed (dropdown disabled)
