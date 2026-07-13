# MIB3 Plugin Development Guide

This file documents how to create a GUI plugin for MIB3 (Microscopy Image Browser 3).  
It serves both as a step-by-step user tutorial and as a reference for Copilot/Claude when
converting or implementing new MIB3 plugins.

---

## Overview

An MIB3 GUI plugin consists of two files:

| File | Role |
|------|------|
| `<Name>.m` | **Controller** — all logic, callbacks, data access |
| `<Name>GUI.mlapp` | **View** — AppDesigner UI; wires callbacks to the controller |

Both files live in:
```
mib/plugins/<Section>/<Name>/
```

The class name equals the folder name. No `Controller` suffix.

MIB3 discovers plugins by scanning `mib/plugins/` and registers them in the Plugins ribbon tab.

---

## Folder and File Layout

```
mib/plugins/Tutorials/GuiTutorial/
    GuiTutorial.m         ← controller (this file's sibling)
    GuiTutorialGUI.mlapp  ← AppDesigner view
    icon_24px.png         ← 24×24 px icon shown in the Plugins ribbon gallery
    icon_16px.png         ← 16×16 px icon (reserved for future use)
    instruction.md        ← this file
```

Both icon files are **required** for the plugin to display a custom icon in the
Plugins ribbon tab.  If either file is absent, MIB falls back to the default
application icon (`mib/assets/icons/mib_icon_24px.png`).

Create simple 24×24 and 16×16 PNG images with a visual hint of what your plugin
does.  The icons are displayed in the gallery tile in the Plugins tab.

---

## Part 1 — The AppDesigner View (`<Name>GUI.mlapp`)

Open AppDesigner and create a new `uifigure`-based app.

### Required `winController` property

Add a public property so the controller can be stored:

```matlab
properties (Access = public)
    winController   % handle to the plugin controller
end
```

### Constructor — accept the controller as an argument

In AppDesigner, edit the constructor to accept `varargin` and pass it through
to `runStartupFcn`.  This is the only manual change needed in the generated
constructor code.

### `startupFcn` — store the controller

Add a `startupFcn` callback (via the **Callbacks** section in AppDesigner) that
stores the controller reference passed in by `core.ChildView`:

```matlab
function startupFcn(app, winController)
    app.winController = winController;
end
```

### Callback methods — delegate to the controller

All button and radio callbacks should call the matching controller method:

```matlab
function continueBtn_ButtonPushed(app, ~)
    app.winController.continueBtn_Callback();
end

function cancelBtn_ButtonPushed(app, ~)
    app.winController.closeWindow();
end

function helpBtn_ButtonPushed(app, ~)
    app.winController.helpBtn_Callback();
end

function buttonGroup_SelectionChanged(app, ~)
    app.winController.buttonGroup_Callback();
end
```

### Widget naming

Give each component a meaningful **Tag** / property name in AppDesigner.
The controller accesses widgets via `obj.view.handles.<propertyName>`, where
`core.ChildView` automatically maps every public component property of the
mlapp to the `handles` struct.

Use descriptive names that reflect purpose rather than widget type —
for example `widthEdit`, `colorPopup`, `cropRadio` — so the controller code
reads naturally.

---

## Part 2 — The Controller (`<Name>.m`)

### Class skeleton

```matlab
classdef GuiTutorial < handle

    properties
        mibModel    % handle to MibModel
        view        % core.ChildView wrapper (holds .gui and .handles)
        listener    % cell array of event listener handles
    end

    events
        CloseEvent  % fired when the window closes
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        function obj = GuiTutorial(mibModel, varargin)    ... end
        function closeWindow(obj)                  ... end
        function updateWidgets(obj)                ... end
        % ... action methods
    end
end
```

### Constructor pattern

```matlab
function obj = GuiTutorial(mibModel, varargin)
    obj.mibModel = mibModel;

    % Build the view — calls GuiTutorialGUI(obj) and populates obj.view.handles
    obj.view = core.ChildView(obj, 'GuiTutorialGUI');

    % Position the window to the left of the main MIB window
    obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

    % Match the application font
    Font = obj.mibModel.preferences.System.Font;
    if obj.view.handles.infoText1.FontSize ~= Font.FontSize || ...
            ~strcmp(obj.view.handles.infoText1.FontName, Font.FontName)
        utils.fontSizeUpdate(obj.view.gui, Font);
    end

    % Wire the window X button
    obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

    % Populate widgets and attach listeners
    obj.updateWidgets();
    obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
        @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
    obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
        @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
end
```

