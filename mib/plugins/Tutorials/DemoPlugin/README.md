# DemoPlugin — BatchOpt Tutorial Plugin

A tutorial MIB3 plugin that demonstrates the **BatchOpt parameter system**
and how to make a plugin compatible with the MIB macro recorder / batch
processor.

See `DemoPlugin.m` for the fully-commented controller source.  
See `instruction.md` (one level up) for the general plugin architecture guide.  
See `conversion_MIB2_to_MIB3_cheat_sheet.md` (one level up) for MIB2 → MIB3 API changes.

---

## What this plugin demonstrates

| # | Concept | Where in code |
|---|---------|---------------|
| 1 | Defining a `BatchOpt` structure | Constructor, "STEP 1" block |
| 2 | Syncing GUI ↔ BatchOpt automatically | `updateWidgets`, `updateBatchOptFromGUI` |
| 3 | Three calling modes (interactive / headless / query) | Constructor, "STEP 3" block |
| 4 | Cancellable progress with `core.PoolWaitbar` | `Calculate`, step 2 |
| 5 | Virtual-stack guard | `Calculate`, step 3 |
| 6 | Registering with the macro recorder | `Calculate`, step 7 / `returnBatchOpt` |

---

## Files

| File | Purpose |
|------|---------|
| `DemoPlugin.m` | Controller — all logic lives here |
| `DemoPluginGUI.mlapp` | AppDesigner view — widgets only, no logic |
| `README.md` | This file |

---

## The BatchOpt structure

`BatchOpt` is the single source of truth for all plugin parameters.
Every field corresponds to one GUI widget (matched by **Tag**):

```matlab
% Text edit box   (uieditfield,  Tag = 'Parameter')
obj.BatchOpt.Parameter = 'my parameter';

% Checkbox        (uicheckbox,   Tag = 'Checkbox')
obj.BatchOpt.Checkbox = true;

% Dropdown        (uidropdown,   Tag = 'Dropdown')
%   {1} = selected item string
%   {2} = cell array of all available options  ← populates the widget
obj.BatchOpt.Dropdown{1} = 'Option 3';
obj.BatchOpt.Dropdown{2} = {'Option 1', 'Option 2', 'Option 3'};

% Radio group     (uibuttongroup, Tag = 'RadioButtonGroup')
%   {1} = Tag of the currently selected radio button
%   {2} = Tags of all radio buttons (documentation only)
obj.BatchOpt.RadioButtonGroup{1} = 'Radio2';
obj.BatchOpt.RadioButtonGroup{2} = {'Radio1', 'Radio2', 'Radio3'};

% Numeric spinner (uispinner,    Tag = 'ParameterNumeric')
%   {1} = current value
%   {2} = [min  max] limits
%   {3} = 'on' (round to integer) | 'off' (allow fractions)
obj.BatchOpt.ParameterNumeric{1} = 512.125;
obj.BatchOpt.ParameterNumeric{2} = [0, 1024];
obj.BatchOpt.ParameterNumeric{3} = 'off';

% Show progress   (uicheckbox,   Tag = 'showWaitbar')
obj.BatchOpt.showWaitbar = true;
```

**Critical rule:** the field name must match the widget Tag **exactly**
(case-sensitive).  A mismatch causes the shared utilities to silently skip
the widget — no error is raised.

### Special fields (not widgets)

| Field | Purpose |
|-------|---------|
| `id` | Active dataset index — updated at runtime, stripped before recording |
| `mibBatchSectionName` | Category label in the batch action menu |
| `mibBatchActionName` | Action label in the batch action menu |
| `mibBatchTooltip.*` | Per-field help strings shown in the batch GUI |

---

## Three calling modes

### Mode 1 — Interactive GUI

```matlab
utils.startController(parentObj, 'DemoPlugin');
% equivalent to: DemoPlugin(parentObj.mibModel)
```

The constructor opens `DemoPluginGUI`, wires callbacks, and waits for
user interaction.

### Mode 2 — Headless / batch

```matlab
BatchOpt.Parameter = 'hello';
BatchOpt.Checkbox  = false;
DemoPlugin(mibModel, parentObj, BatchOpt);
```

A `BatchOpt` struct is supplied as the third argument.
`utils.updateBatchOptCombineFields_Shared` merges it onto the defaults
(supplied fields override defaults; absent fields keep defaults).
`Calculate()` runs immediately; no GUI is opened.

This is how the MIB macro recorder **replays** a previously recorded
operation.

### Mode 3 — Query (parameter discovery)

```matlab
DemoPlugin(mibModel, parentObj, NaN);
```

`NaN` signals "return available parameters without running".
`returnBatchOpt()` fires `SyncBatch` so the batch controller can
display/edit the parameters without executing the plugin.

---

## Auto-sync utilities

