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

if ~iscell(actionLog) || isempty(actionLog)
    obj.view.handles.logList.Items = {};
    obj.view.handles.logList.Value = {};
    return;
end

obj.view.handles.logList.Items = actionLog;

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
