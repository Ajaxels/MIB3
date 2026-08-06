function setDataFast(obj, dataset, z, colChannel, t)
% SETDATAFAST - In-place slice/volume write used by the MibDataset fast paths.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setDataFast(dataset, z, colChannel, t)
%
% Keeps the indexed assignment **inside** MibImage (a single handle hop) so that
% MATLAB mutates ``obj.data`` in place instead of copy-on-writing the whole 5-D
% array. Writing through ``MibDataset.(layer).data(...) = dataset`` (two handle
% hops) defeats MATLAB's in-place optimization and copies the entire array on
% every call - the source of the per-slice ``setData2D``/``setData3D`` slowdown.
%
% When the write spans the **entire** array (all z, all channels, all time
% points), the element-wise indexed assignment is skipped altogether and
% ``obj.data`` is replaced by reference (``obj.data = reshape(dataset, …)``) -
% an O(1) copy-on-write swap instead of touching every element.
%
% Input Arguments:
%   - **dataset** - [numeric] 2D slice ``[height, width]`` (when **z** is a scalar),
%     3D volume ``[height, width, depth]`` (when **z** is ``[]``), or 4D series
%     ``[height, width, depth, time]`` (when both **z** and **t** are ``[]``)
%   - **z** - [numeric or ``[]``] slice index for a 2D write, or ``[]`` to write the
%     full depth (3D volume / 4D series write)
%   - **colChannel** - [numeric] color channel / material index(es) to write
%   - **t** - [numeric or ``[]``] time point to write, or ``[]`` to write all time points
%
%   .. note::
%      Only the simple full-channel case is routed here by the fast paths; the
%      material-index labels case is handled by the slow path. The literal
%      colons are kept inside this method so the assignment stays in-place.

% Updates
%

% Full-array replacement: when the write covers all z, all channels and all
% time points, swap the array header (O(1), COW) instead of writing every element.
% The class check keeps the implicit type conversion of indexed assignment
% (e.g. logical → uint8) on the element-wise path below.
if isempty(z) && isequal(colChannel, 1:size(obj.data, 4)) && ...
        (isempty(t) || (size(obj.data, 5) == 1 && isequal(t, 1))) && ...
        numel(dataset) == numel(obj.data) && strcmp(class(dataset), class(obj.data))
    obj.data = reshape(dataset, size(obj.data));
    return;
end

if isempty(z) && isempty(t)
    obj.data(:, :, :, colChannel, :) = dataset;   % 4D series write (all z, all t)
elseif isempty(z)
    obj.data(:, :, :, colChannel, t) = dataset;   % 3D volume write (all z)
else
    obj.data(:, :, z, colChannel, t) = dataset;   % 2D slice write
end
end
