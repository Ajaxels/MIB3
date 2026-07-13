# CropDataset Controller Port — Conversion Log

**Source:** `MIB2_RENAMED_FOR_MIB3\Classes\@mibCropController\mibCropController.m`  
**GUI source:** `MIB2_RENAMED_FOR_MIB3\GuiTools\mibCropGUI.m`  
**Output controller:** `mib\+controllers\@CropDataset\CropDataset.m`  
**Output view:** `mib\+views\CropDatasetGUI.mlapp` (already existed, patched)  
**Status:** Complete. Controller ported, GUI opens, crop button functional in all three modes (Interactive, Manual, ROI).

---

## Runtime Errors Encountered and Fixed

### 1. `maxId` does not exist on MibModel
**Error:** `Unrecognized method, property, or field 'maxId' for class 'models.MibModel'`  
**Fix:** Replace every `obj.mibModel.maxId` with:
```matlab
maxId = obj.mibModel.Sets.datasetsInSet * numel(obj.mibModel.Sets.names);
```

### 2. `core.ChildView` — too many input arguments
**Error:** `Error using core.ChildView (line 42) Too many input arguments`  
**Root cause:** `CropDatasetGUI.mlapp` had `startupFcn(app)` with no second parameter,
but `core.ChildView` always calls `fh(obj.Controller)` — passing the controller as arg 2.  
**Fix:** Patched `matlab/document.xml` inside the mlapp ZIP:
```
function startupFcn(app)          →   function startupFcn(app, winController)
```
All other MIB3 mlapp views follow the same pattern:
```matlab
function startupFcn(app, winController)
    app.winController = winController;
    app.Figure.Visible = false;
end
```

---

## Pending Work

None — all items resolved. See implementation logs below.

### Completed items (chronological)
1. Port `CropDataset` controller from MIB2 (`mibCropController`)
2. Fix `maxId` → `Sets.datasetsInSet * numel(Sets.names)`
3. Fix `core.ChildView` "too many input arguments" (mlapp `startupFcn` signature)
4. Fix interactive crop zoom/pan via `cRoi.drawingROI` integration
5. Simplify Interactive section (single try-catch, one cleanup block)
6. Rewrite `cropToBtn_Callback` dialog to Set + Buffer spinner pattern
7. Fix Manual mode crop not executing (`editboxes_Callback` not syncing `BatchOpt`)
8. Fix crop-to: destination button not green + axes not fit-to-screen
9. Fix post-crop slice widget crash (`slices` stale after deep copy + crop; guard bug in listeners)

---

## Full Conversion Reference

### Class skeleton

| MIB2 | MIB3 |
|------|------|
| `classdef mibCropController < handle` | `classdef CropDataset < handle` |
| `obj.View` | `obj.view` |
| `event closeEvent` | `event CloseEvent` |
| `mibChildView(obj, 'mibCropGUI')` | `core.ChildView(obj, 'views.CropDatasetGUI')` |
| `global Font` | `obj.mibModel.preferences.System.Font` |
| `global mibPath` | `obj.mibModel.mibPath` |

### Constructor signature

MIB2: `mibCropController(mibModel, mibImageAxes, varargin)`  
MIB3: `CropDataset(mibModel, varargin)` — three recognised calling styles:

1. **Canonical (ribbon):** `varargin{1}` = `controllers.MibController` handle  
   Optional `varargin{2}` = BatchOpt struct / NaN  
   → stores `obj.mibController`; axes resolved dynamically at callback time
2. **Legacy (axes override):** `varargin{1}` = graphics axes handle  
   Optional `varargin{2}` = BatchOpt struct / NaN  
   → stores `obj.mibImageAxes`
3. **Batch only:** `varargin{1}` = BatchOpt struct or NaN (no controller or axes)

Batch mode exit pattern (after processing):
```matlab
obj.batchProcessingSwitch = true;
obj.cropBtn_Callback();
notify(obj, 'CloseEvent');
return;
```

