function saveToFile(obj, filename, options)
% SAVETOFILE - Save the Lines3D graph to a file.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.saveToFile(filename, options)
%
% Saves the graph to a file in one of several supported formats. If ``filename``
% is omitted, a dialog prompts the user to select the filename and format.
%
% Input Arguments:
%   - **filename** - *(optional)* [char] full output path; if ``[]`` or missing, a file dialog opens
%   - **options** - *(optional)* [struct] export settings:
%
%     - ``.format`` - [char] output format; if missing, inferred from file extension:
%
%       - ``'lines3d'`` - MIB native format (MATLAB ``.lines3d`` binary)
%       - ``'amira-ascii'`` - Amira Spatial Graph ASCII format
%       - ``'amira-binary'`` - Amira Spatial Graph binary format
%       - ``'excel'`` - Microsoft Excel ``.xls`` spreadsheet
%
%     - ``.treeId`` - *(optional)* [numeric or []] tree index to export (default: ``[]`` = all trees)
%     - ``.NodeFieldName`` - *(optional)* [char] field name to export for nodes (Amira only)
%     - ``.EdgeFieldName`` - *(optional)* [char] field name to export for edges (Amira only)
%     - ``.showWaitbar`` - *(optional)* [logical] display progress bar (default: ``1``)
%

if nargin < 3; options = struct(); end
if nargin < 2; filename = []; end

if ~isfield(options, 'showWaitbar'); options.showWaitbar = 1; end

% obtain filename if it is not provided
if isempty(filename)
    Filters = {'*.lines3d',  'Matlab format (*.lines3d)';...
        '*.am',   'Amira Spatial Graph ASCII (*.am)';...
        '*.am',   'Amira Spatial Graph BINARY (*.am)';...
        '*.xls',   'Excel format (*.xls)'; };

    [filename, path, FilterIndex] = uiputfile(Filters, 'Save Lines3D...', filename);
    if isequal(filename,0); return; end % check for cancel

    filename = fullfile(path, filename);
    switch Filters{FilterIndex, 2}
        case 'Matlab format (*.lines3d)'
            options.format = 'lines3d';
        case 'Amira Spatial Graph ASCII (*.am)'
            options.format = 'amira-ascii';
        case 'Amira Spatial Graph BINARY (*.am)'
            options.format = 'amira-binary';
        case 'Excel format (*.xls)'
            options.format = 'excel';
    end
end
if options.showWaitbar; wb = waitbar(0, 'Please wait...', 'Name', 'Saving Lines3D', 'WindowStyle','modal'); end
% obtain format if it is not provided
if isempty(options.format)
    [~, ~, ext] = fileparts(filename);
    switch ext
        case '.lines3d'
            options.format = 'lines3d';
        case '.am'
            options.format = 'amira-binary';
        case '.xls'
            options.format = 'excel';
    end
end

% update treeId structure
if ~isfield(options, 'treeId'); options.treeId = []; end

if isempty(options.treeId)
    Graph.G = obj.G;
    Graph.activeNodeId = obj.activeNodeId;
else
    Graph.G = obj.getTree(options.treeId);
    Graph.activeNodeId = size(Graph.G.Nodes, 1);
end
Graph.Settings = obj.getOptions(); %#ok<STRNU>
if options.showWaitbar; waitbar(0.05, wb); end

