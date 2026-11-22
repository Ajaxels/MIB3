classdef Annotations < handle
% ANNOTATIONS - @type Annotations class is responsible for the List of Annotations dialog.
%
% available from MIB Ribbon Models Annotations List of annotations
%
%
% .. code-block:: matlab
%
%   obj.startController('controllers.Annotations'); // as GUI tool

    % Updates
    % ported to MIB3 AppDesigner framework

    properties
        mibModel
        % handle to the MibModel
        view
        % handle to the view / views.AnnotationsGUI
        listener
        % a cell array with handles to listeners
        imarisOptions
        % a structure with export options for Imaris
        % .radii  - default radius scaling factor
        % .color  - default color [R G B A] in range 0..1
        % .name   - default spot name
        indices
        % Nx2 array of [row, col] indices of currently selected table cells
        batchModifyExpressionOperation
        % last-used operation in 'Batch modify' dialog
        batchModifyExpressionFactor
        % last-used factor in 'Batch modify' dialog
        childControllers
        % cell array of open child controllers
        childControllersIds
        % cell array of names of open child controllers
        BatchOpt
        % structure compatible with batch processing; fields for CropPatches
    end

    events
        CloseEvent
        % fires when the window is closed; caught by MibController to purge this child
    end

    methods (Static)
        function ViewListner_Callback2(obj, src, evnt)
            % VIEWLISTNER_CALLBACK2 - Guard: if the view was closed before listener cleanup, clean up and return.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.ViewListner_Callback2(src, evnt)
            %
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener)
                    delete(obj.listener{i});
                end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset', 'UpdateAnnotations'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        function obj = Annotations(mibModel, varargin)
            % ANNOTATIONS - Constructor for the Annotations controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = Annotations(mibModel)
            %       obj = Annotations(mibModel, BatchOpt)
            %
            % Input Arguments:
            %   - **mibModel** - handle to MibModel
            %   - **varargin{1}** - controller handle (unused, for startController compatibility)
            %   - **varargin{2}** - *(optional)* BatchOpt structure; when NaN returns defaults via SyncBatch
            %

            obj.mibModel = mibModel;

            obj.imarisOptions.radii = NaN;
            obj.imarisOptions.color = [1 0 0 0];
            obj.imarisOptions.name  = 'mibSpots';

            obj.indices = [];
            obj.batchModifyExpressionOperation = 'Multiply';
            obj.batchModifyExpressionFactor    = '1.5';
            obj.childControllers   = {};
            obj.childControllersIds = {};

            % ---------- BatchOpt defaults (CropPatches sub-dialog settings) ----------
            obj.BatchOpt.CropObjectsTo = {'Amira Mesh binary (*.am)'};
            obj.BatchOpt.CropObjectsTo{2} = {'Do not crop', 'Crop to MATLAB', ...
                'Amira Mesh binary (*.am)', 'MRC format for IMOD (*.mrc)', ...
                'NRRD Data Format (*.nrrd)', 'TIF format LZW compression (*.tif)', ...
                'TIF format uncompressed (*.tif)'};
            obj.BatchOpt.CropObjectsMarginXY = '256';
            obj.BatchOpt.CropObjectsMarginZ  = '256';
            obj.BatchOpt.CropObjectsDepth    = '1';
            obj.BatchOpt.Generate3DPatches   = false;
            obj.BatchOpt.CropObjectsIncludeModel = {'Do not include'};
            obj.BatchOpt.CropObjectsIncludeModel{2} = {'Do not include', 'Crop to MATLAB', ...
                'MATLAB format (*.model)', 'Amira Mesh binary (*.am)', ...
                'MRC format for IMOD (*.mrc)', 'NRRD Data Format (*.nrrd)', ...
                'TIF format LZW compression (*.tif)', 'TIF format uncompressed (*.tif)'};
            obj.BatchOpt.CropObjectsIncludeModelMaterialIndex = 'NaN';
            obj.BatchOpt.CropObjectsIncludeMask = {'Do not include'};
            obj.BatchOpt.CropObjectsIncludeMask{2} = {'Do not include', 'Crop to MATLAB', ...
                'MATLAB format (*.mask)', 'Amira Mesh binary (*.am)', ...
                'MRC format for IMOD (*.mrc)', 'NRRD Data Format (*.nrrd)', ...
                'TIF format LZW compression (*.tif)', 'TIF format uncompressed (*.tif)'};
            obj.BatchOpt.CropObjectsOutputName = 'CropOut';
            obj.BatchOpt.SingleMaskObjectPerDataset = false;
            obj.BatchOpt.CropObjectsJitter = false;

            if ~isfield(obj.mibModel.sessionSettings, 'annotationsCropPatches') || ...
                    ~isfield(obj.mibModel.sessionSettings.annotationsCropPatches, 'CropObjectsJitterVariation')
                obj.mibModel.sessionSettings.annotationsCropPatches.CropObjectsJitterVariation = '50';
                obj.mibModel.sessionSettings.annotationsCropPatches.CropObjectsJitterSeed = '0';
            end
            obj.BatchOpt.CropObjectsJitterVariation = ...
                obj.mibModel.sessionSettings.annotationsCropPatches.CropObjectsJitterVariation;
            obj.BatchOpt.CropObjectsJitterSeed = ...
                obj.mibModel.sessionSettings.annotationsCropPatches.CropObjectsJitterSeed;
            obj.BatchOpt.showWaitbar = true;
            obj.BatchOpt.id = obj.mibModel.getActiveId();

            % ---------- initialise GUI ----------
            guiName = 'views.AnnotationsGUI';
            obj.view = core.ChildView(obj, guiName);
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme

            obj.addCallbacks();

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.closeBtn.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.closeBtn.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % enable annotation display
            obj.mibModel.showAnnotations = true;

            % initialise precision spinner from stored preference
            if isfield(obj.mibModel.preferences, 'SegmTools') && ...
                    isfield(obj.mibModel.preferences.SegmTools, 'Annotations') && ...
                    isfield(obj.mibModel.preferences.SegmTools.Annotations, 'precision')
                obj.view.handles.precisionEdit.Value = ...
                    obj.mibModel.preferences.SegmTools.Annotations.precision;
            end

            % position window and show
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');
            obj.updateWidgets();

            % add handle tags to the tooltips
            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.view.handles, true, 'obj.view.handles');
            end
            
            % show the gui
            obj.view.gui.Visible = 'on';

            % register model listeners
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{3} = addlistener(obj.mibModel, 'UpdateAnnotations', ...
                @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % -----------------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Close the Annotations window and clean up listeners.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.closeWindow()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.closeWindow: triggered\n');
            end

            for i = numel(obj.childControllers):-1:1
                child = obj.childControllers{i};
                if isa(child, 'handle') && isvalid(child)
                    child.closeWindow();
                end
            end
            obj.childControllers    = {};
            obj.childControllersIds = {};

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
            % ADDCALLBACKS - Wire all widget callbacks. Called once from the constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.addCallbacks()
            %

            % Window X-button triggers proper cleanup
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            h = obj.view.handles;

            % Table
            h.annotationTable.SelectionChangedFcn = @(~, evt) obj.annotationTable_CellSelectionCallback(evt.Selection);
            h.annotationTable.CellEditCallback = @(~, evt) obj.annotationTable_CellEditCallback(evt.Indices);
            h.annotationTable.KeyPressFcn = @(~, evt) obj.annotationTable_KeyPressFcn(evt);
            h.annotationTable.ColumnEditable = [true true true true true true];

            % Figure key press (for Ctrl+Z etc.)
            obj.view.gui.KeyPressFcn = @(~, evt) obj.gui_KeyPressFcn(evt);

            % Context-menu items
            h.cmJump.MenuSelectedFcn          = @(~,~) obj.tableContextMenu_cb('Jump');
            h.cmAdd.MenuSelectedFcn           = @(~,~) obj.tableContextMenu_cb('Add');
            h.cmRename.MenuSelectedFcn        = @(~,~) obj.tableContextMenu_cb('Rename');
            h.cmModify.MenuSelectedFcn        = @(~,~) obj.tableContextMenu_cb('Modify');
            h.cmCount.MenuSelectedFcn         = @(~,~) obj.tableContextMenu_cb('Count');
            h.cmClipboard.MenuSelectedFcn     = @(~,~) obj.tableContextMenu_cb('Clipboard');
            h.cmClipboardPaste.MenuSelectedFcn = @(~,~) obj.tableContextMenu_cb('ClipboardPaste');
            h.cmMask.MenuSelectedFcn          = @(~,~) obj.tableContextMenu_cb('Mask');
            h.cmCropPatches.MenuSelectedFcn   = @(~,~) obj.tableContextMenu_cb('CropPatches');
            h.cmInterpolate.MenuSelectedFcn   = @(~,~) obj.tableContextMenu_cb('Interpolate');
            % "Convert model to indexed objects from annotations" is created here, not in
            % the mlapp, and placed before "Export selected annotations", which hands its
            % separator over to it. A menu shows its Children in reverse order; the
            % context menu has no Tag, so it is not in obj.view.handles.
            tableContextMenu = h.cmExport.Parent;
            obj.view.handles.cmConvertModel = uimenu(tableContextMenu, ...
                'Text', 'Convert model to indexed objects from annotations...', ...
                'Tag', 'cmConvertModel', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~,~) obj.tableContextMenu_cb('ConvertModel'));
            h.cmExport.Separator = 'off';
            menuOrder = flipud(tableContextMenu.Children);
            menuOrder(menuOrder == obj.view.handles.cmConvertModel) = [];
            exportPosition = find(menuOrder == h.cmExport, 1);
            menuOrder = [menuOrder(1:exportPosition-1); obj.view.handles.cmConvertModel; menuOrder(exportPosition:end)];
            tableContextMenu.Children = flipud(menuOrder);
            h.cmExport.MenuSelectedFcn        = @(~,~) obj.tableContextMenu_cb('Export');
            h.cmImaris.MenuSelectedFcn        = @(~,~) obj.tableContextMenu_cb('Imaris');
            h.cmOrderTop.MenuSelectedFcn      = @(~,~) obj.tableContextMenu_cb('OrderTop');
            h.cmOrderUp.MenuSelectedFcn       = @(~,~) obj.tableContextMenu_cb('OrderUp');
            h.cmOrderDown.MenuSelectedFcn     = @(~,~) obj.tableContextMenu_cb('OrderDown');
            h.cmOrderBottom.MenuSelectedFcn   = @(~,~) obj.tableContextMenu_cb('OrderBottom');
            h.cmDelete.MenuSelectedFcn        = @(~,~) obj.tableContextMenu_cb('Delete');

            % Buttons
            h.loadBtn.ButtonPushedFcn         = @(~,~) obj.loadBtn_Callback();
            h.saveBtn.ButtonPushedFcn         = @(~,~) obj.saveBtn_Callback();
            h.deleteBtn.ButtonPushedFcn       = @(~,~) obj.deleteBtn_Callback();
            h.refreshBtn.ButtonPushedFcn      = @(~,~) obj.updateWidgets();
            h.settingsButton.ButtonPushedFcn  = @(~,~) obj.settingsBtn_Callback();
            h.helpBtn.ButtonPushedFcn         = @(~,~) obj.helpBtn_Callback();
            h.closeBtn.ButtonPushedFcn        = @(~,~) obj.closeWindow();

            % Precision spinner
            h.precisionEdit.ValueChangedFcn   = @(~,~) obj.precisionEdit_Callback();

            % Sort dropdown
            h.resortTablePopup.ValueChangedFcn = @(~,~) obj.resortTablePopup_Callback();
        end

        % -----------------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh the annotation table from the current dataset.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.updateWidgets()
            %

            id = obj.mibModel.getActiveId();
            obj.BatchOpt.id = id;

            numberOfLabels = obj.mibModel.I{id}.annotations.getLabelsNumber();
            precision = obj.view.handles.precisionEdit.Value;

            if numberOfLabels >= 1
                [labelsText, labelsVal, labelsPos, labelIndices] = ...
                    obj.mibModel.I{id}.annotations.getLabels();
                data = cell(numel(labelsText), 6);
                data(:,1) = labelsText';
                modFmt   = sprintf('%c.%df', '%', precision);
                data(:,2) = arrayfun(@(x) sprintf(modFmt,  x), labelsVal,      'UniformOutput', false);
                data(:,3) = arrayfun(@(x) sprintf('%.2f', x), labelsPos(:,1), 'UniformOutput', false);
                data(:,4) = arrayfun(@(x) sprintf('%.2f', x), labelsPos(:,2), 'UniformOutput', false);
                data(:,5) = arrayfun(@(x) sprintf('%.2f', x), labelsPos(:,3), 'UniformOutput', false);
                data(:,6) = arrayfun(@(x) sprintf('%d',   x), labelsPos(:,4), 'UniformOutput', false);
                obj.view.handles.annotationTable.Data = data;
                % RowName stores the internal annotation indices for edit/delete
                obj.view.handles.annotationTable.RowName = cellstr(num2str(labelIndices(:)));
            else
                obj.view.handles.annotationTable.Data = cell(6, 6);
                obj.view.handles.annotationTable.RowName = {};
            end
        end

        % -----------------------------------------------------------------
        function loadBtn_Callback(obj)
            % LOADBTN_CALLBACK - Import annotations from a file or from the MATLAB workspace.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.loadBtn_Callback()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.loadBtn_Callback: triggered\n');
            end

            id = obj.BatchOpt.id;

            button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                'Would you like to import annotations from a file or from the main Matlab workspace?', ...
                'Import/Load annotations', ...
                'Load from a file', 'Import from Matlab', 'Cancel', 'Load from a file');
            switch button
                case 'Cancel'
                    return;
                case 'Import from Matlab'
                    availableVars = evalin('base', 'whos');
                    idx = ismember({availableVars.class}, 'struct');
                    labelsList = {availableVars(idx).name}';
                    defIdx = find(ismember(labelsList, 'Labels'), 1);
                    if ~isempty(defIdx)
                        labelsList{end+1} = defIdx;
                    end
                    prompts = {'Structure name with annotations:'};
                    defAns  = {labelsList};
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, ...
                        'Input annotations');
                    if isempty(answer); return; end

                    try
                        Labels = evalin('base', answer{1});
                    catch err
                        dlgOpt.MsgBoxOnly   = true;
                        dlgOpt.HeaderLines  = 1;
                        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                            'Wrong variable', {''}, {err.message}, 'Error', dlgOpt);
                        return;
                    end
                    if ~isfield(Labels, 'Text')
                        dlgOpt.MsgBoxOnly  = true;
                        dlgOpt.HeaderLines = 1;
                        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                            'Wrong structure type!', {''}, {'The structure should contain: Text (cell), Values (array), Positions ([N, z x y t])'}, ...
                            'Wrong structure', dlgOpt);
                        return;
                    end
                    obj.mibModel.backup('annotations', 0);

                    if ~isfield(Labels, 'Values')
                        Labels.Values = ones(numel(Labels.Text), 1);
                    end
                    if size(Labels.Positions, 2) == 3
                        Labels.Positions(:,4) = obj.mibModel.I{id}.slices{5}(1);
                    end
                    obj.mibModel.I{id}.annotations.replaceLabels( ...
                        Labels.Text, Labels.Positions, Labels.Values);

                case 'Load from a file'
                    loadOptions.parentFigure     = obj.view.gui;
                    loadOptions.currentDirectory = obj.mibModel.currentDirectory;
                    loadOptions.boundingBox      = obj.mibModel.I{id}.image.boundingBox;
                    loadOptions.pixSize          = obj.mibModel.I{id}.image.pixSize;
                    loadOptions.currentT         = obj.mibModel.I{id}.slices{5}(1);
                    obj.mibModel.backup('annotations', 0);
                    status = obj.mibModel.I{id}.annotations.loadAnnotations([], loadOptions);
                    if ~status; return; end
                    obj.mibModel.showAnnotations = true;
                    notify(obj.mibModel, 'UpdateGuiWidgets', core.ToggleEventData({'checkboxes'}));
            end
            obj.updateWidgets();
            notify(obj.mibModel, 'ShowImage');
            fprintf('Import annotations: done!\n');
        end

        % -----------------------------------------------------------------
        function saveBtn_Callback(obj)
            % SAVEBTN_CALLBACK - Export annotations to a file or to the MATLAB workspace.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.saveBtn_Callback()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.saveBtn_Callback: triggered\n');
            end

            id = obj.BatchOpt.id;
            [labelText, labelValue, labelPosition] = ...
                obj.mibModel.I{id}.annotations.getLabels();
            if numel(labelText) == 0; return; end

            Labels.Text      = labelText;
            Labels.Values    = labelValue;
            Labels.Positions = labelPosition;

            button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                'Would you like to save annotations to a file or export to the main Matlab workspace?', ...
                'Export/Save annotations', ...
                'Save to a file', 'Export to Matlab', 'Cancel', 'Save to a file');
            if strcmp(button, 'Cancel'); return; end

            if strcmp(button, 'Export to Matlab')
                answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                    {'Please enter a name for the structure with labels:'}, ...
                    {'Labels'}, 'Export to Matlab');
                if isempty(answer); return; end
                assignin('base', answer{1}, Labels);
                fprintf('Export annotations: structure ''%s'' with fields .Text, .Values, .Positions exported.\n', answer{1});
            else
                obj.saveAnnotationsToFile(labelText, labelPosition, labelValue);
            end
        end

        % -----------------------------------------------------------------
        function saveAnnotationsToFile(obj, labelText, labelPosition, labelValue)
            % SAVEANNOTATIONSTOFILE - Save annotations to a file chosen by the user.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.saveAnnotationsToFile(labelText, labelPosition, labelValue)
            %
            % Input Arguments:
            %   - **labelText** - cell array of annotation labels
            %   - **labelPosition** - Nx4 matrix [z x y t] in pixels
            %   - **labelValue** - Nx1 numeric array of annotation values
            %

            id = obj.BatchOpt.id;

            % build default output path from dataset filename
            fn_out = obj.mibModel.I{id}.image.filename;
            dotIdx = strfind(fn_out, '.');
            if ~isempty(dotIdx)
                fn_out = [fn_out(1:dotIdx(end)-1) '_Ann'];
            end
            if isempty(strfind(fn_out, '/')) && isempty(strfind(fn_out, '\')) %#ok<STREMP>
                fn_out = fullfile(obj.mibModel.currentDirectory, fn_out);
            end
            if isempty(fn_out)
                fn_out = obj.mibModel.currentDirectory;
            end

            % prepare PSI/Amira session settings
            if ~isfield(obj.mibModel.sessionSettings, 'Annotations')
                obj.mibModel.sessionSettings.Annotations = struct();
            end
            if ~isfield(obj.mibModel.sessionSettings.Annotations, 'recalculateCoordinates')
                obj.mibModel.sessionSettings.Annotations.recalculateCoordinates = 1;
                obj.mibModel.sessionSettings.Annotations.addLabelToFilename = true;
            end

            Filters = {'*.ann',  'Matlab format (*.ann)'; ...
                       '*.csv',  'Comma-separated value (*.csv)'; ...
                       '*.landmarkAscii', 'Amira landmarks ASCII (*.landmarkAscii)'; ...
                       '*.landmarkBin',   'Amira landmarks BINARY (*.landmarkBin)'; ...
                       '*.psi',  'PSI format ASCII (*.psi)'; ...
                       '*.xls',  'Excel format (*.xls)'};
            [filename, path, FilterIndex] = uiputfile(Filters, 'Save annotations...', fn_out);
            if isequal(filename, 0); return; end
            fn_out = fullfile(path, filename);

            options = struct();
            options.boundingBox = obj.mibModel.I{id}.image.boundingBox;
            options.pixSize     = obj.mibModel.I{id}.image.pixSize;
            options.labelText   = labelText;
            options.labelPosition = labelPosition;
            options.labelValue  = labelValue;

            % generate per-slice filenames for formats that need them
            if numel(obj.mibModel.I{id}.image.sliceName) == obj.mibModel.I{id}.image.depth
                sliceNames = obj.mibModel.I{id}.image.sliceName;
            else
                [~, sn, ext] = fileparts(obj.mibModel.I{id}.image.filename);
                sliceNames = repmat({[sn ext]}, [max(round(labelPosition(:,1))), 1]);
            end
            sliceValsZ = round(labelPosition(:,1));
            sliceValsZ(sliceValsZ <= 0) = 1;
            options.sliceNames = sliceNames(min(sliceValsZ, numel(sliceNames)));

            switch Filters{FilterIndex, 2}
                case 'Matlab format (*.ann)'
                    options.format = 'ann';
                case 'Comma-separated value (*.csv)'
                    options.format = 'csv';
                case 'Excel format (*.xls)'
                    options.format = 'xls';
                case 'PSI format ASCII (*.psi)'
                    prompts = {'Recalculate coordinates with respect to bounding box?'; ...
                               'Add annotation label to filename'};
                    defAns = {{'Recalculate', 'Save as they are', ...
                        obj.mibModel.sessionSettings.Annotations.recalculateCoordinates}; ...
                        obj.mibModel.sessionSettings.Annotations.addLabelToFilename};
                    psiOpt.mibPath = obj.mibModel.mibPath;
                    [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                        '', prompts, defAns, 'Export annotations in PSI format', psiOpt);
                    if isempty(answer); return; end
                    obj.mibModel.sessionSettings.Annotations.recalculateCoordinates = selIndex(1);
                    obj.mibModel.sessionSettings.Annotations.addLabelToFilename = logical(answer{2});
                    options.addLabelToFilename = logical(answer{2});
                    options.format = 'psi';
                    if strcmp(answer{1}, 'Recalculate')
                        options.convertToUnits = true;
                    end
                otherwise  % Amira landmark formats
                    dlgOpt.MsgBoxOnly  = true;
                    dlgOpt.Icon        = 'puffin_info';
                    dlgOpt.HeaderLines = 2;
                    dlgOpt.mibPath = obj.mibModel.mibPath;
                    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                        'Only annotation positions are saved. Use PSI format to keep labels and values.', {''}, {''}, ...
                        'Export to Amira', dlgOpt);

                    recalcBtn = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                        'Recalculate annotations with respect to the current bounding box?', ...
                        'Recalculate coordinates', 'Recalculate', 'Save as they are', 'Recalculate');
                    if strcmp(Filters{FilterIndex, 2}, 'Amira landmarks ASCII (*.landmarkAscii)')
                        options.format = 'landmarkAscii';
                    else
                        options.format = 'landmarkBin';
                    end
                    if strcmp(recalcBtn, 'Recalculate')
                        options.convertToUnits = true;
                    end
            end
            options.mibGUI = obj.view.gui; 
            obj.mibModel.I{id}.annotations.saveToFile(fn_out, options);
        end

        % -----------------------------------------------------------------
        function deleteBtn_Callback(obj)
            % DELETEBTN_CALLBACK - Delete all annotations from the current dataset.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.deleteBtn_Callback()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.deleteBtn_Callback: triggered\n');
            end

            id = obj.BatchOpt.id;
            obj.mibModel.backup('annotations', 0);
            obj.mibModel.I{id}.annotations.removeLabels();
            notify(obj.mibModel, 'ShowImage');
            obj.updateWidgets();
        end

        % -----------------------------------------------------------------
        function annotationTable_CellSelectionCallback(obj, Selection)
            % ANNOTATIONTABLE_CELLSELECTIONCALLBACK - Callback for cell selection change in annotationTable.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.annotationTable_CellSelectionCallback(Selection)
            %
            % Input Arguments:
            %   - **Selection** - Nx2 array of [row col] pairs (from SelectionChangedFcn event.Selection)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.annotationTable_CellSelectionCallback: triggered\n');
            end

            obj.indices = Selection;
            if obj.view.handles.jumpCheck.Value
                obj.tableContextMenu_cb('Jump');
            end
        end

        % -----------------------------------------------------------------
        function annotationTable_CellEditCallback(obj, Indices)
            % ANNOTATIONTABLE_CELLEDITCALLBACK - Callback for cell edit in annotationTable.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.annotationTable_CellEditCallback(Indices)
            %
            % Input Arguments:
            %   - **Indices** - [row col] of the edited cell (from CellEditCallback event.Indices)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.annotationTable_CellEditCallback: triggered\n');
            end

            data      = obj.view.handles.annotationTable.Data;
            rowNames  = obj.view.handles.annotationTable.RowName;
            rowId     = Indices(1);
            if rowId > size(data, 1) || isempty(rowNames); return; end

            obj.mibModel.backup('annotations', 0);

            newLabelText    = data(rowId, 1);
            newLabelValue   = str2double(data{rowId, 2});
            newLabelPos(1)  = str2double(data{rowId, 3});
            newLabelPos(2)  = str2double(data{rowId, 4});
            newLabelPos(3)  = str2double(data{rowId, 5});
            newLabelPos(4)  = str2double(data{rowId, 6});
            annIdx = str2double(rowNames{rowId});
            obj.mibModel.I{obj.BatchOpt.id}.annotations.updateLabels( ...
                annIdx, newLabelText, newLabelPos, newLabelValue);
            notify(obj.mibModel, 'ShowImage');
        end

        % -----------------------------------------------------------------
        function precisionEdit_Callback(obj)
            % PRECISIONEDIT_CALLBACK - Callback for the precision spinner; refresh table with new decimal places.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.precisionEdit_Callback()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.precisionEdit_Callback: triggered\n');
            end

            precision = obj.view.handles.precisionEdit.Value;
            % persist preference
            if isfield(obj.mibModel.preferences, 'SegmTools') && ...
                    isfield(obj.mibModel.preferences.SegmTools, 'Annotations')
                obj.mibModel.preferences.SegmTools.Annotations.precision = precision;
            end
            obj.updateWidgets();
            notify(obj.mibModel, 'UpdateGuiWidgets');
        end

        % -----------------------------------------------------------------
        function tableContextMenu_cb(obj, parameter)
            % TABLECONTEXTMENU_CB - Callbacks for the annotation table context menu.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.tableContextMenu_cb(parameter)
            %
            % Input Arguments:
            %   - **parameter** - string selecting the action
            %   - 'Add'         - add a new annotation
            %   - 'Modify'      - batch-modify values/coords of selected annotations
            %   - 'Rename'      - rename selected annotations
            %   - 'Jump'        - move view to selected annotation
            %   - 'Count'       - count and sum selected annotations
            %   - 'Clipboard'   - copy selected rows to clipboard
            %   - 'ClipboardPaste' - paste clipboard into selected column
            %   - 'CropPatches' - crop image patches around selected annotations
            %   - 'Mask'        - rasterise selected annotations into the mask layer
            %   - 'Interpolate' - interpolate positions between selected annotations
            %   - 'ConvertModel' - convert the model to indexed objects numbered from the annotation names, see convertModelFromAnnotations
            %   - 'Export'      - export selected annotations to file
            %   - 'Imaris'      - export selected annotations to Imaris
            %   - 'OrderTop' / 'OrderUp' / 'OrderDown' / 'OrderBottom' - reorder
            %   - 'Delete'      - delete selected annotations
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.tableContextMenu_cb(%s): triggered\n', parameter);
            end

            id = obj.BatchOpt.id;
            orientation = obj.mibModel.I{id}.orientation;

            switch parameter

                case 'Add'
                    depth  = obj.mibModel.I{id}.image.depth;
                    width  = obj.mibModel.I{id}.image.width;
                    height = obj.mibModel.I{id}.image.height;
                    slices = obj.mibModel.I{id}.slices;
                    zVal = slices{orientation}(1);
                    tVal = slices{5}(1);
                    defText  = obj.mibModel.I{id}.annotations.defaultAnnotationText;
                    defValue = num2str(obj.mibModel.I{id}.annotations.defaultAnnotationValue);

                    prompts = {'Annotation text'; 'Annotation value'; ...
                        sprintf('Z coordinate (Zmax=%d):', depth); ...
                        sprintf('X coordinate (Xmax=%d):', width); ...
                        sprintf('Y coordinate (Ymax=%d):', height); ...
                        sprintf('T coordinate (Tmax=%d):', obj.mibModel.I{id}.image.time)};
                    dlgOpt.WindowHeight = 320;
                    dlgOpt.WindowWidth = 320;
                    defAns = {defText; defValue; 
                        struct('Spinner', true, 'Value', zVal, 'Limits', [1 depth], 'Step', 1, 'Round', false); 
                        struct('Spinner', true, 'Value', 10, 'Limits', [1 width], 'Step', 1, 'Round', false);
                        struct('Spinner', true, 'Value', 10, 'Limits', [1 height], 'Step', 1, 'Round', false); 
                        struct('Spinner', true, 'Value', tVal, 'Limits', [1 height], 'Step', 1, 'Round', false)};
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                        '', prompts, defAns, 'Add annotation', dlgOpt);
                    if isempty(answer); return; end

                    obj.mibModel.backup('annotations', 0);
                    labelsText = answer(1);
                    obj.mibModel.I{id}.annotations.defaultAnnotationText  = labelsText{1};
                    labelsValue   = str2double(answer{2});
                    obj.mibModel.I{id}.annotations.defaultAnnotationValue = labelsValue;
                    labelsPos = [answer{3}, answer{4}, answer{5}, answer{6}];
                    obj.mibModel.I{id}.annotations.addLabels(labelsText, labelsPos, labelsValue);
                    obj.updateWidgets();
                    notify(obj.mibModel, 'ShowImage');

                case {'OrderTop', 'OrderUp', 'OrderDown', 'OrderBottom'}
                    if isempty(obj.indices); return; end
                    [labelsList, labelValues, labelPositions] = ...
                        obj.mibModel.I{id}.annotations.getLabels();
                    n = numel(labelsList);
                    indicesList = (1:n)';
                    selRows = unique(obj.indices(:,1));
                    switch parameter
                        case 'OrderTop'
                            newIndices = [selRows; indicesList(~ismember(indicesList, selRows))];
                        case 'OrderUp'
                            newIndices = indicesList;
                            for i = 1:n
                                if ismember(i, selRows-1)
                                    newIndices([i, i+1]) = newIndices([i+1, i]);
                                end
                            end
                            obj.indices(:,1) = obj.indices(:,1) - 1;
                        case 'OrderDown'
                            newIndices = indicesList;
                            for i = n:-1:1
                                if ismember(i, selRows)
                                    if i == n; return; end
                                    newIndices([i, i+1]) = newIndices([i+1, i]);
                                end
                            end
                            obj.indices(:,1) = obj.indices(:,1) + 1;
                        case 'OrderBottom'
                            newIndices = [indicesList(~ismember(indicesList, selRows)); selRows];
                    end
                    labelsList      = labelsList(newIndices);
                    labelValues     = labelValues(newIndices);
                    labelPositions  = labelPositions(newIndices, :);
                    obj.mibModel.backup('annotations', 0);
                    obj.mibModel.I{id}.annotations.clearContents();
                    obj.mibModel.I{id}.annotations.addLabels(labelsList, labelPositions, labelValues);
                    obj.updateWidgets();
                    notify(obj.mibModel, 'ShowImage');

                case 'Modify'
                    if isempty(obj.indices); return; end
                    dlg_header = 'Select operation and factor to apply to selected values:';
                    operations = {'Set value','Add','Subtract','Multiply','Divide','Round','Floor','Ceil'};
                    prompts = {'Type of operation:'; 'Factor:'};
                    defAns = {[operations, find(ismember(operations, obj.batchModifyExpressionOperation), 1)]; ...
                              obj.batchModifyExpressionFactor};
                    modOpt.HeaderLines = 2;
                    modOpt.WindowWidth = 400;
                    modOpt.WindowHeight = 200;
                    modOpt.mibPath = obj.mibModel.mibPath;
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                        dlg_header, prompts, defAns, 'Batch modify', modOpt);
                    if isempty(answer); return; end
                    obj.batchModifyExpressionOperation = answer{1};
                    obj.batchModifyExpressionFactor    = answer{2};
                    value = str2double(answer{2});
                    [labelsList, labelValues, labelPositions] = ...
                        obj.mibModel.I{id}.annotations.getLabels();

                    for colId = 1:6
                        idx = find(obj.indices(:,2) == colId);
                        if isempty(idx); continue; end
                        if colId == 1
                            dlgOpt.MsgBoxOnly  = true;
                            dlgOpt.HeaderLines = 1;
                            dlgOpt.mibPath = obj.mibModel.mibPath;
                            utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                                'Ops!', {''}, {'Use the "Rename selected annotations" option to modify annotations name!'}, ...
                                'Annotations: batch modify annotations', dlgOpt);
                            return;
                        end
                        if colId == 2
                            A = labelValues(obj.indices(idx,1));
                        else
                            A = labelPositions(obj.indices(idx,1), colId-2);
                        end
                        switch answer{1}
                            case 'Set value'; A(:) = value;
                            case 'Add';       A = A + value;
                            case 'Subtract';  A = A - value;
                            case 'Multiply';  A = A * value;
                            case 'Divide';    A = A / value;
                            case 'Round';     A = round(A);
                            case 'Floor';     A = floor(A);
                            case 'Ceil';      A = ceil(A);
                        end
                        if colId == 2
                            labelValues(obj.indices(idx,1)) = A;
                        else
                            labelPositions(obj.indices(idx,1), colId-2) = A;
                        end
                    end
                    obj.mibModel.backup('annotations', 0);
                    obj.mibModel.I{id}.annotations.clearContents();
                    obj.mibModel.I{id}.annotations.addLabels(labelsList, labelPositions, labelValues);
                    obj.updateWidgets();
                    notify(obj.mibModel, 'ShowImage');

                case 'Rename'
                    if isempty(obj.indices); return; end
                    rowId = unique(obj.indices(:,1));
                    currentName = obj.mibModel.I{id}.annotations.getLabelsById(rowId(1));
                    if isempty(currentName); return; end

                    prompts = {'String to search for'; 'Replace with'};
                    defAns  = {currentName{1}; currentName{1}};
                    rnOpt.Focus = 1;
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                        '', prompts, defAns, 'Rename annotations', rnOpt);
                    if isempty(answer); return; end

                    obj.mibModel.backup('annotations', 0);
                    if isempty(answer{1})
                        obj.mibModel.I{id}.annotations.renameLabels(rowId, answer(2));
                    else
                        labels = obj.mibModel.I{id}.annotations.getLabelsById(rowId);
                        labels = strrep(labels, answer{1}, answer{2});
                        obj.mibModel.I{id}.annotations.renameLabels(rowId, labels);
                    end
                    obj.updateWidgets();
                    notify(obj.mibModel, 'ShowImage');

                case 'Jump'
                    if isempty(obj.indices); return; end
                    if isempty(obj.view.handles.annotationTable.Data); return; end
                    rowId = obj.indices(1);
                    data  = obj.view.handles.annotationTable.Data;
                    if rowId > size(data, 1); return; end

                    imgH = obj.mibModel.I{id}.image.height;
                    imgW = obj.mibModel.I{id}.image.width;
                    imgZ = obj.mibModel.I{id}.image.depth;

                    if orientation == 3      % XY
                        z = str2double(data{rowId, 3});
                        x = str2double(data{rowId, 4});
                        y = str2double(data{rowId, 5});
                    elseif orientation == 1  % ZX: horizontal X, vertical Z, slice Y
                        z = str2double(data{rowId, 5});
                        x = str2double(data{rowId, 4});
                        y = str2double(data{rowId, 3});
                    elseif orientation == 2  % ZY
                        z = str2double(data{rowId, 4});
                        x = str2double(data{rowId, 3});
                        y = str2double(data{rowId, 5});
                    end
                    t = str2double(data{rowId, 6});

                    if x > imgW || y > imgH || z > imgZ
                        dlgOpt.mibPath = obj.mibModel.mibPath;
                        dlgOpt.MsgBoxOnly  = true;
                        dlgOpt.Icon        = 'puffin_warning';
                        dlgOpt.HeaderLines = 1;
                        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                            'The annotation is outside of the image boundaries!', {''}, {''}, ...
                            'Wrong coordinates', dlgOpt);
                        return;
                    end

                    obj.mibModel.I{id}.moveView(x, y);

                    if obj.mibModel.I{id}.image.time > 1
                        newT = round(t);
                        obj.mibModel.I{id}.slices{5} = [newT, newT];
                        notify(obj.mibModel, 'FrameChanged');
                    end
                    if imgZ > 1
                        obj.mibModel.I{id}.slices{orientation}(1) = round(z);
                        obj.mibModel.I{id}.slices{orientation}(2) = round(z);
                        notify(obj.mibModel, 'SliceChanged');
                    else
                        notify(obj.mibModel, 'ShowImage');
                    end

                case 'Count'
                    if isempty(obj.indices); return; end
                    data = obj.view.handles.annotationTable.Data;
                    if isempty(data); return; end
                    annIds      = unique(obj.indices(:,1));
                    labelsList  = strtrim(data(annIds, 1));
                    labelsValues = cellfun(@str2double, data(annIds, 2));
                    totalValues  = sum(labelsValues);
                    uniqLabels   = unique(labelsList);
                    output = sprintf('----------------------------------------------------------\n');
                    output = [output sprintf('Counting annotations:\n')];
                    output = [output sprintf('Total selected categories: %d\n', numel(annIds))];
                    output = [output sprintf('Total selected values sum: %f\n', totalValues)];
                    for labelId = 1:numel(uniqLabels)
                        posIds     = ismember(labelsList, uniqLabels(labelId));
                        Occurrence = sum(labelsValues(posIds));
                        output = [output sprintf('%s: %f (%.3f%%)\n', ...
                            uniqLabels{labelId}, Occurrence, Occurrence/totalValues*100)]; %#ok<AGROW>
                    end
                    fprintf('%s', output);
                    clipboard('copy', output);
                    dlgOpt.MsgBoxOnly  = true;
                    dlgOpt.Icon        = 'puffin_info';
                    dlgOpt.HeaderLines = 1;
                    dlgOpt.mibPath = obj.mibModel.mibPath;
                    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                        'Counting annotations', {''}, {'Results printed to Command Window and copied to clipboard (use Ctrl+V to paste it)'}, ...
                        'Count annotations: done!', dlgOpt);

                case 'Clipboard'
                    if isempty(obj.indices); return; end
                    data = obj.view.handles.annotationTable.Data;
                    cols = min(obj.indices(:,2)):max(obj.indices(:,2));
                    d    = data(unique(obj.indices(:,1)), cols);
                    % flatten cell to tab-separated string
                    rows = size(d,1);
                    str  = '';
                    for r = 1:rows
                        str = [str strjoin(d(r,:), '\t') sprintf('\n')]; %#ok<AGROW>
                    end
                    clipboard('copy', str);
                    fprintf('Annotations: %d row(s) copied to the system clipboard.\n', rows);

                case 'ClipboardPaste'
                    if isempty(obj.indices); return; end
                    obj.mibModel.backup('annotations', 1);
                    startIndex = obj.indices(1,1);
                    colId      = obj.indices(1,2);

                    if colId == 1  % paste label text
                        values = strsplit(strtrim(clipboard('paste')));
                        values(cellfun(@isempty, values)) = [];
                        if isempty(values); return; end
                        endIndex  = startIndex + numel(values) - 1;
                        listOfIds = (startIndex:endIndex)';
                        [lT, lV, lP] = obj.mibModel.I{id}.annotations.getLabelsById(listOfIds);
                        obj.mibModel.I{id}.annotations.updateLabels(listOfIds, values(:), lP, lV);
                    elseif colId == 2  % paste values
                        values = str2num(clipboard('paste')); %#ok<ST2NM>
                        if isempty(values); return; end
                        endIndex  = startIndex + numel(values) - 1;
                        listOfIds = (startIndex:endIndex)';
                        [lT, ~, lP] = obj.mibModel.I{id}.annotations.getLabelsById(listOfIds);
                        obj.mibModel.I{id}.annotations.updateLabels(listOfIds, lT, lP, values(:));
                    else  % paste position column
                        values = str2num(clipboard('paste')); %#ok<ST2NM>
                        if isempty(values); return; end
                        endIndex  = startIndex + numel(values) - 1;
                        listOfIds = (startIndex:endIndex)';
                        [lT, lV, lP] = obj.mibModel.I{id}.annotations.getLabelsById(listOfIds);
                        lP(:, colId-2) = values(:);
                        obj.mibModel.I{id}.annotations.updateLabels(listOfIds, lT, lP, lV);
                    end
                    obj.updateWidgets();
                    notify(obj.mibModel, 'ShowImage');

                case 'Mask'
                    if isempty(obj.indices); return; end
                    prompts = {'Mode'; ...
                        'Spot size policy'; ...
                        'Spot radius in pixels (Fixed) or scale factor (Scaled)'};
                    defAns = {{'2D spots', '3D spots', 1}; {'Fixed value', 'Scaled from Value', 1}; 1};
                    maskOpt.mibPath = obj.mibModel.mibPath;
                    maskOpt.WindowWidth = 400;
                    maskOpt.WindowHeight = 200;
                    [answer, ~] = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                        '', prompts, defAns, 'Conversion to Mask', maskOpt);
                    if isempty(answer); return; end

                    if obj.mibModel.I{id}.maskExist
                        setDataOptions.blockModeSwitch = 0;
                        obj.mibModel.backup('mask', 1, setDataOptions);
                    end
                    obj.mibModel.I{id}.clearLayer('mask');
                    obj.mibModel.I{id}.maskExist = 1;

                    data      = obj.view.handles.annotationTable.Data;
                    selRows   = unique(obj.indices(:,1));
                    d2        = ceil(str2double(data(selRows, 3:6)));   % [z, x, y, t]
                    annotVals = str2double(data(selRows, 2));            % annotation values

                    imgWidth  = obj.mibModel.I{id}.image.width;
                    imgHeight = obj.mibModel.I{id}.image.height;
                    imgDepth  = obj.mibModel.I{id}.image.depth;
                    imgTime   = obj.mibModel.I{id}.image.time;

                    outBounds = d2(:,1) < 1 | d2(:,1) > imgDepth  | ...
                                d2(:,2) < 1 | d2(:,2) > imgWidth   | ...
                                d2(:,3) < 1 | d2(:,3) > imgHeight  | ...
                                d2(:,4) < 1 | d2(:,4) > imgTime;
                    nOutBounds       = sum(outBounds);
                    d2(outBounds, :) = [];
                    annotVals(outBounds) = [];

                    is3D     = strcmp(answer{1}, '3D spots');
                    isScaled = strcmp(answer{2}, 'Scaled from Value');
                    if is3D
                        pixX = obj.mibModel.I{id}.image.pixSize.x;
                        pixZ = obj.mibModel.I{id}.image.pixSize.z;
                    end

                    nPts               = size(d2, 1);
                    getOpt.id          = id;
                    getOpt.blockModeSwitch = 0;
                    pwb = core.PoolWaitbar(nPts, 'Preparing...', obj.view.gui, 'Annotations to Mask', true);

                    for pntId = 1:nPts
                        if pwb.getCancelState(); break; end
                        pwb.updateText(sprintf('Placing spot %d / %d...', pntId, nPts));

                        zc = d2(pntId, 1);
                        xc = d2(pntId, 2);
                        yc = d2(pntId, 3);
                        tc = d2(pntId, 4);
                        getOpt.t = [tc, tc];

                        % compute spot radius for this annotation
                        if isScaled
                            r = round(annotVals(pntId) * answer{3});
                        else
                            r = round(answer{3});
                        end
                        if isnan(r); r = 0; end
                        r = max(0, r);

                        % build per-point list of (z-slice, 2D-radius) pairs
                        if ~is3D || r == 0
                            zSlices = zc;
                            r2dList = r;
                        else
                            rz      = max(1, round(r * pixX / pixZ));
                            zSlices = max(1, zc - rz) : min(imgDepth, zc + rz);
                            r2dList = round(r * sqrt(max(0, ...
                                1 - ((zSlices - zc) ./ rz).^2)));
                        end

                        % place spot on each z-slice
                        for zIdx = 1:numel(zSlices)
                            zSlice = zSlices(zIdx);
                            r2d    = r2dList(zIdx);

                            if r2d == 0
                                % single-voxel
                                getOpt.x  = [xc, xc];
                                getOpt.y  = [yc, yc];
                                maskBlock = cell2mat(obj.mibModel.getData2D( ...
                                    'mask', zSlice, 3, NaN, getOpt));
                                maskBlock(1,1) = 1;
                            else
                                % disk spot via imdilate
                                se   = strel('disk', r2d, 0);
                                seed = zeros(2*r2d+1, 2*r2d+1, 'uint8');
                                seed(r2d+1, r2d+1) = 1;
                                spot = imdilate(seed, se);

                                xMin  = max(1, xc - r2d); xMax = min(imgWidth,  xc + r2d);
                                yMin  = max(1, yc - r2d); yMax = min(imgHeight, yc + r2d);
                                sxMin = xMin - xc + r2d + 1; sxMax = xMax - xc + r2d + 1;
                                syMin = yMin - yc + r2d + 1; syMax = yMax - yc + r2d + 1;

                                getOpt.x  = [xMin, xMax];
                                getOpt.y  = [yMin, yMax];
                                maskBlock = cell2mat(obj.mibModel.getData2D( ...
                                    'mask', zSlice, 3, NaN, getOpt));
                                maskBlock = uint8(maskBlock | spot(syMin:syMax, sxMin:sxMax));
                            end
                            obj.mibModel.setData2D(maskBlock, 'mask', zSlice, 3, NaN, getOpt);
                        end
                        pwb.increment();
                    end

                    pwb.deletePoolWaitbar();
                    obj.mibModel.showMask = true; 
                    eventdata = core.ToggleEventData({'selectionPanel'});
                    notify(obj.mibModel, 'UpdateGuiWidgets', eventdata);
                    notify(obj.mibModel, 'ShowImage');

                    if nOutBounds > 0
                        dlgOpt.MsgBoxOnly  = true;
                        dlgOpt.Icon        = 'puffin_warning';
                        dlgOpt.HeaderLines = 1;
                        dlgOpt.WindowHeight = 180;
                        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                            'Results', {''}, {sprintf('%d annotation(s) were out of image boundaries and not rendered.', ...
                            nOutBounds)}, 'Annotations: conversion to Mask', dlgOpt);
                    end

                case 'Interpolate'
                    if isempty(obj.indices); return; end
                    uniqueRows = unique(obj.indices(:,1));
                    if numel(uniqueRows) < 2; return; end
                    [labelNames, labelValues, labelPosition, labelIndices] = ...
                        obj.mibModel.I{id}.annotations.getLabelsById(uniqueRows);

                    if numel(unique(labelPosition(:,1))) ~= numel(uniqueRows)
                        dlgOpt.MsgBoxOnly  = true;
                        dlgOpt.HeaderLines = 1;
                        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                            'Error', {''}, {'Please select annotations with exactly 1 per slice!'}, ...
                            'Error', dlgOpt);
                        return;
                    end

                    nPts = numel(uniqueRows);
                    interpolationMethod = {'linear'};
                    if nPts > 2; interpolationMethod{end+1} = 'cubic'; end
                    if nPts > 3; interpolationMethod{end+1} = 'spline'; end
                    if nPts > 2
                        interpolationMethod{end+1} = 1;
                        [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                            '', {'Specify interpolation method:'}, {interpolationMethod}, ...
                            'Interpolation method');
                        if isempty(answer); return; end
                        interpolationMethod = interpolationMethod{selIndex(1)};
                    else
                        interpolationMethod = 'linear';
                    end

                    obj.mibModel.backup('annotations', 0);
                    [~, ids]   = sort(labelPosition, 1);
                    labelPosition = labelPosition(ids(:,1), :);
                    labelValues   = labelValues(ids(:,1));
                    labelNames    = labelNames(ids(:,1));
                    z_range  = min(labelPosition(:,1)):max(labelPosition(:,1));
                    x_interp = interp1(labelPosition(:,1), labelPosition(:,2), z_range, interpolationMethod);
                    y_interp = interp1(labelPosition(:,1), labelPosition(:,3), z_range, interpolationMethod);
                    v_interp = interp1(labelPosition(:,1), labelValues, z_range, interpolationMethod);
                    newPositions = [z_range', x_interp', y_interp', ...
                        repmat(labelPosition(1,4), [numel(z_range), 1])];
                    newLabelName = [];
                    for zId = 1:size(labelPosition,1)-1
                        noSlices = labelPosition(zId+1,1)-1 - labelPosition(zId,1) + 1;
                        newLabelName = [newLabelName; repmat(labelNames(zId), [noSlices, 1])]; %#ok<AGROW>
                    end
                    newLabelName(end+1) = labelNames(end);
                    obj.mibModel.I{id}.annotations.removeLabels(labelIndices);
                    obj.mibModel.I{id}.annotations.addLabels(newLabelName, newPositions, v_interp);
                    obj.updateWidgets();
                    notify(obj.mibModel, 'ShowImage');

                case 'ConvertModel'
                    obj.convertModelFromAnnotations();

                case 'Export'
                    if isempty(obj.indices); return; end
                    indList       = unique(obj.indices(:,1));
                    labelText     = obj.mibModel.I{id}.annotations.labelText(indList);
                    labelValue    = obj.mibModel.I{id}.annotations.labelValue(indList);
                    labelPosition = obj.mibModel.I{id}.annotations.labelPosition(indList, :);
                    obj.saveAnnotationsToFile(labelText, labelPosition, labelValue);

                case 'CropPatches'
                    if isempty(obj.indices); return; end
                    indList = unique(obj.indices(:,1));
                    annotationLabels.positions = obj.mibModel.I{id}.annotations.labelPosition(indList, :);
                    annotationLabels.names     = obj.mibModel.I{id}.annotations.labelText(indList);
                    utils.startController(obj, 'controllers.CropObjects', obj, false, annotationLabels);

                case 'Imaris'
                    if isempty(obj.indices); return; end
                    annIds        = unique(obj.indices(:,1));
                    labelText     = obj.mibModel.I{id}.annotations.labelText(annIds);
                    labelValue    = obj.mibModel.I{id}.annotations.labelValue(annIds);
                    labelPosition = obj.mibModel.I{id}.annotations.labelPosition(annIds, :);
                    % reshape from [z,x,y,t] to [x,y,z,t] and convert to physical units
                    labelPosition = [labelPosition(:,2), labelPosition(:,3), labelPosition(:,1), labelPosition(:,4)];
                    bb      = obj.mibModel.I{id}.image.boundingBox;
                    pixSize = obj.mibModel.I{id}.image.pixSize;
                    labelPosition(:,1) = labelPosition(:,1)*pixSize.x + bb(1) - pixSize.x/2;
                    labelPosition(:,2) = labelPosition(:,2)*pixSize.y + bb(3) - pixSize.y/2;
                    labelPosition(:,3) = labelPosition(:,3)*pixSize.z + bb(5) - pixSize.z;

                    if isnan(obj.imarisOptions.radii)
                        obj.imarisOptions.radii = ...
                            (max(labelPosition(:,1)) - min(labelPosition(:,1))) / 50 / max(labelValue);
                    end
                    prompts = {'Radius scaling factor for spots:'; ...
                               sprintf('Color [R G B A] (0..1):'); ...
                               'Name for spots:'};
                    defAns = {num2str(obj.imarisOptions.radii); ...
                              num2str(obj.imarisOptions.color); ...
                              labelText{1}};
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                        '', prompts, defAns, 'Export to Imaris');
                    if isempty(answer); return; end
                    obj.imarisOptions.radii = str2double(answer{1});
                    obj.imarisOptions.color = str2num(answer{2}); %#ok<ST2NM>
                    obj.imarisOptions.name  = answer{3};
                    imarisOpt.radii = labelValue * obj.imarisOptions.radii;
                    imarisOpt.color = obj.imarisOptions.color;
                    imarisOpt.name  = obj.imarisOptions.name;
                    obj.mibModel.connImaris = mibSetImarisSpots(labelPosition, obj.mibModel.connImaris, imarisOpt);

                case 'Delete'
                    if isempty(obj.indices); return; end
                    data  = obj.view.handles.annotationTable.Data;
                    if isempty(data); return; end
                    rowId = unique(obj.indices(:,1));
                    if numel(rowId) == 1
                        button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                            sprintf('Delete annotation?\n\nLabel: %s\nCoords (z,x,y,t): %s %s %s %s', ...
                            data{rowId,1}, data{rowId,3}, data{rowId,4}, data{rowId,5}, data{rowId,6}), ...
                            'Delete annotation', 'Delete', 'Cancel', 'Cancel');
                    else
                        button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                            'Delete the selected annotations?', ...
                            'Delete annotations', 'Delete', 'Cancel', 'Cancel');
                    end
                    if strcmp(button, 'Cancel'); return; end

                    obj.mibModel.backup('annotations', 0);
                    rowNames = obj.view.handles.annotationTable.RowName;
                    removeIds = cellfun(@str2double, rowNames(rowId));
                    obj.mibModel.I{id}.annotations.removeLabels(removeIds);
                    obj.updateWidgets();
                    notify(obj.mibModel, 'ShowImage');
            end
        end

        % -----------------------------------------------------------------
        function convertModelFromAnnotations(obj)
            % CONVERTMODELFROMANNOTATIONS - Convert a 63/255-material model into an indexed-object model numbered by the annotation names.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.convertModelFromAnnotations()
            %
            % Takes the first run of digits in the name of each annotation (``'cell 305b'``
            % -> 305, ``'12_nucleus_3'`` -> 12, leading zeros dropped) and gives that index
            % to the object under the annotation. The object is the connected component of
            % the material at the annotation voxel (the position rounded to the nearest
            % voxel), with the connectivity chosen in the dialog: 3D (26 or 6 neighbours)
            % through the volume, or 2D (8 or 4) in the plane of the annotation only.
            % Objects without an annotation are not kept: the new model holds only the
            % numbered objects. The mask and the selection are kept. The dialog also picks
            % the annotations to use (the selected rows of the table or all of them) and
            % the colors of the objects:
            %
            %   - **Material colors** - each object takes the color of the material it
            %     came from, so the model looks as before. The color is written to row
            %     ``mod(index - 1, 65535) + 1`` of ``labels.materialColors``, the row the
            %     display uses for that index; indices above 65535 share rows with lower
            %     ones, so when two objects of different materials land on one row the
            %     later one sets the color. A material without a color row keeps the
            %     generated color
            %   - **Material color variation** - as *Material colors*, then the color is
            %     varied per object the way the Membrane instances plugin varies seed
            %     colors (its ``seedMaterialColors``): converted to HSV, the hue kept,
            %     saturation and value moved by up to +-0.30 and +-0.25 by the R2
            %     low-discrepancy sequence of the object index, so objects with nearby
            %     indices of one material differ clearly while keeping its hue. The
            %     same index always gets the same color. Grays (saturation below 0.05)
            %     keep their saturation; saturation is kept at 0.2 or above and value
            %     at 0.35 or above, to avoid white and black objects
            %   - **Random colors** - the colors generated by the conversion
            %
            % **Finding an object.** A box is grown around the annotation voxel: it starts
            % at 65 x 65 x 17 voxels (one plane in 2D), the material is read inside it and
            % the component holding the annotation voxel is taken from ``bwconncomp`` (not
            % ``imreconstruct``, which was about 100 times slower per box). The start box is
            % small because the cost of each object grows with its box, and a larger object
            % only costs a few doublings. While that component touches a face of the
            % box that is not the image border, the box is doubled across that face and the
            % component found again. The volume is therefore never read whole, which is
            % what makes the tool work on BigData. There a box may not grow past
            % 2^28 voxels; an object that needs more is skipped and reported. A single-plane
            % box takes the 2D connectivity of the chosen one (26 -> 8, 6 -> 4).
            %
            % Every object is found before anything changes, so a Cancel during the search
            % leaves the model as it was. Then:
            %
            %   - **Standard** - the objects are drawn into a new uint16 array (uint32 when
            %     an index exceeds 65535), the model is converted to 65535 (or 4294967295)
            %     with ``core.MibDataset.convertModel``, which unpacks the mask and the
            %     selection of a 63 model, and the array replaces its labels. One
            %     ``'modelLayers'`` backup is taken first, so Ctrl+Z restores the original
            %     model with its materials.
            %   - **BigData** - only a 63-material store is accepted, with indices up to
            %     1073741823. ``models.MibModel.convertModel`` creates a new 16383 store
            %     (uint16) when every number fits, a 1073741823 store (packed uint32,
            %     twice the disk space) otherwise, with
            %     ``convertOptions.keepMaterials = false`` (mask and selection only; the user
            %     picks the path; the 63 store stays on disk unchanged), then each object is
            %     written into it as a read-modify-write of its box at full resolution. There
            %     is no undo. A Cancel while writing stops there, and the report says how
            %     many objects were written and where the 63 store is.
            %
            % Annotations that number nothing are counted in the report by reason: no
            % number in the name (or the number 0), an index above what the model can hold,
            % outside the image, on the background, on an object already numbered from
            % another annotation with a different number (the first number is kept), or
            % (BigData) on an object too large to read. An annotation on an object already
            % numbered with the same number is not a problem and is not reported. One
            % number on several separate objects gives all of them that index, which makes
            % them one object; the report lists such numbers (per time point, and per slice
            % for the 2D connectivity, where one number on consecutive slices is the normal
            % way to build one object). The full report also goes to the Command Window.
            %
            % The new model has ``labels.objects3D = true``: an index names one object
            % wherever it is, so the next free index is the largest one in the volume. The
            % instance index of the dataset is cleared.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.convertModelFromAnnotations: triggered\n');
            end

            id = obj.BatchOpt.id;
            dataset = obj.mibModel.I{id};
            dialogTitle = 'Convert model to indexed objects';
            msgOpt.MsgBoxOnly  = true;
            msgOpt.Icon        = 'puffin_warning';
            msgOpt.HeaderLines = 1;
            msgOpt.mibPath     = obj.mibModel.mibPath;

            %% Checks
            if dataset.enableSelection == 0
                utils.dlgs.inputUniversalDlg(obj.view.gui, 'The models are switched off!', {''}, ...
                    {'Please enable the "Enable selection" option in Preferences (Ribbon -> Home -> Preferences) and try again.'}, ...
                    dialogTitle, msgOpt);
                return;
            end
            if dataset.datasetType(1) == 'V'
                utils.dlgs.inputUniversalDlg(obj.view.gui, 'Not available in Virtual mode!', {''}, ...
                    {'Please switch to the standard mode and try again.'}, dialogTitle, msgOpt);
                return;
            end
            isBigData = dataset.datasetType(1) == 'B';
            if ~dataset.modelExist
                utils.dlgs.inputUniversalDlg(obj.view.gui, 'No model exists!', {''}, ...
                    {'Please create or load a model with materials first.'}, dialogTitle, msgOpt);
                return;
            end
            if dataset.labels.maxMaterials > 255
                utils.dlgs.inputUniversalDlg(obj.view.gui, 'The model already has indexed objects!', {''}, ...
                    {sprintf(['This tool numbers the objects of a model with 63 or 255 materials. ' ...
                    'The current model is of the %d type.'], dataset.labels.maxMaterials)}, dialogTitle, msgOpt);
                return;
            end

            [labelText, ~, labelPosition] = dataset.annotations.getLabels();
            annotationCount = numel(labelText);
            if annotationCount == 0
                utils.dlgs.inputUniversalDlg(obj.view.gui, 'There are no annotations!', {''}, ...
                    {'Please add annotations with numbers in their names first.'}, dialogTitle, msgOpt);
                return;
            end
            selectedRows = [];
            if ~isempty(obj.indices)
                selectedRows = unique(obj.indices(:,1));
                selectedRows(selectedRows > annotationCount) = [];
            end

            %% Settings
            sourceList = {sprintf('All annotations (%d)', annotationCount)};
            if ~isempty(selectedRows)
                sourceList = [{sprintf('Selected annotations (%d)', numel(selectedRows))}, sourceList];
            end
            connectivityList = {'3D, 26 neighbours', '3D, 6 neighbours', '2D, 8 neighbours', '2D, 4 neighbours'};
            connectivityValues = [26 6 8 4];
            colorList = {'Material colors', 'Material color variation', 'Random colors'};
            header = sprintf(['Converts the model of materials into a model of indexed objects, ' ...
                'where every object has its own number.\n' ...
                'Place an annotation on each object to keep: the first number in the annotation ' ...
                'name becomes the number of the object under it ("cell 305" gives object 305).\n' ...
                'Objects without an annotation are not kept; the mask and selection stay as they are.']);
            prompts = {'Annotations to use:'; 'Connect the voxels of an object in:'; 'Object colors:'};
            defAns = {[sourceList, {1}]; [connectivityList, {1}]; [colorList, {1}]};
            setOpt.HeaderLines = 6;
            setOpt.WindowWidth = 500;
            setOpt.mibPath = obj.mibModel.mibPath;
            [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, header, prompts, defAns, ...
                dialogTitle, setOpt);
            if isempty(answer); return; end

            if ~isempty(selectedRows) && selIndex(1) == 1
                annotationIds = selectedRows(:);
            else
                annotationIds = (1:annotationCount)';
            end
            connectivity = connectivityValues(selIndex(2));
            is3D = connectivity > 8;
            keepMaterialColors = selIndex(3) < 3;    % 1 = material colors, 2 = their variation
            varyMaterialColors = selIndex(3) == 2;
            materialColors = dataset.labels.materialColors;   % the conversion replaces them

            %% Find the object under each annotation; nothing changes yet
            if isBigData
                maxIndex = 1073741823;     % the largest BigData model store (packed uint32)
                voxelBudget = 2^28;        % largest box read for one object
                oldStorePath = char(dataset.labels.modelStorePath);
            else
                maxIndex = 4294967295;
                voxelBudget = Inf;
            end
            volumeSize = [dataset.image.height, dataset.image.width, dataset.image.depth];
            timePoints = dataset.image.time;
            names = reshape(labelText(annotationIds), [], 1);
            numbers = str2double(regexp(names, '\d+', 'match', 'once'));
            positions = labelPosition(annotationIds, :);                                  % [z x y t]
            seeds = round([positions(:,3), positions(:,2), positions(:,1)]);              % [y x z]
            seedTimes = round(positions(:,4));
            startHalfSize = [32 32 8];
            if ~is3D; startHalfSize(3) = 0; end
            boxOptions = struct('blockModeSwitch', 0, 'id', id);
            if isBigData; boxOptions.magFactor = 1; end   % BigData reads and writes at full resolution

            % reason codes: 0 = new object, 1 = no number, 2 = index too large,
            % 3 = outside, 4 = background, 5 = numbered already with another number,
            % 6 = object too large, 7 = numbered already with the same number
            reason = zeros(numel(annotationIds), 1);
            objectBoxes = zeros(0, 6);       % [y1 y2 x1 x2 z1 z2] per object
            objectTimes = zeros(0, 1);
            objectNumbers = zeros(0, 1);
            objectMaterials = zeros(0, 1);   % material the object came from, for its color
            objectVoxels = {};               % linear indices of the object inside its box

            wb = uiprogressdlg(obj.view.gui, 'Title', dialogTitle, 'Value', 0, 'Cancelable', 'on', ...
                'Message', 'Finding the objects under the annotations...');
            for annIdx = 1:numel(annotationIds)
                if wb.CancelRequested
                    delete(wb);
                    fprintf('Convert model from annotations: cancelled, the model was not changed\n');
                    return;
                end
                wb.Value = 0.9 * (annIdx - 1) / numel(annotationIds);

                number = numbers(annIdx);
                seed = seeds(annIdx, :);
                timePoint = seedTimes(annIdx);
                if isnan(number) || number < 1
                    reason(annIdx) = 1; continue;
                end
                if number > maxIndex
                    reason(annIdx) = 2; continue;
                end
                if any(isnan(seed)) || any(seed < 1) || any(seed > volumeSize) || ...
                        isnan(timePoint) || timePoint < 1 || timePoint > timePoints
                    reason(annIdx) = 3; continue;
                end
                owner = localFindObject(objectBoxes, objectTimes, objectVoxels, seed, timePoint);
                if owner > 0
                    if objectNumbers(owner) == number
                        reason(annIdx) = 7;
                    else
                        reason(annIdx) = 5;
                    end
                    continue;
                end
                seedBox = [seed(1) seed(1) seed(2) seed(2) seed(3) seed(3)];
                material = cell2mat(obj.mibModel.getData3D('labels', timePoint, 3, NaN, ...
                    localBoxOptions(boxOptions, seedBox)));
                material = double(material(1));
                if material == 0
                    reason(annIdx) = 4; continue;
                end
                box = [max(1, seed - startHalfSize); min(volumeSize, seed + startHalfSize)];
                box = box(:)';                                                            % [y1 y2 x1 x2 z1 z2]
                [voxels, box] = localGrowObject(obj.mibModel, boxOptions, timePoint, material, ...
                    seed, box, volumeSize, connectivity, is3D, voxelBudget);
                if isempty(voxels)
                    reason(annIdx) = 6; continue;
                end
                objectBoxes(end+1, :) = box; %#ok<AGROW>
                objectTimes(end+1, 1) = timePoint; %#ok<AGROW>
                objectNumbers(end+1, 1) = number; %#ok<AGROW>
                objectMaterials(end+1, 1) = material; %#ok<AGROW>
                objectVoxels{end+1, 1} = voxels; %#ok<AGROW>
            end

            if isempty(objectNumbers)
                delete(wb);
                report = localReport(reason, names, maxIndex, voxelBudget);
                fprintf('Convert model from annotations: no object was numbered, the model was not changed\n%s\n', report);
                utils.dlgs.inputUniversalDlg(obj.view.gui, 'No object was numbered, the model was not changed', ...
                    {''}, {localEscapeHtml(report)}, dialogTitle, msgOpt);
                return;
            end
            highestNumber = max(objectNumbers);

            %% Write the new model
            writtenCount = numel(objectNumbers);
            if ~isBigData
                wb.Message = 'Writing the indexed objects...';
                if highestNumber > 65535
                    newType = 4294967295; dataClass = 'uint32';
                else
                    newType = 65535; dataClass = 'uint16';
                end
                newLabels = zeros([volumeSize, 1, timePoints], dataClass);
                for objIdx = 1:numel(objectNumbers)
                    if wb.CancelRequested
                        delete(wb);
                        fprintf('Convert model from annotations: cancelled, the model was not changed\n');
                        return;
                    end
                    box = objectBoxes(objIdx, :);
                    [rows, cols, planes] = ind2sub(box([2 4 6]) - box([1 3 5]) + 1, double(objectVoxels{objIdx}));
                    fullIndices = sub2ind([volumeSize, timePoints], rows + box(1) - 1, cols + box(3) - 1, ...
                        planes + box(5) - 1, objectTimes(objIdx) + zeros(size(rows)));
                    newLabels(fullIndices) = objectNumbers(objIdx);
                end
                wb.Value = 0.95;
                % Ctrl+Z brings back the 63/255 model with its materials
                obj.mibModel.backup('modelLayers', 1, struct('id', id));
                dataset.convertModel(newType);          % unpacks mask and selection of a 63 model
                dataset.labels.data = newLabels;
                dataset.labels.materialsCount = highestNumber;
                dataset.labels.objects3D = true;        % an index names one object wherever it is
                dataset.instanceIndex = [];
                if keepMaterialColors
                    dataset.labels.materialColors = localMaterialColors(dataset.labels.materialColors, ...
                        materialColors, objectNumbers, objectMaterials, varyMaterialColors);
                end
                delete(wb);
                cancelledAt = 0;
            else
                % the conversion asks for the path of the new store and shows its own
                % progress; 16383 (2 bytes per voxel) when the numbers fit, else the
                % packed uint32 store (4 bytes per voxel)
                delete(wb);
                if highestNumber > 16383
                    newType = 1073741823;
                else
                    newType = 16383;
                end
                if ~obj.mibModel.convertModel(newType, struct('id', id), struct('keepMaterials', false))
                    fprintf('Convert model from annotations: the model was not converted and was not changed\n');
                    return;
                end
                wb = uiprogressdlg(obj.view.gui, 'Title', dialogTitle, 'Value', 0, 'Cancelable', 'on', ...
                    'Message', 'Writing the indexed objects...');
                cancelledAt = 0;
                for objIdx = 1:numel(objectNumbers)
                    if wb.CancelRequested
                        cancelledAt = objIdx;
                        break;
                    end
                    wb.Value = (objIdx - 1) / numel(objectNumbers);
                    writeOptions = localBoxOptions(boxOptions, objectBoxes(objIdx, :));
                    crop = cell2mat(obj.mibModel.getData3D('labels', objectTimes(objIdx), 3, NaN, writeOptions));
                    crop(objectVoxels{objIdx}) = objectNumbers(objIdx);
                    obj.mibModel.setData3D(crop, 'labels', objectTimes(objIdx), 3, [], writeOptions);
                end
                if cancelledAt > 0; writtenCount = cancelledAt - 1; end
                labels = obj.mibModel.I{id}.labels;
                if writtenCount > 0
                    labels.maxIndexUsed = max(labels.maxIndexUsed, max(objectNumbers(1:writtenCount)));
                end
                labels.materialsCount = labels.maxIndexUsed;
                if keepMaterialColors && writtenCount > 0
                    labels.materialColors = localMaterialColors(labels.materialColors, materialColors, ...
                        objectNumbers(1:writtenCount), objectMaterials(1:writtenCount), varyMaterialColors);
                end
                labels.writeMaterialMetadata();
                labels.saveLevelMap();
                delete(wb);
            end

            notify(obj.mibModel, 'UpdateGuiWidgets', core.ToggleEventData({'ribbonModel', 'checkboxes'}));
            notify(obj.mibModel, 'ShowImage');

            %% Report
            if cancelledAt > 0
                resultHeader = 'Cancelled while writing the objects';
                summary = sprintf(['Written: %d of %d objects. The new model store holds only these.\n' ...
                    'The 63-material model is unchanged at:\n%s\nLoad it again to return to it.'], ...
                    writtenCount, numel(objectNumbers), oldStorePath);
            else
                resultHeader = 'The model was converted to indexed objects';
                summary = sprintf('Numbered objects: %d, indices %d to %d\nNew model type: %d', ...
                    writtenCount, min(objectNumbers), highestNumber, newType);
                if isBigData
                    summary = sprintf(['%s\nThere is no undo. The 63-material model is unchanged at:\n%s\n' ...
                        'Load it again to return to it.'], summary, oldStorePath);
                else
                    summary = sprintf('%s\nPress Ctrl+Z to return to the previous model.', summary);
                end
            end
            summary = sprintf('%s\nObjects without an annotation were not kept.', summary);

            % numbers on several separate objects: per time point, and per slice for 2D objects
            if is3D
                numberKeys = [objectNumbers, objectTimes];
            else
                numberKeys = [objectNumbers, objectTimes, objectBoxes(:, 5)];
            end
            [uniqueKeys, ~, keyIds] = unique(numberKeys, 'rows');
            sharedNumbers = unique(uniqueKeys(accumarray(keyIds, 1) > 1, 1));
            if ~isempty(sharedNumbers)
                summary = sprintf(['%s\n\nThese numbers were given to more than one separate object, ' ...
                    'each set is now one object: %s'], summary, localListNumbers(sharedNumbers));
            end
            report = localReport(reason, names, maxIndex, voxelBudget);
            if ~isempty(report)
                summary = sprintf('%s\n\n%s', summary, report);
            end
            fprintf('%s\n%s\n', resultHeader, summary);

            resultOpt = msgOpt;
            if cancelledAt == 0 && isempty(report) && isempty(sharedNumbers)
                resultOpt.Icon = 'puffin_info';
            end
            resultOpt.WindowWidth = 500;
            utils.dlgs.inputUniversalDlg(obj.view.gui, resultHeader, {''}, {localEscapeHtml(summary)}, ...
                dialogTitle, resultOpt);
        end

        % -----------------------------------------------------------------
        function gui_KeyPressFcn(obj, eventdata)
            % GUI_KEYPRESSFCN - Key-press callback for the main figure window.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.gui_KeyPressFcn(eventdata)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.gui_KeyPressFcn: triggered\n');
            end

            if ismember('control', eventdata.Modifier)
                switch lower(eventdata.Key)
                    % Ctrl+Z undo - currently not implemented for annotations
                end
            end
        end

        % -----------------------------------------------------------------
        function annotationTable_KeyPressFcn(obj, eventdata)
            % ANNOTATIONTABLE_KEYPRESSFCN - Key-press callback for the annotation table; handles reorder shortcuts.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.annotationTable_KeyPressFcn(eventdata)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.annotationTable_KeyPressFcn: triggered\n');
            end

            if ismember('control', eventdata.Modifier)
                if ismember('shift', eventdata.Modifier)
                    switch eventdata.Key
                        case 'uparrow';   obj.tableContextMenu_cb('OrderTop');
                        case 'downarrow'; obj.tableContextMenu_cb('OrderBottom');
                    end
                else
                    switch eventdata.Key
                        case 'uparrow';   obj.tableContextMenu_cb('OrderUp');
                        case 'downarrow'; obj.tableContextMenu_cb('OrderDown');
                    end
                end
            end
        end

        % -----------------------------------------------------------------
        function resortTablePopup_Callback(obj)
            % RESORTTABLEPOPUP_CALLBACK - Resort the annotation list by the chosen column.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.resortTablePopup_Callback()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.resortTablePopup_Callback: triggered\n');
            end

            obj.mibModel.backup('annotations', 1);
            sortBy = lower(obj.view.handles.resortTablePopup.Value);
            obj.mibModel.I{obj.BatchOpt.id}.annotations.sortLabels(sortBy);
            obj.updateWidgets();
        end

        % -----------------------------------------------------------------
        function settingsBtn_Callback(obj)
            % SETTINGSBTN_CALLBACK - Open the annotation display settings dialog.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.settingsBtn_Callback()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.settingsBtn_Callback: triggered\n');
            end

            prompts = {'Show annotations for extra slices (positive integer or 0):'; ...
                       'Annotation font size:'; ...
                       'Pick new color:'};
            defAns = { ...
                sprintf('%d', obj.mibModel.preferences.SegmTools.Annotations.ShownExtraDepth); ...
                {'1 (pt 8)', '2 (pt 10)', '3 (pt 12)', '4 (pt 14)', '5 (pt 16)', ...
                 '6 (pt 18)', '7 (pt 20)', obj.mibModel.preferences.SegmTools.Annotations.FontSize}; ...
                false};
            sOpt.WindowWidth = 450;
            sOpt.WindowHeight = 190;
            sOpt.mibPath = obj.mibModel.mibPath;
            [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, [], prompts, defAns, 'Annotation settings', sOpt);
            if isempty(answer); return; end

            value = str2double(answer{1});
            if isnan(value)
                dlgOpt.MsgBoxOnly  = true;
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                    'Wrong value', {''}, {sprintf('Invalid value "%s" - enter a non-negative integer.', answer{1})}, ...
                    'Error', dlgOpt);
                return;
            end

            if answer{3}
                c = uisetcolor(obj.mibModel.preferences.SegmTools.Annotations.Color, ...
                    'Annotations color');
                if numel(c) > 1
                    obj.mibModel.preferences.SegmTools.Annotations.Color = c;
                end
            end

            obj.mibModel.preferences.SegmTools.Annotations.ShownExtraDepth = abs(round(value));
            obj.mibModel.preferences.SegmTools.Annotations.FontSize = selIndex(2);
            notify(obj.mibModel, 'ShowImage');
        end

        % -----------------------------------------------------------------
        function helpBtn_Callback(obj)
            % HELPBTN_CALLBACK - Open the Annotations help page in the browser.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.helpBtn_Callback()
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Annotations.helpBtn_Callback: triggered\n');
            end

            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'panels', 'segm', 'segm-annotations.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/panels/segm/segm-annotations.html');
        end

    end
