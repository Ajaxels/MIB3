function [xOut, yOut, zOut, tOut] = convertMouseToDataCoordinates(obj, x, y, mode, permuteSw)
% function [xOut, yOut, zOut, tOut] = convertMouseToDataCoordinates(obj, x, y, mode, permuteSw)
% Convert coordinates under the mouse cursor to the coordinates of the dataset
%
% Parameters:
% x: x - coordinate
% y: y - coordinate
% mode:  [@em optional] a string that defines a mode of the shown image, @b default is 'shown'
% @li 'shown' - the most common one, convert coordinates of the mouse
% above the image to the coordinates of the dataset
% @li 'full' - suppose to do the conversion for the situation when the full
% image is rendered in the handles.imageAxes, never used...?
% @li 'blockmode' - when the blockface mode is switched on the function
% returns coordinates under the mouse for the Block
% permuteSw: [@em optional], can be @em empty
% @li when @b 0 returns the coordinates for the dataset in the original xy-orientation;
% @li when @b 1 (@b default) returns coordinates for the dataset so that the currently selected orientation becomes @b xy
%
% Return values:
% xOut: x - coordinate with the dataset
% yOut: y - coordinate with the dataset
% zOut: z - coordinate with the dataset
% tOut: t - time coordinate

%| 
% @b Examples:
% @code [xOut, yOut] = obj.mibModel.convertMouseToDataCoordinates(x, y);  // Call from MibController: do conversion' @endcode

% Updates
% 


if nargin < 5; permuteSw = 1; end
if nargin < 4; mode = 'shown'; end

magFactor = obj.getMagFactor();
[axesX, axesY] = obj.getAxesLimits();

if mode(1) == 's' % shown
    % XData is in physical space: 1 data pixel = coef_z XData units for X.
    % Compute coef_z from the current orientation.
    ds = obj.I{obj.id};
    switch ds.orientation
        case 3;  coef_z = ds.pixSize.x / ds.pixSize.y;
        case 1;  coef_z = ds.pixSize.z / ds.pixSize.x;
        otherwise; coef_z = ds.pixSize.z / ds.pixSize.y;
    end

    if magFactor >= 1 && axesX(1) <= 1
        % Full-image mode (zoomed out, view at dataset origin):
        % XLim starts near 0 and x directly encodes absolute data position.
        xOut = x * magFactor / coef_z;
        yOut = y * magFactor;
    else
        % Block/crop mode: view is panned away from the dataset origin
        % (axesX(1) > 1) OR zoomed in (magFactor < 1).
        % XLim starts near 0 (relative to the crop), so axesX(1) must be
        % added to convert from viewport-relative to absolute dataset coords.
        % This also covers Zarr pyramid datasets, which always load a crop
        % even at magFactor >= 1 (e.g. 100% view of a large dataset).
        xOut = x * magFactor / coef_z + max([0 floor(axesX(1))]);
        yOut = y * magFactor           + max([0 floor(axesY(1))]);
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
    if obj.I{obj.id}.orientation == 1    % zx
        xOut = tempY;
        yOut = tempZ;
        zOut = tempX;
    elseif obj.I{obj.id}.orientation == 2 % zy
        xOut = tempZ;
        yOut = tempY;
        zOut = tempX;
    end
end
tOut = obj.I{obj.id}.slices{5}(1);
end