Two shared functions handle GUI ↔ BatchOpt synchronisation automatically.
You should **never** need to write widget-specific read/write code for
standard widget types.

### `utils.updateGUIFromBatchOpt_Shared(view, BatchOpt)` — BatchOpt → GUI

Called in `updateWidgets()` to push values into all widgets.  
The function matches each `BatchOpt` field to a widget with the same Tag
and assigns the value using the appropriate widget property.

```matlab
% In updateWidgets():
obj.view = utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
```

### `utils.updateBatchOptFromGUI_Shared(BatchOpt, hObject)` — widget → BatchOpt

Called from `updateBatchOptFromGUI(obj, event)` whenever a widget changes.  
Wire **every** interactive widget's `ValueChangedFcn` in the `.mlapp` like this:

```matlab
% In DemoPluginGUI.mlapp — ValueChangedFcn for any widget:
function Parameter_ValueChanged(app, event)
    app.winController.updateBatchOptFromGUI(event);
end

function Checkbox_ValueChanged(app, event)
    app.winController.updateBatchOptFromGUI(event);
end
% ... same pattern for all other widgets ...
```

### `utils.updateBatchOptCombineFields_Shared(defaults, input)` — merge

Called in the batch branch of the constructor to merge a partial input
BatchOpt onto the full defaults.  Supplied fields override defaults;
absent fields keep their default values.

---

## AppDesigner view requirements (`DemoPluginGUI.mlapp`)

The `.mlapp` file must satisfy these contracts:

1. **`startupFcn(app, controller)`** — store the controller reference:
   ```matlab
   function startupFcn(app, controller)
       app.winController = controller;
   end
   ```
   (`winController` is a public property of type `handle`)

2. **Widget Tags** must exactly match the `BatchOpt` field names:
   `Parameter`, `Checkbox`, `Dropdown`, `RadioButtonGroup`,
   `ParameterNumeric`, `showWaitbar`, `TextArea`

3. **`ValueChangedFcn`** for every interactive widget calls
   `app.winController.updateBatchOptFromGUI(event)`.

4. **Calculate button callback** calls:
   ```matlab
   app.winController.Calculate();
   ```

5. **Close button callback** calls:
   ```matlab
   app.winController.closeWindow();
   ```

6. **Radio button group** (`uibuttongroup`) Tag = `RadioButtonGroup`;  
   individual radio button Tags = `Radio1`, `Radio2`, `Radio3`.

---

## Progress dialog

`core.PoolWaitbar` creates a `uiprogressdlg` that is safe inside `parfor`
loops.  Constructor signature:

```matlab
progressBar = core.PoolWaitbar(N, message, parentFig, title, cancelable);
```

| Argument | Description |
|----------|-------------|
| `N` | Total number of steps |
| `message` | Initial dialog text |
| `parentFig` | `matlab.ui.Figure` parent (required in MIB3) |
| `title` | Dialog title bar text |
| `cancelable` | `true` to add a Cancel button |

```matlab
% Update message
progressBar.updateText('Phase 2...');

% Advance the bar by one step
progressBar.increment();

% Poll for cancel (between parfor batches, NOT inside parfor)
if progressBar.getCancelState(); break; end

% Close when done
progressBar.deletePoolWaitbar();
```

---

## Batch registration

Add these fields to `BatchOpt` in the constructor to make the plugin
discoverable by the MIB batch controller:

```matlab
obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Plugins';  % menu category
obj.BatchOpt.mibBatchActionName  = 'Demo Plugin';         % action label

% Per-field tooltips (sub-field name = field name):
obj.BatchOpt.mibBatchTooltip.Parameter = 'Describe what Parameter does';
obj.BatchOpt.mibBatchTooltip.Checkbox  = 'Describe what Checkbox does';
% ... one entry per BatchOpt field ...
```

At the end of `Calculate()`, call `returnBatchOpt()` to send the
current parameters to the macro recorder:

```matlab
% Must be the LAST call in Calculate():
obj.returnBatchOpt();
```

---

## Creating a new BatchOpt-compatible plugin

1. Copy the `DemoPlugin/` folder and rename everything:
   - folder: `MyPlugin/`
   - `DemoPlugin.m` → `MyPlugin.m`, class name: `MyPlugin`
   - `DemoPluginGUI.mlapp` → `MyPluginGUI.mlapp`

2. Update `BatchOpt` fields to match your widget names and data types.

3. Update `mibBatchSectionName`, `mibBatchActionName`, and
   `mibBatchTooltip` fields.

4. Replace the body of `Calculate()` with your processing logic.

5. Add the plugin folder to `mib/MIB3.prj` or rely on `addRibbonPlugins.m`
   to add it to the path at runtime.

6. Add an entry to `mib/plugins/Tutorials/GuiTutorial/instruction.md`
   (the plugin registry table) if desired.
