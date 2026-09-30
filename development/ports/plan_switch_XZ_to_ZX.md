# ZX orientation: X horizontal, Z vertical

Status (2026-09-30): **implemented, not committed**. Unit tests pass; live checks on a real dataset
pass; interactive tools (brush, lasso, ROI drag, measure tools, Ctrl+F, Alt+1/2/3, Make Movie) still
need a manual check in ZX.

## Goal

Keep the Y axis vertical and the X axis horizontal in every view:

| View | Before | After |
|------|--------|-------|
| XY (`orientation = 3`) | X horizontal, Y vertical | unchanged |
| ZY (`orientation = 2`) | Z horizontal, Y vertical | unchanged |
| ZX (`orientation = 1`) | **Z horizontal, X vertical** | **X horizontal, Z vertical** |

Only the ZX view changes. MIB2 used the old layout, so this is also a deliberate departure from MIB2.

## Contract (the one rule every caller follows)

In orientation 1, `getData*` / `setData*` work on slices `[z, x, y, c, t]`: rows = Z, columns = X,
slice index = Y.

- Data permute: `permute(data, [3 2 1 4 5])` (was `[2 3 1 4 5]`). It is its own inverse, so
  `setData` uses the same vector with `ipermute`.
- Subarea options in orient 1: `options.x` = horizontal range = dataset X, `options.y` = vertical
  range = dataset Z, `options.z` = slice range = dataset Y (was `.x` = Z, `.y` = X).
- `getDatasetDimensions(..., 1)`: height = depth (Z), width = width (X), depth = height (Y).
- Block-mode `slices`: in ZX, `axesX` maps to `slices{2}` (X), `axesY` to `slices{3}` (Z)
  (`MibDataset.setAxesLimits`).
- Display stretch: Z is stretched **vertically** in ZX (through the image `YData`), horizontally
  in ZY (through `XData`), see `MibDataset.getDisplayStretch`.

Pinned by `tests/core/ZXOrientationFrameTest.m`.

## Approach chosen and the alternative rejected

Two approaches were implemented in this session; the first was reverted.

1. **Camera rotation (rejected by the author, reverted).** Keep the data frame `[x, z]`, rotate the
   axes camera in ZX (`view(ax, [-90 -90])`, `XDir`/`YDir` untouched). Measured in a uiaxes on a
   2000x1500 RGB image: CData update + drawnow 0.6 ms default view, 0.2 ms rotated (noise level);
   a CPU transpose would cost ~3.5 ms per frame. `images.roi.Polygon/Freehand/Line` construct on
   the rotated axes and text stays upright. Needed only ~10 file edits (camera in `showImage`,
   width/height swap in the three places that convert the axes pixel size to a field of view,
   status-bar order, Snapshot/MakeMovie transpose).
   Rejected because processing code (tools, plugins, exports that read `getData*` in orient 1)
   would still receive `[x, z]` - the screen and the data would disagree.
2. **Change the data frame (implemented).** `getData*`/`setData*` return `[z, x]` in ZX, so every
   consumer sees what the screen shows. Cost is the same permute work as before (a different
   permutation vector); the extra work is the vertical display stretch and the audit of every ZX
   branch.

The rotation patch was saved only in the session scratchpad (`zx_camera_rotation.patch`) and is
not kept in the repository.

## Display stretch refactor

Before: 15 files each computed a horizontal `coef_z` with a copy of
`switch orientation; case 3: x/y; case 1: z/x; otherwise: z/y`.

After: `core.MibDataset.getDisplayStretch(orient)` returns `[stretchX, stretchY]`:

| Orientation | stretchX | stretchY |
|-------------|----------|----------|
| 3 (YX) | `pixSize.x / pixSize.y` | 1 |
| 2 (ZY) | `pixSize.z / pixSize.y` | 1 |
| 1 (ZX) | 1 | `pixSize.z / pixSize.x` |

Every place that mapped axes units to data pixels now divides X terms by `coefX` and Y terms by
`coefY`; `XData = [1, w*coefX]`, `YData = [1, h*coefY]`. `magFactor` keeps its meaning: data pixels
per screen pixel along the unstretched axis.

