function selectProtocolSection_Callback(obj, hObject)
% SELECTPROTOCOLSECTION_CALLBACK - handle value change in selectProtocolSection or selectProtocolAction.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.selectProtocolSection_Callback(hObject)
%
% Fires the selected action command with Batch=NaN to retrieve its default
% BatchOpt, then refreshes the selectedActionTable.
%
% Input Arguments:
%   - **hObject** — handle to the dropdown widget that triggered the callback;
%     Tag must be 'selectProtocolSection' or 'selectProtocolAction'
%
% Usage:
%   Example 1::
%
%     obj.selectProtocolSection_Callback(obj.view.handles.selectProtocolSection);
%

% disable "add to protocol"
autoAddSwitch = obj.view.handles.autoAddToProtocol.Value;
obj.view.handles.autoAddToProtocol.Value = false;

switch hObject.Tag
    case 'selectProtocolSection'
        obj.selectedSection = find(ismember(obj.view.handles.selectProtocolSection.Items, hObject.Value), 1);
        obj.selectedAction = 1;
    case 'selectProtocolAction'
        if strcmp(hObject.Value, 'Image filters')
            obj.selectedSection = find(ismember(obj.view.handles.selectProtocolSection.Items, 'Panel -> Image filters'), 1);
            obj.view.handles.selectProtocolSection.Value = obj.view.handles.selectProtocolSection.Items{obj.selectedSection};
            obj.selectedAction = 1;
        else
            obj.selectedAction = find(ismember(obj.view.handles.selectProtocolAction.Items, hObject.Value), 1);
        end
end

if isempty(obj.Sections(obj.selectedSection).Actions(obj.selectedAction).Command)
    switch obj.Sections(obj.selectedSection).Actions(obj.selectedAction).Name
        case 'STOP EXECUTION'
            Batch.Description = 'Wait for a user';
        case 'DIRECTORY LOOP STOP'
            Batch.Description = 'Place this step at the end of the directory loop';
        case 'FILE LOOP STOP'
            Batch.Description = 'Place this step at the end of the file loop';
    end
    Batch.mibBatchSectionName = 'Service steps';
    Batch.mibBatchActionName = obj.Sections(obj.selectedSection).Actions(obj.selectedAction).Name;
    obj.updateSelectedActionTable(Batch);
else
    Batch = NaN; %#ok<NASGU>    % when Parameter is NaN calling of the command returns structure with possible options
    eval(obj.Sections(obj.selectedSection).Actions(obj.selectedAction).Command);
end
obj.selectedActionTableIndex = 1;

% Refresh the action dropdown items when the section changed.
% Temporarily disconnect the ValueChangedFcn so that setting .Value
% programmatically here does NOT re-trigger this callback (which would
% cause a second unnecessary eval call and, under the old code, infinite
% re-entrant SyncBatch → updateWidgets recursion).
if strcmp(hObject.Tag, 'selectProtocolSection')
    actionItems = {obj.Sections(obj.selectedSection).Actions.Name}';
    origCb = obj.view.handles.selectProtocolAction.ValueChangedFcn;
    obj.view.handles.selectProtocolAction.ValueChangedFcn = [];
    obj.view.handles.selectProtocolAction.Items = actionItems;
    obj.view.handles.selectProtocolAction.Value  = actionItems{obj.selectedAction};
    obj.view.handles.selectProtocolAction.ValueChangedFcn = origCb;
end

obj.displaySelectedActionTableItems();
obj.view.handles.autoAddToProtocol.Value = autoAddSwitch;   % restore "add to protocol" status
end