### `closeWindow`

Always clear `CloseRequestFcn` before deleting to prevent recursive calls.
If the plugin opens child controllers, close them first:

```matlab
function closeWindow(obj)
    for i = numel(obj.childControllers):-1:1
        if isvalid(obj.childControllers{i})
            obj.childControllers{i}.closeWindow();
        end
    end
    obj.childControllers    = {};
    obj.childControllersIds = {};
    if isvalid(obj.view.gui)
        obj.view.gui.CloseRequestFcn = '';
        delete(obj.view.gui);
    end
    for i = 1:numel(obj.listener)
        delete(obj.listener{i});
    end
    notify(obj, 'CloseEvent');
end
```

If the plugin has no child controllers, omit the child teardown block.

---

## Part 3 — Key MIB3 API Reference

### Getting the active dataset index

```matlab
id = obj.mibModel.getActiveId();   % CORRECT — always use this
% NOT: obj.mibModel.id             % WRONG — can be stale in split-panel mode
```

### Reading dataset dimensions

```matlab
options.blockModeSwitch = 0;  % ignore the viewport crop
[height, width, depth, colors, time] = ...
    obj.mibModel.I{id}.getDatasetDimensions('image', 3, options);
% orient 3 = XY (native orientation)
% Return order: height, width, depth, colors, time
```

### Reading and writing image data

```matlab
% Read the full 4-D dataset (returns a cell: img{1} is the matrix)
options.blockModeSwitch = 0;
img = obj.mibModel.getData4D('image', [], [], options);
% orient [] = current orientation; col_channel [] = all colour channels

% Write back — same dimensions only (setData4D cannot resize the array)
% Argument order: (dataset, type, orient, col_channel, options)
obj.mibModel.setData4D(img, 'image', [], [], options);
```

### Reading and writing a single 2-D slice

```matlab
% Useful for large datasets — processes one slice at a time
% getData2D returns a cell; when ROI mode is active it contains one entry per ROI
img = obj.mibModel.getData2D('image', z, [], colCh, options);

% Argument order: (dataset, type, slice_no, orient, col_channel, options)
obj.mibModel.setData2D(img, 'image', z, [], colCh, options);
% orient [] = current orientation
```

### Resizing datasets — why `setData4D` cannot be used

`setData4D` delegates to `MibImage.setData`, which performs  
`obj.data{1}(:,:,:,colChannel,:) = dataset`. This is a subscript assignment
into a fixed-size array and will error when the new data has different H/W/D.

For **crop**, use the built-in API:
```matlab
cropF  = [x1, y1, width1, height1, z1, dz, t1, dt];  % pixel coordinates
cropOpts.showWaitbar = true;
cropOpts.UIFigure    = obj.view.gui;
result = obj.mibModel.I{id}.cropDataset(cropF, cropOpts);
```

For **resize**, delegate to `controllers.ResampleDataset` via `utils.startController`
(see "Launching child controllers" section below):
```matlab
BatchOpt.ResamplingMode = {'Dimensions'};
BatchOpt.DimensionX     = num2str(newW);
BatchOpt.DimensionY     = num2str(newH);
utils.startController(obj, 'controllers.ResampleDataset', [], BatchOpt);
% ResampleDataset handles all layers and fires NewDataset + ShowImage on completion.
```

### Launching child controllers

A plugin can open any other MIB controller (e.g. `ResampleDataset`, `CropDataset`)
using `utils.startController`.  Add two tracking properties to the class:

```matlab
properties
    childControllers    = {}    % handles to open child controllers
    childControllersIds = {}    % class names of open child controllers
end
```

Then call:

```matlab
% Open a controller's GUI (interactive mode):
utils.startController(obj, 'controllers.ResampleDataset');

% Run a controller silently in batch mode:
BatchOpt.ResamplingMode = {'Dimensions'};
BatchOpt.DimensionX     = '256';
BatchOpt.DimensionY     = '256';
utils.startController(obj, 'controllers.ResampleDataset', [], BatchOpt);
```

