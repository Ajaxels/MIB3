function [nodes, indices] = findSliceNodes(obj, z, orientation)
% FINDSLICENODES - find nodes that are shown on the current slice.
%
% Syntax:
%   function [nodes, indices] = findSliceNodes(obj, z, orientation)
%
% Input Arguments:
%   - **z** — Z-value to obtain the nodes
%   - **orientation** — [*optional,* default 3 for XY] a number that
%     specifies desired orientation, 3-yx, 1-xz, 2-yz
%
% Output Arguments:
%   - **nodes** — a matrix with coordinates of nodes [node; x, y, z]
%   - **indices** — a vector with indices of returned nodes
%

if nargin < 2; error('findSliceNodes: missing parameters'); end
if nargin < 3; orientation = 3; end
nodes = [];
indices = [];

pixSize = obj.G.Nodes.Properties.UserData.pixSize;

if orientation == 3
    indices = find(obj.G.Nodes.PointsXYZ(:,3) >= z-pixSize.z/2 & obj.G.Nodes.PointsXYZ(:,3) < z+pixSize.z/2);
    nodes = obj.G.Nodes.PointsXYZ(indices, :);
elseif orientation == 1
    indices = find(obj.G.Nodes.PointsXYZ(:,2) >= z-pixSize.y/2 & obj.G.Nodes.PointsXYZ(:,2) < z+pixSize.y/2);
    nodes = obj.G.Nodes.PointsXYZ(indices, :);
elseif orientation == 2
    indices = find(obj.G.Nodes.PointsXYZ(:,1) >= z-pixSize.x/2 & obj.G.Nodes.PointsXYZ(:,1) < z+pixSize.x/2);
    nodes = obj.G.Nodes.PointsXYZ(indices, :);
end

end
