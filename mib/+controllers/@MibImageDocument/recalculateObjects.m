function recalculateObjects(obj)
% RECALCULATEOBJECTS - Recalculate objects for Mask or Model layer for Object Picker tool in 3D.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.recalculateObjects()
%
% Populates the ``maskStats`` structure of the active dataset with connected
% component information (label matrix and bounding boxes, or ``PixelIdxList``
% for models with >65535 materials).
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%
% **Example** — recalculate object stats:
%
%   .. code-block:: matlab
%
%      obj.recalculateObjects();
%

% Updates
%

id = obj.mibModel.getActiveId();
segmHandles = obj.mibController.cSegmentation.handles;

type = 'labels';
colchannel = obj.mibModel.I{id}.getSelectedMaterialIndex();
if colchannel == -1
    type = 'mask';
    colchannel = 0;
    materialName = 'Mask';
elseif colchannel == 0
    materialName = 'Exterior';
else
    if obj.mibModel.I{id}.labels.maxMaterials > 255
        materialName = 'all objects';
    else
        materialName = obj.mibModel.I{id}.labels.materialNames{colchannel};
    end
end

wb = uiprogressdlg(obj.view.gui, 'Value', 0, ...
    'Message', sprintf('Calculating statistics for %s\nPlease wait...', materialName), ...
    'Title', 'Recalculating objects', 'Indeterminate', true);

getDataOptions.blockModeSwitch = 0;
getDataOptions.id = id;

% read connectivity from the magic wand panel radio buttons
connectTag = segmHandles.magicConnect.SelectedObject.Tag;
if strcmp(connectTag, 'magicConnect4')
    connectionType = 6;     % 6-connected
else
    connectionType = 26;    % 26-connected
end

switch type
    case 'labels'
        if obj.mibModel.I{id}.labels.maxMaterials < 65535
            % generate label matrix and bounding boxes
            obj.mibModel.I{id}.maskStats = bwconncomp( ...
                cell2mat(obj.mibModel.getData3D(type, [], 3, colchannel, getDataOptions)), connectionType);
            obj.mibModel.I{id}.maskStats.L = labelmatrix(obj.mibModel.I{id}.maskStats);
            obj.mibModel.I{id}.maskStats.bb = regionprops(obj.mibModel.I{id}.maskStats, 'BoundingBox');
            obj.mibModel.I{id}.maskStats = rmfield(obj.mibModel.I{id}.maskStats, 'PixelIdxList');
        else
            % generate PixelIdxList for large models
            obj.mibModel.I{id}.maskStats = regionprops( ...
                cell2mat(obj.mibModel.getData3D(type, [], 3, [], getDataOptions)), 'PixelIdxList');
        end
    case 'mask'
        obj.mibModel.I{id}.maskStats = bwconncomp( ...
            cell2mat(obj.mibModel.getData3D(type, [], 3, colchannel, getDataOptions)), connectionType);
        obj.mibModel.I{id}.maskStats.L = labelmatrix(obj.mibModel.I{id}.maskStats);
        obj.mibModel.I{id}.maskStats.bb = regionprops(obj.mibModel.I{id}.maskStats, 'BoundingBox');
        obj.mibModel.I{id}.maskStats = rmfield(obj.mibModel.I{id}.maskStats, 'PixelIdxList');
end

close(wb);

end
