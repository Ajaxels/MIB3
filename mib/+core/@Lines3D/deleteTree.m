function deleteTree(obj, treeId)
% DELETETREE - delete tree from the graph.
%
% Syntax:
%   function deleteTree(obj, treeId)
%
% Input Arguments:
%   - **treeId** — index of the tree to delete, or string with name of the tree
%

if nargin < 2; error('treeId is missing!'); end

nodeByTree = conncomp(obj.G); % get tree ids for each node

% find indices of trees to remove
if ~isnumeric(treeId)
    treeNames = obj.getTreeNames();
    if ischar(treeId); treeId = cellstr(treeId); end   % convert char to cell
    treeId = find(ismember(treeNames, treeId));
end
nodeIDs = find(ismember(nodeByTree, treeId));

% make sure that the active node preserved
if ~isempty(obj.activeNodeId)
    if ismember(obj.activeNodeId, nodeIDs) % active node belongs to a tree to delete
        obj.activeNodeId = [];
        activeTreeName = [];
    else
        activeTreeName = obj.G.Nodes.TreeName(obj.activeNodeId);
    end
end

obj.G = rmnode(obj.G, nodeIDs);
obj.noTrees = obj.noTrees - 1;

% find index of a new active tree
if ~isempty(activeTreeName)
    obj.activeNodeId = find(ismember(obj.G.Nodes.TreeName, activeTreeName), 1, 'last');
else
    obj.activeNodeId = size(obj.G.Nodes,1);
end

end
