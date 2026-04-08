classdef Annotations < handle
    % @type Annotations class is responsible for the List of Annotations dialog
    % available from MIB -> Ribbon -> Models -> Annotations -> List of annotations
    %
    % @code
    % obj.startController('controllers.Annotations'); // as GUI tool
    % @endcode

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
            % Guard: if the view was closed before listener cleanup, clean up and return.
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

        function purgeControllers(obj, src, evnt)
            % function purgeControllers(obj, src, evnt)
            % Find and delete a child controller that fired its CloseEvent.
            id = obj.findChildId(class(src));
            delete(obj.childControllers{id});
            obj.childControllers(id) = [];
            obj.childControllersIds(id) = [];
        end
    end

    methods
        function obj = Annotations(mibModel, varargin)
            % function obj = Annotations(mibModel, varargin)
            % Constructor for the Annotations controller.
            %
            % Parameters:
            % mibModel: handle to MibModel
            % varargin{1}: controller handle (unused, for startController compatibility)
            % varargin{2}: [@em optional] BatchOpt structure; when NaN returns defaults via SyncBatch

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
            % function closeWindow(obj)
            % Close the Annotations window and clean up listeners.

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
            % function addCallbacks(obj)
            % Wire all widget callbacks. Called once from the constructor.

            % Window X-button triggers proper cleanup
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            h = obj.view.handles;

            % Table
            h.annotationTable.SelectionChangedFcn = ...
                @(~, evt) obj.annotationTable_CellSelectionCallback(evt.Selection);
            h.annotationTable.CellEditCallback = ...
                @(~, evt) obj.annotationTable_CellEditCallback(evt.Indices);
            h.annotationTable.KeyPressFcn = ...
                @(~, evt) obj.annotationTable_KeyPressFcn(evt);
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
            % function updateWidgets(obj)
            % Refresh the annotation table from the current dataset.

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
            % function loadBtn_Callback(obj)
            % Import annotations from a file or from the MATLAB workspace.

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
                    [filename, path, indx] = utils.dlgs.mibUiGetFile( ...
                        {'*.ann;',  'Matlab format (*.ann)'; ...
                         '*.csv;',  'CSV format (*.csv)'; ...
                         '*.landmarkAscii;', 'landmarkAscii Amira format (*.landmarkAscii)'; ...
                         '*.landmarkBin;',   'landmarkBin Amira format (*.landmarkBin)'; ...
                         '*.*',     'All Files (*.*)'}, ...
                        'Load annotations...', obj.mibModel.currentDirectory);
                    if isequal(filename, 0); return; end
                    fullFilename = fullfile(path, filename{1});

                    obj.mibModel.backup('annotations', 0);
                    switch indx
                        case 1  % .ann (MATLAB)
                            res = load(fullFilename, '-mat');
                            % compatibility with old variable names
                            if isfield(res, 'labelsList')
                                res.labelText = res.labelsList;
                                res = rmfield(res, 'labelsList');
                            end
                            if isfield(res, 'labelValues')
                                res.labelValue = res.labelValues;
                                res = rmfield(res, 'labelValues');
                            end
                            if isfield(res, 'labelPositions')
                                res.labelPosition = res.labelPositions;
                                res = rmfield(res, 'labelPositions');
                            end
                            if ~isfield(res, 'labelValue')
                                res.labelValue = ones(numel(res.labelText), 1);
                            end
                            if size(res.labelPosition, 2) == 3
                                res.labelPosition(:,4) = obj.mibModel.I{id}.slices{5}(1);
                            end

                        case 2  % CSV
                            opts = detectImportOptions(fullFilename);
                            T    = readtable(fullFilename, opts);
                            varNames  = T.Properties.VariableNames;
                            varNames2 = ['do not import', sort(varNames)];

                            prompts = {'Annotation name'; 'Annotation value'; ...
                                'Z coordinate (pixels)'; 'X coordinate (pixels)'; ...
                                'Y coordinate (pixels)'; 'T coordinate (pixels)'};
                            defAns = {[varNames2, {1}], [varNames2, {1}], [varNames2, {1}], ...
                                      [varNames2, {1}], [varNames2, {1}], [varNames2, {1}]};
                            csvOpt.WindowHeight = 320;
                            csvOpt.Columns     = 1;
                            answer = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                                'Select column names in CSV file that map to these fields', prompts, defAns, 'Import from CSV', csvOpt);
                            if isempty(answer); return; end

                            N = height(T);
                            res.labelText     = repmat({'Label'}, [N, 1]);
                            res.labelValue    = zeros([N, 1]);
                            res.labelPosition = ones([N, 4]);

                            if ~strcmp(answer{1}, 'do not import')
                                if isnumeric(T.(answer{1})(1))
                                    res.labelText = cellstr(string(T.(answer{1})));
                                else
                                    res.labelText = T.(answer{1});
                                end
                            end
                            if ~strcmp(answer{2}, 'do not import')
                                if isnumeric(T.(answer{2})(1))
                                    res.labelValue = T.(answer{2});
                                else
                                    res.labelValue = str2double(T.(answer{2}));
                                end
                            end
                            for fieldId = 3:6
                                if ~strcmp(answer{fieldId}, 'do not import')
                                    if isnumeric(T.(answer{fieldId})(1))
                                        res.labelPosition(:, fieldId-2) = T.(answer{fieldId});
                                    else
                                        res.labelPosition(:, fieldId-2) = str2double(T.(answer{fieldId}));
                                    end
                                end
                            end

                        case {3, 4}  % Amira landmark files
                            amiraLandmarks = io.AmiraMesh.amiraLandmarks2points(fullFilename);
                            res.labelText     = repmat({'AmiraLandmark'}, [size(amiraLandmarks,1), 1]);
                            res.labelValue    = ones([size(amiraLandmarks,1), 1]);
                            res.labelPosition = ones([size(amiraLandmarks,1), 4]);
                            bb      = obj.mibModel.I{id}.image.boundingBox;
                            pixSize = obj.mibModel.I{id}.image.pixSize;
                            res.labelPosition(:,1) = round((amiraLandmarks(:,3) - bb(5) + pixSize.z) / pixSize.z);
                            res.labelPosition(:,2) = (amiraLandmarks(:,1) - bb(1) + pixSize.x/2) / pixSize.x;
                            res.labelPosition(:,3) = (amiraLandmarks(:,2) - bb(3) + pixSize.y/2) / pixSize.y;
                        otherwise
                            return
                    end
                    obj.mibModel.I{id}.annotations.replaceLabels( ...
                        res.labelText, res.labelPosition, res.labelValue);
            end
            obj.updateWidgets();
            notify(obj.mibModel, 'ShowImage');
            fprintf('Import annotations: done!\n');
        end

        % -----------------------------------------------------------------
        function saveBtn_Callback(obj)
            % function saveBtn_Callback(obj)
            % Export annotations to a file or to the MATLAB workspace.

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
            % function saveAnnotationsToFile(obj, labelText, labelPosition, labelValue)
            % Save annotations to a file chosen by the user.
            %
            % Parameters:
            % labelText: cell array of annotation labels
            % labelPosition: Nx4 matrix [z x y t] in pixels
            % labelValue: Nx1 numeric array of annotation values

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
            % function deleteBtn_Callback(obj)
            % Delete all annotations from the current dataset.

            id = obj.BatchOpt.id;
            obj.mibModel.backup('annotations', 0);
            obj.mibModel.I{id}.annotations.removeLabels();
            notify(obj.mibModel, 'ShowImage');
            obj.updateWidgets();
        end

        % -----------------------------------------------------------------
        function annotationTable_CellSelectionCallback(obj, Selection)
            % function annotationTable_CellSelectionCallback(obj, Selection)
            % Callback for cell selection change in annotationTable.
            %
            % Parameters:
            % Selection: Nx2 array of [row col] pairs (from SelectionChangedFcn event.Selection)

            obj.indices = Selection;
            if obj.view.handles.jumpCheck.Value
                obj.tableContextMenu_cb('Jump');
            end
        end

        % -----------------------------------------------------------------
        function annotationTable_CellEditCallback(obj, Indices)
            % function annotationTable_CellEditCallback(obj, Indices)
            % Callback for cell edit in annotationTable.
            %
            % Parameters:
            % Indices: [row col] of the edited cell (from CellEditCallback event.Indices)

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
            % function precisionEdit_Callback(obj)
            % Callback for the precision spinner; refresh table with new decimal places.

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
            % function tableContextMenu_cb(obj, parameter)
            % Callbacks for the annotation table context menu.
            %
            % Parameters:
            % parameter: string selecting the action
            % @li 'Add'         - add a new annotation
            % @li 'Modify'      - batch-modify values/coords of selected annotations
            % @li 'Rename'      - rename selected annotations
            % @li 'Jump'        - move view to selected annotation
            % @li 'Count'       - count and sum selected annotations
            % @li 'Clipboard'   - copy selected rows to clipboard
            % @li 'ClipboardPaste' - paste clipboard into selected column
            % @li 'CropPatches' - crop image patches around selected annotations
            % @li 'Mask'        - rasterise selected annotations into the mask layer
            % @li 'Interpolate' - interpolate positions between selected annotations
            % @li 'Export'      - export selected annotations to file
            % @li 'Imaris'      - export selected annotations to Imaris
            % @li 'OrderTop' / 'OrderUp' / 'OrderDown' / 'OrderBottom' - reorder
            % @li 'Delete'      - delete selected annotations

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
                    elseif orientation == 1  % ZX
                        z = str2double(data{rowId, 5});
                        x = str2double(data{rowId, 3});
                        y = str2double(data{rowId, 4});
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

                    wb = uiprogressdlg(obj.view.gui, 'Title', 'Annotations to Mask', ...
                        'Message', 'Preparing...', 'Value', 0);

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

                    for pntId = 1:nPts
                        wb.Value   = (pntId - 1) / nPts;
                        wb.Message = sprintf('Placing spot %d / %d...', pntId, nPts);

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
                    end

                    wb.Value = 1;
                    delete(wb);
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
                    if isempty(obj.indices) || size(obj.indices,1) == 1; return; end
                    [labelNames, labelValues, labelPosition, labelIndices] = ...
                        obj.mibModel.I{id}.annotations.getLabelsById(obj.indices(:,1));

                    if numel(unique(labelPosition(:,1))) ~= size(obj.indices,1)
                        dlgOpt.MsgBoxOnly  = true;
                        dlgOpt.HeaderLines = 1;
                        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                            'Error', {''}, {'Please select annotations with exactly 1 per slice!'}, ...
                            'Error', dlgOpt);
                        return;
                    end

                    nPts = size(obj.indices, 1);
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
                    obj.startController('controllers.CropObjects', obj, false, annotationLabels);

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
        function gui_KeyPressFcn(obj, eventdata)
            % function gui_KeyPressFcn(obj, eventdata)
            % Key-press callback for the main figure window.

            if ismember('control', eventdata.Modifier)
                switch lower(eventdata.Key)
                    % Ctrl+Z undo — currently not implemented for annotations
                end
            end
        end

        % -----------------------------------------------------------------
        function annotationTable_KeyPressFcn(obj, eventdata)
            % function annotationTable_KeyPressFcn(obj, eventdata)
            % Key-press callback for the annotation table; handles reorder shortcuts.

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
            % function resortTablePopup_Callback(obj)
            % Resort the annotation list by the chosen column.

            obj.mibModel.backup('annotations', 1);
            sortBy = lower(obj.view.handles.resortTablePopup.Value);
            obj.mibModel.I{obj.BatchOpt.id}.annotations.sortLabels(sortBy);
            obj.updateWidgets();
        end

        % -----------------------------------------------------------------
        function settingsBtn_Callback(obj)
            % function settingsBtn_Callback(obj)
            % Open the annotation display settings dialog.

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
            [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                prompts, defAns, 'Annotation settings', sOpt);
            if isempty(answer); return; end

            value = str2double(answer{1});
            if isnan(value)
                dlgOpt.MsgBoxOnly  = true;
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                    'Wrong value', {''}, {sprintf('Invalid value "%s" — enter a non-negative integer.', answer{1})}, ...
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
            % function helpBtn_Callback(obj)
            % Open the Annotations help page in the browser.

            web(fullfile(fileparts(obj.mibModel.mibPath), ...
                'docs/html/user-interface/menu/models/annotations.html'), '-browser');
        end

        % -----------------------------------------------------------------
        function startController(obj, controllerName, varargin)
            % function startController(obj, controllerName, varargin)
            % Start a child controller by name (e.g., 'controllers.CropObjects').
            %
            % Parameters:
            % controllerName: char — fully-qualified controller class name
            % varargin: additional arguments forwarded to the child constructor

            id = obj.findChildId(controllerName);
            if ~isempty(id); return; end  % already open

            id = numel(obj.childControllersIds) + 1;
            obj.childControllersIds{id} = controllerName;
            fh = str2func(controllerName);
            if nargin > 2
                obj.childControllers{id} = fh(obj.mibModel, varargin{:});
            else
                obj.childControllers{id} = fh(obj.mibModel);
            end
            addlistener(obj.childControllers{id}, 'CloseEvent', ...
                @(src,evnt) controllers.Annotations.purgeControllers(obj, src, evnt));
        end

        % -----------------------------------------------------------------
        function id = findChildId(obj, childName)
            % function id = findChildId(obj, childName)
            % Return index of named child controller, or [] if not open.

            if ~ismember(childName, obj.childControllersIds)
                id = [];
            else
                id = find(ismember(obj.childControllersIds, childName), 1);
            end
        end

    end
end
