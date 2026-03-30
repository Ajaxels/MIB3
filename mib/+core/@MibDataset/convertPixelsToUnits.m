function [x, y, z] = convertPixelsToUnits(obj, x, y, z)
% [x, y, z] = convertPixelsToUnits(obj, x, y, z)
% Convert pixel coordinates to physical imaging units using pixSize and boundingBox.
%
% Parameters:
% x: double, x-coordinate(s) in pixels
% y: double, y-coordinate(s) in pixels
% z: double, z-coordinate(s) in pixels
%
% Return values:
% x: double, x-coordinate(s) in physical units (e.g. um)
% y: double, y-coordinate(s) in physical units (e.g. um)
% z: double, z-coordinate(s) in physical units (e.g. um)

%|
% @b Examples:
% @code
% [xU, yU, zU] = obj.mibModel.I{obj.mibModel.getActiveId()}.convertPixelsToUnits(xPx, yPx, zPx);
% @endcode

if nargin < 4; error('convertPixelsToUnits: missing parameters, x, y and z are required'); end

bb = obj.image.boundingBox;
pixSize = obj.image.pixSize;

if obj.orientation == 3     % yx (default in MIB3)
    x = x * pixSize.x + bb(1);
    y = y * pixSize.y + bb(3);
    z = z * pixSize.z + bb(5) - pixSize.z;
elseif obj.orientation == 1     % xz
    x = x * pixSize.x + bb(1);
    y = y * pixSize.y + bb(3) - pixSize.y;
    z = z * pixSize.z + bb(5);
elseif obj.orientation == 2     % yz
    x = x * pixSize.x + bb(1) - pixSize.x;
    y = y * pixSize.y + bb(3);
    z = z * pixSize.z + bb(5);
end

end
