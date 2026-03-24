function updateMaterialsTable(obj, position)
% function updateMaterialsTable(obj, position)
% Update materials table with colors and formatting
%
% Description:
%   Updates the materials table with current model data including:
%   - Material colors as background
%   - Font colors based on selection mode
%   - Show/hide checkboxes
%   - Special rows for Mask and Exterior
%
% Parameters:
%   obj - Controller object with obj.mibModel and view
%   position - Scroll position control:
%              [] - Keep current scroll position (default)
%              number - Scroll to specific row index
%              Inf - Scroll to the end of the table
%
% Examples:
%   % Update table and keep current position
%   obj.updateMaterialsTable([]);
%
%   % Update table and scroll to row 5
%   obj.updateMaterialsTable(5);
%
%   % Update table and scroll to bottom
%   obj.updateMaterialsTable(Inf);

if nargin < 2; position = []; end

% get table handle
tableHandle = obj.handles.materialsTable;

% get or initialize UserData
userData = tableHandle.UserData;
if isempty(userData)
    userData = struct();
end

% % check if table is initialized (skip during startup)
% if ~isfield(userData, 'initialized')
%     userData.initialized = true;
%     tableHandle.UserData = userData;
%     return;  % Exit during first initialization
% end

% get dataset alias
dataset = obj.mibModel.I{obj.mibModel.id};

% Determine font color based on selection restriction
if dataset.restrictSelectionToMaterial
    fontColor = [0.78, 0.78, 0.78];  % Gray for restricted mode
else
    fontColor = [0, 0, 0];  % Black for normal mode
end

% update material names
if dataset.labels.exists == 0
    dataset.labels.materialNames = {};
end

% Determine max colors and column editability
if dataset.labels.maxMaterials < 256  % 63 and 255 type models
    maxColor = numel(dataset.labels.materialNames);
    columnEditable = [false, false, false];
else  % Other models
    maxColor = 2;
    columnEditable = [false, true, false];
end

% generate additional colors if needed
nCurrentColors = size(dataset.labels.materialColors, 1);
if maxColor > nCurrentColors
    nNewColors = maxColor - nCurrentColors;
    newColors = rand(nNewColors, 3);
    dataset.labels.materialColors(nCurrentColors+1:nCurrentColors+nNewColors, :) = newColors;
end

% Initialize table data
if dataset.labels.maxMaterials < 256
    tableData = cell(maxColor+2, 3); % add 2 rows for Mask and Exterior
    
    % Row 1: Mask
    tableData{1, 1} = '';  % Color column (will use StyleConfigurations)
    tableData{1, 2} = 'Mask';
    tableData{1, 3} = false;
    
    % Row 2: Exterior
    tableData{2, 1} = '';
    tableData{2, 2} = 'Exterior';
    tableData{2, 3} = false;
    
    % Material rows
    for matIdx = 1:maxColor
        tableData{matIdx+2, 1} = '';
        tableData{matIdx+2, 2} = dataset.labels.materialNames{matIdx};
        tableData{matIdx+2, 3} = false;
    end
else
    % Simple model with 2 materials
    tableData = cell(4, 3);
    
    tableData{1, 1} = '';
    tableData{1, 2} = 'Mask';
    tableData{1, 3} = false;
    
    tableData{2, 1} = '';
    tableData{2, 2} = 'Exterior';
    tableData{2, 3} = false;
    
    % Material 1
    tableData{3, 1} = '';
    tableData{3, 2} = dataset.labels.materialNames{1};
    tableData{3, 3} = false;
    
    % Material 2
    tableData{4, 1} = '';
    tableData{4, 2} = dataset.labels.materialNames{2};
    tableData{4, 3} = false;
end

% Update table data and editability
tableHandle.Data = tableData;
tableHandle.ColumnEditable = columnEditable;

% Clear previous styles
removeStyle(tableHandle);

% Apply styling using StyleConfigurations
numRows = size(tableData, 1);

% Style for each row with background color
for i = 1:numRows
    if i == 1  % Mask
        bgColor = obj.mibModel.preferences.Colors.MaskColor;
    elseif i == 2  % Exterior
        bgColor = [1, 1, 1];  % White
    else  % Materials
        matIdx = i - 2;
        if dataset.labels.maxMaterials < 256
            bgColor = dataset.labels.materialColors(matIdx, :);
        else
            % For simple models
            if matIdx <= numel(dataset.labels.materialNames)
                colorId = mod(str2double(dataset.labels.materialNames{matIdx}) - 1, 65535) + 1;
                bgColor = dataset.labels.materialColors(colorId, :);
            else
                bgColor = [1, 1, 1];
            end
        end
    end
    
    % Create style with background color
    rowStyle = uistyle('BackgroundColor', bgColor, 'FontColor', fontColor);
    addStyle(tableHandle, rowStyle, 'cell', [i, 1]);
end

% Store current state in UserData
userData.numRows = numRows;
userData.maxColor = maxColor;
tableHandle.UserData = userData;

% Force update
drawnow;

% Handle scrolling
if ~isempty(position)
    if isinf(position)
        % Scroll to bottom
        scroll(tableHandle, 'bottom');
    elseif position > 0 && position <= numRows
        % Scroll to specific row
        scroll(tableHandle, 'row', position);
    end
end

% Highlight selected material (column 2)
%eventData = struct();
%eventData.Indices = [dataset.selectedMaterial, 2];
obj.materialsTable_CellSelectionCallback([dataset.selectedMaterial, 2]);

% Highlight selected Add To material (column 3)
%eventData.Indices = [dataset.selectedAddToMaterial, 3];
obj.materialsTable_CellSelectionCallback([dataset.selectedAddToMaterial, 3]);

% Update selected material indices if they point beyond existing rows
% selectedMaterial/AddTo use a +2 offset: 1=Mask, 2=Exterior, 3+=materials
if dataset.selectedMaterial > maxColor + 2; dataset.selectedMaterial = 1; end
if dataset.selectedAddToMaterial > maxColor + 2; dataset.selectedAddToMaterial = 1; end

end
