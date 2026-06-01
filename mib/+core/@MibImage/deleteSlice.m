function result = deleteSlice(obj, sliceNumbers, orient)
% DELETESLICE - Delete specified slice(s) from the image array.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.deleteSlice(sliceNumbers, orient)
%
% Pure data-manipulation layer: removes indexed slices from ``obj.data``
% and updates ``obj.height``, ``obj.width``, ``obj.depth``, ``obj.time``,
% ``obj.dim_yxzct``, and ``obj.sliceName`` (for depth operations).
% No dialogs, no waitbars.  Annotation bookkeeping and view-range updates
% are handled by the caller (``core.MibDataset.deleteSlice``).
%
% Input Arguments:
%   - **sliceNumbers** — index or index vector of slices to delete
%   - **orient** — dimension to operate on:
%     ``1`` = height (y), ``2`` = width (x), ``3`` = depth (z),
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
%     result = obj.image.deleteSlice(5, 3);  % delete z-slice 5
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     result = obj.image.deleteSlice([2, 5, 8], 3);  % delete z-slices 2, 5, and 8
%
%   **Example 3**
%
%   .. code-block:: matlab
%
%
%     result = obj.image.deleteSlice(1, 5);  % delete time-frame 1
%

% Updates
%

result = 0;
maxSlice = size(obj.data, orient);
if any(sliceNumbers > maxSlice) || any(sliceNumbers < 1); return; end

switch orient
    case 3  % depth (z) — dim 3 in MIB3
        indexList = setdiff(1:maxSlice, sliceNumbers);
        obj.data = obj.data(:, :, indexList, :, :);
    case 1  % height (y)
        indexList = setdiff(1:maxSlice, sliceNumbers);
        obj.data = obj.data(indexList, :, :, :, :);
    case 2  % width (x)
        indexList = setdiff(1:maxSlice, sliceNumbers);
        obj.data = obj.data(:, indexList, :, :, :);
    case 5  % time (t)
        indexList = setdiff(1:maxSlice, sliceNumbers);
        obj.data = obj.data(:, :, :, :, indexList);
    otherwise
        return;
end

obj.height = size(obj.data, 1);
obj.width  = size(obj.data, 2);
obj.depth  = size(obj.data, 3);
obj.time   = size(obj.data, 5);
obj.dim_yxzct = [obj.height, obj.width, obj.depth, obj.colors, obj.time];

if orient == 3 && ~isempty(obj.sliceName) && numel(obj.sliceName) > 1
    sliceNames = obj.sliceName;
    sliceNames(sliceNumbers) = [];
    obj.sliceName = sliceNames;
end

result = 1;
end
