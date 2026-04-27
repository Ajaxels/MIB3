# MIB2 → MIB3 Plugin Conversion Cheat Sheet

Reference for porting GUIDE-based MIB2 plugin controllers to the MIB3
AppContainer / AppDesigner architecture.  Each section covers one area of
the API, showing the MIB2 pattern on the left and the MIB3 equivalent on
the right.

For the full architectural context see `instruction.md` in this folder.

---

## Class and naming

| MIB2 | MIB3 |
|------|------|
| `classdef mibMyController < handle` | `classdef MyPlugin < handle` — class name = folder name, no `Controller` suffix |
| `obj.View` (capital V) | `obj.view` (lowercase) |
| `obj.mibModel.id` | `obj.mibModel.getActiveId()` — never read `.id` directly; it is stale in split-panel mode |
| `notify(obj, 'closeEvent')` | `notify(obj, 'CloseEvent')` |
| `notify(obj.mibModel, 'plotImage')` | `notify(obj.mibModel, 'ShowImage')` |
| `notify(obj.mibModel, 'newDataset')` | `notify(obj.mibModel, 'NewDataset')` |
| `notify(obj.mibModel, 'updateId')` | `notify(obj.mibModel, 'UpdateGuiWidgets')` |
| `notify(obj.mibModel, 'showModel', evd)` | `obj.mibModel.showModel = true` then `notify(obj.mibModel, 'ShowImage')` |

---

## View initialisation

| MIB2 | MIB3 |
|------|------|
| `mibChildView(obj, 'MyControllerView')` | `core.ChildView(obj, 'MyPluginGUI')` — pass the mlapp class name |
| `obj.View.gui` | `obj.view.gui` — handle to the AppDesigner `uifigure` |
| `obj.View.handles.myWidget` | `obj.view.handles.myWidget` — populated by `core.ChildView` from mlapp properties |
| `mibMoveWindowOutside(obj.View.gui, ...)` | `utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left')` |
| `global Font; mibUpdateFontSize(obj.View.gui, Font)` | `Font = obj.mibModel.preferences.System.Font;` then `utils.fontSizeUpdate(obj.view.gui, Font)` |

---

## Constructor

| MIB2 | MIB3 |
|------|------|
| `function obj = MyController(mibModel)` | `function obj = MyPlugin(mibModel, varargin)` — accept varargin for batch-mode compatibility |
| `obj.View = mibChildView(obj, ...)` | `obj.view = core.ChildView(obj, 'MyPluginGUI')` |
| GUIDE figure's `CloseRequestFcn` wired in `.fig` | `obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow()` in constructor |

---

## Dataset dimensions

```matlab
% MIB2
[height, width, depth, colors, time] = obj.mibModel.I{id}.getDatasetDimensions('image');

% MIB3 — same return order, but orient 4 (XY) is now orient 3
options.blockModeSwitch = 0;
[height, width, depth, colors, time] = ...
    obj.mibModel.I{id}.getDatasetDimensions('image', 3, options);
% Return order: height, width, depth, colors, time
```

| MIB2 | MIB3 |
|------|------|
| `orient = 4` (XY native) | `orient = 3` |
| `orient = NaN` (current) | `orient = []` |

---

## getData / setData

### Argument order changes

| Operation | MIB2 | MIB3 |
|-----------|------|------|
| `setData4D` | `(type, dataset, orient, ch, opts)` | `(dataset, type, orient, ch, opts)` — **dataset moved first** |
| `setData3D` | `(type, dataset, slice, orient, ch, opts)` | `(dataset, type, slice, orient, ch, opts)` — **dataset moved first** |
| `setData2D` | `(type, dataset, slice, orient, ch, opts)` | `(dataset, type, slice, orient, ch, opts)` — **dataset moved first** |
| `getData*` | `type` always first | unchanged |

### col_channel convention

| MIB2 | MIB3 |
|------|------|
| `col_channel = 0` (all channels) | `col_channel = []` (all channels) — `0` is invalid (index must be ≥ 1) |

### Type name

| MIB2 | MIB3 |
|------|------|
| `type = 'model'` | `type = 'labels'` |

---

## Undo / backup

| MIB2 | MIB3 |
|------|------|
| `obj.mibModel.mibDoBackup(type, switch3d, opts)` | `obj.mibModel.backup(type, switch3d, opts)` |
| `opts.roiId = []` → currently selected ROI | `opts.roiId = -1` (or omit `roiId`) → full dataset, no ROI mode |

**Note:** `roiId = []` in `backup` options resolves to `selectedROI`.  If the
user has no ROI defined this causes an out-of-range error in `MibBackup.store`.
Always pass `roiId = -1` or omit the field entirely when you want to back up
the full image.

---

