function updateBoundingBox(obj, newBB, xyzShift, imgDims)
% function updateBoundingBox(obj, newBB, xyzShift, imgDims)
% Update the bounding box of the dataset stored in obj.boundingBox
%
% The bounding box describes the physical extent of the dataset in 3D
% space. It is stored directly in the obj.boundingBox property as
% [xmin xmax ymin ymax zmin zmax] in micrometres.
%
% Parameters:
% newBB: new bounding box vector [xmin xmax ymin ymax zmin zmax] in
%   obj.pixSize.units. Pass [] (empty) to shift the existing bounding
%   box instead of replacing it entirely.
% xyzShift: [optional] vector [dx dy dz] with shifts in
%   obj.pixSize.units to apply to the current bounding box origin when
%   newBB is empty. When omitted the origin remains unchanged.
% imgDims: [optional] vector [height width depth] with image dimensions
%   used to compute the new extent. When omitted obj.height, obj.width
%   and obj.depth are used.
%
% Return values:
% (none) — obj.boundingBox and obj.pixSize.x/y/z are updated in place
%
% @b Examples:
% @code
% % shift the bounding box by 10 units in X, 5 in Y, 0 in Z:
% xyzShift = [10 5 0];
% mibImage.updateBoundingBox([], xyzShift);
% @endcode
% @code
% % assign an explicit bounding box:
% mibImage.updateBoundingBox([15 50 10 150 1 15]);
% @endcode

% Updates
%

if nargin < 4
    h     = obj.height;
    w     = obj.width;
    depth = obj.depth;
else
    h     = imgDims(1);
    w     = imgDims(2);
    depth = imgDims(3);
end
if nargin < 3; xyzShift = []; end
if nargin < 2; newBB    = []; end

% convert all distances to micrometres
switch obj.pixSize.units
    case 'm';  coef = 1e6;
    case 'cm'; coef = 1e4;
    case 'mm'; coef = 1e3;
    case 'um'; coef = 1;
    case 'nm'; coef = 1e-3;
    otherwise; coef = 1;
end
obj.pixSize.units = 'um';

if isempty(newBB)   % shift the existing bounding box
    bb = obj.boundingBox;   % [xmin xmax ymin ymax zmin zmax]
    xyzZero(1) = bb(1);
    xyzZero(2) = bb(3);
    xyzZero(3) = bb(5);

    if isempty(xyzShift)
        xyzShift = xyzZero;
    else
        xyzShift(1) = xyzZero(1) + xyzShift(1);
        xyzShift(2) = xyzZero(2) + xyzShift(2);
        xyzShift(3) = xyzZero(3) + xyzShift(3);
    end

    if isnan(xyzShift(1)); xyzShift(1) = 0; end
    if isnan(xyzShift(2)); xyzShift(2) = 0; end
    if isnan(xyzShift(3)); xyzShift(3) = 0; end

    % tweak for Amira single-layer images: max([dim 2]) ensures extent > 0
    dx = (max([w     2]) - 1) * obj.pixSize.x * coef;
    dy = (max([h     2]) - 1) * obj.pixSize.y * coef;
    dz = (max([depth 2]) - 1) * obj.pixSize.z * coef;

    newBB = [xyzShift(1), xyzShift(1)+dx, ...
             xyzShift(2), xyzShift(2)+dy, ...
             xyzShift(3), xyzShift(3)+dz];
end

% store the updated bounding box
obj.boundingBox = newBB;

% recalculate voxel size from the new extent
obj.pixSize.x = (newBB(2) - newBB(1)) / (w - 1);
obj.pixSize.y = (newBB(4) - newBB(3)) / (h - 1);
obj.pixSize.z = (newBB(6) - newBB(5)) / max([depth - 1, 1]);
end
