function result = countMaterials(obj)
% COUNTMATERIALS - Calculate and update obj.materialsCount from the current model state.
%
% Syntax:
%   function result = countMaterials(obj)
%
% When materialNames is available (non-empty), the count is taken from
% numel(materialNames).  Otherwise the method scans the pixel data across
% all time-points, extracts the model bits (bits 1–6, mask 0x3F = 63) from
% the packed uint8 container, and finds the highest non-zero material
% index.
%
% This method should be called after loading or importing a model to
% ensure that materialsCount is synchronised with the actual data.
%
% Input Arguments:
%
% Output Arguments:
%   - **result** — double, the updated materialsCount value.
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     n = obj.mibModel.I{obj.mibModel.id}.labels.countMaterials();% recount after load/import
%

% Updates
%

if ~isempty(obj.materialNames) && numel(obj.materialNames) > 0
    obj.materialsCount = numel(obj.materialNames);
elseif obj.exists && ~isempty(obj.data) && ~isempty(obj.data{1})
    maxVal = 0;
    for t = 1:obj.time
        img = bitand(obj.data{1}(:,:,:,1,t), uint8(63));   % extract model bits 1-6
        maxVal = max(maxVal, double(max(img(:))));
    end
    obj.materialsCount = maxVal;
else
    obj.materialsCount = 0;
end

result = obj.materialsCount;
end
