# MIB2 → MIB3 AppDesigner Controller Conversion — Step-by-Step Plan

> Generic procedure for porting any `mibXxxController` + `mibXxxGUI.mlapp` pair to
> the MIB3 package/class structure. Follow each phase in order; tick boxes as you go.
> For quick lookup tables (widget syntax, event names, data structures) see
> `guide_to_appdesigner_conversion.md` in this directory.
>
> Last updated: DebrisRemoval port (2026-05).

---

## Phase 0 — Preparation

- [ ] Identify source files:
  - Controller: `C:\Matlab\MIB2\Classes\@mibXxxController\mibXxxController.m`
  - Renamed reference (may be partially converted): `C:\Matlab\MIB2_RENAMED_FOR_MIB3\Classes\@mibXxxController\`
  - View: `C:\Matlab\MIB2\GuiTools\mibXxxGUI.mlapp` (or `.fig` + `.m` for old GUIDE dialogs)
- [ ] Decide target names:
  - Class: `Xxx` (PascalCase, no `mib` prefix)
  - Controller: `mib/+controllers/@Xxx/Xxx.m`
  - View: `mib/+views/XxxGUI.mlapp`
- [ ] Create the controller directory: `mkdir mib/+controllers/@Xxx`

---

## Phase 1 — Analyse the Source

Read through the MIB2 controller and record:

1. **BatchOpt fields** — note type of each:
   - Dropdown / radio: `{value, {allowed list}}`
   - Numeric spinner: was often a bare string `'7'` → must become `{value, [min max], round}`
   - Checkbox: logical scalar
   - Text edit: char

2. **All dialog calls**: `warndlg`, `errordlg`, `questdlg`, `inputdlg`, `mibInputMultiDlg`, `waitbar`

3. **All `notify` calls** — note event names (they all need PascalCase in MIB3)

4. **All `getData`/`setData` calls** — check argument order (MIB3 swaps `setData`: data first)

5. **Any `NaN` passed as orient/col_channel** → must become `[]`

6. **Backup calls**: `mibDoBackup(type, sw, opts)` → `backup(type, sw, opts)`

7. **Global variables**: `global Font`, `global mibPath`

8. **Model property access**: `I{id}.pixSize`, `I{id}.depth/width/height` → add `.image.` prefix

9. **`updateImgInfo` / `updateActionLog`** → lives on `I{id}.image`, not on `I{id}`

10. **`getDatasetDimensions`** — check which object it is called on:
    - On `MibDataset` (`I{id}`): `[h,w,c,d,t] = I{id}.getDatasetDimensions(type, orient, opts)` — 3 input args after obj
    - On `MibImage` (`I{id}.image`): different signature — avoid calling directly

11. **Widget types** — identify which are ButtonGroups (radio sets) vs DropDowns; they use `SelectionChangedFcn` not `ValueChangedFcn`

12. **Button callbacks** — note names; MIB3 convention: `applyButton_Callback`, `closeButton_Callback`

---

## Phase 2 — Create the View (.mlapp)

- [ ] Open AppDesigner; create new app; save as `mib/+views/XxxGUI.mlapp`
- [ ] **Startup function** must accept exactly one extra argument — the controller handle:
  ```matlab
  function startupFcn(app, winController)
      app.winController = winController;
  end
  ```
- [ ] Set a **unique Tag** on every interactive widget — these become `obj.view.handles.<Tag>`
- [ ] Widget Tags should match `BatchOpt` field names exactly for auto-sync to work
- [ ] **No callback logic** in the `.mlapp` — layout only
- [ ] **No `CloseRequestFcn`** in `.mlapp` — set in controller's `addCallbacks`
- [ ] For ButtonGroups (radio sets): each radio button needs its own Tag (used in `SelectionChangedFcn` to identify selection via `event.Source.SelectedObject.Tag`)
- [ ] Standard buttons: `applyButton` / `removeAllButton`, `currentButton`, `helpButton`, `closeButton`

---

## Phase 3 — Write the Controller

### 3.1 Class skeleton

```matlab
classdef Xxx < handle
% XXX - Controller for the Xxx dialog.
    properties
        mibModel        % handle to MibModel
        view            % handle to the view (views.XxxGUI)
        mibGUI          % handle to main MIB figure
        listener        % cell array of listener handles
        BatchOpt        % structure compatible with batch processing
    end
    events
        CloseEvent
    end
    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
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

### 3.2 Constructor

