# MCcalc Plugin — MIB2 → MIB3 Port Log

## Source files

| Role | Path |
|------|------|
| MIB2 controller (source) | `C:\Matlab\MIB2\Plugins\Organelle Analysis\MCcalc\MCcalcController.m` |
| MIB2 view callbacks (source) | `C:\Matlab\MIB2\Plugins\Organelle Analysis\MCcalc\MCcalcGUI.m` |
| MIB3 controller (output) | `mib\plugins\OrganelleAnalysis\MCcalc\MCcalc.m` |
| MIB3 view | `mib\plugins\OrganelleAnalysis\MCcalc\MCcalcGUI.mlapp` (created by user) |
| Auxiliary | `LineNormals2D.m`, `license_LineNormals2D.txt` (copied from MIB2) |

---

## Completed work

### Step 1 — Auxiliary files copied ✅
`LineNormals2D.m` and `license_LineNormals2D.txt` copied from MIB2 source to destination.

### Step 2 — `MCcalc.m` created ✅
Full MIB3 controller written from scratch based on `MCcalcController.m`.
No BatchOpt — simple plugin pattern (like `TripleAreaIntensity`).

### Step 3 — Ribbon name fix ✅
`addRibbonPlugins.m` changed from inserting space before every capital letter to
splitting only on lowercase→uppercase boundary, so `MCcalc` renders as **MCcalc**
instead of `M Ccalc`.

File: `mib\+views\@MibView\addRibbonPlugins.m` lines 58 and 74:
```matlab
% OLD (breaks acronyms):
regexprep(name, '([A-Z])', ' $1')
% NEW (proper CamelCase split):
regexprep(name, '([a-z])([A-Z])', '$1 $2')
```

---

## MIB2 → MIB3 conversions applied

| MIB2 | MIB3 |
|------|------|
| `classdef MCcalcController` | `classdef MCcalc` |
| `event closeEvent` | `event CloseEvent` |
| `obj.View` (uppercase) | `obj.view` (lowercase) |
| `mibChildView(obj, 'MCcalcGUI')` | `core.ChildView(obj, 'MCcalcGUI')` |
| `obj.mibModel.Id` | `obj.mibModel.getActiveId()` |
| `obj.mibModel.I{id}.modelMaterialNames` | `obj.mibModel.I{id}.labels.materialNames` |
| `obj.mibModel.I{id}.modelFilename` | `obj.mibModel.I{id}.labels.filename` |
| `obj.mibModel.I{id}.meta('Filename')` | `obj.mibModel.I{id}.image.filename` |
| `obj.mibModel.I{id}.pixSize.x` | `obj.mibModel.I{id}.image.pixSize.x` |
| `obj.mibModel.I{id}.pixSize.units` | `obj.mibModel.I{id}.image.pixSize.units` |
| `obj.mibModel.I{id}.time` | `obj.mibModel.I{id}.image.time` |
| `obj.mibModel.I{id}.depth` | `obj.mibModel.I{id}.image.depth` |
| `obj.mibModel.I{id}.image.height/width` | `obj.mibModel.I{id}.image.height/width` |
| `getData2D('model', z, 4, idx, opts)` | `getData2D('labels', z, 3, idx, opts)` |
| `setData2D('selection', sel, z, 4, ...)` | `setData2D(sel, 'selection', z, 3, ...)` ← arg order swapped |
| `hLabels.clearContents()` | `obj.mibModel.I{id}.annotations.clearContents()` |
| `hLabels.addLabels(text, [z, centroid, t])` | `obj.mibModel.I{id}.annotations.addLabels({text}, [z, centroid, t])` |
| `popup.Value` (integer index) | `find(strcmp(popup.Items, popup.Value))` |
| `widget.String` (edit box) | `widget.Value` |
| `widget.String` (label) | `widget.Text` |
| `popup.String = list` | `popup.Items = list` |
| `popup.Value = 1` (index) | `popup.Value = list{1}` (string) |
| `windv(...)` | `utils.align.windv(...)` |
| `waitbar(...)` | `uiprogressdlg(obj.view.gui, ...)` |
| `errordlg(msg, title)` | `utils.dlgs.showErrorDialog(obj.view.gui, msg, title)` |
| `questdlg(...)` | `utils.dlgs.inputQuestDlg(obj.view.gui, ...)` |
| `mibInputDlg(...)` | `utils.dlgs.inputUniversalDlg(obj.view.gui, ...)` |
| `notify(obj.mibModel, 'plotImage')` | `notify(obj.mibModel, 'ShowImage')` |
| `obj.mibModel.mibShowAnnotationsCheck = 1` | `obj.mibModel.showAnnotations = true` |
| `obj.mibModel.mibAnnMarkerEdit = 'label'` | removed (not needed in MIB3) |
| `mibUpdateFontSize(gui, Font)` | `utils.fontSizeUpdate(obj.view.gui, Font)` |
| `moveWindowOutside(h, 'left')` | `utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left')` |
| `global Font` | `obj.mibModel.preferences.System.Font` |
| `global mibPath` | `obj.mibModel.mibPath` |

