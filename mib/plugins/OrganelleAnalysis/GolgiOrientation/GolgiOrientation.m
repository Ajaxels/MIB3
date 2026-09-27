classdef GolgiOrientation < handle
% GOLGIORIENTATION - Controller for Golgi orientation analysis plugin.
%
% Calculates relative orientation of Golgi with respect to nucleus or
% cell boundaries from segmented 3-D models.
%
% @code
%   controller = GolgiOrientation(mibModel);
% @endcode
% or, from a MIB ribbon button callback:
% @code
%   obj.mibController.startController('GolgiOrientation');
% @endcode
% or batch mode:
% @code
%   BatchOpt.Mode = {'Complete model'};
%   obj.mibController.startController('GolgiOrientation', [], BatchOpt);
% @endcode
% or return possible batch options:
% @code
%   obj.mibController.startController('GolgiOrientation', [], NaN);
% @endcode
%

% Updates
%

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view / GolgiOrientationGUI
        listener
        % cell array of event listener handles
        BatchOpt
        % structure compatible with batch processing
        % .Mode{1}           - [dropdown]  'Complete model' | 'Cropped cells'
        % .Method{1}         - [dropdown]  orientation method
        % .imagePath         - [editbox]   path to image file
        % .golgiModelPath    - [editbox]   path to Golgi model file
        % .nucleiModelPath   - [editbox]   path to Nuclei model file
        % .celloutlineModelPath - [editbox] path to Cell outlines model file
        % .InputDirectories{1} - [dropdown] currently selected directory
        % .InputDirectories{2} - cell array of all selected directories
        % .OutputFilename    - [editbox]   output file path
        % .FilenameImageExtension{1} - [dropdown] image file extension
        % .FilenameModelExtension{1} - [dropdown] model file extension
        % .MaterialGolgi{1}  - [spinner]   Golgi material index
        % .MaterialNucleus{1} - [spinner]  Nucleus material index
        % .MaterialCell{1}   - [spinner]   Cell material index
        % .ThresholdGolgi{1} - [spinner]   min Golgi object size in px
        % .ThresholdNucleus{1} - [spinner] min Nucleus object size in px
        % .ThresholdCell{1}  - [spinner]   min Cell object size in px
        % .DistanceMaxFromNucleus{1} - [spinner] crop margin in px
        % .showWaitbar       - [checkbox]  show progress bar
    end

    events
        CloseEvent
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
        % ViewListner_Callback2  React to MibModel events.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        function obj = GolgiOrientation(mibModel, varargin)
        % GolgiOrientation  Constructor - initialise controller and (optionally) GUI.
            obj.mibModel = mibModel;

            % default output path from the currently loaded dataset
            id = obj.mibModel.getActiveId();
            defaultPath = fileparts(obj.mibModel.I{id}.image.filename);
            if isempty(defaultPath); defaultPath = pwd; end

            %% BatchOpt defaults
            obj.BatchOpt.Mode = {'Complete model'};
            obj.BatchOpt.Mode{2} = {'Complete model', 'Cropped cells'};
            obj.BatchOpt.Method = {'Relative to nucleus'};
            obj.BatchOpt.Method{2} = {'Relative to nucleus', 'Relative to cell boundary', 'Both'};

            obj.BatchOpt.imagePath = defaultPath;
            obj.BatchOpt.golgiModelPath = defaultPath;
            obj.BatchOpt.nucleiModelPath = defaultPath;
            obj.BatchOpt.celloutlineModelPath = defaultPath;

            obj.BatchOpt.InputDirectories = {'Start by selecting directories'};
            obj.BatchOpt.InputDirectories{2} = {'Start by selecting directories'};
            obj.BatchOpt.OutputFilename = fullfile(defaultPath, 'GolgiOrientation.xls');
            obj.BatchOpt.FilenameImageExtension = {'AM'};
            obj.BatchOpt.FilenameImageExtension{2} = upper(obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'Default', false));
            obj.BatchOpt.FilenameModelExtension = {'MODEL'};
            obj.BatchOpt.FilenameModelExtension{2} = {'MODEL', 'TIF', 'TIFF'};

            obj.BatchOpt.MaterialGolgi{1} = 3;
            obj.BatchOpt.MaterialGolgi{2} = [0, Inf];
            obj.BatchOpt.MaterialGolgi{3} = 'on';
            obj.BatchOpt.MaterialNucleus{1} = 2;
            obj.BatchOpt.MaterialNucleus{2} = [0, Inf];
            obj.BatchOpt.MaterialNucleus{3} = 'on';
            obj.BatchOpt.MaterialCell{1} = 1;
            obj.BatchOpt.MaterialCell{2} = [0, Inf];
            obj.BatchOpt.MaterialCell{3} = 'on';
            obj.BatchOpt.ThresholdGolgi{1} = 0;
            obj.BatchOpt.ThresholdGolgi{2} = [0, Inf];
            obj.BatchOpt.ThresholdGolgi{3} = 'on';
            obj.BatchOpt.ThresholdNucleus{1} = 0;
            obj.BatchOpt.ThresholdNucleus{2} = [0, Inf];
            obj.BatchOpt.ThresholdNucleus{3} = 'on';
            obj.BatchOpt.ThresholdCell{1} = 0;
            obj.BatchOpt.ThresholdCell{2} = [0, Inf];
            obj.BatchOpt.ThresholdCell{3} = 'on';
            obj.BatchOpt.DistanceMaxFromNucleus{1} = 200;
            obj.BatchOpt.DistanceMaxFromNucleus{2} = [1 Inf];
            obj.BatchOpt.DistanceMaxFromNucleus{3} = 'on';
            obj.BatchOpt.showWaitbar = true;

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Plugins';
            obj.BatchOpt.mibBatchActionName  = 'GolgiOrientationAnalysis';

            obj.BatchOpt.mibBatchTooltip.Mode = 'When Complete model, a single model file is expected; for the cropped mode each cell should be cropped out from the dataset';
            obj.BatchOpt.mibBatchTooltip.imagePath = 'Select file containing the image dataset';
            obj.BatchOpt.mibBatchTooltip.golgiModelPath = 'Select model file containing segmented Golgi';
            obj.BatchOpt.mibBatchTooltip.nucleiModelPath = 'Select model file containing segmented Nuclei';
            obj.BatchOpt.mibBatchTooltip.celloutlineModelPath = 'Select model file containing segmented Cell outlines';
            obj.BatchOpt.mibBatchTooltip.InputDirectories = 'List of input directories containing a dataset and a model with segmented Golgi, nucleus and/or cell shape';
            obj.BatchOpt.mibBatchTooltip.OutputFilename = 'Name of output filename with results';
            obj.BatchOpt.mibBatchTooltip.FilenameImageExtension = 'Filename extension of images';
            obj.BatchOpt.mibBatchTooltip.FilenameModelExtension = 'Filename extension of models';
            obj.BatchOpt.mibBatchTooltip.Method = 'Method to calculate orientation of Golgi';
            obj.BatchOpt.mibBatchTooltip.MaterialGolgi = 'Index of material encoding Golgi';
            obj.BatchOpt.mibBatchTooltip.MaterialNucleus = 'Index of material encoding nucleus';
            obj.BatchOpt.mibBatchTooltip.MaterialCell = 'Index of material encoding cell boundary';
            obj.BatchOpt.mibBatchTooltip.ThresholdGolgi = 'Keep Golgi objects that are larger than this value in pixels';
            obj.BatchOpt.mibBatchTooltip.ThresholdNucleus = 'Keep Nuclei objects that are larger than this value in pixels';
            obj.BatchOpt.mibBatchTooltip.ThresholdCell = 'Keep Cell objects that are larger than this value in pixels';
            obj.BatchOpt.mibBatchTooltip.DistanceMaxFromNucleus = 'Max distance for automatic crop when calculating distance map when Relative to nucleus method is used, in pixels';
            obj.BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not progress bar during the plugin work';

            % restore settings from previous session
            if isfield(obj.mibModel.sessionSettings, 'GolgiOrientationAnalysis')
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, obj.mibModel.sessionSettings.GolgiOrientationAnalysis.BatchOpt);
            end

            %% batch / headless mode
            if nargin == 3
                BatchOptIn = varargin{2};
                if isstruct(BatchOptIn) == 0
                    if isnan(BatchOptIn)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 3rd parameter is required!', 'Error');
                    end
                    notify(obj, 'CloseEvent');
                    return;
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
                obj.Calculate();
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'GolgiOrientationGUI');
            % the tab tints, the buttons and the info page (written by addInfo) carry colors
            % of the current theme; set them now and again on a theme switch
            obj.view.gui.ThemeChangedFcn = @(src, evnt) golgiOrientationThemeChanged(obj);
            utils.applyThemeColors(obj.view.gui);
            % the .mlapp paints this grid the pre-R2025a default grey; let it follow the theme
            obj.view.handles.filenameExtensionGridLayout.BackgroundColorMode = 'auto';
            obj.addCallbacks();

            % window icon
            pluginDir = fileparts(mfilename('fullpath'));
            localIcon = fullfile(pluginDir, 'icon_16px.png');
            fallbackIcon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'mib_icon_16px.png');
            if isfile(localIcon)
                obj.view.gui.Icon = localIcon;
            elseif isfile(fallbackIcon)
                obj.view.gui.Icon = fallbackIcon;
            end

            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.golgiModelLabel.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.golgiModelLabel.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.updateWidgets();
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.selectMode();

            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        function addCallbacks(obj)
        % addCallbacks  Wire callbacks that cannot be set inside the .mlapp.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            obj.view.handles.TabGroup.SelectionChangedFcn = @(~,~) obj.updateCalculateButton();
            % All other widget callbacks are set directly in GolgiOrientationGUI.mlapp
            % via app.winController.method() calls.
        end

        function updateCalculateButton(obj)
        % updateCalculateButton  Enable Calculate only when the Settings tab is active.
            isSettings = obj.view.handles.TabGroup.SelectedTab == obj.view.handles.SettingsTab;
            obj.view.handles.Calculate.Enable = matlab.lang.OnOffSwitchState(isSettings);
        end

        function closeWindow(obj)
        % closeWindow  Save session state, destroy GUI, fire CloseEvent.
            obj.mibModel.sessionSettings.GolgiOrientationAnalysis.BatchOpt = obj.BatchOpt;
            if isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        function updateWidgets(obj)
        % updateWidgets  Refresh GUI from BatchOpt (called on dataset change).
            if isfield(obj.BatchOpt, 'id'); obj.BatchOpt.id = obj.mibModel.getActiveId(); end
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
        end

        function updateBatchOptFromGUI(obj, event)
        % updateBatchOptFromGUI  Sync BatchOpt from a widget change event.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
        end

        function returnBatchOpt(obj, BatchOptOut)
        % returnBatchOpt  Fire SyncBatch event with current (or supplied) BatchOpt.
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        function selectMode(obj)
        % selectMode  Switch tab visibility and widget enable states based on Mode.
            obj.BatchOpt.Mode{1} = obj.view.handles.Mode.Value;
            obj.addInfo();
            switch obj.BatchOpt.Mode{1}
                case 'Cropped cells'
                    obj.view.handles.TabGroup.SelectedTab = obj.view.handles.CroppedCellsDirsTab;
                    
                    obj.view.handles.InputDirectories.Enable        = 'on';
                    obj.view.handles.imagePath.Enable               = 'off';
                    obj.view.handles.golgiModelPath.Enable          = 'off';
                    obj.view.handles.nucleiModelPath.Enable         = 'off';
                    obj.view.handles.celloutlineModelPath.Enable    = 'off';

                    obj.view.handles.MaterialGolgi.Enable           = 'on';
                    obj.view.handles.MaterialNucleus.Enable         = 'on';
                    obj.view.handles.MaterialCell.Enable            = 'on';
                    obj.view.handles.ThresholdGolgi.Enable          = 'off';
                    obj.view.handles.ThresholdNucleus.Enable        = 'off';
                    obj.view.handles.ThresholdCell.Enable           = 'off';
                    obj.view.handles.DistanceMaxFromNucleus.Enable  = 'off';
                case 'Complete model'
                    obj.view.handles.TabGroup.SelectedTab = obj.view.handles.CompleteModelFilesTab;
                    
                    obj.view.handles.InputDirectories.Enable        = 'off';
                    obj.view.handles.imagePath.Enable               = 'on';
                    obj.view.handles.golgiModelPath.Enable          = 'on';
                    obj.view.handles.nucleiModelPath.Enable         = 'on';
                    obj.view.handles.celloutlineModelPath.Enable    = 'on';

                    obj.view.handles.MaterialGolgi.Enable           = 'off';
                    obj.view.handles.MaterialNucleus.Enable         = 'off';
                    obj.view.handles.MaterialCell.Enable            = 'off';
                    obj.view.handles.ThresholdGolgi.Enable          = 'on';
                    obj.view.handles.ThresholdNucleus.Enable        = 'on';
                    obj.view.handles.ThresholdCell.Enable           = 'on';
                    obj.view.handles.DistanceMaxFromNucleus.Enable  = 'on';
            end
            obj.updateCalculateButton();
        end

        function addInfo(obj)
        % addInfo  Populate the info HTML panel with mode-specific instructions.
            switch obj.BatchOpt.Mode{1}
                case 'Complete model'
                    infoText = ['<p style="font-family:arial; font-size: 10pt">' ...
                        'Golgi orientation analysis calculates relative orientation of Golgi relative to ' ...
                        'Nucleus or Cell boundaries<br>' ...
                        '<ul style="font-family:arial; font-size: 9pt">' ...
                        '<li>Segment Golgi, Nucleus and/or Cell shape and save them as separate models, ' ...
                        'where indices indicate cell id (for example, in the cell model indices 1001-1007 indicate Paneth cells ' ...
                        'and the corresponding Golgi model has Golgi segmented within the same cells stored as 1001-1007)</li>' ...
                        '<li>Make sure that the voxels are isotropic!</li>' ...
                        '<li>Specify output filename and file formats</li>' ...
                        '<li>Select the image and model files in the Complete model files tab</li>' ...
                        '<li>In the Settings tab select the method and update object size thresholds and distances from nuclei</li>' ...
                        '<li>Hit the Calculate button</li>' ...
                        '</ul>' ...
                        '</p>'];
                case 'Cropped cells'
                    infoText = ['<p style="font-family:arial; font-size: 10pt">' ...
                        'Golgi orientation analysis calculates relative orientation of Golgi relative to ' ...
                        'Nucleus or Cell boundaries<br>' ...
                        '<ul style="font-family:arial; font-size: 9pt">' ...
                        '<li>Segment Golgi, Nucleus and/or Cell shape; 1 segmented cell/per file</li>' ...
                        '<li>Make sure that the voxels are isotropic!</li>' ...
                        '<li>Arrange data into directories containing 1 image and 1 model file</li>' ...
                        '<li>Select directories in the Cropped cells dirs tab</li>' ...
                        '<li>Specify output filename and file formats</li>' ...
                        '<li>In the Settings tab update indices of segmented materials</li>' ...
                        '<li>Hit the Calculate button</li>' ...
                        '</ul>' ...
                        '</p>'];
            end
            hInfo = obj.view.handles.infoHTML;
            hInfo.HTMLSource = [utils.themeHtmlStyle(obj.view.gui, hInfo.Parent.BackgroundColor), infoText];
        end

        function selectOutputFilename(obj, sourceTag)
        % selectOutputFilename  Open file browser to pick output or input paths.
        %
        % Parameters:
        % sourceTag: tag of the button that triggered the call
            switch sourceTag
                case 'selectOutputFilename'
                    Filters = {'*.mat',  'Matlab format (*.mat)'; ...
                               '*.csv',  'Comma-separated value (*.csv)'; ...
                               '*.xls',  'Excel format (*.xls)'};
                    [filename, path, ~] = uiputfile(Filters, 'Select file to save results...', obj.BatchOpt.OutputFilename);
                    if isequal(filename, 0); return; end
                    obj.BatchOpt.OutputFilename = fullfile(path, filename);
                    obj.view.handles.OutputFilename.Value = obj.BatchOpt.OutputFilename;

                case {'selectImagePath', 'selectGolgiModel', 'selectNucleiModel', 'selectCelloutlineModel'}
                    switch sourceTag
                        case 'selectImagePath'
                            fieldName = 'imagePath';
                            dlgTitle  = 'Select file containing image dataset';
                            fnExt     = lower(obj.BatchOpt.FilenameImageExtension{1});
                        case 'selectGolgiModel'
                            fieldName = 'golgiModelPath';
                            dlgTitle  = 'Select model file containing segmented Golgi';
                            fnExt     = lower(obj.BatchOpt.FilenameModelExtension{1});
                        case 'selectNucleiModel'
                            fieldName = 'nucleiModelPath';
                            dlgTitle  = 'Select model file containing segmented Nuclei';
                            fnExt     = lower(obj.BatchOpt.FilenameModelExtension{1});
                        case 'selectCelloutlineModel'
                            fieldName = 'celloutlineModelPath';
                            dlgTitle  = 'Select model file containing segmented Cell outlines';
                            fnExt     = lower(obj.BatchOpt.FilenameModelExtension{1});
                    end
                    Filters = {sprintf('*.%s', fnExt), sprintf('Model file (*.%s)', fnExt); ...
                               '*.*', 'All files (*.*)'};
                    [file, path] = uigetfile(Filters, dlgTitle, obj.BatchOpt.(fieldName));
                    if isequal(file, 0); return; end
                    obj.BatchOpt.(fieldName) = fullfile(path, file);
                    obj.view.handles.(fieldName).Value = obj.BatchOpt.(fieldName);
            end
            drawnow;
            figure(obj.view.gui);
        end

        function selectInputDirectories(obj)
        % selectInputDirectories  Prompt user to pick one or more input directories.
            selpath = uigetfile_n_dir(obj.mibModel.I{obj.mibModel.getActiveId()}.image.filename, 'Select directories');
            if isempty(selpath); return; end
            selpath = selpath';
            selpath(~isfolder(selpath)) = [];
            if isempty(selpath); return; end

            
            % remove 'Start by selecting directories'
            obj.BatchOpt.InputDirectories{2}(ismember(obj.BatchOpt.InputDirectories{2}, 'Start by selecting directories')) = [];

            duplicateIds = ismember(lower(selpath), lower(obj.BatchOpt.InputDirectories{2}));
            selpath(duplicateIds) = [];
            obj.BatchOpt.InputDirectories{2} = [obj.BatchOpt.InputDirectories{2}; selpath];
            obj.BatchOpt.InputDirectories{2} = sort(obj.BatchOpt.InputDirectories{2});
            obj.BatchOpt.InputDirectories{1} = obj.BatchOpt.InputDirectories{2}{1};

            % update GUI
            obj.view.handles.InputDirectories.Items = obj.BatchOpt.InputDirectories{2};
            obj.view.handles.InputDirectories.Value = obj.BatchOpt.InputDirectories{1};

            drawnow;
            figure(obj.view.gui);
        end

        function removeSelectedDirectory(obj, parameter)
        % removeSelectedDirectory  Remove one or all directories from the input list.
        %
        % Parameters:
        % parameter: 'all' (default) or 'selected'
            if nargin < 2; parameter = 'all'; end
            switch parameter
                case 'all'
                    obj.BatchOpt.InputDirectories    = {'Start by selecting directories'};
                    obj.BatchOpt.InputDirectories{2} = {'Start by selecting directories'};
                case 'selected'
                    selectedDir = obj.view.handles.InputDirectories.Value;
                    obj.BatchOpt.InputDirectories{2}(ismember(obj.BatchOpt.InputDirectories{2}, selectedDir)) = [];
                    if numel(obj.BatchOpt.InputDirectories{2}) == 0
                        obj.BatchOpt.InputDirectories    = {'Start by selecting directories'};
                        obj.BatchOpt.InputDirectories{2} = {'Start by selecting directories'};
                    end
            end
            obj.BatchOpt.InputDirectories{1} = obj.BatchOpt.InputDirectories{2}{1};
            obj.view.handles.InputDirectories.Items = obj.BatchOpt.InputDirectories{2};
            obj.view.handles.InputDirectories.Value = obj.BatchOpt.InputDirectories{1};
        end

        function model = loadModel(~, modelFilename)
        % loadModel  Load a model from file; returns a uint8 label array.
        %
        % Parameters:
        % modelFilename: 1-element cell array with full file path
            model = [];
            if nargin < 2; return; end
            modelFilename = modelFilename{1};
            [~, ~, ext] = fileparts(modelFilename);
            switch lower(ext)
                case '.model'
                    res = load(modelFilename, '-mat');
                    model = res.(res.modelVariable);
                case '.tif'
                    meta  = imfinfo(modelFilename);
                    model = zeros([meta(1).Height, meta(1).Width, numel(meta)], 'uint8');
                    for sliceId = 1:numel(meta)
                        model(:, :, sliceId) = imread(modelFilename, 'Index', sliceId);
                    end
            end
        end

        % ------------------------------------------------------------------
        function Calculate(obj)
        % Calculate  Dispatch to the mode-specific calculation method.
            warning('off', 'MATLAB:table:RowsAddedExistingVars');
            switch obj.BatchOpt.Mode{1}
                case 'Complete model'
                    obj.calculateCompleteMode();
                case 'Cropped cells'
                    obj.calculateCroppedMode();
            end
            warning('on', 'MATLAB:table:RowsAddedExistingVars');
        end

        function calculateCompleteMode(obj)
        % calculateCompleteMode  Run Golgi orientation from full-volume model files.

            % distance-map filter options (same for nucleus and cell boundary)
            distFilterOpt.FilterName   = {'DistanceMap'};
            distFilterOpt.DatasetType  = {'3D, Stack'};
            distFilterOpt.Mode3D       = true;
            distFilterOpt.AspectRatio3D = '1 1 1';
            distFilterOpt.SourceLayer  = {'model'};
            distFilterOpt.ColorChannel = {'All'};
            distFilterOpt.Method       = {'euclidean'};

            obj.BatchOpt.showWaitbar = true;
            if obj.BatchOpt.showWaitbar
                progressBar = core.PoolWaitbar(1, 'Loading and detecting Golgi', ...
                    obj.mibModel.mibGUI, 'Golgi Orientation Calculations', true);
                progressBar.updateMaxNumberOfIterations(5);
            end

            % verify image file; ask whether to continue with pixel units
            if exist(obj.BatchOpt.imagePath, 'file') ~= 2
                if obj.BatchOpt.showWaitbar; delete(progressBar); end
                res = utils.dlgs.inputQuestDlg(obj.mibModel.mibGUI, ...
                    sprintf('Image file has not been found!\n\nContinue to use pixels as units, or Cancel?'), ...
                    'Missing image', 'Use pixels as units', 'Cancel', 'Cancel');
                if strcmp(res, 'Cancel'); return; end
                pixSize.x = 1;
                pixSize.y = 1;
                pixSize.z = 1;
                if obj.BatchOpt.showWaitbar
                    progressBar = core.PoolWaitbar(1, 'Loading and detecting Golgi', ...
                        obj.mibModel.mibGUI, 'Golgi Orientation Calculations', true);
                    progressBar.updateMaxNumberOfIterations(5);
                end
            else
                getDataOpt.waitbar    = false;
                getDataOpt.silentMode = true;
                loaderInfo = obj.mibModel.extensionRegistryLoad.resolveLoader(obj.BatchOpt.imagePath, 'Standard', 'Default');
                loader = io.LoaderFactory.create(loaderInfo, getDataOpt);
                [imginfo, ~] = loader.loadMetadata({obj.BatchOpt.imagePath}, getDataOpt);
                pixSize = imginfo{"pixSize"};
            end

            if exist(obj.BatchOpt.golgiModelPath, 'file') ~= 2
                if obj.BatchOpt.showWaitbar; delete(progressBar); end
                utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, ...
                    sprintf('A model file with segmented Golgi is required!\n\nUse\nComplete model files -> Golgi model\nto specify it'), ...
                    'Missing Golgi model');
                return;
            end

            if (strcmp(obj.BatchOpt.Method{1}, 'Relative to nucleus') || strcmp(obj.BatchOpt.Method{1}, 'Both')) && ...
                    exist(obj.BatchOpt.nucleiModelPath, 'file') ~= 2
                if obj.BatchOpt.showWaitbar; delete(progressBar); end
                utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, ...
                    sprintf('A model file with segmented Nuclei is required!\n\nUse\nComplete model files -> Nuclei model\nto specify it'), ...
                    'Missing Nuclei model');
                return;
            end

            if (strcmp(obj.BatchOpt.Method{1}, 'Relative to cell boundary') || strcmp(obj.BatchOpt.Method{1}, 'Both')) && ...
                    exist(obj.BatchOpt.celloutlineModelPath, 'file') ~= 2
                if obj.BatchOpt.showWaitbar; delete(progressBar); end
                utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, ...
                    sprintf('A model file with segmented Cell outlines is required!\n\nUse\nComplete model files -> Cell outlines model\nto specify it'), ...
                    'Missing Cell outlines model');
                return;
            end

            %% detect Golgi
            tic;
            loadedModel = obj.loadModel({obj.BatchOpt.golgiModelPath});
            [height, width, depth] = size(loadedModel);

            CC = bwconncomp(loadedModel, 26);
            if obj.BatchOpt.ThresholdGolgi{1} > 0
                golgiSizeList = cellfun(@(s) numel(s), CC.PixelIdxList);
                removeIds = find(golgiSizeList < obj.BatchOpt.ThresholdGolgi{1});
                CC.PixelIdxList(removeIds) = [];
                CC.NumObjects = numel(CC.PixelIdxList);
            end

            golgiIds = zeros([CC.NumObjects, 1]);
            for golgiId = 1:CC.NumObjects
                golgiIds(golgiId) = double(loadedModel(CC.PixelIdxList{golgiId}(1)));
                [CC.y{golgiId}, CC.x{golgiId}, CC.z{golgiId}] = ind2sub([height, width, depth], CC.PixelIdxList{golgiId});
            end

            if obj.BatchOpt.showWaitbar
                if progressBar.getCancelState(); delete(progressBar); return; end
                progressBar.updateText(sprintf('Sorting Golgi indices\nPlease wait...'));
            end

            [~, indx] = sort(golgiIds);
            golgiCC = CC;
            for golgiId = 1:CC.NumObjects
                golgiCC.PixelIdxList(golgiId) = CC.PixelIdxList(indx(golgiId));
                golgiCC.x(golgiId)  = CC.x(indx(golgiId));
                golgiCC.y(golgiId)  = CC.y(indx(golgiId));
                golgiCC.z(golgiId)  = CC.z(indx(golgiId));
                golgiCC.CellIds(golgiId) = golgiIds(indx(golgiId));
            end
            golgiCC.GolgiIdsAsDetected = indx';

            columnNames = {'Cell Id', 'Golgi stack Id', 'Golgi index', 'Golgi volume, units', 'Golgi volume, px', ...
                'Std relative to Nucleus', 'Std relative to Cell boundary', ...
                'Nucleus volume, units', 'Nucleus volume, px', 'Cell volume, units', 'Cell volume, px'};
            columnTypes = {'double', 'double', 'double', 'double', 'double', ...
                           'double', 'double', ...
                           'double', 'double', 'double', 'double'};
            outTable = table('Size', [numel(golgiIds), numel(columnNames)], ...
                'VariableTypes', columnTypes, 'VariableNames', columnNames);

            %% cell boundary distance maps
            if strcmp(obj.BatchOpt.Method{1}, 'Relative to cell boundary') || strcmp(obj.BatchOpt.Method{1}, 'Both')
                if obj.BatchOpt.showWaitbar
                    if progressBar.getCancelState(); delete(progressBar); return; end
                    progressBar.updateText(sprintf('Loading and detecting cell boundaries\nPlease wait...'));
                    progressBar.increment();
                end

                loadedModel = obj.loadModel({obj.BatchOpt.celloutlineModelPath});
                cellStats   = regionprops(loadedModel, {'Area', 'BoundingBox'});

                if obj.BatchOpt.ThresholdCell{1} > 0
                    area = [cellStats.Area];
                    removeCellBoundaryIds = find(area < obj.BatchOpt.ThresholdCell{1} & area > 0);
                    if ~isempty(removeCellBoundaryIds); [cellStats(removeCellBoundaryIds).Area] = deal(0); end
                end

                area = [cellStats.Area];
                cellboundaryIds = find(~area == 0);
                cellboundaryIds = intersect(golgiCC.CellIds, cellboundaryIds);

                if obj.BatchOpt.showWaitbar
                    if progressBar.getCancelState(); delete(progressBar); return; end
                    progressBar.updateText(sprintf('Processing cell boundaries\nPlease wait...'));
                    progressBar.increaseMaxNumberOfIterations(numel(cellboundaryIds));
                end

                for index = 1:numel(cellboundaryIds)
                    cellId = cellboundaryIds(index);
                    x1 = ceil(cellStats(cellId).BoundingBox(1));
                    y1 = ceil(cellStats(cellId).BoundingBox(2));
                    z1 = ceil(cellStats(cellId).BoundingBox(3));
                    x2 = x1 + cellStats(cellId).BoundingBox(4) - 1;
                    y2 = y1 + cellStats(cellId).BoundingBox(5) - 1;
                    z2 = z1 + cellStats(cellId).BoundingBox(6) - 1;

                    distMapCell = loadedModel(y1:y2, x1:x2, z1:z2);
                    distMapCell = distMapCell & (distMapCell == cellId);
                    distMapCell = uint8(~distMapCell);
                    [distMapCell, ~] = utils.doImageFiltering(distMapCell, distFilterOpt, ...
                        obj.mibModel.preferences.System.cpuParallelLimit);
                    distMapCell = squeeze(distMapCell);

                    [heightDistMap, widthDistMap, depthDistMap] = size(distMapCell);
                    [~, tableIndx] = find(golgiCC.CellIds == cellId);

                    for golgiIndex = 1:numel(tableIndx)
                        tableRowIndex = tableIndx(golgiIndex);
                        golgiId       = tableRowIndex;

                        x = golgiCC.x{golgiId} - x1 + 1;
                        y = golgiCC.y{golgiId} - y1 + 1;
                        z = golgiCC.z{golgiId} - z1 + 1;

                        pixelIdxList_cropped = sub2ind([heightDistMap, widthDistMap, depthDistMap], y, x, z);
                        golgiIntensityVals   = double(distMapCell(pixelIdxList_cropped));

                        outTable.('Cell Id')(tableRowIndex)          = cellId;
                        outTable.('Golgi stack Id')(tableRowIndex)   = golgiCC.GolgiIdsAsDetected(tableRowIndex);
                        outTable.('Golgi index')(tableRowIndex)      = golgiIndex;
                        outTable.('Golgi volume, px')(tableRowIndex) = numel(pixelIdxList_cropped);
                        outTable.('Golgi volume, units')(tableRowIndex) = outTable.('Golgi volume, px')(tableRowIndex) * pixSize.x*pixSize.y*pixSize.z;
                        outTable.('Cell volume, px')(tableRowIndex)  = cellStats(cellId).Area;
                        outTable.('Cell volume, units')(tableRowIndex) = cellStats(cellId).Area * pixSize.x*pixSize.y*pixSize.z;
                        outTable.('Std relative to Cell boundary')(tableRowIndex) = std(golgiIntensityVals);
                    end
                    if obj.BatchOpt.showWaitbar
                        if progressBar.getCancelState(); delete(progressBar); return; end
                        progressBar.increment();
                    end
                end
                clear cellStats;
            end

            %% nucleus distance maps
            if strcmp(obj.BatchOpt.Method{1}, 'Relative to nucleus') || strcmp(obj.BatchOpt.Method{1}, 'Both')
                if obj.BatchOpt.showWaitbar
                    if progressBar.getCancelState(); delete(progressBar); return; end
                    progressBar.updateText(sprintf('Loading and detecting nuclei\nPlease wait...'));
                    progressBar.increment();
                end

                loadedModel  = obj.loadModel({obj.BatchOpt.nucleiModelPath});
                nucleusStats = regionprops(loadedModel, {'Area', 'BoundingBox'});

                if obj.BatchOpt.ThresholdNucleus{1} > 0
                    area = [nucleusStats.Area];
                    removeNucleiIds = find(area < obj.BatchOpt.ThresholdNucleus{1} & area > 0);
                    if ~isempty(removeNucleiIds); [nucleusStats(removeNucleiIds).Area] = deal(0); end
                end

                area       = [nucleusStats.Area];
                nucleusIds = find(~area == 0);
                nucleusIds = intersect(golgiCC.CellIds, nucleusIds);
                modelMarginPx = obj.BatchOpt.DistanceMaxFromNucleus{1};

                if obj.BatchOpt.showWaitbar
                    if progressBar.getCancelState(); delete(progressBar); return; end
                    progressBar.updateText(sprintf('Processing nuclei\nPlease wait...'));
                    progressBar.increaseMaxNumberOfIterations(numel(nucleusIds));
                end

                for index = 1:numel(nucleusIds)
                    cellId   = nucleusIds(index);
                    xMinCrop = ceil(nucleusStats(cellId).BoundingBox(1));
                    yMinCrop = ceil(nucleusStats(cellId).BoundingBox(2));
                    zMinCrop = ceil(nucleusStats(cellId).BoundingBox(3));
                    x1 = max([1,     xMinCrop - modelMarginPx]);
                    y1 = max([1,     yMinCrop - modelMarginPx]);
                    z1 = max([1,     zMinCrop - modelMarginPx]);
                    x2 = min([width, xMinCrop + nucleusStats(cellId).BoundingBox(4) - 1 + modelMarginPx]);
                    y2 = min([height, yMinCrop + nucleusStats(cellId).BoundingBox(5) - 1 + modelMarginPx]);
                    z2 = min([depth, zMinCrop + nucleusStats(cellId).BoundingBox(6) - 1 + modelMarginPx]);

                    distMapCell = loadedModel(y1:y2, x1:x2, z1:z2);
                    distMapCell = distMapCell & (distMapCell == cellId);
                    distMapCell = uint8(distMapCell);
                    [distMapCell, ~] = utils.doImageFiltering(distMapCell, distFilterOpt, ...
                        obj.mibModel.preferences.System.cpuParallelLimit);
                    distMapCell = squeeze(distMapCell);

                    [heightDistMap, widthDistMap, depthDistMap] = size(distMapCell);
                    [~, tableIndx] = find(golgiCC.CellIds == cellId);

                    for golgiIndex = 1:numel(tableIndx)
                        tableRowIndex = tableIndx(golgiIndex);
                        golgiId       = tableRowIndex;

                        x = golgiCC.x{golgiId} - x1 + 1;
                        y = golgiCC.y{golgiId} - y1 + 1;
                        z = golgiCC.z{golgiId} - z1 + 1;

                        if max(x) > widthDistMap || max(y) > heightDistMap || max(z) > depthDistMap || ...
                                min(x) < 1 || min(y) < 1 || min(z) < 1

                            increaseRange = 0;
                            removeIndX2 = find(x > widthDistMap);
                            if ~isempty(removeIndX2); increaseRange = max([increaseRange, max(x(removeIndX2) - widthDistMap)]); end
                            removeIndY2 = find(y > heightDistMap | y < 1);
                            if ~isempty(removeIndY2); increaseRange = max([increaseRange, max(y(removeIndY2) - heightDistMap)]); end
                            removeIndZ2 = find(z > depthDistMap | z < 1);
                            if ~isempty(removeIndZ2); increaseRange = max([increaseRange, max(z(removeIndZ2) - depthDistMap)]); end
                            removeIndX1 = find(x < 1);
                            if ~isempty(removeIndX1); increaseRange = max([increaseRange, max(abs(x(removeIndX1)) + 1)]); end
                            removeIndY1 = find(y < 1);
                            if ~isempty(removeIndY1); increaseRange = max([increaseRange, max(abs(y(removeIndY1)) + 1)]); end
                            removeIndZ1 = find(z < 1);
                            if ~isempty(removeIndZ1); increaseRange = max([increaseRange, max(abs(z(removeIndZ1)) + 1)]); end
                            removeInd = [removeIndX1, removeIndY1, removeIndZ1, removeIndX2, removeIndY2, removeIndZ2];

                            fprintf('CellId: %d, Golgi index: %d  Increase distance from nucleus by ~%d pixels!\n', ...
                                cellId, golgiIndex, increaseRange);
                            x(removeInd) = [];
                            y(removeInd) = [];
                            z(removeInd) = [];
                        end

                        pixelIdxList_cropped = sub2ind([heightDistMap, widthDistMap, depthDistMap], y, x, z);
                        golgiIntensityVals   = double(distMapCell(pixelIdxList_cropped));

                        outTable.('Cell Id')(tableRowIndex)           = cellId;
                        outTable.('Golgi stack Id')(tableRowIndex)    = golgiCC.GolgiIdsAsDetected(tableRowIndex);
                        outTable.('Golgi index')(tableRowIndex)       = golgiIndex;
                        outTable.('Golgi volume, px')(tableRowIndex)  = numel(pixelIdxList_cropped);
                        outTable.('Golgi volume, units')(tableRowIndex) = outTable.('Golgi volume, px')(tableRowIndex) * pixSize.x*pixSize.y*pixSize.z;
                        outTable.('Nucleus volume, px')(tableRowIndex)  = nucleusStats(cellId).Area;
                        outTable.('Nucleus volume, units')(tableRowIndex) = nucleusStats(cellId).Area * pixSize.x*pixSize.y*pixSize.z;
                        outTable.('Std relative to Nucleus')(tableRowIndex) = std(golgiIntensityVals);
                    end
                    if obj.BatchOpt.showWaitbar
                        if progressBar.getCancelState(); delete(progressBar); return; end
                        progressBar.increment();
                    end
                end
            end

            % save results
            if obj.BatchOpt.showWaitbar
                if progressBar.getCancelState(); delete(progressBar); return; end
                progressBar.updateText(sprintf('Saving results\nPlease wait...'));
                progressBar.increment();
            end

            [path, fn, ext] = fileparts(obj.BatchOpt.OutputFilename);
            save(fullfile(path, [fn '.mat']), 'outTable');
            if ismember(ext, {'.csv', '.xls'})
                writetable(outTable, obj.BatchOpt.OutputFilename);
            end

            if obj.BatchOpt.showWaitbar
                maxIter = progressBar.getMaxNumberOfIterations();
                progressBar.setCurrentIteration(maxIter);
                delete(progressBar);
            end
            toc;
        end

        function calculateCroppedMode(obj)
        % calculateCroppedMode  Run Golgi orientation from per-cell cropped directories.
            if obj.BatchOpt.showWaitbar
                progressBar = core.PoolWaitbar(1, 'Starting calculations', obj.view.gui, 'Golgi Orientation Calculations', true);
            end

            warning('off', 'MATLAB:table:RowsAddedExistingVars');

            imageExt = lower(obj.BatchOpt.FilenameImageExtension{1});
            modelExt = lower(obj.BatchOpt.FilenameModelExtension{1});

            getDataOpt.waitbar    = false;
            getDataOpt.silentMode = true;

            distFilterOpt.FilterName   = {'DistanceMap'};
            distFilterOpt.DatasetType  = {'3D, Stack'};
            distFilterOpt.Mode3D       = true;
            distFilterOpt.AspectRatio3D = '1 1 1';
            distFilterOpt.SourceLayer  = {'model'};
            distFilterOpt.ColorChannel = {'All'};
            distFilterOpt.Method       = {'euclidean'};

            outTable = table('Size', [numel(obj.BatchOpt.InputDirectories{2}), 8], ...
                'VariableTypes', {'string', 'string', 'string', 'string', 'double', 'double', 'double', 'double'}, ...
                'VariableNames', {'Directory', 'Directory short', 'Dataset name', 'Model name', ...
                                  'Golgi stack Id', 'Volume, units', 'Std relative to Nucleus', 'Std relative to Cell boundary'});

            tableIndex = 0;
            if obj.BatchOpt.showWaitbar
                if progressBar.getCancelState(); delete(progressBar); return; end
                progressBar.updateMaxNumberOfIterations(numel(obj.BatchOpt.InputDirectories{2}));
            end

            % switch to skip warning message when no cell boundary exists
            skipRelativeToBoundaryWarning = false;

            for inputDirId = 1:numel(obj.BatchOpt.InputDirectories{2})
                selectedDir = obj.BatchOpt.InputDirectories{2}{inputDirId};

                if obj.BatchOpt.showWaitbar
                    if progressBar.getCancelState(); delete(progressBar); return; end
                    [~, currDir] = fileparts(selectedDir);
                    progressBar.updateText(sprintf('Processing "%s"\nPlease wait...', currDir));
                    progressBar.increment();
                end

                % find image and model files in this directory
                imageFiles    = dir(fullfile(selectedDir, ['*.' imageExt]));
                imageFiles2   = arrayfun(@(f) fullfile(selectedDir, f.name), imageFiles, 'UniformOutput', false);
                notDirsIdx    = arrayfun(@(p) ~isfolder(cell2mat(p)), imageFiles2);
                imageFilename = imageFiles2(notDirsIdx)';

                modelFiles    = dir(fullfile(selectedDir, ['*.' modelExt]));
                modelFiles2   = arrayfun(@(f) fullfile(selectedDir, f.name), modelFiles, 'UniformOutput', false);
                notDirsIdx    = arrayfun(@(p) ~isfolder(cell2mat(p)), modelFiles2);
                modelFilename = modelFiles2(notDirsIdx)';

                if numel(imageFilename) ~= 1 || numel(modelFilename) ~= 1
                    utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, ...
                        sprintf('There should be:\n  - a single image file (*.%s)\n  - a single model file (*.%s)\nin each input directory!\n\nThis criteria is not fulfilled in\n%s', ...
                        imageExt, modelExt, selectedDir), 'Wrong files');
                    continue;
                end

                [~, imageStem, imageExt2]  = fileparts(imageFilename{1});
                imageFilenameShort = [imageStem imageExt2];
                [~, modelStem, modelExt2]  = fileparts(modelFilename{1});
                modelFilenameShort = [modelStem modelExt2];

                loaderInfo = obj.mibModel.extensionRegistryLoad.resolveLoader(imageFilename{1}, 'Standard', 'Default');
                loader = io.LoaderFactory.create(loaderInfo, getDataOpt);
                [imginfo, ~] = loader.loadMetadata(imageFilename, getDataOpt);
                pixSize = imginfo{"pixSize"};
                mModel = obj.loadModel(modelFilename);

                % detect Golgi
                golgiModel    = uint8(mModel == obj.BatchOpt.MaterialGolgi{1});
                CC            = bwconncomp(golgiModel, 26);
                noGolgiStacks = CC.NumObjects;
                if noGolgiStacks == 0; continue; end

                % calculate volumes in units
                for golgiId = 1:noGolgiStacks
                    outTable.('Volume, units')(tableIndex + golgiId) = numel(CC.PixelIdxList{golgiId}) * pixSize.x*pixSize.y*pixSize.z;
                end

                % distance map from nucleus
                if strcmp(obj.BatchOpt.Method{1}, 'Relative to nucleus') || strcmp(obj.BatchOpt.Method{1}, 'Both')
                    distMapNucleus = uint8(mModel == obj.BatchOpt.MaterialNucleus{1});
                    [distMapNucleus, ~] = utils.doImageFiltering(distMapNucleus, distFilterOpt, obj.mibModel.preferences.System.cpuParallelLimit);
                    distMapNucleus = squeeze(distMapNucleus);
                    STATS = regionprops(CC, distMapNucleus, 'PixelValues');
                    % convert to double
                    intensityValsVsNucleus = arrayfun(@(x) double(x.PixelValues), STATS, 'UniformOutput', false);
                else
                    intensityValsVsNucleus = repmat({NaN}, [noGolgiStacks, 1]);
                end

                % distance map from cell boundary
                if strcmp(obj.BatchOpt.Method{1}, 'Relative to cell boundary') || strcmp(obj.BatchOpt.Method{1}, 'Both')
                    % check for presence of the cell boundary material
                    if isempty(find(mModel==obj.BatchOpt.MaterialCell{1}, 1, 'first'))
                        % skipping
                        intensityValsVsCell = repmat({NaN}, [noGolgiStacks, 1]);
                        
                        if ~skipRelativeToBoundaryWarning
                            errOpts.MsgBoxOnly = true; 
                            errOpts.Icon = 'puffin_warning';
                            errOpts.headerLines = 1;
                            header = 'No cell boundary found!';
                            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {'Skipping the relative to the cell boundary analysis part!'}, 'Missing cell boundary', errOpts);
                            skipRelativeToBoundaryWarning = true;
                        end

                    else
                        % combine all materials as shape
                        distMapCell = mModel > 0;
                        % invert the model
                        distMapCell = uint8(~distMapCell);
                        [distMapCell, ~] = utils.doImageFiltering(distMapCell, distFilterOpt, obj.mibModel.preferences.System.cpuParallelLimit);
                        distMapCell = squeeze(distMapCell);
                        STATS = regionprops(CC, distMapCell, 'PixelValues');
                        % convert to double
                        intensityValsVsCell = arrayfun(@(x) double(x.PixelValues), STATS, 'UniformOutput', false);
                        noGolgiStacks = numel(intensityValsVsCell);
                    end
                else
                    intensityValsVsCell = repmat({NaN}, [noGolgiStacks, 1]);
                end

                for golgiId = 1:noGolgiStacks
                    outTable.('Directory')(tableIndex + golgiId)        = selectedDir;
                    [~, selectedDirShort] = fileparts(selectedDir);
                    outTable.('Directory short')(tableIndex + golgiId)  = selectedDirShort;
                    outTable.('Dataset name')(tableIndex + golgiId)     = imageFilenameShort;
                    outTable.('Model name')(tableIndex + golgiId)       = modelFilenameShort;
                    outTable.('Golgi stack Id')(tableIndex + golgiId)   = golgiId;
                    outTable.('Std relative to Nucleus')(tableIndex + golgiId)       = std(intensityValsVsNucleus{golgiId}, 'omitnan');
                    outTable.('Std relative to Cell boundary')(tableIndex + golgiId) = std(intensityValsVsCell{golgiId}, 'omitnan');
                end

                clear CC;
                tableIndex = tableIndex + noGolgiStacks;
            end

            % save results
            if obj.BatchOpt.showWaitbar
                if progressBar.getCancelState(); delete(progressBar); return; end
                progressBar.updateText(sprintf('Saving results\nPlease wait...'));
            end

            [path, fn, ext] = fileparts(obj.BatchOpt.OutputFilename);
            save(fullfile(path, [fn '.mat']), 'outTable');
            if ismember(ext, {'.csv', '.xls'})
                writetable(outTable, obj.BatchOpt.OutputFilename);
            end

            if obj.BatchOpt.showWaitbar; delete(progressBar); end

            obj.returnBatchOpt();
            warning('on', 'MATLAB:table:RowsAddedExistingVars');
        end

    end
end

function golgiOrientationThemeChanged(obj)
% GOLGIORIENTATIONTHEMECHANGED - ThemeChangedFcn of the GolgiOrientation window: remap the
% tab tints and standard dialog colors, and rewrite the info page via addInfo, whose colors are
% set for the theme at the time it is written (see utils.themeHtmlStyle).
utils.applyThemeColors(obj.view.gui);
obj.addInfo();
end
