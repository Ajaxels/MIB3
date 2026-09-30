function [yMin, yMax, xMin, xMax, zMin, zMax] = getCoordinatesOfShownImage(obj, transposeTo3)
% GETCOORDINATESOFSHOWNIMAGE - Return minimal and maximal coordinates (XY) of the image that is.
%
% Syntax:
%   .. code-block:: matlab
%
%       [yMin, yMax, xMin, xMax, zMin, zMax] = obj.getCoordinatesOfShownImage(transposeTo3)
%
% currently shown.
%
% Input Arguments:
%   - **transposeTo3** - - *(optional)* when
%     true, transpose dataset to the orientation 3, when looking on the XY plane of the dataset
%     false, do not transpose
%
% Output Arguments:
%   - **yMin** - - minimal Y coordinate
%   - **yMax** - - maximal Y coordinate
%   - **xMin** - - minimal Y coordinate
%   - **xMax** - - maximal Y coordinate
%   - **zMin** - - minimal Z coordinate
%   - **zMax** - - maximal Z coordinate
%
%   **Note:**
%   it is also possible to get coordinates from .slices field of mibImage class
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     [yMin, yMax, xMin, xMax] = obj.mibModel.I{obj.mibModel.id}.getCoordinatesOfShownImage();% get coordinates
%

% Updates

if nargin < 2; transposeTo3 = 0; end

Xlim = ceil(obj.axesX);
Ylim = ceil(obj.axesY);

if ~transposeTo3
    if obj.orientation==1     % zx: rows = Z, columns = X
        yMin = max([Ylim(1) 1]);
        yMax = min([Ylim(2) obj.image.depth]);
        xMin = max([Xlim(1) 1]);
        xMax = min([Xlim(2) obj.image.width]);
        zMin = 1;
        zMax = obj.image.height;
    elseif obj.orientation==2 % yz
        yMin = max([Ylim(1) 1]);
        yMax = min([Ylim(2) obj.image.height]);
        xMin = max([Xlim(1) 1]);
        xMax = min([Xlim(2) obj.image.depth]);
        zMin = 1;
        zMax = obj.image.width;
    elseif obj.orientation==3 % yx
        yMin = max([Ylim(1) 1]);
        yMax = min([Ylim(2) obj.image.height]);
        xMin = max([Xlim(1) 1]);
        xMax = min([Xlim(2) obj.image.width]);
        zMin = 1;
        zMax = obj.image.depth;
    end
else    % transpose to XY
    if obj.orientation==1     % zx: rows = Z, columns = X
        xMin = max([Xlim(1) 1]);
        xMax = min([Xlim(2) obj.image.width]);
        zMin = max([Ylim(1) 1]);
        zMax = min([Ylim(2) obj.image.depth]);
        yMin = 1;
        yMax = obj.image.height;
    elseif obj.orientation==2 % yz
        yMin = max([Ylim(1) 1]);
        yMax = min([Ylim(2) obj.image.height]);
        zMin = max([Xlim(1) 1]);
        zMax = min([Xlim(2) obj.image.depth]);
        xMin = 1;
        xMax = obj.image.width;
    elseif obj.orientation==3 % yx
        yMin = max([Ylim(1) 1]);
        yMax = min([Ylim(2) obj.image.height]);
        xMin = max([Xlim(1) 1]);
        xMax = min([Xlim(2) obj.image.width]);
        zMin = 1;
        zMax = obj.image.depth;
    end
end

end
