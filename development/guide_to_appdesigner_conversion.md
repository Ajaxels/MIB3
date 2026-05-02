# MIB2 GUIDE → MIB3 AppDesigner Conversion Guide

> **Purpose:** Generic reference for porting any MIB2 GUIDE-based dialog/controller to the
> MIB3 AppDesigner + package framework. Add new patterns here as they are discovered so
> future conversions can proceed without rediscovering the same rules.
> Last updated during `Annotations` controller port.

---

## 1. File layout

| MIB2 | MIB3 |
|------|------|
| `Classes/@mibXxxController/mibXxxController.m` | `mib/+controllers/@Xxx/Xxx.m` |
| `GuiTools/mibXxxGUI.m` + `mibXxxGUI.fig` | `mib/+views/XxxGUI.mlapp` |

Naming: drop the `mib` prefix, PascalCase the rest (`mibBoundingBoxController` → `BoundingBox`).

---

## 2. View (.mlapp)

Create a new App Designer app in `mib/+views/XxxGUI.mlapp`.

- The startup function must accept exactly one argument after `app`: the controller handle.
  `core.ChildView` calls `XxxGUI(controller)`.
- Every interactive widget must have a **Tag** set — `core.ChildView` maps Tags to
  `obj.view.handles.<Tag>`.
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

### Class and properties

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
        CloseEvent
    end
```

### Constructor

Helper renames:

```matlab
% MIB2                                   % MIB3
mibChildView(obj, 'mibXxxGUI')           core.ChildView(obj, 'views.XxxGUI')
mibRescaleWidgets(...)                   (remove — AppDesigner handles scaling)
mibUpdateFontSize(gui, Font)             utils.fontSizeUpdate(gui, Font)
moveWindowOutside(h, 'left')             utils.moveWindowOutside(gui, mibGUI, 'left')
updateGUIFromBatchOpt_Shared(...)        utils.updateGUIFromBatchOpt_Shared(...)
updateBatchOptCombineFields_Shared(...)  utils.updateBatchOptCombineFields_Shared(...)
```

**Generic skeleton** (covers GUI mode, batch mode with struct, and the `NaN` defaults probe — all dialogs that participate in batch processing must implement all three):

```matlab
function obj = Xxx(mibModel, varargin)
    obj.mibModel = mibModel;
    if nargin > 1 && ~isempty(varargin{1})
        obj.extraController = varargin{1};   % optional 2nd positional arg
    else
        obj.extraController = [];
    end

    %% 1. Initialize BatchOpt with defaults — see "BatchOpt structure" section
    obj.BatchOpt.SomeField = ...;
    obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Xxx';
    obj.BatchOpt.mibBatchActionName  = 'Do something';
    obj.BatchOpt.mibBatchTooltip.SomeField = '...';

    %% 2. Batch-mode dispatch — runs without GUI
    if nargin == 3
        BatchOptInput = varargin{2};
        if ~isstruct(BatchOptInput)
            if isnan(BatchOptInput)              % caller asked for default options
                obj.returnBatchOpt();
            else
                utils.dlgs.showErrorDialog([], 'A structure as the 3rd parameter is required!', 'BatchOpt Error');
            end
            return;
        end
        obj.BatchOpt = updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);
        obj.applyButton_Callback();   % the action method, run headless
        return;
    end

    %% 3. GUI mode
    obj.view = core.ChildView(obj, 'views.XxxGUI');
    obj.addCallbacks();
    obj.updateWidgets();

    Font = obj.mibModel.preferences.System.Font;
    if obj.view.handles.<anchorWidget>.FontSize ~= Font.FontSize ...
            || ~strcmp(obj.view.handles.<anchorWidget>.FontName, Font.FontName)
        utils.fontSizeUpdate(obj.view.gui, Font);
    end
    obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

    obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
    obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
    % register additional events here (e.g. AxesLimitsChanged)

    obj.view.gui.Visible = true;
end
```

Notes:
- **Always** support all three constructor signatures: `(model)`, `(model, extra)`, `(model, [], BatchOpt)` — the batch system relies on it.
- The `isnan(BatchOptInput)` branch is how the batch GUI probes defaults via the `SyncBatch` event — never skip it.
- `obj.view.gui.Visible = true` at the very end avoids the user seeing a half-built dialog.

### addCallbacks (new method, no MIB2 equivalent)

All widget callbacks are wired here, called once from the constructor.
**Always set `CloseRequestFcn` first** so the window X button triggers proper cleanup:

```matlab
function addCallbacks(obj)
    obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
    handles = obj.view.handles;
    handles.someEdit.ValueChangedFcn   = @obj.updateBatchOptFromGUI;
    handles.applyButton.ButtonPushedFcn = @(~,~) obj.applyButton_Callback;
    handles.closeButton.ButtonPushedFcn = @(~,~) obj.closeButton_Callback;
    ...
