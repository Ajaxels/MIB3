function [Graph, nodeIds, EdgesTable, NodesTable] = getTree(obj, treeId)
% GETTREE - return graph with the tree specified in treeId.
%
% Syntax:
%   .. code-block:: matlab
%
%       [Graph, nodeIds, EdgesTable, NodesTable] = obj.getTree(treeId)
%
% Input Arguments:
%   - **treeId** — index of tree to get
%
% Output Arguments:
%   - **Graph** — graph object containing tree specified in treeId
%   - **nodeIds** — indices of nodes belonging to this tree
%   - **EdgesTable** — a table with edges that belong to treeId
%   - **NodesTable** — a table with nodes that belong to treeId
%

if nargin < 2; return; end

nodeByTree = conncomp(obj.G);
nodeIds = find(ismember(nodeByTree, treeId));
Graph = subgraph(obj.G, nodeIds);
if nargout > 2
    NodesTable = obj.G.Nodes(nodeIds,:);
    edge1 =  find(ismember(obj.G.Edges.EndNodes(:,1), nodeIds));
    edge2 =  find(ismember(obj.G.Edges.EndNodes(:,2), nodeIds));
    edgeIds = unique([edge1, edge2]);
    EdgesTable = obj.G.Edges(edgeIds,:);
end

end
