function reorderMaterials(obj, newOrder)
% REORDERMATERIALS - Reorder material names and colours according to newOrder.
%
% Syntax:
%   function reorderMaterials(obj, newOrder)
%
% The caller is responsible for remapping the corresponding pixel values
% beforehand (see MibDataset.reorderMaterials).
%
% Input Arguments:
%   - **newOrder** — double vector, permutation of 1:numel(materialNames)
%     specifying the new arrangement.  For example [3 1 2] moves material 3
%     to position 1, material 1 to position 2, material 2 to position 3.
%
% Output Arguments:
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.labels.reorderMaterials([3 1 2]);% rotate materials
%

% Updates
%

obj.materialColors = obj.materialColors(newOrder, :);
obj.materialNames  = obj.materialNames(newOrder);
obj.materialsCount = numel(obj.materialNames);
end
