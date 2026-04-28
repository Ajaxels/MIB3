# GuiTutorialBatch — Batch-Compatible Tutorial Plugin

## Overview

`GuiTutorialBatch` extends `GuiTutorial` (which teaches the four image
operations: Crop / Resize / Convert / Invert) by adding the full **BatchOpt
infrastructure** required for macro recording, replay, and headless scripted
execution.

Read these files in order:

| File | Teaches |
|------|---------|
| `GuiTutorial/GuiTutorial.m` | Plugin structure, four operations, GUI wiring |
| `DemoPlugin/DemoPlugin.m` | BatchOpt system, three calling modes |
| `DemoPlugin/README.md` | BatchOpt encoding table, shared utilities, batch registration |
| **This folder** | Combining both — operations that work from GUI and batch |

---

## Files in this Folder

| File | Role |
|------|------|
| `GuiTutorialBatch.m` | Controller — all logic lives here |
| `GuiTutorialBatchGUI.mlapp` | AppDesigner view — copy `GuiTutorialGUI.mlapp` and adapt |
| `README.md` | This file |

---

## Key Differences from GuiTutorial

### 1. BatchOpt property

Every tunable parameter lives in `obj.BatchOpt`. Field names must **exactly
match the Tag** of the corresponding AppDesigner widget.

### 2. Three calling modes (see constructor)

```matlab
% Interactive (from Plugins ribbon):
utils.startController(parentObj, 'plugins.Tutorials.GuiTutorialBatch.GuiTutorialBatch');

% Headless batch (from a script or macro replay):
BatchOpt.OperationButtonGroup = {'cropRadio'};
BatchOpt.xMinEdit   = {10, [1 50000], 'on'};
BatchOpt.yMinEdit   = {10, [1 50000], 'on'};
BatchOpt.widthEdit  = {200, [1 50000], 'on'};
BatchOpt.heightEdit = {200, [1 50000], 'on'};
GuiTutorialBatch(mibModel, parentObj, BatchOpt);

% Query (discover parameters without running):
GuiTutorialBatch(mibModel, parentObj, NaN);
```

### 3. updateWidgets() — BatchOpt-driven, not widget-direct

GuiTutorial writes directly to widget properties:
```matlab
obj.view.handles.widthEdit.Value = width;   % GuiTutorial style
```

GuiTutorialBatch updates BatchOpt then calls the shared utility:
```matlab
obj.BatchOpt.widthEdit{1} = width;                               % update struct
obj.view = utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);  % push to widgets
```

**Why?** The shared utility handles all widget types uniformly.  Any widget
whose Tag matches a BatchOpt field name gets updated automatically — no
per-widget assignment code needed.

### 4. Operation methods return a success flag

```matlab
success = obj.cropDataset();   % returns true/false
```

`Calculate()` only calls `returnBatchOpt()` (which registers the operation in
the macro recorder) when `success` is true.  A failed crop (out-of-bounds
rectangle) or a no-op conversion (same class) is therefore NOT recorded.

### 5. Spinner limits are NOT clamped to the current image size

GuiTutorial clamps spinner values to the current image width/height.
GuiTutorialBatch uses a fixed upper limit of 50 000 for all spinners so that
the **Resize** operation can upscale an image beyond its current dimensions.
The **Crop** operation validates the rectangle at run time inside `cropDataset()`.

---

## BatchOpt Field Reference

| Field | Widget type | Tag | Default | Notes |
|-------|-------------|-----|---------|-------|
| `OperationButtonGroup` | `uibuttongroup` | `OperationButtonGroup` | `'cropRadio'` | Radio Tags: cropRadio/resizeRadio/convertRadio/invertRadio |
| `xMinEdit` | `uispinner` | `xMinEdit` | `{1, [1 50000], 'on'}` | Crop origin X |
| `yMinEdit` | `uispinner` | `yMinEdit` | `{1, [1 50000], 'on'}` | Crop origin Y |
| `widthEdit` | `uispinner` | `widthEdit` | `{512, [1 50000], 'on'}` | Crop/Resize width |
| `heightEdit` | `uispinner` | `heightEdit` | `{512, [1 50000], 'on'}` | Crop/Resize height |
| `convertDropdown` | `uidropdown` | `convertDropdown` | `{'uint8', {'uint8','uint16'}}` | Convert target class |
| `colorDropdown` | `uidropdown` | `colorDropdown` | `{'Channel 1', {dynamic}}` | Invert channel |
| `showWaitbar` | `uicheckbox` | `showWaitbar` | `true` | Show/hide progress |
| `id` | *(none)* | — | from `getActiveId()` | Not a widget; session-specific |

> For full encoding rules see `DemoPlugin/README.md` § "BatchOpt Field Encoding".

---

## Building the AppDesigner View

Copy `GuiTutorial/GuiTutorialGUI.mlapp` to this folder as
`GuiTutorialBatchGUI.mlapp`.  Rename the class inside the file from
`GuiTutorialGUI` to `GuiTutorialBatchGUI`.