## MibImage methods — called via `I{id}.image`, not `I{id}`

`obj.mibModel.I{id}` is a `MibDataset`.  Methods that operate on the pixel
data live on the inner `MibImage` object at `I{id}.image`:

| MIB2 | MIB3 |
|------|------|
| `obj.mibModel.I{id}.updateActionLog(msg)` | `obj.mibModel.I{id}.image.updateActionLog(msg)` |
| `obj.mibModel.I{id}.updateDisplayParameters()` | See below |

### Updating the display range after a type conversion

`updateDisplayParameters` does not exist in MIB3.  After replacing image data
with a different numeric type, update the three interdependent properties on
`MibImage` manually:

```matlab
imageObj           = obj.mibModel.I{id}.image;
imageObj.data{1}   = newTypedArray;          % replace data container directly
imageObj.dataClass = class(newTypedArray);   % update class string
imageObj.maxInt    = double(intmax(class(newTypedArray)));  % update max value
imageObj.getDefaultViewPort();               % reset viewPort [min, max, gamma]
```

**Why not `setData4D`?**  `MibImage.setData` uses indexed assignment
(`obj.data{1}(...) = dataset`) which silently casts the incoming array back
to the existing container type.  Direct assignment to `imageObj.data{1}`
replaces the cell contents with the new type without casting.

---

## Dialogs

| MIB2 | MIB3 |
|------|------|
| `errordlg(msg, title)` | `utils.dlgs.showErrorDialog(obj.view.gui, msg, title)` |
| `warndlg(msg, title)` | `dlgOpt.MsgBoxOnly=true; dlgOpt.Icon='puffin_warning';` then `utils.dlgs.inputUniversalDlg(obj.view.gui, msg, {}, {}, title, dlgOpt)` |
| `questdlg(msg, title, b1, b2, def)` | `utils.dlgs.inputQuestDlg(obj.view.gui, msg, title, b1, b2, def)` |
| `inputdlg(prompt, title, 1, {default})` | `utils.dlgs.inputUniversalDlg(obj.view.gui, header, {prompt}, {default}, title)` |
| `wb = waitbar(0, 'msg')` | `wb = uiprogressdlg(obj.view.gui, 'Message', 'msg', 'Title', 't', 'Value', 0)` |
| `waitbar(v, wb)` | `wb.Value = v` |
| `delete(wb)` | `close(wb)` |

`utils.dlgs.inputUniversalDlg` icons: `'puffin_question'` (default),
`'puffin_warning'`, `'puffin_error'`, `'puffin_info'`.

---

## Widget access

| Widget | MIB2 (GUIDE) | MIB3 (AppDesigner) |
|--------|--------------|---------------------|
| Edit box — read string | `handles.myEdit.String` | `handles.mySpinner.Value` (Spinner returns double directly) |
| Edit box — read number | `str2double(handles.myEdit.String)` | `handles.mySpinner.Value` (already double) |
| Popup menu — set items | `handles.myPopup.String = {'a','b'}` | `handles.myDD.Items = {'a','b'}` |
| Popup menu — read selection | `handles.myPopup.Value` (integer index) | `handles.myDD.Value` (selected **string**) |
| Radio button | `handles.myRB.Value == 1` | `handles.myRB.Value == true` |
| Label text | `handles.myText.String` | `handles.myLabel.Text` |
| Enable/disable | `set(handles.w, 'Enable', 'on')` | `handles.w.Enable = 'on'` |

---

## Child controllers (startController)

| MIB2 | MIB3 |
|------|------|
| `obj.startController('MyChild')` (own wrapper method) | `utils.startController(obj, 'controllers.MyChild')` (shared utility) |
| Custom `purgeControllers` method | `utils.purgeChildController(parentObj, src)` (wired automatically) |

See `development/startController.md` in the repository root for the full
lifecycle contract.

---

## closeWindow — required teardown pattern

```matlab
function closeWindow(obj)
    % 1. Close children first (reverse order avoids index-shift bugs)
    for i = numel(obj.childControllers):-1:1
        child = obj.childControllers{i};
        if isa(child, 'handle') && isvalid(child)
            child.closeWindow();
        end
    end
    obj.childControllers    = {};
    obj.childControllersIds = {};

    % 2. Delete figure (prevent recursive call first)
    if isvalid(obj.view.gui)
        obj.view.gui.CloseRequestFcn = '';
        delete(obj.view.gui);
    end

    % 3. Delete listeners
    for i = 1:numel(obj.listener)
        delete(obj.listener{i});
    end

    % 4. Signal lifecycle wiring
    notify(obj, 'CloseEvent');
end
```

**`isa(child, 'handle') && isvalid(child)`** — always guard with both checks.
`isvalid` errors if called on a non-handle value (e.g. `[]`).
