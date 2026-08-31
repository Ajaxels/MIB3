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
obj.view.gui.KeyPressFcn = @(~, e) obj.figureKeyPress(e);

% object list
%
% The three list widgets go through objectList_Callback rather than straight to
% updateObjectTable: the table is repainted from a dozen places internally, and a
% DeveloperMode marker on it would report a user action every time. The dedicated
% callback is the only one a widget can fire, so its marker means what it says.
h.objectTable.SelectionChangedFcn = @(~, e) obj.objectTable_SelectionChanged(e);
h.MaxRows.ValueChangedFcn         = @(src, ~) obj.objectList_Callback(src);
h.filterMaxVoxels.ValueChangedFcn = @(src, ~) obj.objectList_Callback(src);
h.filterMaxSlices.ValueChangedFcn = @(src, ~) obj.objectList_Callback(src);
h.jumpToIndex.ValueChangedFcn     = @(~, ~) obj.jumpToIndex_Callback();
h.updateTable.ButtonPushedFcn     = @(~, ~) obj.updateTable_Callback();
h.autoUpdateTable.ValueChangedFcn = @(~, ~) obj.autoUpdateTable_Callback();

% picking
h.pickByClick.ValueChangedFcn = @(~, ~) obj.pickMode_Callback();

% A context menu rather than a button, so that a way of un-picking an object can
% be added without another widget in the .mlapp. Highlight the entries in the
% list first - a right-click does not select what is under it.
selectionMenu = uicontextmenu(obj.view.gui);
uimenu(selectionMenu, 'Text', 'Remove highlighted from selection', ...
    'MenuSelectedFcn', @(~, ~) obj.selectedList_ContextMenu('remove'));
uimenu(selectionMenu, 'Text', 'Clear the selection', ...
    'MenuSelectedFcn', @(~, ~) obj.selectedList_ContextMenu('clear'));
h.selectedList.ContextMenu = selectionMenu;

% operation settings
h.Mode3D.ValueChangedFcn       = @(~, ~) obj.mode3D_Callback();
h.Connectivity.ValueChangedFcn = @(src, ~) obj.updateBatchOptFromGUI(src);
h.ConnectMode.ValueChangedFcn  = @(src, ~) obj.updateBatchOptFromGUI(src);
for spinner = {'MinObjectVoxels', 'MinObjectSlices', 'AbsorbFragmentVoxels'}
    h.(spinner{1}).ValueChangedFcn = @(src, ~) obj.updateBatchOptFromGUI(src);
end

% operations
h.mergeButton.ButtonPushedFcn            = @(~, ~) obj.runOperation('Merge');
h.splitComponentsButton.ButtonPushedFcn  = @(~, ~) obj.runOperation('SplitComponents');
h.splitBySelectionButton.ButtonPushedFcn = @(~, ~) obj.runOperation('SplitBySelection');
h.cutAtSliceButton.ButtonPushedFcn       = @(~, ~) obj.runOperation('CutAtSlice');
h.connectButton.ButtonPushedFcn          = @(~, ~) obj.runOperation('Connect');
h.deleteButton.ButtonPushedFcn           = @(~, ~) obj.runOperation('Delete');
h.cleanupButton.ButtonPushedFcn          = @(~, ~) obj.runOperation('Cleanup');
h.compactButton.ButtonPushedFcn          = @(~, ~) obj.runOperation('Compact');

% housekeeping
h.rebuildButton.ButtonPushedFcn = @(~, ~) obj.rebuildIndex();
h.helpButton.ButtonPushedFcn    = @(~, ~) obj.helpButton_Callback();
h.closeButton.ButtonPushedFcn   = @(~, ~) obj.closeWindow();
end
