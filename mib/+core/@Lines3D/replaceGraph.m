function replaceGraph(obj, Graph)
% REPLACEGRAPH - Replace the graph object with a new graph.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.replaceGraph(Graph)
%
% Replaces the current graph with a new one, normalizing node and edge structure,
% converting pixel coordinates to physical units if needed, and calculating missing
% metadata fields.
%
% Input Arguments:
%   - **Graph** - *(optional)* [graph] a MATLAB ``graph`` object containing the new data; if ``[]`` or missing, clears the graph.
%     The graph should have the following structure:
%
%     - ``.Nodes`` - table containing node information:
%
%       - ``.PointsXYZ`` - [required] matrix ``[NodeId × 3]`` with ``(x, y, z)`` coordinates IN PHYSICAL UNITS;
%         use ``mibImage.convertPixelsToUnits`` to convert from pixels
%       - ``.TreeName`` - *(optional)* cell array assigning each node to a tree
%       - ``.NodeName`` - *(optional)* cell array with individual node names
%       - ``.Radius`` - *(optional)* vector with radius parameter for each node
%       - ``.Properties.UserData.pixSize`` - struct with pixel size fields ``.x``, ``.y``, ``.z``, ``.units``
%       - ``.Properties.UserData.BoundingBox`` - vector ``[xmin, width, ymin, height, zmin, depth]``
%       - ``.Properties.VariableUnits`` - cell array indicating units; specify ``'pixel'`` when coordinates are in pixels
%
%     - ``.Edges`` - table containing edge information:
%
%       - ``.EndNodes`` - [required] connectivity table ``[EdgeId × 2]`` with ``(Node1, Node2)`` indices
%       - ``.Edges`` - *(optional)* matrix ``[EdgeId × 6]`` with coordinates ``[x1, y1, z1, x2, y2, z2]`` IN PHYSICAL UNITS
%       - ``.Weight`` - *(optional)* vector of edge weights
%       - ``.Length`` - *(optional)* vector of edge lengths IN PHYSICAL UNITS
%

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
    bb      = Graph.Nodes.Properties.UserData.BoundingBox;
    pixSize = Graph.Nodes.Properties.UserData.pixSize;
    % XY orientation (3) assumed - mirrors MibDataset.convertPixelsToUnits with orientation=3
    Graph.Nodes.PointsXYZ(:,1) = Graph.Nodes.PointsXYZ(:,1) * pixSize.x + bb(1);
    Graph.Nodes.PointsXYZ(:,2) = Graph.Nodes.PointsXYZ(:,2) * pixSize.y + bb(3);
    Graph.Nodes.PointsXYZ(:,3) = Graph.Nodes.PointsXYZ(:,3) * pixSize.z + bb(5) - pixSize.z;

    Graph.Nodes.Properties.VariableUnits{1} = pixSize.units;
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
