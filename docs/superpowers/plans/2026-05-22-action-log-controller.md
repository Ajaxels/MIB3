# ActionLog Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port MIB2's `mibLogListController` to MIB3 as `controllers.ActionLog`, reading from `MibImage.actionLog` and replacing the three push-buttons with a context menu on the log listbox.

**Architecture:** Single controller class in `+controllers/@ActionLog/` following the `DatasetInfo` pattern — constructor wires the view, `updateWidgets` reads `image.actionLog` directly (no pipe parsing needed), and three context-menu callbacks delegate mutations to `image.updateActionLog`. The view (`views.ActionLogGUI`) is created by the user; the controller assumes specific widget names.

**Tech Stack:** MATLAB AppDesigner, MIB3 package namespace (`+controllers`, `+core`, `+utils`), `core.ChildView`, `utils.dlgs.*`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `mib/+controllers/@ActionLog/ActionLog.m` | **Create** | Class definition, constructor, `closeWindow`, `addCallbacks`, all inline callbacks |
| `mib/+controllers/@ActionLog/updateWidgets.m` | **Create** | Read `image.actionLog`, populate `logList.Items` |
| `mib/+views/ActionLogGUI.mlapp` | **User-provided** | View with widgets: `logList`, `refreshButton`, `logPrintButton`, `clipboardButton`, `closeButton` |

---

## Task 1: Class skeleton + read-only callbacks

**Files:**
- Create: `mib/+controllers/@ActionLog/ActionLog.m`
- Create: `mib/+controllers/@ActionLog/updateWidgets.m`

### Steps

- [ ] **Create `mib/+controllers/@ActionLog/ActionLog.m`**

```matlab
classdef ActionLog < handle
% ACTIONLOG - Controller for the Action Log window.
%
% Displays and manages the action log of the active dataset.
% Log entries are stored in ``MibImage.actionLog`` — a cell array of
% timestamped strings. Insert, Modify, and Delete operations are accessed
% via a context menu on the log list.
%
% Usage:
%   .. code-block:: matlab
%
%      obj.mibController.startController('controllers.ActionLog');

    properties
        mibModel    % handle to MibModel
        view        % handle to ActionLogGUI (set by core.ChildView)
        listener    % cell array of listener handles
    end

    events
        CloseEvent  % fired when the window closes
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static guarded listener callback.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for listenerIdx = 1:numel(obj.listener)
                    delete(obj.listener{listenerIdx});
                end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        % External method declarations
        updateWidgets(obj)

        % -------------------------------------------------------------------
        function obj = ActionLog(mibModel)
            % ACTIONLOG - Construct the action log controller.
            %
            % Input Arguments:
            %   - **mibModel** — handle to :class:`models.MibModel`.

            obj.mibModel = mibModel;

            obj.view = core.ChildView(obj, 'views.ActionLogGUI');
            obj.addCallbacks();

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.closeButton.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.closeButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'right');

            obj.updateWidgets();

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));

            obj.view.gui.Visible = 'on';
        end

        % -------------------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Close the dialog and release listeners.
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for listenerIdx = 1:numel(obj.listener)
                delete(obj.listener{listenerIdx});
            end
            notify(obj, 'CloseEvent');
        end

        % -------------------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire every widget callback and build the context menu.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            obj.view.gui.KeyPressFcn     = @(~, evt) obj.keyPress_Callback(evt);

            widgetHandles = obj.view.handles;
            widgetHandles.logList.Multiselect     = 'on';
            widgetHandles.refreshButton.ButtonPushedFcn   = @(~,~) obj.updateWidgets();
            widgetHandles.logPrintButton.ButtonPushedFcn  = @(~,~) obj.logPrint_Callback();
            widgetHandles.clipboardButton.ButtonPushedFcn = @(~,~) obj.clipboard_Callback();
            widgetHandles.closeButton.ButtonPushedFcn     = @(~,~) obj.closeWindow();

            contextMenu = uicontextmenu(obj.view.gui);
            uimenu(contextMenu, 'Text', 'Insert', ...
                'MenuSelectedFcn', @(~,~) obj.insertEntry_Callback());
            uimenu(contextMenu, 'Text', 'Modify', ...
                'MenuSelectedFcn', @(~,~) obj.modifyEntry_Callback());
            uimenu(contextMenu, 'Text', 'Delete', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) obj.deleteEntry_Callback());
            widgetHandles.logList.ContextMenu = contextMenu;
        end

        % -------------------------------------------------------------------
        function keyPress_Callback(obj, eventdata)
            % KEYPRESS_CALLBACK - Forward key presses to the main MIB key handler.
            if isempty(eventdata.Character); return; end
            evtData = struct('eventdata', eventdata);
            notify(obj.mibModel, 'keyPressEvent', core.ToggleEventData(evtData));
        end

        % -------------------------------------------------------------------
        function logPrint_Callback(obj)
            % LOGPRINT_CALLBACK - Print all log entries to the MATLAB console.
            items = obj.view.handles.logList.Items;
            for entryIndex = 1:numel(items)
                disp(items{entryIndex});
            end
        end

        % -------------------------------------------------------------------
        function clipboard_Callback(obj)
            % CLIPBOARD_CALLBACK - Copy all log entries to the system clipboard.
            items = obj.view.handles.logList.Items;
            clipboard('copy', strjoin(items, newline));
        end

        % -------------------------------------------------------------------
        function insertEntry_Callback(obj)
            % INSERTENTRY_CALLBACK - Insert a new log entry after the selected position.
        end

        % -------------------------------------------------------------------
        function modifyEntry_Callback(obj)
            % MODIFYENTRY_CALLBACK - Modify the selected log entry text.
        end

        % -------------------------------------------------------------------
        function deleteEntry_Callback(obj)
            % DELETEENTRY_CALLBACK - Delete selected log entries after confirmation.
        end

    end
end
```

