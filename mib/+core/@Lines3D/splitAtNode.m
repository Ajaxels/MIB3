function splitAtNode(obj, x, y, z, orientation)
% function splitAtNode(obj, x, y, z, orientation)
% split tree at the node that is closest to the point with coordinates x, y, z
% the node and its edges will be removed
%
% Parameters:
% x: x coordinate of a point next to the node
% y: y coordinate of a point next to the node
% z: z coordinate of a point next to the node
% orientation: [@em optional] a number with orientation of the dataset, 3-yx, 1-xz, 2-yz, default 3

if nargin < 5; orientation = 3; end

nodeId = obj.findClosestNode(x, y, z, orientation);
if isempty(nodeId); return; end     % no node

N = neighbors(obj.G, nodeId);   % find neighboring nodes
obj.G = rmnode(obj.G, nodeId);  % remove node and split the graph
obj.noTrees = obj.noTrees + numel(N)-1;  % increase tree counter

if ~isempty(N)
    obj.activeNodeId = min(N);
else
    if obj.noTrees > 0
        obj.activeNodeId = 1;
    else
        obj.activeNodeId = [];
    end
end

% rename tree name for the second part of the splitted graph, add 's' to the end
if numel(N) > 1   % real split, i.e the deleted node was not on the end of the graph
    N = sort(N);
    bins = conncomp(obj.G);
    for i=2:numel(N)
        newFirstNode = N(i)-1;      % new index of the new node, decreased by one due to remove of the node earlier
        nodesToRenameIds = find(bins == bins(newFirstNode));    % find indices to rename
        treeNameTemplate = obj.G.Nodes.TreeName{nodesToRenameIds(1)};
        underLineIndex = strfind(treeNameTemplate, '_');
        if ~isempty(underLineIndex)
            treeNameTemplate = treeNameTemplate(1:underLineIndex(end)-1);
        end

        % generate a new tree name
        notOk = 1;
        while notOk > 0
            newTreeName = sprintf('%s_%.5d', treeNameTemplate, randi(65535));
            if ~ismember({newTreeName}, obj.G.Nodes.TreeName)
                notOk = 0;
            end
        end

        obj.G.Nodes.TreeName(nodesToRenameIds) = repmat({newTreeName}, [numel(nodesToRenameIds), 1]);
    end
end

% recalculate length of edges
obj.G = obj.calculateLengthOfNodes(obj.G);

end
