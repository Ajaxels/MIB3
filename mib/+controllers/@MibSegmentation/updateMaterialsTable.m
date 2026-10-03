function updateMaterialsTable(obj, position)
% UPDATEMATERIALSTABLE - Update materials table rendering with colors and styling.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateMaterialsTable(position)
%
% Updates the materials table (``obj.handles.materialsTable``) with current model data.
% Applies material colors as backgrounds, sets font colors based on selection state,
% manages visibility checkboxes, and formats special rows (Mask, Exterior).
%
% Input Arguments:
%   - **position** - *(optional)* [empty | numeric | Inf] scroll position control (default: ``[]``):
%
%     - ``[]`` - keep current scroll position
%     - numeric value - scroll to specific row index
%     - ``Inf`` - scroll to end of table (last material)
%
% Output Arguments:
%   None
%
% **Example 1** - update table and keep current position:
%
%   .. code-block:: matlab
%
%      obj.updateMaterialsTable([])
%
% **Example 2** - update table and scroll to row 5:
%
%   .. code-block:: matlab
%
%      obj.updateMaterialsTable(5)
%
% **Example 3** - update table and scroll to bottom:
%
%   .. code-block:: matlab
%
%      obj.updateMaterialsTable(Inf)
%

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

% Determine font color based on selection restriction; the colors follow the
% MATLAB theme, obj.UIFigure.ThemeChangedFcn calls this function again
palette = utils.themeColors(obj.UIFigure);
if dataset.restrictSelectionToMaterial
    fontColor = palette.disabledText;  % Gray for restricted mode
else
    fontColor = palette.text;  % Normal mode
end

% update material names
if dataset.labels.exists == 0
    dataset.labels.materialNames = {};
end

% "3D objects" describes instance models only; 63/255 models have no such
% property (core.MibLabels.objects3D), so the checkbox is off and unchecked
isInstanceModel = dataset.modelExist && dataset.labels.maxMaterials > 255 && ...
    isprop(dataset.labels, 'objects3D');
obj.handles.objects3D.Enable = isInstanceModel;
obj.handles.objects3D.Value = isInstanceModel && dataset.labels.objects3D;

% Determine max colors; no column is editable in place - typing into a cell would
% start inline editing and swallow the single-key segmentation shortcuts ('a', 's', ...).
% Materials are renamed via the context menu / F2 (models.MibModel.renameMaterial),
% which for 65535+ models rewrites the material index stored in the selected slot.
if dataset.labels.maxMaterials < 256  % 63 and 255 type models
    maxColor = numel(dataset.labels.materialNames);
else  % 65535 and 4294967295 type models: only two material slots
    maxColor = 2;
end
columnEditable = [false, false, false];

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
        bgColor = palette.tableCell;  % no color, plain cell
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
                bgColor = palette.tableCell;
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
drawnow limitrate;

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

% Clamp selection indices before applying them - must happen before the
% callback that writes to materialsTable.Selection to avoid an out-of-bounds
% error (AppDesigner raises if the row index exceeds the table row count).
if dataset.selectedMaterial > numRows; dataset.selectedMaterial = 1; end
if dataset.selectedAddToMaterial > numRows; dataset.selectedAddToMaterial = 1; end

% Highlight selected material (column 2)
obj.materialsTable_CellSelectionCallback([dataset.selectedMaterial, 2]);

% Highlight selected Add To material (column 3)
obj.materialsTable_CellSelectionCallback([dataset.selectedAddToMaterial, 3]);

end