end

% =====================================================================
% Local functions of convertModelFromAnnotations
% =====================================================================
function options = localBoxOptions(boxOptions, box)
% getData3D / setData3D options for the box [y1 y2 x1 x2 z1 z2]
options = boxOptions;
options.y = box(1:2);
options.x = box(3:4);
options.z = box(5:6);
end

% =====================================================================
function owner = localFindObject(objectBoxes, objectTimes, objectVoxels, seed, timePoint)
% Index of the object found already that holds the voxel seed [y x z], or 0.
% Two annotations on one object must not find it twice: the second would write
% its number over the first one's object.
owner = 0;
if isempty(objectTimes); return; end
candidates = find(objectTimes == timePoint & ...
    objectBoxes(:,1) <= seed(1) & objectBoxes(:,2) >= seed(1) & ...
    objectBoxes(:,3) <= seed(2) & objectBoxes(:,4) >= seed(2) & ...
    objectBoxes(:,5) <= seed(3) & objectBoxes(:,6) >= seed(3));
for candidate = reshape(candidates, 1, [])
    box = objectBoxes(candidate, :);
    localIndex = sub2ind(box([2 4 6]) - box([1 3 5]) + 1, ...
        seed(1) - box(1) + 1, seed(2) - box(3) + 1, seed(3) - box(5) + 1);
    if any(objectVoxels{candidate} == localIndex)
        owner = candidate;
        return;
    end
