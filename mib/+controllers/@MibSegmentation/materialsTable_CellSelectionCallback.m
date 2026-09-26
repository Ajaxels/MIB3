function materialsTable_CellSelectionCallback(obj, cellIndices)
% MATERIALSTABLE_CELLSELECTIONCALLBACK - Handle cell selection in materials table (obj.handles.materialsTable).
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.materialsTable_CellSelectionCallback(cellIndices)
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.materialsTable_CellSelectionCallback cell in the materialsTable (obj.mibController.cSegmentation.handles.materialsTable) was selected\n');
end

% Get aliases
tableHandle = obj.handles.materialsTable;
userData = tableHandle.UserData;
dataset = obj.mibModel.I{obj.mibModel.id};

if nargin < 2
    cellIndices = tableHandle.Selection; 
else
    obj.handles.materialsTable.Selection = cellIndices;
end
if isempty(cellIndices); return; end

% handle Ctrl+A press
if size(cellIndices, 1) > 1 && cellIndices(1, 1) == 1
    obj.updateMaterialsTable([]);
    return;
end

% get first selected cell
Indices = cellIndices(1, :);

% Previous selections
prevMaterial = dataset.selectedMaterial;
prevAddTo = dataset.selectedAddToMaterial;

% Get unlink state from the dataset property
unlink = dataset.unlinkMaterials;

% Check if selection is restricted to material
isRestricted = dataset.restrictSelectionToMaterial == 1;

% Store all selected indices
userData.selectedIndices = cellIndices;
tableHandle.UserData = userData;

% Define cell styles; the colors follow the MATLAB theme (utils.themeColors),
% grey text only when selection is restricted to material
palette = utils.themeColors(obj.UIFigure);
if isRestricted
    resetStyle = uistyle('BackgroundColor', palette.tableCell, 'FontColor', palette.disabledText);
else
    resetStyle = uistyle('BackgroundColor', palette.tableCell, 'FontColor', palette.text);
end
highlightStyle = uistyle('BackgroundColor', palette.tableHighlight, 'FontColor', palette.text);

% Get total number of rows
numRows = size(tableHandle.Data, 1);
currentData = tableHandle.Data;

% Handle Material column (column 2)
if Indices(2) == 2
    selectedMaterial = Indices(1);
    dataset.selectedMaterial = selectedMaterial;
    
    % Update selection history
    if ~ismember(selectedMaterial, dataset.lastSegmSelection)
        dataset.lastSegmSelection(1) = dataset.lastSegmSelection(2);
        dataset.lastSegmSelection(2) = selectedMaterial;
    end
    
    % Update Add To material and checkbox if linked
    if unlink == false
        dataset.selectedAddToMaterial = selectedMaterial;
        
        % Uncheck all checkboxes, then check the selected row
        for i = 1:numRows
            currentData{i, 3} = false;
        end
        currentData{selectedMaterial, 3} = true;
        tableHandle.Data = currentData;
    end
    
    % Clear all column 2 highlights, then apply the new one
    for i = 1:numRows
        addStyle(tableHandle, resetStyle, 'cell', [i, 2]);
    end

    % Highlight selected material in column 2
    addStyle(tableHandle, highlightStyle, 'cell', [selectedMaterial, 2]);

    % Style column 3 (Add To) based on restriction mode
    for i = 1:numRows
        addStyle(tableHandle, resetStyle, 'cell', [i, 3]);
    end
    % Highlight the active Add To row in column 3
    if unlink
        addStyle(tableHandle, highlightStyle, 'cell', [dataset.selectedAddToMaterial, 3]);
    end
    
    % Update plot if showAllMaterials is off
    if dataset.showAllMaterials == 0 && selectedMaterial > 2
        notify(obj.mibModel, 'ShowImage');
    end
    
% Handle Add To column (column 3)
elseif Indices(2) == 3
    selectedAddTo = Indices(1);
    dataset.selectedAddToMaterial = selectedAddTo;
    
    % Always uncheck all checkboxes first, then check the selected row
    for i = 1:numRows
        currentData{i, 3} = false;
    end
    currentData{selectedAddTo, 3} = true;
    tableHandle.Data = currentData;
    
    % Style column 3 based on restriction mode
    for i = 1:numRows
        addStyle(tableHandle, resetStyle, 'cell', [i, 3]);
    end
    % Highlight the selected Add To row when unlinked
    if unlink
        addStyle(tableHandle, highlightStyle, 'cell', [selectedAddTo, 3]);
    end
    
    % If linked, also update selectedMaterial and highlight
    if unlink == false
        dataset.selectedMaterial = selectedAddTo;
        
        % Update selection history
        if ~ismember(selectedAddTo, dataset.lastSegmSelection)
            dataset.lastSegmSelection(1) = dataset.lastSegmSelection(2);
            dataset.lastSegmSelection(2) = selectedAddTo;
        end
        
        % Clear all column 2 highlights, then apply the new one
        for i = 1:numRows
            addStyle(tableHandle, resetStyle, 'cell', [i, 2]);
        end

        % Highlight selected row in column 2
        addStyle(tableHandle, highlightStyle, 'cell', [selectedAddTo, 2]);
    end

% Handle Color column (column 1) - select a new color for material
elseif Indices(2) == 1
    if Indices(1) == 1    % Mask
        c = uisetcolor(obj.mibModel.preferences.Colors.MaskColor, 'Set color for Mask');
        if isscalar(c); return; end
        obj.mibModel.preferences.Colors.MaskColor = c;
    elseif Indices(1) > 2  % Materials (rows 3+)
        figTitle = ['Set color for ' dataset.labels.materialNames{Indices(1)-2}];
        c = uisetcolor(dataset.labels.materialColors(Indices(1)-2, :), figTitle);
        if isscalar(c); return; end
        if dataset.labels.maxMaterials < 256
            colIndex = Indices(1) - 2;
        else
            colIndex = str2double(dataset.labels.materialNames{Indices(1)-2});
            colIndex = mod(colIndex - 1, 65535) + 1;
        end
        dataset.labels.materialColors(colIndex, :) = c;
    else
        return;  % Exterior (row 2) - no color change
    end
    obj.updateMaterialsTable([]);
    notify(obj.mibModel, 'ShowImage');
end

% With preferences.Colors.CursorMaterialColor on, the brush cursor is drawn in
% the color of the selected material, but it is repainted on mouse motion only.
% Refresh it here so the color follows a selection made from the table or from
% the "Toggle between the selected material and exterior" ("e") shortcut, which
% both leave the mouse standing still over the image.
obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.updateBrushCursor();

end
