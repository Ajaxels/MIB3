function moveView(obj, x, y, orient)
% function moveView(obj, x, y, orient)
% Center the image view at the provided coordinates: x, y
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.moveView(x);
%       obj.moveView(x, y);
%       obj.moveView(x, y, orient);
%
% Description:
%   Pans the image display so that the given pixel coordinate (x, y) becomes
%   the center of the visible axes area. The current zoom level and axes span
%   are preserved — only the center position shifts.
%
%   When only a single value is provided for x, it is treated as a linear
%   pixel index into the dataset at the given orientation. The corresponding
%   (y, x) coordinates are then derived via ind2sub using the full dataset
%   dimensions (blockModeSwitch = 0).
%
% Input Arguments:
%   - **obj** — handle to the MibDataset model object
%   - **x** — X coordinate of the desired view center in pixels,
%     or a linear pixel index when ``y`` is omitted or ``NaN``
%   - **y** — *(optional)* Y coordinate of the desired view center in pixels.
%     Use ``NaN`` or omit to treat ``x`` as a linear index. Default: ``NaN``
%   - **orient** — *(optional)* orientation of the input coordinates.
%     Default: ``obj.orientation`` (currently displayed orientation).
%     Supported values:
%
%     - **0** — current orientation (same as ``obj.orientation``)
%     - **1** — ZX plane
%     - **2** — ZY plane
%     - **3** — XY plane
%
% Usage:
%   **Example 1** — Center view on pixel (50, 75) in the current orientation:
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.moveView(50, 75);
%
%   **Example 2** — Center view using a linear pixel index (pixel 3820):
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.moveView(3820);
%
%   **Example 3** — Center view on pixel (100, 200) in the XY plane:
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.moveView(100, 200, 3);
%
%   **Example 4** — Center view on a point known in ZX orientation:
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.moveView(64, 32, 1);
%

% Updates
% 

if nargin < 4; orient = obj.orientation; end
if nargin < 3; y = NaN; end
    
if isnan(y)     % generate y from the point index
    getDataOptions.blockModeSwitch = 0;
    [img_height, img_width, img_depth] = obj.getDatasetDimensions('image', orient, getDataOptions);
    [y, x, ~] = ind2sub([img_height img_width img_depth], x);
end

axesX = [x - diff(obj.axesX)/2 x + diff(obj.axesX)/2];
axesY = [y - diff(obj.axesY)/2 y + diff(obj.axesY)/2];
obj.setAxesLimits(axesX, axesY);

end