### Required Widget Tags

Set **exactly** these Tags on the components:

| Widget | Tag | Purpose |
|--------|-----|---------|
| Button group | `OperationButtonGroup` | Drives dispatch in Calculate() |
| Radio button | `cropRadio` | — |
| Radio button | `resizeRadio` | — |
| Radio button | `convertRadio` | — |
| Radio button | `invertRadio` | — |
| Spinner | `xMinEdit` | Crop/resize X |
| Spinner | `yMinEdit` | Crop/resize Y |
| Spinner | `widthEdit` | Crop/resize width |
| Spinner | `heightEdit` | Crop/resize height |
| Drop-down | `convertDropdown` | Convert target class |
| Drop-down | `colorDropdown` | Invert channel |
| Checkbox | `showWaitbar` | Progress flag (new in this plugin) |
| Text label | `infoText1` | Static title |
| Text label | `infoText2` | Dynamic dataset info |
| Button | `continueBtn` | Run the operation |
| Button | `helpBtn` | Open tutorials page |
| Button | `closeBtn` | Close the plugin |

### Required Callbacks in the mlapp

Every interactive widget must call back into the controller.  Wire callbacks as:

```matlab
% Every plain widget (spinners, dropdowns, checkbox):
function widthEdit_ValueChanged(app, event)
    app.winController.updateBatchOptFromGUI(event);
end

% Button group — buttonGroup_Callback reads SelectedObject.Tag directly,
% so updateBatchOptFromGUI is NOT needed here:
function OperationButtonGroup_SelectionChanged(app, event) %#ok<INUSD>
    app.winController.buttonGroup_Callback();
end

% Buttons:
function continueBtnButtonPushed(app, event)
    app.winController.continueBtn_Callback();
end
function helpBtnButtonPushed(app, event)
    app.winController.helpBtn_Callback();
end
function closeBtnButtonPushed(app, event)
    app.winController.closeWindow();
end
```

### startupFcn in the mlapp

The app's `startupFcn` must store the controller reference on the app:
```matlab
function startupFcn(app, controller)
    app.winController = controller;
end
```

---

## Method Overview

| Method | Called from | Purpose |
|--------|-------------|---------|
| `GuiTutorialBatch(mibModel, ...)` | utils.startController | Constructor; handles all three modes |
| `closeWindow()` | CloseRequestFcn, closeBtn | Tear down GUI and listeners |
| `updateWidgets()` | Constructor, MibModel events | Rebuild BatchOpt from dataset, push to widgets |
| `buttonGroup_Callback()` | mlapp SelectionChanged, updateWidgets | Enable/disable widgets per operation |
| `updateBatchOptFromGUI(event)` | mlapp ValueChanged callbacks | Pull changed widget → BatchOpt |
| `returnBatchOpt([override])` | Calculate, query mode | Register run with macro recorder |
| `continueBtn_Callback()` | Continue button | Calls Calculate() |
| `Calculate()` | continueBtn, batch constructor | Dispatch + macro recording |
| `cropDataset()` → bool | Calculate | Crop to BatchOpt rectangle |
| `resizeDataset()` → bool | Calculate | Resize via ResampleDataset |
| `convertDataset()` → bool | Calculate | Type-convert uint8 ↔ uint16 |
| `invertDataset()` → bool | Calculate | Invert one colour channel |
| `getDialogParent()` | Internal | Returns obj.view.gui or mibGUI |
| `normalizeBatchOptForCurrentDataset()` | Batch constructor | Validate dynamic fields in headless mode |

---

## Batch Registration

To make this plugin appear in **Edit → Batch Processing**, add to
`controllers.BatchProcessing.initialize`:

```matlab
obj.Sections(secIndex).Actions(actionId).Name    = 'GuiTutorial Batch';
obj.Sections(secIndex).Actions(actionId).Command = ...
    'obj.mibController.startController(''plugins.Tutorials.GuiTutorialBatch.GuiTutorialBatch'', [], Batch);';
actionId = actionId + 1;
```

---

## What This Tutorial Teaches (Summary)

1. **Where to put BatchOpt defaults** — STEP 1 in the constructor, before any
   conditional logic.
2. **How to handle three calling modes** — the `if nargin == 3` branch in
   the constructor.
3. **How to validate dynamic fields** — `normalizeBatchOptForCurrentDataset()`
   runs in headless mode where `updateWidgets()` never fires.
4. **How updateWidgets changes** — update BatchOpt first, then call
   `updateGUIFromBatchOpt_Shared`; never write to widgets directly.
5. **How operation methods become mode-agnostic** — by reading from BatchOpt
   instead of from widget handles they work identically in GUI and batch mode.
6. **How Calculate controls macro recording** — operations return a success
   flag; `returnBatchOpt()` is only called when the operation actually ran.
7. **How to parent dialogs and progress bars correctly** — `getDialogParent()`
   returns the right figure in both interactive and headless mode.
