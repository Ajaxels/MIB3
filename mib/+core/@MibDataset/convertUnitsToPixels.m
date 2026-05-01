function [x, y, z] = convertUnitsToPixels(obj, x, y, z)
% CONVERTUNITSTOPIXELS - [x, y, z] = convertUnitsToPixels(obj, x, y, z).
%
% Syntax:
%   .. code-block:: matlab
%
%       [x, y, z] = obj.convertUnitsToPixels(x, y, z)
%
% Convert coordinates from physical imaging units to pixels using pixSize and boundingBox.
%
% Input Arguments:
%   - **x** — double, x-coordinate(s) in physical units (e.g. um)
%   - **y** — double, y-coordinate(s) in physical units (e.g. um)
%   - **z** — double, z-coordinate(s) in physical units (e.g. um)
%
% Output Arguments:
%   - **x** — double, x-coordinate(s) in pixels
%   - **y** — double, y-coordinate(s) in pixels
%   - **z** — double, z-coordinate(s) in pixels
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     [xPx, yPx, zPx] = obj.mibModel.I{obj.mibModel.getActiveId()}.convertUnitsToPixels(xU, yU, zU);
%

if nargin < 4; error('convertUnitsToPixels: missing parameters, x, y and z are required'); end

bb = obj.image.boundingBox;
pixSize = obj.image.pixSize;

if obj.orientation == 3     % yx (default in MIB3)
    x = (x - bb(1)) / pixSize.x;
    y = (y - bb(3)) / pixSize.y;
    z = (z - bb(5) + pixSize.z) / pixSize.z;
elseif obj.orientation == 1     % xz
    x = (x - bb(1)) / pixSize.x;
    y = (y - bb(3) + pixSize.y) / pixSize.y;
    z = (z - bb(5)) / pixSize.z;
elseif obj.orientation == 2     % yz
    x = (x - bb(1) + pixSize.x) / pixSize.x;
    y = (y - bb(3)) / pixSize.y;
    z = (z - bb(5)) / pixSize.z;
end

end