### BatchOpt — radio buttons

MIB2 used three separate boolean fields:
```matlab
obj.BatchOpt.Interactive = false;
obj.BatchOpt.Manual = true;
obj.BatchOpt.ROI = false;
```

MIB3 uses a single button-group cell (Tag of button group → Tag of selected radio):
```matlab
obj.BatchOpt.cropMode    = {'Manual'};
obj.BatchOpt.cropMode{2} = {'Interactive', 'Manual', 'ROI'};
```
Check in callbacks: `strcmp(BatchOptLoc.cropMode{1}, 'Manual')` etc.  
Batch section name: `'Ribbon -> Dataset'` (was `'Menu -> Dataset'`)

### `maxId` replacement

```matlab
% MIB2:
obj.mibModel.maxId

% MIB3:
obj.mibModel.Sets.datasetsInSet * numel(obj.mibModel.Sets.names)
```
Introduce as a local `maxId` variable when used more than once in a function.

### Widget access — GUIDE → AppDesigner

| Widget | MIB2 property | MIB3 property |
|--------|--------------|---------------|
| Edit field (read/write text) | `.String` | `.Value` |
| Label / static text | `.String` | `.Text` |
| Tooltip | `.TooltipString` | `.Tooltip` |
| Dropdown — set item list | `.String = cellArray` | `.Items = cellArray` |
| Dropdown — set selected (by string) | `.Value = numericIndex` | `.Value = stringValue` |
| Dropdown — get selected index | `.Value` (numeric) | `find(strcmp(.Items, .Value), 1)` |
| Radio button — read | `.Value == 1` per button | `buttonGroup.SelectedObject.Tag` |
| Radio button — write | `radioBtn.Value = 1` | `buttonGroup.SelectedObject = radioBtn` |
| Button callback | `Callback` | `ButtonPushedFcn` |
| Edit callback | `Callback` | `ValueChangedFcn` |
| Button group callback | none | `SelectionChangedFcn` → `event.NewValue` = selected radio btn |

### `addCallbacks()` method (new in MIB3)

All widget callbacks wired in one place, called from constructor after `core.ChildView`:
```matlab
function addCallbacks(obj)
    obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
    h = obj.view.handles;
    % button group
    h.cropMode.SelectionChangedFcn = @(~, event) obj.radio_Callback(event.NewValue);
    % edit fields
    h.Width.ValueChangedFcn  = @(~,~) obj.editboxes_Callback();
    % dropdowns
    h.SelectROI.ValueChangedFcn = @(~,~) obj.SelectROI_Callback();
    h.ZarrPyramidLevel.ValueChangedFcn = @(src,~) obj.ZarrPyramidLevel_Callback(src);
    % buttons
    h.cropBtn.ButtonPushedFcn  = @(src,~) obj.cropBtn_Callback(src);
    h.closeBtn.ButtonPushedFcn = @(~,~) obj.closeWindow();
end
```

### `radio_Callback` — radio button handling

MIB2: hObject was the GUIDE radio button; `mode = hObject.Tag`.  
MIB3: hObject is the **selected radio button** (`event.NewValue`) passed from `SelectionChangedFcn`:
```matlab
function radio_Callback(obj, hObject)
    mode = hObject.Tag;   % 'Interactive' | 'Manual' | 'ROI'
    ...
    obj.BatchOpt.cropMode{1} = mode;
    ...
    % pass the BUTTON GROUP (not hObject) to updateBatchOptFromGUI:
    obj.updateBatchOptFromGUI(obj.view.handles.cropMode);
end
```
To set a radio from code (e.g., `resetBtn_Callback`):
```matlab
obj.view.handles.cropMode.SelectedObject = obj.view.handles.Manual;
obj.radio_Callback(obj.view.handles.Manual);
```

### `updateWidgets` — reading current radio selection