end
end

% =====================================================================
function [voxels, box] = localGrowObject(mibModel, boxOptions, timePoint, material, seed, box, ...
    volumeSize, connectivity, is3D, voxelBudget)
% Connected component of material holding the voxel seed [y x z], found in a box
% grown until the component no longer touches a face that is not the image
% border; see convertModelFromAnnotations. Returns the linear indices of the component
% inside the final box [y1 y2 x1 x2 z1 z2], or [] when the box would exceed
% voxelBudget voxels.
%
% The component is taken from bwconncomp + labelmatrix at the seed voxel rather
% than from imreconstruct: on a 257 x 257 x 33 box imreconstruct took 175 ms,
% bwconncomp about 100 times less.
voxels = [];
planeConnectivity = 8;
if connectivity == 6 || connectivity == 4; planeConnectivity = 4; end
while true
    crop = cell2mat(mibModel.getData3D('labels', timePoint, 3, material, localBoxOptions(boxOptions, box))) > 0;
    cropSize = size(crop, 1, 2, 3);
    if cropSize(3) == 1   % one plane takes the 2D connectivity
        components = bwconncomp(crop, planeConnectivity);
    else
        components = bwconncomp(crop, connectivity);
    end
    componentMap = labelmatrix(components);
    seedComponent = componentMap(seed(1) - box(1) + 1, seed(2) - box(3) + 1, seed(3) - box(5) + 1);
    componentVoxels = components.PixelIdxList{seedComponent};
    [rows, cols, planes] = ind2sub(cropSize, componentVoxels);
    touched = [box(1) > 1 && min(rows) == 1, ...
        box(2) < volumeSize(1) && max(rows) == cropSize(1), ...
        box(3) > 1 && min(cols) == 1, ...
        box(4) < volumeSize(2) && max(cols) == cropSize(2), ...
        is3D && box(5) > 1 && min(planes) == 1, ...
        is3D && box(6) < volumeSize(3) && max(planes) == cropSize(3)];
    if ~any(touched); break; end

    % double the box across every face the object touches
    extent = box([2 4 6]) - box([1 3 5]) + 1;
    for axisId = 1:3
        if touched(2*axisId - 1)
            box(2*axisId - 1) = max(1, box(2*axisId - 1) - extent(axisId));
        end
        if touched(2*axisId)
            box(2*axisId) = min(volumeSize(axisId), box(2*axisId) + extent(axisId));
        end
    end
    if prod(box([2 4 6]) - box([1 3 5]) + 1) > voxelBudget; return; end
