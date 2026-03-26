# MIB2 GUIDE → MIB3 AppDesigner Conversion Guide

Generic reference for porting any MIB2 GUIDE-based dialog/controller to the MIB3 AppDesigner + package framework. Add new patterns here as they are discovered.

---

## 1. File Layout

| MIB2 | MIB3 |
|------|------|
| `Classes/@mibXxxController/mibXxxController.m` | `mib/+controllers/@Xxx/Xxx.m` |
| `GuiTools/mibXxxGUI.m` + `mibXxxGUI.fig` | `mib/+views/XxxGUI.mlapp` |

Naming: drop the `mib` prefix, PascalCase the rest (`mibBoundingBoxController` → `BoundingBox`).

---

## 2. View (.mlapp)

Create a new App Designer app in `mib/+views/XxxGUI.mlapp`.

- Startup function must accept exactly one argument after `app`: the controller handle. `core.ChildView` calls `XxxGUI(controller)`.
- Every interactive widget must have a **Tag** set — `core.ChildView` maps Tags to `obj.view.handles.<Tag>`.
- The `.mlapp` contains **layout only** — no callback logic.
- No `CloseRequestFcn` in the `.mlapp`; it is set in the controller's `addCallbacks`.

Widget property differences from GUIDE:

| Property | GUIDE | AppDesigner |
|----------|-------|-------------|
| Text display | `.String` | `.Text` (uilabel) |
| Edit / text area | `.String` | `.Value` |
| Checkbox, dropdown | `.Value` | `.Value` (unchanged) |
| Button callback | `Callback` | `ButtonPushedFcn` |
| Edit callback | `Callback` | `ValueChangedFcn` |

---

## 3. Controller (Xxx.m)

### Class and Properties

```matlab
classdef Xxx < handle        % was: mibXxxController
    properties
        mibModel
        view                 % was: View
        listener
        BatchOpt
        ...
    end
    events
        closeEvent
    end
```

### Constructor

```matlab
% MIB2                                   % MIB3
mibChildView(obj, 'mibXxxGUI')           core.ChildView(obj, 'views.XxxGUI')
mibRescaleWidgets(...)                   (remove — AppDesigner handles scaling)
mibUpdateFontSize(gui, Font)             utils.fontSizeUpdate(gui, Font)
moveWindowOutside(h, 'left')             utils.moveWindowOutside(gui, mibGUI, 'left')
updateGUIFromBatchOpt_Shared(...)        utils.updateGUIFromBatchOpt_Shared(...)
updateBatchOptCombineFields_Shared(...)  utils.updateBatchOptCombineFields_Shared(...)
```

After creating the view, call `obj.addCallbacks()`, then register listeners:

```matlab
obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
```

### addCallbacks (new method, no MIB2 equivalent)

All widget callbacks are wired here, called once from the constructor.
**Always set `CloseRequestFcn` first:**

```matlab
function addCallbacks(obj)
    obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
    handles = obj.view.handles;
    handles.someEdit.ValueChangedFcn    = @obj.updateBatchOptFromGUI;
    handles.applyButton.ButtonPushedFcn = @(~,~) obj.applyButton_Callback;
    handles.closeButton.ButtonPushedFcn = @(~,~) obj.closeButton_Callback;
    ...
end
```

### ViewListner_Callback2 (static method)

Add a guard against stale listeners:

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

### updateBatchOptFromGUI

AppDesigner callbacks pass an extra `valueChangedData` argument (declare but ignore):

```matlab
function updateBatchOptFromGUI(obj, hObject, ~)
    obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
end
```

---

## 4. Widget Syntax Reference

### Listbox / Popup Index → String

MIB2 popup `Value` is a numeric index; MIB3 dropdown `Value` is the string:

```matlab
% MIB2: idx = obj.View.handles.sectionPopup.Value;
%        name = obj.View.handles.sectionPopup.String{idx};
% MIB3: name = obj.view.handles.sectionPopup.Value;
```

Setting a popup by index:
```matlab
% MIB2: obj.View.handles.sectionPopup.Value = 3;
% MIB3: items = obj.view.handles.sectionPopup.Items;
%        obj.view.handles.sectionPopup.Value = items{3};
```

Full widget syntax table:

