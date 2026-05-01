function refreshROIList(obj, previousValue)
% REFRESHROILIST - Rebuild the ROI list-box items from current hROI.Data and attempt to.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.refreshROIList(previousValue)
%
% preserve the previously selected value.
%
% Input Arguments:
%   - **obj** — controllers.MibRoi — the ROI panel controller
%   - **previousValue** — char — previously selected item in the list
%
%   Return values: none
%
% Usage:
%   Example 1::
%
%     // refresh list and keep the current selection
%     obj.refreshROIList(obj.handles.roiList.Value);
%
%   Example 2::
%
%     // refresh list and select 'All'
%     obj.refreshROIList('All');
%

% developer mode
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRoi.refreshROIList: pressed\n');
end

dataset = obj.mibModel.I{obj.mibModel.id};
hROI    = dataset.hROI;

[number, indices] = hROI.getNumberOfROI(0);
items = cell(1, number + 1);
items{1} = 'All';
for i = 1:number
    lbl = hROI.Data(indices(i)).label;
    if iscell(lbl); lbl = lbl{1}; end
    items{i+1} = lbl;
end

obj.handles.roiList.Items = items;

% try to keep the previous selection; fall back to last item or 'All'
if nargin >= 2 && ~isempty(previousValue)
    if strcmp(previousValue, 'All') && number > 0
        % after adding, select the newest ROI (last in list)
        obj.handles.roiList.Value = items{end};
    elseif ismember(previousValue, items)
        obj.handles.roiList.Value = previousValue;
    else
        obj.handles.roiList.Value = 'All';
    end
else
    obj.handles.roiList.Value = 'All';
end
end