- [ ] **Create `mib/+controllers/@ActionLog/updateWidgets.m`**

```matlab
function updateWidgets(obj)
% UPDATEWIDGETS - Refresh the log list from the active dataset's action log.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateWidgets()
%
% Reads ``MibImage.actionLog`` from the currently active dataset and
% populates ``logList.Items``.  The current selection is preserved when
% the selected items still exist in the updated list; otherwise the
% first item is selected.

% Updates
% 22.05.2026 - created

datasetId = obj.mibModel.getActiveId();
actionLog = obj.mibModel.I{datasetId}.image.actionLog;

currentValue = obj.view.handles.logList.Value;   % cell array (Multiselect='on')
obj.view.handles.logList.Items = actionLog;

if isempty(actionLog); return; end

% Restore previous selection if items still present; fall back to first item
if ~isempty(currentValue)
    validSelections = currentValue(ismember(currentValue, actionLog));
else
    validSelections = {};
end

if ~isempty(validSelections)
    obj.view.handles.logList.Value = validSelections;
else
    obj.view.handles.logList.Value = actionLog(1);
end
end
```

- [ ] **Run static check**

```
cd C:\Matlab\MIB3
buildtool check
```

Expected: no issues reported for the two new files (warnings about empty callback bodies are acceptable).

- [ ] **Commit**

```
cd C:\Matlab\MIB3
git add mib/+controllers/@ActionLog/ActionLog.m mib/+controllers/@ActionLog/updateWidgets.m
git commit -m "feat: add ActionLog controller skeleton with updateWidgets"
```

---

## Task 2: `insertEntry_Callback`

**Files:**
- Modify: `mib/+controllers/@ActionLog/ActionLog.m` — fill in `insertEntry_Callback`

### Steps

- [ ] **Replace the empty `insertEntry_Callback` body in `ActionLog.m`**

Find this block:
```matlab
        function insertEntry_Callback(obj)
            % INSERTENTRY_CALLBACK - Insert a new log entry after the selected position.
        end
```

