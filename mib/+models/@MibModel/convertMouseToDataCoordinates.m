function [xOut, yOut, zOut, tOut] = convertMouseToDataCoordinates(obj, x, y, mode, permuteSw)
% CONVERTMOUSETODATACOORDINATES - Convert coordinates under the mouse cursor to the coordinates of the dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       [xOut, yOut, zOut, tOut] = obj.convertMouseToDataCoordinates(x, y, mode, permuteSw)
%
% Input Arguments:
%   - **x** - x - coordinate
%   - **y** - y - coordinate
%   - **mode** - *(optional)* string; default ``'shown'``:
%
%     - ``'shown'`` - convert coordinates of the mouse above the image to dataset coordinates
%     - ``'full'`` - conversion for when the full image is rendered in ``handles.imageAxes``
%     - ``'blockmode'`` - returns coordinates under the mouse for the Block (blockface mode)
%
%   - **permuteSw** - *(optional)*, can be ``[]``:
%
%     - ``0`` - returns coordinates for the dataset in the original XY orientation
%     - ``1`` - *(default)* returns coordinates so that the currently selected orientation becomes XY
%
% Output Arguments:
%   - **xOut** - x - coordinate with the dataset
%   - **yOut** - y - coordinate with the dataset
%   - **zOut** - z - coordinate with the dataset
%   - **tOut** - t - time coordinate
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     [xOut, yOut] = obj.mibModel.convertMouseToDataCoordinates(x, y);
%

% Updates
% 


if nargin < 5; permuteSw = 1; end
if nargin < 4; mode = 'shown'; end

magFactor = obj.getMagFactor();
[axesX, axesY] = obj.getAxesLimits();

if mode(1) == 's' % shown
    % XData/YData are in physical space: 1 data pixel = coefX XData units
    % horizontally and coefY YData units vertically (see MibDataset.getDisplayStretch)
    [coefX, coefY] = obj.I{obj.id}.getDisplayStretch();

    if magFactor >= 1 && axesX(1) <= 1 && axesY(1) <= 1
        % Full-image mode (zoomed out, view at dataset origin):
        % XLim starts near 0 and x directly encodes absolute data position.
        xOut = x * magFactor / coefX;
        yOut = y * magFactor / coefY;
    else
        % Block/crop mode: view is panned away from the dataset origin
        % (axesX(1) > 1) OR zoomed in (magFactor < 1).
        % XLim starts near 0 (relative to the crop), so axesX(1) must be
        % added to convert from viewport-relative to absolute dataset coords.
        % This also covers Zarr pyramid datasets, which always load a crop
        % even at magFactor >= 1 (e.g. 100% view of a large dataset).
        xOut = x * magFactor / coefX + max([0 floor(axesX(1))]);
        yOut = y * magFactor / coefY + max([0 floor(axesY(1))]);
    end
elseif mode(1) == 'b' % blockmode
    xOut = x*magFactor;
    yOut = y*magFactor;
else  % full
    %sprintf('Mag=%f, x1=%f, axexX=%f\n',magFactor, x(1), axesX(1))
    xOut = (x*magFactor +  max([0 axesX(1)]))/max([1 magFactor]);
    yOut = (y*magFactor +  max([0 axesY(1)]))/max([1 magFactor]);
end

zOut = zeros(size(xOut,1)) + obj.I{obj.id}.getCurrentSliceNumber();
% generate zOut coordinates
if permuteSw == 0
    tempX = xOut;
    tempY = yOut;
    tempZ = zOut;
    if obj.I{obj.id}.orientation == 1    % zx: horizontal = X, vertical = Z, slice = Y
        xOut = tempX;
        yOut = tempZ;
        zOut = tempY;
    elseif obj.I{obj.id}.orientation == 2 % zy
        xOut = tempZ;
        yOut = tempY;
        zOut = tempX;
    end
end
tOut = obj.I{obj.id}.slices{5}(1);
end
