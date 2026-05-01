function swapMaterials(obj, index1, index2)
% SWAPMATERIALS - Swap material names and colours between two positions.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.swapMaterials(index1, index2)
%
% The caller is responsible for swapping the corresponding pixel values
% beforehand (see MibDataset.swapMaterials).
%
% Input Arguments:
%   - **index1** — double, 1-based index of the first material.
%   - **index2** — double, 1-based index of the second material.
%
% Output Arguments:
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.labels.swapMaterials(1, 3);% swap materials 1 and 3
%

% Updates
%

nMats = numel(obj.materialNames);
if index1 == index2; return; end
if index1 < 1 || index1 > nMats || index2 < 1 || index2 > nMats; return; end

newOrder = 1:nMats;
newOrder(index1) = index2;
newOrder(index2) = index1;

obj.materialColors = obj.materialColors(newOrder, :);
obj.materialNames  = obj.materialNames(newOrder);
end