Replace with:
```matlab
        function insertEntry_Callback(obj)
            % INSERTENTRY_CALLBACK - Insert a new log entry after the selected position.
            %
            % Prompts for entry text, then inserts it after the last selected item.
            % If nothing is selected, the new entry is appended to the end.

            datasetId = obj.mibModel.getActiveId();
            currentItems = obj.view.handles.logList.Items;
            selectedValue = obj.view.handles.logList.Value;   % cell array

            % Determine insert position: one after last selected, or append
            if isempty(selectedValue) || isempty(currentItems)
                insertPosition = numel(currentItems) + 1;
            else
                selectedIndices = find(ismember(currentItems, selectedValue));
                if isempty(selectedIndices)
                    insertPosition = numel(currentItems) + 1;
                else
                    insertPosition = max(selectedIndices) + 1;
                end
            end

            answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                {'Entry text:'}, {'type here'}, 'Insert new log entry');
            if isempty(answer); return; end
            if isempty(strtrim(answer{1})); return; end

            obj.mibModel.I{datasetId}.image.updateActionLog(answer{1}, 'insert', insertPosition);
            obj.updateWidgets();

            % Select the newly inserted item
            updatedItems = obj.view.handles.logList.Items;
            actualPosition = min(insertPosition, numel(updatedItems));
            if actualPosition >= 1
                obj.view.handles.logList.Value = updatedItems(actualPosition);
            end
        end
```

- [ ] **Run static check**

```
cd C:\Matlab\MIB3
buildtool check
```

Expected: no new issues.

- [ ] **Commit**

```
cd C:\Matlab\MIB3
git add mib/+controllers/@ActionLog/ActionLog.m
git commit -m "feat: implement ActionLog insertEntry_Callback"
```

---

## Task 3: `modifyEntry_Callback`

**Files:**
- Modify: `mib/+controllers/@ActionLog/ActionLog.m` — fill in `modifyEntry_Callback`

### Steps

- [ ] **Replace the empty `modifyEntry_Callback` body in `ActionLog.m`**

Find:
```matlab
        function modifyEntry_Callback(obj)
            % MODIFYENTRY_CALLBACK - Modify the selected log entry text.
        end
```

Replace with:
```matlab
        function modifyEntry_Callback(obj)
            % MODIFYENTRY_CALLBACK - Modify the selected log entry text.
            %
            % Strips the ``MIB(YYMMDDHHNN): `` timestamp prefix before presenting
            % the entry text for editing.  The modified entry is saved with a new
            % timestamp via ``image.updateActionLog('modify')``.
            % Only the first selected entry is modified when multi-select is active.

            datasetId = obj.mibModel.getActiveId();
            currentItems = obj.view.handles.logList.Items;
            selectedValue = obj.view.handles.logList.Value;   % cell array

            if isempty(selectedValue) || isempty(currentItems); return; end

            % Use only the first selected entry
            firstSelected = selectedValue{1};
            selectedIndex = find(strcmp(currentItems, firstSelected), 1);
            if isempty(selectedIndex); return; end

            % Strip timestamp prefix "MIB(YYMMDDHHNN): " to expose editable text
            entryText = currentItems{selectedIndex};
            colonPosition = strfind(entryText, ':');
            if ~isempty(colonPosition)
                editableText = strtrim(entryText(colonPosition(1)+1:end));
            else
                editableText = entryText;
            end

            answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                {'Modify entry text:'}, {editableText}, 'Modify log entry');
            if isempty(answer); return; end
            if isempty(strtrim(answer{1})); return; end

            obj.mibModel.I{datasetId}.image.updateActionLog(answer{1}, 'modify', selectedIndex);
            obj.updateWidgets();
        end
```

- [ ] **Run static check**

```
cd C:\Matlab\MIB3
buildtool check
```

Expected: no new issues.

- [ ] **Commit**

```
cd C:\Matlab\MIB3
git add mib/+controllers/@ActionLog/ActionLog.m
git commit -m "feat: implement ActionLog modifyEntry_Callback"
```

---

## Task 4: `deleteEntry_Callback`

**Files:**
- Modify: `mib/+controllers/@ActionLog/ActionLog.m` — fill in `deleteEntry_Callback`

### Steps

- [ ] **Replace the empty `deleteEntry_Callback` body in `ActionLog.m`**

Find:
```matlab
        function deleteEntry_Callback(obj)
            % DELETEENTRY_CALLBACK - Delete selected log entries after confirmation.
        end
```

