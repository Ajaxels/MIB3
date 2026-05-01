function treeNames = getTreeNames(obj, index)
% GETTREENAMES - return name of trees.
%
% Syntax:
%   .. code-block:: matlab
%
%       treeNames = obj.getTreeNames(index)
%
% Input Arguments:
%   - **index** — *(optional)* indices of the trees
%
% Output Arguments:
%   - **treeNames** — a cell array with names of trees
%

if nargin < 2; index = []; end
if isempty(obj.G.Nodes); treeNames = []; return; end

treeNames = unique(obj.G.Nodes.TreeName, 'stable');     % 'stable' - do not sort the results
if ~isempty(index)
    treeNames = treeNames(index);
end

end
