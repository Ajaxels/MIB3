# Port MIB2 `mibMeasure` + `mibMeasureToolController` → MIB3

## Status: IMPLEMENTED ✓

- `core.Measurements` — implemented 2026-05-02. All smoke tests pass, 0 static analysis issues.
- `controllers.MeasureTool` — implemented 2026-05-02. 22 files, 0 static analysis issues.

## Remaining Work

- `views.MeasureToolGUI.mlapp` — user creates in App Designer with widget tags listed in the [MeasureTool Controller section](#measuretool-controller-file-layout).
- `MibController` integration: add `cMeasureTool` property, instantiate from Measurements ribbon button, enable `addMeasurementsToPlot` scaffolding in `showImage` (~lines 235–240).

## Context

MIB3 currently has a placeholder `MibDataset.measure = []` (set in `mib\+core\@MibDataset\initialize.m:110`) and the backup/undo infrastructure (`mib\+models\@MibModel\backup.m:325`, `undo.m:141,166,217,261`) and `imageDeepCopy.m:111-116` already reference `obj.I{id}.measure.Data` — but no class exists yet to hold measurements. The MIB2 source class `C:\Matlab\MIB2\Classes\@mibMeasure\mibMeasure.m` (2412 LOC, 18 methods) is tightly coupled to `mibController`: nearly every method (`AngleFun`, `CaliperFun`, `CircleFun`, `DistanceFun`, `DistanceFreeFun`, `DistancePolyFun`, `PointFun`, `editMeasurements`, `drawROI`, `generateKymograph`) takes a controller handle to access axes, mouse clicks, coordinate conversion, image data, and `plotImage()`. `MibDataset` should not know about a controller.

**Goal:** Port to MIB3 as a **strict data-only** class `core.Measurements` mirroring the architecture of `core.RoiRegion` (`mib\+core\@RoiRegion\RoiRegion.m`). All interactive drawing UX (clicks, MATLAB `images.roi.*` objects, dialogs, refresh, `disableSegmentation`) moves to the future `controllers.MibMeasureToolController` (out of scope here). `core.Measurements` provides:

- `Data` storage with the same per-record schema MIB2 used (so undo/backup keeps working)
- Pure-math helpers (circle fit, angle, distance, intensity profile from a passed-in image)
- A passive `addMeasurementsToPlot(axes, convertFcn, …)` renderer (axes & coord-conversion injected, like `RoiRegion.addROIsToPlot`)
- Dataset-aware geometry transforms (`resample`, `crop`)

**Not in scope:** `controllers.MibMeasureToolController` (next task), MIB2 `.measure` legacy file loading, kymograph file save/dialog (controller will own; computation helper stays here).

## Design Summary

| Concern | Where it lives |
|---|---|
| `Data` struct array, `Options`, `typeToShow`, `fixZ` | `core.Measurements` (data) |
| Pure math (angle, circle fit, distance, profile interpolation) | `core.Measurements` (static or instance, takes inputs, returns numbers) |
| Render overlays on axes | `core.Measurements.addMeasurementsToPlot(axes, mode, orientation, convertFcn, selectedIdx, showLabel)` — mirrors `RoiRegion.addROIsToPlot` exactly |
| Geometric transforms after resample/crop | `core.Measurements.resample`, `.crop` (mirrors `RoiRegion`) |
| Mouse clicks, `images.roi.*` objects, info dialogs, `getClickPoint()`, `plotImage()`, `disableSegmentation` toggling | future `controllers.MibMeasureToolController` (NOT this task) |
| `getData2D()` and pass image into compute helpers | future controller |
| Save/load `.measure` files | future controller (matches how `roiSave.m` / `roiLoad.m` sit alongside `controllers.MibRoi`, not in `core.RoiRegion`) |

**Back-reference:** `obj.mibDataset` (handle to `core.MibDataset`) — same name as `RoiRegion.mibDataset`. Used to read orientation, dimensions, `pixSize`, `axesX/Y`, `blockModeSwitch`. NEVER a controller.

**Per-record `Data` schema** (preserved from MIB2 for backup/undo compatibility, MIB3 conversions applied):

| Field | Type | Notes |
|---|---|---|
| `n` | double | 1-based index, auto-renumbered on add/remove |
| `type` | char | `'Point'`, `'Distance (linear)'`, `'Distance (polyline)'`, `'Angle'`, `'Circle (R)'`, `'Caliper'` |
| `value` | double | numeric result |
| `X`, `Y` | double vec | data-space pixel coords |
| `Z`, `T` | double | slice / timepoint |
| `orientation` | double | **MIB3 values: 1=zx, 2=zy, 3=yx** (MIB2 used 4 for yx — translate on input) |
| `spline` | struct \| [] | polyline `ppval` data |
| `circ` | struct \| [] | `{xc, yc, R, Rp}` for circles |
| `intensity` | double vec | mean per channel |
| `profile` | double mat | `[position; intensity]` |
| `integrateWidth` | double \| [] | linear distance only |
| `info` | char | user annotation |
| `colCh` | double | color channel used |

## File Layout

**Single-file implementation** — `core.RoiRegion` turned out to be all-inline (1 file, not split), so `core.Measurements` follows the same pattern. All methods are inline in one file (~1135 lines).

```
mib\+core\@Measurements\
  Measurements.m    % complete class — all 12 instance methods + 5 static methods inline
```

**Instance methods:** `Measurements` (constructor), `clearContents`, `clearData`, `setDefaultOptions`, `updateOptions`, `storeMeasurement`, `removeMeasurement`, `getNumberOfMeasurements`, `findIndexByLabel`, `addMeasurementsToPlot`, `resample`, `crop`

**Static methods** (in `methods (Static)` block): `computeAngle`, `computeDistance`, `computeCircleFit`, `computeProfile`, `computeKymograph`

**Properties** (data-only, no controller, no axes):
```matlab
Data         % struct array of measurements
Options      % display options
typeToShow   % filter for plotting ('All' | type name)
fixZ         % logical; preserve Z/T on edit (controller may toggle)
mibDataset   % back-ref to core.MibDataset for orientation, dims, pixSize, axesX/Y, blockModeSwitch
```

`Options` field names use **lowercase** convention matching `core.RoiRegion` (not mixed-case as originally drafted):
`marker='o'`, `markersize='10'`, `linestyle='-'`, `linewidth='1'`, `color='y'`, `textcolorfg='y'`, `textcolorbg='none'`, `fontsize='14'`, `splinemethod='spline'`, `showMarkers=1`, `showLines=1`, `showText=1`

## Methods Excluded From This Class (Moved to Future Controller)

These MIB2 methods will live in `controllers.MibMeasureToolController` and are NOT ported into `core.Measurements`:

- `editMeasurements` — controller drives the re-edit flow, then calls `storeMeasurement` with the recomputed struct
- `drawROI` — controller creates `images.roi.Line / .Polyline / .Ellipse / .Point / .Freehand` (modern replacements for `imline/impoly/imellipse/impoint/imfreehand`)
- `updateROIposition1`, `updateROIposition2`, `updateROIScreenPosition` — interactive callbacks during drag
- `AngleFun`, `CaliperFun`, `CircleFun`, `DistanceFun`, `DistanceFreeFun`, `DistancePolyFun`, `PointFun` — interactive measurement creation (the controller orchestrates clicks → coords → calls `computeAngle/computeDistance/computeCircleFit/computeProfile` → builds the `Data` record → `storeMeasurement`)
- `generateKymograph` (file/dialog half) — controller calls `computeKymograph` and handles save dialog / format selection

Result: `core.Measurements` is ~1135 LOC vs MIB2's 2412 LOC (the extra lines are RST docblocks). The bulk of the UX logic that moved to the controller is interactive drawing, dialogs, `plotImage`, and `disableSegmentation` toggling.

## Integration Points to Update (Outside `+core/@Measurements/`)

| File | Change |
|---|---|
| `mib\+core\@MibDataset\initialize.m:110` | `obj.measure = [];` → `obj.measure = core.Measurements(obj);` |
| `mib\+models\@MibModel\imageDeepCopy.m:115` | Update guard `isprop(newDataset.measure, 'hImg')` → `isprop(newDataset.measure, 'mibDataset')`; assign `newDataset.measure.mibDataset = newDataset;` |

`backup.m` and `undo.m` already use `obj.I{id}.measure.Data` — no changes needed because the new class exposes `Data` with the same semantics.

`controllers.MibController.showImage` already has commented scaffolding (~lines 235-240) for `dataset.hMeasure.addMeasurementsToPlot(...)` — leave that commented for now; the future `MibMeasureToolController` and a new `mibShowAnnotationsCheck` MibModel state will wire it in. **Do not enable in this task** to avoid coupling to UI that doesn't exist yet.

## Critical Files To Read Before Implementation

- `mib\+core\@RoiRegion\RoiRegion.m` — entire file: the architectural template
- `C:\Matlab\MIB2\Classes\@mibMeasure\mibMeasure.m` — properties/events block, `setDefaultOptions`, `addMeasurements`, `removeMeasurements`, `addMeasurementsToPlot` (rendering switch on type), `circlefit` (math helper)
- `C:\Matlab\MIB2\Classes\@mibMeasure\AngleFun.m`, `CircleFun.m`, `DistanceFun.m`, `PointFun.m` — extract the math (angle from 3 points + aspect ratio per orientation; profile via `interp2`/`improfile`; circle from `circlefit`) into the static compute helpers; ignore the click/UX code
- `mib\+core\@MibDataset\MibDataset.m:1-110` — properties block style, docblocks
- `mib\+models\@MibModel\imageDeepCopy.m:109-118` — exact code to update

## Doc Style

All docblocks use the RST `sphinxcontrib-matlabdomain` style per `CLAUDE.md` and `development\docs_api_sphinx.md`: `% METHODNAME - One-line.`, `Syntax`/`Input Arguments`/`Output Arguments`/`Usage` sections, `.. code-block:: matlab`, `**bold**` parameter names with em-dash `—`. Mirror the existing docblocks in `RoiRegion.m`.

## Verification Results

All checks passed on 2026-05-02.

1. **Static check** — `mcp__matlab__check_matlab_code` on `Measurements.m`, `initialize.m`, `imageDeepCopy.m`: **0 issues** each.
2. **Smoke tests** — 10/10 passed (standalone instantiation, store/remove/find, computeDistance, computeAngle, computeCircleFit, computeProfile, resample/crop on empty data, typeToShow preservation).
3. **buildtool check** — fails on 4 pre-existing errors unrelated to this work (`to do.m`, `sliceNumberSlider_ContextMenu.m`, `mapRgbaVectorToScalar.m`, `readMetaDataFromFibicsTIFs.m`). No new failures introduced.

## Notes / Deviations from Original Plan

- **Single file** — plan listed 17 separate `.m` files; actual `core.RoiRegion` is single-file so `core.Measurements` follows the same pattern.
- **Options field names** — originally drafted as `markerSize`, `lineStyle`, etc. (mixed case); changed to `markersize`, `linestyle`, etc. (lowercase) to match `core.RoiRegion` and avoid silent runtime mismatches in future controllers.
- **`colCh` in `clearData`** — plan said "do not initialize colCh"; added during review because omitting it caused `isfield`-guarded code to error on a fresh Data struct.
- **`storeMeasurement` guard** — added `if index < 1; index = count + 1; end` to prevent `obj.Data(0)` indexing.
- **`findIndexByLabel`** — searches `.info` field (label text); `.n` is the numeric index so a direct search by n is just `obj.Data(n)`.
- **`addMeasurementsToPlot` Z/T filter** — filters by `mibDataset.slices{3}(1)` (z) and `slices{5}(1)` (time), plus `orientation` parameter, so measurements only render in the correct view plane and slice.

---

## MeasureTool Controller

### File Layout

```
mib\+controllers\@MeasureTool\
  MeasureTool.m              % classdef + constructor (inline) + method signatures
  addCallbacks.m             % wire widget callbacks + build context menu on measureTable
  gui_Callbacks.m            % dispatcher for all widget callbacks (by src.Tag)
  updateWidgets.m            % refresh channel list, pixel size, checkboxes, table
  updateTable.m              % rebuild 6-column table with type filter applied
  addMeasurement.m           % addBtn flow: backup → disableSegmentation → type dispatch → restore
  editMeasurement.m          % re-edit at index: navigate to slice, remove old, re-insert new
  contextMenu.m              % ModifyInfo / Jump / Modify / Recalculate / Duplicate / Kymograph / Plot / Delete
  measureAngle.m             % 3-point polyline → computeAngle → storeMeasurement
  measureCaliper.m           % line + point → perpendicular distance → storeMeasurement
  measureCircle.m            % ellipse boundary → computeCircleFit → 60-pt arc → storeMeasurement
  measureDistance.m          % 2-point line → computeDistance → storeMeasurement
  measureDistancePoly.m      % N-point polygon → spline interpolation → arc-length → storeMeasurement
  measureDistanceFree.m      % freehand → evenly-spaced downsample → poly logic → storeMeasurement
  measurePoint.m             % single point → pixel intensity → storeMeasurement
  drawROI.m                  % creates images.roi.* object, wait(roi), converts axes→data coords
  generateKymograph.m        % getData4D → computeKymograph → Preview/TIF/MAT/CSV
  loadMeasurements.m         % uigetfile → deserialise .measure → storeMeasurement loop
  saveMeasurements.m         % uiputfile → serialise hMeasure.Data
  plotIntensityProfile.m     % standalone figure 1952 for intensity profile
  previewIntensityProfile.m  % live preview in profileAxes + optional auto-jump
  updatePlotSettings.m       % sync markersCheck/linesCheck/textCheck → Options → ShowImage
```

### Key Architecture Notes

- **Axes handle**: `obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.handles.imViewAxes`
- **Coordinate conversion**: `obj.mibModel.convertMouseToDataCoordinates(X, Y, 'shown')` — 3 args, no magFactor
- **Cancel detection**: `~isvalid(roiObject)` after `wait(roiObject)` (Escape before placing → invalid immediately; Escape after placing → invalid after wait)
- **Replace-at-index pattern**: `removeMeasurement(idx)` then `storeMeasurement(newData, idx)` — because `storeMeasurement` inserts (shifts), not overwrites
- **`disableSegmentation`**: set to `1` in `addMeasurement`/`editMeasurement` before drawing, restored to `0` in `finally`-equivalent catch block
- **Backup**: `obj.mibModel.backup('measurements')` — no extra args; stores `{hMeasure.Data}` internally

### View Widget Tags (for `views.MeasureToolGUI.mlapp`)

| Tag | Type |
|---|---|
| `addBtn`, `closeBtn`, `deleteAllBtn`, `optionsBtn`, `loadBtn`, `saveBtn`, `refreshTableBtn`, `helpBtn`, `updateVoxelsButton` | Button |
| `measureTable` | UITable (6 cols: n, type, value, info, Z, T) |
| `filterPopup`, `measureTypePopup`, `imageColChPopup`, `modePopup` | DropDown |
| `integrateCheck`, `fixNumberPoints`, `finetuneCheck`, `calcIntensityCheck`, `showEditInfoDlg`, `previewIntensityCheck`, `markersCheck`, `linesCheck`, `textCheck`, `autoJumpCheck` | CheckBox |
| `integrationWidth`, `noPointsEdit` | EditField |
| `voxelSizeTxt` | Label |
| `profileAxes` | Axes |

### Verification Results

Static check 2026-05-02: **0 issues** on all 22 files.

### Integration Points (Pending)

| File | Change |
|---|---|
| `+controllers/@MibController/MibController.m` | Add `cMeasureTool` property |
| Measurements ribbon button callback | `obj.cMeasureTool = controllers.MeasureTool(obj)` |
| `+controllers/@MibController/showImage.m:235–240` | Enable commented `addMeasurementsToPlot` scaffolding |
