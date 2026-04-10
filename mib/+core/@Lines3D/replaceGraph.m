function replaceGraph(obj, Graph)
% function replaceGraph(obj, Graph)
% replace the current graph object with a new graph
%
% Parameters:
% Graph: graph object with a new graph, required fields (may have more)
%   .Nodes - a table containing information about nodes of the graph
%       .PointsXYZ - matrix with coordinates of nodes [nodeId](x, y, z) (in physical units)
%           to recalculate from pixels to the imaging units use mibImage.convertPixelsToUnits
%       .TreeName - [@em optional] a cell array where each entry contains name of the node's parant tree
%       .NodeName - [@em optional] a cell array where each entry has name of the corresponding node
%       .Radius - [@em optional] a vector with radius parameter for each node
%   	.[name_of_field] - [@em optional] optional fields as either array of vectors or cells
%       .Properties.UserData.pixSize - a structure with pixSize of the underlying dataset
%               .x - x resoulution, um/px
%               .y - x resoulution, um/px
%               .z - x resoulution, um/px
%       .Properties.UserData.BoundingBox - a vector with the bounding box information [xmin, width, ymin, height, zmin, depth]
%       .Properties.VariableUnits - a cell array with units for each
%               variable, when coordinate are 'pixels', MIB suggest recompute
%               them to image units
%
%   .Edges - a table containing information about edges of the graph
%       .EndNodes - connectivity table [edgeId][Node1 Node2], each row defines an edge
%                   with indices of nodes that form the edge
%       .Edges - [@em optional] a matrix with coordinates of the edges, [edgeId][x1 y1 z1 x2 y2 z2], (in physical units)
%       .Weight - [@em optional] a vector of weights for each edge
%       .Length - [@em optional] a vector of length for each edge (in physical units)

if nargin < 2; obj.clearContents(); return; end

% get provided fields
edgeFields = Graph.Edges.Properties.VariableNames;
nodeFields = Graph.Nodes.Properties.VariableNames;

% update number of trees
nodeByTree = conncomp(Graph);
obj.noTrees = max(nodeByTree);
% define the active node
obj.activeNodeId = size(Graph.Nodes.PointsXYZ, 1);

% % --------- process Nodes -----------
% add TreeName
if ~ismember('TreeName', nodeFields)
    Graph.Nodes.TreeName = cell([size(Graph.Nodes.PointsXYZ, 1), 1]);    % add tree names to nodes
    for treeId = 1:obj.noTrees
        ids = find(nodeByTree == treeId);
        Graph.Nodes.TreeName(ids) = repmat({sprintf('Tree %.5d', treeId)}, [numel(ids), 1]);    % add tree names to nodes
    end
end

% Add node names
if ~ismember('NodeName', nodeFields)
    Graph.Nodes.NodeName = repmat({'Node'}, [size(Graph.Nodes.PointsXYZ, 1), 1]);    % add tree names to nodes
end

% Add Radius
if ~ismember('Radius', nodeFields)
    Graph.Nodes.Radius = ones([size(Graph.Nodes.PointsXYZ,1), 1]);    % add tree names to nodes
end

% adding additional fields
obj.extraNodeFields = nodeFields(~ismember(nodeFields, {'PointsXYZ', 'TreeName', 'NodeName','Radius'}))';
obj.extraNodeFieldsNumeric = zeros([numel(obj.extraNodeFields), 1]);
if ~isempty(obj.extraNodeFields)    % update extraNodeFieldsNumeric variable
    for fieldId = 1:numel(obj.extraNodeFields)
        obj.extraNodeFieldsNumeric(fieldId) = isnumeric(Graph.Nodes.(obj.extraNodeFields{fieldId})(1));
    end
end

% add pixSize structure
if ~isfield(Graph.Nodes.Properties.UserData, 'pixSize')
    Graph.Nodes.Properties.UserData.pixSize = struct();
    Graph.Nodes.Properties.UserData.pixSize.x = 1;
    Graph.Nodes.Properties.UserData.pixSize.y = 1;
    Graph.Nodes.Properties.UserData.pixSize.z = 1;
    Graph.Nodes.Properties.UserData.pixSize.units = 'um';
    Graph.Nodes.Properties.UserData.pixSize.tunits = 's';
end

% add variable units if they are missing
if isempty(Graph.Nodes.Properties.VariableUnits)
    Graph.Nodes.Properties.VariableUnits = repmat(cellstr(''), [numel(Graph.Nodes.Properties.VariableNames), 1]);
end

for varNameId = 1:numel(Graph.Nodes.Properties.VariableNames)
    if isempty(Graph.Nodes.Properties.VariableUnits{varNameId})
        switch Graph.Nodes.Properties.VariableNames{varNameId}
            case {'PointsXYZ', 'Radius'}
                Graph.Nodes.Properties.VariableUnits{varNameId} = Graph.Nodes.Properties.UserData.pixSize.units;
            case {'TreeName', 'NodeName'}
                Graph.Nodes.Properties.VariableUnits{varNameId} = 'string';
            otherwise
                Graph.Nodes.Properties.VariableUnits{varNameId} = '';
        end
    end
end

% recalculate pixels to image units
pointsXYZindex = find(ismember(Graph.Nodes.Properties.VariableNames, 'PointsXYZ'));
if strcmp(Graph.Nodes.Properties.VariableUnits{pointsXYZindex}, 'pixel')
    orientation = 3;    % assuming xy orientation
    [Graph.Nodes.PointsXYZ(:,1), Graph.Nodes.PointsXYZ(:,2), Graph.Nodes.PointsXYZ(:,3)] = ...
        convertPixelsToUnits(Graph.Nodes.PointsXYZ(:,1), Graph.Nodes.PointsXYZ(:,2), Graph.Nodes.PointsXYZ(:,3),...
        Graph.Nodes.Properties.UserData.BoundingBox, Graph.Nodes.Properties.UserData.pixSize, orientation);

    Graph.Nodes.Properties.VariableUnits{1} =  Graph.Nodes.Properties.UserData.pixSize.units;
    if ismember('Edges', Graph.Edges.Properties.VariableNames)
        Graph.Edges.Edges = [];   % remove edges, they will be recalculated in the Lines3D.replaceGraph function
    end
end

% % --------- process Edges -----------
% generate edges matrix
if ~ismember('Edges', edgeFields)
    Graph.Edges.Edges = ...
        [Graph.Nodes.PointsXYZ(Graph.Edges.EndNodes(:,1),:) Graph.Nodes.PointsXYZ(Graph.Edges.EndNodes(:,2),:)];
end

if ~ismember('Weight', edgeFields)
    Graph.Edges.Weight = ones([size(Graph.Edges.EndNodes, 1), 1]);
end

if ~ismember('Length', edgeFields)
    Graph = obj.calculateLengthOfNodes(Graph);
    edgeFields = [edgeFields, 'Length'];
end

% adding additional fields
obj.extraEdgeFields = edgeFields(~ismember(edgeFields, {'EndNodes', 'Edges', 'Weight', 'Length'}))';
obj.extraEdgeFieldsNumeric = zeros([numel(obj.extraEdgeFields), 1]);
if ~isempty(obj.extraEdgeFields)
    for fieldId = 1:numel(obj.extraEdgeFields)
        obj.extraEdgeFieldsNumeric(fieldId) = isnumeric(Graph.Edges.(obj.extraEdgeFields{fieldId})(1));
    end
end

obj.G = Graph;
clear Graph;

end