`utils.startController` handles:
- re-focus if the child window is already open
- lifecycle wiring (`CloseEvent` listener → `utils.purgeChildController`)
- batch mode (child runs silently when a `BatchOpt` struct is the third argument)

**Required:** `closeWindow` must close all children before deleting the plugin's
own GUI.  Omitting this leaves child windows open on screen after the parent
closes:

```matlab
function closeWindow(obj)
    for i = numel(obj.childControllers):-1:1
        if isvalid(obj.childControllers{i})
            obj.childControllers{i}.closeWindow();
        end
    end
    obj.childControllers    = {};
    obj.childControllersIds = {};
    % ... rest of existing closeWindow code ...
end
```

Iterate in reverse (`numel:-1:1`) so index shifts caused by a child's own
`CloseEvent` do not skip entries.

### Dialogs

```matlab
% Error dialog
utils.dlgs.showErrorDialog(obj.view.gui, 'Something went wrong', 'Error title');

% Warning (message-only dialog)
dlgOpt.MsgBoxOnly = true;
dlgOpt.Icon       = 'puffin_warning';
utils.dlgs.inputUniversalDlg(obj.view.gui, 'Header text', {}, {}, 'Title', dlgOpt);

% Question dialog
answer = utils.dlgs.inputQuestDlg(obj.view.gui, 'Proceed?', 'Confirm', 'Yes', 'No', 'Yes');

% Input dialog — collect parameters from the user
% Signature: (ParentFigure, header, prompts, defAns, dlgTitle, options)
prompts = {'Smoothing radius:', 'Mode:'};
defAns  = {struct('Spinner', true, 'Value', 5, 'Limits', [1 100], 'Round', true), ...  % numeric spinner
           {'2D', '3D', 1}};                                                           % dropdown, default = item 1
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, 'Parameters', prompts, defAns, 'My Plugin');
if isempty(answer); return; end   % user pressed Cancel
radius = answer{1};               % spinner returns a double directly — no str2double
mode   = answer{2};               % dropdown returns the selected item string
```

`defAns` formats:

| Widget wanted | `defAns{i}` | `answer{i}` returns |
|---------------|-------------|---------------------|
| Edit field | `'text'` | char |
| Checkbox | `true` / `false` | logical |
| Dropdown | `{'item1','item2','item3', 2}` — items + **numeric default index** last | selected item (char) |
| Numeric spinner | `struct('Spinner',true,'Value',5,'Limits',[1 100],'Round',true)` | double |

Icons for `dlgOpt.Icon`: `'puffin_question'` (default), `'puffin_warning'`, `'puffin_error'`, `'puffin_info'`.

### Progress dialogs

```matlab
% Create
waitbarHandle = uiprogressdlg(obj.view.gui, ...
    'Message', 'Processing...', 'Title', 'My Plugin', 'Value', 0);

% Update  (0.0 – 1.0)
waitbarHandle.Value = 0.5;

% Close
close(waitbarHandle);
```

For **`parfor` loops** or when a **Cancel button** is needed, use `core.PoolWaitbar`
instead — never update `uiprogressdlg.Value` from inside a `parfor`:

```matlab
pwb = core.PoolWaitbar(n, 'Processing...', obj.view.gui, 'My Plugin', true);  % true = Cancelable
for i = 1:n            % works the same with parfor
    if pwb.getCancelState(); break; end
    % ... process item i ...
    pwb.increment();
end
pwb.deletePoolWaitbar();
```

### Undo support — back up data before modifying it

Call `obj.mibModel.backup(type, switch3d, options)` **before** writing to a layer, so
the user can press Ctrl+Z after the plugin runs:

```matlab
% type: 'image', 'selection', 'mask', 'labels', 'annotations', 'mibDataset', ...
% switch3d: 0 = current 2D slice only, 1 = full 3D stack
options.id = obj.mibModel.getActiveId();
obj.mibModel.backup('image', 1, options);      % store the full image stack
% ... modify the data via setData2D/3D/4D ...
```

Skip the backup (or ask the user first) for very large datasets — a 3D image backup
doubles memory use.

