classdef Stitching < handle
% STITCHING - Controller for the Image Stitching tool.
%
% Assembles a mosaic from overlapping 2D/3D tile images using:
%   (a) grid dialog, (b) position file, or (c) MIB2 filename pattern.
% Registration is performed by pairwise phase correlation + global weighted
% least-squares optimisation (MIST/BigStitcher approach).  Fusion supports
% in-memory (Standard dataset) and streaming OME-Zarr (BigData) outputs.
%
% Available from Ribbon -> Dataset -> Stitch.

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
        canvas
        % struct — output canvas plan (size, tilePlacement, etc.)
    end

    events
        CloseEvent
        % fired when the window is closed
    end

    methods (Static)
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
            obj.canvas    = [];

            % ---- BatchOpt defaults
            obj.BatchOpt.LayoutSource    = {'Grid'};
            obj.BatchOpt.LayoutSource{2} = {'Grid', 'Position file', 'Filename pattern'};

            obj.BatchOpt.InputPath       = '';
            obj.BatchOpt.SubfolderMode   = false;

            obj.BatchOpt.GridRows        = {0, [0 10000], 'on'};
            obj.BatchOpt.GridCols        = {0, [0 10000], 'on'};

            obj.BatchOpt.TileOrder       = {'Horizontal'};
            obj.BatchOpt.TileOrder{2}    = {'Horizontal', 'Horizontal snake', 'Vertical', 'Vertical snake'};

            obj.BatchOpt.OverlapX        = {10, [0 90], 'off'};
            obj.BatchOpt.OverlapY        = {10, [0 90], 'off'};
            obj.BatchOpt.EstimateOverlap = true;

            obj.BatchOpt.TransformType   = {'Translation'};
            obj.BatchOpt.TransformType{2} = {'Translation'};

            obj.BatchOpt.QualityThreshold = {0.30, [0 1], 'off'};
            obj.BatchOpt.NominalPositionWeight = {0.10, [0 1], 'off'};
            obj.BatchOpt.SubpixelPlacement = false;

            obj.BatchOpt.OutputMode      = {'In memory'};
            obj.BatchOpt.OutputMode{2}   = {'In memory', 'OME-Zarr (BigData)'};
            obj.BatchOpt.OutputPath      = '';

            obj.BatchOpt.BlendMode       = {'Feather'};
            obj.BatchOpt.BlendMode{2}    = {'Feather', 'Average', 'Max', 'Overwrite'};

            obj.BatchOpt.SaveProject     = true;
            obj.BatchOpt.showWaitbar     = true;

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
            obj.BatchOpt.mibBatchActionName  = 'Stitch...';

            obj.BatchOpt.mibBatchTooltip.LayoutSource    = 'Source of tile layout: Grid, Position file, or MIB2 filename pattern';
            obj.BatchOpt.mibBatchTooltip.InputPath       = 'Path to the tile folder, position file, or folder of tile files';
            obj.BatchOpt.mibBatchTooltip.SubfolderMode   = 'Treat each subfolder as a separate Z-stack tile (position-file mode)';
            obj.BatchOpt.mibBatchTooltip.GridRows        = 'Number of grid rows (0 = auto from tile count)';
            obj.BatchOpt.mibBatchTooltip.GridCols        = 'Number of grid columns (0 = auto from tile count)';
            obj.BatchOpt.mibBatchTooltip.TileOrder       = 'Order tiles were acquired: Horizontal, Horizontal snake, Vertical, or Vertical snake';
            obj.BatchOpt.mibBatchTooltip.OverlapX        = 'Horizontal overlap between adjacent tiles in percent (0–90)';
            obj.BatchOpt.mibBatchTooltip.OverlapY        = 'Vertical overlap between adjacent tiles in percent (0–90)';
            obj.BatchOpt.mibBatchTooltip.EstimateOverlap = 'Estimate the actual overlap from the images before measuring (grid layout); OverlapX/Y are then only a rough starting guess';
            obj.BatchOpt.mibBatchTooltip.TransformType   = 'Registration transform type (Translation only in Phase 1)';
            obj.BatchOpt.mibBatchTooltip.QualityThreshold = 'Minimum normalized peak height to accept a pairwise shift measurement (0–1)';
            obj.BatchOpt.mibBatchTooltip.NominalPositionWeight = 'How strongly tiles with weak or failed registration are pulled back toward their nominal grid positions (0–1)';
            obj.BatchOpt.mibBatchTooltip.SubpixelPlacement = 'Use sub-pixel precision for tile placement (Phase 1: rounds to integer)';
            obj.BatchOpt.mibBatchTooltip.OutputMode      = 'Output as Standard in-memory dataset or OME-Zarr BigData file';
            obj.BatchOpt.mibBatchTooltip.OutputPath      = 'Output path for OME-Zarr BigData file (OutputMode = OME-Zarr)';
            obj.BatchOpt.mibBatchTooltip.BlendMode       = 'Blending strategy at tile seams: Feather, Average, Max, or Overwrite';
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

    end % methods
end % classdef
