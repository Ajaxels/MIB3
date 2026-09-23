function findMaterialUnderCursor(obj)
% FINDMATERIALUNDERCURSOR - select the material located under the mouse cursor.
%
% Callback for the 'Find material under cursor' keyboard shortcut (default
% ``Ctrl + F``). Reads the cursor position from the status-bar pixel label,
% looks up the model material at that point and selects it in the
% segmentation materials table. Converted from MIB2
% ``@mibController/mibFindMaterialUnderCursor.m``.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.findMaterialUnderCursor()
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%

% Updates
%

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};

% cancel when model is not present
if dataset.modelExist == 0; return; end

% cancel when the cursor is not above the image
% cImageDoc is indexed by the set index, not by the dataset id
cImageDoc = obj.cImageDoc{obj.mibModel.Sets.selectedSet};
if isnan(cImageDoc.isInsideImage) || ~cImageDoc.isInsideImage; return; end

% cursor coordinates from the status-bar pixel label ("x:y (...)")
xyString = obj.cStatus.handles.pixelLabel.Text;
xy = sscanf(xyString, '%f:%f', 2);
if numel(xy) < 2 || any(isnan(xy)); return; end
x1 = xy(1);
y1 = xy(2);

z = dataset.getCurrentSliceNumber();
switch dataset.orientation
    case 3  % yx
        x = x1;
        y = y1;
    case 1  % xz
        y = z;
        x = y1;
        z = x1;
    case 2  % yz
        x = z;
        y = y1;
        z = x1;
end
options.id = id;   % pin to the active dataset; the wrapper default obj.id may be stale
options.blockModeSwitch = 0;
options.y = [y y];
options.x = [x x];
materialIndex = cell2mat(obj.mibModel.getData2D('labels', z, [], [], options));

if dataset.labels.maxMaterials < 256
    % palette model (63/255): every material has its own table row, just select it
    obj.cSegmentation.materialsTable_CellSelectionCallback([materialIndex + 2, 2]);
    return;
end

% 65535+ material model: the table holds only two material slots whose displayed
% names store the actual material index. Write the index found under the cursor
% into the currently selected slot, then re-render the table (updateMaterialsTable
% re-reads materialNames into the cells, recolours, and reapplies the selection;
% materialsTable_CellSelectionCallback alone would not refresh the displayed name).
if materialIndex == 0
    obj.cSegmentation.materialsTable_CellSelectionCallback([2, 2]);  % exterior
    return;
end

if dataset.selectedMaterial > 2
    % a material slot is selected: overwrite its index, keep it selected
    dataset.labels.materialNames{dataset.selectedMaterial - 2} = num2str(materialIndex);
elseif ~dataset.restrictSelectionToMaterial
    % Mask/Exterior selected: write into the first material slot and select it
    dataset.labels.materialNames{1} = num2str(materialIndex);
    dataset.selectedMaterial = 3;
else
    % selection restricted to material: write into the Add-To slot, keep selection
    dataset.labels.materialNames{dataset.selectedAddToMaterial - 2} = num2str(materialIndex);
end
obj.cSegmentation.updateMaterialsTable();  % re-render names/colours and reapply selection
% the picked material may have a different colour, and with
% preferences.Colors.CursorMaterialColor on the brush cursor carries it - the
% mouse is standing still over the image here, so repaint it explicitly
cImageDoc.updateBrushCursor();
end
