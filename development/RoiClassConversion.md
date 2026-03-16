# ROI Class Conversion: MIB2 → MIB3

**Last updated:** 2026-03-17
**Author:** Ilya Belevich

---

## Architecture

MIB2 `mibRoiRegion` split into two MIB3 components:

| Component | Location | Responsibility |
|---|---|---|
| `core.RoiRegion` | `+core/@RoiRegion/RoiRegion.m` | Pure data: storage, masking, resampling, overlay rendering |
| `controllers.MibRoi` | `+controllers/@MibRoi/` | Interactive drawing, panel callbacks, UI state |

`core.RoiRegion` holds a back-reference to parent `core.MibDataset` only (no controller references).

### ROI Type Names

| MIB2 | MATLAB fn | MIB3 type |
|---|---|---|
| `'imrect'` | `drawrectangle()` | `'rectangle'` |
| `'imellipse'` | `drawellipse()` | `'ellipse'` |
| `'impoly'` | `drawpolygon()` | `'polygon'` |
| `'imfreehand'` | `drawfreehand()` | `'freehand'` |

Legacy `.roi` files handled by `RoiRegion.convertLegacyTypes()` via `LegacyTypeMap` dictionary.

---

## Completed Work

### `core.RoiRegion` (`+core/@RoiRegion/RoiRegion.m`)
- Inherits `matlab.mixin.Copyable`
- 14 methods: `clearContents`, `clearData`, `setDefaultOptions`, `updateOptions`, `findIndexByLabel`, `storeROI`, `removeROI`, `getNumberOfROI`, `getBoundingBox`, `returnMask`, `resample`, `crop`, `addROIsToPlot`, `convertLegacyTypes`
- `updateOptions`: dialog via `utils.dlgs.inputUniversalDlg`
- `addROIsToPlot`: accepts `convertFcn` closure; `selectedROI=0` → all, `>0` → specific Data index; style applied at `plot()`/`text()` construction (not post-hoc); pre-computes `effectiveMarker`/`effectiveLineStyle` once before loop

### `controllers.MibRoi` (`+controllers/@MibRoi/`)
- **`MibRoi.m`**: must inherit `< handle` (value class caused state mutations in callbacks to be lost); `drawingROI` struct tracks in-progress interactive ROI: `.active`, `.roi`, `.type`, `.dataPos`, `.repositioning`
- **`gui_Callbacks.m`**: dispatcher for all panel widgets; `roiList` sets `dataset.selectedROI = hWidget.ValueIndex - 1` (list pos 1="All" → 0)
- **`addROI.m`**: manual + interactive modes; sets `disableSegmentation=1` during draw; captures data-pixel coords via `captureDataPos` (inner function with `MovingROI`/`ROIMoved` listeners); `Lasso` → dialog via `utils.dlgs.inputSingleDlg` (spinner, asks N× decrease factor) → stored as `'polygon'`; on add: calls `refreshROIList([])`, forces list to `'All'`, sets `selectedROI=0`; Esc guard: checks `roi.Position`/`Vertices` size before conversion
- **`removeROI.m`**: single or all with confirmation; hides `roiShowROI` when empty
- **`refreshROIList.m`**: rebuilds `roiList.Items`; pass `[]` to select `'All'`
- **`repositionDrawingROI.m`**: converts cached `dataPos` → current axes coords via `convertDataToMouseCoordinates`; re-entry guard via `.repositioning` flag
- **`roiSave.m`**: checks `getNumberOfROI(0) < 1`; default filename from `dataset.image.filename` (strip extension) or `currentDirectory`; `uiputfile`; saves `hROI.Data` as variable `Data` in `-v7.3` MAT; confirmation via `utils.dlgs.inputUniversalDlg` (MsgBoxOnly, puffin_info)
- **`roiLoad.m`**: start path from `dataset.image.filename` or `currentDirectory`; `utils.dlgs.mibUiGetFile`; loads `res.Data` → `hROI.Data`; calls `convertLegacyTypes()` for MIB2 compatibility; sets `roiShow=true`, `roiShowROI` checkbox, QuickAccessBar `roiMode`; calls `refreshROIList([])` + `showImage()`
- **`roiModify.m`**: if `selectedROI==0` shows `inputUniversalDlg` dropdown to pick ROI; converts stored `X`/`Y` data-pixels → axes via `convertDataToMouseCoordinates`; re-launches draw tool pre-populated (Rectangle: `[x y w h]`; Ellipse: center+semi-axes from vertex bbox; Polygon: vertex array); same `captureDataPos`/`MovingROI`/`ROIMoved` tracking and Esc guard as `addROI`; updates `hROI.Data(roiIdx)` in-place (label/orientation preserved)

