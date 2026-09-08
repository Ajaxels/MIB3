function addCallbacks(obj)
% ADDCALLBACKS - Wire all widget callbacks after the view has been created.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.addCallbacks()
%
% The .mlapp is built by hand in App Designer and carries no callbacks of its
% own; everything is attached here against ``obj.view.handles.<Tag>``, which
% ``core.ChildView`` fills from the App Designer component names. The contract
% between the two halves is therefore the component names - a renamed widget
% shows up as a missing field here rather than as a silently dead button.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)

% Updates
%

h = obj.view.handles;

obj.view.gui.CloseRequestFcn = @(~, ~) obj.closeWindow();

% WindowKeyPressFcn, not KeyPressFcn: the latter fires only while the figure
% itself has the focus, so every MIB shortcut - Ctrl+Z above all - went dead as
% soon as the user had clicked a button or a row in this window.
obj.view.gui.WindowKeyPressFcn = @(~, e) obj.figureKeyPress(e);

% object list
h.objectTable.SelectionChangedFcn = @(~, e) obj.objectTable_SelectionChanged(e);
h.jumpToIndex.ValueChangedFcn     = @(~, ~) obj.jumpToIndex_Callback();
h.updateTable.ButtonPushedFcn     = @(~, ~) obj.updateTable_Callback();
h.autoUpdateTable.ValueChangedFcn = @(~, ~) obj.autoUpdateTable_Callback();
h.detectionSettings.ButtonPushedFcn = @(~, ~) obj.askDetectionSettings();

% picking
h.pickByClick.ValueChangedFcn = @(~, ~) obj.pickMode_Callback();

h.useShortcuts.ValueChangedFcn = @(~, ~) obj.shortcutMode_Callback();

% A context menu rather than a button, so that a way of un-picking an object can
% be added without another widget in the .mlapp. Highlight the entries in the
% list first - a right-click does not select what is under it.
selectionMenu = uicontextmenu(obj.view.gui);
uimenu(selectionMenu, 'Text', 'Remove highlighted from selection', ...
    'MenuSelectedFcn', @(~, ~) obj.selectedList_ContextMenu('remove'));
uimenu(selectionMenu, 'Text', 'Clear list', ...
    'MenuSelectedFcn', @(~, ~) obj.selectedList_ContextMenu('clear'));
h.selectedList.ContextMenu = selectionMenu;

% operation settings
h.Mode3D.ValueChangedFcn      = @(~, ~) obj.mode3D_Callback();
h.ConnectMode.ValueChangedFcn = @(src, ~) obj.updateBatchOptFromGUI(src);

% operations
h.mergeButton.ButtonPushedFcn            = @(~, ~) obj.runOperation('Merge');
h.splitComponentsButton.ButtonPushedFcn  = @(~, ~) obj.runOperation('SplitComponents');
h.splitBySelectionButton.ButtonPushedFcn = @(~, ~) obj.runOperation('SplitBySelection');
h.cutAtSliceButton.ButtonPushedFcn       = @(~, ~) obj.runOperation('CutAtSlice');
h.connectButton.ButtonPushedFcn          = @(~, ~) obj.runOperation('Connect');
h.deleteButton.ButtonPushedFcn           = @(~, ~) obj.runOperation('Delete');
h.cleanupButton.ButtonPushedFcn          = @(~, ~) obj.runOperation('Cleanup');
h.compactButton.ButtonPushedFcn          = @(~, ~) obj.runOperation('Compact');

% The same dialog the Cleanup button opens, without the cleanup that follows it,
% so the thresholds can be set and looked at while deciding.
h.cleanupOptions.ButtonPushedFcn = @(~, ~) obj.askCleanupSettings(false);

% housekeeping
h.rebuildButton.ButtonPushedFcn = @(~, ~) obj.rebuildIndex();
h.helpButton.ButtonPushedFcn    = @(~, ~) obj.helpButton_Callback();
h.closeButton.ButtonPushedFcn   = @(~, ~) obj.closeWindow();
end
