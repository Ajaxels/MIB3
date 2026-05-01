classdef Lines3D < matlab.mixin.Copyable
    % LINES3D - Container for 3D lines and skeletons represented as a MATLAB graph object.
    %
    % The Lines3D class manages spatial networks of nodes and edges using MATLAB's
    % built-in ``graph`` object, supporting visualization, editing, and file I/O of
    % 3D skeletal structures (trees, filaments, networks).
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
        % % declaration of functions in the external files
        % img = addLinesToImage(obj, img, Box, options)    % add lines to the image; returns img with fused lines
        % 
        % addNode(obj, x, y, z, newTreeSwitch, options)   % add a new node(s) to the graph
        % 
        % Graph = calculateLengthOfNodes(obj, Graph, options)  % calculate/update edge lengths in the graph
        % 
        % clearContents(obj)                               % set all elements of the class to default values
        % 
        % [edge, edgeIds] = clipEdge(obj, Box)             % clip edges using a bounding box
        % 
        % connectNodes(obj, s, t)                          % make an edge between two nodes
        % 
        % result = deleteNode(obj, x, y, z, orientation)   % delete node closest to (x,y,z); returns result string
        % 
        % deleteTree(obj, treeId)                          % delete tree from the graph by index or name
        % 
        % nodeId = findClosestNode(obj, x, y, z, orientation)  % find the closest node to a point
        % 
        % [nodes, indices] = findSliceNodes(obj, z, orientation)  % find nodes shown on the current slice
        % 
        % options = getOptions(obj)                        % get display/rendering options of the class
        % 
        % [Graph, nodeIds, EdgesTable, NodesTable] = getTree(obj, treeId)  % return subgraph for a single tree
        % 
        % treeNames = getTreeNames(obj, index)             % return names of trees
        % 
        % insertNode(obj, nodeId, x, y, z)                 % insert a node after nodeId; inserted node becomes active
        % 
        % makeDummyGraph(obj)                              % generate a dummy graph for developmental purposes
        % 
        % replaceGraph(obj, Graph)                         % replace the current graph object with a new graph
        % 
        % saveToFile(obj, filename, options)               % save Lines3D to a file (lines3d/amira/excel)
        % 
        % setActiveNode(obj, x, y, z, orientation)         % set the node closest to (x,y,z) as the active node
        % 
        % setOptions(obj, options)                         % update display/rendering options of the class
        % 
        % splitAtNode(obj, x, y, z, orientation)           % split tree at the node closest to (x,y,z)
        % 
        % [noTrees, nodeByTree] = updateNumberOfTrees(obj) % update noTrees count and return nodeByTree vector
        % 
        % updateNodeCoordinate(obj, nodeId, x, y, z)       % update coordinates of a node and recalculate edges
        % 
        % updateNodeStrel(obj, nodeStrelSize)              % update strel element for rendering nodes as circles

        function obj = Lines3D(Gin, activeNodeId, options)
            % LINES3D - Constructor for the Lines3D class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = Lines3D()
            %       obj = Lines3D(Gin)
            %       obj = Lines3D(Gin, activeNodeId, options)
            %
            % Initializes a Lines3D container with a graph of 3D nodes and edges.
            %
            % Input Arguments:
            %   - **Gin** — *(optional)* [graph] a MATLAB ``graph`` object with nodes and edges; must have the following structure:
            %
            %     - ``.Nodes`` — table containing node information:
            %
            %       - ``.PointsXYZ`` — coordinates of nodes ``[NodeId][x, y, z]`` IN PHYSICAL UNITS; use ``mibImage.convertPixelsToUnits`` to convert from pixels
            %       - ``.TreeName`` — cell array with tree name for each node
            %       - ``.NodeName`` — *(optional)* cell array with individual node names
            %       - ``.Radius`` — *(optional)* vector with node radii
            %
            %     - ``.Edges`` — table containing edge information:
            %
            %       - ``.EndNodes`` — connectivity table ``[edgeId][Node1 Node2]`` defining connected node pairs
            %       - ``.Weight`` — *(optional)* weights of edges
            %       - ``.Length`` — *(optional)* length of edges, IN PHYSICAL UNITS
            %
            %     - ``.Nodes.Properties.VariableUnits`` — cell array indicating units for each variable; specify ``'pixel'`` when coordinates are in pixels
            %     - ``.Nodes.Properties.UserData.pixSize`` — struct with pixel size fields ``.x``, ``.y``, ``.z``, ``.units``
            %     - ``.Nodes.Properties.UserData.BoundingBox`` — vector ``[xmin, width, ymin, height, zmin, depth]``
            %
            %   - **activeNodeId** — *(optional)* [numeric] index of the node to set as active; can be ``[]``
            %   - **options** — *(optional)* [struct] display and rendering settings:
            %
            %     - ``.edgeColor`` — [1×3 numeric] color of edges ``[R, G, B]``, range 0–1 (default: ``[1.000, 0.800, 0.502]``)
            %     - ``.edgeThickness`` — [numeric] thickness of edges (default: ``2``)
            %     - ``.nodeColor`` — [1×3 numeric] color of nodes ``[R, G, B]``, range 0–1 (default: ``[1.0000, 1.0000, 0]``)
            %     - ``.nodeActiveColor`` — [1×3 numeric] color of the active node ``[R, G, B]``, range 0–1 (default: ``[1.0000, 0.0000, 0]``)
            %     - ``.nodeRadius`` — [numeric] radius of nodes (default: ``5``)
            %
            % **Example 1** — create a simple graph with points in pixels:
            %
            %   .. code-block:: matlab
            %
            %       points = [303 81 72; 294 90 67; 294 172 56; 290 207 20; ...
            %                 252 268 1; 294 172 40; 387 198 42; 400 252 25; 314 270 19];
            %       s = [1 2 3 4 4 6 7];
            %       t = [2 3 4 5 6 7 8];
            %       Weight = ones([numel(s), 1]);
            %       NodeTable = table(points, 'VariableNames', {'PointsXYZ'});
            %       EdgeTable = table([s', t'], Weight, 'VariableNames', {'EndNodes', 'Weight'});
            %       G = graph(EdgeTable, NodeTable);
            %       G.Nodes.Properties.VariableUnits = {'pixel'};
            %       G.Nodes.Properties.UserData.pixSize = struct('x', 0.013, 'y', 0.013, 'z', 0.03, 'units', 'um');
            %       G.Nodes.Properties.UserData.BoundingBox = obj.mibModel.I{obj.mibModel.id}.getBoundingBox();
            %       obj = core.Lines3D(G);
            %
            % **Example 2** — create a graph with two trees:
            %
            %   .. code-block:: matlab
            %
            %       points = [303 81 72; 294 90 67; 294 172 56; 290 207 20; ...
            %                 252 268 1; 294 172 40; 387 198 42; 400 252 25; 314 270 19];
            %       s = [1 2 3 5 6 7];
            %       t = [2 3 4 6 7 8];
            %       TreeName = [repmat({'TreeName1'}, 4, 1); repmat({'TreeName2'}, 4, 1); {'TreeName2'}];
            %       NodeTable = table(points, TreeName, 'VariableNames', {'PointsXYZ', 'TreeName'});
            %       EdgeTable = table([s', t'], 'VariableNames', {'EndNodes'});
            %       G = graph(EdgeTable, NodeTable);
            %       G.Nodes.Properties.VariableUnits = {'pixel', 'string'};
            %       G.Nodes.Properties.UserData.pixSize = obj.mibModel.I{obj.mibModel.id}.pixSize;
            %       G.Nodes.Properties.UserData.BoundingBox = obj.mibModel.I{obj.mibModel.id}.getBoundingBox();
            %       obj = core.Lines3D(G);
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
