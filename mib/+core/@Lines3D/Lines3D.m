classdef Lines3D < matlab.mixin.Copyable
    % LINES3D - :class:`Lines3D` class is responsible for keeping 3d lines and skeletons.
    %

    %
    % REQUIREMENTS: Matlab 8.6, R2015b!
    %
    % Updates
    % @code
    %% example how to make a simple graph object, where each node is
    %% encoded in pixels (the graph object requires points to be in the physical units)
    %
    % points = [303 81 72;...
    %           294 90 67;...
    %           294 172 56;...
    %           290 207 20;...
    %           252 268 1;...
    %           294 172 40;...
    %           387 198 42;...
    %           400 252 25;
    %           314 270 19];% coordinates of nodes in pixels, [x, y, z]
    %
    % s = [1 2 3 4 4 6 7];% input node indices
    % t = [2 3 4 5 6 7 8];% output node indices
    %
    % NodeName = repmat({'Node'}, [size(points,1), 1]);% optional names of nodes
    % TreeName = repmat({'TreeName'}, [size(points,1), 1]);% optional names for the trees (tree identity of each point is defined by this tag)
    % Radius = ones([size(points,1), 1]);% add node radius to nodes
    % NumberExtra = ones([size(points,1), 1])+1;% optional, add Extra parameter to nodes
    % StringExtra = repmat({'Comment'}, [size(points,1), 1]);% optional, add Extra parameter to nodes
    %
    % Weight = ones([numel(s), 1]);% optional, add weight to edges
    %
    % NodeTable = table(points, NodeName, Radius, TreeName, NumberExtra, StringExtra, 'VariableNames',{'PointsXYZ','NodeName','Radius',TreeName, 'NumberExtra','StringExtra'});
    % EdgeTable = table([s', t'], Weight, 'VariableNames', {'EndNodes', 'Weight'});
    %
    % G = graph(EdgeTable, NodeTable);% generate the graph
    % G.Nodes.Properties.VariableUnits = {'pixel','string','um','um','string'};% it is important to indicate "pixel" unit for the PointsXYZ field, when using pixels
    %
    % Graph.Nodes.Properties.UserData.pixSize = struct();% required when points are pixels, add pixSize structure
    % Graph.Nodes.Properties.UserData.pixSize.x = .013;
    % Graph.Nodes.Properties.UserData.pixSize.y = .013;
    % Graph.Nodes.Properties.UserData.pixSize.z = .03;
    % Graph.Nodes.Properties.UserData.pixSize.units = 'um';
    % Graph.Nodes.Properties.UserData.BoundingBox = obj.mibModel.I{obj.mibModel.id}.getBoundingBox();% required when points are pixels; add bounding box information
    % @endcode
    %
    % @code
    %% minimalistic example with two trees and points in pixels
    % points = [303 81 72;...
    %           294 90 67;...
    %           294 172 56;...
    %           290 207 20;...
    %           252 268 1;...
    %           294 172 40;...
    %           387 198 42;...
    %           400 252 25;
    %           314 270 19];% coordinates of nodes in pixels, [x, y, z]
    %
    % s = [1 2 3 5 6 7];% input node indices
    % t = [2 3 4 6 7 8];% output node indices
    % TreeName = repmat({'TreeName1'}, [4, 1]);% nodes 1:4 belong to TreeName1, optional names for the trees (tree identity of each point is defined by this tag)
    % TreeName(5:8) = repmat({'TreeName2'}, [4, 1]);% nodes 5:8 belong to TreeName2, optional names for the trees (tree identity of each point is defined by this tag)
    % NodeTable = table(points, TreeName, 'VariableNames',{'PointsXYZ','TreeName'});% make nodes table
    % EdgeTable = table([s', t'], 'VariableNames', {'EndNodes'});% make edges table
    % G = graph(EdgeTable, NodeTable);% generate the graph
    % G.Nodes.Properties.VariableUnits = {'pixel','string'};% it is important to indicate "pixel" unit for the PointsXYZ field, when using pixels
    % G.Nodes.Properties.UserData.BoundingBox = obj.mibModel.I{obj.mibModel.id}.getBoundingBox();% a vector with the bounding box information [xmin, width, ymin, height, zmin, depth]
    % G.Nodes.Properties.UserData.pixSize = obj.mibModel.I{obj.mibModel.id}.pixSize;  % add pixel size
    % obj.mibModel.I{obj.mibModel.id}.hLines3D.replaceGraph(G);% replace the current Lines3D with a new graph
    %

    properties
        G
        % a graph with lines.
        %
        % - ``.Edges`` — a table containing information about edges of the graph:
        %
        %   - ``.EndNodes`` — connectivity table ``[edgeId][Node1 Node2]``, each row defines an edge
        %     with indices of nodes that form the edge
        %   - ``.Edges`` — matrix with coordinates of the edges, ``[edgeId][x1 y1 z1 x2 y2 z2]``, IN PHYSICAL UNITS
        %   - ``.Weight`` — weights of edges
        %   - ``.Length`` — length of nodes, IN PHYSICAL UNITS
        %
        % - ``.Nodes`` — a table containing information about nodes of the graph:
        %
        %   - ``.PointsXYZ`` — coordinates of nodes ``[NodeId][x, y, z]`` IN PHYSICAL UNITS;
        %     to recalculate from pixels to imaging units use ``mibImage.convertPixelsToUnits``
        %   - ``.TreeName`` — a cell array where each node has the name of the tree
        %     to which the node belongs, ``[NodeId]{'TreeName'}``
        %   - ``.NodeName`` — a cell array with names for the nodes, ``[NodeId]{'NodeName'}``
        %   - ``.Radius`` — a vector with radii of nodes
        %   - ``.Properties.VariableUnits`` — a cell array with units for each variable;
        %     when coordinates are 'pixels', MIB suggests recomputing them to image units
        %   - ``.Properties.UserData.pixSize`` — a structure with pixSize of the underlying dataset
        %     (``.x``, ``.y``, ``.z`` — resolution in um/px)
        %   - ``.Properties.UserData.BoundingBox`` — a vector with the bounding box information
        %     ``[xmin, width, ymin, height, zmin, depth]``
        %
        activeNodeId = [];
        % index of the active node
        clipExtraThickness = 1;
        % a number, extend clipping of the edges with additional thickness
        % +/- this number sections
        defaultNodeName = 'Node'
        % default name for nodes
        defaultTreeName = 'Tree'
        % default name for trees
        edgeActiveColor = [0.984, 0.549, 0.000];
        % color of edges for the active tree [R, G, B], from 0 to 1
        edgeColor = [1.000, 0.800, 0.502];
        % color of edges [R, G, B], from 0 to 1
        edgeThickness = 2;
        % thickness of edges
        extraEdgeFields = [];
        % a cell array with names of additional fields in the Edges table of the graph object
        extraEdgeFieldsNumeric = [];
        % a vector with indicator whether the field in extraEdgeFields is numeric (1) or not (0)
        extraNodeFields = [];
        % a cell array with names of additional fields in the Nodes table of the graph object
        extraNodeFieldsNumeric = [];
        % a vector with indicator whether the field in extraNodeFields is numeric (1) or not (0)
        filename = [];
        % filename of the Lines3D file
        nodeActiveColor = [1.0000    0.0000         0];
        % color of the active node [R, G, B], from 0 to 1
        nodeColor = [1.0000    1.0000         0];
        % color of nodes [R, G, B], from 0 to 1
        nodeRadius = 5;
        % radius of nodes
        nodeStrel;
        % strel element for making nodes
        noTrees = 0;
        % number of trees of the graph
        treeLengths
        % total length of each tree, numeric array
    end

    methods
        % declaration of functions in the external files
        img = addLinesToImage(obj, img, Box, options)    % add lines to the image; returns img with fused lines

        addNode(obj, x, y, z, newTreeSwitch, options)   % add a new node(s) to the graph

        Graph = calculateLengthOfNodes(obj, Graph, options)  % calculate/update edge lengths in the graph

        clearContents(obj)                               % set all elements of the class to default values

        [edge, edgeIds] = clipEdge(obj, Box)             % clip edges using a bounding box

        connectNodes(obj, s, t)                          % make an edge between two nodes

        result = deleteNode(obj, x, y, z, orientation)   % delete node closest to (x,y,z); returns result string

        deleteTree(obj, treeId)                          % delete tree from the graph by index or name

        nodeId = findClosestNode(obj, x, y, z, orientation)  % find the closest node to a point

        [nodes, indices] = findSliceNodes(obj, z, orientation)  % find nodes shown on the current slice

        options = getOptions(obj)                        % get display/rendering options of the class

        [Graph, nodeIds, EdgesTable, NodesTable] = getTree(obj, treeId)  % return subgraph for a single tree

        treeNames = getTreeNames(obj, index)             % return names of trees

        insertNode(obj, nodeId, x, y, z)                 % insert a node after nodeId; inserted node becomes active

        makeDummyGraph(obj)                              % generate a dummy graph for developmental purposes

        replaceGraph(obj, Graph)                         % replace the current graph object with a new graph

        saveToFile(obj, filename, options)               % save Lines3D to a file (lines3d/amira/excel)

        setActiveNode(obj, x, y, z, orientation)         % set the node closest to (x,y,z) as the active node

        setOptions(obj, options)                         % update display/rendering options of the class

        splitAtNode(obj, x, y, z, orientation)           % split tree at the node closest to (x,y,z)

        [noTrees, nodeByTree] = updateNumberOfTrees(obj) % update noTrees count and return nodeByTree vector

        updateNodeCoordinate(obj, nodeId, x, y, z)       % update coordinates of a node and recalculate edges

        updateNodeStrel(obj, nodeStrelSize)              % update strel element for rendering nodes as circles

        function obj = Lines3D(Gin, activeNodeId, options)
            % LINES3D - Constructor for the :class:`Lines3D` class.
            %
            % Syntax:
            %   function obj = Lines3D(Gin, activeNodeId, options)
            %
            % Constructor for the Lines3D class. Create a new instance of
            % the class with default parameters
            %
            % Input Arguments:
            %   - **Gin** — *(optional)* graph with 3d lines
            %     .Edges - a table containing information about edges of the graph
            %     .EndNodes - connectivity table [edgeId][Node1 Node2], each row defines an edge
            %     with indices of nodes that form the edge
            %     .Edges - matrix with coordinates of the edges, [edgeId][x1 y1 z1 x2 y2 z2]
            %     .Nodes - a table containing information about nodes of the graph
            %     .PointsXYZ - coordinates of nodes [NodeId][x, y, z]
            %     to recalculate from pixels to the imaging units use mibImage.convertPixelsToUnits
            %     .Properties.UserData.pixSize - pixSize structure
            %     .Properties.UserData.BoundingBox - bounding box [xmin, width, ymin, height, zmin, depth]
            %     .Properties.VariableUnits - a cell array with units for each
            %     variable, when coordinate are 'pixels', MIB suggest recompute
            %     them to image units
            %   - **activeNodeId** — *(optional)* index of the active node, can be *empty*
            %   - **options** — *(optional)* a structure with additional settings
            %     .edgeColor - color of edges [R, G, B], from 0 to 1
            %     .edgeThickness - thickness of edges
            %     .nodeColor - color of nodes [R, G, B], from 0 to 1
            %     .nodeActiveColor - color of the active node [R, G, B], from 0 to 1
            %     .nodeRadius - radius of nodes
            %
            % Output Arguments:
            %   obj - instance of the :class:`Lines3D` class.
            %

            if nargin < 3; options = struct(); end
            if ~isfield(options, 'edgeColor'); options.edgeColor = obj.edgeColor; end
            if ~isfield(options, 'edgeThickness'); options.edgeThickness = obj.edgeThickness; end
            if ~isfield(options, 'nodeColor'); options.nodeColor = obj.nodeColor; end
            if ~isfield(options, 'nodeActiveColor'); options.nodeActiveColor = obj.nodeActiveColor; end
            if ~isfield(options, 'nodeRadius'); options.nodeRadius = obj.nodeRadius; end

            if nargin < 2; activeNodeId = []; end
            if nargin < 1; Gin = []; end

            obj.setOptions(options);

            obj.clearContents();
            if ~isempty(Gin)
                obj.replaceGraph(Gin);
            end
            if ~isempty(activeNodeId); obj.activeNodeId = activeNodeId; end
        end

    end
end