```matlab
function obj = Xxx(mibModel, varargin)
    obj.mibModel = mibModel;
    obj.mibGUI   = mibModel.mibGUI;

    % --- BatchOpt defaults ---
    obj.BatchOpt.SomeDropdown    = {'Value1'};
    obj.BatchOpt.SomeDropdown{2} = {'Value1', 'Value2'};
    obj.BatchOpt.SomeSpinner     = {7, [1 Inf], 'on'};   % {default, [min max], round}
    obj.BatchOpt.SomeCheckbox    = true;
    obj.BatchOpt.id              = obj.mibModel.getActiveId();  % NOT obj.mibModel.Id

    obj.BatchOpt.mibBatchSectionName = 'Ribbon -> ...';   % NOT 'Menu -> ...'
    obj.BatchOpt.mibBatchActionName  = 'Action label';
    obj.BatchOpt.mibBatchTooltip.SomeDropdown = 'Description...';
    obj.BatchOpt.mibBatchTooltip.SomeSpinner  = 'Description...';

    % --- Batch / headless mode ---
    if nargin == 2
        BatchOptIn = varargin{1};
        if ~isstruct(BatchOptIn)
            if isnan(BatchOptIn)
                obj.returnBatchOpt();
            else
                utils.dlgs.showErrorDialog([], 'A structure as the 2nd parameter is required!', 'Error');
            end
            notify(obj, 'CloseEvent');
            return;
        end
        obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
        obj.applyButton_Callback('Remove all', true);   % pass batchModeSwitch=true
        notify(obj, 'CloseEvent');
        return;
    end

    % --- GUI mode ---
    obj.view = core.ChildView(obj, 'views.XxxGUI');
    obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');
    Font = obj.mibModel.preferences.System.Font;
    if obj.view.handles.someStableWidget.FontSize ~= Font.FontSize ...
            || ~strcmp(obj.view.handles.someStableWidget.FontName, Font.FontName)
        utils.fontSizeUpdate(obj.view.gui, Font);
    end
    obj.updateWidgets();
    utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
    obj.addCallbacks();
    obj.view.gui.Visible = 'on';

    obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
    obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
end
```

**Key constructor rules:**
- `obj.mibGUI = mibModel.mibGUI` — required for dialog parents
- `getActiveId()` not `obj.mibModel.Id` — stale in split-panel mode
- `nargin == 2` / `varargin{1}` (MIB3 batch calling convention)
- Pass `batchModeSwitch = true` to the action method to skip undo backup
- `addCallbacks()` before `Visible = 'on'`
- `utils.updateGUIFromBatchOpt_Shared` after `updateWidgets()` for initial population

### 3.3 addCallbacks

```matlab
function addCallbacks(obj)
    obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();  % always first

    % Dropdowns / spinners / checkboxes — plain sync
    obj.view.handles.SomeDropdown.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e);
    obj.view.handles.SomeSpinner.ValueChangedFcn  = @(h,e) obj.updateBatchOptFromGUI(e);

    % ButtonGroup (radio) — needs SelectionChangedFcn, not ValueChangedFcn
    obj.view.handles.ModeButtonGroup.SelectionChangedFcn = @(h,e) obj.modeSelectionChanged(e);

    % Action buttons
    obj.view.handles.applyButton.ButtonPushedFcn  = @(~,~) obj.applyButton_Callback();
    obj.view.handles.helpButton.ButtonPushedFcn   = @(~,~) obj.helpButton_Callback();
    obj.view.handles.closeButton.ButtonPushedFcn  = @(~,~) obj.closeWindow();
end
```

**ButtonGroup note:** Radio button sets use `SelectionChangedFcn`. The selected radio
button's Tag is read as `event.Source.SelectedObject.Tag`.

### 3.4 Boilerplate methods

```matlab
function closeWindow(obj)
    if isvalid(obj.view.gui); delete(obj.view.gui); end
    for i = 1:numel(obj.listener); delete(obj.listener{i}); end
    notify(obj, 'CloseEvent');
end

function updateWidgets(obj)
    obj.BatchOpt.id = obj.mibModel.getActiveId();
    utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
end

function updateBatchOptFromGUI(obj, event)
    obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
end

function returnBatchOpt(obj, BatchOptOut)
    if nargin < 2; BatchOptOut = obj.BatchOpt; end
    if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
    notify(obj.mibModel, 'SyncBatch', core.ToggleEventData(BatchOptOut));
end

function helpButton_Callback(obj)
    web(fullfile(obj.mibModel.mibPath, 'techdoc/html/...'), '-browser');
end
```

### 3.5 Conditional widget enable/disable (ButtonGroup-triggered)

When a ButtonGroup selection should enable or disable other widgets:

```matlab
function modeSelectionChanged(obj, event)
    obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
    isAutoMode = strcmp(event.Source.SelectedObject.Tag, 'AutoModeButton');
    enableState = matlab.lang.OnOffSwitchState(isAutoMode);
    obj.view.handles.DependentSpinner.Enable  = enableState;
    obj.view.handles.DependentDropdown.Enable = enableState;
end
```