end
```

In MIB2 these assignments lived in the GUIDE `.m` file (`OpeningFcn`, per-widget
`_Callback` stubs, `CloseRequestFcn`). All of that moves here.

### ViewListner_Callback2 (static method)

Add a guard against stale listeners (fires when the window was closed via X
before the listener was cleaned up):

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

MIB2 only listened to `updateGuiWidgets`; MIB3 also adds `NewDataset`.

### updateBatchOptFromGUI

AppDesigner callbacks pass an extra `valueChangedData` argument (declare but ignore):

```matlab
function updateBatchOptFromGUI(obj, hObject, ~)
    obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
end
```

### returnBatchOpt and closeWindow (boilerplate)

Two short methods every batch-aware controller needs verbatim:

```matlab
function returnBatchOpt(obj, BatchOptOut)
    if nargin < 2; BatchOptOut = obj.BatchOpt; end
    eventdata = core.ToggleEventData(BatchOptOut);
    notify(obj.mibModel, 'SyncBatch', eventdata);
end

function closeWindow(obj)
    if isvalid(obj.view.gui); delete(obj.view.gui); end
    for i = 1:numel(obj.listener); delete(obj.listener{i}); end
    notify(obj, 'CloseEvent');
end
```

### BatchOpt structure — shapes per widget type

The `BatchOpt` struct is the source of truth for every persisted parameter. Its shape
**varies by widget type** — `utils.updateBatchOptFromGUI_Shared` and
`updateBatchOptCombineFields_Shared` dispatch on the shape, so getting it wrong silently
corrupts batch round-trips. Use this table for every new field:

| Widget | BatchOpt shape | Notes |
|--------|---------------|-------|
| `uicheckbox` | `false` / `true` (logical scalar) | unchanged from MIB2 |
| `uidropdown` | `{'item', {'item','itemB',...}}` — value first, allowed list as 2nd cell | MIB3 stores the **string**, not an index. Same shape for `uibuttongroup` (radio) — list children's `Tag` names |
| `uieditfield(text)` | `'string'` (char) | unchanged |
| `uispinner`, `uinumericeditfield` | `{value, [min max], roundFlag}` — **3-cell numeric form** | NEW in MIB3. MIB2 stored these as strings (`'2'`, `'10'`). Spinner widget returns numeric `.Value` directly, no `str2double`. |
| Plain numeric scalar (no widget bound) | bare number | rare — only for internal flags |

**Example block** showing all four common shapes side-by-side:

```matlab
% checkbox
obj.BatchOpt.UseScalebar = false;

% dropdown / radio group  (string default + allowed list)
obj.BatchOpt.FileFormat    = {'TIF'};
obj.BatchOpt.FileFormat{2} = {'TIF', 'BMP', 'JPG', 'PNG'};

% text edit field
obj.BatchOpt.Description = '';

