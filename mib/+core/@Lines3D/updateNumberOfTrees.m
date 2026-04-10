function [noTrees, nodeByTree] = updateNumberOfTrees(obj)
% function [noTrees, nodeByTree] = updateNumberOfTrees(obj)
% update number of trees in the graph and get array of nodes by tree index
%
% Parameters:
%
% Return values:
% noTrees: total number of isolated trees of the graph
% nodeByTree: vector of nodes, where values indicate corresponding tree of the node

noTrees = 0;
nodeByTree = [];
if isempty(obj.G); return; end
if isempty(obj.G.Nodes); return; end

nodeByTree = conncomp(obj.G);
noTrees = max(nodeByTree);
obj.noTrees = noTrees;

end
