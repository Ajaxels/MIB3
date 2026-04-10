function addNode(obj, x, y, z, newTreeSwitch, options)
% function addNode(obj, x, y, z, newTreeSwitch, options)
% add a new node(s) to the graph; when x,y,z are columns of
% coordinates they are considered to be connected with edges
%
% Parameters:
% x: a column of x coordinates of nodes (in physical units)
% y: a column of y coordinates of nodes (in physical units)
% z: a column of z coordinates of nodes (in physical units)
% newTreeSwitch: an optional switch to start a new tree
% options: a structure with optional parameters
%  .pixSize - structure with pixel sizes of the dataset
%  .BoundingBox - a vector with the bounding box information [xmin, width, ymin, height, zmin, depth]

if nargin < 6; options = struct(); end
if nargin < 5; newTreeSwitch = 0; end
if isempty(obj.activeNodeId); newTreeSwitch = 1; end

if isempty(obj.G) || isempty(obj.G.Nodes)
    newTreeSwitch = 1;
    numNodes = 0;
    %NodeTable = table({[]},{[]},{[]},{[]}, 'VariableNames',{'PointsXYZ','TreeName','NodeName','Radius'});
    %EdgeTable = table({[]},{[]},{[]}, 'VariableNames',{'EndNodes', 'Edges', 'Weight'});
    obj.G = graph();
else
    numNodes = size(obj.G.Nodes, 1);     % number of nodes in the existing graph
end

numBranchNodes = numel(x);    % number of nodes in the branch
nodeFields = obj.G.Nodes.Properties.VariableNames;

if newTreeSwitch == 0   % add node to existing tree
    s = [obj.activeNodeId, numNodes+1:numNodes+numBranchNodes-1];     % input nodes
    t = numNodes+1:numNodes+numBranchNodes;                           % output nodes

    % add the coordinates of the active node to x, y, z
    x = [obj.G.Nodes.PointsXYZ(obj.activeNodeId, 1); x];
    y = [obj.G.Nodes.PointsXYZ(obj.activeNodeId, 2); y];
    z = [obj.G.Nodes.PointsXYZ(obj.activeNodeId, 3); z];

    NewTreeName = repmat(obj.G.Nodes.TreeName(obj.activeNodeId), [numBranchNodes, 1]);
    NodeName = repmat(obj.G.Nodes.NodeName(obj.activeNodeId), [numBranchNodes, 1]);
    Radius = zeros([numBranchNodes, 1]) + obj.G.Nodes.Radius(obj.activeNodeId);
    Weights = zeros([numel(s), 1])+1;

    NodeProps = table([x(2:end) y(2:end) z(2:end)], NewTreeName, NodeName, Radius, ...
        'VariableNames', {'PointsXYZ', 'TreeName', 'NodeName', 'Radius'});
else  % add node to a new tree
    obj.noTrees = obj.noTrees + 1;  % increase counter of trees
    s = numNodes+1:numNodes+numBranchNodes-1;     % input nodes
    t = numNodes+2:numNodes+numBranchNodes;       % output nodes
    Weights = zeros([numel(s), 1])+1;

    % find name for a new tree
    treeNameFound = 0;
    treeCounter = 1;
    treeNames = obj.getTreeNames();
    while treeNameFound == 0
        NewTreeName = sprintf('%s_%.5d', obj.defaultTreeName, treeCounter);
        if ~ismember(NewTreeName, treeNames)
            treeNameFound = 1;
        else
            treeCounter = treeCounter + 1;
        end
    end
    NewTreeName = repmat({NewTreeName}, [numBranchNodes, 1]);
    NodeName = repmat({obj.defaultNodeName}, [numBranchNodes, 1]);
    Radius = ones([numBranchNodes, 1]);

    NodeProps = table([x y z], NewTreeName, NodeName, Radius, ...
        'VariableNames', {'PointsXYZ', 'TreeName', 'NodeName', 'Radius'});
end

% add additional fields to Nodes
for fieldId=1:numel(obj.extraNodeFields)
    if obj.extraNodeFieldsNumeric(fieldId)
        valVec = zeros([numel(NewTreeName), 1]);
    else
        valVec = repmat({''}, [numel(NewTreeName), 1]);
    end
    NodeProps.(obj.extraNodeFields{fieldId}) = valVec;
end

obj.G = addnode(obj.G, NodeProps);

% add/update pixSize structure
if isfield(options, 'pixSize')
    obj.G.Nodes.Properties.UserData.pixSize = options.pixSize;
end
% add/update BoundingBox structure
if isfield(options, 'BoundingBox')
    obj.G.Nodes.Properties.UserData.BoundingBox = options.BoundingBox;
end

% add edge(s) field that describe each edge
if numel(s) > 0
    EdgesVec = zeros([numel(s), 6]);
    LengthVec = zeros([numel(s), 1]);
    for edge = 1:numel(s)
        EdgesVec(edge,:) = [x(edge), y(edge), z(edge), x(edge+1), y(edge+1), z(edge+1)];
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
else
    obj.activeNodeId = size(obj.G.Nodes, 1);
end

end