Files: `showImage`, `listener_updateDatasetAxes` (fit / resize maths), `gui_SizeChangedFcn`,
`orientationChange`, `gui_WinMouseMotionFcn`, `gui_panAxesFcn`, `gui_WindowButtonDownFcn` (padded
pan paths and drawing-ROI repositioning), `updateBrushCursorOffset` (cursor ellipse now stretched on
Y from `YData`), `measureLength`, `updateMeasureText`, `convertMouseToDataCoordinates`,
`convertDataToMouseCoordinates`. The brush (`segmentationBrush`, `gui_WindowBrushMotionFcn`) maps
through `XData`/`YData` generically and needed only comment updates.

## Changed files by area

Core data layer (permute + options mapping):
- `+core/@MibImage/getData.m`, `setData.m`, `getDatasetDimensions.m`
- `+core/@MibLabels63/getData63.m`, `setData63.m`
- `+core/@MibBigDataLabels/MibBigDataLabels.m` (`orientPhysRanges`), `getData63.m`, `setData63.m`
- `+core/@MibBigDataLabelsIndex/getData.m` (`orientFullRanges`, `orientPermute`)
- `+core/@MibVirtualImage/getDataZarr.m`, `getDataVirt.m`
- `+core/@MibDataset/getDatasetDimensions.m` (block mode), docblocks of `getData2D/3D/4D`,
  `setData2D/3D/4D`, `MibVirtualImage/getData.m`

Dataset view helpers: `MibDataset/getCoordinatesOfShownImage.m`, `setAxesLimits.m`,
`getSliceLabels.m` (annotation column ids), `getRoiBoundingBox.m`, new `getDisplayStretch.m`
(signature added to `MibDataset.m`).

Model: `backup.m` (block-mode 3D ranges), `getRGBimage.m` (Lines3D box, annotation ids),
`interpolateImage.m` (shape bounding box to dataset xyz), the two mouse/data converters.

Overlays: `Lines3D/addLinesToImage.m`, `findClosestNode.m`; `Measurements.m` (`resample`, `crop`,
`computeAngle`, `computeDistance`); `RoiRegion.m` (`resample`, `crop`); `utils/addScaleBar.m`
(ZX horizontal unit is now `pixSize.x`).

Controllers (swap "horizontal = Z, vertical = X" to "horizontal = X, vertical = Z"):
- segmentation: `segmentationSpot`, `segmentationObjectPicker`, `segmentationLasso`,
  `segmentationLassoManual`, `segmentationAnnotation`, `segmentBlackWhiteThreshold`
- `MibRoi/roiToSelection`, `CropDataset` (rectangle -> Width/Depth, crop factor)
- `Lines3dDialog` (Jump, Pixels), `Annotations` controller (Jump)
- `MeasureTool`: `measureCircle`, `measureDistanceFree`, `measureDistancePoly`
- Alignment bounding-box shift: `DriftCorrection`, `AutomaticFeatureBased`, `...V2`,
  `LandmarkMultiPoint`, `SingleLandmark`, `ThreeLandmarks`
- `MibController/gui_WindowKeyPressFcn` (Alt+1/2 pivot from the status-bar x:y),
  `MibQuickAccessBar/orientationChange` (pivot for Alt+3, new-view size and stretch)
- `Snapshot`, `MakeMovie`: in ZX the output height is stretched (`height * pixSize.z/pixSize.x`),
  width is X

Checked and deliberately unchanged: `transposeDataset` (physical dataset transform, not the view),
zarr loader axis-order permutations, `segmentationClickTracker` (works in dataset axes, orient 3),
`clearLayer`, `deleteSlice`/`insertSlice`/`resliceDataset`/`transpose` (slice ranges only),
`convertPixelsToUnits`/`convertUnitsToPixels` (dataset xyz), `moveView` (uses dimensions),
`Annotations.m` line ~495 (dead code after `error`), Fiji/isosurface helpers (dataset axes).

## Saved files keep the legacy ZX frame

ROIs and measurements store `X`/`Y` in the frame of the view they were drawn in, and are saved to
`.roi` / `.measure` MAT files. To keep those files readable by MIB2 and older MIB3 (and old files
readable here), the files stay in the legacy frame and are converted at the boundary:

- `core.RoiRegion.swapZXAxes(Data)` - swaps `.X/.Y` and `.BoundingBox.x/.y` for entries with
  `orientation == 1`; applied in `MibRoi/roiLoad.m` and `roiSave.m`.
