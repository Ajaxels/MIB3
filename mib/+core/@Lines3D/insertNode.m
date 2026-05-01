function insertNode(obj, nodeId, x, y, z)
% INSERTNODE - insert node to a tree after nodeId, the inserted node becomes an active node.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.insertNode(nodeId, x, y, z)
%
% Input Arguments:
%   - **nodeId** — index of the node after which a new node should be inserted
%   - **x** — new x coordinate
%   - **y** — new y coordinate
%   - **z** — new z coordinate
%

if nargin < 5; error('not enough parameters!'); end
if isempty(obj.G); return; end

% modify nodes
NodesTable = obj.G.Nodes;
NodesTable = [NodesTable(1:nodeId,:); NodesTable(nodeId,:); NodesTable(nodeId+1:end,:)];
NodesTable.PointsXYZ(nodeId+1,:) = [x, y, z];

% modify edges
EdgesTable = obj.G.Edges;
EdgesTable.EndNodes(EdgesTable.EndNodes(:,1)>nodeId,1) = EdgesTable.EndNodes(EdgesTable.EndNodes(:,1)>nodeId,1) + 1;
EdgesTable.EndNodes(EdgesTable.EndNodes(:,2)>nodeId,2) = EdgesTable.EndNodes(EdgesTable.EndNodes(:,2)>nodeId,2) + 1;

% find index of the edge where to insert the node
edgeIndex = find(EdgesTable.EndNodes(:,1)==nodeId);
if isempty(edgeIndex)   % the active node is the last one in the tree
    errordlg(sprintf('!!! Error !!!\n\nThis active point is the last point of the tree, use the add node function instead or select a previous node'),'End of tree node');
    return;
end
if numel(edgeIndex) > 1     % the active node is a branch node of multiple edges
    errordlg(sprintf('!!! Error !!!\n\nThe active node is a branch node for multiple edges!\nPlease select another node'),'Too many input nodes');
    return;
end

% modify the edges table
EdgesTable(end+1,:) = EdgesTable(edgeIndex,:);
EdgesTable.EndNodes(end,1) = nodeId+1;
EdgesTable.Edges(end, 1:3) = NodesTable.PointsXYZ(nodeId+1,:);

EdgesTable.EndNodes(edgeIndex,2) = nodeId+1;
EdgesTable.Edges(edgeIndex, 4:6) = NodesTable.PointsXYZ(nodeId+1,:);

% recalculate the graph
obj.G = graph(EdgesTable, NodesTable);
obj.activeNodeId = nodeId + 1;
% recalculate length of edges
options.nodeId = [nodeId, nodeId+1];
obj.G = obj.calculateLengthOfNodes(obj.G, options);

end