% numeric spinner (default / range / round)
obj.BatchOpt.ColsNumber{1} = 2;
obj.BatchOpt.ColsNumber{2} = [1 Inf];
obj.BatchOpt.ColsNumber{3} = true;
```

**MIB2 → MIB3 BatchOpt migration rules:**

| MIB2 | MIB3 | Reason |
|------|------|--------|
| `BatchOpt.RowsNumber = '2'` (string) | `BatchOpt.RowsNumber = {2, [1 Inf], true}` | spinner widget — see table above |
| `str2double(BatchOpt.X)` reads back the value | `BatchOpt.X{1}` reads back the value | numeric is stored directly |
| `BatchOpt.Target = {'File', {'File','Clipboard'}}` | unchanged | dropdown/radio shape is the same |

**Required metadata fields** (all three are checked by the batch system):

```matlab
obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Xxx';   % MIB2 used 'Menu -> File' etc.
obj.BatchOpt.mibBatchActionName  = 'Action label';
obj.BatchOpt.mibBatchTooltip.<EveryUserField> = '...';   % one entry per user-facing field
```

`mibBatchSectionName` moved from `'Menu -> ...'` to `'Ribbon -> ...'` because MIB3 has a
ribbon, not a menu bar — update it whenever you port a controller.

### Reading BatchOpt at action time

In MIB2 most callbacks read widget values directly (`str2double(handles.X.String)`); in
MIB3 the *consistent* path is to read `obj.BatchOpt.<Field>{1}` (or the bare value for
checkboxes / strings). The same read works in both GUI and headless batch modes — no
conditional needed. Use `obj.view.handles.X.Value` only when the widget is purely
cosmetic and not in `BatchOpt` (e.g. an `outputDir` text field that mirrors a derived
path).

### Other renames

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
| `errordlg(...)` | `utils.dlgs.showErrorDialog(...)` or `inputUniversalDlg` with `puffin_error` icon |
| `global mibPath` | `mibPath = obj.mibModel.mibPath` (property on MibModel) |
| `obj.mibModel.mibDoBackup(type, sw)` | `obj.mibModel.backup(type, sw)` |
| `obj.mibModel.I{id}.clearMask()` | `obj.mibModel.I{id}.clearLayer('mask')` |
| `obj.mibModel.I{id}.depth/width/height` | `obj.mibModel.I{id}.image.depth/width/height` |
| `obj.mibModel.I{id}.pixSize` | `obj.mibModel.I{id}.image.pixSize` |
| `obj.mibModel.I{id}.getBoundingBox()` | `obj.mibModel.I{id}.image.boundingBox` |
| `obj.mibModel.I{id}.maskExist` | `obj.mibModel.I{id}.maskExist` (unchanged) |
| `obj.mibModel.getImageProperty('orientation')` | `obj.mibModel.I{id}.orientation` |
| `obj.mibModel.getImageProperty('slices')` | `obj.mibModel.I{id}.slices` |
| `obj.mibModel.getImageProperty('depth/width/height/time')` | `obj.mibModel.I{id}.image.depth/width/height/time` |
| `obj.mibModel.getImageProperty('defaultAnnotationText')` | `obj.mibModel.I{id}.annotations.defaultAnnotationText` |
| MIB2 orientation: XY=4, ZX=1, ZY=2 | MIB3 orientation: XY=3, ZX=1, ZY=2 |
| `slices{3}` = colour, `slices{4}` = z (MIB2) | `slices{3}` = z, `slices{4}` = colour (MIB3) — slices indices shifted with the orientation change |
| `BackgroundColor = 'r'` / `'g'` (char) | RGB triplet `[1 0 0]` / `[0.149 0.902 0.1804]` |
| `waitbar`, `uiprogressdlg` | `core.PoolWaitbar` — see "Progress dialogs" section |
| `mibAddScaleBar(...)` | `utils.addScaleBar(...)` — orientation default ``4`` → ``3`` |
| `mibImWrite(...)` | `utils.mibImWrite(...)` |

---

## 4. Model access

Data now lives inside `MibDataset.image` rather than directly on `MibDataset`:

```matlab
% MIB2                                   % MIB3
I{id}.pixSize                            I{id}.image.pixSize
I{id}.getBoundingBox()                   I{id}.image.boundingBox
I{id}.pixSize.x = v; ...                 I{id}.setPixSize(newStruct)
I{id}.updateBoundingBox(NaN, shift)      I{id}.updateBoundingBox([], shift)
```

### `getDatasetDimensions` arity differs by class

The same method name exists on **two** classes with **different signatures** — picking
the wrong receiver gives a confusing "Too many input arguments" error:

```matlab
% MibDataset (3 args after obj):
[h,w,d,c,t] = ds.getDatasetDimensions(type, orient, options);   % type = 'image'/'mask'/...

% MibImage (3 args after obj, different meaning):
[h,w,d,c,t] = ds.image.getDatasetDimensions(orient, splitDims, blockModeSwitch);
```

MIB2 had a 4-arg form on `mibImage` (`(type, NaN, NaN, options)`) — that signature is
gone. When porting, drop the leading `'image'` and the redundant `NaN`.

### Methods removed from MibImage / MibDataset

MIB2 attached interactive helpers (e.g. dialog launchers) directly to `mibImage`. In
MIB3 these are **plain `utils.*` functions**; the call site is responsible for showing
the dialog and writing the result back via the dataset's setters.

| MIB2 (gone in MIB3) | MIB3 replacement |
|---------------------|-------------------|
| `I{id}.updatePixSizeResolution()` (popup dialog form) | `[~, newPx, ok] = utils.updatePixSizeAndResolution([], I{id}.image.pixSize, dlgOpts);`<br/>`if ok; I{id}.setPixSize(newPx); end` |
| `I{id}.updatePixSizeResolution(pixSize)` (programmatic form) | `I{id}.setPixSize(pixSize)` |

When you hit `Unrecognized method ... for class 'core.MibDataset'`, look for the same
name on `mibImage` in MIB2 — most of them moved to `+utils/` and now require the
caller to glue dialog → setter.

---

## 5. Progress dialogs (`core.PoolWaitbar`)

**All progress dialogs in MIB3 controllers must be `core.PoolWaitbar`** (defined in
`mib/+core/@PoolWaitbar/PoolWaitbar.m`). Bare `waitbar` and bare `uiprogressdlg` are
forbidden — `PoolWaitbar` is the only progress widget the rest of MIB3 cooperates with,
it works for both serial and `parfor` loops, and it is the only one wired to the
parallel `DataQueue` machinery.

**The Cancel button is always on** (5th constructor arg = `true`). Every long-running
operation must be interruptible — never pass `false`, never omit the argument:

```matlab
pwb = core.PoolWaitbar(maxIterations, 'Working...', obj.view.gui, 'Title', true);   % always true

