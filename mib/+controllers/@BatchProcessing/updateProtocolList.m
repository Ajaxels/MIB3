function updateProtocolList(obj)
% UPDATEPROTOCOLLIST - refresh the protocol listbox from obj.Protocol, preserving the current selection.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateProtocolList()
%
% Usage:
%   Example 1::
%
%     obj.updateProtocolList();
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
