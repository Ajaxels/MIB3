function treeNames = getTreeNames(obj, index)
% GETTREENAMES - return name of trees.
%
% Syntax:
%   .. code-block:: matlab
%
%       treeNames = obj.getTreeNames(index)
%
% One name is returned per tree, i.e. per connected component of the graph, so that the
% indices match those used by getTree, deleteTree and the nodeByTree vector of
% updateNumberOfTrees. The name is taken from the first node of each component; the same
% name may be returned more than once when a tree got disconnected without being renamed
% (for example a Delaunay triangulation that left isolated points).
%
% Input Arguments:
%   - **index** - *(optional)* indices of the trees
%
% Output Arguments:
%   - **treeNames** - a cell array with names of trees
%

if nargin < 2; index = []; end
if isempty(obj.G) || isempty(obj.G.Nodes); treeNames = []; return; end

nodeByTree = conncomp(obj.G);
[~, firstNodeOfTree] = unique(nodeByTree, 'first');     % components are numbered 1:noTrees, so unique sorts them by index
treeNames = obj.G.Nodes.TreeName(firstNodeOfTree);
if ~isempty(index)
    treeNames = treeNames(index);
end

end
