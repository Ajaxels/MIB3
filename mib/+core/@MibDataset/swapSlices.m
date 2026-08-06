function result = swapSlices(obj, sliceFrom, sliceTo, orient)
% SWAPSLICES - Swap slice(s) between two positions across all image layers.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.swapSlices(sliceFrom, sliceTo, orient)
%
% Orchestrates a within-dataset slice swap across all active layers: the
% primary image, labels (model), mask, and selection.  Delegates actual
% array manipulation to ``core.MibImage.swapSlices`` for each layer.
% The dataset size does not change.
%
% Input Arguments:
%   - **sliceFrom** - index or index vector of source slices
%   - **sliceTo** - index or index vector of destination slices; must be the
%     same length as **sliceFrom**
%   - **orient** - *(optional)* dimension to operate on:
%     ``1`` = height (y), ``2`` = width (x), ``3`` = depth (z),
%     ``5`` = time (t). Default: ``obj.orientation``
%
% Output Arguments:
%   - **result** - ``1`` on success, ``0`` on failure
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{id}.swapSlices(3, 10);
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{id}.swapSlices([1,2], [5,6], 3);
%

% Updates
%

if nargin < 4 || isempty(orient); orient = obj.orientation; end

result = obj.image.swapSlices(sliceFrom, sliceTo, orient);
if result == 0; return; end

if obj.labels.maxMaterials == 63   % labels63: model+mask+selection packed together
    if obj.modelExist
        obj.labels.swapSlices(sliceFrom, sliceTo, orient);
    end
else   % separate model / mask / selection layers
    if obj.modelExist
        obj.labels.swapSlices(sliceFrom, sliceTo, orient);
    end
    if obj.maskExist
        obj.mask.swapSlices(sliceFrom, sliceTo, orient);
    end
    if obj.selection.exists
        obj.selection.swapSlices(sliceFrom, sliceTo, orient);
    end
end

obj.image.actionLog{end+1} = sprintf('Swap slices: %s <-> %s, orient: %d', ...
    num2str(sliceFrom), num2str(sliceTo), orient);

result = 1;
end
