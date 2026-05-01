function lutTable_CellEditCallback(obj, hWidget, hData, keyModifier)
% LUTTABLE_CELLEDITCALLBACK - callbacks for cell edit in the LUT table (obj.handles.lutTable) of the Selection and Image View panel.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.lutTable_CellEditCallback(hWidget, hData, keyModifier)
%
% Input Arguments:
%   - **hWidget** — [uitable] handle to the LUT table widget
%   - **hData** — [CellEditData] edit event data with properties:
%
%     - ``.Indices`` — [1×2 numeric] ``[row, col]`` indices of edited cell
%     - ``.PreviousData`` — old value before edit
%     - ``.NewData`` — new value after edit
%     - ``.Source`` — [uitable] handle to the table
%     - ``.EventName`` — ``'CellEdit'`` event name
%
%   - **keyModifier** — [char|empty] pressed modifier key: ``[]``, ``'control'``, or ``'shift'`` (default: read from Figure.CurrentModifier)
%

if nargin < 4
    keyModifier = obj.view.handles.panels.selectionPanel.Figure.CurrentModifier; 
    if ~isempty(keyModifier); keyModifier = keyModifier{1}; end
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSelection.lutTable_CellEditCallback\n');
end

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
        obj.handles.colChannel.Value = sprintf('Ch %d', obj.mibModel.I{obj.mibModel.id}.slices{4});
        obj.mibModel.I{obj.mibModel.id}.selectedColorChannel = obj.mibModel.I{obj.mibModel.id}.slices{4};
    end

    obj.lutTable_update_fromModel();
    notify(obj.mibModel, 'ShowImage');
end

end
