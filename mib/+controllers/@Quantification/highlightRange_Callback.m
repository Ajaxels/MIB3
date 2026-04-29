function highlightRange_Callback(obj)
% HIGHLIGHTRANGE_CALLBACK - Highlight all objects whose Value column falls within the range.
%
% Syntax:
%   function highlightRange_Callback(obj)
%
% specified in the highlight1 and highlight2 edit boxes.
%
% Reads the lower and upper range limits from the highlight1 and
% highlight2 edit fields, finds all rows in statTable whose Value
% (column 2) lies within that range, and highlights the corresponding
% objects in the selection layer.  Object IDs are taken from the table
% RowName, which encodes the canonical object index.
%
% Usage:
%   Example 1::
%
%     % wired in addCallbacks:
%
%   Example 2::
%
%     h.highlightRange.ButtonPushedFcn = @(~,~) obj.highlightRange_Callback();
%

% Updates
%

data = obj.view.handles.statTable.Data;
if isempty(data) || size(data, 1) < 1 || iscell(data(1))
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf('!!! Error !!!\n\nStats values are empty!\nPlease calculate statistics values first!\nPress the Run button'), ...
        'No data');
    return;
end

value(1) = obj.view.handles.highlight1.Value;
value(2) = obj.view.handles.highlight2.Value;
value = sort(value);

indices = find(data(:,2) >= value(1) & data(:,2) <= value(2));
if isempty(indices); return; end

rowNames   = obj.view.handles.statTable.RowName;
object_list = str2num(cell2mat(rowNames(indices))); %#ok<ST2NM>
sliceNumbers = data(indices, 3);
obj.highlightSelection(object_list, [], sliceNumbers);
end
