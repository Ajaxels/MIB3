classdef Stitching < handle
% STITCHING - Controller for the Image Stitching tool.
%
% Assembles a mosaic from overlapping 2D/3D tile images using:
%   (a) grid dialog, (b) position file, or (c) MIB2 filename pattern.
% Registration is performed by pairwise phase correlation + global weighted
% least-squares optimisation (MIST/BigStitcher approach).  Fusion supports
% in-memory (Standard dataset) and streaming OME-Zarr3 (BigData) outputs.
%
% Available from Ribbon -> Dataset -> Stitching.

    % Updates
    %

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (StitchingGUI), empty in batch mode
        listener
        % cell array of listener handles
        BatchOpt
        % structure compatible with batch processing
        layout
        % struct array — tile layout (nomOrigin, tileSize, etc.)
        edges
        % struct array — measured pairwise edges (i, j, direction, measured, quality, valid)
        positions
        % N-by-3 double — solved tile origins [y x z]
        tforms
        % N-by-1 cell of 3x3 doubles — solved per-tile affine transforms
        % (tile-local xy -> global xy) when TransformType is not Translation;
        % {} for the translation solve
        solverInfo
        % struct from the last global solve (rmseTotal, nPruned,
        % disconnectedTiles). Kept on the controller — not just inside
        % optimizePositions_Callback — so the alignment-quality chip can be
        % re-rendered whenever the edges change (e.g. the inspector excluding a
        % seam) without re-solving; [] until the first solve
        layoutFromProject
        % logical — true while obj.layout comes from a loaded project sidecar
        % rather than from BatchOpt. The widgets may then describe a completely
        % different job (a project carries no layout source/grid before schema
        % v3), so anything that would silently re-derive the layout from
        % BatchOpt must stand down. Cleared by buildLayoutFromBatchOpt, i.e. by
        % every deliberate rebuild
        canvas
        % struct — output canvas plan (size, tilePlacement, etc.)
        zSliceFixes
        % K-by-3 double — per-slice mosaic corrections [z dy dx] from the
        % inspector's Fix Z: every output slice >= z shifts in-plane by
        % [dy dx] (cumulative over rows). Applied by planCanvas/fusers,
        % persisted in the project sidecar; [] = none
        automaticOptions
        % struct — feature-detector tuning (per-detector params, RANSAC,
        % rotation invariance, downsampling) for the Feature-based method;
        % same shape as controllers.Alignment.defaultAutomaticOptions
        tileROIs
        % array of images.roi.Rectangle — draggable tile handles in edit mode
        roiListeners
        % cell array of ROIMoved listener handles for tileROIs
        inspector
        % handle to the seam-inspector child controller (controllers.StitchingInspector),
        % [] when not open
        inspectorListeners
        % cell array of listeners on the inspector (SeamsUpdated / CloseEvent)
        zarrExportOptions
        % struct of OME-Zarr3 pyramid/chunk/compression settings collected once
        % (io.savers.Zarr3Saver.optionsDialog) for the current output path and
        % reused by later re-fuses to the same path; [] until the dialog runs,
        % reset when the output path or mode changes
    end

    events
        CloseEvent
        % fired when the window is closed
    end

    methods (Static)
        function fieldNames = projectSettingFields()
            % PROJECTSETTINGFIELDS - BatchOpt fields persisted in the project sidecar.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       fieldNames = controllers.Stitching.projectSettingFields()
            %
            % The single list shared by
            % :meth:`controllers.Stitching.collectProjectSettings` (save) and
            % :meth:`controllers.Stitching.applyProjectSettings` (load), so the
            % two can never drift apart. Excludes ``showWaitbar`` / ``mibBatch*``
            % / ``id`` — batch plumbing rather than user settings.
            %
            % Output Arguments:
            %   - **fieldNames** — [cell] BatchOpt field names, in dialog order
            %
            fieldNames = { ...
                'LayoutSource', 'InputPath', 'SubfolderMode', 'AtlasImport', ...
                'GridRows', 'GridCols', 'TileOrder', 'OverlapX', 'OverlapY', 'EstimateOverlap', ...
                'TransformType', 'AllowRotation', 'RegistrationMethod', 'FeatureDetectorType', ...
                'QualityThreshold', 'NominalPositionWeight', 'SubpixelPlacement', ...
                'OutputMode', 'OutputPath', 'BlendMode', 'SaveProject'};
        end

        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static model-event listener guard.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       controllers.Stitching.ViewListner_Callback2(obj, src, evnt)
            %
            % Input Arguments:
            %   - **obj** — handle to the Stitching controller
            %   - **evnt** — event data from the model
            %
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for listenerIdx = 1:numel(obj.listener)
                    delete(obj.listener{listenerIdx});
                end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods

        % ---------------------------------------------------------------
        function obj = Stitching(mibModel, varargin)
            % STITCHING - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = controllers.Stitching(mibModel)
            %      obj = controllers.Stitching(mibModel, BatchOpt)
            %      obj = controllers.Stitching(mibModel, NaN)
            %
            % Input Arguments:
            %   - **mibModel** — handle to MibModel
            %   - **varargin{1}** *(optional)* — BatchOpt struct (batch run), or NaN
            %     (return BatchOpt to mibBatchController)
            %

            obj.mibModel = mibModel;
            obj.layout   = struct('index', {}, 'filename', {}, 'sliceFiles', {}, ...
                'zLayer', {}, 'gridRC', {}, 'nomOrigin', {}, 'tileSize', {}, 'dataClass', {});
            obj.edges     = struct('i', {}, 'j', {}, 'direction', {}, 'nominal', {});
            obj.positions = [];
            obj.tforms    = {};
            obj.canvas    = [];
            obj.zSliceFixes = [];
            obj.solverInfo  = struct();
            obj.layoutFromProject = false;
            obj.tileROIs     = images.roi.Rectangle.empty;
            obj.roiListeners = {};
            obj.inspector    = [];
            obj.inspectorListeners = {};
            obj.zarrExportOptions  = [];
            obj.automaticOptions = obj.defaultFeatureOptions();

            % ---- BatchOpt defaults
            obj.BatchOpt.LayoutSource    = {'Grid'};
            obj.BatchOpt.LayoutSource{2} = {'Bio-Formats metadata', 'Filename pattern', ...
                'Grid', 'Position file'};

            obj.BatchOpt.InputPath       = '';
            obj.BatchOpt.SubfolderMode   = false;

            % How much of an Atlas mosaic's own stitch to take. Consulted only
            % when the Position file source is pointed at a Fibics Atlas
            % ``.ve-mif`` rather than a position text file. The GUI asks when a
            % .ve-tie / .ve-updates is found next to the picked .ve-mif and
            % records the answer here, so a batch protocol or a reloaded project
            % repeats the same import silently.
            obj.BatchOpt.AtlasImport     = {'Atlas seams + solved positions'};
            obj.BatchOpt.AtlasImport{2}  = {'Nominal grid only', ...
                'Atlas seam measurements', 'Atlas seams + solved positions'};

            obj.BatchOpt.GridRows        = {0, [0 10000], 'on'};
            obj.BatchOpt.GridCols        = {0, [0 10000], 'on'};

            obj.BatchOpt.TileOrder       = {'Horizontal'};
            obj.BatchOpt.TileOrder{2}    = {'Horizontal', 'Horizontal snake', 'Vertical', 'Vertical snake'};

            obj.BatchOpt.OverlapX        = {10, [0 90], 'off'};
            obj.BatchOpt.OverlapY        = {10, [0 90], 'off'};
            obj.BatchOpt.EstimateOverlap = true;

            obj.BatchOpt.TransformType   = {'Translation'};
            obj.BatchOpt.TransformType{2} = {'Translation', 'Rigid', 'Similarity', 'Affine'};
            obj.BatchOpt.AllowRotation   = false;

            obj.BatchOpt.RegistrationMethod    = {'Phase correlation'};
            obj.BatchOpt.RegistrationMethod{2} = {'Phase correlation', 'Feature-based'};

            obj.BatchOpt.FeatureDetectorType    = {'Blobs: Speeded-Up Robust Features (SURF) algorithm'};
            obj.BatchOpt.FeatureDetectorType{2} = { ...
                'Blobs: Speeded-Up Robust Features (SURF) algorithm', ...
                'Blobs: Detect scale invariant feature transform (SIFT)', ...
                'Regions: Maximally Stable Extremal Regions (MSER) algorithm', ...
                'Corners: Harris-Stephens algorithm', ...
                'Corners: Binary Robust Invariant Scalable Keypoints (BRISK)', ...
                'Corners: Features from Accelerated Segment Test (FAST)', ...
                'Corners: Minimum Eigenvalue algorithm', ...
                'Oriented FAST and rotated BRIEF (ORB)'};

            obj.BatchOpt.QualityThreshold = {0.30, [0 1], 'off'};
            obj.BatchOpt.NominalPositionWeight = {0.10, [0 1], 'off'};
            obj.BatchOpt.SubpixelPlacement = false;

            obj.BatchOpt.OutputMode      = {'In memory'};
            obj.BatchOpt.OutputMode{2}   = {'In memory', 'OME-Zarr3 (BigData)'};
            obj.BatchOpt.OutputPath      = '';

            obj.BatchOpt.BlendMode       = {'Feather'};
            obj.BatchOpt.BlendMode{2}    = {'Feather', 'Average', 'Max', 'Min', 'Overwrite'};

            obj.BatchOpt.SaveProject     = true;
            obj.BatchOpt.showWaitbar     = true;

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
            obj.BatchOpt.mibBatchActionName  = 'Stitch...';

            obj.BatchOpt.mibBatchTooltip.LayoutSource    = 'How tiles are arranged: Grid, Position file (a text file or a Fibics Atlas .ve-mif mosaic), MIB2 filename pattern, or embedded Bio-Formats stage coordinates';
            obj.BatchOpt.mibBatchTooltip.InputPath       = 'Path to the tile folder, position file, Atlas .ve-mif mosaic file, or folder of tile files';
            obj.BatchOpt.mibBatchTooltip.SubfolderMode   = 'Each tile is a folder of slice images (a Z-stack) instead of a single image file — works with any layout source';
            obj.BatchOpt.mibBatchTooltip.AtlasImport     = sprintf([ ...
                '[Position file pointed at a Fibics Atlas .ve-mif]: how much of the mosaic''s own stitch to reuse.\n' ...
                'Nominal grid only — ignore the .ve-tie/.ve-updates files and register from scratch;\n' ...
                'Atlas seam measurements — take the .ve-tie shifts, let MIB run the global solve;\n' ...
                'Atlas seams + solved positions — also take the .ve-updates placement, so Stitch fuses with nothing recomputed.\n' ...
                'Ignored for a plain position text file.']);
            obj.BatchOpt.mibBatchTooltip.GridRows        = 'Number of grid rows (0 = auto from tile count)';
            obj.BatchOpt.mibBatchTooltip.GridCols        = 'Number of grid columns (0 = auto from tile count)';
            obj.BatchOpt.mibBatchTooltip.TileOrder       = 'Order tiles were acquired: Horizontal, Horizontal snake, Vertical, or Vertical snake';
            obj.BatchOpt.mibBatchTooltip.OverlapX        = 'Horizontal overlap between adjacent tiles in percent (0–90)';
            obj.BatchOpt.mibBatchTooltip.OverlapY        = 'Vertical overlap between adjacent tiles in percent (0–90)';
            obj.BatchOpt.mibBatchTooltip.EstimateOverlap = 'Estimate the actual overlap from the images before measuring (grid layout); OverlapX/Y are then only a rough starting guess';
            obj.BatchOpt.mibBatchTooltip.TransformType   = 'Registration transform: Translation (grid stages), Rigid (+rotation), Similarity (+uniform scale) or Affine (+scale/shear); non-translation transforms act in-plane per slice (z stays translational) and use feature-based measurement';
            obj.BatchOpt.mibBatchTooltip.AllowRotation   = 'Tiles are rotated against each other: permits per-tile rotation in Rigid/Similarity/Affine solves AND switches feature matching to rotation-invariant descriptors. Keep off for stage-tiled data (stages translate but do not rotate) — matching is then faster and noisy overlaps cannot inject spurious rotations';
            obj.BatchOpt.mibBatchTooltip.RegistrationMethod = 'How pairwise overlaps are measured: Phase correlation (best for small overlaps with modest jitter) or Feature-based (best for large/unknown offsets, matches SURF features over the full tiles)';
            obj.BatchOpt.mibBatchTooltip.FeatureDetectorType = '[Feature-based]: keypoint detector used to match tiles; configure its parameters + downsampling with the Settings button';
            obj.BatchOpt.mibBatchTooltip.QualityThreshold = 'Minimum normalized peak height to accept a pairwise shift measurement (0–1)';
            obj.BatchOpt.mibBatchTooltip.NominalPositionWeight = 'How strongly tiles with weak or failed registration are pulled back toward their nominal grid positions (0–1)';
            obj.BatchOpt.mibBatchTooltip.SubpixelPlacement = 'Sub-pixel refinement of the pairwise-shift measurements; tiles are still placed on whole pixels';
            obj.BatchOpt.mibBatchTooltip.OutputMode      = 'Output as a Standard in-memory dataset or a streamed OME-Zarr3 BigData file (pyramid settings are asked when stitching)';
            obj.BatchOpt.mibBatchTooltip.OutputPath      = 'Output path for the OME-Zarr3 BigData file (OutputMode = OME-Zarr3)';
            obj.BatchOpt.mibBatchTooltip.BlendMode       = 'Blending strategy at tile seams: Feather, Average, Max (brightest tile wins), Min (darkest tile wins), or Overwrite';
            obj.BatchOpt.mibBatchTooltip.SaveProject     = 'Save project sidecar JSON after stitching';
            obj.BatchOpt.mibBatchTooltip.showWaitbar     = 'Show progress bar during stitching (batch-only option, not shown in the GUI)';

            % ---- Batch-mode path (nargin == 3 means controller called with BatchOpt/NaN)
            if nargin == 3
                BatchOptInput = varargin{2};
                if isstruct(BatchOptInput)
                    obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);
                    obj.BatchOpt.id = obj.mibModel.getActiveId();
                    obj.stitchBtn_Callback(true);
                    notify(obj, 'CloseEvent');
                elseif isnan(BatchOptInput)
                    obj.returnBatchOpt();
                else
                    utils.dlgs.showErrorDialog([], ...
                        'A BatchOpt struct is required as the 3rd parameter.', ...
                        'Stitching: init error');
                    notify(obj.mibModel, 'StopProtocol');
                end
                return;
            end

            % ---- GUI path
            obj.view = core.ChildView(obj, 'views.StitchingGUI');
            
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.closeButton.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.closeButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            obj.addCallbacks();
            obj.updateWidgets();

            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % ---------------------------------------------------------------
        function options = defaultFeatureOptions(~)
            % DEFAULTFEATUREOPTIONS - Default feature-detector tuning for the
            % Feature-based registration method. Same shape as
            % controllers.Alignment.defaultAutomaticOptions, tuned for stitching:
            % full-resolution detection (factor 1) and a lower SURF threshold
            % (more blobs in thin overlaps).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      options = obj.defaultFeatureOptions()
            %
            options.imgDownsamplingFactorForAnalysis = 1;   % full resolution for stitch precision
            % Placeholder only — buildFeatureOptions DERIVES this from
            % BatchOpt.AllowRotation on every use, so the stored value is never
            % read by the registration path. Kept in the struct so the shape
            % still matches controllers.Alignment.defaultAutomaticOptions.
            options.rotationInvariance = true;
            options.featureMinInliers  = 8;
            options.detectSURFFeatures = struct('MetricThreshold', 500, 'NumOctaves', 3, 'NumScaleLevels', 4);
            options.detectSIFTFeatures = struct('ContrastThreshold', 0.0133, 'EdgeThreshold', 10, ...
                'NumLayersInOctave', 3, 'Sigma', 1.6);
            options.detectMSERFeatures = struct('ThresholdDelta', 2, 'RegionAreaRange', [30 14000], 'MaxAreaVariation', 0.25);
            options.detectHarrisFeatures   = struct('MinQuality', 0.01, 'FilterSize', 5);
            options.detectBRISKFeatures    = struct('MinContrast', 0.2, 'MinQuality', 0.1, 'NumOctaves', 4);
            options.detectFASTFeatures     = struct('MinQuality', 0.1, 'MinContrast', 0.1);
            options.detectMinEigenFeatures = struct('MinQuality', 0.01, 'FilterSize', 5);
            options.detectORBFeatures      = struct('ScaleFactor', 1.2, 'NumLevels', 8);
            options.estGeomTransform = struct('MaxNumTrials', 1000, 'Confidence', 99, 'MaxDistance', 1.5);
        end

        % ---------------------------------------------------------------
        function featureOptions = buildFeatureOptions(obj)
            % BUILDFEATUREOPTIONS - Assemble the options struct for
            % utils.stitch.featureShift from the current detector selection and
            % automaticOptions (used when RegistrationMethod = Feature-based).
            %
            % ``rotationInvariance`` is DERIVED from ``BatchOpt.AllowRotation``
            % rather than stored: it is MATLAB's ``extractFeatures`` ``Upright``
            % flag, so upright descriptors (``true``) cannot match rotated
            % content at all and would silently veto a rotating solve. The two
            % are therefore one user decision — "are the tiles rotated?" — and
            % the single *Allow rotation* checkbox owns it. Deriving it here,
            % the one place every consumer (measure, stitch,
            % :func:`previewFeatureMatch`) goes through, means the two cannot
            % drift and no stale value can survive a project load.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      featureOptions = obj.buildFeatureOptions()
            %
            featureOptions = obj.automaticOptions;
            featureOptions.featureDetector = obj.BatchOpt.FeatureDetectorType{1};
            featureOptions.downsampleFactor = obj.automaticOptions.imgDownsamplingFactorForAnalysis;
            featureOptions.rotationInvariance = ~obj.BatchOpt.AllowRotation;
        end

        % ---------------------------------------------------------------
        function figureHandle = guiFigure(obj)
            % GUIFIGURE - Handle of the tool window, or ``[]`` without a view.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      figureHandle = obj.guiFigure()
            %
            % Every dialog parent and progress-bar anchor goes through this so
            % the workflow methods run unchanged whether the tool has a window
            % (GUI), was launched from a batch protocol, or is driven headlessly
            % by the test suite. ``utils.dlgs.*`` and the ``utils.stitch``
            % progress helpers all accept ``[]`` as "no parent".
            %
            % Output Arguments:
            %   - **figureHandle** — [handle] the ``StitchingGUI`` figure, or
            %     ``[]`` when the controller has no (valid) view
            %
            figureHandle = [];
            if ~isempty(obj.view) && ~isempty(obj.view.gui) && isvalid(obj.view.gui)
                figureHandle = obj.view.gui;
            end
        end

        % ---------------------------------------------------------------
        function warnUser(obj, message, dlgTitle)
            % WARNUSER - Report an unmet precondition ("measure first", "no
            % tiles selected", …).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.warnUser(message, dlgTitle)
            %
            % With a window: a message box, and the caller returns leaving the
            % state untouched. Without one (batch protocol, headless run) there
            % is nobody to read a message box, so the same condition is raised
            % as an error — the caller's ``return`` would otherwise report
            % success for work that never happened.
            %
            % Input Arguments:
            %   - **message** — [char] what is missing, in user language
            %   - **dlgTitle** — [char] dialog title
            %
            if isempty(obj.view)
                error('Stitching:precondition', '%s', message);
            end
            warnOptions.MsgBoxOnly  = true;
            warnOptions.Icon        = 'puffin_warning';
            warnOptions.HeaderLines = 1;
            utils.dlgs.inputUniversalDlg(obj.guiFigure(), message, {}, {}, dlgTitle, warnOptions);
        end

        % ---------------------------------------------------------------
        function reportError(obj, errorInfo, dlgTitle)
            % REPORTERROR - Surface a caught error from a workflow step.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.reportError(errorInfo, dlgTitle)
            %
            % With a window: an error dialog, and the caller returns. Without
            % one the error is rethrown, so a batch protocol or a test sees the
            % failure instead of a silently skipped step.
            %
            % Input Arguments:
            %   - **errorInfo** — [MException] the caught error
            %   - **dlgTitle** — [char] dialog title
            %
            if isempty(obj.view); rethrow(errorInfo); end
            utils.dlgs.showErrorDialog(obj.guiFigure(), errorInfo.message, dlgTitle);
        end

        % ---------------------------------------------------------------
        function refreshInputPathWidget(obj)
            % REFRESHINPUTPATHWIDGET - Show BatchOpt.InputPath in the InputPath
            % widget, handling either a uieditfield (single newline-joined string)
            % or a uilistbox (one item per path — better for multi-folder input).
            % BatchOpt.InputPath stays the newline-joined string in both cases, so
            % batch mode is unaffected.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.refreshInputPathWidget()
            %
            widget = obj.view.handles.InputPath;
            if isprop(widget, 'Items')      % uilistbox: one path per row
                entries = strtrim(strsplit(obj.BatchOpt.InputPath, newline));
                entries = entries(~cellfun(@isempty, entries));
                widget.Items = entries;
            else                            % uieditfield: single string
                widget.Value = obj.BatchOpt.InputPath;
            end
        end

        % ---------------------------------------------------------------
        function updateInfoLabel(obj)
            % UPDATEINFOLABEL - Set the info label to a short description of what
            % the current ``LayoutSource`` does, so the user knows what input to
            % provide. Guarded by ``isfield`` — no-op until the ``infoLabel``
            % widget exists in the mlapp.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateInfoLabel()
            %
            if ~isfield(obj.view.handles, 'infoLabel'); return; end
            % One short (2-line) description per layout source.
            switch obj.BatchOpt.LayoutSource{1}
                case 'Grid'
                    description = sprintf(['Tiles on a regular grid. Pick the tile files, set Rows/Cols and ' ...
                        'overlap (or tick Estimate overlap); Tile order sets the scan pattern.']);
                case 'Position file'
                    description = sprintf(['A file stating where each tile goes — either a text file\n' ...
                        '("tiles/tile_01.tif 0 0 0" per line), or a Fibics Atlas mosaic\n' ...
                        '("MosaicInfo_*.ve-mif"), whose own stitch can be imported with it.']);
                case 'Filename pattern'
                    description = sprintf(['Grid indices are read as pattern:\n   "_Z##-X##-Y##"\nfrom file or ' ...
                        'folder names. The order of letters is not important but it should contain 2 digits.']);
                case 'Bio-Formats metadata'
                    description = sprintf('Tile positions are based on embedded microscope stage coordinates.');
                otherwise
                    description = '';
            end
            obj.view.handles.infoLabel.Text = description;
        end

    end % methods
end % classdef