```matlab
% MIB2:
if obj.View.handles.Interactive.Value == 1; obj.currentMode = 'Interactive'; end

% MIB3:
obj.currentMode = obj.view.handles.cropMode.SelectedObject.Tag;
```

### Dropdown index → string and back

```matlab
% Set by index (e.g., SelectROI):
obj.view.handles.SelectROI.Items = list;
obj.view.handles.SelectROI.Value = list{idx};

% Read as index (SelectROI_Callback, selectZarrLevel):
val = find(strcmp(obj.view.handles.SelectROI.Items, obj.view.handles.SelectROI.Value), 1) - 1;
zarrIdx = find(strcmp(obj.view.handles.ZarrPyramidLevel.Items, obj.view.handles.ZarrPyramidLevel.Value), 1);
```

### Dimension properties

MIB3 dimensions are on `MibImage`, not directly on `MibDataset`:

| MIB2 | MIB3 |
|------|------|
| `obj.mibModel.I{id}.height` | `obj.mibModel.I{id}.image.height` |
| `obj.mibModel.I{id}.depth`  | `obj.mibModel.I{id}.image.depth`  |
| `obj.mibModel.I{id}.image.width` | same |
| `obj.mibModel.I{id}.image.time`  | same |

### `getDatasetDimensions` signature change

```matlab
% MIB2: (type, orient, col_channel, options) — 4 params; orient 4=XY; returns [h,w,colors,d,t]
[height, width, ~, depth, time] = obj.mibModel.I{id}.getDatasetDimensions('image', 4, NaN, opts);

% MIB3: (type, orient, options) — 3 params; orient 3=XY; returns [h,w,d,colors,t]
[height, width, depth, ~, time] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, opts);
```
- Orient XY: `4` → `3`; use `[]` instead of `NaN` for current orientation
- Return order changed: `[h, w, colors, d, t]` → `[h, w, d, colors, t]` (depth and colors swapped)

### Event name changes

| MIB2 | MIB3 |
|------|------|
| `'updateGuiWidgets'` | `'UpdateGuiWidgets'` |
| `'updateROI'` | (removed — `UpdateGuiWidgets` covers it) |
| `'plotImage'` | `'ShowImage'` |
| `'newDatasetLite'` | `'NewDataset'` (no event data) |
| `'newDataset'` + `ToggleEventData(bufferId)` | `'NewDataset'` + `core.ToggleEventData(struct('index', bufferId))` |
| `'closeEvent'` | `'CloseEvent'` |
| `ToggleEventData(x)` | `core.ToggleEventData(x)` |

### Utility function prefixes

All shared utilities require `utils.` prefix in MIB3:

```matlab
updateBatchOptCombineFields_Shared(...)  →  utils.updateBatchOptCombineFields_Shared(...)
updateBatchOptFromGUI_Shared(...)        →  utils.updateBatchOptFromGUI_Shared(...)
mibUpdateFontSize(gui, Font)             →  utils.fontSizeUpdate(gui, Font)
moveWindowOutside(h, 'left')             →  utils.moveWindowOutside(gui, mibGUI, 'left')
```

### Dialog replacements

| MIB2 | MIB3 |
|------|------|
| `errordlg(msg, title)` | `utils.dlgs.showErrorDialog(obj.view.gui, msg, title)` |
| `msgbox(msg, title, 'warn')` | `dlgOpt.MsgBoxOnly=true; dlgOpt.Icon='puffin_warning'; dlgOpt.HeaderLines=1;` + `utils.dlgs.inputUniversalDlg(obj.view.gui, '!!! Warning !!!', {''}, {msg}, title, dlgOpt)` |
| `mibInputMultiDlg({mibPath}, p, d, t)` | `utils.dlgs.inputUniversalDlg(obj.view.gui, '', p, d, t)` |

`inputUniversalDlg` dropdown `defAns`: `{'item1','item2','item3', 2}` — strings + numeric default index as last element.

### Deep copy and backup

