function result = countMaterials(obj)
% COUNTMATERIALS - Calculate and update obj.materialsCount from the current model state.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.countMaterials()
%
% For small model types (255) the count is taken from
% numel(materialNames) when available.  For large model types
% (65535/4294967295) materialNames always contains only two placeholder
% entries, so the method scans the pixel data across all time-points to
% find the highest non-zero label index.
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

if obj.maxMaterials < 256
    % Small models: materialNames reliably tracks the count
    if ~isempty(obj.materialNames) && numel(obj.materialNames) > 0
        obj.materialsCount = numel(obj.materialNames);
    else
        obj.materialsCount = 0;
    end
else
    % Large models (65535+): materialNames has only placeholder entries,
    % scan pixel data for the highest occupied index
    if obj.exists && ~isempty(obj.data)
        maxVal = 0;
        for t = 1:obj.time
            img = obj.data(:,:,:,1,t);
            maxVal = max(maxVal, double(max(img(:))));
        end
        obj.materialsCount = maxVal;
    else
        obj.materialsCount = 0;
    end
end

result = obj.materialsCount;
end