for k = 1:maxIterations
    if pwb.getCancelState()           % cancel-check: top of every iteration
        pwb.deletePoolWaitbar();
        return;                       % caller must restore button colours / state
    end
    % ... work ...
    pwb.increment();                  % replaces  wb.Value = k/N
end

% Update the message before a separate phase (e.g. "Saving...")
pwb.updateText('Exporting, please wait...');

pwb.deletePoolWaitbar();              % replaces  close(wb) / delete(wb)
```

Cancellation rules:
- Check `getCancelState()` at the **top of each loop iteration** and once **before any
  irreversible operation** (file save, clipboard copy, network call).
- Every early-return path **must** call `deletePoolWaitbar()` first — otherwise the
  dialog and its `DataQueue` listener leak.
- Inside `parfor`, only `pwb.increment()` is safe; never call `getCancelState` or
  `updateText` from a worker.

For long sequential phases that share one dialog, use
`pwb.deletePoolWaitbar(true)` to detach the listener while keeping the
`uiprogressdlg` handle (`pwb.getWaitbarHandle()`) for the next phase.

---

## 6. Two-way sync between dropdown and TabGroup

A common GUIDE pattern was a "format" dropdown that toggled the visibility of
several overlapping panels (`tifPanel`, `jpgPanel`, ...). In AppDesigner the
panels become tabs of a `uitabgroup`, and the dropdown should stay in sync with
the active tab in **both** directions:

```matlab
% wired in addCallbacks():
h.FormatTabGroup.SelectionChangedFcn = @(~,~) obj.FormatTabGroup_Callback();
h.FileFormat.ValueChangedFcn         = @(~,~) obj.FileFormat_Callback();
```

```matlab
function FileFormat_Callback(obj)            % dropdown → tab
    fmt = obj.view.handles.FileFormat.Value;
    obj.view.handles.FormatTabGroup.SelectedTab = obj.view.handles.([lower(fmt) 'Tab']);
    % ... derive filename / batchopt ...
end

function FormatTabGroup_Callback(obj)        % tab → dropdown
    fmt = obj.view.handles.FormatTabGroup.SelectedTab.Title;   % use tab Title as truth
    obj.view.handles.FileFormat.Value = fmt;
    % ... same derive logic ...
end
```

No re-entrancy guard is needed: AppDesigner does not fire `ValueChangedFcn` /
`SelectionChangedFcn` on **programmatic** writes, only on user interaction. Keep the
two callbacks free of mutual calls and the loop never closes.

---

## 7. Checklist

- [ ] `.mlapp` startup function accepts `(app, controller)`
- [ ] All widgets have unique Tags; addressed as `obj.view.handles.<Tag>`
- [ ] `core.ChildView` used; `obj.view` (lowercase)
- [ ] Constructor supports all three signatures: `(model)`, `(model, extra)`, `(model, [], BatchOpt)`
- [ ] `isnan(BatchOptInput)` branch present and calls `returnBatchOpt()`
- [ ] `BatchOpt` shapes match the widget table (spinners use `{value, [min max], round}`)
- [ ] `mibBatchSectionName` reads `'Ribbon -> ...'`, not `'Menu -> ...'`
- [ ] `mibBatchTooltip.<Field>` exists for every user-facing BatchOpt entry
- [ ] `addCallbacks()` called from constructor; `CloseRequestFcn` set inside it
- [ ] `ViewListner_Callback2` has `~isvalid(obj.view.gui)` guard
- [ ] Both `UpdateGuiWidgets` and `NewDataset` listeners registered
- [ ] All utility functions namespaced (`utils.*`, `core.*`)
- [ ] Event names PascalCase (`UpdateGuiWidgets`, `UpdateImgInfo`, `NewDataset`)
- [ ] No `waitbar` / bare `uiprogressdlg` — `core.PoolWaitbar` only, **constructed with `Cancelable = true`** and `getCancelState()` checked at every loop top + before every irreversible op
- [ ] No `str2double` on spinner / numeric edit field values (they're already numeric)
- [ ] No `'r'` / `'g'` background colour strings — RGB triplets only
- [ ] `slices{3}` ↔ `slices{4}` swap audited (color is now index 4, z is index 3)
- [ ] Calls to removed `mibImage` methods (e.g. `updatePixSizeResolution`) replaced by `utils.*` + `setPixSize`