```matlab
% MIB2:
obj.mibModel.mibImageDeepCopy(fromId, toId, BatchOptLoc)
obj.mibModel.mibDoBackup('mibImage')

% MIB3:
copyOpts.showWaitbar = BatchOptLoc.showWaitbar;
copyOpts.UIFigure    = obj.view.gui;   % or [] in batch mode
obj.mibModel.imageDeepCopy(fromId, toId, copyOpts)

obj.mibModel.backup('image', 1)        % 1 = full 3D backup
```

### Action log

```matlab
% MIB2:
obj.mibModel.I{bufferId}.updateImgInfo(log_text)

% MIB3:
obj.mibModel.I{bufferId}.image.updateActionLog(log_text)
```

### Dataset notify after crop

```matlab
% MIB2 — same buffer:
notify(obj.mibModel, 'newDatasetLite');
% MIB3:
notify(obj.mibModel, 'NewDataset');

% MIB2 — different buffer:
eventdata = ToggleEventData(bufferId);
notify(obj.mibModel, 'newDataset', eventdata);
% MIB3:
eventdata = core.ToggleEventData(struct('index', bufferId));
notify(obj.mibModel, 'NewDataset', eventdata);
```

### Constructor init sequence (GUI path)

```matlab
guiName = 'views.CropDatasetGUI';
obj.view = core.ChildView(obj, guiName);   % creates the mlapp
obj.addCallbacks();                         % wire all callbacks
Font = obj.mibModel.preferences.System.Font;
utils.fontSizeUpdate(obj.view.gui, Font);
obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');
obj.updateWidgets();
obj.view.gui.Icon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'mib_icon_16px.png');
obj.view.gui.Visible = 'on';
obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj,src,evnt));
obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src,evnt) obj.ViewListner_Callback2(obj,src,evnt));
```

### `ViewListner_Callback2` — guard pattern

```matlab
methods (Static)
    function ViewListner_Callback2(obj, src, evnt)
        if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            return;
        end
        switch evnt.EventName
            case {'UpdateGuiWidgets', 'NewDataset'}
                obj.updateWidgets();
        end
    end
end
```

### mlapp `startupFcn` — required pattern

Every MIB3 mlapp view **must** accept `winController` as second argument:
```matlab
function startupFcn(app, winController)
    app.winController = winController;
    app.Figure.Visible = false;
end
```
If a new mlapp is created without this (e.g., via App Designer), add `winController` manually.  
`core.ChildView` always calls the mlapp as `fh(obj.Controller)` — omitting the parameter causes  
"Too many input arguments" at `core.ChildView` line 42.

### Listener suppression during bulk notify

When firing `NewDataset` inside a method that is itself triggered by a listener,
disable listener 1 to avoid re-entrant `updateWidgets` calls:
```matlab
obj.listener{1}.Enabled = 0;
notify(obj.mibModel, 'NewDataset');
obj.listener{1}.Enabled = 1;
```

### `filename` property

```matlab
% MIB2:
obj.mibModel.I{i}.meta('Filename')

% MIB3:
obj.mibModel.I{i}.image.filename
```
Default empty-buffer sentinel: `'none.tif'` (same in both versions).

---

## MibImage.crop + MibDataset.cropDataset — Implementation Log

**Status:** Implemented 16.04.2025

### Files created
- `mib/+core/@MibImage/crop.m` — crops `data{1}` in-place; updates `height/width/depth/time/dim_yxzct/sliceName`; no bounding-box update (left to caller)
- `mib/+core/@MibDataset/cropDataset.m` — orchestrates all layers; handles Virtual → Standard; resets `slices{}`/`current_yxz`; calls `updateBoundingBox([], xyzShift)`
- Method declarations added to `MibImage.m` and `MibDataset.m`

