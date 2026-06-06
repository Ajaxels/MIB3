# SurfaceArea3d Plugin — Port Log & Resumption Guide

**Source:** `C:\Matlab\MIB2\Plugins\Organelle Analysis\SurfaceArea3D\`  
**Target:** `C:\Matlab\MIB3\mib\plugins\OrganelleAnalysis\SurfaceArea3d\`  
**Reference pattern:** `SurfaceMeasurements.m` (same directory)  
**Video demo:** https://youtu.be/dIl1dt_cSqE

---

## Status

| Task | Done |
|------|------|
| Controller `SurfaceArea3d.m` created and converted | ✅ |
| View `SurfaceArea3dGUI.mlapp` created by user | ✅ |
| Dependencies copied | ✅ |
| Widget tags synced to final .mlapp names | ✅ |
| Docstrings updated to RST/Sphinx format | ✅ |
| Runtime testing | ❌ not yet done |

---

## Files in Plugin Directory

| File | Origin | Notes |
|------|--------|-------|
| `SurfaceArea3d.m` | Written from scratch (port) | Main controller |
| `SurfaceArea3dGUI.mlapp` | User-created in AppDesigner | View; startup function accepts `winController` |
| `mibTriangulateCurvePair.m` | Copied from MIB2 plugin dir | No changes |
| `triangulateCurvePair.m` | Copied from MIB2 plugin dir | No changes |
| `license_triangulateCurvePair.txt` | Copied from MIB2 plugin dir | No changes |
| `surf2amiraHyperSurface.m` | Copied from `MIB2\ImportExportTools\Amira\` | Not present in MIB3 — local copy |

---

## Widget Tag Map (mlapp → controller)

All `obj.view.handles.<Tag>` references in the controller use the final AppDesigner tags below.

| Widget tag | Type | Purpose |
|------------|------|---------|
| `materialDropdown` | DropDown | Select model material |
| `xySmoothingEditField` | NumericEditField | XY boundary smoothing half-width (px) |
| `xySamplingEditField` | NumericEditField | XY sampling step (every N-th point) |
| `zSamplingEditField` | NumericEditField | Z sampling step (every N-th slice) |
| `showPointsCheckBox` | CheckBox | Write boundary points to selection layer |
| `exportMatlabCheck` | CheckBox | Export result struct to MATLAB workspace |
| `saveResultsCheck` | CheckBox | Save results to CSV / MAT / XLSX |
| `addMaterialNameCheckBox` | CheckBox | Append material name to output filename |
| `generateModelObjectsCheckBox` | CheckBox | Save .surf files per object |
| `exportContactImarisCheckBox` | CheckBox | Send surfaces to open Imaris session |
| `filenameEdit` | EditField (text) | Output file path |
| `exportResultsFilename` | Button | Browse for output file |
| `exportResultsSurfEditField` | EditField (text) | Directory for .surf files |
| `exportResultsSurf` | Button | Browse for .surf output directory |
| `Label` | Label | Bold info text (also used for font size check) |
| `Label2` | Label | Italic warning text |
| `continueBtn` | Button | Start calculation |
| `closeBtn` | Button | Close window |
| `helpBtn` | Button | Open HTML docs |

### Widget rename history (MIB2 → initial plan → final mlapp)

Some names changed twice; recorded here to avoid confusion if re-reading MIB2 source.

| MIB2 GUIDE handle | Initial plan name | Final mlapp tag |
|-------------------|-------------------|-----------------|
| `material1Popup` | `material1Popup` | `materialDropdown` |
| `xySmoothEdit` | `XYsmoothingEditField` | `xySmoothingEditField` |
| `xySamplingEdit` | `XYsamplingEditField` | `xySamplingEditField` |
| `zSamplingEdit` | `ZsamplingEditField` | `zSamplingEditField` |
| `showPointsCheck` | `showpointsCheckBox` | `showPointsCheckBox` |
| `filenameMaterialCheck` | `addmaterialnameCheckBox` | `addMaterialNameCheckBox` |
| `exportModelsToImaris` | `exportcontacttoImarisCheckBox` | `exportContactImarisCheckBox` |
| `resultsImagesCheck` | `CheckBox` | `generateModelObjectsCheckBox` |
| `resultImagesDirEdit` | `EditField` | `exportResultsSurfEditField` |
| `resultImagesDirBtn` | `exportResultsFilename_2` | `exportResultsSurf` |

**Note:** `outputResolutionEdit` (MIB2) was intentionally omitted — not included in the user's mlapp.

---

## Key API Conversions Applied

### Data access
| MIB2 | MIB3 |
|------|------|
| `getData3D('model', NaN, NaN, idx, opts)` | `getData3D('labels', [], 3, idx, opts)` |
| `setData3D('selection', data, t, NaN, 1, opts)` | `setData3D(data, 'selection', t, 3, [], opts)` — **data first in MIB3** |
| `mibDoBackup('labels', 1)` | `obj.mibModel.backup('labels', 1)` |
| `I{id}.pixSize` | `I{id}.image.pixSize` |
| `I{id}.getBoundingBox()` | `I{id}.image.boundingBox` |
| `I{id}.depth` | `I{id}.image.depth` |
| `hLabels.addLabels(...)` | `obj.mibModel.I{id}.annotations.addLabels(...)` |
| `hLabels.clearContents()` | `obj.mibModel.I{id}.annotations.clearContents()` |
| `I{id}.modelFilename` | `I{id}.labels.filename` |
| `I{id}.modelMaterialNames` | `I{id}.labels.materialNames` |
| `I{id}.modelExist` | `I{id}.modelExist` (unchanged) |

### Material index recovery
MIB2 popup returned a numeric index directly.  
MIB3 DropDown returns the selected string — index must be recovered:
```matlab
material1_Name  = obj.view.handles.materialDropdown.Value;
materialsList   = obj.mibModel.I{id}.labels.materialNames;
material1_Index = find(strcmp(materialsList, material1_Name));
if isempty(material1_Index); material1_Index = 1; end
```

### Utility functions
| MIB2 | MIB3 |
|------|------|
| `mibRemoveBranches(img)` | `utils.removeBranches(img)` |
| `windv(v, w)` | `utils.align.windv(v, w)` |
| `mibSetImarisSurface(...)` | `io.imaris.mibSetImarisSurface(...)` |
| `surf2amiraHyperSurface(...)` | `surf2amiraHyperSurface(...)` — **local copy in plugin dir** |
| `trimeshSurfaceArea(v, f)` | unchanged (`external/matGeom` on path) |
| `distancePoints(...)` | unchanged |
| `minDistancePoints(...)` | unchanged |

### Events
| MIB2 | MIB3 |
|------|------|
| `notify(obj.mibModel, 'plotImage')` | `notify(obj.mibModel, 'ShowImage')` |
| `notify(obj.mibModel, 'updatedAnnotations')` | `notify(obj.mibModel, 'UpdateAnnotations')` |
| `notify(obj, 'closeEvent')` | `notify(obj, 'CloseEvent')` |

### Dialogs
| MIB2 | MIB3 |
|------|------|
| `errordlg(msg, title)` | `utils.dlgs.showErrorDialog(obj.view.gui, msg, title)` |
| `questdlg(msg, title, ...)` | `utils.dlgs.inputQuestDlg(obj.view.gui, msg, title, ...)` |
| `inputdlg(...)` | `utils.dlgs.inputUniversalDlg(obj.view.gui, ...)` |
| `waitbar(...)` | `uiprogressdlg(obj.view.gui, 'Title', ..., 'Message', ..., 'Value', 0)` |

---

## Controller Method Index

| Method | Lines (approx) | Notes |
|--------|----------------|-------|
| `ViewListner_Callback2` (Static) | ~28–48 | Guard + UpdateGuiWidgets/NewDataset |
| `SurfaceArea3d` (constructor) | ~55–125 | Virtual check, ChildView, icon, font, callbacks, tooltips, updateWidgets, listeners |
| `closeWindow` | ~128–153 | Child cleanup, delete gui, listeners, notify CloseEvent |
| `addCallbacks` | ~157–175 | Wires all ButtonPushedFcn / ValueChangedFcn |
| `initTooltips` | ~178–246 | Sets .Tooltip on all 17 interactive widgets |
| `updateWidgets` | ~249–272 | Populates materialDropdown; enables/disables continueBtn |
| `exportMatlabCheck_Callback` | ~275–289 | Prompt for workspace variable name |
| `saveResultsCheck_Callback` | ~292–309 | Toggle exportResultsFilename + filenameEdit |
| `exportResultsFilename_Callback` | ~312–330 | uiputfile for CSV/MAT/XLSX |
| `CheckBox_Callback` | ~333–345 | Toggle exportResultsSurf + exportResultsSurfEditField |
| `exportResultsSurf_Callback` | ~348–360 | uigetdir for .surf output directory |
| `helpBtn_Callback` | ~363–370 | web(..., '-browser') |
| `continueBtn_Callback` | ~373–838 | Main processing — ~460 lines |
| `saveToCSV` | ~841–860 | writetable → .csv |
| `saveToExcel` | ~863–893 | xlswrite2 → .xlsx with header block |

---

## Known Issues / Things to Verify at Runtime

### 1. Plugin auto-discovery
MIB3 scans `mib/plugins/<Category>/<PluginName>/` and expects a class named after the directory.  
Check that the plugin appears in the ribbon under **OrganelleAnalysis** after starting MIB3:
```matlab
cd C:\Matlab\MIB3\mib; mib3
```

### 2. Virtual stacking guard
The constructor returns early (with a warning dialog) when the dataset is in Virtual mode.  
`obj.view` is set to `[]` before `closeWindow` is called — `closeWindow` must tolerate `isempty(obj.view)`.  
Current code already checks `~isempty(obj.view) && isvalid(obj.view.gui)` — should be fine.

### 3. Material index on empty model
If `labels.materialNames` is empty after `modelExist == 1` (edge case), `material1_Index` could be `[]`.  
The guard `if isempty(material1_Index); material1_Index = 1; end` handles this but will silently use material 1.

### 4. `generateModelObjectsCheckBox` semantic
In MIB2 this checkbox was labelled "Save result images (.surf files)".  
The new mlapp label is "Generate Model Objects" — verify this matches the user's intended label in the UI; otherwise the tooltip may be misleading.

### 5. `saveImages` variable name inside `continueBtn_Callback`
```matlab
saveImages = obj.view.handles.generateModelObjectsCheckBox.Value;
```
The local variable is still called `saveImages` (from MIB2). It controls `.surf` file generation, not raster images.  
Functionally correct; rename if confusing.

### 6. `CheckBox_Callback` method name
The method is named `CheckBox_Callback` (legacy of the intermediate `CheckBox` widget name).  
The callback in `addCallbacks` correctly points to `generateModelObjectsCheckBox.ValueChangedFcn → obj.CheckBox_Callback()`.  
Consider renaming to `generateModelObjectsCheckBox_Callback` for clarity.

### 7. No icon file
There is no `icon_16px.png` in the plugin directory.  
The constructor falls back to `assets/icons/mib_icon_16px.png`. To add a custom icon, place a 16×16 PNG at:  
`C:\Matlab\MIB3\mib\plugins\OrganelleAnalysis\SurfaceArea3d\icon_16px.png`

### 8. `surf2amiraHyperSurface` is a local copy
The function is absent from MIB3's main tree and was copied from MIB2.  
If MIB3 later gains a canonical `io.amira.surf2amiraHyperSurface`, update the call in `continueBtn_Callback` and remove the local copy.

### 9. Excel output requires `xlswrite2`
`saveToExcel` calls `xlswrite2` which lives in `mib/external/xlswrite2.m`.  
This path must be on the MATLAB path when the plugin runs — it should be added by MIB3's startup, but confirm if the Excel export path is ever hit.

### 10. Progress dialog stays open on error
If `continueBtn_Callback` throws an unhandled exception after creating `progressDialog`, the dialog will stay open.  
Wrap the main body in `try/catch` and call `close(progressDialog)` in the `catch` block if robustness is needed.

---

## Test Checklist

- [ ] Start MIB3; plugin appears in the OrganelleAnalysis ribbon section
- [ ] Open a dataset that has a model with ≥1 material
- [ ] Open the plugin; material dropdown populates correctly
- [ ] Tick *Save results*, browse to a CSV path, click Calculate
- [ ] Verify CSV written; check SurfaceId / centroid columns
- [ ] Tick *Export to MATLAB*; verify `SurfaceArea` struct appears in workspace
- [ ] Tick *Generate Model Objects* (.surf), pick a directory, re-run; verify .surf files created
- [ ] Tick *Show points*; verify selection layer fills with boundary points after run
- [ ] Close the plugin; verify no MATLAB warnings about invalid listeners
- [ ] Load a new dataset while plugin is open; verify dropdown refreshes
