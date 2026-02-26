function materialsTable_CellSelectionCallback(obj, cellIndices)
% function materialsTable_CellSelectionCallback(obj, cellIndices)
% Handle cell selection in materials table (obj.handles.materialsTable)

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

% Get unlink state (keep it independent from restriction mode)
unlink = userData.unlink;

% Check if selection is restricted to material
isRestricted = dataset.restrictSelectionToMaterial == 1;

% Store all selected indices
userData.selectedIndices = cellIndices;
tableHandle.UserData = userData;

% Define colors
highlightColor = [0.2, 0.6, 1];
greyFontColor = [0.78, 0.78, 0.78];
blackFontColor = [0, 0, 0];

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
    
    % Apply styles based on restriction mode
    if isRestricted
        % Make ALL rows grey first
        greyStyle = uistyle('BackgroundColor', [1, 1, 1], 'FontColor', greyFontColor);
        for i = 1:numRows
            addStyle(tableHandle, greyStyle, 'cell', [i, 2]);
        end
    else
        % Normal mode - unhighlight previous only
        if prevMaterial ~= selectedMaterial
            whiteBgStyle = uistyle('BackgroundColor', [1, 1, 1], 'FontColor', blackFontColor);
            addStyle(tableHandle, whiteBgStyle, 'cell', [prevMaterial, 2]);
        end
    end
    
    % Highlight selected material in column 2 (black font, blue background)
    highlightStyle = uistyle('BackgroundColor', highlightColor, 'FontColor', blackFontColor);
    addStyle(tableHandle, highlightStyle, 'cell', [selectedMaterial, 2]);
    
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
    
    % If linked, also update selectedMaterial and highlight
    if unlink == false
        dataset.selectedMaterial = selectedAddTo;
        
        % Update selection history
        if ~ismember(selectedAddTo, dataset.lastSegmSelection)
            dataset.lastSegmSelection(1) = dataset.lastSegmSelection(2);
            dataset.lastSegmSelection(2) = selectedAddTo;
        end
        
        % Apply styles based on restriction mode
        if isRestricted
            % Make ALL rows grey first
            greyStyle = uistyle('BackgroundColor', [1, 1, 1], 'FontColor', greyFontColor);
            for i = 1:numRows
                addStyle(tableHandle, greyStyle, 'cell', [i, 2]);
            end
        else
            % Normal mode - unhighlight previous only
            if prevMaterial ~= selectedAddTo
                whiteBgStyle = uistyle('BackgroundColor', [1, 1, 1], 'FontColor', blackFontColor);
                addStyle(tableHandle, whiteBgStyle, 'cell', [prevMaterial, 2]);
            end
        end
        
        % Highlight selected row in column 2
        highlightStyle = uistyle('BackgroundColor', highlightColor, 'FontColor', blackFontColor);
        addStyle(tableHandle, highlightStyle, 'cell', [selectedAddTo, 2]);
    end
end

end
