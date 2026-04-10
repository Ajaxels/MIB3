function treeNames = getTreeNames(obj, index)
% function treeNames = getTreeNames(obj, index)
% return name of trees
%
% Parameters:
% index: [@em optional] indices of the trees
%
% Return values:
% treeNames: a cell array with names of trees

if nargin < 2; index = []; end
if isempty(obj.G.Nodes); treeNames = []; return; end

treeNames = unique(obj.G.Nodes.TreeName, 'stable');     % 'stable' - do not sort the results
if ~isempty(index)
    treeNames = treeNames(index);
end

end
