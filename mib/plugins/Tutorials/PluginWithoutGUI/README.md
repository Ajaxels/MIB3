# PluginWithoutGUI — Tutorial Plugin (No Window)

## Overview

`PluginWithoutGUI` is a minimalist MIB3 tutorial plugin that demonstrates
how to write a plugin that **does not display its own window**.  It asks the
user for a threshold value, thresholds the current 2D image slice, and
writes the result to the MIB Mask layer — all without an AppDesigner `.mlapp`
file.

Read the plugins in this order for a complete picture:

| Plugin | Teaches |
|--------|---------|
| **PluginWithoutGUI** ← you are here | No-GUI plugin structure; MibModel API |
| `GuiTutorial` | Adding a GUI window (AppDesigner) |
| `DemoPlugin` | BatchOpt — macro recording and scripted replay |
| `GuiTutorialBatch` | Combining a GUI with full batch support |

---

## When to Use a No-GUI Plugin

A plugin without a GUI is the right choice when:

- The operation is **simple enough to parameterise with a single dialog**
  (`utils.dlgs.inputUniversalDlg`).
- The plugin **runs once and exits** — it does not need to stay open while
  the user adjusts settings interactively.
- You want to **keep the code as small as possible** (no `.mlapp` file needed).

---

## Files in This Folder

| File | Role |
|------|------|
| `PluginWithoutGUI.m` | The entire plugin — one `.m` file, no `.mlapp` |
| `README.md` | This file |

There is no `.mlapp` file because the plugin has no persistent window.  The
only UI elements are a single input dialog (Step 1) and a progress dialog
(Step 2), both created with standard MATLAB functions.

---

## Minimum Required Class Structure

Every MIB3 plugin must satisfy the following interface so that
`utils.startController` can manage its lifecycle:

```matlab
classdef MyPlugin < handle

    properties
        view = []       % [] signals "no GUI" to utils.startController
    end

    events
        CloseEvent      % fired when the plugin is done / closing
    end

    methods
        function obj = MyPlugin(mibModel, varargin)
            obj.mibModel = mibModel;
            % ... do work ...
            notify(obj, 'CloseEvent');
        end

        function closeWindow(obj)
            % Called by MibController on MIB shutdown.
            notify(obj, 'CloseEvent');
        end
    end
end
```

That is all.  No `listener` array, no `childControllers`, no `BatchOpt` are
required for a simple no-GUI plugin.

### Why `view = []`?

`utils.startController` inspects `obj.view` after the constructor returns.
If it is empty, `startController` re-fires `CloseEvent`, which triggers
`utils.purgeChildController` to remove the plugin from the parent's
`childControllers` list.

> **Legacy note:** MIB2 plugins used `noGui = 1` for the same purpose.
> In MIB3 the `view = []` convention is preferred because it is consistent
> with the batch-mode pattern used by `DemoPlugin` and `GuiTutorialBatch`.

---

## Lifecycle: How `utils.startController` Manages the Plugin

```
Parent controller
  │
  └─ utils.startController(parentObj, 'plugins.Tutorials.PluginWithoutGUI.PluginWithoutGUI')
       │
       ├─ 1. Instantiates PluginWithoutGUI(mibModel)
       │       Constructor calls Calculate() → dialog → threshold → ShowImage
       │       Constructor calls notify(obj, 'CloseEvent')   ← no-op (listener not wired yet)
       │       Constructor returns
       │
       ├─ 2. Wires CloseEvent listener → utils.purgeChildController
       │
       └─ 3. Checks: isempty(obj.view) → true
               Re-fires CloseEvent → purgeChildController deletes plugin,
               removes it from parentObj.childControllers
```

The `notify(obj, 'CloseEvent')` inside the constructor is therefore
**redundant when called via `startController`**, but it is good practice for
direct invocations (tests, scripts).

---

## MIB3 API Calls Demonstrated

### Reading image data

```matlab
options.blockModeSwitch = 0;    % full slice, not viewport-cropped
options.id              = id;   % target dataset index

img = cell2mat(obj.mibModel.getData2D('image', [], [], NaN, options));
%                                        type  Z    orient  channels
%   []  = current Z slice
%   []  = current orientation (XY/XZ/YZ)
%   NaN = all colour channels → result is [height, width, numChannels]
```

