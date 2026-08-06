function removeMaterial(obj, materialIndices, wb)
% REMOVEMATERIAL - Remove materials from the model - low-level data layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.removeMaterial(materialIndices, wb)
%
% Modifies pixel data across all time-points and then updates the model
% metadata (materialNames, materialColors, selection state).
%
% For types 63 and 255 the remaining materials are remapped to contiguous
% indices 1..N and the corresponding name/colour entries are deleted.
%
% For types 65535 and 4294967295 the pixels belonging to the removed
% materials are zeroed out.  The materialNames and materialColors arrays
% are indexed directly by material value, so row-deletion would shift
% colours of unrelated materials; they are therefore left unchanged.
%
% Input Arguments:
%   - **materialIndices** - double vector, 1-based indices of materials to remove.
%     Must already be validated by the caller (MibModel.removeMaterial).
%   - **wb** - *(optional)* handle to a uiprogressdlg used for progress display;
%     when empty no progress is reported.
%
% Output Arguments:
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.removeMaterial([2 4]);% remove materials 2 and 4
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.removeMaterial([1 3], wb);% with progress bar
%

% Updates
%

if nargin < 3; wb = []; end

modelType = obj.labels.maxMaterials;
materialIndices = sort(materialIndices);

%% Pixel-data manipulation across all time-points
options.blockModeSwitch = false;
numT = obj.image.time;

for t = 1:numT
    M = obj.getData3D('labels', t, 3, NaN, options);
    if isempty(M) || isempty(M{1})
        if ~isempty(wb); wb.Value = t / numT * 0.9; end
        continue;
    end
    img = M{1};

    if modelType < 256
        % Remap: remove specified materials, reindex remaining to 1..N
        keepMaterials = 1:numel(obj.labels.materialNames);
        keepMaterials(ismember(keepMaterials, materialIndices)) = [];
        [logicalMember, indexValue] = ismember(img, keepMaterials);
        newImg = zeros(size(img), class(img));
        newImg(logicalMember) = cast(indexValue(logicalMember), class(img));
        obj.setData3D({newImg}, 'labels', t, 3, NaN, options);
    else
        % Zero out pixels belonging to the removed material indices
        img(ismember(img, cast(materialIndices, class(img)))) = 0;
        obj.setData3D({img}, 'labels', t, 3, 0, options);
    end

    if ~isempty(wb); wb.Value = t / numT * 0.9; end
end

%% Metadata cleanup
if modelType < 256
    nMats    = numel(obj.labels.materialNames);
    validIdx = materialIndices(materialIndices >= 1 & materialIndices <= nMats);
    if ~isempty(validIdx)
        obj.labels.materialColors(validIdx, :) = [];
        obj.labels.materialNames(validIdx)     = [];
    end
    obj.labels.materialsCount = numel(obj.labels.materialNames);
end
% For large models materialsCount is a high-water mark - zeroing out
% mid-range indices does not lower it; squeezeMaterialLabels recounts.

% Reset selection to Exterior regardless of model type
obj.selectedMaterial      = 2;
obj.selectedAddToMaterial = 2;
obj.lastSegmSelection     = [2, 1];
end
