function result = swapSlices(obj, sliceFrom, sliceTo, orient)
% SWAPSLICES - Swap specified slice(s) between two positions within the same array.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.swapSlices(sliceFrom, sliceTo, orient)
%
% Pure data-manipulation layer: operates only on ``obj.data``.  No dialogs,
% no waitbars, no annotation handling.  Caller (``core.MibDataset.swapSlices``)
% is responsible for auxiliary-layer operations and action-log updates.
%
% Input Arguments:
%   - **sliceFrom** — index or index vector of source slices
%   - **sliceTo** — index or index vector of destination slices; must be the
%     same length as **sliceFrom**
%   - **orient** — *(optional)* dimension to operate on:
%     ``1`` = height (y), ``2`` = width (x), ``3`` = depth (z, default),
%     ``5`` = time (t)
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
%     result = obj.image.swapSlices(3, 10);  % swap z-slices 3 and 10
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     result = obj.image.swapSlices([1,2], [5,6], 3);  % swap two-slice blocks
%

% Updates
%

if nargin < 4 || isempty(orient); orient = 3; end

result = 0;
if numel(sliceFrom) ~= numel(sliceTo); return; end
maxSlice = size(obj.data, orient);
if max(sliceFrom) > maxSlice || max(sliceTo) > maxSlice || min(sliceFrom) < 1 || min(sliceTo) < 1
    return;
end

switch orient
    case 3  % depth (z) — dim 3 in MIB3
        temp = obj.data(:, :, sliceTo, :, :);
        obj.data(:, :, sliceTo, :, :) = obj.data(:, :, sliceFrom, :, :);
        obj.data(:, :, sliceFrom, :, :) = temp;
    case 1  % height (y)
        temp = obj.data(sliceTo, :, :, :, :);
        obj.data(sliceTo, :, :, :, :) = obj.data(sliceFrom, :, :, :, :);
        obj.data(sliceFrom, :, :, :, :) = temp;
    case 2  % width (x)
        temp = obj.data(:, sliceTo, :, :, :);
        obj.data(:, sliceTo, :, :, :) = obj.data(:, sliceFrom, :, :, :);
        obj.data(:, sliceFrom, :, :, :) = temp;
    case 5  % time (t)
        temp = obj.data(:, :, :, :, sliceTo);
        obj.data(:, :, :, :, sliceTo) = obj.data(:, :, :, :, sliceFrom);
        obj.data(:, :, :, :, sliceFrom) = temp;
    otherwise
        return;
end

result = 1;
end
