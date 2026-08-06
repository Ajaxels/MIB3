function result = deleteNode(obj, x, y, z, orientation)
% DELETENODE - delete node that is closest to the point with coordinates x, y, z.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.deleteNode(x, y, z, orientation)
%
% the previous and following nodes get connected after remove of the node
%
% Input Arguments:
%   - **x** - x coordinate of a point next to the node, or index of the
%     node (in this case, y and z should be empty)
%   - **y** - y coordinate of a point next to the node
%   - **z** - z coordinate of a point next to the node
%   - **orientation** - *(optional)* a number with orientation of the dataset, 3-yx, 1-xz, 2-yz, default 3
%
% Output Arguments:
%   - **result** - type of the node that was deleted
%     'removed tree' - the last node of a tree was removed, so the tree was deleted
%     'middle node'  - the removed node was in a middle of a tree
%     'multiple split' - the node had more than 2 connections and as result multiple new trees were formed
%

if nargin < 5; orientation = 3; end
if nargin < 3; y = []; z = []; end
result = '';

if isempty(y)
    nodeId = x;
else
    nodeId = [];
end

if isempty(nodeId)
    nodeId = obj.findClosestNode(x, y, z, orientation);
    if isempty(nodeId); return; end     % no node
end

% find edges that connected to this node
edgeIds = unique([find(obj.G.Edges.EndNodes(:,1) == nodeId); find(obj.G.Edges.EndNodes(:,2) == nodeId)]);
if isempty(edgeIds)     % a single not connected node
    obj.G = rmnode(obj.G, nodeId);
    obj.noTrees = obj.noTrees - 1;
    N = nodeId-1;   % N is used at the end of the function to reassign the active node
    result = 'removed tree';
elseif numel(edgeIds) == 2  % node is between other nodes
    affectedEdges = obj.G.Edges(edgeIds,:);
    N = neighbors(obj.G, nodeId);   % find neighboring nodes
    obj.G = rmnode(obj.G, nodeId);

    N(N>nodeId) = N(N>nodeId) - 1;  % decrease N by 1 because the node was removed

    if findedge(obj.G, N(1), N(2)) == 0   % if edge already exist skip formation of a new one
        node1 = N(1);
        node2 = N(2);
        EndNodesClip = affectedEdges(1,:);
        EndNodesClip.EndNodes(1:2) = [node1, node2];
        EndNodesClip.Edges(1:3) = obj.G.Nodes(node1,:).PointsXYZ;
        EndNodesClip.Edges(4:6) = obj.G.Nodes(node2,:).PointsXYZ;
        obj.G = addedge(obj.G, EndNodesClip);

        % recalculate length of edges
        options.nodeId = EndNodesClip.EndNodes;
        obj.G = obj.calculateLengthOfNodes(obj.G, options);
    end
    result = 'middle node';
else    % node is at the end of the graph or between 3 or more nodes
    N = neighbors(obj.G, nodeId);   % find neighboring nodes
    obj.G = rmnode(obj.G, nodeId);

    obj.noTrees = obj.noTrees + numel(N)-1;  % increase tree counter
    % rename tree name for the second part of the splitted graph, add 's' to the end
    if numel(N) > 1   % real split
        bins = conncomp(obj.G);
        for i=2:numel(N)
            newFirstNode = N(i)-1;      % new index of the new node, decreased by one due to remove of the node earlier
            nodesToRenameIds = find(bins == bins(newFirstNode));    % find indices to rename

            obj.G.Nodes.TreeName(nodesToRenameIds) = arrayfun(@(x, y) {sprintf('%ss%d', cell2mat(x), y-1)}, obj.G.Nodes.TreeName(nodesToRenameIds), repmat(i, [numel(nodesToRenameIds), 1]));
        end
    end
    N(N>nodeId) = N(N>nodeId) - 1;  % decrease N by 1 because the node was removed
    result = 'multiple split';
end

% correct the active node
if ~isempty(obj.activeNodeId)
    if obj.activeNodeId == nodeId   % reassign the active node
        obj.activeNodeId = N(1);
    else
        obj.activeNodeId(obj.activeNodeId>nodeId) = obj.activeNodeId(obj.activeNodeId>nodeId) - 1;
    end
    if obj.activeNodeId == 0; obj.activeNodeId = []; end
end

end
