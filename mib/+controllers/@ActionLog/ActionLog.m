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
            uimenu(contextMenu, 'Text', 'Insert', 'MenuSelectedFcn', @(~,~) obj.insertEntry_Callback());
            uimenu(contextMenu, 'Text', 'Modify', 'MenuSelectedFcn', @(~,~) obj.modifyEntry_Callback());
            uimenu(contextMenu, 'Text', 'Move Up', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) obj.moveEntryUp_Callback());
            uimenu(contextMenu, 'Text', 'Move Down', 'MenuSelectedFcn', @(~,~) obj.moveEntryDown_Callback());
            uimenu(contextMenu, 'Text', 'Delete', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) obj.deleteEntry_Callback());
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

            dlgOpt.Focus = 1;
            answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                {'Entry text:'}, {'type here'}, 'Insert new log entry', dlgOpt);
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

        % -------------------------------------------------------------------
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
            editableText = regexprep(entryText, '^MIB\(\d{10}\):\s*', '');
            if isempty(editableText)
                editableText = entryText;
            end

            dlgOpt.Focus = 1;
            answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                {'Modify entry text:'}, {editableText}, 'Modify log entry', dlgOpt);
            if isempty(answer); return; end
            if isempty(strtrim(answer{1})); return; end

            obj.mibModel.I{datasetId}.image.updateActionLog(answer{1}, 'modify', selectedIndex);
            obj.updateWidgets();
        end

        % -------------------------------------------------------------------
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

            if isscalar(selectedIndices)
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

        % -------------------------------------------------------------------
        function moveEntryUp_Callback(obj)
            % MOVEENTRYUP_CALLBACK - Move the selected log entry one position up.
            %
            % Swaps the entry with its predecessor in ``image.actionLog``.
            % Entry timestamps are preserved unchanged.
            % Only the first selected entry is moved when multi-select is active.

            datasetId = obj.mibModel.getActiveId();
            currentItems = obj.view.handles.logList.Items;
            selectedValue = obj.view.handles.logList.Value;   % cell array

            if isempty(selectedValue) || isempty(currentItems); return; end

            selectedIndex = find(strcmp(currentItems, selectedValue{1}), 1);
            if isempty(selectedIndex) || selectedIndex <= 1; return; end

            actionLog = obj.mibModel.I{datasetId}.image.actionLog;
            actionLog([selectedIndex-1, selectedIndex]) = actionLog([selectedIndex, selectedIndex-1]);
            obj.mibModel.I{datasetId}.image.actionLog = actionLog;

            obj.updateWidgets();
            updatedItems = obj.view.handles.logList.Items;
            obj.view.handles.logList.Value = updatedItems(selectedIndex-1);
        end

        % -------------------------------------------------------------------
        function moveEntryDown_Callback(obj)
            % MOVEENTRYDOWN_CALLBACK - Move the selected log entry one position down.
            %
            % Swaps the entry with its successor in ``image.actionLog``.
            % Entry timestamps are preserved unchanged.
            % Only the first selected entry is moved when multi-select is active.

            datasetId = obj.mibModel.getActiveId();
            currentItems = obj.view.handles.logList.Items;
            selectedValue = obj.view.handles.logList.Value;   % cell array

            if isempty(selectedValue) || isempty(currentItems); return; end

            selectedIndex = find(strcmp(currentItems, selectedValue{1}), 1);
            if isempty(selectedIndex) || selectedIndex >= numel(currentItems); return; end

            actionLog = obj.mibModel.I{datasetId}.image.actionLog;
            actionLog([selectedIndex, selectedIndex+1]) = actionLog([selectedIndex+1, selectedIndex]);
            obj.mibModel.I{datasetId}.image.actionLog = actionLog;

            obj.updateWidgets();
            updatedItems = obj.view.handles.logList.Items;
            obj.view.handles.logList.Value = updatedItems(selectedIndex+1);
        end

    end
end
