function protocolList_SelectionCallback(obj)
% PROTOCOLLIST_SELECTIONCALLBACK - handle row selection in the protocol listbox - loads parameters into the action table.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.protocolList_SelectionCallback()
%
% Reads the current listbox selection, updates obj.protocolListIndex, and
% populates selectedActionTable with the step's BatchOpt fields.
%
% Usage:
%   Example 1::
%
%     obj.protocolList_SelectionCallback();
%

% sync protocolListIndex from the listbox selection
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.BatchProcessing.protocolList_SelectionCallback: triggered\n');
end
items = obj.view.handles.protocolList.Items;
selVal = obj.view.handles.protocolList.Value;
if isempty(items) || isempty(selVal)
    obj.protocolListIndex = 0;
    return;
end
obj.protocolListIndex = find(strcmp(items, selVal), 1);
if isempty(obj.protocolListIndex); obj.protocolListIndex = 0; end

if obj.protocolListIndex == 0; return; end

if ~obj.view.handles.showParametersOnClick.Value; return; end

BatchOpt = obj.Protocol(obj.protocolListIndex).Batch;
BatchOpt.mibBatchSectionName = obj.Protocol(obj.protocolListIndex).mibBatchSectionName;
BatchOpt.mibBatchActionName = obj.Protocol(obj.protocolListIndex).mibBatchActionName;
obj.updateSelectedActionTable(BatchOpt);

obj.selectedActionTableIndex = 1;
obj.displaySelectedActionTableItems();
end
