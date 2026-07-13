# ROI Class Conversion: MIB2 → MIB3

**Status: DONE** (core + controller ported, including `roiToSelection`)

---

## Architecture

MIB2 `mibRoiRegion` split into two MIB3 components:

| Component | Location | Responsibility |
|-----------|----------|----------------|
| `core.RoiRegion` | `+core/@RoiRegion/RoiRegion.m` | Pure data: storage, masking, resampling, overlay rendering |
| `controllers.MibRoi` | `+controllers/@MibRoi/` | Interactive drawing, panel callbacks, UI state |

`core.RoiRegion` holds a back-reference to parent `core.MibDataset` only (no controller references).

### ROI Type Names

| MIB2 | MATLAB fn | MIB3 type |
|------|-----------|-----------|
| `'imrect'` | `drawrectangle()` | `'rectangle'` |
| `'imellipse'` | `drawellipse()` | `'ellipse'` |
| `'impoly'` | `drawpolygon()` | `'polygon'` |
| `'imfreehand'` | `drawfreehand()` | `'freehand'` |

Legacy `.roi` files handled by `RoiRegion.convertLegacyTypes()` via `LegacyTypeMap` dictionary.

---

## Implemented: core.RoiRegion

14 methods: `clearContents`, `clearData`, `setDefaultOptions`, `updateOptions`, `findIndexByLabel`, `storeROI`, `removeROI`, `getNumberOfROI`, `getBoundingBox`, `returnMask`, `resample`, `crop`, `addROIsToPlot`, `convertLegacyTypes`

- `updateOptions`: dialog via `utils.dlgs.inputUniversalDlg`
- `addROIsToPlot`: accepts `convertFcn` closure; `selectedROI=0` → all, `>0` → specific Data index; style applied at `plot()`/`text()` construction (not post-hoc)

## Implemented: controllers.MibRoi

Files: `MibRoi.m`, `gui_Callbacks.m`, `addROI.m`, `removeROI.m`, `refreshROIList.m`, `repositionDrawingROI.m`, `roiSave.m`, `roiLoad.m`, `roiModify.m`

Key implementation notes:
- **Must inherit `< handle`** (value class causes state mutations in callbacks to be lost)
- `drawingROI` struct tracks in-progress interactive ROI: `.active`, `.roi`, `.type`, `.dataPos`, `.repositioning`
- `roiList` sets `dataset.selectedROI = hWidget.ValueIndex - 1` (list pos 1="All" → 0)
- `addROI`: sets `disableSegmentation=1` during draw; captures data-pixel coords via `captureDataPos` (inner function with `MovingROI`/`ROIMoved` listeners)
- Esc guard: checks `roi.Position`/`Vertices` size before conversion
- `drawellipse` aspect ratio: `'AspectRatio', 1, 'FixedAspectRatio', true`

---

## Zoom/Pan Compatibility During ROI Drawing

ROI stays anchored to image pixels during zoom/pan:

1. `addROI` sets `disableSegmentation=1` → segmentation blocked, pan still works
2. `captureDataPos` caches data-pixel coords on every `MovingROI`/`ROIMoved` event
3. `showImage.m` end: calls `cRoi.repositionDrawingROI()` after every image redraw
4. `gui_WindowButtonDownFcn.m`: at pan start (non-fast-pan only), inline repositioning:
   - `magFactor < 1`: `x_axes = imgXLim(1) + (x_data - imgXLim(1)) * coef_z`
   - `magFactor >= 1`: `x_axes = x_data * coef_z / magFactor`, `y_axes = y_data / magFactor`
5. ROI overlay lines (tag `'roi'`) deleted at pan start only in non-fast-pan mode

---

---

## Widget Handles (Roi.mlapp)

| Handle | Type | Purpose |
|--------|------|---------|
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
| `roiToSelection` | Button | Burn ROI to selection |
| `roiMode` (QuickAccessBar) | Toggle | Master ROI visibility |