### Zoom/Pan compatibility during ROI drawing
ROI stays anchored to image pixels during zoom/pan:

1. `addROI` sets `disableSegmentation=1` → segmentation blocked, pan still works
2. `captureDataPos` caches data-pixel coords on every `MovingROI`/`ROIMoved` event
3. `showImage.m` end: calls `cRoi.repositionDrawingROI()` after every image redraw
4. `gui_WindowButtonDownFcn.m`: at pan start (non-fast-pan only), inline repositioning converts `dataPos` to pan coordinate system directly (bypasses `convertDataToMouseCoordinates` which uses model state, not pan state):
   - `magFactor < 1`: `x_axes = imgXLim(1) + (x_data - imgXLim(1)) * coef_z`, `y_axes = y_data`
   - `magFactor >= 1`: `x_axes = x_data * coef_z / magFactor`, `y_axes = y_data / magFactor`
5. Condition uses `disableSegmentation == 1` (not `drawingROI.active`) because `active` was always 0 at pan time before the `< handle` fix was applied
6. ROI overlay lines (tag `'roi'`) deleted at pan start only in non-fast-pan mode; fast-pan keeps them (coordinate system unchanged)

### Key fixes
- `MibRoi < handle`: value class caused all callback-side mutations (`.active`, `.dataPos`, etc.) to be discarded — fixed by inheriting handle
- `drawellipse` aspect ratio: use `'AspectRatio', 1, 'FixedAspectRatio', true` (not `FixedAspectRatio` alone which only locks initial ratio)
- Manual ellipse fixed aspect: use `min(roiW, roiH)/2` for both radii
- Esc during draw: guard `numel(roi.Position) < 4` (Rectangle), `size < 2` (Polyline/Lasso), `isempty(roi.Vertices)` (Ellipse) → silent cancel

### Modified files
- `+core/@MibDataset/initialize.m`: `obj.hROI = core.RoiRegion(obj)`, `selectedROI = 0`
- `+core/@MibDataset/MibDataset.m`: `selectedROI` property declared
- `+models/@MibModel/MibModel.m`: `disableSegmentation = 0` property; `convertDataToMouseCoordinates` declaration
- `+models/@MibModel/convertDataToMouseCoordinates.m`: new file; inverse of `convertMouseToDataCoordinates` with `coef_z`
- `+controllers/@MibController/showImage.m`: ROI overlay via `addROIsToPlot`; calls `cRoi.repositionDrawingROI()` at end
- `+controllers/@MibController/updateGuiWidgets.m`: ROI list population from `hROI.Data`
- `+controllers/@MibImageDocument/gui_WindowButtonDownFcn.m`: pan-start ROI repositioning; ROI overlay deletion only in non-fast-pan mode
- `+views/+components/Roi.mlapp`: ROI panel UI
- `+utils/+dlgs/inputQuestDlg.m`: new (replaces `mibQuestDlg`); uifigure-based

---

## Remaining Work

| Task | Priority |
|---|---|
| `roiToSelection` — rasterise selected ROI into selection layer | Medium |

---

## Key Widget Handles

| Handle | Type | Purpose |
|---|---|---|
| `roiType` | DropDown | `Rectangle` / `Ellipse` / `Polyline` / `Lasso` |
| `roiList` | ListBox | Item 1 = `'All'`; `ValueIndex-1` → `selectedROI` |
| `roiManually` | CheckBox | Coordinate-spinner mode |
| `roiX1`, `roiY1`, `roiWidth`, `roiHeight` | Spinner | Manual ROI coords |
| `roiFixAspect` | CheckBox | Circle for ellipse; square for rectangle |
| `roiShowLabel` | CheckBox | Label text next to ROI |
| `roiShowROI` | CheckBox | Toggle ROI overlay |
| `roiAdd`, `roiRemove` | Button | Add / remove |
| `roiLoad`, `roiSave` | Button | File I/O |
| `roiModify` | Button | Modify selected ROI interactively |
| `roiOptions` | Button | Edit display options |
| `roiToSelection` | Button | Burn ROI to selection (not yet implemented) |
| `roiMode` (QuickAccessBar) | Toggle | Master ROI visibility |
