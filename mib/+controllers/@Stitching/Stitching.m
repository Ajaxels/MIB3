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
        % struct array - tile layout (nomOrigin, tileSize, etc.)
        edges
        % struct array - measured pairwise edges (i, j, direction, measured, quality, valid)
        positions
        % N-by-3 double - solved tile origins [y x z]
        tforms
        % N-by-1 cell of 3x3 doubles - solved per-tile affine transforms
        % (tile-local xy -> global xy) when TransformType is not Translation;
        % {} for the translation solve
        solverInfo
        % struct from the last global solve (rmseTotal, nPruned,
        % disconnectedTiles). Kept on the controller - not just inside
        % optimizePositions_Callback - so the alignment-quality chip can be
        % re-rendered whenever the edges change (e.g. the inspector excluding a
        % seam) without re-solving; [] until the first solve
        layoutFromProject
        % logical - true while obj.layout comes from a loaded project sidecar
        % rather than from BatchOpt. The widgets may then describe a completely
        % different job (a project carries no layout source/grid before schema
        % v3), so anything that would silently re-derive the layout from
        % BatchOpt must stand down. Cleared by buildLayoutFromBatchOpt, i.e. by
        % every deliberate rebuild
        canvas
        % struct - output canvas plan (size, tilePlacement, etc.)
        zSliceFixes
        % K-by-3 double - per-slice mosaic corrections [z dy dx] from the
        % inspector's Fix Z: every output slice >= z shifts in-plane by
        % [dy dx] (cumulative over rows). Applied by planCanvas/fusers,
        % persisted in the project sidecar; [] = none
        automaticOptions
        % struct - feature-detector tuning (per-detector params, RANSAC,
        % rotation invariance, downsampling) for the Feature-based method;
        % same shape as controllers.Alignment.defaultAutomaticOptions
        tileROIs
        % array of images.roi.Rectangle - draggable tile handles in edit mode
        roiListeners
        % cell array of ROIMoved listener handles for tileROIs
        inspector
        % handle to the seam-inspector child controller (controllers.StitchingInspector),
        % [] when not open
        inspectorListeners
        % cell array of listeners on the inspector (SeamsUpdated / CloseEvent)
        intensityCorrection
        % struct from utils.stitch.estimateIntensityCorrection - the intensity
        % correction every tile read is made with. Estimating it costs one pass
        % over the tiles, so it is computed LAZILY by ensureIntensityCorrection and
        % kept here; [] means "not estimated yet", which is not the same as
        % BatchOpt.IntensityCorrection = 'None' (that estimates to a neutral struct).
        % Dropped whenever the layout is rebuilt or the method changes
        resolvePending
        % logical - an inspector edit (manual fix, exclude, undo) has changed the
        % edge set while Auto re-solve was off, so obj.positions no longer follow
        % from obj.edges. Lives HERE rather than on the inspector because the
        % debt outlives the window: closing the inspector used to drop the flag
        % with it, after which the chip stopped warning and Stitch fused the
        % stale placement. Cleared by any solve (optimizePositions_Callback);
        % stitchBtn_Callback settles it before fusing
        seamScoresStamp
        % struct - what obj.edges' seamScores were computed for (.positions,
        % .numEdges, .correctionMethod), so the same overlaps are not re-read by
        % the next consumer that wants them. Set by
        % controllers.Stitching.ensureSeamScores and by a project load whose
        % sidecar already carried a complete score set; [] = not scored (yet).
        % Compared against live state rather than explicitly invalidated, so
        % nothing can forget to clear it
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
        function settings = renameLegacyFields(settings)
            % RENAMELEGACYFIELDS - Map retired BatchOpt field names onto current ones.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       settings = controllers.Stitching.renameLegacyFields(settings)
            %
            % Applied to anything arriving from OUTSIDE this class - a batch
            % protocol or a project sidecar - before it is merged into
            % ``BatchOpt``, so both entry points age the same way.
            %
            % ``AtlasImport`` became ``LayoutImport`` when SerialEM montages
            % joined Fibics Atlas in offering their own stitch for import: the
            % three modes were never Atlas-specific, and the old name made a
            % SerialEM protocol read as an Atlas one. The values were renamed with
            % it (``'Atlas seams…'`` → ``'Vendor seams…'``).
            %
            % A file carrying BOTH names keeps the current one - an old key
            % alongside a new one means the writer knew about the new name.
            %
            % Input Arguments:
            %   - **settings** - [struct] BatchOpt-shaped struct, possibly using
            %     retired field names
            %
            % Output Arguments:
            %   - **settings** - [struct] same struct with retired names replaced

            if ~isstruct(settings); return; end

            if isfield(settings, 'AtlasImport')
                if ~isfield(settings, 'LayoutImport')
                    legacyValue = settings.AtlasImport;
                    % Accept both the raw char and the {'value', {items}} cell form.
                    if iscell(legacyValue) && ~isempty(legacyValue)
                        legacyValue = legacyValue{1};
                    end
                    settings.LayoutImport = strrep(char(legacyValue), 'Atlas ', 'Vendor ');
                end
                settings = rmfield(settings, 'AtlasImport');
            end
        end

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
            % / ``id`` - batch plumbing rather than user settings.
            %
            % Output Arguments:
            %   - **fieldNames** - [cell] BatchOpt field names, in dialog order
            %
            fieldNames = { ...
                'LayoutSource', 'InputPath', 'SubfolderMode', 'LayoutImport', ...
                'GridRows', 'GridCols', 'TileOrder', 'OverlapX', 'OverlapY', 'EstimateOverlap', ...
                'TransformType', 'AllowRotation', 'RegistrationMethod', 'FeatureDetectorType', ...
                'QualityThreshold', 'NominalPositionWeight', 'SubpixelPlacement', ...
                'OutputMode', 'OutputPath', 'OutputFormat', 'BlendMode', 'IntensityCorrection', ...
                'CanvasColor', 'Autocrop', 'SaveProject'};
        end

        function formats = imageFileFormats()
            % IMAGEFILEFORMATS - The image file formats ``OutputMode = Image files`` offers.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       formats = controllers.Stitching.imageFileFormats()
            %
            % One table shared by the file picker
            % (:meth:`controllers.Stitching.selectOutputPath_Callback`), the
            % ``BatchOpt.OutputFormat`` item list and the fuse
            % (:meth:`controllers.Stitching.stitchBtn_Callback`), so a label
            % offered in the dialog cannot name a saver the fuse does not call.
            %
            % ``label`` is what the user picks and what ``BatchOpt.OutputFormat``
            % records; ``saverFormat`` + ``policy`` are what
            % :func:`utils.stitch.fuseToFiles` passes on to ``io.SaverFactory``.
            % The two are not the same string because a TIF format name says
            % nothing about 2-D versus 3-D - MIB's own Save-as asks that
            % separately, through ``Saving3DPolicy`` - and this dialog raises no
            % follow-up questions, so the choice has to be in the label.
            %
            % Output Arguments:
            %   - **formats** - [1xN struct] with fields ``.label``,
            %     ``.extension``, ``.saverFormat``, ``.policy``
            %
            formats = struct( ...
                'label', { ...
                    'TIF format uncompressed, 2D sequence (*.tif)', ...
                    'TIF format LZW compression, 2D sequence (*.tif)', ...
                    'Portable Network Graphics, 2D sequence (*.png)', ...
                    'Amira Mesh binary, 2D sequence (*.am)', ...
                    'Amira Mesh binary, 3D stack (*.am)'}, ...
                'extension', {'.tif', '.tif', '.png', '.am', '.am'}, ...
                'saverFormat', { ...
                    'TIF format uncompressed (*.tif)', ...
                    'TIF format LZW compression (*.tif)', ...
                    'Portable Network Graphics (*.png)', ...
                    'Amira Mesh binary file sequence (*.am)', ...
                    'Amira Mesh binary (*.am)'}, ...
                'policy', {'2D sequence', '2D sequence', '2D sequence', ...
                    '2D sequence', '3D stack'});
        end

        function entry = imageFileFormat(label)
            % IMAGEFILEFORMAT - Look one :meth:`imageFileFormats` row up by label.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       entry = controllers.Stitching.imageFileFormat(label)
            %
            % Input Arguments:
            %   - **label** - [char] a ``BatchOpt.OutputFormat`` value
            %
            % Output Arguments:
            %   - **entry** - [struct] the matching row; the FIRST row when the
            %     label is unknown, so a project or batch protocol written by a
            %     newer MIB still exports rather than erroring
            %
            formats = controllers.Stitching.imageFileFormats();
            matchIdx = find(strcmp({formats.label}, label), 1);
            if isempty(matchIdx); matchIdx = 1; end
            entry = formats(matchIdx);
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
            %   - **obj** - handle to the Stitching controller
            %   - **evnt** - event data from the model
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
            %   - **mibModel** - handle to MibModel
            %   - **varargin{1}** *(optional)* - BatchOpt struct (batch run), or NaN
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
            obj.resolvePending     = false;
            obj.seamScoresStamp    = [];
            obj.zarrExportOptions  = [];
            obj.automaticOptions = obj.defaultFeatureOptions();

            % ---- BatchOpt defaults
            obj.BatchOpt.LayoutSource    = {'Grid'};
            obj.BatchOpt.LayoutSource{2} = {'Bio-Formats metadata', 'Filename pattern', ...
                'Grid', 'Position file'};

            obj.BatchOpt.InputPath       = '';
            obj.BatchOpt.SubfolderMode   = false;

            % How much of an acquisition's OWN stitch to take. Consulted only
            % when the Position file source is pointed at a file that can carry
            % one - a Fibics Atlas ``.ve-mif`` or a SerialEM ``.mdoc`` - rather
            % than a position text file. The GUI asks when the vendor's stitch is
            % found and records the answer here, so a batch protocol or a reloaded
            % project repeats the same import silently.
            %
            % Vendor-neutral by design: both formats record the same three stages
            % (nominal placement, pairwise seam measurements, solved positions),
            % and naming the field after one of them made a SerialEM protocol read
            % as an Atlas import. ``AtlasImport`` is still accepted on input.
            obj.BatchOpt.LayoutImport    = {'Vendor seams + solved positions'};
            obj.BatchOpt.LayoutImport{2} = {'Nominal grid only', ...
                'Vendor seam measurements', 'Vendor seams + solved positions'};

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
            obj.BatchOpt.OutputMode{2}   = {'In memory', 'OME-Zarr3 (BigData)', 'Image files'};
            obj.BatchOpt.OutputPath      = '';

            % Which image format 'Image files' writes. Widget-less, like
            % LayoutImport: the choice is made in the output file picker, where
            % it belongs - a format dropdown beside a path field is a second
            % place to state the same thing, and the two can disagree.
            imageFormats = controllers.Stitching.imageFileFormats();
            obj.BatchOpt.OutputFormat    = {imageFormats(1).label};
            obj.BatchOpt.OutputFormat{2} = {imageFormats.label};

            % Overwrite by default: it is the honest one. Every other mode mixes
            % the overlap and so SOFTENS a misalignment, which is exactly what
            % must stay visible while the stitch is being judged - switch to
            % Feather once the seams are known to be right.
            obj.BatchOpt.BlendMode       = {'Overwrite'};
            obj.BatchOpt.BlendMode{2}    = {'Average', 'Feather', 'Max', 'Min', 'Overwrite'};

            % Evens out tile brightness before anything reads a pixel. A family
            % rather than a checkbox because the right correction depends on WHY
            % the tiles differ, and the two causes want opposite treatments - see
            % utils.stitch.estimateIntensityCorrection for the measured comparison.
            obj.BatchOpt.IntensityCorrection    = {'None'};
            obj.BatchOpt.IntensityCorrection{2} = {'None', 'Flat-field (shared)', ...
                'Flat-field (overlap-solved)', 'Match tile means'};

            % What the mosaic's uncovered pixels are filled with. Defaults to
            % white because MIB's stitching input is predominantly EM, where an
            % empty field is bright and a zero frame reads as a black border
            % drawn around the specimen. See utils.stitch.canvasBackground.
            obj.BatchOpt.CanvasColor     = {'white'};
            obj.BatchOpt.CanvasColor{2}  = {'black', 'white'};

            % Trim the ragged frame instead of colouring it. Off by default: it
            % changes the output dimensions, and a mosaic whose size no longer
            % matches the plan is a surprise nobody asked for.
            obj.BatchOpt.Autocrop        = false;

            obj.BatchOpt.SaveProject     = true;
            obj.BatchOpt.showWaitbar     = true;

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
            obj.BatchOpt.mibBatchActionName  = 'Stitching';

            obj.BatchOpt.mibBatchTooltip.LayoutSource    = sprintf([ ...
                'Where the tile arrangement comes from:\n' ...
                '  - Grid: a regular grid you describe with Rows/Cols and overlap\n' ...
                '  - Position file: a file stating where each tile goes - MIB text, a Fibics Atlas ".ve-mif" mosaic, or a SerialEM ".mdoc" montage\n' ...
                '  - Filename pattern: grid indices read from "_Z##-X##-Y##" in the names\n' ...
                '  - Bio-Formats metadata: stage coordinates embedded in the image files']);
            obj.BatchOpt.mibBatchTooltip.InputPath       = 'Path to the tile folder, position file, Atlas .ve-mif mosaic, SerialEM .mdoc/.mrc montage, or folder of tile files';
            obj.BatchOpt.mibBatchTooltip.SubfolderMode   = 'Each tile is a folder of slice images (a Z-stack) instead of a single image file - works with any layout source';
            obj.BatchOpt.mibBatchTooltip.LayoutImport    = sprintf([ ...
                'How much of the acquisition''s own stitch to reuse. Applies to a Fibics Atlas ".ve-mif" or SerialEM ".mdoc"; ignored for a plain position text file:\n' ...
                '  - Nominal grid only: ignore it, register everything from scratch\n' ...
                '  - Vendor seam measurements: take the recorded pairwise shifts, let MIB run the global solve\n' ...
                '  - Vendor seams + solved positions: also take the final placement, so Stitch fuses with nothing recomputed']);
            obj.BatchOpt.mibBatchTooltip.GridRows        = 'Number of grid rows (0 = auto from tile count)';
            obj.BatchOpt.mibBatchTooltip.GridCols        = 'Number of grid columns (0 = auto from tile count)';
            obj.BatchOpt.mibBatchTooltip.TileOrder       = sprintf([ ...
                'Order the tiles were acquired in, which is how file order maps to grid position:\n' ...
                '  - Horizontal: row by row, each row restarting on the left\n' ...
                '  - Horizontal snake: row by row, alternate rows right to left\n' ...
                '  - Vertical: column by column, each column restarting at the top\n' ...
                '  - Vertical snake: column by column, alternate columns bottom to top']);
            obj.BatchOpt.mibBatchTooltip.OverlapX        = 'Horizontal overlap between adjacent tiles in percent (0 - 90)';
            obj.BatchOpt.mibBatchTooltip.OverlapY        = 'Vertical overlap between adjacent tiles in percent (0 - 90)';
            obj.BatchOpt.mibBatchTooltip.EstimateOverlap = 'Estimate the actual overlap from the images before measuring (grid layout); OverlapX/Y are then only a rough starting guess';
            obj.BatchOpt.mibBatchTooltip.TransformType   = sprintf([ ...
                'How much each tile is allowed to move to fit its neighbours:\n' ...
                '  - Translation: shift only, the right choice for stage-tiled data\n' ...
                '  - Rigid: shift + rotation\n' ...
                '  - Similarity: shift + rotation + uniform scale\n' ...
                '  - Affine: shift + rotation + scale + shear\n' ...
                'Anything above Translation acts in-plane per slice (z stays a shift) and forces feature-based measurement.']);
            obj.BatchOpt.mibBatchTooltip.AllowRotation   = sprintf([ ...
                'The tiles are rotated against each other. Two effects:\n' ...
                '  - allows per-tile rotation in the Rigid/Similarity/Affine solve\n' ...
                '  - switches feature matching to rotation-invariant descriptors\n' ...
                'Keep off for stage-tiled data: stages translate but do not rotate, so matching is faster and a noisy overlap cannot inject a spurious rotation.']);
            obj.BatchOpt.mibBatchTooltip.RegistrationMethod = sprintf([ ...
                'How the shift between two overlapping tiles is measured:\n' ...
                '  - Phase correlation: best for small overlaps with modest jitter\n' ...
                '  - Feature-based: best for large or unknown offsets, matches SURF features over the full tiles']);
            obj.BatchOpt.mibBatchTooltip.FeatureDetectorType = '[Feature-based]: keypoint detector used to match tiles; configure its parameters + downsampling with the Settings button';
            obj.BatchOpt.mibBatchTooltip.QualityThreshold = 'Minimum normalized peak height to accept a pairwise shift measurement (0 - 1)';
            obj.BatchOpt.mibBatchTooltip.NominalPositionWeight = 'How strongly tiles with weak or failed registration are pulled back toward their nominal grid positions (0 - 1)';
            obj.BatchOpt.mibBatchTooltip.SubpixelPlacement = 'Sub-pixel refinement of the pairwise-shift measurements; tiles are still placed on whole pixels';
            obj.BatchOpt.mibBatchTooltip.OutputMode      = sprintf([ ...
                'Where the fused mosaic goes:\n' ...
                '  - In memory: a Standard dataset, opened straight into MIB\n' ...
                '  - OME-Zarr3 (BigData): streamed to disk tile by tile, for a mosaic that does not fit in RAM; pyramid settings are asked when stitching\n' ...
                '  - Image files: written to disk as ordinary TIF/PNG/Amira files and not opened; pick the format in the output file dialog']);
            obj.BatchOpt.mibBatchTooltip.OutputPath      = 'Output path for the OME-Zarr3 BigData store or the image file(s); ignored when OutputMode = In memory';
            obj.BatchOpt.mibBatchTooltip.OutputFormat    = sprintf([ ...
                '[OutputMode = Image files] Image format the mosaic is written in, chosen in the output file dialog:\n' ...
                '  - TIF format uncompressed, 2D sequence: one numbered .tif per mosaic slice, the format everything reads and the fastest to write\n' ...
                '  - TIF format LZW compression, 2D sequence: the same pixels losslessly compressed; smaller on typical EM data, slower to write, and LZW can EXPAND a noisy image\n' ...
                '  - Portable Network Graphics, 2D sequence: one numbered .png per slice; lossless, and the most reliably compressed of the three\n' ...
                '  - Amira Mesh binary, 2D sequence: one numbered .am per slice, carrying the voxel size in each header\n' ...
                '  - Amira Mesh binary, 3D stack: the whole mosaic in a single .am; needs it all in RAM, the TIF and PNG sequences do not']);
            obj.BatchOpt.mibBatchTooltip.BlendMode       = sprintf([ ...
                'How pixels are combined where tiles overlap:\n' ...
                '  - Average: plain mean of the overlapping tiles; sharper than Feather, but any brightness step stays visible\n' ...
                '  - Feather: weighted blend fading out toward each tile edge, hides small steps; the choice for a finished mosaic\n' ...
                '  - Max: brightest tile wins; keeps bright detail, drops dark debris\n' ...
                '  - Min: darkest tile wins; keeps dark detail, drops bright debris\n' ...
                '  - Overwrite: the last tile wins; hard seams and no mixing, which is what makes it the honest check that the tiles are actually aligned (default)\n' ...
                'Blending hides a brightness step, it does not remove it - see Intensity correction.']);
            obj.BatchOpt.mibBatchTooltip.IntensityCorrection  = sprintf([ ...
                'Even out tile brightness before measuring and fusing:\n' ...
                '  - None: use the pixels as they are\n' ...
                '  - Flat-field (shared): one illumination field averaged from all the tiles; needs many tiles with different specimen under each, or it absorbs the sample''s own shading\n' ...
                '  - Flat-field (overlap-solved): fits the field to the disagreement where tiles overlap, so the specimen cancels out, then levels the mosaic. Slower to set up but the better answer whenever seams still show\n' ...
                '  - Match tile means: scale each tile to the common mean. For a detector that drifts over a long acquisition; it does NOT fix uneven illumination, which sits inside each tile']);
            obj.BatchOpt.mibBatchTooltip.CanvasColor     = sprintf([ ...
                'Fill for the mosaic pixels no tile covers - the frame the solved positions leave around the edges, and any gap inside:\n' ...
                '  - white: the highest intensity the output image class can hold; the right choice for EM, where an empty field is bright\n' ...
                '  - black: zero, the usual background for light microscopy\n' ...
                'Tick Autocrop to remove the frame instead of colouring it.']);
            obj.BatchOpt.mibBatchTooltip.Autocrop        = ...
                'Crop the mosaic to the largest rectangle that tiles cover on every output slice, so no background frame is left along the ragged edges. The output is smaller than the planned canvas';
            obj.BatchOpt.mibBatchTooltip.SaveProject     = 'Save project sidecar JSON after stitching';
            obj.BatchOpt.mibBatchTooltip.showWaitbar     = 'Show progress bar during stitching (batch-only option, not shown in the GUI)';

            % ---- Batch-mode path (nargin == 3 means controller called with BatchOpt/NaN)
            if nargin == 3
                BatchOptInput = varargin{2};
                if isstruct(BatchOptInput)
                    BatchOptInput = controllers.Stitching.renameLegacyFields(BatchOptInput);
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
            % Placeholder only - buildFeatureOptions DERIVES this from
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
            % are therefore one user decision - "are the tiles rotated?" - and
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
            %   - **figureHandle** - [handle] the ``StitchingGUI`` figure, or
            %     ``[]`` when the controller has no (valid) view
            %
            figureHandle = [];
            if ~isempty(obj.view) && ~isempty(obj.view.gui) && isvalid(obj.view.gui)
                figureHandle = obj.view.gui;
            end
        end

        % ---------------------------------------------------------------
        function stamp = currentSeamScoreStamp(obj)
            % CURRENTSEAMSCORESTAMP - What a seam-score pass over the current
            % state would be valid for.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      stamp = obj.currentSeamScoreStamp()
            %
            % One builder shared by everything that records the stamp, so the
            % fields compared in
            % :meth:`controllers.Stitching.seamScoresAreCurrent` and the fields
            % written after scoring cannot drift apart.
            %
            % Output Arguments:
            %   - **stamp** - [struct] ``.positions``, ``.numEdges``,
            %     ``.correctionMethod``
            %
            stamp = struct( ...
                'positions',        obj.positions, ...
                'numEdges',         numel(obj.edges), ...
                'correctionMethod', obj.BatchOpt.IntensityCorrection{1});
        end

        % ---------------------------------------------------------------
        function tf = seamScoresAreCurrent(obj)
            % SEAMSCORESARECURRENT - True when obj.edges' seam scores still
            % describe the current placement, edge set and intensity correction.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      tf = obj.seamScoresAreCurrent()
            %
            % The stamp is COMPARED against live state rather than cleared by
            % whoever changes that state: a rescore that should have happened
            % and did not is a mosaic rated on the wrong pixels, and there is no
            % single place every position change goes through. Every edge must
            % also actually carry a score - a cancelled pass or a pre-scoring
            % project leaves some empty, and a partial set is not a set.
            %
            tf = false;
            if isempty(obj.seamScoresStamp) || isempty(obj.edges) || isempty(obj.positions)
                return;
            end
            stamp = obj.seamScoresStamp;
            if ~isequal(stamp.positions, obj.positions); return; end
            if stamp.numEdges ~= numel(obj.edges); return; end
            if ~strcmp(stamp.correctionMethod, obj.BatchOpt.IntensityCorrection{1}); return; end
            if ~isfield(obj.edges, 'seamScore'); return; end
            if any(cellfun(@isempty, {obj.edges.seamScore})); return; end
            tf = true;
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
            % as an error - the caller's ``return`` would otherwise report
            % success for work that never happened.
            %
            % Input Arguments:
            %   - **message** - [char] what is missing, in user language
            %   - **dlgTitle** - [char] dialog title
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
            %   - **errorInfo** - [MException] the caught error
            %   - **dlgTitle** - [char] dialog title
            %
            if isempty(obj.view); rethrow(errorInfo); end
            utils.dlgs.showErrorDialog(obj.guiFigure(), errorInfo.message, dlgTitle);
        end

        % ---------------------------------------------------------------
        function refreshInputPathWidget(obj)
            % REFRESHINPUTPATHWIDGET - Show BatchOpt.InputPath in the InputPath
            % widget, handling either a uieditfield (single newline-joined string)
            % or a uilistbox (one item per path - better for multi-folder input).
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
            % provide. Guarded by ``isfield`` - no-op until the ``infoLabel``
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
                    description = sprintf(['A file stating where each tile goes: a text file\n' ...
                        '("tiles/tile_01.tif 0 0 0" per line), a Fibics Atlas mosaic ("*.ve-mif")\n' ...
                        'or a SerialEM montage ("*.mdoc") - the last two can import their own stitch.']);
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
