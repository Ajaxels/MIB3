%function materialsTable_moveLayers(obj, menuEntry, selectedData)
function materialsTable_moveLayers(obj, obj_type_from, obj_type_to, layers_id, action_type)
% MATERIALSTABLE_MOVELAYERS - callbacks for the context menu of the segmentation table to move layers (obj.handles.panels.segmentation.handles.materialsTableContextM2S):.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.materialsTable_moveLayers(obj_type_from, obj_type_to, layers_id, action_type)
%
% -> Material to Selection
% -> Material to Mask
% -> Mask to Material
%
% Input Arguments:
%   - **obj_type_from** — [char] the source layer ('selection', 'mask', 'labels')
%   - **obj_type_to** — [char] the destination layer ('selection', 'mask', 'labels')
%   - **layers_id** — [char] identifier of the dataset ('2D, Slice', '3D, Stack', '4D, Dataset')
%   - **action_type** — [char] what to do ('replace', 'add', 'remove')
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.materialsTable_moveLayers\n');
end

if strcmp(action_type, 'remove') && strcmp(obj_type_from, 'mask') && strcmp(obj_type_to, 'labels')
    % tweak for mask to model
    BatchOpt.restrictSelectionToMaterial = true;
    obj.mibModel.moveLayers(obj_type_from, obj_type_to, layers_id, action_type, BatchOpt);
else
    obj.mibModel.moveLayers(obj_type_from, obj_type_to, layers_id, action_type);    
end


end
