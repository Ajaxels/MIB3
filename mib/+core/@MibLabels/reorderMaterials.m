function reorderMaterials(obj, newOrder)
% function reorderMaterials(obj, newOrder)
% Reorder material names and colours according to newOrder
%
% The caller is responsible for remapping the corresponding pixel values
% beforehand (see MibDataset.reorderMaterials).
%
% Parameters:
% newOrder: double vector, permutation of 1:numel(materialNames)
%   specifying the new arrangement.  For example [3 1 2] moves material 3
%   to position 1, material 1 to position 2, material 2 to position 3.
%
% Return values:
%

%|
% @b Examples:
% @code obj.mibModel.I{obj.mibModel.id}.labels.reorderMaterials([3 1 2]);  // rotate materials @endcode

% Updates
%

obj.materialColors = obj.materialColors(newOrder, :);
obj.materialNames  = obj.materialNames(newOrder);
obj.materialsCount = numel(obj.materialNames);
end