end
voxels = componentVoxels;
if prod(cropSize) < double(intmax('uint32')); voxels = uint32(voxels); end
end

% =====================================================================
function report = localReport(reason, names, maxIndex, voxelBudget)
% Annotations that numbered nothing, by reason, with up to five names each; ''
% when there are none. Reason 7 (on an object numbered already with the same
% number) is not a problem and is not listed.
descriptions = {1, 'no number in the name'; ...
    2, sprintf('a number above %d, the largest index this model can hold', maxIndex); ...
    3, 'outside the image'; ...
    4, 'on the background, with no material under it'; ...
    5, 'on an object numbered already from another annotation with a different number; the first number was kept'; ...
    6, sprintf('on an object larger than %d voxels, too large to read', voxelBudget)};
reportLines = {};
for row = 1:size(descriptions, 1)
    hits = find(reason == descriptions{row, 1});
    if isempty(hits); continue; end
    shownNames = names(hits(1:min(5, numel(hits))));
    nameList = strjoin(strcat('"', shownNames, '"'), ', ');
    if numel(hits) > 5; nameList = [nameList ', ...']; end %#ok<AGROW>
    reportLines{end+1} = sprintf('- %s: %d (%s)', descriptions{row, 2}, numel(hits), nameList); %#ok<AGROW>