### `raytraceObject` signature change
MIB2 read `extendRays` and `extendRaysFactor` from view handles internally.
MIB3: extracted in `continueBtn_Callback` and passed as parameters.
```matlab
% MIB3 signature:
function [results, B, rayDestinationPosX, rayDestinationPosY, Bx1, Bx2, By1, By2] = ...
        raytraceObject(obj, B, D2, range, pixSize, extendRays, extendRaysFactor)
```

### UI-only callbacks moved from `MCcalcGUI.m` into the controller
- `saveResultsCheck_Callback`
- `exportResultsFilename_Callback`
- `resultsImagesCheck_Callback`
- `resultImagesDirBtn_Callback`
- `detectContactsCheck_Callback`
- `extendRays_Callback`

`probeDistanceEdit_Callback`, `smoothEdit_Callback`, `extendRaysFactor_Callback`
(which only rounded values) — **dropped**: AppDesigner spinners enforce limits and
integer rounding natively.

---

## Bugs fixed during development

### Bug 1 — `updateWidgets`: Value before Items
**Error:** `'Value' must be the empty cell because the 'Items' property is empty.`

AppDesigner requires `.Items` to be set before `.Value`. Original code set
`material2Popup.Value` before `material1/2Popup.Items` in the empty-model branch.

**Fix:** Restructured so `.Items` is always assigned before `.Value` on both popups.

---

### Bug 2 — `calcPixelsCheck_Callback`: Value out of Limits
**Error:** `'Value' must be a double scalar within the range of 'Limits'.`

When switching modes the new numeric value could fall outside the spinner's current
`Limits` (e.g. physical-unit value of 0.05 is < the pixel minimum of 1).

**Fix:** Update `Limits` and `ValueDisplayFormat` *before* setting `Value`:
- Pixels mode: `Limits = [1, Inf]`, `ValueDisplayFormat = '%d'`
- Units mode:  `Limits = [0, Inf]`, `ValueDisplayFormat = '%.3f'`

---

### Bug 3 — `detectContactsCheck`: highlightCheck not disabled
`highlightCheck` was always enabled regardless of `detectContactsCheck` state.

**Fix:** Added `highlightCheck.Enable = 'on'/'off'` inside `detectContactsCheck_Callback`.

---

## Widget list and tooltips

### Labels
| Handle | Type | Note |
|--------|------|------|
| `infoText` | `uilabel` | Set programmatically in `addCallbacks` |
| `unitsText` | `uilabel` | Updated dynamically by `calcPixelsCheck_Callback` |

### Dropdowns
| Handle | Tooltip |
|--------|---------|
| `material1Popup` | Main organelle material. Rays are cast from its boundary outward toward the secondary material. |
| `material2Popup` | Secondary organelle material. The distance to the nearest pixel of this material is recorded for each ray. |

### Spinners
| Handle | Default Limits | Format | Tooltip |
|--------|---------------|--------|---------|
| `probeDistanceEdit` | `[0, Inf]` or `[1, Inf]` | `%.3f` / `%d` | Maximum probing distance from the main organelle boundary. Units depend on "Use pixels". |
| `smoothEdit` | — | integer | Half-window size (boundary points) for moving-average smoothing before normals are computed. 0 = disabled. |
| `showObjectEdit` | — | integer | Index of the object whose detail figure is shown on screen. |
| `histBinningEdit` | — | integer | Bin step for the distance histogram (multiplier of pixel size). |
| `outputResolutionEdit` | — | integer | DPI of saved PNG images (150 = screen, 300 = print). Active only when "Save result images" is checked. |
| `contactCutOffEdit` | `[0, Inf]` or `[1, Inf]` | `%.3f` / `%d` | Distance threshold for contact detection. Units follow "Use pixels". |
| `contactGapWidthEdit` | — | float | Maximum gap (pixels) between contact points still fused into one zone. Must be > √2 ≈ 1.414. |
| `extendRaysFactor` | — | float | Precision of ray endpoint interpolation. Smaller = denser fill, slower. |