Replace with:
```matlab
        function deleteEntry_Callback(obj)
            % DELETEENTRY_CALLBACK - Delete selected log entries after confirmation.
            %
            % Supports multi-selection.  Entries are deleted in reverse index order
            % so that earlier indices remain stable during the loop.

            datasetId = obj.mibModel.getActiveId();
            currentItems = obj.view.handles.logList.Items;
            selectedValue = obj.view.handles.logList.Value;   % cell array

            if isempty(selectedValue) || isempty(currentItems); return; end

            % Resolve selected strings to numeric indices
            selectedIndices = zeros(1, numel(selectedValue));
            for selectionIdx = 1:numel(selectedValue)
                foundIndex = find(strcmp(currentItems, selectedValue{selectionIdx}), 1);
                if ~isempty(foundIndex)
                    selectedIndices(selectionIdx) = foundIndex;
                end
            end
            selectedIndices = unique(selectedIndices(selectedIndices > 0));
            if isempty(selectedIndices); return; end

            if numel(selectedIndices) == 1
                confirmMessage = 'You are going to delete the highlighted entry!';
            else
                confirmMessage = sprintf('You are going to delete %d highlighted entries!', ...
                    numel(selectedIndices));
            end
            button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                sprintf('%s\n\nAre you sure?', confirmMessage), ...
                'Delete entries', 'Delete', 'Cancel', 'Cancel');
            if strcmp(button, 'Cancel'); return; end

            % Delete in reverse order to preserve validity of earlier indices
            for sortedIdx = numel(selectedIndices):-1:1
                obj.mibModel.I{datasetId}.image.updateActionLog('', 'delete', ...
                    selectedIndices(sortedIdx));
            end
            obj.updateWidgets();
        end
```

- [ ] **Run static check**

```
cd C:\Matlab\MIB3
buildtool check
```

Expected: no new issues.

- [ ] **Commit**

```
cd C:\Matlab\MIB3
git add mib/+controllers/@ActionLog/ActionLog.m
git commit -m "feat: implement ActionLog deleteEntry_Callback"
```

---

## Task 5: Manual verification

**Prerequisite:** `ActionLogGUI.mlapp` exists with the widget names listed in the file map above.

### Steps

- [ ] **Launch the controller from the MATLAB console**

```matlab
cd C:\Matlab\MIB3\mib
mib3
% Once MIB is running, open a demo dataset, then in the MATLAB console:
mibController.startController('controllers.ActionLog')
```

Expected: ActionLog window opens to the right of the MIB window, showing the current dataset's action log entries.

- [ ] **Verify `updateWidgets`**

Open the demo SBEM dataset (which has pre-populated log entries). The listbox should show entries like `MIB(260104...): MIB demo dataset, Huh7 SBEM`.

- [ ] **Verify Insert**

Right-click → Insert. Type `Test entry`. Click OK.
Expected: new entry appears in the list directly after the previously selected item, selected automatically.

- [ ] **Verify Modify**

Select the new `Test entry` line. Right-click → Modify.
Expected: dialog pre-fills with `Test entry` (timestamp prefix stripped). Change to `Updated entry`. Click OK.
Expected: item updates in place with a new timestamp; dialog closes.

- [ ] **Verify Delete (single)**

Select `Updated entry`. Right-click → Delete.
Expected: confirmation dialog appears. Click Delete. Entry is removed.

- [ ] **Verify Delete (multi)**

Ctrl-click two entries. Right-click → Delete.
Expected: confirmation dialog says "2 highlighted entries". Click Delete. Both removed.

- [ ] **Verify Refresh button**

Click Refresh. Expected: list refreshes without error.

- [ ] **Verify Print button**

Click Print. Expected: all entries printed to MATLAB Command Window.

- [ ] **Verify Clipboard button**

Click Clipboard. Paste into a text editor.
Expected: all entries, one per line.

- [ ] **Verify Close button and CloseEvent**

Click Close (or X). Expected: window closes, no MATLAB errors.

- [ ] **Verify listener refresh**

With ActionLog open, switch to a different dataset (or load a new one).
Expected: log list updates automatically.

---

## Ribbon Wiring (out of scope — user action required)

The ActionLog window is launched via:

```matlab
obj.mibController.startController('controllers.ActionLog')
```

Wire this to the appropriate ribbon button callback in `+controllers/@MibRibbon/` (or whichever ribbon callback corresponds to the "Log" button in the Path panel area). No controller code changes needed — `startController` handles singleton behaviour (brings existing window to front if already open).