| GUIDE | AppDesigner |
|-------|-------------|
| `widget.String` (popup/listbox) | `widget.Items` |
| `widget.Value` (popup → numeric index) | `widget.Value` (→ actual string item) |
| `popup.String{popup.Value}` | `popup.Value` directly |
| `widget.String` (button) | `widget.Text` |
| `widget.String` (edit box) | `widget.Value` |
| `widget.String` (label/text) | `widget.Text` |
| `.TooltipString` | `.Tooltip` |
| `.BackgroundColor = 'g'` | `.BackgroundColor = [0 1 0]` |
| `.CData` (button icon) | `.Icon` |
| `.Visible = 'on'/'off'` | `.Visible = 'on'/'off'` (both work) |

---

## 5. Global Variables and Utility Functions

| MIB2 | MIB3 |
|------|------|
| `global Font;` | `obj.mibModel.preferences.System.Font` |
| `global mibPath;` | `obj.mibModel.mibPath` |
| `moveWindowOutside(gui, 'left')` | `utils.moveWindowOutside(gui, obj.mibModel.mibGUI, 'left')` |
| `mibRescaleWidgets(gui)` | Remove (not needed in AppDesigner) |
| `mibUpdateFontSize(gui, Font)` | `utils.fontSizeUpdate(gui, Font)` |
| `mibInputMultiDlg({mibPath}, ...)` | `utils.dlgs.mibInputMultiDlg(...)` |
| `errordlg(...)` | `utils.dlgs.showErrorDialog(...)` |
| `findjobj(...)` | Remove — use native uitable `ColumnWidth`/`scroll()` |

---

## 6. Other Renames

| MIB2 | MIB3 |
|------|------|
| `obj.View` | `obj.view` |
| `okBtn_Callback` | `applyButton_Callback` |
| `cancelBtn_Callback` | `closeButton_Callback` |
| `ToggleEventData(x)` | `core.ToggleEventData(x)` |
| `notify(..., 'updateGuiWidgets')` | `notify(..., 'UpdateGuiWidgets')` |
| `notify(..., 'updateImgInfo')` | `notify(..., 'UpdateImgInfo')` |
| `notify(..., 'plotImage', eventdata)` | `notify(..., 'ShowImage')` (no eventdata needed) |
| `notify(..., 'updateId')` | `notify(..., 'UpdateGuiWidgets')` |
| `notify(..., 'updatedAnnotations')` | `notify(..., 'UpdateAnnotations')` |
| `notify(..., 'showMask')` | set `obj.mibModel.showMask = true` then `notify(..., 'ShowImage')` |
| `notify(..., 'updateLayerSlider', evd)` | update `I{id}.slices{orient}` then `notify(..., 'SliceChanged')` |
| `notify(..., 'updateTimeSlider', evd)` | update `I{id}.slices{5}` then `notify(..., 'FrameChanged')` |
| `obj.mibModel.I{id}.depth/width/height` | `obj.mibModel.I{id}.image.depth/width/height` |
| `obj.mibModel.I{id}.pixSize` | `obj.mibModel.I{id}.image.pixSize` |
| `obj.mibModel.getImageProperty('orientation')` | `obj.mibModel.I{id}.orientation` |
| MIB2 orientation: XY=4, ZX=1, ZY=2 | MIB3 orientation: XY=3, ZX=1, ZY=2 |

---

## 7. Context Menus

Create programmatically in `createContextMenus()`:

```matlab
cm = uicontextmenu(obj.view.gui);
uimenu(cm, 'Label', 'Action', 'MenuSelectedFcn', @(~,~) obj.callback());
obj.view.handles.widget.ContextMenu = cm;
```

---

## 8. Java Table Removal

Remove properties: `jSelectedActionTable`, `jSelectedActionTableScroll`.
Remove `findjobj(...)` init code. Replace with:
```matlab
obj.view.handles.selectedActionTable.ColumnWidth = {'fit', 'auto'};
```
Use `scroll(uitableHandle, 'row', rowIndex)` (R2021a+) for programmatic scrolling.

---

## 9. Conversion Checklist

- [ ] `.mlapp` startup function accepts `(app, controller)`
- [ ] All widgets have unique Tags; addressed as `obj.view.handles.<Tag>`
- [ ] `core.ChildView` used; `obj.view` (lowercase)
- [ ] `addCallbacks()` called from constructor; `CloseRequestFcn` set inside it
- [ ] `ViewListner_Callback2` has `~isvalid(obj.view.gui)` guard
- [ ] Both `UpdateGuiWidgets` and `NewDataset` listeners registered
- [ ] All utility functions namespaced (`utils.*`, `core.*`)
- [ ] Event names PascalCase (`UpdateGuiWidgets`, `UpdateImgInfo`, `NewDataset`)
- [ ] `obj.view` (lowercase) throughout — never `obj.View`
- [ ] `global mibPath` / `global Font` replaced with model properties
