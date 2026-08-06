function result = resliceDataset(obj, sliceNumbers, orient)
% RESLICEDATASET - Keep only the specified slice(s), removing all others.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.resliceDataset(sliceNumbers, orient)
%
% Pure data-manipulation layer: retains indexed slices in ``obj.data``
% and updates ``obj.height``, ``obj.width``, ``obj.depth``, ``obj.time``,
% ``obj.dim_yxzct``, and ``obj.sliceName`` (for depth operations).
% No dialogs, no waitbars.  View-range and bounding-box updates are handled
% by the caller (``core.MibDataset.resliceDataset``).
%
% Input Arguments:
%   - **sliceNumbers** - index or index vector of slices to *keep*; all other
%     slices are removed
%   - **orient** - dimension to operate on:
%     ``1`` = height (y), ``2`` = width (x), ``3`` = depth (z),
%     ``5`` = time (t)
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
%     result = obj.image.resliceDataset(1:2:50, 3);  % keep every other z-slice
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     result = obj.image.resliceDataset([1, 5, 10, 20], 3);  % keep 4 specific slices
%

% Updates
%

result = 0;
maxSlice = size(obj.data, orient);
if any(sliceNumbers > maxSlice) || any(sliceNumbers < 1); return; end

switch orient
    case 3  % depth (z) - dim 3 in MIB3
        obj.data = obj.data(:, :, sliceNumbers, :, :);
    case 1  % height (y)
        obj.data = obj.data(sliceNumbers, :, :, :, :);
    case 2  % width (x)
        obj.data = obj.data(:, sliceNumbers, :, :, :);
    case 5  % time (t)
        obj.data = obj.data(:, :, :, :, sliceNumbers);
    otherwise
        return;
end

obj.height = size(obj.data, 1);
obj.width  = size(obj.data, 2);
obj.depth  = size(obj.data, 3);
obj.time   = size(obj.data, 5);
obj.dim_yxzct = [obj.height, obj.width, obj.depth, obj.colors, obj.time];

if orient == 3 && ~isempty(obj.sliceName) && numel(obj.sliceName) > 1
    obj.sliceName = obj.sliceName(sliceNumbers);
end

result = 1;
end