`matlab.lang.OnOffSwitchState(logical)` maps `true`→`'on'`, `false`→`'off'` cleanly.

### 3.6 Action method (the core processing)

```matlab
function applyButton_Callback(obj, mode, batchModeSwitch)
    if nargin < 2; mode = 'default'; end
    if nargin < 3; batchModeSwitch = false; end

    % 1. Create progress bar FIRST (needed even for early exits)
    if obj.BatchOpt.showWaitbar
        progressBar = uiprogressdlg(obj.mibGUI, 'Value', 0, 'Cancelable', 'on', ...
            'Message', 'Please wait...', 'Title', 'Xxx');
    end

    % 2. Guard: virtual stacking mode
    if strcmp(obj.mibModel.I{obj.BatchOpt.id}.datasetType, 'Virtual')
        if obj.BatchOpt.showWaitbar; delete(progressBar); end
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        utils.dlgs.inputUniversalDlg(obj.mibGUI, '!!! Warning !!!', {''}, ...
            {'Not compatible with virtual stacking mode'}, 'Not implemented', dlgOpt);
        notify(obj.mibModel, 'StopProtocol');
        obj.closeWindow();
        return;
    end

    % 3. Backup — skip in batch mode
    getDataOptions.id = obj.BatchOpt.id;
    if ~batchModeSwitch
        obj.mibModel.backup('image', 1, getDataOptions);   % 0=current slice, 1=full stack
    end

    % 4. Get dimensions
    [~, ~, ~, depth, ~] = obj.mibModel.I{obj.BatchOpt.id}.getDatasetDimensions('image');

    % 5. Main loop with cancel check
    for z = 1:depth
        if obj.BatchOpt.showWaitbar
            if progressBar.CancelRequested; delete(progressBar); return; end
            progressBar.Value = z/depth;
            progressBar.Message = sprintf('Processing slice %d of %d', z, depth);
        end
        % ... read: cell2mat(obj.mibModel.getData2D('image', z, [], [], getDataOptions))
        % ... write: obj.mibModel.setData2D(data, 'image', z, [], [], getDataOptions)
        %                                   ^data first in MIB3!
    end
    if obj.BatchOpt.showWaitbar; delete(progressBar); end

    % 6. Notify display update
    obj.mibModel.showMask = true;        % if mask was written
    notify(obj.mibModel, 'ShowImage');

    % 7. Log and sync batch (only in non-batch mode for 'Remove all' operations)
    if ~batchModeSwitch
        obj.mibModel.I{obj.BatchOpt.id}.image.updateActionLog('...');
        obj.returnBatchOpt();
    end
end
```

---

## Phase 4 — Key Conversion Rules (Runtime-Verified)

These were discovered as runtime errors during the DebrisRemoval port:

| Pattern | MIB2 | MIB3 | Error if wrong |
|---------|------|------|----------------|
| Backup | `mibDoBackup(type, sw, opts)` | `backup(type, sw, opts)` | `Unrecognized method 'mibDoBackup'` |
| Action log | `I{id}.updateActionLog(txt)` | `I{id}.image.updateActionLog(txt)` | `Unrecognized method 'updateActionLog' for class 'core.MibDataset'` |
| Dataset dims | `I{id}.getDatasetDimensions('image', NaN, NaN, opts)` (4 args) | `I{id}.getDatasetDimensions('image', orient, opts)` (3 args) | `Too many input arguments` |
| setData order | `setData2D(type, data, z, ...)` | `setData2D(data, type, z, ...)` | silent data corruption |
| Orient/col | `getData2D(..., NaN, NaN, ...)` | `getData2D(..., [], [], ...)` | may cause index errors |
| Progress bar placement | created after early-exit checks | create BEFORE early-exit checks | `Variable might be used before defined` |
| BatchOpt id | `obj.mibModel.Id` | `obj.mibModel.getActiveId()` | stale id in split-panel |

---

## Phase 5 — Progress Bar Rules

**Simple sequential loops** (no `parfor`): use `uiprogressdlg` with `Cancelable = 'on'`:

```matlab
progressBar = uiprogressdlg(obj.mibGUI, 'Value', 0, 'Cancelable', 'on', ...
    'Message', 'Please wait...', 'Title', 'Title');
% inside loop:
if progressBar.CancelRequested; delete(progressBar); return; end
progressBar.Value = z/depth;
progressBar.Message = sprintf('Slice %d of %d', z, depth);
% after loop:
delete(progressBar);
```

**Rules:**
- Always create the bar BEFORE any early-exit guards (virtual check, etc.) so it can be deleted on early return
- Check `CancelRequested` at the TOP of each iteration, before any reads or writes
- Every `return` path after bar creation must `delete(progressBar)` first
- Use `progressBar` as the variable name (not `wb` — descriptive naming rule)

