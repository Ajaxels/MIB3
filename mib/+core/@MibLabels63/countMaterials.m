function result = countMaterials(obj)
% COUNTMATERIALS - Calculate and update obj.materialsCount from the current model state.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.countMaterials()
%
% For the uint8 layout (63 materials), when materialNames is available
% (non-empty), the count is taken from numel(materialNames).  Otherwise the
% method scans the pixel data across all time-points, extracts the material
% bits (bitand with materialMask) and finds the highest non-zero material
% index.
%
% The uint16 layout (16383) is an instance model: as for 65535,
% materialNames holds only two placeholder entries, so the pixel data is
% always scanned. ``core.MibBigDataLabels`` overrides this method and answers
% from its persisted ``maxIndexUsed`` instead of scanning the store.
%
% This method should be called after loading or importing a model to
% ensure that materialsCount is synchronised with the actual data.
%
% Input Arguments:
%
% Output Arguments:
%   - **result** - double, the updated materialsCount value.
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

if obj.maxMaterials < 256 && ~isempty(obj.materialNames) && numel(obj.materialNames) > 0
    obj.materialsCount = numel(obj.materialNames);
elseif obj.exists && ~isempty(obj.data)
    maxVal = 0;
    for t = 1:obj.time
        img = bitand(obj.data(:,:,:,1,t), obj.materialMask);   % extract the material bits
        maxVal = max(maxVal, double(max(img(:))));
    end
    obj.materialsCount = maxVal;
else
    obj.materialsCount = 0;
end

result = obj.materialsCount;
end