### Key MIB2 → MIB3 differences
- `data{1}` layout: MIB2 `img{1}` = `[h,w,c,d,t]`; MIB3 `image.data{1}` = `[h,w,d,c,t]` → crop index order changed
- Label layers (`MibLabels`, `MibLabels63`) inherit `crop()` from `MibImage` — same `[h,w,d,1,t]` layout
- `MibLabels63` check: `isa(obj.labels, 'core.MibLabels63')` (was `obj.modelType == 63`)
- Depth slice index: `slices{3}` in MIB3 (was `slices{4}`)
- `obj.dim_yxzct(obj.orientation)` correctly maps: orient 3→depth, 1→height, 2→width
- BoundingBox: `updateBoundingBox([], xyzShift)` — pass `[]` not `NaN`
- Progress: `uiprogressdlg` requires `options.UIFigure`; silently skipped when absent
- Virtual detection: `obj.datasetType(1) == 'V'`

---

## Interactive crop mode — drawrectangle + dynamic axes resolution

**Status:** Implemented 16.04.2026

- Ribbon callback now passes `obj.mibController` to `startController`:
  ```matlab
  case 'Crop'
      obj.mibController.startController('controllers.CropDataset', obj.mibController);
  ```
- `CropDataset` stores `obj.mibController` as a new property (matches the
  `MibRoi` / `BatchProcessing` / `MibDeep` pattern). `obj.mibImageAxes` kept as
  optional fallback for callers that still pass an axes handle directly.
- Constructor `varargin` parsing rewritten to accept three calling styles:
  1. `startController('controllers.CropDataset', mibController)` — canonical
  2. `startController('controllers.CropDataset', axesHandle)` — legacy
  3. `startController('controllers.CropDataset', BatchOpt|NaN)` — batch
  Plus optional trailing `BatchOpt` for styles 1 and 2.
- Interactive mode resolves the active image axes at callback time:
  `obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.handles.imViewAxes`
  This is **split-panel safe** — if the user switches the active panel after
  opening the Crop dialog, the rectangle is drawn on the correct panel.
- `imrect` → `drawrectangle`. `.Position` format `[x y w h]` is unchanged, so
  the downstream coordinate math is untouched.
- Brush cursor overlay is hidden and cursor set to `'cross'` during draw; both
  are restored on all exit paths (Escape, exception, completion) via the
  `cImageDoc.brushCursor.Visible = false` / `cImageDoc.updateBrushCursor()` pair.
- Escape / invalid-ROI handling: `isvalid(roi)` check after `wait(roi)` — when
  the user presses Escape, the ROI object becomes invalid and we return without
  cropping (no error dialog).

---

## Interactive crop mode — zoom/pan stability via cRoi.drawingROI

**Status:** Implemented 16.04.2026

- Old approach: bare `drawrectangle` + `wait(roi)` — position lost during zoom/pan because
  `showImage` runs `repositionDrawingROI()` only on `cRoi.drawingROI.active == true`.
- Fix: piggyback on `cRoi.drawingROI` struct:
  - Set `cRoi.drawingROI.active = true` before `wait(roi)`, clear on all exit paths.
  - Add `MovingROI`/`ROIMoved` listeners → `captureCropDataPos` (static private method)
    that calls `mibModel.convertMouseToDataCoordinates` and writes data-pixel coords into
    `cRoi.drawingROI.dataPos` (2×2: `[xmin ymin; xmax ymax]`).
  - `showImage` (line 247) already calls `cRoi.repositionDrawingROI()` on every redraw.
  - Final crop position read from `cRoi.drawingROI.dataPos` (zoom-corrected) instead of
    converting `roi.Position` again.

---

## Simplification of Interactive section in cropBtn_Callback

**Status:** 16.04.2026

- Replaced 4 near-identical cleanup blocks with a single `try`-`catch` + `drawOk` flag and
  one cleanup section at the end.
- Merged two `obj.mibController` guard checks into one.
- Replaced `if-elseif` orientation chain with `switch`.
- Removed all commented-out dead code.
- Brush cursor save/restore pattern: save `brushCursorState`, hide cursor before draw,
  restore on ALL exit paths.

---

## cropToBtn_Callback — Set + Buffer spinner dialog