switch options.format
    case 'lines3d'
        save(filename, 'Graph', '-mat', '-v7.3');
        obj.filename = filename;
    case 'excel'
        warning('off', 'MATLAB:xlswrite:AddSheet');

        % Sheet 1
        s = {sprintf('Lines3D filename: %s', obj.filename)};
        s(4,1) = {'NODES'};

        Variables = obj.G.Nodes.Properties.VariableNames;
        s(6,2) = {'NodeId'}; s(6,3) = {'TreeName'}; s(6,4) = {'NodeName'}; s(6,5) = {'X'}; s(6,6) = {'Y'}; s(6,7) = {'Z'};
        Variables(ismember(Variables, {'PointsXYZ', 'TreeName', 'NodeName'})) = [];
        s(6,8:8+numel(Variables)-1) = Variables;

        % sheet 2
        s2 = {sprintf('Lines3D filename: %s', obj.filename)};
        s2(4,1) = {'EDGES'};

        Variables = obj.G.Edges.Properties.VariableNames;
        s2(6,2) = {'EndNode1'}; s2(6,3) = {'EndNode2'}; s2(6,4) = {'EndNode1Name'}; s2(6,5) = {'EndNode2Name'};
        s2(6,6) = {'Weight'}; s2(6,7) = {'Length'};
        Variables(ismember(Variables, {'EndNodes', 'Weight', 'Length', 'Edges'})) = [];
        s2(6,8:8+numel(Variables)-1) = Variables;

        dy1 = 8;
        dy2 = 8;
        if options.showWaitbar; waitbar(.1, wb); end

        if isempty(options.treeId)
            treeIds = 1:obj.noTrees;
        else
            treeIds = options.treeId;
        end
        for treeId = treeIds
            if treeId > obj.noTrees; error('the treeId is too large'); end
            [~, nodeIds, EdgesTable, NodesTable] = obj.getTree(treeId);
            TreeName = NodesTable.TreeName(1,:);
            s(dy1, 1) = TreeName;
            noRows = size(NodesTable, 1);
            s(dy1:dy1+noRows-1, 2) = num2cell(nodeIds);
            s(dy1:dy1+noRows-1, 3) = NodesTable.TreeName;
            s(dy1:dy1+noRows-1, 4) = NodesTable.NodeName;
            s(dy1:dy1+noRows-1, 5:7) = [num2cell(NodesTable.PointsXYZ(:,1)), num2cell(NodesTable.PointsXYZ(:,2)), num2cell(NodesTable.PointsXYZ(:,3))];
            NodesTable.TreeName = [];
            NodesTable.NodeName = [];
            NodesTable.PointsXYZ = [];
            [~, noCols] = size(NodesTable);
            s(dy1:dy1+noRows-1, 8:8+noCols-1) = table2cell(NodesTable);
            dy1 = dy1 + noRows;

            s2(dy2, 1) = TreeName;
            noRows = size(EdgesTable, 1);
            s2(dy2:dy2+noRows-1, 2) = num2cell(EdgesTable.EndNodes(:,1));
            s2(dy2:dy2+noRows-1, 3) = num2cell(EdgesTable.EndNodes(:,2));
            s2(dy2:dy2+noRows-1, 4) = obj.G.Nodes.NodeName(EdgesTable.EndNodes(:,1));
            s2(dy2:dy2+noRows-1, 5) = obj.G.Nodes.NodeName(EdgesTable.EndNodes(:,2));
            s2(dy2:dy2+noRows-1, 6) = num2cell(EdgesTable.Weight);
            s2(dy2:dy2+noRows-1, 7) = num2cell(EdgesTable.Length);
            EdgesTable.EndNodes = [];
            EdgesTable.Weight = [];
            EdgesTable.Length = [];
            EdgesTable.Edges = [];  % do not save Edges
            [~, noCols] = size(EdgesTable);
            s2(dy2:dy2+noRows-1, 8:8+noCols-1) = table2cell(EdgesTable);
            dy2 = dy2 + noRows;
        end

        if options.showWaitbar; waitbar(.2, wb); end
        xlswrite2(filename, s, 'Nodes', 'A1');
        if options.showWaitbar; waitbar(.7, wb); end
        xlswrite2(filename, s2, 'Edges', 'A1');
    case {'amira-ascii', 'amira-binary'}
        if strcmp(options.format, 'amira-ascii')
            amiraOptions.format = 'ascii';
        else
            amiraOptions.format = 'binary';
        end
        amiraOptions.overwrite = 1;

        extraNodeFieldsLocal = [];
        extraEdgeFieldsLocal = [];

        if ~isempty(obj.extraNodeFields)
            extraNodeFieldsLocal = obj.extraNodeFields(obj.extraNodeFieldsNumeric>0);
        end
        if ~isempty(obj.extraEdgeFields)
            extraEdgeFieldsLocal = obj.extraEdgeFields(obj.extraEdgeFieldsNumeric>0);
        end

        if ~isempty(extraEdgeFieldsLocal) || ~isempty(extraNodeFieldsLocal)
            if ~isfield(options, 'NodeFieldName') || ~isfield(options, 'EdgeFieldName')
                % add default fields
                extraEdgeFieldsLocal = [{'Length'; 'Weight'}; extraEdgeFieldsLocal];
                extraNodeFieldsLocal = [{'Radius'}; extraNodeFieldsLocal];

                if numel(extraNodeFieldsLocal) < 2
                    prompts = {'Field for nodes:'; 'Field for edges:'};
                    defAns = {[extraNodeFieldsLocal; 1]; extraEdgeFieldsLocal};
                else
                    prompts = {'First field for nodes:'; 'Second field for nodes:'; 'Field for edges:'};
                    defAns = {[extraNodeFieldsLocal; 1]; ...
                        [extraNodeFieldsLocal; 1]; ...
                        extraEdgeFieldsLocal};
                end
                dlgTitle = 'Export to Amira';
                dlgOptions.WindowStyle = 'normal';
                dlgOptions.HeaderLines = 2;
                dlgOptions.Focus = 1;
                dlgHeader = sprintf('Select fields to export\n(only numerical fields can be exported)');
                [answer, selIndex] = utils.dlgs.inputUniversalDlg([], dlgHeader, prompts, defAns, dlgTitle, dlgOptions);
                if isempty(answer); return; end
                if numel(extraNodeFieldsLocal) < 2
                    outputFieldNode = extraNodeFieldsLocal(selIndex(1));
                    outputFieldEdge = extraEdgeFieldsLocal(selIndex(2));
                else
                    outputFieldNode = [extraNodeFieldsLocal(selIndex(1)); extraNodeFieldsLocal(selIndex(2))];
                    outputFieldEdge = extraEdgeFieldsLocal(selIndex(3));
                end
            else
                outputFieldNode = options.NodeFieldName;
                outputFieldEdge = options.EdgeFieldName;
            end
        else
            outputFieldNode = {'Radius'};
            outputFieldEdge = {'Weight'};
            if isfield(options, 'EdgeFieldName')
                if strcmp(options.EdgeFieldName, 'Length')
                    outputFieldEdge = {'Length'};
                end
            end
        end
        amiraOptions.NodeFieldName = outputFieldNode;
        amiraOptions.EdgeFieldName = outputFieldEdge;
        if options.showWaitbar; waitbar(.1, wb); end

        Graph.G.Nodes.XData = Graph.G.Nodes.PointsXYZ(:,1);
        Graph.G.Nodes.YData = Graph.G.Nodes.PointsXYZ(:,2);
        Graph.G.Nodes.ZData = Graph.G.Nodes.PointsXYZ(:,3);
        Graph.G.Nodes.PointsXYZ = [];   % remove PointsXYZ

        % generate points for edge segments
        Graph.G.Edges.Points = repmat({zeros([2 6])}, [size(Graph.G.Edges,1) 1]);
        if options.showWaitbar; waitbar(.2, wb); end
        for edgeId = 1:size(Graph.G.Edges,1)
            id1 = Graph.G.Edges.EndNodes(edgeId,1);
            id2 = Graph.G.Edges.EndNodes(edgeId,2);
            Graph.G.Edges.Points{edgeId, :} = ...
                [Graph.G.Nodes.XData([id1 id2]), Graph.G.Nodes.YData([id1 id2]), Graph.G.Nodes.ZData([id1 id2])];
        end
        if options.showWaitbar; waitbar(.3, wb); end
        io.AmiraMesh.graph2amiraSpatialGraph(filename, Graph.G, amiraOptions);
    otherwise
end
if options.showWaitbar; waitbar(1, wb); end
if options.showWaitbar; delete(wb); end

end