- `core.Measurements.swapZXAxes(Data)` - swaps `.X/.Y`, `.circ.xc/.yc`, `.spline.x/.y`; applied in
  `MeasureTool/loadMeasurements.m` and `saveMeasurements.m` (`.measure` only).

Both are their own inverse. The Excel export of measurements writes the in-memory frame, which now
matches its `[xcoords]`/`[ycoords]` headers for ZX. ROIs are not stored anywhere else
(checked `+io`, dataset save/load).

## Tests

- New: `tests/core/ZXOrientationFrameTest.m` (8 tests): image and all label containers (63 / 255 /
  65535) in `[z, x]`, subarea options, a ZX write lands at dataset (y, x, z) and touches no other
  slice, dimensions, stretch values, both file-frame swaps are self-inverse.
- Updated (they pinned the old frame): `MibBigDataLabelsIndexTest/anXZSliceReadsTheSameVoxelsTransposed`,
  `GetSetDataCorrectnessTest/get3DImageOrient1`.
- Unit tests in `tests/core`, `models`, `controllers`, `utils`, `io`: all pass (3 BigData VolRen
  tests skip without `CMU-1.ndpi`). Code Analyzer: 0 errors in the 67 changed files.

## Live verification (buffer with 887x813x171, pixSize x = 0.014, z = 0.03)

- Rendered ZX slice from `getData2D(..., 1)` is 171x813 (Z x X); screen grab vs `Ishown` mapped
  through `XData/YData`: correlation 0.93; aspect on screen 2.207 vs physical 2.222.
- Axes units equal screen pixels on both axes after fit / orientation switch.
- 25 random labelled voxels: data -> mouse -> data round trip and label readout, 0 mismatches.
- Snapshot in ZX: dialog 813 x 366, output 813 x 388 (incl. 22 px scale-bar strip), Z vertical,
  scale bar in `pixSize.x`.

## Related fix found during testing: Snapshot / Make Movie size after a voxel-size change

Pre-existing (affects ZY and XY with x != y too): Width/Height were computed when the dialog opened
and recomputed on `AxesLimitsChanged` only in "Shown area" mode, so after changing the voxel size
a "Full image" snapshot kept the old aspect ratio. The voxel-size dialog opened from the scale bar
checkbox also changed `pixSize` without refreshing anything.

Fix: both controllers store `dimsPixSize` (the pixSize the fields were computed from); on
`AxesLimitsChanged` they recompute when in "Shown area" mode **or** when the voxel size changed, so
a size typed by the user is not reset by every zoom. The scale-bar voxel-size dialog now notifies
`UpdateDatasetAxes('resize')` + `ShowImage`, as `MibRibbon.updateVoxelSizes` does. Not yet
confirmed live (needs the Snapshot dialog closed and reopened to load the new class definition).

## Open items / known limitations

- Manual check in ZX: brush, lasso, magic wand, ROI drawing and dragging, measure tools, Ctrl+F,
  Alt+1/2/3 pivots, Make Movie, snapshot with measurements overlay and ROI crop.
- BigData and virtual (zarr / BioFormats) ZX paths are covered by unit tests only.
- **API change for plugins / user scripts**: any call of `getData*`/`setData*` with orientation 1
  now gets or must pass `[z, x]`. No plugin in `mib/plugins` branches on orientation 1.
- Pre-existing issues seen during the audit, left unchanged:
  - `gui_WinMouseMotionFcn`, Virtual/BigData readout path ignores the display stretch.
  - `segmentBlackWhiteThreshold` "fix selection to material" reads the model in orient 3 with
    view-frame indices, which is inconsistent for ZX/ZY regardless of this change.
  - `measureCaliper` uses `pixSize.x` for ZX (and `pixSize.y` for ZY) as an approximation for an
    anisotropic in-plane distance.
  - `MibDataset.clearLayer` in block mode clears the full Z range in ZX/ZY (in-plane range only on
    the horizontal axis).
  - Snapshot/MakeMovie `origHeight` in ZX holds the stretched height, which the BigData ROI
    pyramid-level choice mixes with full-resolution widths.
- Unverified observation: the quick-access-bar docs table lists XZ as Alt+2, while
  `gui_WindowKeyPressFcn` comments name Alt+2 as ZY and Alt+3 as ZX.
