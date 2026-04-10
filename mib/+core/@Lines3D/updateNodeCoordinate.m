function updateNodeCoordinate(obj, nodeId, x, y, z)
% function updateNodeCoordinate(obj, nodeId, x, y, z)
% update coordinate of the node
%
% Parameters:
% nodeId: index of the node to update
% x: new x coordinate
% y: new y coordinate
% z: new z coordinate

if nargin < 5; error('not enough paramters!'); end

% update coordinate of the node
obj.G.Nodes.PointsXYZ(nodeId,:) = [x, y, z];
% recalculate edges
inputIndex = find(obj.G.Edges.EndNodes(:,1) == nodeId);
outputIndex = find(obj.G.Edges.EndNodes(:,2) == nodeId);
obj.G.Edges.Edges(inputIndex,1:3) = repmat([x,y,z], [numel(inputIndex), 1]); %#ok<FNDSB>
obj.G.Edges.Edges(outputIndex,4:6) = repmat([x,y,z], [numel(outputIndex), 1]); %#ok<FNDSB>

% recalculate length of edges
options.nodeId = nodeId;
obj.G = obj.calculateLengthOfNodes(obj.G, options);

end
