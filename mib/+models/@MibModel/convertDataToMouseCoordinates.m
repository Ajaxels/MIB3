function [xOut, yOut] = convertDataToMouseCoordinates(obj, x, y, mode)
% CONVERTDATATOMOUSECOORDINATES - Convert coordinates of a pixel in the dataset to the coordinates of the.
%
% Syntax:
%   .. code-block:: matlab
%
%       [xOut, yOut] = obj.convertDataToMouseCoordinates(x, y, mode)
%
% image axes (screen/mouse space).
%
% This is the inverse of convertMouseToDataCoordinates.  It takes pixel
% positions in the dataset coordinate frame and returns the corresponding
% positions in the axes coordinate frame used for rendering.
%
% Input Arguments:
%   - **x** - numeric - x-coordinate(s) in dataset space
%   - **y** - numeric - y-coordinate(s) in dataset space
%   - **mode** - *(optional)* char - rendering mode, default **'shown'**
%   - 'shown' - standard viewport (most common)
%   - 'full'  - full-image rendering during panning
%
% Output Arguments:
%   - **xOut** - numeric - x-coordinate(s) in axes space
%   - **yOut** - numeric - y-coordinate(s) in axes space
%
% Usage:
%   Example 1::
%
%     [xOut, yOut] = obj.mibModel.convertDataToMouseCoordinates(x, y);  // from MibController
%
%   Example 2::
%
%     [xOut, yOut] = obj.mibModel.convertDataToMouseCoordinates(x, y, 'shown'); // explicit mode
%

if nargin < 4; mode = 'shown'; end

magFactor = obj.getMagFactor();
[axesX, axesY] = obj.getAxesLimits();

if mode(1) == 's' % shown
    % see MibDataset.getDisplayStretch
    [coefX, coefY] = obj.I{obj.id}.getDisplayStretch();

    if magFactor >= 1 && axesX(1) <= 1 && axesY(1) <= 1
        % Full-image mode: inverse of xData = xMouse * magFactor / coefX
        xOut = x * coefX / magFactor;
        yOut = y * coefY / magFactor;
    else
        % Block/crop mode: inverse of xData = xMouse * magFactor / coefX + offset
        xOut = (x - max([0 floor(axesX(1))])) * coefX / magFactor;
        yOut = (y - max([0 floor(axesY(1))])) * coefY / magFactor;
    end
else  % full
    xOut = x / max([1 magFactor]);
    yOut = y / max([1 magFactor]);
end
end