### Events — notifying the main MIB window

```matlab
notify(obj.mibModel, 'NewDataset');       % dataset dimensions changed
notify(obj.mibModel, 'ShowImage');        % redraw the image
notify(obj.mibModel, 'UpdateGuiWidgets'); % refresh MIB toolbar/menus
```

### Widget value access

| Widget type | Get value | Set value |
|-------------|-----------|-----------|
| `uispinner` | `handles.mySpinner.Value` (double) | `handles.mySpinner.Value = 5` |
| `uidropdown` | `handles.myDD.Value` (string) | `handles.myDD.Value = 'item'` |
| `uidropdown` items | `handles.myDD.Items` | `handles.myDD.Items = {'a','b'}` |
| `uiradiobutton` | `handles.myRB.Value` (logical) | `handles.myRB.Value = true` |
| `uilabel` | `handles.myLabel.Text` | `handles.myLabel.Text = 'hello'` |
| `uibutton` | — | `handles.myBtn.Enable = 'on'/'off'` |

### Coding rules

- **Key-value storage:** use `dictionary(keys, values)` (R2022b+), not `containers.Map`.
  Lookups: `isKey(d, key)`, `d(key)`.
- **Descriptive variable names:** write `viewPort`, `waitbarHandle`, `filename` in full —
  avoid abbreviations like `vp`, `wb`, `fn`.
- **Performance — per-slice loops writing pixel data directly.** If you bypass
  `getData2D/setData2D` and index into `obj.mibModel.I{id}.image.data` inside a loop,
  cache the array in a local variable first, mutate locally, and write back once —
  otherwise MATLAB's copy-on-write through the handle chain makes the loop 15–200× slower:

  ```matlab
  imageData = obj.mibModel.I{id}.image.data;     % single read
  for z = 1:depth
      imageData(:,:,z,ch,t) = process(imageData(:,:,z,ch,t));
  end
  obj.mibModel.I{id}.image.data = imageData;     % single write
  ```

  When using the `getData`/`setData` API this is handled for you.

---

## Part 4 — Step-by-Step: Creating a New Plugin from Scratch

1. **Create the folder**  
   `mib/plugins/<Section>/<Name>/`

2. **Add icons**  
   Place `icon_24px.png` (24×24 px) and `icon_16px.png` (16×16 px) in the folder.  
   If you skip this step, the default MIB icon is used as a fallback.

3. **Create the view in AppDesigner**  
   - Add a `winController` property (public)  
   - Modify the constructor to accept `varargin` and call `runStartupFcn`  
   - Add `startupFcn(app, winController)` that stores `app.winController = winController`  
   - Wire all component callbacks to `app.winController.<method>()`

4. **Create the controller**  
   Copy `GuiTutorial.m` as a template. Rename the class and update:  
   - Class name = folder name  
   - `guiName` string in the constructor  
   - Add your own action methods  
   - Adjust which MibModel events to listen to

5. **Register the plugin (automatic)**  
   MIB3 scans `mib/plugins/` at startup via `addRibbonPlugins.m`.  
   No manual registration is needed as long as the controller file name
   matches the folder name.

6. **Test**  
   ```matlab
   cd C:\Matlab\MIB3\mib
   mib3
   ```
   The plugin appears under Plugins → `<Section>` in the ribbon.

---

## Part 5 — Reference Files

| Purpose | Path |
|---------|------|
| This tutorial controller | `mib/plugins/Tutorials/GuiTutorial/GuiTutorial.m` |
| This tutorial view | `mib/plugins/Tutorials/GuiTutorial/GuiTutorialGUI.mlapp` |
| MIB2 → MIB3 plugin conversion cheat sheet | `mib/plugins/Tutorials/GuiTutorial/conversion_MIB2_to_MIB3_cheat_sheet.md` |
| A full-featured plugin controller | `mib/plugins/FileProcessing/ImageConverter/ImageConverter.m` |
| The view base class | `mib/+core/@ChildView/ChildView.m` |
| Dataset crop API | `mib/+core/@MibDataset/cropDataset.m` |
| Dataset resize reference | `mib/+controllers/@ResampleDataset/ResampleDataset.m` |
