function data = sortBtn_Callback(obj, data)
% SORTBTN_CALLBACK - Sort the statTable data matrix according to the current sorting settings.
%
% Syntax:
%   .. code-block:: matlab
%
%       data = obj.sortBtn_Callback()
%       data = obj.sortBtn_Callback(data)
%
% Reads obj.sortingColIndex and obj.sortingDirection (set by
% updateSortingSettings) and reorders rows accordingly.  When called with
% no data argument it reads from and writes back to the table widget.
%
% Input Arguments:
%   - **data** - *(optional)* numeric matrix [N×4] with table contents
%     (cols: ObjId, Value, Slice, TimePnt); when omitted the current
%     statTable.Data is used and the result is written back to the table
%
% Output Arguments:
%   - **data** - sorted numeric matrix [N×4]
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

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Quantification.sortBtn_Callback: triggered\n');
end
if nargin < 2; data = obj.view.handles.statTable.Data; end
if iscell(data) || isempty(data); return; end    % nothing to sort, i.e. the material has no objects

if obj.sortingColIndex < 5
    [~, index] = sort(data(:, obj.sortingColIndex), obj.sortingDirection);
else
    rowNames = obj.view.handles.statTable.RowName;
    if isempty(rowNames); return; end   % the table was never populated with object indices
    objectIndices = str2double(cellstr(rowNames));
    if numel(objectIndices) ~= size(data, 1) || any(isnan(objectIndices))
        return;     % row names do not encode object indices, e.g. the default 'numbered'
    end
    [~, index] = sort(objectIndices, obj.sortingDirection);
end
data = data(index, :);

if nargin < 2
    obj.view.handles.statTable.Data = data;
    rowNames = obj.view.handles.statTable.RowName;
    if iscell(rowNames) && numel(rowNames) == numel(index)
        obj.view.handles.statTable.RowName = rowNames(index);
    end
end
end
