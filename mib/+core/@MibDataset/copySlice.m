function result = copySlice(obj, sliceFrom, sliceTo, orient)
% COPYSLICE - Copy slice(s) from one position to another in all image layers.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.copySlice(sliceFrom, sliceTo, orient)
%
% Orchestrates a within-dataset slice copy across all active layers: the
% primary image, labels (model), mask, and selection.  Delegates actual
% array manipulation to ``core.MibImage.copySlice`` for each layer.
% The dataset size does not change; this is an in-place overwrite of the
% destination slice with the source slice contents.
%
% Input Arguments:
%   - **sliceFrom** — index or index vector of source slices
%   - **sliceTo** — index or index vector of destination slices; must be the
%     same length as **sliceFrom**
%   - **orient** — *(optional)* dimension to operate on:
%     ``1`` = height (y), ``2`` = width (x), ``3`` = depth (z),
%     ``5`` = time (t). Default: ``obj.orientation``
%
% Output Arguments:
%   - **result** — ``1`` on success, ``0`` on failure
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{id}.copySlice(3, 10);
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{id}.copySlice([1,2], [5,6], 3);
%

% Updates
%

if nargin < 4 || isempty(orient); orient = obj.orientation; end

result = obj.image.copySlice(sliceFrom, sliceTo, orient);
if result == 0; return; end

if obj.labels.maxMaterials < 255   % labels63: model+mask+selection packed together
    if obj.modelExist
        obj.labels.copySlice(sliceFrom, sliceTo, orient);
    end
else   % separate model / mask / selection layers
    if obj.modelExist
        obj.labels.copySlice(sliceFrom, sliceTo, orient);
    end
    if obj.maskExist
        obj.mask.copySlice(sliceFrom, sliceTo, orient);
    end
    if obj.selection.exists
        obj.selection.copySlice(sliceFrom, sliceTo, orient);
    end
end

obj.image.actionLog{end+1} = sprintf('Copy slice: %s -> %s, orient: %d', ...
    num2str(sliceFrom), num2str(sliceTo), orient);

result = 1;
end