### Checkboxes
| Handle | Tooltip |
|--------|---------|
| `calcPixelsCheck` | When checked, probe distance and contact cut-off are in pixels; otherwise physical units from dataset pixel size. |
| `highlightCheck` | Add contact pixels to the Selection layer for inspection in MIB after analysis. Enabled only when Detect contacts is on. |
| `detectContactsCheck` | Detect and measure organelle contact sites closer than the cut-off distance. |
| `extendRays` | Fill gaps in ray coverage by interpolating extra rays between widely spaced ray endpoints. |
| `exportMatlabCheck` | Export the full MCcalcExport structure to the MATLAB base workspace. Variable name set interactively. Disabled in deployed mode. |
| `saveResultsCheck` | Save analysis results to an Excel (.xlsx) or MAT file. |
| `resultsImagesCheck` | Save a PNG figure for every processed object to the selected directory. |

### Buttons
| Handle | Tooltip |
|--------|---------|
| `continueBtn` | Run the analysis on all objects of the main material across all slices and time points. |
| `closeBtn` | Close this dialog. |
| `helpBtn` | Open the MCcalc documentation page in a browser. |
| `exportResultsFilename` | Browse for the output file path (.xlsx or .mat). |
| `resultImagesDirBtn` | Browse for the directory where per-object PNG images will be saved. |

### Text edits (path display)
| Handle | Tooltip |
|--------|---------|
| `filenameEdit` | Full path of the output results file. Edit directly or use the folder button. |
| `resultImagesDirEdit` | Directory where per-object PNG images are saved. Edit directly or use the folder button. |

---

## Known potential issues to investigate

1. **`generateSelectionSw` without contact detection** — `highlightCheck` is disabled when
   `detectContactsCheck` is off, so `generateSelectionSw` will always be `false` in that
   case. Verify this matches intended MIB2 behavior (MIB2 allowed highlighting independently
   of contact detection).

2. **`annotations.addLabels` coordinate order** — MIB3 `Annotations.addLabels` expects
   `[z, x, y, t]`. `STATS.Centroid` from `regionprops` returns `[x, y]` (column, row),
   so `[z, STATS(objIndex).Centroid, t]` = `[z, x, y, t]`. Verify visually that annotation
   dots land on the correct object centroids.

3. **`DistributionMinDistNormAv` accumulation** — initialized only when `objId == 1`, then
   accumulated across all objects. If the number of histogram bins differs between objects
   (edge case: object near the border with very short probing range), this will error.
   Low probability but worth testing with edge objects.

4. **`contactGapWidthEdit` spinner lower limit** — code enforces `> sqrt(2)` at runtime by
   clamping and writing back to the widget. Consider setting the spinner's `Limits` to
   `[sqrt(2)+0.05, Inf]` in the mlapp to prevent entering invalid values in the first place.

5. **`xlswrite2` path** — requires `mib\external\xlswrite2.m` to be on the MATLAB path.
   This is added at MIB startup, so it should be available; confirm on first Excel-save test.

6. **`figure(1024)`** — the averaged results plot uses a fixed figure number. If the user
   happens to have an open figure 1024 it will be overwritten. Consider using
   `figure('Name', 'MCcalc averaged results')` with a name-based lookup to avoid collisions.

7. **`saveToExcel` — `contactLength` field missing when contacts disabled** — the loop
   `arrayfun(@(x) numel(x.contactLength), MCcalcExport)` on line 878 will error if
   `contactCutOff == 0` because `contactLength` is not stored in that case. The outer
   `if MCcalcExport(1).contactCutOff > 0` guard should protect it, but verify.

---

## Testing checklist

- [ ] Plugin appears in Plugins ribbon as **MCcalc** (no space between M and C)
- [ ] Dialog opens; material dropdowns populate correctly from the active model
- [ ] Switching "Use pixels" checkbox converts probe/cutoff values and updates units label
- [ ] `detectContactsCheck` off → `contactCutOffEdit`, `contactGapWidthEdit`, `highlightCheck` all disabled
- [ ] `extendRays` off → `extendRaysFactor` disabled
- [ ] `saveResultsCheck` off → filename edit and browse button disabled
- [ ] `resultsImagesCheck` off → dir edit, browse, resolution disabled
- [ ] Continue runs without errors on a dataset with a 2-material model
- [ ] Annotations appear at object centroids after analysis
- [ ] Detail figure appears for `showObjectEdit` index
- [ ] Excel export produces correct sheet structure
- [ ] Close button / window X button tears down cleanly with no MATLAB errors
