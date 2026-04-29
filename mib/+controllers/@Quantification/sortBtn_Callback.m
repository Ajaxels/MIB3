function data = sortBtn_Callback(obj, data)
% SORTBTN_CALLBACK - Sort the statTable data matrix according to the current sorting settings.
%
% Syntax:
%   function data = sortBtn_Callback(obj, data)
%
% Reads obj.sortingColIndex and obj.sortingDirection (set by
% updateSortingSettings) and reorders rows accordingly.  When called with
% no data argument it reads from and writes back to the table widget.
%
% Input Arguments:
%   - **data** — *(optional)* numeric matrix [N×4] with table contents
%     (cols: ObjId, Value, Slice, TimePnt); when omitted the current
%     statTable.Data is used and the result is written back to the table
%
% Output Arguments:
%   - **data** — sorted numeric matrix [N×4]
%
% Usage:
%   Example 1::
%
%     data = obj.sortBtn_Callback(data);   // sort supplied matrix
%
%   Example 2::
%
%     obj.sortBtn_Callback();              // sort and refresh table in-place
%

% Updates
%

if nargin < 2; data = obj.view.handles.statTable.Data; end
if iscell(data); return; end    % nothing to sort

if obj.sortingColIndex < 5
    [~, index] = sort(data(:, obj.sortingColIndex), obj.sortingDirection);
else
    [~, index] = sort(str2num(cell2mat(obj.view.handles.statTable.RowName)), obj.sortingDirection); %#ok<ST2NM>
end
data = data(index, :);

if nargin < 2
    obj.view.handles.statTable.Data = data;
    obj.view.handles.statTable.RowName = obj.view.handles.statTable.RowName(index);
end
end
