# mibStatisticsController → controllers.Quantification Conversion

**Date:** March 2026 (last updated: 26 March 2026)  
**MIB2 source:** `C:\Matlab\MIB2_RENAMED_FOR_MIB3\Classes\@mibStatisticsController\`  
**MIB3 destination:** `C:\Matlab\MIB3\mib\+controllers\@Quantification\`  
**Launch:** Model ribbon → "Quantify" button → `obj.mibController.startController('controllers.Quantification')`

---

## Status: Controller complete, view pending

| Component | Status | Notes |
|-----------|--------|-------|
| Controller (`@Quantification/`) | ✅ Done — 25 files | All methods ported, all documented |
| Documentation (all 24 method files) | ✅ Done | Full doc blocks per `.claude/doc_template.md` with `@b Examples:` |
| View (`views.QuantificationGUI.mlapp`) | ⏳ **To be created by user** | Widget tags listed below |
| `multipleBtn_Callback` property dialog | ⚠️ Placeholder | Calls MIB2 `mibMaskStatsProps` — needs MIB3 port |
| `materialColors`/`materialNames` in `highlightSelection` | ⚠️ Unverified | MIB3 API uncertain; see notes |
| Launch wiring | ✅ Done | `modelQuantification_Callback.m` |
| `CropObjects.m` update | ✅ Done | `sessionSettingsKey` property added |
| Keyboard shortcuts (Ctrl+Z undo, Escape) | ✅ Done | Via shared `utils.childWindowKeyPressFcn` |
| Backup type fix (`tableContextMenu_cb.m`) | ✅ Done | Was `'labels'` (wrong layer), now `'annotations'` |
| `getPixelIdxList`/`setPixelIdxList` (used by `highlightSelection`) | ✅ Done | Ported to `MibImage` + `MibDataset` wrappers |

---

## Files Created

All 25 files in `mib/+controllers/@Quantification/`:

| File | Description |
|------|-------------|
| `Quantification.m` | Main classdef — properties, events, static listeners, constructor |
| `runStatAnalysis_Callback.m` | Core 3D/2D statistics engine (largest file) |
| `addCallbacks.m` | Wires all widget callbacks from constructor |
| `closeWindow.m` | Close dialog and clean up listeners |
| `returnBatchOpt.m` | Publish BatchOpt for macro recorder |
| `updateBatchOptFromGUI.m` | Sync BatchOpt from widget changes |
| `updateWidgets.m` | Refresh all widgets from BatchOpt |
| `enableStatTable.m` | Enable/disable table & export buttons after run |
| `histScale_Callback.m` | Toggle log/linear histogram axis |
| `Material_Callback.m` | Material dropdown changed |
| `Units_Callback.m` | Units dropdown changed |
| `Multiple_Callback.m` | Multiple properties checkbox toggle |
| `radioButton_Callback.m` | Object/Intensity radio group changed |
| `Property_Callback.m` | Property dropdown changed |
| `sortBtn_Callback.m` | Sort table by column |
| `updateSortingSettings.m` | Sync sorting state to/from GUI |
| `multipleBtn_Callback.m` | Open property selection dialog (placeholder) |
| `createContextMenus.m` | Build right-click context menu on statTable |
| `gui_WindowButtonDownFcn.m` | Figure mouse click — trigger highlight |
| `statTable_CellSelectionCallback.m` | Row selection → call highlightSelection |
| `highlightSelection.m` | Highlight selected objects in selection layer |
| `tableContextMenu_cb.m` | All context menu actions (copy, crop, navigate) |
| `exportButton_Callback.m` | Export to Excel/CSV/MAT/workspace |
| `startController.m` | Launch child controllers (CropObjects) |
| `findChildId.m` | Find index of a child controller by class name |

---

## Modified Files

### `mib/+controllers/@CropObjects/CropObjects.m`
- Added `sessionSettingsKey` property (string)
- Constructor now reads `sessionSettingsKey` from parent if `isprop(parentController, 'sessionSettingsKey')` is true; defaults to `'annotationsCropPatches'`
- All literal `sessionSettings.annotationsCropPatches.*` field accesses replaced with `sessionSettings.(obj.sessionSettingsKey).*`

### `mib/+controllers/@MibRibbon/modelQuantification_Callback.m`
- Added: `obj.mibController.startController('controllers.Quantification');`

---

## Recent Changes (Post-Initial Port)

### Documentation (all 24 method files)
All method files now have full documentation blocks following `.claude/doc_template.md`:
- First comment repeats the function signature
- `[@em optional]` for optional params, `@li` for struct fields
- Every file has `@b Examples:` with realistic calls and `% Updates` footer

### Backup Type Fix (`tableContextMenu_cb.m` line 105, 108)
**Bug:** MIB2 `'labels'` meant point annotations (`hLabels`). In MIB3, `'labels'` = segmentation model layer. Annotations are `'annotations'`.  
**Fix:** Changed `backup('labels', 1)` → `backup('annotations', 1)` in both occurrences.

### `getPixelIdxList` / `setPixelIdxList` (new MIB3 infrastructure)
Ported from MIB2's `@mibImage` to a two-layer architecture:
- **Real logic:** `mib/+core/@MibImage/getPixelIdxList.m` and `setPixelIdxList.m` — handle MibLabels63 bit-packing
- **Wrappers:** `mib/+core/@MibDataset/getPixelIdxList.m` and `setPixelIdxList.m` — route by type (image/labels/mask/selection)
- Signatures added to `MibImage.m` and `MibDataset.m` classdefs
- Used by `highlightSelection.m` to read/write voxel selections efficiently

### Keyboard Shortcuts (`utils.childWindowKeyPressFcn`)
Created a shared keyboard handler for child dialog controllers:
- Handles **Ctrl+Z** (undo via `mibModel.undo()` + `notify(mibModel,'ShowImage')`) and **Escape** (close dialog)
- Wired in `addCallbacks.m`: `obj.view.gui.WindowKeyPressFcn = @(h,d) utils.childWindowKeyPressFcn(obj, h, d);`
- No `MibController` dependency needed — works through `mibModel` alone
- Documented in `.claude/conversion_ui.md` § "Child Dialog Keyboard Shortcuts"

---

## View: `views.QuantificationGUI.mlapp` — Widget Tags Required

The view has **not** been created. When creating it, use these exact AppDesigner component Tags:

| Tag | Type | Description |
|-----|------|-------------|
| `statTable` | UITable | Main results table (4 cols: ObjId, Value, Slice, TimePnt) |
| `Material` | DropDown | Material/Mask selector |
| `Shape2D` | RadioButton | 2D shape mode |
| `Shape3D` | RadioButton | 3D shape mode |
| `Object` | RadioButton | Object properties mode |
| `Intensity` | RadioButton | Intensity properties mode |
| `Mode` | ButtonGroup | RadioButton group for Object/Intensity |
| `Property` | DropDown | Single property selector |
| `DatasetType` | DropDown | 2D Slice / 3D Stack / 4D Dataset |
| `ColorChannel1` | DropDown | Primary color channel |
| `ColorChannel2` | DropDown | Secondary color channel (Correlation) |
| `Units` | DropDown | pixels / physical units |
| `Multiple` | CheckBox | Enable multiple properties |
| `multipleBtn` | Button | Open property selection dialog |
| `sortingPopup` | DropDown | Sort column selector |
| `runStatAnalysis` | Button | Run analysis |
| `exportButton` | Button | Export results |
| `helpButton` | Button | Help |
| `closeBtn` | Button | Close |
| `histScale` | CheckBox | Log scale for histogram |
| `updateBtn` | Button | Update/re-run |
| `autoHighlightCheck` | CheckBox | Auto-highlight on row click |
| `highlight1` | RadioButton | Add to selection |
| `highlight2` | RadioButton | Remove from selection |
| `histogram` | UIAxes | Histogram axes |
| `detailsPanel` | ButtonGroup | Add/Remove/Replace selection (contains `highlight1`, `highlight2`, and a "Replace" radio) |
| `Connectivity` | DropDown | 4/6 or 8/26 connectivity |

**Table column headers:** `{'ObjId', 'Value', 'Slice', 'TimePnt'}` (set in `enableStatTable.m`)

---

## Key MIB2 → MIB3 Translations Applied

| MIB2 | MIB3 |
|------|------|
| `obj.mibModel.id` | `id = obj.mibModel.getActiveId()` |
| XY orientation `4` | `3` |
| `obj.View.handles.*` | `obj.view.handles.*` |
| `mibChildView(obj,'mibStatisticsGUI')` | `core.ChildView(obj,'views.QuantificationGUI')` |
| `notify(obj,'plotImage')` | `notify(obj.mibModel,'ShowImage')` |
| `notify(obj,'updateId')` | `notify(obj.mibModel,'UpdateGuiWidgets')` |
| `ToggleEventData(x)` | `core.ToggleEventData(x)` |
| `waitbar(v,wb,msg)` | `uiprogressdlg` (GUI) + `waitbar` (batch) via `mibSetWb()` local helper |
| `warndlg(msg,title)` | `utils.dlgs.inputUniversalDlg(gui,{},{},'title',dlgOpt)` with `dlgOpt.Icon='puffin_warning'` |
| `errordlg(msg,title)` | `utils.dlgs.showErrorDialog(gui,msg,title)` |
| `questdlg(msg,title,…)` | `utils.dlgs.inputQuestDlg(gui,msg,title,…)` |
| `mibInputMultiDlg/mibInputDlg` | `utils.dlgs.inputUniversalDlg(gui,prompts,defAns,title)` |
| `getData3D(…, 4, …)` (hardcoded XY) | `getData3D(…, 3, …)` |
| `getData2D(…, NaN, …)` (col_channel) | `getData2D(…, [], …)` |
| `getCoordinatesOfShownImage(4)` | `getCoordinatesOfShownImage(3)` |
| `obj.mibModel.I{id}.colors` | `obj.mibModel.I{id}.image.colors` |
| `obj.mibModel.I{id}.pixSize` | `obj.mibModel.getImageProperty('pixSize')` |
| `global mibPath` | `obj.mibModel.mibPath` |
| `num2clip(d)` | `clipboard('copy',d)` |
| `containers.Map` | `dictionary` |
| `mibCropObjectsController` | `controllers.CropObjects` |
| Popup `.String` / `.Value` index | `.Items` / `.Value` string |

---

## Unfinished / Placeholder Items

### 1. Property Selection Dialog (`multipleBtn_Callback.m`)
**What it does:** Opens a dialog to let the user pick a subset of properties from the available list for batch calculation.  
**Current state:** Calls the MIB2 function `mibMaskStatsProps(propertyList, obj3d)` directly as a placeholder.  
**File:** `mib/+controllers/@Quantification/multipleBtn_Callback.m` — look for `% TODO: replace with a MIB3 port when available`  
**What to do:** Port `mibMaskStatsProps` from:  
- MIB2 source: `C:\Matlab\MIB2\GuiTools\mibMaskStatsProps.m` (GUIDE-based dialog)  
- Create as `views.MibMaskStatsPropsGUI.mlapp` + `controllers.MibMaskStatsProps` (or an `inputUniversalDlg` call if simple enough)  
- The function signature is `res = mibMaskStatsProps(propertyList, obj3d)` where:
  - `propertyList` is a cell array of currently-selected properties
  - `obj3d` is logical (true = 3D mode)
  - Returns cell array of selected properties, or empty if cancelled

### 2. `highlightSelection.m` — `materialColors` / `materialNames` API
**What it does:** In `'obj2model'` mode, sets model voxels to the selected material index using pixel colors.  
**Uncertain line:** `obj.mibModel.I{id}.labels.materialColors` and `obj.mibModel.I{id}.labels.materialNames`  
**MIB3 equivalents:** These are properties of `MibLabels` class. Verify the exact property path in `mib/+core/@MibLabels/MibLabels.m`. It may be `obj.mibModel.I{id}.labels.materialColors` (direct) or accessed via a method.

### 3. `'updateUserScore'` event
**Location:** `runStatAnalysis_Callback.m` (near the end) — `notify(obj.mibModel, 'updateUserScore', eventdata)`  
**Status:** Kept as-is, assumed to still exist in MIB3's `MibModel`. Verify in `mib/+models/@MibModel/MibModel.m` events block.

### 4. `dim_yxzct(orientation)` call
**Location:** `runStatAnalysis_Callback.m` line ~337 — `obj.mibModel.I{id}.dim_yxzct(orientation)`  
**Used for:** Getting the number of slices along the current viewing orientation in 2D stack mode.  
**Status:** Kept as-is; verify this property still exists on `MibDataset` in MIB3. If removed, replace with:
- orientation 3 (XY): `obj.mibModel.I{id}.image.depth`
- orientation 1 (ZX): `obj.mibModel.I{id}.image.width`
- orientation 2 (ZY): `obj.mibModel.I{id}.image.height`

---

## `CropObjects` Session Key Architecture

`CropObjects.m` now uses a `sessionSettingsKey` property (string) to store/restore jitter and naming settings in `mibModel.sessionSettings`. This allows multiple callers to have independent settings:

| Caller | Key |
|--------|-----|
| `controllers.Annotations` | `'annotationsCropPatches'` (default) |
| `controllers.Quantification` | `'quantificationCropPatches'` |

`Quantification.m` defines `sessionSettingsKey = 'quantificationCropPatches'` as a property. `CropObjects` reads it via `isprop(parentController, 'sessionSettingsKey')`.

---

## BatchOpt Fields Reference

```matlab
BatchOpt.MaterialIndex              % string, e.g. '1'; -1=Mask, 0=Exterior, -2=full Model
BatchOpt.DatasetType{1}            % '2D, Slice' | '3D, Stack' | '4D, Dataset'
BatchOpt.Shape{1}                  % 'Shape2D' | 'Shape3D'
BatchOpt.Mode{1}                   % 'Object' | 'Intensity'
BatchOpt.Property{1}               % selected property name, e.g. 'Area'
BatchOpt.Multiple                  % logical — compute multiple properties
BatchOpt.MultipleProperty          % semicolon-separated list, e.g. 'Area; Perimeter'
BatchOpt.Connectivity{1}           % '4/6 connectivity' | '8/26 connectivity'
BatchOpt.Units{1}                  % 'pixels' | physical unit string
BatchOpt.ColorChannel1{1}          % 'ColCh 1', etc.
BatchOpt.ColorChannel2{1}          % 'ColCh 2', etc.
BatchOpt.ExportResultsTo{1}        % 'Do not export' | 'Export to MATLAB' | 'Excel format (*.xls)' | ...
BatchOpt.ExportFilename            % string, output file path (no extension)
BatchOpt.CropObjectsTo{1}          % 'Do not crop' | 'Crop to MATLAB' | format strings
BatchOpt.CropObjectsMarginXY       % string, e.g. '0'
BatchOpt.CropObjectsMarginZ        % string
BatchOpt.CropObjectsIncludeModel{1}
BatchOpt.CropObjectsIncludeMask{1}
BatchOpt.CropObjectsJitter         % logical
BatchOpt.CropObjectsJitterVariation   % via sessionSettings.quantificationCropPatches
BatchOpt.CropObjectsJitterSeed        % via sessionSettings.quantificationCropPatches
BatchOpt.Generate3DPatches         % logical
BatchOpt.CropObjectsDepth          % string, depth for 3D patches
BatchOpt.CropObjectsOutputName     % base name for exported files
BatchOpt.showWaitbar               % logical
BatchOpt.id                        % dataset index (set at run time)
```

---

## How to Test Once View is Ready

1. Open MIB3, load an image, create a model with at least one material
2. Click **Model ribbon → Quantify**
3. Verify the dialog opens with the correct material pre-selected
4. Select a property (e.g. `Area`), click **Run** — table should populate
5. Click a table row — selection layer should highlight that object
6. Right-click table row — context menu should appear with crop/export options
7. Check **Multiple**, click **Define properties** — currently calls MIB2 `mibMaskStatsProps`
8. Export to Excel — check `xlswrite2` is on the MATLAB path (it's in `mib/external/`)

---

## Source Files for Reference

| MIB2 original | MIB2 renamed (partial rename) |
|---------------|------------------------------|
| `C:\Matlab\MIB2\Classes\@mibStatisticsController\` | `C:\Matlab\MIB2_RENAMED_FOR_MIB3\Classes\@mibStatisticsController\` |
| `C:\Matlab\MIB2\GuiTools\mibStatisticsGUI.m` | View layout reference |
| `C:\Matlab\MIB2\GuiTools\mibMaskStatsProps.m` | Placeholder dialog (still needed for MIB3) |
