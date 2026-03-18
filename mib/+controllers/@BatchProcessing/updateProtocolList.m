function updateProtocolList(obj)
% function updateProtocolList(obj)
% refresh the protocol listbox from obj.Protocol, preserving the current selection
%
%|
% @b Examples:
% @code obj.updateProtocolList(); @endcode
%
% Updates
%

tData = cell([numel(obj.Protocol), 1]);
for rowId = 1:numel(obj.Protocol)
    tData{rowId} = sprintf('%d. %s -> %s', rowId, obj.Protocol(rowId).mibBatchSectionName, obj.Protocol(rowId).mibBatchActionName);
end
obj.view.handles.protocolList.Items = tData;
if obj.protocolListIndex > 0 && obj.protocolListIndex <= numel(tData)
    obj.view.handles.protocolList.Value = tData{obj.protocolListIndex};
end
end
