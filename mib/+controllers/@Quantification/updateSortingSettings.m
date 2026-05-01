function updateSortingSettings(obj)
% UPDATESORTINGSETTINGS - Sync sort direction and column index from the sortTable dropdown.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateSortingSettings()
%
% Reads the selected item from sortTable (e.g. 'Value, descend'),
% updates obj.sortingDirection ('ascend'/'descend') and
% obj.sortingColIndex (1=ObjId, 2=Value, 3=Slice, 4=TimePnt, 5=RowIndex),
% then immediately re-sorts the table.
%
% Usage:
%   Example 1::
%
%     % wired in addCallbacks:
%
%   Example 2::
%
%     h.sortTable.ValueChangedFcn = @(~,~) obj.updateSortingSettings();
%

% Updates
%

switch obj.view.handles.sortTable.Value
    case 'Value, ascend';    obj.sortingDirection = 'ascend';  obj.sortingColIndex = 2;
    case 'Value, descend';   obj.sortingDirection = 'descend'; obj.sortingColIndex = 2;
    case 'ObjectId, ascend'; obj.sortingDirection = 'ascend';  obj.sortingColIndex = 1;
    case 'ObjectId, descend';obj.sortingDirection = 'descend'; obj.sortingColIndex = 1;
    case 'SliceNo, ascend';  obj.sortingDirection = 'ascend';  obj.sortingColIndex = 3;
    case 'SliceNo, descend'; obj.sortingDirection = 'descend'; obj.sortingColIndex = 3;
    case 'TimePnt, ascend';  obj.sortingDirection = 'ascend';  obj.sortingColIndex = 4;
    case 'TimePnt, descend'; obj.sortingDirection = 'descend'; obj.sortingColIndex = 4;
    case 'ObjectIndex, ascend';  obj.sortingDirection = 'ascend';  obj.sortingColIndex = 5;
    case 'ObjectIndex, descend'; obj.sortingDirection = 'descend'; obj.sortingColIndex = 5;
end
obj.sortBtn_Callback();
end