**Status:** 16.04.2026

- Replaced flat global-index dropdown with two-field dialog matching the "Link views" /
  "Duplicate dataset" pattern from `buffers_ContextMenu.m`.
- Prompts: set-name dropdown (`Sets.names`) + local buffer spinner (1..`datasetsInSet`).
- Default destination: first empty container, resolved via `ceil/mod` decomposition.
- Result global id: `destLocalId + (destSetIdx-1)*datasetsInSet`.

---

## editboxes_Callback — Manual mode crop was not executing

**Status:** 16.04.2026

- **Root cause:** `editboxes_Callback` only updated `obj.roiPos` but `cropBtn_Callback`
  reads exclusively from `BatchOptLoc` (snapshot of `obj.BatchOpt`).
- **Fix:** Added `obj.BatchOpt.Width/Height/Depth/Time` sync lines at the top of
  `editboxes_Callback` before updating `obj.roiPos`.

---

## Crop-to — destination buffer button not green + axes not fit-to-screen

**Status:** Fixed 16.04.2026

### Bug 1 — axes not fit-to-screen
`listener_newDataset.m` else branch (when `Parameters.index` is provided) was firing
`UpdateDatasetAxes` with no `mode` field → defaulted to `'resize'` (keeps stale zoom).
**Fix:** Add `Parameters.mode = 'fitToScreen'` in the else branch.

### Bug 2 — button not turning green
`update_fromModel.m` button-color loop was gated on `selectedSet ~= prevSelectedSet`.
When crop-to targets a buffer in the **same set**, colors were never refreshed.
**Fix:** Move the button-color `for` loop outside the set-change condition so it always
runs on every `DatasetsPanelUpdate` event.

### Bug 3 — DatasetsPanelUpdate not fired for crop-to
`listener_newDataset.m` else branch did not fire `DatasetsPanelUpdate`, so
`update_fromModel` never ran. **Fix:** Added `notify(obj.mibModel, 'DatasetsPanelUpdate')`
after `UpdateDatasetAxes` in the else branch.

---

## Post-crop slice widget crash when navigating destination buffer

**Status:** Fixed 16.04.2026

### Bug 1 — stale `slices{}` after deep copy + crop (root cause)
`imageDeepCopy` copies `slices{orientation}(1)` from source to destination. If the crop
reduces depth, the copied value (e.g. 80) exceeds the new max (e.g. 50). When
`updateGuiWidgets` sets `Limits = [1, 50]` then tries `Value = 80`, MATLAB throws
`'Value' must be within Limits`.

**Fix (`CropDataset.m`):** After `cropDataset`, clamp all slice positions:
```matlab
newDims = obj.mibModel.I{bufferId}.dim_yxzct;
maxZ = newDims(3); maxT = newDims(5);
for dimIdx = 1:3
    obj.mibModel.I{bufferId}.slices{dimIdx} = min(obj.mibModel.I{bufferId}.slices{dimIdx}, [maxZ maxZ]);
end
obj.mibModel.I{bufferId}.slices{5} = min(obj.mibModel.I{bufferId}.slices{5}, [maxT maxT]);
```

### Bug 2 — defensive clamp in updateGuiWidgets
`updateGuiWidgets.m` now clamps `currentSlice`/`currentTime` to `max_slice`/`image.time`
before assigning to widget `Value`, guarding against any future stale-slices scenario.

### Bug 3 — wrong guard in listener_sliceChanged / listener_frameChanged (pre-existing)
Guard was `obj.setOfDatasetsIndex ~= obj.mibModel.id` — compares SET index (1,2,…) to
GLOBAL buffer id (1…N). With `datasetsInSet = 10`, only buffer 1 of set 1 ever matched.
**Fix:** Changed to `obj.mibModel.Sets.selectedSet ~= obj.setOfDatasetsIndex` — the same
comparison used by `gui_ScrollWheelFcn` and `gui_WindowButtonDownFcn`.