**Parallel loops** (`parfor`): use `core.PoolWaitbar` — see `guide_to_appdesigner_conversion.md` §5.

---

## Phase 6 — Dialogs

| MIB2 | MIB3 |
|------|------|
| `errordlg(msg, title)` | `utils.dlgs.showErrorDialog(obj.mibGUI, msg, title)` |
| `warndlg(msg, title)` | `utils.dlgs.inputUniversalDlg(obj.mibGUI, '!!! Warning !!!', {''}, {msg}, title, dlgOpt)` with `dlgOpt.MsgBoxOnly=true; dlgOpt.Icon='puffin_warning'` |
| `questdlg(msg,title,b1,b2,def)` | `utils.dlgs.inputQuestDlg(obj.mibGUI, msg, title, b1, b2, def)` |
| `inputdlg` / `mibInputMultiDlg` | `utils.dlgs.inputUniversalDlg(obj.mibGUI, header, prompts, defAns, title, options)` |
| `waitbar` | `uiprogressdlg` (sequential) or `core.PoolWaitbar` (parallel) |

---

## Phase 7 — Event Names (MIB2 → MIB3)

| MIB2 | MIB3 |
|------|------|
| `'plotImage'` | `'ShowImage'` |
| `'updateGuiWidgets'` / `'updateId'` | `'UpdateGuiWidgets'` |
| `'showMask'` (event) | `obj.mibModel.showMask = true` then `notify(..., 'ShowImage')` |
| `'showModel'` (event) | `obj.mibModel.showModel = true` then `notify(..., 'ShowImage')` |
| `'syncBatch'` | `'SyncBatch'` |
| `'stopProtocol'` | `'StopProtocol'` |
| `'closeEvent'` | `'CloseEvent'` |
| `'updatedAnnotations'` | `'UpdateAnnotations'` |
| `'updateLayerSlider'` | update `slices{orient}` then `notify(..., 'SliceChanged')` |
| `'updateTimeSlider'` | update `slices{5}` then `notify(..., 'FrameChanged')` |

---

## Phase 8 — Verification Checklist

After writing the controller, run through these before testing:

- [ ] `classdef Xxx < handle` — no `mib` prefix
- [ ] `property view` lowercase — never `View`
- [ ] `property mibGUI` present
- [ ] `event CloseEvent` PascalCase
- [ ] `ViewListner_Callback2` with `~isvalid(obj.view.gui)` guard
- [ ] Constructor: `obj.mibGUI = mibModel.mibGUI`
- [ ] Constructor: `getActiveId()` not `.Id`
- [ ] Constructor: `nargin == 2` batch check
- [ ] Constructor: batch call passes `batchModeSwitch = true`
- [ ] `mibBatchSectionName = 'Ribbon -> ...'` not `'Menu -> ...'`
- [ ] `mibBatchTooltip` has entry for every user-facing field
- [ ] `addCallbacks()` called before `Visible = 'on'`
- [ ] `CloseRequestFcn` set as first line of `addCallbacks`
- [ ] ButtonGroups use `SelectionChangedFcn`, spinners/dropdowns use `ValueChangedFcn`
- [ ] `backup(type, sw, opts)` not `mibDoBackup`
- [ ] `backup` call inside `if ~batchModeSwitch` guard
- [ ] `setData2D(data, type, ...)` — data first
- [ ] `getData2D` / `setData2D` use `[]` not `NaN` for orient/col_channel
- [ ] `I{id}.image.updateActionLog(...)` not `I{id}.updateActionLog(...)`
- [ ] `I{id}.image.pixSize` / `.depth` / `.width` / `.height` (not direct on dataset)
- [ ] Progress bar created BEFORE virtual mode and error checks
- [ ] Every early-return path deletes the progress bar
- [ ] `CancelRequested` checked at top of each loop iteration
- [ ] `notify(..., 'ShowImage')` not `'plotImage'`
- [ ] `obj.mibModel.showMask = true` set before `ShowImage` if mask was written
- [ ] `core.ToggleEventData` not `ToggleEventData`
- [ ] All utility calls namespaced: `utils.*`, `core.*`
- [ ] Run `mcp__matlab__check_matlab_code` — zero issues

---

## Phase 9 — Live Testing

1. Launch MIB3: `cd C:\Matlab\MIB3\mib; mib3`
2. Open a multi-slice dataset
3. Launch via Ribbon button / `startController('controllers.Xxx')`
4. Verify window opens left of main window, font matches MIB preferences
5. Test all widgets — verify `BatchOpt` stays in sync (check via breakpoint or `disp`)
6. Test the primary action on a real dataset
7. Test Cancel button during a long run
8. Test with virtual stacking mode — warning dialog expected
9. Test batch mode: `obj.mibController.startController('controllers.Xxx', [], NaN)` — must sync to batch controller without error
10. Run `buildtool check` — no new issues