`getData2D` always returns a cell array `{roiId}[...]`; `cell2mat` collapses
it to a plain matrix when there is a single ROI.

### Writing mask data

```matlab
obj.mibModel.setData2D(mask, 'mask', [], [], 0, options);
%                      data  type    Z    orient  colCh
```

> **MIB2 → MIB3:** argument order changed — `dataset` is now **first**.
> MIB2 had `setData2D(type, dataset, ...)`.

### Enabling the Mask display layer

```matlab
obj.mibModel.showMask = true;                           % enable compositing
eventdata = core.ToggleEventData({'selectionPanel'});   % update ribbon checkbox
notify(obj.mibModel, 'UpdateGuiWidgets', eventdata);
notify(obj.mibModel, 'ShowImage');                      % redraw canvas
```

> **MIB2:** used `notify(mibModel, 'showMask')`.  
> **MIB3:** that event no longer exists — use the three-step pattern above.

### Progress dialog

```matlab
waitbarHandle = uiprogressdlg(obj.mibModel.mibGUI, ...
    'Message', 'Working...', 'Title', 'My Plugin', 'Value', 0);

waitbarHandle.Value = 0.5;   % update during processing

delete(waitbarHandle);       % close when done
```

> **MIB2:** used `waitbar`.  
> **MIB3:** use `uiprogressdlg` with `mibModel.mibGUI` as parent.  
> Parent must be `mibGUI` (AppContainer), **not** a plugin's own UIFigure —
> if the plugin has no window there is no alternative anyway.

### Input dialog

```matlab
answer = utils.dlgs.inputUniversalDlg( ...
    obj.mibModel.mibGUI, ...           % parent
    'Explain what the plugin does.', ...  % header (bold label above fields)
    {'Field label:'}, ...              % prompts (one per input field)
    {'default value'}, ...             % default answers
    'Dialog Title');                   % window title
if isempty(answer); return; end        % user pressed Cancel
value = str2double(answer{1});
```

> **MIB2:** used `mibInputMultiDlg({mibPath}, ...)`.  
> **MIB3:** use `utils.dlgs.inputUniversalDlg(mibGUI, ...)`.

---

## How to Register This Plugin in MIB

Add one entry to `controllers.BatchProcessing.initialize` (or to the Plugins
ribbon definition):

```matlab
obj.Sections(secIndex).Actions(actionId).Name    = 'Plugin Without GUI';
obj.Sections(secIndex).Actions(actionId).Command = ...
    'obj.mibController.startController(''plugins.Tutorials.PluginWithoutGUI.PluginWithoutGUI'');';
actionId = actionId + 1;
```

Or launch it directly from another controller:

```matlab
utils.startController(obj, 'plugins.Tutorials.PluginWithoutGUI.PluginWithoutGUI');
```

---

## Summary of MIB2 → MIB3 Changes in This Plugin

| MIB2 | MIB3 |
|------|------|
| `mibPluginWithoutGUIController` | `PluginWithoutGUI` |
| `noGui = 1` property | `view = []` property |
| `closeEvent` event | `CloseEvent` event |
| `mibModel.id` | `mibModel.getActiveId()` |
| `global mibPath; mibInputMultiDlg({mibPath},...)` | `utils.dlgs.inputUniversalDlg(mibModel.mibGUI,...)` |
| `warndlg(msg, title)` | `utils.dlgs.inputUniversalDlg` with `MsgBoxOnly=true` |
| `waitbar(v, wb)` | `uiprogressdlg(mibModel.mibGUI, ...)` |
| `getData2D('image')` | `getData2D('image', [], [], NaN, options)` |
| `setData2D('mask', data)` | `setData2D(data, 'mask', [], [], 0, options)` |
| `notify(mibModel, 'showMask')` | `mibModel.showMask=true` + `UpdateGuiWidgets` + `ShowImage` |
| Orient value `4` (native YX) | Orient value `3` |
