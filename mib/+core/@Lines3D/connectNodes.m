function connectNodes(obj, s, t)
% function connectNodes(obj, s, t)
% make an edge between two nodes
%
% Parameters:
% s: index of the first node
% t: index of the second node

if nargin < 3; error('not enough parameters!'); end

noNodes = size(obj.G.Nodes,1);
if max([s, t]) > noNodes
    error('graph does not have that many nodes!');
end

GidxOut = findedge(obj.G, s, t);
if GidxOut > 0
    return; % nodes are already connected
end

EdgesVec = zeros([numel(s), 6]);
LengthVec = zeros([numel(s), 1]);
Weights = zeros([numel(s), 1])+1;
for edge = 1:numel(s)
    EdgesVec(edge,:) = [obj.G.Nodes.PointsXYZ(s,:), obj.G.Nodes.PointsXYZ(t,:)];
end

% make table with edges
Table = table([s', t'], EdgesVec, Weights, LengthVec, 'VariableNames', {'EndNodes', 'Edges', 'Weight', 'Length'});

% add additional fields to Edges
for fieldId=1:numel(obj.extraEdgeFields)
    if obj.extraEdgeFieldsNumeric(fieldId)
        valVec = zeros([numel(Weights), 1]);
    else
        valVec = repmat({''}, [numel(Weights), 1]);
    end
    Table.(obj.extraEdgeFields{fieldId}) = valVec;
end

% rearrange the table so that the variable names match those in the obj.G.Edges table
% do not resort when adding the first edge
if numel(obj.G.Edges.Properties.VariableNames) > 1
    Table = Table(:, obj.G.Edges.Properties.VariableNames);
end

obj.G = addedge(obj.G, Table);
obj.activeNodeId = t(end);   % define the active node

% recalculate length of edges
options.nodeId = Table.EndNodes;
obj.G = obj.calculateLengthOfNodes(obj.G, options);

currentNumberOfTrees = obj.noTrees;
[numTrees, ~] = obj.updateNumberOfTrees();
if currentNumberOfTrees ~= numTrees
    % update number of trees and TreeNames
    obj.noTrees = numTrees;
    treeNameS = obj.G.Nodes.TreeName(s(1));
    treeNameT = obj.G.Nodes.TreeName(t(1));
    % rename tree names of the target to source
    obj.G.Nodes.TreeName(ismember(obj.G.Nodes.TreeName, treeNameT)) = treeNameS;
end

end
