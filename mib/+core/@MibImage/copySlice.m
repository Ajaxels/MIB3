function result = copySlice(obj, sliceFrom, sliceTo, orient)
% COPYSLICE - Copy specified slice(s) from one position to another within the same array.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.copySlice(sliceFrom, sliceTo, orient)
%
% Pure data-manipulation layer: operates only on ``obj.data{1}``.  No dialogs,
% no waitbars, no annotation handling.  Caller (``core.MibDataset.copySlice``)
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
%     result = obj.image.copySlice(3, 10);  % copy z-slice 3 to z-slice 10
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     result = obj.image.copySlice(3, 10, 5);  % copy time-frame 3 to frame 10
%

% Updates
%

if nargin < 4 || isempty(orient); orient = 3; end

result = 0;
maxSlice = size(obj.data{1}, orient);
if any(sliceFrom > maxSlice) || any(sliceTo > maxSlice) || any(sliceFrom < 1) || any(sliceTo < 0)
    return;
end
if numel(sliceFrom) ~= numel(sliceTo); return; end

switch orient
    case 3  % depth (z) — dim 3 in MIB3
        obj.data{1}(:, :, sliceTo, :, :) = obj.data{1}(:, :, sliceFrom, :, :);
    case 1  % height (y)
        obj.data{1}(sliceTo, :, :, :, :) = obj.data{1}(sliceFrom, :, :, :, :);
    case 2  % width (x)
        obj.data{1}(:, sliceTo, :, :, :) = obj.data{1}(:, sliceFrom, :, :, :);
    case 5  % time (t)
        obj.data{1}(:, :, :, :, sliceTo) = obj.data{1}(:, :, :, :, sliceFrom);
    otherwise
        return;
end

result = 1;
end