end
report = '';
if isempty(reportLines); return; end
report = sprintf('Annotations not used: %d\n%s', sum(reason >= 1 & reason <= 6), strjoin(reportLines, newline));
end

% =====================================================================
function colors = localMaterialColors(colors, materialColors, objectNumbers, objectMaterials, varyColors)
% Give every object the color of the material it came from, varied per object
% when varyColors is true (see "Material color variation" in
% convertModelFromAnnotations; the same formula as seedMaterialColors of the
% Membrane instances plugin). The display picks the color of index k from row
% mod(k - 1, 65535) + 1, so that row is set; a material without a color row keeps
% the generated color.
if size(materialColors, 2) ~= 3; return; end
hasColor = objectMaterials <= size(materialColors, 1);
objectNumbers = objectNumbers(hasColor);
rows = mod(objectNumbers - 1, 65535) + 1;
if max([rows; 0]) > size(colors, 1)
    colors(end+1:max(rows), :) = rand(max(rows) - size(colors, 1), 3);
end
objectColors = materialColors(objectMaterials(hasColor), :);
if varyColors && ~isempty(objectColors)
    hsvColors = rgb2hsv(objectColors);
    saturationOffset = mod(0.5 + objectNumbers * 0.7548776662466927, 1);   % R2 sequence, 0-1
    valueOffset = mod(0.5 + objectNumbers * 0.5698402909980532, 1);
    isColored = hsvColors(:, 2) >= 0.05;                                      % grays keep their saturation
    saturation = hsvColors(:, 2) + 0.30 * (2 * saturationOffset - 1);
    hsvColors(isColored, 2) = min(1, max(0.2, saturation(isColored)));
    hsvColors(:, 3) = min(1, max(0.35, hsvColors(:, 3) + 0.25 * (2 * valueOffset - 1)));
    objectColors = hsv2rgb(hsvColors);
end
colors(rows, :) = objectColors;
end

% =====================================================================
function text = localListNumbers(numbers)
% Comma-separated list of up to 20 numbers
text = strjoin(arrayfun(@(x) sprintf('%d', x), numbers(1:min(20, numel(numbers))), 'UniformOutput', false), ', ');
if numel(numbers) > 20; text = [text ', ...']; end
end

% =====================================================================
function text = localEscapeHtml(text)
% The message box shows its text as HTML; annotation names may hold < > &
text = strrep(strrep(strrep(text, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
end
