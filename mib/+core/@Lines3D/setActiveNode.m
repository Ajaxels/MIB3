function setActiveNode(obj, x, y, z, orientation)
% function setActiveNode(obj, x, y, z, orientation)
% set active the node which is closest to a point with coordinates x, y, z
%
% Parameters:
% x: x coordinate of a point next to the node
% y: y coordinate of a point next to the node
% z: z coordinate of a point next to the node
% orientation: [@em optional] a number with orientation of the dataset, 3-yx, 1-xz, 2-yz, default 3

if nargin < 5; orientation = 3; end

nodeId = obj.findClosestNode(x, y, z, orientation);
if isempty(nodeId); return; end     % no node
obj.activeNodeId = nodeId(1);

end
