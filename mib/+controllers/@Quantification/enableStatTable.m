function enableStatTable(obj)
% ENABLESTATTABLE - Enable or disable statTable depending on whether results are available.
%
% Syntax:
%   function enableStatTable(obj)
%
% for the active dataset.
%
% The table is enabled only when obj.runId(1) matches the currently active
% dataset index, i.e. results in obj.STATS are current.  Called after
% quantification_Callback completes and on dataset switches.
%
% Usage:
%   Example 1::
%
%     obj.enableStatTable();  // called after quantification_Callback
%

% Updates
%

id = obj.mibModel.getActiveId();
obj.view.handles.statTable.Enable = 'off';
if ~isempty(obj.runId)
    if obj.runId(1) == id
        obj.view.handles.statTable.Enable = 'on';
    end
end
end
