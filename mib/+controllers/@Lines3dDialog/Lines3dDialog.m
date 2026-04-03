classdef Lines3dDialog < handle
    % Lines3dDialog is a controller class for the Lines3D table view dialog.
    %
    % Displays and edits 3D line trees, nodes and edges via interactive
    % tables. Opened from the segmentation panel's "Table View" button.
    %
    % @code
    % obj.startController('controllers.Lines3dDialog'); // as GUI tool
    % @endcode

    % Updates
    % ported to MIB3 AppDesigner framework

    properties
        mibModel
        % handle to the MibModel
        view
        % handle to the view / views.Lines3dDialog (core.ChildView)
        listener
        % a cell array with handles to listeners
        hAx = []
        % axes for the 3D visualization figure
        hFig = []
        % a handle to the 3D visualization figure
        hPlot = []
        % a handle to a plot on the 3D visualization figure
        imarisOptions
        % a structure with export options for imaris
        % .radii  - default radius scaling factor
        % .color  - default color [R G B A] in range 0..1
        % .name   - default spot name
        indicesEdges
        % indices of selected cell in edgesViewTable
        indicesNodes
        % indices of selected cell in nodesViewTable
        indicesTrees
        % indices of selected tree in treesViewTable
        childControllers
        % cell array of open child controllers
        childControllersIds
        % cell array of names of open child controllers
    end

    events
        CloseEvent
        % fires when the window is closed; caught by MibController to purge this child
    end

    methods (Static)
        function ViewListner_Callback2(obj, src, evnt)
            % ViewListner_Callback2(obj, src, evnt)
            % Static callback for model event listeners.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener)
                    delete(obj.listener{i});
                end
                return;
            end
            switch evnt.EventName
                case 'UpdatedLines3D'
                    if obj.view.handles.autoRefreshCheck.Value == 0; return; end
                    obj.updateWidgets();
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
                case 'Undo'
                    if strcmp(evnt.Parameters, 'lines3d')
                        obj.updateWidgets();
                    end
            end
        end

        function purgeControllers(obj, src, evnt)
            % purgeControllers(obj, src, evnt)
            % Find and delete a child controller that fired its CloseEvent.
            id = obj.findChildId(class(src));
            delete(obj.childControllers{id});
            obj.childControllers(id) = [];
            obj.childControllersIds(id) = [];
        end
    end

    methods
        function obj = Lines3dDialog(mibModel, varargin)
            % Lines3dDialog(mibModel, varargin)
            % Constructor for the Lines3dDialog controller.
            %
            % Parameters:
            % mibModel: handle to MibModel
            % varargin{1}: controller handle (unused, for startController compatibility)

            obj.mibModel = mibModel;

            obj.imarisOptions.radii = NaN;
            obj.imarisOptions.color = [1 0 0 0];
            obj.imarisOptions.name  = 'mibSpots';

            obj.indicesNodes = 0;
            obj.indicesTrees = 0;
            obj.indicesEdges = [];
            obj.childControllers   = {};
            obj.childControllersIds = {};

            % ---------- initialise GUI ----------
            guiName = 'views.Lines3dDialog';
            obj.view = core.ChildView(obj, guiName);

            obj.addCallbacks();

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.closeBtn.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.closeBtn.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % position window and show
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');
            obj.updateWidgets();
            obj.view.gui.Visible = 'on';

            % register model listeners
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'UpdatedLines3D', ...
                @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{3} = addlistener(obj.mibModel, 'Undo', ...
                @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{4} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % -----------------------------------------------------------------
        function closeWindow(obj)
            % closeWindow(obj)
            % Close the Lines3dDialog window and clean up listeners.
            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------------
        function addCallbacks(obj)
            % addCallbacks(obj)
            % Wire all widget callbacks. Called once from the constructor.

            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            h = obj.view.handles;

            % Tables
            h.treesViewTable.CellEditCallback = ...
                @(~, evt) obj.treesViewTable_CellEditCallback(evt.Indices);
            h.treesViewTable.CellSelectionCallback = ...
                @(~, evt) obj.treesViewTable_CellSelectionCallback(evt.Indices);

            h.nodesViewTable.CellEditCallback = ...
                @(~, evt) obj.nodesViewTable_CellEditCallback(evt);
            h.nodesViewTable.CellSelectionCallback = ...
                @(~, evt) obj.nodesViewTable_CellSelectionCallback(evt.Indices);

            h.edgesViewTable.CellEditCallback = ...
                @(~, evt) obj.edgesViewTable_CellEditCallback(evt);
            h.edgesViewTable.CellSelectionCallback = ...
                @(~, evt) obj.edgesViewTable_CellSelectionCallback(evt.Indices);

            % Buttons
            h.settingsBtn.ButtonPushedFcn  = @(~,~) obj.settingsBtn_Callback();
            h.loadBtn.ButtonPushedFcn      = @(~,~) obj.loadBtn_Callback();
            h.saveBtn.ButtonPushedFcn      = @(~,~) obj.saveBtn_Callback();
            h.deleteBtn.ButtonPushedFcn    = @(~,~) obj.deleteBtn_Callback();
            h.visualizeBtn.ButtonPushedFcn = @(~,~) obj.visualizeBtn_Callback();
            h.refreshBtn.ButtonPushedFcn   = @(~,~) obj.updateWidgets();

            % Dropdowns
            h.tableSelectionPopup.ValueChangedFcn = @(~,~) obj.updateWidgets();
            h.nodesViewAdditionalField.ValueChangedFcn = @(~,~) obj.updateWidgets();
            h.edgesViewAdditionalField.ValueChangedFcn = @(~,~) obj.updateWidgets();

            % Context menus for nodes table
            h.nodesViewTable_cm_Jump.MenuSelectedFcn       = @(~,~) obj.nodesViewTable_cb('Jump');
            h.nodesViewTable_cm_Active.MenuSelectedFcn     = @(~,~) obj.nodesViewTable_cb('Active');
            h.nodesViewTable_cm_Rename.MenuSelectedFcn     = @(~,~) obj.nodesViewTable_cb('Rename');
            h.nodesViewTable_cm_Pixels.MenuSelectedFcn     = @(~,~) obj.nodesViewTable_cb('Pixels');
            h.nodesViewTable_cm_AnnotationsNew.MenuSelectedFcn    = @(~,~) obj.nodesViewTable_cb('AnnotationsNew');
            h.nodesViewTable_cm_AnnotationsAdd.MenuSelectedFcn    = @(~,~) obj.nodesViewTable_cb('AnnotationsAdd');
            h.nodesViewTable_cm_AnnotationsDelete.MenuSelectedFcn = @(~,~) obj.nodesViewTable_cb('AnnotationsDelete');
            h.nodesViewTable_cm_Delete.MenuSelectedFcn     = @(~,~) obj.nodesViewTable_cb('Delete');

            % Context menus for edges table
            h.edgesViewTable_cm_Jump.MenuSelectedFcn   = @(~,~) obj.edgesViewTable_cb('Jump');
            h.edgesViewTable_cm_Active.MenuSelectedFcn = @(~,~) obj.edgesViewTable_cb('Active');

            % Context menus for trees table
            h.treesViewTable_cm_Rename.MenuSelectedFcn    = @(~,~) obj.treesViewTable_cb('rename');
            h.treesViewTable_cm_Find.MenuSelectedFcn      = @(~,~) obj.treesViewTable_cb('find');
            h.treesViewTable_cm_Visualize.MenuSelectedFcn = @(~,~) obj.treesViewTable_cb('visualize');
            h.treesViewTable_cm_Save.MenuSelectedFcn      = @(~,~) obj.treesViewTable_cb('save');
            h.treesViewTable_cm_Delete.MenuSelectedFcn    = @(~,~) obj.treesViewTable_cb('delete');
        end

        % -----------------------------------------------------------------
        function updateWidgets(obj)
            % updateWidgets(obj)
            % Update all tables and status indicators.

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            [dataset.lines3D.noTrees, nodeByTree] = dataset.lines3D.updateNumberOfTrees();
            noTrees = dataset.lines3D.noTrees;

            if noTrees > 0
                N = histcounts(nodeByTree, 0.5:noTrees+.5);
                treeNames = dataset.lines3D.getTreeNames();

                data1 = cell([noTrees, 2]);
                data1(:,1) = treeNames;
                data1(:,2) = num2cell(N');
                obj.view.handles.treesViewTable.Data = data1;

                activeTreeName = dataset.lines3D.G.Nodes.TreeName(dataset.lines3D.activeNodeId);
                if ~isempty(activeTreeName)
                    activeTreeIndex = find(ismember(treeNames, activeTreeName));

                    curTable = obj.view.handles.tableSelectionPopup.Value;
                    switch curTable
                        case 'Nodes'
                            obj.updateNodesViewTable(activeTreeIndex, nodeByTree);
                        case 'Edges'
                            obj.updateEdgesViewTable(activeTreeIndex, nodeByTree);
                    end

                    obj.view.handles.activeTreeText.Text = sprintf('Active tree: %d', activeTreeIndex);
                    obj.view.handles.activeNodeText.Text = sprintf('Active node: %d', dataset.lines3D.activeNodeId);
                end
            else
                obj.view.handles.treesViewTable.Data = {};
                obj.view.handles.nodesViewTable.Data = {};
                obj.view.handles.edgesViewTable.Data = {};
                obj.view.handles.activeTreeText.Text = 'Active tree: None';
                obj.view.handles.activeNodeText.Text = 'Active node: None';
            end
        end

        % -----------------------------------------------------------------
        function updateEdgesViewTable(obj, activeTreeIndex, nodeByTree)
            % updateEdgesViewTable(obj, activeTreeIndex, nodeByTree)
            % Update the edges table for the given tree.

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            if nargin < 3; [~, nodeByTree] = dataset.lines3D.updateNumberOfTrees(); end
            if nargin < 2; activeTreeIndex = obj.indicesTrees; end

            extraFields = [{'Weight'}; dataset.lines3D.extraEdgeFields];
            extraFieldsValue = obj.view.handles.edgesViewAdditionalField.Value;
            if ~ismember(extraFieldsValue, extraFields)
                extraFieldsValue = extraFields{1};
            end
            obj.view.handles.edgesViewAdditionalField.Items = extraFields';
            obj.view.handles.edgesViewAdditionalField.Value = extraFieldsValue;
            extraParameter = extraFieldsValue;

            NodesId = find(nodeByTree == activeTreeIndex);
            EdgeIds = find(ismember(dataset.lines3D.G.Edges.EndNodes(:,1), NodesId));

            data2 = cell([numel(EdgeIds), 4]);
            if ~isempty(EdgeIds)
                data2(:,1) = num2cell(dataset.lines3D.G.Edges.EndNodes(EdgeIds,1));
                data2(:,2) = num2cell(dataset.lines3D.G.Edges.EndNodes(EdgeIds,2));
                if isnumeric(dataset.lines3D.G.Edges.(extraParameter)(EdgeIds(1)))
                    obj.view.handles.edgesViewTable.ColumnFormat{3} = 'numeric';
                    data2(:,3) = num2cell(dataset.lines3D.G.Edges.(extraParameter)(EdgeIds));
                else
                    obj.view.handles.edgesViewTable.ColumnFormat{3} = 'char';
                    data2(:,3) = dataset.lines3D.G.Edges.(extraParameter)(EdgeIds);
                end
                data2(:,4) = num2cell(dataset.lines3D.G.Edges.Length(EdgeIds));
            end
            obj.view.handles.edgesViewTable.Data = data2;
            obj.view.handles.edgesViewTable.RowName = EdgeIds;
            obj.view.handles.edgesViewTable.ColumnName{3} = extraParameter;
        end

        % -----------------------------------------------------------------
        function activeIndex = updateNodesViewTable(obj, activeTreeIndex, nodeByTree)
            % activeIndex = updateNodesViewTable(obj, activeTreeIndex, nodeByTree)
            % Update the nodes table for the given tree.

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            if nargin < 3; [~, nodeByTree] = dataset.lines3D.updateNumberOfTrees(); end
            if nargin < 2; activeTreeIndex = obj.indicesTrees; end

            extraFields = [{'Radius'}; dataset.lines3D.extraNodeFields];
            extraFieldsValue = obj.view.handles.nodesViewAdditionalField.Value;
            if ~ismember(extraFieldsValue, extraFields)
                extraFieldsValue = extraFields{1};
            end
            obj.view.handles.nodesViewAdditionalField.Items = extraFields';
            obj.view.handles.nodesViewAdditionalField.Value = extraFieldsValue;
            extraParameter = extraFieldsValue;

            NodesId = find(nodeByTree == activeTreeIndex);
            data2 = cell([numel(NodesId), 5]);
            data2(:,1) = dataset.lines3D.G.Nodes.NodeName(NodesId);
            if isnumeric(dataset.lines3D.G.Nodes.(extraParameter)(NodesId(1)))
                obj.view.handles.nodesViewTable.ColumnFormat{2} = 'numeric';
                data2(:,2) = num2cell(dataset.lines3D.G.Nodes.(extraParameter)(NodesId));
            else
                obj.view.handles.nodesViewTable.ColumnFormat{2} = 'char';
                data2(:,2) = dataset.lines3D.G.Nodes.(extraParameter)(NodesId);
            end
            data2(:,3) = num2cell(dataset.lines3D.G.Nodes.PointsXYZ(NodesId, 3));
            data2(:,4) = num2cell(dataset.lines3D.G.Nodes.PointsXYZ(NodesId, 1));
            data2(:,5) = num2cell(dataset.lines3D.G.Nodes.PointsXYZ(NodesId, 2));
            obj.view.handles.nodesViewTable.Data = data2;
            obj.view.handles.nodesViewTable.RowName = num2str(NodesId');
            obj.view.handles.nodesViewTable.ColumnName{2} = extraParameter;

            activeIndex = find(NodesId == dataset.lines3D.activeNodeId);
            if ~isempty(activeIndex)
                try
                    scroll(obj.view.handles.nodesViewTable, 'row', activeIndex);
                catch
                    % scroll not available in older MATLAB versions
                end
            end
        end

        % -----------------------------------------------------------------
        function edgesViewTable_CellEditCallback(obj, eventdata)
            % edgesViewTable_CellEditCallback(obj, eventdata)
            % Callback for modification of cell in edgesViewTable.

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            colId = eventdata.Indices(1,2);
            rowId = eventdata.Indices(1,1);
            edgeId = str2double(obj.view.handles.edgesViewTable.RowName(rowId,:));
            fieldName = obj.view.handles.edgesViewTable.ColumnName(colId);
            if isnumeric(eventdata.NewData)
                dataset.lines3D.G.Edges.(fieldName{1})(edgeId) = eventdata.NewData;
            else
                dataset.lines3D.G.Edges.(fieldName{1}){edgeId} = eventdata.NewData;
            end
        end

        % -----------------------------------------------------------------
        function nodesViewTable_CellEditCallback(obj, eventdata)
            % nodesViewTable_CellEditCallback(obj, eventdata)
            % Callback for modification of cell in nodesViewTable.

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            colId = eventdata.Indices(1,2);
            rowId = eventdata.Indices(1,1);
            nodeIndex = str2double(obj.view.handles.nodesViewTable.RowName(rowId,:));
            fieldName = obj.view.handles.nodesViewTable.ColumnName(colId);
            if colId < 3
                if isnumeric(eventdata.NewData)
                    dataset.lines3D.G.Nodes.(fieldName{1})(nodeIndex) = eventdata.NewData;
                else
                    dataset.lines3D.G.Nodes.(fieldName{1}){nodeIndex} = eventdata.NewData;
                end
            else    % modification of xyz coordinate
                xyzIndex = find(ismember({'x', 'y', 'z'}, fieldName));
                newCoordinates = dataset.lines3D.G.Nodes.PointsXYZ(nodeIndex, :);
                newCoordinates(xyzIndex) = eventdata.NewData; %#ok<FNDSB>
                dataset.lines3D.updateNodeCoordinate(nodeIndex, newCoordinates(1), newCoordinates(2), newCoordinates(3));
                notify(obj.mibModel, 'ShowImage');
            end
        end

        % -----------------------------------------------------------------
        function settingsBtn_Callback(obj)
            % settingsBtn_Callback(obj)
            % Update visual settings for Lines3D.

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};
            settings = dataset.lines3D.getOptions();

            prompts = {'Color for edges:'; 'Color for the active tree:'; ...
                'Color for nodes:'; 'Color for active node:'; ...
                'Edge thickness (1-...):'; 'Node radius (1-...):'; ...
                'Extra clipping (0-...):'};
            defAns = {sprintf('%.3f, %.3f, %.3f', settings.edgeColor(1), settings.edgeColor(2), settings.edgeColor(3)); ...
                sprintf('%.3f, %.3f, %.3f', settings.edgeActiveColor(1), settings.edgeActiveColor(2), settings.edgeActiveColor(3)); ...
                sprintf('%.3f, %.3f, %.3f', settings.nodeColor(1), settings.nodeColor(2), settings.nodeColor(3)); ...
                sprintf('%.3f, %.3f, %.3f', settings.nodeActiveColor(1), settings.nodeActiveColor(2), settings.nodeActiveColor(3)); ...
                sprintf('%d', settings.edgeThickness); ...
                sprintf('%d', settings.nodeRadius); ...
                sprintf('%d', settings.clipExtraThickness)};
            dlgTitle = 'Lines3D Settings';
            options.WindowStyle = 'normal';
            options.PromptLines = [1, 1, 1, 1, 1, 1, 1];
            options.Title = 'For colors use [Red, Green, Blue] format with range between 0-1';
            options.TitleLines = 2;
            options.Columns = 2;
            options.WindowWidth = 1.2;
            options.Focus = 1;
            [answer, ~] = utils.dlgs.inputUniversalDlg(obj.view.gui, prompts, defAns, dlgTitle, options);
            if isempty(answer); return; end

            errorText = '';
            settings2.edgeColor = str2num(answer{1}); %#ok<ST2NM>
            if isempty(settings2.edgeColor); errorText = [errorText '\nWrong edge color']; end
            settings2.edgeActiveColor = str2num(answer{2}); %#ok<ST2NM>
            if isempty(settings2.edgeActiveColor); errorText = [errorText '\nWrong active tree color']; end
            settings2.nodeColor = str2num(answer{3}); %#ok<ST2NM>
            if isempty(settings2.nodeColor); errorText = [errorText '\nWrong node color']; end
            settings2.nodeActiveColor = str2num(answer{4}); %#ok<ST2NM>
            if isempty(settings2.nodeActiveColor); errorText = [errorText '\nWrong active node color']; end
            settings2.edgeThickness = round(str2double(answer{5}));
            if isnan(settings2.edgeThickness) || settings2.edgeThickness < 1; errorText = [errorText '\nWrong edge thickness, should be above 1']; end
            settings2.nodeRadius = round(str2double(answer{6}));
            if isnan(settings2.nodeRadius) || settings2.nodeRadius < 1; errorText = [errorText '\nWrong node radius, should be above 1']; end
            settings2.clipExtraThickness = round(str2double(answer{7}));
            if isnan(settings2.clipExtraThickness) || settings2.clipExtraThickness < 0; errorText = [errorText '\nWrong clipping value, should be above 0']; end
            if ~isempty(errorText)
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_error';
                dlgOpt.Header = sprintf(errorText);
                dlgOpt.HeaderLines = numel(strfind(errorText, '\n')) + 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Error', dlgOpt);
                return;
            end
            dataset.lines3D.setOptions(settings2);
            notify(obj.mibModel, 'ShowImage');
        end

        % -----------------------------------------------------------------
        function loadBtn_Callback(obj)
            % loadBtn_Callback(obj)
            % Load Lines3D from a file or import from Matlab workspace.

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                'Would you like to import 3D lines from a file or from the main Matlab workspace?', ...
                'Import/Load 3D lines', 'Load from a file', 'Import from Matlab', 'Cancel', 'Load from a file');
            switch button
                case 'Cancel'
                    return;
                case 'Import from Matlab'
                    availableVars = evalin('base', 'whos');
                    idx = ismember({availableVars.class}, {'struct', 'graph'});
                    labelsList = {availableVars(idx).name}';
                    idx = find(ismember(labelsList, 'Lines3D') == 1);
                    if ~isempty(idx)
                        labelsList{end+1} = idx;
                    end

                    title = 'Input 3D lines';
                    defAns = {labelsList};
                    prompts = {'Name for structure or graph object with 3D lines:'};
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, prompts, defAns, title);
                    if isempty(answer); return; end

                    Graph = evalin('base', answer{1});
                    obj.mibModel.backup('lines3d');

                    dataset.lines3D.activeNodeId = [];
                    if isa(Graph, 'graph')
                        Lines3D = struct();
                        Lines3D.G = Graph;
                    else
                        Lines3D = Graph;
                        if ~isfield(Lines3D, 'G')
                            dlgOpt.MsgBoxOnly = true;
                            dlgOpt.Icon = 'puffin_error';
                            dlgOpt.Header = sprintf('!!! Error !!!\n\nThe imported structure %s should contain field G with a graph', answer{1});
                            dlgOpt.HeaderLines = 3;
                            utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Wrong format', dlgOpt);
                            return;
                        end
                    end
                case 'Load from a file'
                    [filename, path] = utils.dlgs.mibUiGetFile(...
                        {'*.lines3d;',  'Matlab format (*.lines3d)'; ...
                        '*.*',  'All Files (*.*)'}, ...
                        'Load 3D lines...', obj.mibModel.currentDirectory);
                    if isequal(filename, 0); return; end
                    filename = filename{1};

                    obj.mibModel.backup('lines3d');

                    res = load(fullfile(path, filename), '-mat');
                    fieldsNames = fieldnames(res);
                    Lines3D = res.(fieldsNames{1});
                    dataset.lines3D.filename = fullfile(path, filename);
            end

            pixSize = dataset.image.pixSize;

            recalculateFromPixels = 0;
            if isempty(Lines3D.G.Nodes.Properties.VariableUnits)
                for varNameId = 1:numel(Lines3D.G.Nodes.Properties.VariableNames)
                    switch Lines3D.G.Nodes.Properties.VariableNames{varNameId}
                        case {'PointsXYZ', 'Radius'}
                            Lines3D.G.Nodes.Properties.VariableUnits{varNameId} = pixSize.units;
                        case {'TreeName', 'NodeName'}
                            Lines3D.G.Nodes.Properties.VariableUnits{varNameId} = 'string';
                        otherwise
                            Lines3D.G.Nodes.Properties.VariableUnits{varNameId} = '';
                    end
                end
            else
                pointsXYZindex = find(ismember(Lines3D.G.Nodes.Properties.VariableNames, 'PointsXYZ'));
                if strcmp(Lines3D.G.Nodes.Properties.VariableUnits{pointsXYZindex}, 'pixel') %#ok<FNDSB>
                    button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                        sprintf('Would you like to recalculate points from pixels to the current units?\nNote: all other fields will stay as they are!'), ...
                        'Recalculate coordinates', ...
                        'Recalculate', 'Keep as they are', 'Recalculate');
                    if strcmp(button, 'Recalculate'); recalculateFromPixels = 1; end
                end
            end

            if recalculateFromPixels
                [Lines3D.G.Nodes.PointsXYZ(:,1), Lines3D.G.Nodes.PointsXYZ(:,2), Lines3D.G.Nodes.PointsXYZ(:,3)] = ...
                    dataset.convertPixelsToUnits(Lines3D.G.Nodes.PointsXYZ(:,1), Lines3D.G.Nodes.PointsXYZ(:,2), Lines3D.G.Nodes.PointsXYZ(:,3));
                Lines3D.G.Nodes.Properties.VariableUnits{pointsXYZindex} = pixSize.units;
                if ismember('Edges', Lines3D.G.Edges.Properties.VariableNames)
                    Lines3D.G.Edges.Edges = [];
                end
            end

            Lines3D.G.Nodes.Properties.UserData.pixSize = pixSize;
            Lines3D.G.Nodes.Properties.UserData.BoundingBox = dataset.image.boundingBox;

            dataset.lines3D.replaceGraph(Lines3D.G);

            if isfield(Lines3D, 'Settings')
                dataset.lines3D.setOptions(Lines3D.Settings);
            end
            if isfield(Lines3D, 'activeNodeId')
                dataset.lines3D.activeNodeId = Lines3D.activeNodeId;
            end

            obj.updateWidgets();
            notify(obj.mibModel, 'ShowImage');
            disp('Import lines3D: done!')
        end

        % -----------------------------------------------------------------
        function saveBtn_Callback(obj, treeIds)
            % saveBtn_Callback(obj, treeIds)
            % Save Lines3D to a file or export to Matlab workspace.

            if nargin < 2; treeIds = []; end

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            noTrees = dataset.lines3D.noTrees;
            if noTrees < 1; return; end

            button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                'Would you like to save 3D lines to a file or export to the main Matlab workspace?', ...
                'Export/Save 3D lines', 'Save to a file', 'Export to Matlab', 'Cancel', 'Save to a file');
            if strcmp(button, 'Cancel'); return; end
            if strcmp(button, 'Export to Matlab')
                prompts = {'Please enter name for the structures with the Graph:'};
                defAns = {'Lines3D'};
                answer = utils.dlgs.inputUniversalDlg(obj.view.gui, prompts, defAns, 'Export to Matlab');
                if isempty(answer); return; end

                if isempty(treeIds)
                    Lines3DStruct.G = dataset.lines3D.G;
                    Lines3DStruct.activeNodeId = dataset.lines3D.activeNodeId;
                else
                    Lines3DStruct.G = dataset.lines3D.getTree(treeIds);
                    Lines3DStruct.activeNodeId = size(Lines3DStruct.G.Nodes, 1);
                end
                Lines3DStruct.Settings = dataset.lines3D.getOptions();
                assignin('base', answer{1}, Lines3DStruct);
                fprintf('Export Lines3d: structure ''%s'' with fields .G and .Settings was exported to Matlab!\n', answer{1});
            else
                if isempty(dataset.lines3D.filename)
                    fn_out = dataset.image.sliceName('Filename');
                    [pathStr, fn_out, ~] = fileparts(fn_out);
                    if isempty(pathStr); pathStr = obj.mibModel.currentDirectory; end
                    if isempty(fn_out)
                        fn_out = obj.mibModel.currentDirectory;
                    else
                        fn_out = sprintf('Lines_%s', fn_out);
                        fn_out = fullfile(pathStr, fn_out);
                    end
                else
                    fn_out = dataset.lines3D.filename;
                end

                Filters = {'*.lines3d',  'Matlab format (*.lines3d)'; ...
                    '*.am',   'Amira Spatial Graph ASCII (*.am)'; ...
                    '*.am',   'Amira Spatial Graph BINARY (*.am)'; ...
                    '*.xls',   'Excel format (*.xls)'};
                [filename, pathStr, FilterIndex] = uiputfile(Filters, 'Save Lines3D...', fn_out);
                if isequal(filename, 0); return; end

                fn_out = fullfile(pathStr, filename);

                switch Filters{FilterIndex, 2}
                    case 'Matlab format (*.lines3d)'
                        saveOptions.format = 'lines3d';
                    case {'Amira Spatial Graph ASCII (*.am)', 'Amira Spatial Graph BINARY (*.am)'}
                        if strcmp(Filters{FilterIndex, 2}, 'Amira Spatial Graph ASCII (*.am)')
                            saveOptions.format = 'amira-ascii';
                        else
                            saveOptions.format = 'amira-binary';
                        end

                        extraNodeFields = dataset.lines3D.extraNodeFields;
                        if ~isempty(extraNodeFields)
                            extraNodeFieldsNumeric = dataset.lines3D.extraNodeFieldsNumeric;
                            extraNodeFields = extraNodeFields(extraNodeFieldsNumeric > 0);
                        end
                        extraEdgeFields = dataset.lines3D.extraEdgeFields;
                        if ~isempty(extraEdgeFields)
                            extraEdgeFieldsNumeric = dataset.lines3D.extraEdgeFieldsNumeric;
                            extraEdgeFields = extraEdgeFields(extraEdgeFieldsNumeric > 0);
                        end

                        if ~isempty(extraEdgeFields) || ~isempty(extraNodeFields)
                            extraEdgeFields = [{'Length'; 'Weight'}; extraEdgeFields];
                            extraNodeFields = [{'Radius'}; extraNodeFields];

                            selectedNode = obj.view.handles.nodesViewAdditionalField.Value;
                            if numel(extraNodeFields) < 2
                                prompts = {'Field for nodes:'; 'Field for edges:'};
                                defAns = {[extraNodeFields; find(ismember(extraNodeFields, selectedNode))]; extraEdgeFields};
                            else
                                nodeId2 = find(~ismember(extraNodeFields, selectedNode));
                                prompts = {'First field for nodes:'; 'Second field for nodes:'; 'Field for edges:'};
                                defAns = {[extraNodeFields; find(ismember(extraNodeFields, selectedNode))]; ...
                                    [extraNodeFields; nodeId2(1)]; ...
                                    extraEdgeFields};
                            end
                            dlgTitle = 'Export to Amira';
                            amiraOpts.WindowStyle = 'normal';
                            amiraOpts.Title = sprintf('Select fields to export\n(only numerical fields can be exported)');
                            amiraOpts.TitleLines = 2;
                            amiraOpts.Focus = 1;
                            [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, prompts, defAns, dlgTitle, amiraOpts);
                            if isempty(answer); return; end
                            if numel(extraNodeFields) < 2
                                outputFieldNode = extraNodeFields(selIndex(1));
                                outputFieldEdge = extraEdgeFields(selIndex(2));
                            else
                                outputFieldNode = [extraNodeFields(selIndex(1)); extraNodeFields(selIndex(2))];
                                outputFieldEdge = extraEdgeFields(selIndex(3));
                            end
                        else
                            outputFieldNode = {'Radius'};
                            outputFieldEdge = {'Weight'};
                        end
                        saveOptions.NodeFieldName = outputFieldNode;
                        saveOptions.EdgeFieldName = outputFieldEdge;
                    case 'Excel format (*.xls)'
                        saveOptions.format = 'excel';
                end
                saveOptions.treeId = treeIds;
                dataset.lines3D.saveToFile(fn_out, saveOptions);
                fprintf('Saving Lines3D to %s: done!\n', fn_out);
            end
        end

        % -----------------------------------------------------------------
        function deleteBtn_Callback(obj)
            % deleteBtn_Callback(obj)
            % Delete all Lines3D data.

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                sprintf('!!! Warning !!!\n\nYou are going to remove all 3d lines, are you sure?'), ...
                'Delete all', 'Delete', 'Cancel', 'Cancel');
            if strcmp(button, 'Cancel'); return; end

            obj.mibModel.backup('lines3d');
            dataset.lines3D.clearContents();
            notify(obj.mibModel, 'ShowImage');
            obj.updateWidgets();
        end

        % -----------------------------------------------------------------
        function nodesViewTable_CellSelectionCallback(obj, Indices, forceJump)
            % nodesViewTable_CellSelectionCallback(obj, Indices, forceJump)
            % Callback for cell selection in nodesViewTable.

            if nargin < 3; forceJump = 0; end
            if forceJump == 0; forceJump = obj.view.handles.jumpCheck.Value; end
            obj.indicesNodes = Indices;

            if forceJump == 1
                obj.nodesViewTable_cb('Jump');
            end
        end

        % -----------------------------------------------------------------
        function edgesViewTable_CellSelectionCallback(obj, Indices, forceJump)
            % edgesViewTable_CellSelectionCallback(obj, Indices, forceJump)
            % Callback for cell selection in edgesViewTable.

            if nargin < 3; forceJump = obj.view.handles.jumpCheck.Value; end
            obj.indicesEdges = Indices;

            if forceJump == 1
                if isempty(obj.indicesEdges); return; end
                if obj.indicesEdges(1,2) > 2; return; end
                nodeId = cell2mat(obj.view.handles.edgesViewTable.Data(obj.indicesEdges(1,1), obj.indicesEdges(1,2)));
                obj.nodesViewTable_cb('Jump', nodeId);
            end
        end

        % -----------------------------------------------------------------
        function treesViewTable_CellSelectionCallback(obj, Indices)
            % treesViewTable_CellSelectionCallback(obj, Indices)
            % Callback for cell selection in treesViewTable.

            if isempty(Indices); return; end
            if isempty(obj.view.handles.nodesViewTable.RowName); return; end

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            rowId = Indices(1);
            if obj.indicesTrees ~= rowId
                if isempty(dataset.lines3D.activeNodeId)
                    treeName = dataset.lines3D.getTreeNames(rowId);
                    nodeIds = find(ismember(dataset.lines3D.G.Nodes.TreeName, treeName));
                    if ~isempty(nodeIds)
                        dataset.lines3D.activeNodeId = nodeIds(end);
                    end
                end
                if ~isempty(dataset.lines3D.activeNodeId)
                    curTable = obj.view.handles.tableSelectionPopup.Value;
                    switch curTable
                        case 'Nodes'
                            obj.updateNodesViewTable(rowId);
                            nodeIds = str2num(obj.view.handles.nodesViewTable.RowName); %#ok<ST2NM>
                        case 'Edges'
                            obj.updateEdgesViewTable(rowId);
                            nodeIds = cell2mat(obj.view.handles.edgesViewTable.Data(:,1:2));
                    end
                    [isActiveInTheTree, posX] = find(nodeIds == dataset.lines3D.activeNodeId); %#ok<EFIND>
                    if isempty(isActiveInTheTree)
                        switch curTable
                            case 'Nodes'
                                dataset.lines3D.activeNodeId = max(nodeIds);
                                isActiveInTheTree = numel(nodeIds);
                            case 'Edges'
                                dataset.lines3D.activeNodeId = min(nodeIds(:));
                                [isActiveInTheTree, posX] = find(nodeIds == dataset.lines3D.activeNodeId); %#ok<EFIND>
                        end
                    end
                    forceJump = 1;
                    switch curTable
                        case 'Nodes'
                            obj.nodesViewTable_CellSelectionCallback(isActiveInTheTree, forceJump);
                        case 'Edges'
                            obj.edgesViewTable_CellSelectionCallback([isActiveInTheTree, posX], forceJump);
                    end
                    obj.view.handles.activeNodeText.Text = sprintf('Active node: %d', dataset.lines3D.activeNodeId);
                    obj.view.handles.activeTreeText.Text = sprintf('Active tree: %d', rowId);
                end
            end
            obj.indicesTrees = Indices(:, 1);
        end

        % -----------------------------------------------------------------
        function treesViewTable_CellEditCallback(obj, Indices)
            % treesViewTable_CellEditCallback(obj, Indices)
            % Callback for cell edit in treesViewTable.
            %
            % Note: this method appears to handle annotation edits in the
            % MIB2 source; ported as-is for completeness.

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            data = obj.view.handles.treesViewTable.Data;
            rowIndices = obj.view.handles.treesViewTable.RowName;
            rowId = Indices(1);
            obj.mibModel.backup('labels', 0);

            newLabelText = data(rowId, 1);
            newLabelValue = str2double(data{rowId, 2});
            newLabelPos(1) = str2double(data{rowId, 3});
            newLabelPos(2) = str2double(data{rowId, 4});
            newLabelPos(3) = str2double(data{rowId, 5});
            newLabelPos(4) = str2double(data{rowId, 6});
            dataset.annotations.updateLabels(str2double(rowIndices(rowId,:)), newLabelText, newLabelPos, newLabelValue);
            notify(obj.mibModel, 'ShowImage');
        end

        % -----------------------------------------------------------------
        function treesViewTable_cb(obj, parameter)
            % treesViewTable_cb(obj, parameter)
            % Context menu callbacks for treesViewTable.

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            if isempty(obj.indicesTrees); return; end
            switch parameter
                case 'rename'
                    rowId = obj.indicesTrees(:,1);
                    rowText = obj.view.handles.treesViewTable.Data(rowId(1),:);
                    currentName = rowText{1};

                    prompts = {'New name for the selected tree:'};
                    defAns = {currentName};
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, prompts, defAns, 'Rename');
                    if isempty(answer); return; end

                    if sum(ismember(obj.view.handles.treesViewTable.Data(:,1), answer(1))) > 0
                        dlgOpt.MsgBoxOnly = true;
                        dlgOpt.Icon = 'puffin_warning';
                        dlgOpt.Header = '!!! Warning !!!\n\nThe names of trees should be unique!';
                        dlgOpt.HeaderLines = 3;
                        utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Duplicated tree name', dlgOpt);
                        return;
                    end
                    obj.mibModel.backup('lines3d');
                    dataset.lines3D.defaultTreeName = answer{1};

                    ids = find(ismember(dataset.lines3D.G.Nodes.TreeName, rowText(1)) == 1);
                    dataset.lines3D.G.Nodes.TreeName(ids) = answer(1);
                    obj.updateWidgets();
                    notify(obj.mibModel, 'ShowImage');

                case 'find'
                    prompts = {'Enter index of the node to find a corresponding tree:'};
                    defAns = {'1'};
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, prompts, defAns, 'Find tree');
                    if isempty(answer); return; end
                    nodeId = str2double(answer{1});
                    if isnan(nodeId); return; end

                    TreeName = dataset.lines3D.G.Nodes(nodeId,:).TreeName;
                    TreeNames = obj.view.handles.treesViewTable.Data(:,1);
                    Indices = find(ismember(TreeNames, TreeName));
                    dataset.lines3D.activeNodeId = nodeId;
                    try
                        scroll(obj.view.handles.treesViewTable, 'row', Indices);
                    catch
                    end

                case 'visualize'
                    rowId = obj.indicesTrees(:,1);
                    obj.visualizeBtn_Callback(rowId);

                case 'save'
                    treeIds = obj.indicesTrees(:,1);
                    if numel(treeIds) > 1
                        dlgOpt.MsgBoxOnly = true;
                        dlgOpt.Icon = 'puffin_error';
                        dlgOpt.Header = 'Please select a single tree and try again!';
                        dlgOpt.HeaderLines = 1;
                        utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Multiple trees selection', dlgOpt);
                        return;
                    end
                    obj.saveBtn_Callback(treeIds);

                case 'delete'
                    obj.mibModel.backup('lines3d');
                    rowId = obj.indicesTrees(:,1);
                    button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                        sprintf('!!! Warning !!!\n\nYou are going to delete selected trees!\nAre you sure?'), ...
                        'Delete tree(s)', 'Delete', 'Cancel', 'Cancel');
                    if strcmp(button, 'Cancel'); return; end

                    dataset.lines3D.deleteTree(rowId);
                    obj.updateWidgets();
                    obj.nodesViewTable_cb('Jump', dataset.lines3D.activeNodeId);
                    notify(obj.mibModel, 'ShowImage');
            end
        end

        % -----------------------------------------------------------------
        function edgesViewTable_cb(obj, parameter)
            % edgesViewTable_cb(obj, parameter)
            % Context menu callbacks for edgesViewTable.

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            if isempty(obj.indicesEdges); return; end
            switch parameter
                case 'Jump'
                    if obj.indicesEdges(1,2) > 2
                        dlgOpt.MsgBoxOnly = true;
                        dlgOpt.Icon = 'puffin_error';
                        dlgOpt.Header = 'Please select a cell containing index of a node!';
                        dlgOpt.HeaderLines = 1;
                        utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Wrong cell', dlgOpt);
                        return;
                    end
                    nodeId = cell2mat(obj.view.handles.edgesViewTable.Data(obj.indicesEdges(1,1), obj.indicesEdges(1,2)));
                    obj.nodesViewTable_cb('Jump', nodeId);
                case 'Active'
                    if obj.indicesEdges(1,2) > 2
                        dlgOpt.MsgBoxOnly = true;
                        dlgOpt.Icon = 'puffin_error';
                        dlgOpt.Header = 'Please select a cell containing index of a node!';
                        dlgOpt.HeaderLines = 1;
                        utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Wrong cell', dlgOpt);
                        return;
                    end
                    nodeId = cell2mat(obj.view.handles.edgesViewTable.Data(obj.indicesEdges(1,1), obj.indicesEdges(1,2)));
                    dataset.lines3D.activeNodeId = nodeId;
                    obj.nodesViewTable_cb('Jump', nodeId);
                    obj.view.handles.activeNodeText.Text = sprintf('Active node: %d', dataset.lines3D.activeNodeId);
            end
        end

        % -----------------------------------------------------------------
        function nodesViewTable_cb(obj, parameter, nodeId)
            % nodesViewTable_cb(obj, parameter, nodeId)
            % Context menu callbacks for nodesViewTable.

            if nargin < 3; nodeId = []; end

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            if ~isempty(nodeId)
                nodeTableIndices = str2num(obj.view.handles.nodesViewTable.RowName); %#ok<ST2NM>
                obj.indicesNodes = find(nodeTableIndices == nodeId);
            end
            if isempty(obj.indicesNodes) && isempty(nodeId); return; end

            switch parameter
                case 'Jump'     % jump to the highlighted node
                    if isempty(nodeId) && isequal(obj.indicesNodes, 0); return; end
                    if ~isempty(nodeId) && nodeId == 0; return; end

                    if isempty(nodeId)
                        rowId = obj.indicesNodes(1);
                        rowText = obj.view.handles.nodesViewTable.Data(rowId,:);
                    else
                        rowText{3} = dataset.lines3D.G.Nodes.PointsXYZ(nodeId, 3);     % z
                        rowText{4} = dataset.lines3D.G.Nodes.PointsXYZ(nodeId, 1);     % x
                        rowText{5} = dataset.lines3D.G.Nodes.PointsXYZ(nodeId, 2);     % y
                    end

                    imgH = dataset.image.height;
                    imgW = dataset.image.width;
                    imgZ = dataset.image.depth;
                    orientation = dataset.orientation;

                    [rowText{4}, rowText{5}, rowText{3}] = dataset.convertUnitsToPixels(rowText{4}, rowText{5}, rowText{3});

                    if orientation == 3      % xy
                        z = rowText{3};
                        x = rowText{4};
                        y = rowText{5};
                    elseif orientation == 1  % zx
                        z = rowText{5};
                        x = rowText{3};
                        y = rowText{4};
                    elseif orientation == 2  % zy
                        z = rowText{4};
                        x = rowText{3};
                        y = rowText{5};
                    end

                    if x > imgW || y > imgH || z > imgZ
                        dlgOpt.MsgBoxOnly = true;
                        dlgOpt.Icon = 'puffin_warning';
                        dlgOpt.Header = 'The node is outside of the image boundaries!';
                        dlgOpt.HeaderLines = 1;
                        utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Wrong coordinates', dlgOpt);
                        return;
                    end

                    dataset.moveView(x, y);

                    if dataset.image.depth > 1
                        dataset.slices{orientation}(1) = round(z);
                        dataset.slices{orientation}(2) = round(z);
                        notify(obj.mibModel, 'SliceChanged');
                    else
                        notify(obj.mibModel, 'ShowImage');
                    end

                case 'Active'
                    rowId = obj.indicesNodes(1);
                    dataset.lines3D.activeNodeId = ...
                        str2double(obj.view.handles.nodesViewTable.RowName(rowId,:));
                    obj.nodesViewTable_cb('Jump');
                    obj.view.handles.activeNodeText.Text = sprintf('Active node: %d', dataset.lines3D.activeNodeId);

                case 'Rename'
                    rowId = obj.indicesNodes(:,1);
                    rowText = obj.view.handles.nodesViewTable.Data(rowId(1),:);
                    currentName = rowText{1};

                    prompts = {'New name for the selected nodes:'};
                    defAns = {currentName};
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, prompts, defAns, 'Rename');
                    if isempty(answer); return; end

                    obj.mibModel.backup('lines3d');
                    nodesIds = str2num(obj.view.handles.nodesViewTable.RowName(rowId,:)); %#ok<ST2NM>
                    dataset.lines3D.G.Nodes.NodeName(nodesIds) = repmat(answer(1), [numel(nodesIds), 1]);

                    obj.updateWidgets();
                    notify(obj.mibModel, 'ShowImage');

                case 'Pixels'   % show coordinate in pixels
                    rowId = obj.indicesNodes(1);
                    rowText = obj.view.handles.nodesViewTable.Data(rowId,:);
                    [x1, y1, z1] = dataset.convertUnitsToPixels(rowText{4}, rowText{5}, rowText{3});
                    orientation = dataset.orientation;

                    if orientation == 3      % xy
                        z = z1; x = x1; y = y1;
                    elseif orientation == 1  % zx
                        z = y1; x = z1; y = x1;
                    elseif orientation == 2  % zy
                        z = x1; x = z1; y = y1;
                    end
                    msgText = sprintf('The coordinate of the node %d\n(x,y,z = %f, %f, %f)\n\nin pixels:\nXY orientation:         %d, %d, %d\nCurrent orientation:  %d, %d, %d', ...
                        rowId, rowText{4}, rowText{5}, rowText{3}, round(x1), round(y1), round(z1), round(x), round(y), round(z));
                    dlgOpt.MsgBoxOnly = true;
                    dlgOpt.Icon = 'puffin_info';
                    dlgOpt.Header = msgText;
                    dlgOpt.HeaderLines = 7;
                    utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Node coordinate', dlgOpt);

                case {'AnnotationsNew', 'AnnotationsAdd', 'AnnotationsDelete'}
                    if strcmp(parameter, 'AnnotationsNew')
                        if dataset.annotations.getLabelsNumber() > 0
                            button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                                sprintf('!!! Warning !!!\n\nDo you want to overwrite the existing annotations?'), ...
                                'Overwrite annotations', 'Overwrite', 'Cancel', 'Cancel');
                            if strcmp(button, 'Cancel'); return; end
                        end
                        obj.mibModel.backup('labels', 0);
                        dataset.annotations.clearContents();
                    end

                    if ~strcmp(parameter, 'AnnotationsDelete')
                        button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                            'Would you like to use node names or node indices as labels?', ...
                            'Define name for labels', 'Node names', 'Node indices', 'Cancel', 'Node names');
                        if strcmp(button, 'Cancel'); return; end
                    end

                    rowId = obj.indicesNodes(:,1);
                    nodesIds = str2num(obj.view.handles.nodesViewTable.RowName(rowId,:)); %#ok<ST2NM>

                    % [z x y t]
                    positionList = [dataset.lines3D.G.Nodes.PointsXYZ(nodesIds, 3), ...
                                    dataset.lines3D.G.Nodes.PointsXYZ(nodesIds, 1), ...
                                    dataset.lines3D.G.Nodes.PointsXYZ(nodesIds, 2), ...
                                    ones([numel(nodesIds) 1])];

                    [positionList(:,2), positionList(:,3), positionList(:,1)] = ...
                        dataset.convertUnitsToPixels(positionList(:,2), positionList(:,3), positionList(:,1));

                    if ~strcmp(parameter, 'AnnotationsDelete')
                        if strcmp(button, 'Node names')
                            labelList = dataset.lines3D.G.Nodes.NodeName(nodesIds);
                        else
                            labelList = cellstr(num2str(nodesIds));
                        end
                    end

                    fieldName = obj.view.handles.nodesViewAdditionalField.Value;

                    if ~isnumeric(dataset.lines3D.G.Nodes.(fieldName)(1))
                        labelValues = zeros([numel(nodesIds) 1]);
                    else
                        labelValues = dataset.lines3D.G.Nodes.(fieldName)(nodesIds);
                    end

                    if strcmp(parameter, 'AnnotationsDelete')
                        dataset.annotations.removeLabels(positionList);
                    else
                        dataset.annotations.addLabels(labelList, positionList, labelValues);
                    end
                    obj.mibModel.showAnnotations = true;

                    notify(obj.mibModel, 'UpdateAnnotations');
                    notify(obj.mibModel, 'ShowImage');

                case 'Delete'   % delete the highlighted nodes
                    rowId = obj.indicesNodes(:,1);
                    nodesIds = str2num(obj.view.handles.nodesViewTable.RowName(rowId,:)); %#ok<ST2NM>
                    if numel(nodesIds) == 1
                        button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                            sprintf('Delete the following node?\n\nNode Id: %d', nodesIds), ...
                            'Delete node', 'Delete', 'Cancel', 'Cancel');
                    else
                        button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                            'Delete the multiple nodes?', ...
                            'Delete nodes', 'Delete', 'Cancel', 'Cancel');
                    end
                    if strcmp(button, 'Cancel'); return; end

                    obj.mibModel.backup('lines3d');
                    wb = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Please wait...', 'Title', 'Delete node');
                    index = 0;
                    for i = numel(nodesIds):-1:1
                        dataset.lines3D.deleteNode(nodesIds(i));
                        notify(obj.mibModel, 'ShowImage');
                        index = index + 1;
                        wb.Value = index / numel(nodesIds);
                    end
                    obj.updateWidgets();
                    delete(wb);
                    notify(obj.mibModel, 'ShowImage');
            end
        end

        % -----------------------------------------------------------------
        function visualizeBtn_Callback(obj, treeId)
            % visualizeBtn_Callback(obj, treeId)
            % Visualize the graph in 3D using a separate figure.

            if nargin < 2; treeId = 0; end

            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            prompts = {'Use default colors?', 'Add an orthoslice of the visualization?', 'Slice number:'};
            defAns = {true, false, num2str(dataset.getCurrentSliceNumber())};
            dlgTitle = 'Add slice';
            answer = utils.dlgs.inputUniversalDlg(obj.view.gui, prompts, defAns, dlgTitle);
            if isempty(answer); return; end

            if answer{2} == 1
                showSlice = str2double(answer{3});
            else
                showSlice = [];
            end

            defaultColors = answer{1};

            if isempty(obj.hFig)
                obj.hFig = figure();
                obj.hAx = axes();
            elseif ~isvalid(obj.hFig)
                obj.hFig = figure();
                obj.hAx = axes();
            end

            if treeId == 0
                nodeIds = [];
                Graph = dataset.lines3D.G;
            else
                [Graph, nodeIds] = dataset.lines3D.getTree(treeId);
            end
            if ~isempty(nodeIds)
                Graph.Nodes.Name = cellstr(num2str(nodeIds'));
            end

            pixSize = dataset.image.pixSize;

            obj.hPlot = plot(obj.hAx, Graph);
            obj.hPlot.XData = Graph.Nodes.PointsXYZ(:,1);
            obj.hPlot.YData = Graph.Nodes.PointsXYZ(:,2);
            obj.hPlot.ZData = Graph.Nodes.PointsXYZ(:,3);
            obj.hAx.XLabel.String = ['X, ', pixSize.units];
            obj.hAx.YLabel.String = ['Y, ', pixSize.units];
            obj.hAx.ZLabel.String = ['Z, ', pixSize.units];
            obj.hAx.DataAspectRatio = [1 1 1];
            grid(obj.hAx, 'on');
            obj.hAx.XAxis.TickValues = obj.hAx.XAxis.Limits(1):diff(obj.hAx.XAxis.Limits)/5:obj.hAx.XAxis.Limits(2);
            obj.hAx.YAxis.TickValues = obj.hAx.YAxis.Limits(1):diff(obj.hAx.YAxis.Limits)/5:obj.hAx.YAxis.Limits(2);
            obj.hAx.ZAxis.TickValues = obj.hAx.ZAxis.Limits(1):diff(obj.hAx.ZAxis.Limits)/5:obj.hAx.ZAxis.Limits(2);
            if defaultColors == 0
                obj.hPlot.LineWidth = dataset.lines3D.edgeThickness;
                obj.hPlot.MarkerSize = dataset.lines3D.nodeRadius;
                obj.hPlot.EdgeColor = dataset.lines3D.edgeActiveColor;
                obj.hPlot.NodeColor = dataset.lines3D.nodeColor;
            end

            if ~isempty(showSlice)
                if showSlice > dataset.image.depth
                    showSlice = dataset.image.depth;
                else
                    showSlice = max([1 showSlice]);
                end
                getRGBOptions.sliceNo = showSlice;
                getRGBOptions.mode = 'full';
                getRGBOptions.resize = 'no';

                img = obj.mibModel.getRGBimage(getRGBOptions);
                bb = dataset.image.boundingBox;

                hold on;
                xValue = bb(1):(bb(2)-bb(1))/size(img,2):bb(2);
                xValue = xValue(1:end-1);
                yValue = bb(3):(bb(4)-bb(3))/size(img,1):bb(4);
                yValue = yValue(1:end-1);
                [xValue, yValue] = meshgrid(xValue, yValue);

                zValue = showSlice * pixSize.z + bb(5);
                surf(xValue, yValue, zValue + zeros([size(img, 1) size(img, 2)]), img, 'EdgeColor', 'none')
                colormap('gray');
                hold off;
            end
            disp('Hint: render image to file with the following command:')
            disp('print(''MIB-snapshot.tif'', ''-dtiff'', ''-r600'',''-opengl'');');
        end

    end
end
