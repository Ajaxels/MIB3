function nodeId = findClosestNode(obj, x, y, z, orientation)
% function nodeId = findClosestNode(obj, x, y, z, orientation)
% find the closest node to a point with coordinates x, y, z
%
% Parameters:
% x: x coordinate of a point next to the node
% y: y coordinate of a point next to the node
% z: z coordinate of a point next to the node
% orientation: [@em optional] a number with orientation of the dataset, 3-yx, 1-xz, 2-yz, default 3

if nargin < 5; orientation = 3; end

% transpose points from xy to
if orientation == 1         % zx
    x1 = x; y1 = y; z1 = z;
    x = z1; y = x1; z = y1;
elseif orientation == 2     % zy
    x1 = x; y1 = y; z1 = z;
    x = z1; y = y1; z = x1;
end

% find all points of the existing graph that are shown on the slice of the first point of the branch
[nodes, nodeIds] = obj.findSliceNodes(z, orientation);
if orientation == 1         % zx
    nodes = nodes(:,[3 1]);
elseif orientation == 2     % zy
    nodes = nodes(:,[3 2]);
end
dist = distancePoints([x, y], nodes(:,1:2));    % matGeom function

% find the closest point
[~, nodeId] = min(dist);
% find index of the closest node to the specified point to delete
nodeId = nodeIds(nodeId);

end
