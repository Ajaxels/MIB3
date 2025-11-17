function selectionPanelLutTable_CellEditCallback(obj, hWidget, hData, keyModifier)
% function selectionPanelLutTable_CellEditCallback(obj, hWidget, hData, keyModifier)
% callbacks for cell edit in the LUT table (obj.view.handles.panels.selection.handles.lutTable) of the Selection and Image View panel
%
% Parameters:
% hWidget: handle to the pressed widget (lutTable)
% hData: CellEditData object with properties:
%   .Indices: [row, col] - indices of edited cell
%   .PreviousData - old value before edit
%   .NewData - new value after edit
%   .Source - handle to the table
%   .EventName - 'CellEdit'
% keyModifier: a pressed key modifier, [], 'control', 'shift'

if nargin < 4; keyModifier = []; end

if isempty(hData.Indices); return; end

data = hWidget.Data;
rowIdx = hData.Indices(1);
colIdx = hData.Indices(2);

% Only handle edits for the selection
if colIdx == 2
    % Validate that at least one is selected
    selected = find(cell2mat(data(:,2))==1)';
    if isempty(selected)
        % Revert to previous if none selected
        data{rowIdx, 2} = hData.PreviousData;
        hWidget.Data = data;
        return;
    end

    if isequal(keyModifier, 'control')  % Toggle using Ctrl
        data(:,2) = num2cell(zeros(size(data,1),1)); % clear all
        data{rowIdx,2} = 1;
        hWidget.Data = data;
    end

    % Now update model and GUI as before:
    obj.mibModel.I{obj.mibModel.id}.slices{4} = find(cell2mat(data(:,2))==1)';
    if isscalar(obj.mibModel.I{obj.mibModel.id}.slices{4})
        obj.view.handles.panels.selection.handles.colChannel.Value = sprintf('Ch %d', obj.mibModel.I{obj.mibModel.id}.slices{4});
        obj.mibModel.I{obj.mibModel.id}.selectedColorChannel = obj.mibModel.I{obj.mibModel.id}.slices{4};
    end

    obj.selectionLutTableUpdate_fromModel();
    notify(obj.mibModel, 'RenderImage');
end

end