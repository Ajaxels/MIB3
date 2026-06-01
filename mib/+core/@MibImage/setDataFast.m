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
% every call — the source of the per-slice ``setData2D``/``setData3D`` slowdown.
%
% Input Arguments:
%   - **dataset** — [numeric] 2D slice ``[height, width]`` (when **z** is a scalar)
%     or 3D volume ``[height, width, depth]`` (when **z** is ``[]``)
%   - **z** — [numeric or ``[]``] slice index for a 2D write, or ``[]`` to write the
%     full depth (3D volume write)
%   - **colChannel** — [numeric] color channel / material index to write
%   - **t** — [numeric] time point to write
%
%   .. note::
%      Only the simple full-channel case is routed here by the fast paths; the
%      material-index labels case is handled by the slow path. The literal
%      colons are kept inside this method so the assignment stays in-place.

% Updates
%
if isempty(z)
    obj.data(:, :, :, colChannel, t) = dataset;   % 3D volume write (all z)
else
    obj.data(:, :, z, colChannel, t) = dataset;   % 2D slice write
end
end
