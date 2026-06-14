classdef Alignment < handle
% ALIGNMENT - Controller class for slice-by-slice alignment of 3D image stacks.
%
% Replaces ``mibAlignmentController`` from MIB2. Drives the alignment dialog,
% builds the ``BatchOpt`` parameter set, and dispatches to per-algorithm method
% files (drift correction, single/three-point landmarks, multi-point landmarks,
% feature-based, AMST). The "Two stacks" mode from MIB2 is intentionally not
% ported.
%
% Usage:
%   .. code-block:: matlab
%
%      obj.mibController.startController('controllers.Alignment');
%      controllers.Alignment(mibModel, [], BatchOpt);   % headless batch run
%      controllers.Alignment(mibModel, [], NaN);        % return BatchOpt schema

    properties
        mibModel        % handle to MibModel
        view            % handle to the view (AlignmentGUI .mlapp)
        listener        % cell array of listener handles
        BatchOpt        % structure compatible with batch processing
        automaticOptions % struct with feature-detector / AMST tuning parameters
        shiftsX         % vector of X shifts or affine tform matrix
        shiftsY         % vector of Y shifts or rigid-body matrix
        varname         % workspace variable name for shift export
        files           % files structure from getImageMetadata (HDD mode)
        meta            % meta dictionary from getImageMetadata (HDD mode)
        pathstr         % current dataset path
        pixSize         % pixSize struct from getImageMetadata (HDD mode)
    end

    events
        CloseEvent      % fired when the window closes
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static guarded listener callback.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.ViewListner_Callback2(src, evnt)
            %
            % Routes the model events ``UpdateGuiWidgets`` and ``NewDataset`` to
            % :meth:`updateWidgets`. Deletes stale listeners if the controller or
            % its view has been destroyed.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end

        function idx = findMatchingPairs(X1, X2)
            % FINDMATCHINGPAIRS - Nearest-neighbour matching between two point sets.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      idx = controllers.Alignment.findMatchingPairs(X1, X2)
            %
            % Input Arguments:
            %   - **X1** — ``[N x 2]`` array of (x, y) coordinates.
            %   - **X2** — ``[M x 2]`` array of (x, y) coordinates.
            %
            % Output Arguments:
            %   - **idx** — ``[M x 1]`` vector of indices such that
            %     ``X1(j)`` matches ``X2(idx(j))``; ``NaN`` for unmatched rows.
            distances = zeros(size(X1, 1), size(X2, 1));
            for i = 1:size(X1, 1)
                for j = 1:size(X2, 1)
                    distances(i, j) = sqrt((X1(i,1)-X2(j,1))^2 + (X1(i,2)-X2(j,2))^2);
                end
            end
            N = size(X1, 1);
            matchAtoB = NaN(N, 1);
            for ii = 1:N
                distances(matchAtoB(1:ii-1), :) = Inf;
                [~, matchAtoB(ii)] = min(distances(:, ii));
            end
            matchBtoA = NaN(size(X2, 1), 1);
            matchBtoA(matchAtoB) = 1:N;
            idx = matchBtoA;
        end
    end

    methods
        % --- method in external files signatures ---
        continueBtn_Callback(obj, useBatchMode)
        gui_Callbacks(obj, source, event)
        algorithm_Callback(obj)
        subwindowEdit_Callback(obj, hObject)
        getSearchWindow_Callback(obj)
        loadShiftsCheck_Callback(obj)
        DriftCorrection_Alignment(obj, parameters)
        SingleLandmark_Alignment(obj, parameters)
        ThreeLandmarks_Alignment(obj, parameters)
        LandmarkMultiPoint_Alignment(obj, parameters)
        LandmarkMultiPointColor_Alignment(obj, parameters)
        AutomaticFeatureBased_Alignment(obj, parameters)
        AutomaticFeatureBasedV2_Alignment(obj, parameters)
        AlignMedianSmoothTemplate_Alignment(obj, parameters)
        alignDriftCorrectionHDD_Alignment(obj, parameters)
        AutomaticFeatureBasedHDD_Alignment(obj, parameters)
        AutomaticFeatureBasedHDDV2_Alignment(obj, parameters)
        status = updateAutomaticOptions(obj)
        previewFeaturesBtn_Callback(obj)

        function obj = Alignment(mibModel, varargin)
            % ALIGNMENT - Construct the alignment controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = controllers.Alignment(mibModel)
            %      obj = controllers.Alignment(mibModel, [])
            %      obj = controllers.Alignment(mibModel, [], BatchOptInput)
            %
            % Input Arguments:
            %   - **mibModel** — handle to :class:`models.MibModel`.
            %   - **varargin{1}** *(optional)* — reserved (compat slot).
            %   - **varargin{2}** *(optional)* — ``BatchOpt`` struct for headless run,
            %     or ``NaN`` to request the default ``BatchOpt`` via ``SyncBatch``.

            obj.mibModel = mibModel;
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            % Reject virtual-stacking mode early
            if any(dataset.datasetType(1) == ['V' 'B'])
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), ...
                    'Alignment is not available in virtual or BigData mode', {''}, ...
                    {'Switch to memory-resident mode and try again.'}, ...
                    'Not implemented', dlgOpt);
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            getDataOpt.blockModeSwitch = 0;
            [height, width, ~, colors] = dataset.getDatasetDimensions('image', 3, getDataOpt);

            % Restore or initialise feature-detector tuning options
            if isfield(obj.mibModel.sessionSettings, 'automaticAlignmentOptions') ...
                    && ~isempty(obj.mibModel.sessionSettings.automaticAlignmentOptions)
                obj.automaticOptions = obj.mibModel.sessionSettings.automaticAlignmentOptions;
            else
                obj.automaticOptions = obj.defaultAutomaticOptions(width);
            end

            % ---- BatchOpt defaults (no TwoStacks / SecondDataset fields) ----
            BatchOpt.Algorithm    = {'Drift correction'};
            BatchOpt.Algorithm{2} = {'Drift correction', 'Template matching', ...
                'Automatic feature-based', 'Automatic feature-based v2', ...
                'Single landmark point', 'Three landmark points', ...
                'Landmarks, multi points', 'Color channels, multi points', ...
                'AMST: median-smoothed template'};

            BatchOpt.CorrelateWith    = {'Previous slice'};
            BatchOpt.CorrelateWith{2} = {'Previous slice', 'First slice', 'Relative to'};
            BatchOpt.CorrelateStep    = {1, [1 Inf], true};

            BatchOpt.ColorChannel    = {'ColCh 1'};
            BatchOpt.ColorChannel{2} = arrayfun(@(x) sprintf('ColCh %d', x), ...
                1:numel(colors), 'UniformOutput', false);
            BatchOpt.IntensityGradient = false;

            BatchOpt.TransformationType    = {'non reflective similarity'};
            BatchOpt.TransformationType{2} = {'translate', 'rigid', 'non reflective similarity', 'similarity', 'affine', 'projective'};
            BatchOpt.TransformationMode    = {'extended'};
            BatchOpt.TransformationMode{2} = {'extended', 'cropped'};
            BatchOpt.TransformationDegree    = {'2 (min: 6 pnt)'};
            BatchOpt.TransformationDegree{2} = {'2 (min: 6 pnt)', '3 (min: 10 pnt)', '4 (min: 15 pnt)'};

            BatchOpt.FeatureDetectorType    = {'Blobs: Speeded-Up Robust Features (SURF) algorithm'};
            BatchOpt.FeatureDetectorType{2} = { ...
                'Blobs: Speeded-Up Robust Features (SURF) algorithm', ...
                'Blobs: Detect scale invariant feature transform (SIFT)', ...
                'Regions: Maximally Stable Extremal Regions (MSER) algorithm', ...
                'Corners: Harris-Stephens algorithm', ...
                'Corners: Binary Robust Invariant Scalable Keypoints (BRISK)', ...
                'Corners: Features from Accelerated Segment Test (FAST)', ...
                'Corners: Minimum Eigenvalue algorithm', ...
                'Oriented FAST and rotated BRIEF (ORB)'};
            BatchOpt.MedianSize          = {15, [1 Inf], true};
            BatchOpt.UseParallelComputing = false;

            BatchOpt.BackgroundColor    = {'White'};
            BatchOpt.BackgroundColor{2} = {'White', 'Black', 'Mean', 'Custom'};
            BatchOpt.CustomColorValue   = {dataset.image.maxInt, [0 dataset.image.maxInt], true};

            BatchOpt.Subarea    = {'Full image'};
            BatchOpt.Subarea{2} = {'Full image', 'Manually specified', 'Selection', 'Mask'};
            BatchOpt.minX = {floor(width/2)-floor(width/4), [1 Inf], true};
            BatchOpt.maxX = {floor(width/2)+floor(width/4), [1 Inf], true};
            BatchOpt.minY = {floor(height/2)-floor(height/4), [1 Inf], true};
            BatchOpt.maxY = {floor(height/2)+floor(height/4), [1 Inf], true};

            BatchOpt.SubtractRunningAverage             = false;
            BatchOpt.SubtractRunningAverageStep         = {25, [0 Inf], true};
            BatchOpt.SubtractRunningAverageExcludePeaks = {10, [0 Inf], true};
            BatchOpt.SubtractRunningAverageFixStretch          = true;
            BatchOpt.SubtractRunningAverageFixShear            = true;
            BatchOpt.SubtractRunningAverageExcludeStretchPeaks = {0, [0 Inf], true};
            BatchOpt.SubtractRunningAverageExcludeShearPeaks   = {0, [0 Inf], true};

            BatchOpt.SaveShiftsToFile = false;
            BatchOpt.showWaitbar      = true;

            % HDD-mode parameters
            BatchOpt.HDD_Mode               = false;
            BatchOpt.HDD_InputDir           = obj.mibModel.currentDirectory;
            BatchOpt.HDD_OutputSubfolderName = 'MIB_Align';
            BatchOpt.HDD_InputFilenameExtension    = {'TIF'};
            allowedExt = upper(obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'Default', false));
            BatchOpt.HDD_InputFilenameExtension{2} = allowedExt;
            BatchOpt.HDD_BioformatsReader  = false;
            BatchOpt.HDD_BioformatsIndex   = {1, [1 Inf], true};
            BatchOpt.HDD_OutputFileExtension    = {'TIF'};
            BatchOpt.HDD_OutputFileExtension{2} = {'AM', 'JPG', 'MRC', 'NRRD', 'PNG', 'TIF'};

            % Batch metadata
            BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
            BatchOpt.mibBatchActionName  = 'Alignment / Drift correction...';
            BatchOpt.mibBatchTooltip = obj.defaultTooltips();

            obj.BatchOpt = BatchOpt;

            % ---- Batch-mode dispatch ----
            if nargin == 3
                BatchOptInput = varargin{2};
                if ~isstruct(BatchOptInput)
                    if isnan(BatchOptInput)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                            'A structure as the 3rd parameter is required!', 'BatchOpt Error');
                    end
                    return;
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);
                obj.continueBtn_Callback(true);
                return;
            end

            % ---- GUI mode ----
            obj.varname = 'I';
            obj.view = core.ChildView(obj, 'views.AlignmentGUI');
            obj.addCallbacks();

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.existingDimText.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.existingDimText.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            obj.updateWidgets();
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));

            obj.view.gui.Visible = 'on';
        end

        function closeWindow(obj)
            % CLOSEWINDOW - Close the dialog and detach listeners.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.closeWindow()
            obj.mibModel.sessionSettings.automaticAlignmentOptions = obj.automaticOptions;
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end

            notify(obj, 'CloseEvent');
        end

        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Forward ``BatchOpt`` to ``mibBatchController`` via ``SyncBatch``.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.returnBatchOpt()
            %      obj.returnBatchOpt(BatchOptOut)
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        function updateBatchOptFromGUI(obj, hObject)
            % UPDATEBATCHOPTFROMGUI - Sync ``obj.BatchOpt`` from a single widget.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateBatchOptFromGUI(hObject)
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
        end

        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh dialog widgets from the current dataset.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets()
            id = obj.mibModel.getActiveId();
            
            if obj.mibModel.I{id}.image.time > 1
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_error';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), ...
                    'Alignment does not support 5D datasets', {''}, ...
                    {'Use a 4D (YXZC) dataset and try again.'}, 'Error', dlgOpt);
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            getDataOpt.blockModeSwitch = 0;
            [height, width, depth, colors] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, getDataOpt);
            fn = obj.mibModel.I{id}.image.filename;
            [obj.pathstr, name, ext] = fileparts(fn);

            obj.shiftsX = [];
            obj.shiftsY = [];
            obj.meta    = dictionary;
            obj.files   = struct();
            obj.pixSize = struct();

            h = obj.view.handles;
            h.existingFnText1.Text    = obj.pathstr;
            h.existingFnText1.Tooltip = fn;
            h.existingFnText2.Text    = [name ext];
            h.existingFnText2.Tooltip = fn;
            h.existingDimText.Text = sprintf('%d x %d x %d', width, height, depth);
            h.existingPixText2.Text = sprintf('Pixel size, %s:', obj.mibModel.I{id}.image.pixSize.units);
            h.existingPixText.Text = sprintf('%f x %f x %f', ...
                obj.mibModel.I{id}.image.pixSize.x, ...
                obj.mibModel.I{id}.image.pixSize.y, ...
                obj.mibModel.I{id}.image.pixSize.z);

            h.saveShiftsXYpath.Value = fullfile(obj.pathstr, [name '_align.coefXY']);
            h.loadShiftsXYpath.Value = fullfile(obj.pathstr, [name '_align.coefXY']);
            
            % Refresh dynamic dropdowns / spinner ranges
            obj.BatchOpt.ColorChannel{2} = arrayfun(@(x) sprintf('ColCh %d', x), 1:numel(colors), 'UniformOutput', false);
            selColCh = max([1 obj.mibModel.I{id}.selectedColorChannel]);
            if selColCh > numel(obj.BatchOpt.ColorChannel{2}); selColCh = 1; end
            obj.BatchOpt.ColorChannel{1} = obj.BatchOpt.ColorChannel{2}{selColCh};

            obj.BatchOpt.minX = {floor(width/2)-floor(width/4),  [1 width],  true};
            obj.BatchOpt.maxX = {floor(width/2)+floor(width/4),  [1 width],  true};
            obj.BatchOpt.minY = {floor(height/2)-floor(height/4),[1 height], true};
            obj.BatchOpt.maxY = {floor(height/2)+floor(height/4),[1 height], true};

            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
        end

        function addCallbacks(obj)
            % ADDCALLBACKS - Wire every widget to the central :meth:`gui_Callbacks` dispatcher.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addCallbacks()
            %
            % Sets ``CloseRequestFcn`` on the figure first; assigns a single
            % anonymous-handle callback to every widget Tag listed in the view
            % contract. Widgets that the user's ``.mlapp`` does not yet expose
            % are silently skipped.

            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            h  = obj.view.handles;
            cb = @(src,evt) obj.gui_Callbacks(src, evt);

            buttonTags = {'continueBtn','closeBtn','helpBtn', ...
                          'getSearchWindow','previewFeaturesBtn','HDD_SelectDirBtn'};
            for k = 1:numel(buttonTags)
                if isfield(h, buttonTags{k})
                    h.(buttonTags{k}).ButtonPushedFcn = cb;
                end
            end

            valueTags = {'Algorithm','CorrelateWith','CorrelateStep', ...
                'ColorChannel','IntensityGradient', ...
                'TransformationType','TransformationMode','TransformationDegree', ...
                'FeatureDetectorType','MedianSize','UseParallelComputing', ...
                'Subarea','minX','minY','maxX','maxY', ...
                'BackgroundColor','BackgroundColorCustom','CustomColorValue', ...
                'SubtractRunningAverage','SubtractRunningAverageStep', ...
                'SubtractRunningAverageExcludePeaks', ...
                'SubtractRunningAverageFixStretch','SubtractRunningAverageFixShear', ...
                'SubtractRunningAverageExcludeStretchPeaks', ...
                'SubtractRunningAverageExcludeShearPeaks', ...
                'SaveShiftsToFile','saveShiftsXYpath', ...
                'loadShiftsCheck','loadShiftsXYpath', ...
                'HDD_Mode','HDD_InputDir','HDD_InputFilenameExtension', ...
                'HDD_BioformatsReader','HDD_BioformatsIndex', ...
                'HDD_OutputSubfolderName','HDD_OutputFileExtension', ...
                'showWaitbar'};
            for k = 1:numel(valueTags)
                if isfield(h, valueTags{k})
                    h.(valueTags{k}).ValueChangedFcn = cb;
                end
            end
        end
    end

    methods (Access = private)
        function options = defaultAutomaticOptions(~, width)
            % DEFAULTAUTOMATICOPTIONS - Build the default feature-detector / AMST tuning struct.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      options = obj.defaultAutomaticOptions(width)
            options.imgWidthForAnalysis = round(width/4);
            options.imgDownsamplingFactorForAnalysis = 4;
            options.rotationInvariance = true;
            options.detectSURFFeatures = struct( ...
                'MetricThreshold', 1000, 'NumOctaves', 3, 'NumScaleLevels', 4);
            options.detectSIFTFeatures = struct( ...
                'ContrastThreshold', 0.0133, 'EdgeThreshold', 10, ...
                'NumLayersInOctave', 3, 'Sigma', 1.6);
            options.detectMSERFeatures = struct( ...
                'ThresholdDelta', 2, 'RegionAreaRange', [30 14000], 'MaxAreaVariation', 0.25);
            options.detectHarrisFeatures = struct('MinQuality', 0.01, 'FilterSize', 5);
            options.detectBRISKFeatures  = struct('MinContrast', 0.2, 'MinQuality', 0.1, 'NumOctaves', 4);
            options.detectFASTFeatures   = struct('MinQuality', 0.1, 'MinContrast', 0.2);
            options.detectMinEigenFeatures = struct('MinQuality', 0.01, 'FilterSize', 5);
            options.detectORBFeatures    = struct('ScaleFactor', 1.2, 'NumLevels', 8);
            options.amst = struct( ...
                'PyramidLevels', 1, 'MaximumIterations', 100, ...
                'GradientMagnitudeTolerance', 0.0001, 'MinimumStepLength', 0.0001, ...
                'MaximumStepLength', 0.0625, 'RelaxationFactor', 0.5);
            options.estGeomTransform = struct( ...
                'MaxNumTrials', 1000, 'Confidence', 99, 'MaxDistance', 1.5);
        end

        function tooltips = defaultTooltips(~)
            % DEFAULTTOOLTIPS - Build the ``mibBatchTooltip`` struct.
            tooltips.Algorithm           = 'Algorithm used for the alignment';
            tooltips.CorrelateWith       = 'Slice used as the correlation reference';
            tooltips.CorrelateStep       = '[CorrelateWith->Relative to]: correlate with slice N positions away';
            tooltips.ColorChannel        = 'Colour channel used for the alignment';
            tooltips.IntensityGradient   = 'Use intensity gradients instead of pixel intensities (helps for gradient-rich data)';
            tooltips.TransformationType  = '[Feature/Landmarks]: image transform model';
            tooltips.TransformationMode  = '[Feature/Landmarks]: "extended" keeps every pixel; "cropped" crops to the first slice';
            tooltips.TransformationDegree = '[Feature/Landmarks/Polynomial]: polynomial transform degree';
            tooltips.FeatureDetectorType = '[Automatic feature based]: feature detector';
            tooltips.MedianSize          = '[AMST only]: Z size of the median filter';
            tooltips.UseParallelComputing = '[AMST only]: enable parallel computing';
            tooltips.BackgroundColor     = 'Padding colour for the aligned canvas';
            tooltips.BackgroundColorCustom = '[BackgroundColor->Custom]: custom colour as RGB triplet or grayscale value';
            tooltips.CustomColorValue    = '[BackgroundColor->Custom]: custom colour intensity for the background';
            tooltips.Subarea             = 'Calculate shifts from the whole image, a manual subset, the selection, or the mask';
            tooltips.minX                = '[Subarea->Manually specified]: min X point';
            tooltips.maxX                = '[Subarea->Manually specified]: max X point';
            tooltips.minY                = '[Subarea->Manually specified]: min Y point';
            tooltips.maxY                = '[Subarea->Manually specified]: max Y point';
            tooltips.SubtractRunningAverage = '[Drift correction]: subtract the running average from the shifts';
            tooltips.SubtractRunningAverageStep = '[Drift correction]: half-width of the running-average window';
            tooltips.SubtractRunningAverageExcludePeaks = 'Exclude peaks higher than this value from the running average';
            tooltips.SubtractRunningAverageFixStretch  = '[Automatic]: fix stretch using the running average';
            tooltips.SubtractRunningAverageFixShear    = '[Automatic]: fix shear using the running average';
            tooltips.SubtractRunningAverageExcludeStretchPeaks = 'Exclude stretch peaks higher than this value';
            tooltips.SubtractRunningAverageExcludeShearPeaks   = 'Exclude shear peaks higher than this value';
            tooltips.SaveShiftsToFile    = 'Automatically save detected shifts to a file alongside the dataset';
            tooltips.HDD_Mode            = '[Drift correction only] Use HDD processing mode (files not loaded into memory)';
            tooltips.HDD_InputDir        = 'Input directory with image files to be aligned';
            tooltips.HDD_OutputSubfolderName = 'Name of the output subfolder';
            tooltips.HDD_InputFilenameExtension = 'Extension of input image files';
            tooltips.HDD_BioformatsReader = 'Use the Bio-Formats reader';
            tooltips.HDD_BioformatsIndex  = 'Index of the series for the Bio-Formats reader';
            tooltips.HDD_OutputFileExtension = 'Extension for output files';
            tooltips.showWaitbar         = 'Show the progress bar during execution';
        end
    end
end
