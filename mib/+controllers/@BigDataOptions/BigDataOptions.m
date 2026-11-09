classdef BigDataOptions < handle
% BIGDATAOPTIONS - Shared BigData output options for the Image tools: BatchOpt fields, a panel added to the tool's window, and the run.
%
% The source image of a BigData dataset is read-only, so an Image tool that
% processes it writes the result to a new OME-Zarr store. This class gives every
% such tool the same three pieces, so the tool itself needs about three calls:
%
%   1. **BatchOpt fields** (``addBatchOptFields``), added in the tool's
%      constructor before its batch dispatch, so batch protocols carry them:
%
%      - ``BigData_PyramidLevel`` - ``{'s0', {'s0', 's1', ...}}``, the level
%        that is processed; named from ``s0`` (full resolution) as in Crop and
%        Chunking export, without the level size, so a protocol recorded on one
%        dataset runs on another of a different size. Only the leading ``sN`` is
%        read
%      - ``BigData_OutputPath`` - [char] path of the new store, default
%        ``<source stem>_<suffix>.zarr3`` next to the source
%      - ``BigData_Result`` - ``{'OME-Zarr store', items}``; ``'Standard (in
%        memory)'`` opens the result as a Standard dataset in ``BigData_OpenIn``
%        instead (``runToStandard``), and the Open in items are then
%        ``'Current overwrite (BigData)'``, ``'Current'`` and ``'Container N'``
%      - ``BigData_OpenIn`` - ``{'Container 3', items}``: ``'Current overwrite (BigData)
%        (BigData)'``, ``'Current'``, ``'Container N'`` or ``'Do not open'``;
%        default the first empty container, else ``'Do not open'``.
%        ``'Current'`` opens the new store in this buffer and keeps the
%        source store; ``'Current overwrite (BigData)'`` replaces the source
%        store itself (see below) with either ``BigData_Result``, and ignores
%        ``BigData_OutputPath``
%
%      They are ignored for datasets that are not BigData.
%   2. **The panel** (``attach`` / ``updateWidgets``): the component
%      ``views.components.BigDataOutput``, inserted in code, so the tool's
%      ``.mlapp`` has no BigData widgets: a row of the component's designed
%      height is inserted into the window's top grid layout above its last row
%      (the buttons), and the window grows by that height. It is created the
%      first time the active dataset is BigData and then only hidden (its row
%      at 0 px, the window shorter by that height) and shown again. Its
%      widgets (the component's ``handles``) are tagged with their BatchOpt
%      field names and write into ``controller.BatchOpt`` through
%      ``utils.updateBatchOptFromGUI_Shared``. They are not added to
%      ``controller.view.handles``: ``utils.updateGUIFromBatchOpt_Shared`` looks
%      up App Designer widgets as properties of the app, so the panel keeps its
%      own widgets in sync.
%   3. **The run** (``run``): checks, the Zarr settings dialog (GUI only,
%      pre-filled from the source pyramid as Alignment and Crop do), the
%      processing through ``utils.bigdata.processImageToStore``, and opening the
%      result in the chosen buffer (``openStoreInBuffer``). A tool whose result
%      is a mask or selection calls ``runToModel`` instead, which writes into
%      the model of the dataset; ``setModelOutput(true)`` then disables the
%      widgets that do not apply (Open in, Output). ``reportStoreResult`` /
%      ``reportModelResult`` then tell the user where the result went, the
%      same way for every tool.
%
% **Output path checks.** The path of any store open in MIB (an image or a
% BigData labels store of any buffer) is refused. An existing folder is replaced
% after a question in the GUI, without one in batch mode, where the protocol
% names the path on purpose.
%
% **Cancel and Resume.** A cancelled run into a new store returns an empty
% result, so nothing half-written is opened. The GUI then asks whether to keep
% the partial store (one carrying the saver's resume record, i.e. one this run
% wrote) or delete it; without a window it is deleted. A kept store, and the
% store of a run that failed, gets ``ResumeSettingsFile`` with the saver
% options of the run. When a later run finds the resume record at its output
% path, the GUI asks Resume / Start over / Cancel (batch: ``ResumeIncomplete``):
% Resume skips the run confirmation and the Zarr settings dialog, takes the
% saver options from that file (the source-derived defaults when it is
% missing, after a crash) and continues with ``saveStreamResumable``'s
% ``Resume``, which redoes nothing finished. The saver compares the store and
% the source fingerprint of ``processImageToStore`` (source, level, channels,
% halo, block function, the tool's ``Fingerprint``, ROI box) with the record
% and refuses another run (``cannotResume``, reported with a hint to Start
% over). The file is deleted when the store completes. Current overwrite,
% model output and a Standard result write no store to resume.
%
% **Current overwrite (BigData)** replaces the image store of the dataset on
% disk, with either ``BigData_Result`` (the result stays a BigData dataset, so
% the Standard result does not apply to it). It is refused unless the image is unlocked (a BigData image opens locked; in the
% GUI the locked notice offers to unlock it), the level is ``s0`` (the result
% must keep the size of the image, so the model, ROIs and annotations stay
% valid) and the image is an OME-Zarr v3 store (a vendor file cannot be
% rewritten). The GUI asks for a confirmation; there is no Zarr settings
% dialog, the store keeps the layout of its pyramid. Steps: the result is
% written to ``<stem>.mib_overwrite<ext>`` next to the store; group
% attributes of the source that the saver does not write (``omero``, ...)
% are copied over; the readers are closed; the store is renamed to
% ``<stem>.mib_replaced<ext>``, the result to the store's name, and the
% renamed source is deleted. If the second rename fails the source is renamed
% back. Only the image object of the dataset is then replaced - labels, mask,
% selection, ROIs, annotations, measurements and the view stay - and the
% action log, LUT colours, mask filename, lock state and (for an unchanged
% class) the contrast are carried over. ``io.zarr.ChunkCache`` is cleared,
% because its key (path plus the metadata file's time stamp) can match a
% store rewritten within the same second. ``NewDataset`` is sent with
% ``keepBackup``, so the undo history of the model survives. A cancel or an
% error deletes the temporary store and leaves the source as it was.
%
% **Current overwrite (BigData) of the shown slice** (``DatasetType`` ``'2D, Slice'``,
% the only result for which the tool offers it; a dataset of more than one
% slice) writes into the store instead of replacing it, so one slice costs
% one slice, not the whole stack (``overwriteRegion``); so does Restrict to
% ROI, for the ROI box of the shown slice or of every slice. Two steps: the slice is
% processed into ``<stem>.mib_overwrite<ext>`` (cancelable; the source is not
% touched), then written into level ``s0`` of the store and rebuilt in every
% coarser level from the level above, as the saver builds them (bilinear,
% ``imresize`` by 0.5, the Z pairs of an anisotropy-preserving level
% averaged). The second step is not cancelable: stopped halfway it would
% leave the slice half old and half new. The store must have the layout MIB
% writes (axes ``yxz`` or ``yxzc``, each level half the size of the level
% above in XY and 1 or 2 in Z); another layout is refused before reading. The
% store keeps its chunks, shards and attributes; the image object is reopened
% as after the whole overwrite.
%
% **Restrict to ROI** (the checkbox of the Selection panel,
% ``MibDataset.restrictToROI``), in a tool that sets ``RoiAware`` (one that
% honours it on a Standard dataset), limits every output to the box of the ROI
% selected in the ROI list, or of all XY ROIs (``regionOfInterest``): a new
% store or a Standard result is that box of the level, placed where the box
% is (its bounding box starts there); the mask or selection and the image of
% a Current overwrite change only inside the box. Inside the box, pixels
% outside a ROI that is not a rectangle keep their values. The halo is read
% around the box in X and Y, so the box equals that part of a whole run.
%
% **Parallel processing.** With ``BatchOpt.UseParallelComputing`` (a tool's
% own checkbox; a BatchOpt without the field runs on the client) every output
% computes its bands on the workers of a process pool (``startPool``: the open
% pool, or one of ``preferences.System.cpuParallelLimit`` workers started after
% the confirmation). A new store and the whole-image overwrite pass the pool to
% ``processImageToStore``, whose saver also writes on the workers; the model,
% a Standard result and the processing step of ``overwriteRegion`` compute the
% bands on the workers and write them on the client (``processBands``). Each
% worker opens the source store itself (``io.savers.FilteredSliceProvider``),
% so the block function must capture only data, not handles. The result equals
% the one computed on the client. After the run the chunk caches of the
% workers are cleared, so an overwrite never leaves stale chunks there. The
% gain is in the computing: measured on a local SSD (2026-11-07) it was
% 90-99 % of a run for NonLocalMeans, LocalContrast, FastLocalLaplacian and
% BMxD, but 16-48 % for Gaussian, Median and Bilateral, whose runs are mostly
% reading and writing.
%
% See also: utils.bigdata.processImageToStore, io.savers.FilteredSliceProvider,
% io.savers.Zarr3Saver.reviewOptionsDialog
%
% **Example** - in a tool controller:
%
%   .. code-block:: matlab
%
%      % constructor, before the batch dispatch
%      obj.bigDataOptions = controllers.BigDataOptions(obj, 'filtered');
%      obj.BatchOpt = obj.bigDataOptions.addBatchOptFields(obj.BatchOpt);
%      % after the view is created, and in updateWidgets
%      obj.bigDataOptions.updateWidgets();
%      % at Apply, for a BigData dataset
%      result = obj.bigDataOptions.run(obj.BatchOpt, @(block) imgaussfilt(block, 2), HaloYX = 6);

    properties
        OutputSuffix (1,:) char = 'processed'
        % [char] suffix of the default output name, ``<stem>_<suffix>.zarr3``
        BandBytes (1,1) double {mustBePositive} = 256e6
        % [double] memory budget of one band of ``run`` (``utils.bigdata.processImageToStore``); a test lowers it to check the halos
        GuidePixels (1,1) double {mustBePositive} = 32e6
        % [double] the most pixels of the coarser level slice that a filter depending on the whole slice takes its global part from (ImageFilters); 32 Mpx keep that pass to seconds and under 1 GB
        ModelOutput (1,1) logical = false
        % [logical] true while the tool writes into the model (``runToModel``): only the level applies, Open in and Output are disabled
        ResumeIncomplete (1,1) logical = false
        % [logical] without a window (batch, tests): resume an unfinished store found at the output path instead of starting over; the window asks
        RoiAware (1,1) logical = false
        % [logical] true for a tool that honours Restrict to ROI on a Standard dataset (Image filters): its runs are then limited to the ROI box (``regionOfInterest``); the other tools process the whole dataset, as they do on a Standard one
    end

    properties (SetAccess = private)
        controller
        % handle to the tool controller; must have ``mibModel``, ``BatchOpt`` and ``view``
        mibModel
        % handle to models.MibModel
        panel = []
        % handle to the views.components.BigDataOutput component, empty while not shown
    end

    properties (Access = private)
        widgets = struct()
        % handles of the panel widgets
        pathEditedByUser = false
        % true once the user typed or selected a path; the default then stops following the suffix
        panelHeight = 0
        % height of the inserted grid row, pixels: the designed height of the component
        panelShown = false
        % [logical] true while the panel's row has its height, false while it is 0 px (a dataset that is not BigData)
        datasetTypeItems = {}
        % [cell] the tool's own ``DatasetType`` items, kept while ``'2D, Slice'`` is removed from them
    end

    properties (Constant)
        DoNotOpen = 'Do not open'
        % item of BigData_OpenIn that writes the store only
        CurrentOverwrite = 'Current overwrite (BigData)'
        % item of BigData_OpenIn that replaces the image store of the dataset
        StoreResult = 'OME-Zarr store'
        % item of BigData_Result: the result is written to a new store
        StandardResult = 'Standard (in memory)'
        % item of BigData_Result: the result opens as a Standard dataset, no store is written
        ResumeSettingsFile = '.mib_run_settings.mat'
        % file in an unfinished store with the saver options of its run (``saverOptions``), read back on Resume
    end

    methods
        function obj = BigDataOptions(controller, outputSuffix)
            % BIGDATAOPTIONS - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = controllers.BigDataOptions(controller)
            %       obj = controllers.BigDataOptions(controller, outputSuffix)
            %
            % Input Arguments:
            %   - **controller** - the tool controller (``mibModel``, ``BatchOpt``, ``view``)
            %   - **outputSuffix** - *(optional)* suffix of the default output name, default ``'processed'``
            obj.controller = controller;
            obj.mibModel = controller.mibModel;
            if nargin > 1 && ~isempty(outputSuffix); obj.OutputSuffix = outputSuffix; end
        end

        function BatchOpt = addBatchOptFields(obj, BatchOpt)
            % ADDBATCHOPTFIELDS - Add or refresh the BigData_* fields for the dataset ``BatchOpt.id``.
            %
            % Refreshes the item lists from the dataset (levels, containers). The
            % selected level and buffer are kept when still valid; the output path
            % follows the dataset and suffix until the user has changed it.
            dataset = obj.mibModel.I{BatchOpt.id};

            % plain level names, without sizes: a protocol recorded on one dataset
            % must match the items of another one; the size label shows the size
            levelItems = {'s0'};
            if strcmp(dataset.datasetType, 'BigData')
                levelItems = arrayfun(@(level) sprintf('s%d', level), ...
                    0:size(dataset.image.pyramid.levelImageSizes, 1) - 1, 'UniformOutput', false);
            end
            selectedLevel = 1;
            if isfield(BatchOpt, 'BigData_PyramidLevel') && ~isempty(BatchOpt.BigData_PyramidLevel)
                selectedLevel = obj.levelFromItem(BatchOpt.BigData_PyramidLevel{1});
                if isempty(selectedLevel) || selectedLevel > numel(levelItems); selectedLevel = 1; end
            end
            BatchOpt.BigData_PyramidLevel = {levelItems{selectedLevel}, levelItems};

            if ~obj.pathEditedByUser || ~isfield(BatchOpt, 'BigData_OutputPath') || isempty(BatchOpt.BigData_OutputPath)
                [sourceFolder, sourceStem] = fileparts(dataset.image.filename);
                if isempty(sourceFolder); sourceFolder = obj.mibModel.currentDirectory; end
                BatchOpt.BigData_OutputPath = fullfile(sourceFolder, [sourceStem '_' obj.OutputSuffix '.zarr3']);
            end

            resultItems = {obj.StoreResult, obj.StandardResult};
            selectedResult = obj.StoreResult;
            if isfield(BatchOpt, 'BigData_Result') && ~isempty(BatchOpt.BigData_Result) && ...
                    ismember(BatchOpt.BigData_Result{1}, resultItems)
                selectedResult = BatchOpt.BigData_Result{1};
            end
            BatchOpt.BigData_Result = {selectedResult, resultItems};

            % a Standard result opens in a buffer: no overwrite of the store, no "Do not open"
            containerItems = arrayfun(@(id) sprintf('Container %d', id), 1:numel(obj.mibModel.I), 'UniformOutput', false);
            if strcmp(selectedResult, obj.StandardResult)
                openItems = [{obj.CurrentOverwrite, 'Current'}, containerItems];
            else
                openItems = [{obj.CurrentOverwrite, 'Current'}, containerItems, {obj.DoNotOpen}];
            end
            if isfield(BatchOpt, 'BigData_OpenIn') && ~isempty(BatchOpt.BigData_OpenIn) && ...
                    ismember(BatchOpt.BigData_OpenIn{1}, openItems)
                selectedOpen = BatchOpt.BigData_OpenIn{1};
            else
                % no empty container: write the store only, or for a Standard result
                % replace this dataset, which the confirmation asks about
                selectedOpen = obj.DoNotOpen;
                if strcmp(selectedResult, obj.StandardResult); selectedOpen = 'Current'; end
                for id = 1:numel(obj.mibModel.I)
                    if strcmp(obj.mibModel.I{id}.image.filename, 'none.tif')
                        selectedOpen = sprintf('Container %d', id);
                        break;
                    end
                end
            end
            BatchOpt.BigData_OpenIn = {selectedOpen, openItems};

            BatchOpt.mibBatchTooltip.BigData_PyramidLevel = '[BigData] pyramid level to process; s0 is full resolution, a coarser level is faster';
            BatchOpt.mibBatchTooltip.BigData_OutputPath = '[BigData] path of the new OME-Zarr store with the result; the source is not changed';
            BatchOpt.mibBatchTooltip.BigData_Result = ['[BigData] a new OME-Zarr store, or a Standard dataset in memory ' ...
                '(when the result fits in memory; no store is written)'];
            BatchOpt.mibBatchTooltip.BigData_OpenIn = ['[BigData] buffer to open the result in, or write the store only; ' ...
                '"Current overwrite (BigData)" replaces the image store of the dataset (unlocked image, level s0), whatever the Result'];
        end

        function updateWidgets(obj)
            % UPDATEWIDGETS - Show the panel for a BigData dataset, hide it otherwise, and sync its widgets.
            %
            % Call after the tool's view is created and from the tool's
            % ``updateWidgets``. Does nothing without a view (batch mode).
            % The panel is created the first time a BigData dataset is shown
            % (``attach``) and then only hidden and shown again (``showPanel``),
            % so switching buffers does not rebuild it.
            if isempty(obj.controller.view) || ~isvalid(obj.controller.view.gui); return; end
            isBigData = strcmp(obj.mibModel.I{obj.controller.BatchOpt.id}.datasetType, 'BigData');
            if isBigData && isempty(obj.panel)
                obj.attach();
            elseif ~isempty(obj.panel)
                obj.showPanel(isBigData);
            end
            obj.updateDatasetType(isBigData);
            if ~isBigData || isempty(obj.panel); return; end

            obj.controller.BatchOpt = obj.addBatchOptFields(obj.controller.BatchOpt);
            BatchOpt = obj.controller.BatchOpt;
            for fieldName = {'BigData_PyramidLevel', 'BigData_Result', 'BigData_OpenIn'}
                obj.widgets.(fieldName{1}).Items = BatchOpt.(fieldName{1}){2};
                obj.widgets.(fieldName{1}).Value = BatchOpt.(fieldName{1}){1};
            end
            obj.widgets.BigData_OutputPath.Value = BatchOpt.BigData_OutputPath;
            obj.updateSizeLabel();
            obj.updatePathEnable();
        end

        function setModelOutput(obj, modelOutput)
            % SETMODELOUTPUT - Switch the panel between an image result (new store) and a model result (``runToModel``).
            obj.ModelOutput = modelOutput;
            obj.updatePathEnable();
            if ~isempty(obj.controller.view) && isvalid(obj.controller.view.gui)
                obj.updateDatasetType(strcmp(obj.mibModel.I{obj.controller.BatchOpt.id}.datasetType, 'BigData'));
            end
        end

        function setOutputSuffix(obj, outputSuffix)
            % SETOUTPUTSUFFIX - Change the suffix of the default output name (e.g. the selected filter).
            obj.OutputSuffix = outputSuffix;
            if obj.pathEditedByUser; return; end
            obj.controller.BatchOpt = obj.addBatchOptFields(obj.controller.BatchOpt);
            if ~isempty(obj.panel)
                obj.widgets.BigData_OutputPath.Value = obj.controller.BatchOpt.BigData_OutputPath;
            end
        end

        function result = run(obj, BatchOpt, blockFunction, options)
            % RUN - Process the BigData dataset ``BatchOpt.id`` into a new store and open it, or overwrite its store.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       result = obj.run(BatchOpt, blockFunction)
            %       result = obj.run(BatchOpt, blockFunction, HaloYX = 6, HaloZ = 0, Fingerprint = '...')
            %
            % Input Arguments:
            %   - **BatchOpt** - the tool's BatchOpt with ``id`` and the BigData_* fields
            %   - **blockFunction** - ``out = f(block)``, see ``io.savers.FilteredSliceProvider``
            %   - **options.HaloYX**, **options.HaloZ** - halo rows / slices, default 0
            %   - **options.ColChannel** - channels to read, default ``[]`` (all)
            %   - **options.Fingerprint** - description of the processing parameters, see
            %     ``utils.bigdata.processImageToStore``
            %   - **options.BandBytes** - memory budget of a band, default ``[]``: the
            %     ``BandBytes`` property. A block function that keeps several working
            %     copies of a band (a pyramid per intensity level) passes a smaller one
            %   - **options.Confirmed** - [logical] the tool already asked
            %     ``confirmRun`` (before a statistics pass), default false: the
            %     window then asks here, before the store dialogs
            %
            % With ``BigData_Result`` ``'Standard (in memory)'`` no store is
            % written: the result opens as a Standard dataset (``runToStandard``),
            % except with ``'Current overwrite (BigData)'``, which always
            % rewrites the source store.
            %
            % Output Arguments:
            %   - **result** - struct with ``outputPath`` [char] and ``bufferId``
            %     (``0`` when not opened); for ``'Current overwrite (BigData)'`` the path of
            %     the replaced store and ``BatchOpt.id``; for a Standard result
            %     ``'Container N (Standard, in memory)'`` and ``N``; ``[]`` when the
            %     user cancelled at any step
            %
            % Errors of the processing (a refused output class, a failed task) are
            % raised; the caller shows them.
            arguments
                obj
                BatchOpt (1,1) struct
                blockFunction (1,1) function_handle
                options.HaloYX (1,1) double = 0
                options.HaloZ (1,1) double = 0
                options.ColChannel = []
                options.Fingerprint = ''
                options.BandBytes double = []
                options.Confirmed (1,1) logical = false
            end
            if isempty(options.BandBytes); options.BandBytes = obj.BandBytes; end
            result = [];
            dataset = obj.mibModel.I{BatchOpt.id};
            if ~strcmp(dataset.datasetType, 'BigData')
                error('controllers:BigDataOptions:notBigData', 'Dataset %d is not a BigData dataset.', BatchOpt.id);
            end
            parentFigure = obj.guiFigure();
            level = obj.resolveLevel(BatchOpt);
            % an overwrite rewrites the source store with either Result
            if strcmp(BatchOpt.BigData_OpenIn{1}, obj.CurrentOverwrite)
                result = obj.runOverwrite(BatchOpt, level, blockFunction, options, parentFigure);
                return;
            end
            if isfield(BatchOpt, 'BigData_Result') && strcmp(BatchOpt.BigData_Result{1}, obj.StandardResult)
                result = obj.runToStandard(BatchOpt, level, blockFunction, options);
                return;
            end
            outputPath = char(BatchOpt.BigData_OutputPath);
            if isempty(outputPath)
                error('controllers:BigDataOptions:noOutputPath', 'The output path (BigData_OutputPath) is empty.');
            end

            [openStore, openId, openLayer] = obj.openStoreAtPath(outputPath);
            if ~isempty(openStore)
                isLocked = strcmp(openLayer, 'image') && obj.mibModel.I{openId}.image.lockedState;
                if openId == BatchOpt.id && strcmp(openLayer, 'image')
                    % writing into its own store is an overwrite of the dataset
                    if isLocked
                        error('controllers:BigDataOptions:outputIsOpen', ['The output path is the store of this ' ...
                            'dataset (buffer %d), whose image is locked.\nChoose another path, or unlock the ' ...
                            'image and set Open in to "%s".'], openId, obj.CurrentOverwrite);
                    end
                    error('controllers:BigDataOptions:outputIsOpen', ['The output path is the store of this ' ...
                        'dataset (buffer %d).\nChoose another path, or set Open in to "%s".'], openId, obj.CurrentOverwrite);
                end
                if isLocked
                    error('controllers:BigDataOptions:outputIsOpen', ['The output path is the %s, which is ' ...
                        'open in MIB and locked; choose another path.'], openStore);
                end
                error('controllers:BigDataOptions:outputIsOpen', ...
                    'The output path is the %s, which is open in MIB; choose another path.', openStore);
            end
            [region, regionMask] = obj.regionOfInterest(BatchOpt, level);

            % an unfinished store of an earlier run at this path: resume it or start over
            resumeRun = false;
            settingsFile = fullfile(outputPath, obj.ResumeSettingsFile);
            if isfile(fullfile(outputPath, '.mib_resume.json'))
                if isempty(parentFigure)
                    resumeRun = obj.ResumeIncomplete;
                else
                    answer = uiconfirm(parentFigure, sprintf(['An earlier run into\n%s\nstopped before it ' ...
                        'finished. Resume it from where it stopped, or start over?\n\nResume needs the ' ...
                        'same tool, settings, level and ROI as that run.'], outputPath), ...
                        'Resume the run?', 'Options', {'Resume', 'Start over', 'Cancel'}, ...
                        'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'question');
                    if strcmp(answer, 'Cancel'); return; end
                    resumeRun = strcmp(answer, 'Resume');
                end
            end
            if ~resumeRun && ~options.Confirmed && ~obj.confirmRun(BatchOpt, blockFunction, HaloYX = options.HaloYX, ...
                    HaloZ = options.HaloZ, ColChannel = options.ColChannel, BandBytes = options.BandBytes)
                return;
            end
            if ~resumeRun && isfolder(outputPath) && ~isfile(fullfile(outputPath, '.mib_resume.json')) && ~isempty(parentFigure)
                answer = uiconfirm(parentFigure, sprintf('%s\nalready exists. Replace it?', outputPath), ...
                    'Replace the store?', 'Options', {'Replace', 'Cancel'}, 'DefaultOption', 2, ...
                    'CancelOption', 2, 'Icon', 'warning');
                if ~strcmp(answer, 'Replace'); return; end
            end

            saverOptions = struct();
            if resumeRun
                % the store settings of the stopped run, which the saver must find again
                if isfile(settingsFile)
                    stored = load(settingsFile, 'saverOptions');
                    saverOptions = stored.saverOptions;
                end
            elseif ~isempty(parentFigure)
                % the settings of the source pyramid, as many levels as it has from this level down
                saverOptions = io.savers.Zarr3Saver.optionsFromPyramid(dataset.image.pyramid);
                saverOptions.Levels = max(1, size(dataset.image.pyramid.levelImageSizes, 1) - level + 1);
                levelSize = dataset.image.pyramid.levelImageSizes(level, :);
                if ~isempty(region); levelSize(1:2) = [region(2) - region(1), region(4) - region(3)] + 1; end
                scale = dataset.image.pyramid.levelScaleFactors(level, :);
                pixSize = dataset.image.pixSize;
                pixSize.y = pixSize.y * scale(1); pixSize.x = pixSize.x * scale(2); pixSize.z = pixSize.z * scale(3);
                datasetInfo = struct('Y', levelSize(1), 'X', levelSize(2), 'Z', levelSize(3), 'pixSize', pixSize);
                saverOptions = io.savers.Zarr3Saver.reviewOptionsDialog(saverOptions, parentFigure, ...
                    obj.mibModel.mibPath, datasetInfo);
                if isempty(saverOptions); return; end
                % the dialog omits Levels for auto and ShardSize for no sharding; say so
                % explicitly, or the source-derived values of the engine would win
                if ~isfield(saverOptions, 'Levels'); saverOptions.Levels = []; end
                if ~isfield(saverOptions, 'ShardSize'); saverOptions.ShardSize = []; end
            end
            [pool, releaseWorkers, cancelled] = obj.startPool(BatchOpt, parentFigure); %#ok<ASGLU> kept until the run returns
            if cancelled; return; end

            try
                writtenPath = utils.bigdata.processImageToStore(dataset.image, blockFunction, outputPath, ...
                    Level = level, ColChannel = options.ColChannel, HaloYX = options.HaloYX, HaloZ = options.HaloZ, ...
                    SaverOptions = saverOptions, Fingerprint = options.Fingerprint, ParentFigure = parentFigure, ...
                    BandBytes = options.BandBytes, Region = region, RegionMask = regionMask, Resume = resumeRun, ...
                    Pool = pool);
            catch processError
                if strcmp(processError.identifier, 'io:Zarr3Saver:cannotResume')
                    error('controllers:BigDataOptions:cannotResume', ['The unfinished store cannot be resumed ' ...
                        'with these settings:\n%s\nRun it again with the tool, settings, level and ROI of the ' ...
                        'stopped run, or choose Start over.'], processError.message);
                end
                % a failed run leaves its store resumable, as a cancelled one that is kept
                if ~isfile(fullfile(outputPath, '.mib_resume.json')); rethrow(processError); end
                save(settingsFile, 'saverOptions');
                failure = MException('controllers:BigDataOptions:runFailed', ['%s\n\nThe part written so far is ' ...
                    'kept in\n%s\nTo finish it, run the same tool again with the same settings, level, ROI and ' ...
                    'output path, and choose Resume; or delete the folder.'], processError.message, outputPath);
                throw(addCause(failure, processError));
            end
            if isempty(writtenPath)
                % cancelled: keep the partial store to resume it later, or delete it
                if ~isfile(fullfile(outputPath, '.mib_resume.json')); return; end
                keepStore = false;
                if ~isempty(parentFigure)
                    answer = uiconfirm(parentFigure, sprintf(['The run was stopped; the result is written ' ...
                        'only in part, to\n%s\n\nKeep it to finish later: run the same tool again with the ' ...
                        'same settings, level, ROI and output path, and choose Resume - it continues from ' ...
                        'where it stopped.\nDelete it to free the disk space.'], outputPath), ...
                        'Keep the unfinished result?', 'Options', {'Keep', 'Delete'}, ...
                        'DefaultOption', 1, 'CancelOption', 1, 'Icon', 'question');
                    keepStore = strcmp(answer, 'Keep');
                end
                if keepStore
                    save(settingsFile, 'saverOptions');
                else
                    rmdir(outputPath, 's');
                end
                return;
            end
            if isfile(fullfile(writtenPath, obj.ResumeSettingsFile)); delete(fullfile(writtenPath, obj.ResumeSettingsFile)); end

            result = struct('outputPath', writtenPath, 'bufferId', 0);
            openIn = BatchOpt.BigData_OpenIn{1};
            if strcmp(openIn, obj.DoNotOpen); return; end
            if strcmp(openIn, 'Current')
                targetId = BatchOpt.id;
            else
                targetId = sscanf(openIn, 'Container %d');
            end
            controllers.BigDataOptions.openStoreInBuffer(obj.mibModel, writtenPath, targetId);
            result.bufferId = targetId;
        end

        function result = runToModel(obj, BatchOpt, blockFunction, layer, options)
            % RUNTOMODEL - Process the image of the BigData dataset ``BatchOpt.id`` into the mask or selection of its model.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       result = obj.runToModel(BatchOpt, blockFunction, layer)
            %       result = obj.runToModel(BatchOpt, blockFunction, 'selection', HaloYX = 3, ColChannel = 1)
            %
            % The image is read at level ``BatchOpt.BigData_PyramidLevel`` in
            % bands of rows through ``io.savers.FilteredSliceProvider`` (each band
            % plus ``HaloYX`` rows, and ``HaloZ`` slices, of context), and each
            % result band replaces the layer through
            % ``core.MibBigDataLabels.setData63`` at that level. So the layer of the
            % **whole dataset** (or of ``Slices``) is replaced; ``setData63`` updates the coarser
            % levels and marks the level map, and finer levels are recomputed when
            % they are read, as after any edit at that zoom. ``BigData_OpenIn`` and
            % ``BigData_OutputPath`` do not apply. With Restrict to ROI
            % (``regionOfInterest``) only the box of the ROI is read and
            % written, and only its pixels inside the ROI change (the layer
            % outside a non-rectangular ROI is read and written back).
            %
            % Refused (errors): the checks of ``checkModelOutput`` - a dataset
            % that is not BigData, no model, a read-only model, a model level of
            % another size than the image level.
            %
            % **No undo.** The layer of a whole slide can be many GB, so no copy is
            % kept; the GUI asks for a confirmation first. A cancel stops between
            % bands, so the layer is replaced on part of the dataset: ``result``
            % says how far it got, and the caller must report it.
            %
            % Memory: one band, ``BandBytes`` (default 256 MB) at 8 bytes per pixel
            % of the level width.
            %
            % Input Arguments:
            %   - **BatchOpt** - the tool's BatchOpt with ``id`` and ``BigData_PyramidLevel``
            %   - **blockFunction** - ``out = f(block)``, ``block`` as in
            %     ``io.savers.FilteredSliceProvider``; ``out`` is ``[rows width]``,
            %     non-zero = set, of any numeric or logical class
            %   - **layer** - [char] ``'mask'`` or ``'selection'``
            %   - **options.HaloYX**, **options.HaloZ** - halo rows / slices, default 0
            %   - **options.ColChannel** - channels to read, default ``[]`` (all)
            %   - **options.BandBytes** - memory budget of a band, default 256e6
            %   - **options.Slices** - level slices to write, default ``[]`` (all);
            %     ``levelSlices`` gives the shown slice for a 2D tool. The layer of
            %     the other slices is not touched
            %   - **options.Confirmed** - [logical] the tool already asked
            %     ``confirmRun`` (before a statistics pass), default false
            %
            % Output Arguments:
            %   - **result** - struct: ``level`` [double, 1-based], ``completed``
            %     [logical], ``slicesDone`` [double] number of level slices fully
            %     written, ``slicesTotal``; ``[]`` when cancelled at the confirmation
            arguments
                obj
                BatchOpt (1,1) struct
                blockFunction (1,1) function_handle
                layer {mustBeMember(layer, {'mask', 'selection'})}
                options.HaloYX (1,1) double = 0
                options.HaloZ (1,1) double = 0
                options.ColChannel = []
                options.BandBytes (1,1) double = 256e6
                options.Slices double {mustBeInteger, mustBePositive} = []
                options.Confirmed (1,1) logical = false
            end
            result = [];
            level = obj.checkModelOutput(BatchOpt, layer);
            dataset = obj.mibModel.I{BatchOpt.id};
            pyramid = dataset.image.pyramid;
            levelSize = pyramid.levelImageSizes(level, :);    % [Y X Z]
            slices = options.Slices(:)';
            if isempty(slices); slices = 1:levelSize(3); end
            if any(slices > levelSize(3))
                error('controllers:BigDataOptions:wrongSlice', 'Slice %d requested, level s%d has %d slices.', ...
                    max(slices), level - 1, levelSize(3));
            end
            scale = pyramid.levelScaleFactors(level, :);
            [region, regionMask] = obj.regionOfInterest(BatchOpt, level);

            parentFigure = obj.guiFigure();
            if ~options.Confirmed && ~obj.confirmRun(BatchOpt, blockFunction, Layer = layer, Slices = slices, ...
                    HaloYX = options.HaloYX, HaloZ = options.HaloZ, ColChannel = options.ColChannel, ...
                    BandBytes = options.BandBytes)
                return;
            end
            [pool, releaseWorkers, cancelled] = obj.startPool(BatchOpt, parentFigure); %#ok<ASGLU> kept until the run returns
            if cancelled; return; end

            provider = io.savers.FilteredSliceProvider(dataset.image, level, options.ColChannel, blockFunction, ...
                HaloYX = options.HaloYX, HaloZ = options.HaloZ, Region = region);
            if isempty(region); region = [1 levelSize(1) 1 levelSize(2)]; end
            regionSize = provider.SliceSize;    % [rows columns] of the region
            fullSize = [dataset.image.height, dataset.image.width, dataset.image.depth];
            bandHeight = max(1, min(regionSize(1), floor(options.BandBytes / (8 * regionSize(2)))));
            bandStarts = 1:bandHeight:regionSize(1);
            result = struct('level', level, 'completed', false, 'slicesDone', 0, 'slicesTotal', numel(slices));

            progressDialog = [];
            if ~isempty(parentFigure)
                progressDialog = uiprogressdlg(parentFigure, 'Title', sprintf('Writing the %s', layer), ...
                    'Message', sprintf('Level s%d, %d slices', level - 1, numel(slices)), 'Cancelable', 'on');
                cleanupDialog = onCleanup(@() delete(progressDialog));
            end
            labels = dataset.labels;
            % a cancelled run leaves a partly written mask, which must still show
            if strcmp(layer, 'mask'); dataset.maskExist = true; end
            % one task per band, slice by slice: [z firstRow lastRow]
            [bandIndices, sliceIndices] = ndgrid(1:numel(bandStarts), 1:numel(slices));
            firstRows = bandStarts(bandIndices(:)');
            tasks = [slices(sliceIndices(:)'); firstRows; min(firstRows + bandHeight - 1, regionSize(1))]';
            [cancelled, written] = obj.processBands(provider, tasks, pool, progressDialog, @localWriteBand);
            % the slices of which every band is written; with a pool they finish in any order
            result.slicesDone = nnz(all(reshape(written, numel(bandStarts), numel(slices)), 1));
            result.completed = ~cancelled;

            function localWriteBand(taskIndex, rows)
                % the band into the layer at the level; nested, it writes with the run's labels and region
                z = tasks(taskIndex, 1);
                band = uint8(rows ~= 0);
                levelRows = region(1) - 1 + tasks(taskIndex, 2:3);
                % full-resolution coordinates of the level slice and rows, see getData
                writeOptions = struct('pyramidLevel', level, ...
                    'x', [(region(3) - 1) * scale(2) + 1, min(region(4) * scale(2), fullSize(2))], ...
                    'y', [(levelRows(1) - 1) * scale(1) + 1, min(levelRows(2) * scale(1), fullSize(1))], ...
                    'z', [(z - 1) * scale(3) + 1, min(z * scale(3), fullSize(3))]);
                if ~isempty(regionMask)
                    % outside a non-rectangular ROI the layer stays
                    current = reshape(labels.getData63(layer, 3, [], writeOptions), size(band));
                    outside = ~regionMask(tasks(taskIndex, 2):tasks(taskIndex, 3), :);
                    band(outside) = current(outside);
                end
                labels.setData63(band, layer, 3, [], writeOptions);
            end
        end

        function confirmed = confirmRun(obj, BatchOpt, blockFunction, options)
            % CONFIRMRUN - Ask in the tool's window before a run over the BigData dataset, with a rough estimate of its time.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       confirmed = obj.confirmRun(BatchOpt, blockFunction)
            %       confirmed = obj.confirmRun(BatchOpt, blockFunction, HaloYX = 6, Layer = 'mask', Slices = 3, ...
            %           Note = 'A statistics pass comes first; it is not in the estimate.')
            %
            % ``run``, ``runOverwrite`` and ``runToModel`` call it, so a run never
            % starts from a single click. A tool that reads the dataset before
            % the run (a statistics pass) calls it before that pass with a
            % stand-in ``blockFunction`` of a similar cost, then passes
            % ``Confirmed = true`` to the run. Without a window (batch mode,
            % headless) it returns true and reads nothing.
            %
            % The dialog names what is replaced or written (a new store, the
            % image store itself, the mask or selection of ``Slices``) and the
            % size of the level, or of the ROI box with Restrict to ROI
            % (``regionOfInterest``; the estimate is then scaled by the box
            % area). The estimate (``estimateRunSeconds``) times
            % ``blockFunction`` twice on a small part of the middle slice, so it
            % costs a fraction of a second for most filters; it is rough (read
            % speed varies; writing is taken as long as reading) and left out
            % when the probe fails. Cancel in the "Estimating" dialog counts as
            % Cancel of the run (checked after the probe, which cannot stop midway).
            % With ``BatchOpt.UseParallelComputing`` the dialog says whether the
            % open pool is used or a pool of ``cpuParallelLimit`` workers starts
            % first; the computing part of the estimate is divided by the number
            % of workers, and 15 s are added for a pool that is not open yet.
            %
            % Input Arguments:
            %   - **BatchOpt** - the tool's BatchOpt with ``id`` and the BigData_* fields
            %   - **blockFunction** - the band function of the run, see ``run``
            %   - **options.HaloYX**, **options.HaloZ**, **options.ColChannel**,
            %     **options.BandBytes** - as for ``run`` (``BandBytes`` ``[]``: the property)
            %   - **options.Layer** - [char] ``'mask'`` / ``'selection'`` for
            %     ``runToModel``, ``''`` (default) for an image result
            %   - **options.Slices** - level slices processed, ``[]`` (default) all;
            %     for an image result the shown slice of a ``'2D, Slice'`` overwrite
            %     (``overwriteSlices``) when not given
            %   - **options.Note** - [char] a line added to the message
            %
            % Return values:
            %   - **confirmed** - [logical] true to go on
            arguments
                obj
                BatchOpt (1,1) struct
                blockFunction (1,1) function_handle
                options.HaloYX (1,1) double = 0
                options.HaloZ (1,1) double = 0
                options.ColChannel = []
                options.BandBytes double = []
                options.Layer char = ''
                options.Slices double = []
                options.Note char = ''
            end
            confirmed = true;
            parentFigure = obj.guiFigure();
            if isempty(parentFigure); return; end
            if isempty(options.BandBytes); options.BandBytes = obj.BandBytes; end

            dataset = obj.mibModel.I{BatchOpt.id};
            pyramid = dataset.image.pyramid;
            level = obj.resolveLevel(BatchOpt);
            levelSize = pyramid.levelImageSizes(level, :);    % [Y X Z]
            scale = pyramid.levelScaleFactors(level, :);
            slices = options.Slices(:)';
            if isempty(slices) && isempty(options.Layer); slices = obj.overwriteSlices(BatchOpt); end
            if isempty(slices); slices = 1:levelSize(3); end
            channels = options.ColChannel;
            if isempty(channels); channels = 1:dataset.image.colors; end
            % with Restrict to ROI the box of the ROI is read
            region = obj.regionOfInterest(BatchOpt, level);
            areaSize = levelSize(1:2);
            roiText = '';
            if ~isempty(region)
                areaSize = [region(2) - region(1), region(4) - region(3)] + 1;
                roiText = ' inside the ROI';
            end
            if numel(slices) == levelSize(3)
                extent = 'the whole dataset';
            elseif isscalar(slices) && scale(3) == 1
                extent = sprintf('slice %d', slices);
            elseif isscalar(slices)
                extent = sprintf('slices %d-%d', (slices - 1) * scale(3) + 1, min(slices * scale(3), dataset.image.depth));
            else
                extent = sprintf('%d slices of level s%d', numel(slices), level - 1);
            end
            overwriteExtent = 'The image of this dataset';
            if numel(slices) ~= levelSize(3)
                overwriteExtent = sprintf('%s of the image of this dataset', [upper(extent(1)) extent(2:end)]);
            end
            extent = [extent roiText];
            bytes = prod(areaSize) * numel(slices) * numel(channels) * ...
                numel(typecast(zeros(1, 1, dataset.image.dataClass), 'uint8'));
            byteUnits = {'bytes', 'KB', 'MB', 'GB', 'TB'};
            unitIndex = min(numel(byteUnits), max(1, floor(log(max(bytes, 1)) / log(1024)) + 1));
            sizeText = sprintf('Level s%d: %d x %d px, %d slice(s), %d channel(s)\n%.3g %s to read', level - 1, ...
                areaSize(2), areaSize(1), numel(slices), numel(channels), bytes / 1024^(unitIndex - 1), byteUnits{unitIndex});

            if ~isempty(options.Layer)
                message = sprintf('The %s of %s is replaced with the result, computed at level s%d.\nThis cannot be undone.', ...
                    options.Layer, extent, level - 1);
                title = sprintf('Replace the %s?', options.Layer);
                startText = 'Replace';
                icon = 'warning';
            elseif strcmp(BatchOpt.BigData_OpenIn{1}, obj.CurrentOverwrite)
                message = sprintf('%s%s is replaced with the result, on disk:\n%s\nThis cannot be undone.', ...
                    overwriteExtent, roiText, char(dataset.image.filename));
                title = 'Overwrite the image?';
                startText = 'Overwrite';
                icon = 'warning';
            elseif isfield(BatchOpt, 'BigData_Result') && strcmp(BatchOpt.BigData_Result{1}, obj.StandardResult)
                if strcmp(BatchOpt.BigData_OpenIn{1}, 'Current')
                    message = sprintf(['%s is processed into memory; the result replaces this BigData dataset ' ...
                        'in its buffer and its model is closed.\nThe files on disk are kept.'], [upper(extent(1)) extent(2:end)]);
                    title = 'Replace the dataset?';
                    startText = 'Replace';
                    icon = 'warning';
                else
                    message = sprintf('%s is processed into memory and opened in %s as a Standard dataset.', ...
                        [upper(extent(1)) extent(2:end)], lower(BatchOpt.BigData_OpenIn{1}));
                    title = 'Process the dataset?';
                    startText = 'Start';
                    icon = 'question';
                end
            else
                message = sprintf('%s is processed into a new store:\n%s', [upper(extent(1)) extent(2:end)], ...
                    char(BatchOpt.BigData_OutputPath));
                title = 'Process the dataset?';
                startText = 'Start';
                icon = 'question';
            end
            message = sprintf('%s\n\n%s', message, sizeText);

            % with Use parallel computing the workers of the pool share the computing (startPool)
            options.Workers = 1;
            poolSeconds = 0;
            if isfield(BatchOpt, 'UseParallelComputing') && BatchOpt.UseParallelComputing
                pool = gcp('nocreate');
                if isempty(pool)
                    options.Workers = obj.mibModel.preferences.System.cpuParallelLimit;
                    poolSeconds = 15;       % 4 process workers started in 15 s (2026-11-07)
                    message = sprintf('%s\nIn parallel: a pool of %d workers is started first', message, options.Workers);
                else
                    options.Workers = pool.NumWorkers;
                    message = sprintf('%s\nIn parallel, on the %d workers of the open pool', message, options.Workers);
                end
            end

            progressDialog = uiprogressdlg(parentFigure, 'Title', title, 'Message', 'Estimating the time...', ...
                'Indeterminate', 'on', 'Cancelable', 'on');
            seconds = obj.estimateRunSeconds(dataset.image, level, blockFunction, slices, channels, options);
            % the ROI box: the time of the whole slice in proportion to its area, rough as the estimate
            seconds = seconds * prod(areaSize) / prod(levelSize(1:2)) + poolSeconds;
            cancelled = progressDialog.CancelRequested;
            delete(progressDialog);
            if cancelled        % Cancel during the probe: the run does not start
                confirmed = false;
                return;
            end
            if ~isnan(seconds)
                if seconds < 60
                    timeText = 'under a minute';
                elseif seconds < 600
                    timeText = sprintf('about %d min', round(seconds / 60));
                elseif seconds < 3600
                    timeText = sprintf('about %d min', 5 * round(seconds / 300));
                elseif seconds < 48 * 3600
                    timeText = sprintf('about %.2g h', seconds / 3600);
                else
                    timeText = sprintf('about %.2g days', seconds / 86400);
                end
                message = sprintf('%s\nEstimated time: %s\n(rough, from a test on a part of slice %d)', ...
                    message, timeText, slices(ceil(end / 2)));
            end
            if ~isempty(options.Note); message = sprintf('%s\n%s', message, options.Note); end

            answer = uiconfirm(parentFigure, message, title, 'Options', {startText, 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2, 'Icon', icon);
            confirmed = strcmp(answer, startText);
        end

        function level = resolveLevel(obj, BatchOpt)
            % RESOLVELEVEL - 1-based pyramid level of ``BatchOpt.BigData_PyramidLevel`` for the BigData dataset ``BatchOpt.id``.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       level = obj.resolveLevel(BatchOpt)
            %
            % Errors with ``controllers:BigDataOptions:notBigData`` when the
            % dataset is not BigData and ``controllers:BigDataOptions:wrongLevel``
            % when the item is not one of its levels (a protocol recorded on a
            % dataset with more levels). A tool that reads the image before
            % ``run`` / ``runToModel`` (a statistics pass) calls it first, so a
            % wrong level fails before the reading.
            dataset = obj.mibModel.I{BatchOpt.id};
            if ~strcmp(dataset.datasetType, 'BigData')
                error('controllers:BigDataOptions:notBigData', 'Dataset %d is not a BigData dataset.', BatchOpt.id);
            end
            levelCount = size(dataset.image.pyramid.levelImageSizes, 1);
            level = controllers.BigDataOptions.levelFromItem(BatchOpt.BigData_PyramidLevel{1});
            if isempty(level) || level > levelCount
                error('controllers:BigDataOptions:wrongLevel', ...
                    'Unknown pyramid level "%s" (BigData_PyramidLevel); use s0..s%d.', ...
                    BatchOpt.BigData_PyramidLevel{1}, levelCount - 1);
            end
        end

        function slices = levelSlices(obj, BatchOpt, level, scope)
            % LEVELSLICES - Level slices a tool processes for its dataset scope: the shown slice for ``'2D, Slice'``, ``[]`` (all) otherwise.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       slices = obj.levelSlices(BatchOpt, level, BatchOpt.DatasetType{1})
            %
            % For ``'2D, Slice'`` the shown slice of the dataset ``BatchOpt.id``
            % (``getCurrentSliceNumber``, full resolution) is mapped to the level
            % slice that holds it, ``ceil(z / scale)``; a level downsampled in Z
            % holds several full-resolution slices in one. ``'3D, Stack'`` and
            % ``'4D, Dataset'`` give ``[]``, all slices (a BigData dataset has one
            % time point). Pass the result as ``Slices`` to ``runToModel`` and to
            % the statistics pass.
            %
            % Errors with ``controllers:BigDataOptions:orientation`` for
            % ``'2D, Slice'`` when the dataset is not shown in XY: the bands are
            % rows of XY slices, so the shown ZX / ZY plane cannot be processed
            % alone.
            %
            % Input Arguments:
            %   - **BatchOpt** - the tool's BatchOpt with ``id``
            %   - **level** - [double] 1-based level, from ``resolveLevel`` / ``checkModelOutput``
            %   - **scope** - [char] ``'2D, Slice'``, ``'3D, Stack'`` or ``'4D, Dataset'``
            slices = [];
            if ~strcmp(scope, '2D, Slice'); return; end
            dataset = obj.mibModel.I{BatchOpt.id};
            if dataset.orientation ~= 3
                error('controllers:BigDataOptions:orientation', ['"2D, Slice" on a BigData dataset processes ' ...
                    'the shown XY slice; switch the view to XY, or use "3D, Stack".']);
            end
            scale = dataset.image.pyramid.levelScaleFactors(level, :);
            slices = ceil(dataset.getCurrentSliceNumber() / scale(3));
        end

        function level = checkModelOutput(obj, BatchOpt, layer)
            % CHECKMODELOUTPUT - Check that ``runToModel`` can write ``layer`` of the BigData dataset ``BatchOpt.id``; return the level.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       level = obj.checkModelOutput(BatchOpt, layer)
            %
            % The checks of ``runToModel``, which calls it: the level
            % (``resolveLevel``), a model that exists (``noModel``), is not
            % read-only (``readOnlyModel``, a Zarr v2 overlay or an instance
            % index), and has a level of the size of the image level
            % (``modelLevelMismatch``, a label overlay with its own pyramid).
            % Mask and selection writes are allowed on locked labels (see
            % ``core.MibBigDataLabels.setData63``), so the lock is not checked.
            % A tool with a statistics pass calls it first, so a refusal comes
            % before the reading.
            %
            % Input Arguments:
            %   - **BatchOpt** - the tool's BatchOpt with ``id`` and ``BigData_PyramidLevel``
            %   - **layer** - [char] ``'mask'`` or ``'selection'``, for the messages
            %
            % Output Arguments:
            %   - **level** - [double] 1-based pyramid level
            level = obj.resolveLevel(BatchOpt);
            dataset = obj.mibModel.I{BatchOpt.id};
            if ~dataset.modelExist || ~isa(dataset.labels, 'core.MibBigDataLabels') || ~dataset.labels.exists
                error('controllers:BigDataOptions:noModel', ...
                    ['The result goes to the %s of the model, but dataset %d has no model.\n' ...
                     'Create one first (Segmentation panel -> Create).'], layer, BatchOpt.id);
            end
            if strcmp(dataset.getLockedState('labels'), 'readOnly')
                error('controllers:BigDataOptions:readOnlyModel', ...
                    'The model of dataset %d is read-only, so its %s cannot be written.', BatchOpt.id, layer);
            end
            levelSize = dataset.image.pyramid.levelImageSizes(level, :);    % [Y X Z]
            if level > size(dataset.labels.modelLevelSizes, 1) || ~isequal(dataset.labels.modelLevelSizes(level, :), levelSize)
                error('controllers:BigDataOptions:modelLevelMismatch', ...
                    ['Level s%d of the model does not have the size of the image level (%d x %d x %d); ' ...
                     'the model has its own pyramid. Choose a level they share.'], level - 1, levelSize(2), levelSize(1), levelSize(3));
            end
        end

        function reportStoreResult(obj, result, logText)
            % REPORTSTORERESULT - Tell where the result of ``run`` went: log it in the buffer it opened in, or say where it was written.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.reportStoreResult(result, logText)
            %
            % When the store was opened in a buffer, ``logText`` is added to the
            % action log of its image and the image is redrawn; otherwise the GUI
            % shows the path in a dialog. ``logText`` is printed in both cases.
            %
            % Input Arguments:
            %   - **result** - non-empty output of ``run``
            %   - **logText** - [char] one line describing the processing
            if result.bufferId > 0
                obj.mibModel.I{result.bufferId}.image.updateActionLog(logText);
                notify(obj.mibModel, 'ShowImage');
            else
                parentFigure = obj.guiFigure();
                if ~isempty(parentFigure)
                    uialert(parentFigure, sprintf('The result was written to\n%s', result.outputPath), 'Done', 'Icon', 'success');
                end
            end
            fprintf('%s\n', logText);
        end

        function completed = reportModelResult(obj, result, layer)
            % REPORTMODELRESULT - Show the layer written by ``runToModel`` and report a cancel or a coarse level.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       completed = obj.reportModelResult(result, layer)
            %
            % Turns the mask display on for a mask and redraws. A run cancelled
            % during the write replaced the layer on part of the dataset only,
            % and there is no undo: that is said in a dialog (GUI) and printed,
            % and ``StopProtocol`` is sent. After a run at a level coarser than
            % s0 the GUI explains that the finer levels are filled by upsampling,
            % when zoomed in or with Save model -> Finalize & save; they are not
            % filled automatically (``materializeAll`` of a whole slide can take
            % long).
            %
            % Input Arguments:
            %   - **result** - non-empty output of ``runToModel``
            %   - **layer** - [char] ``'mask'`` or ``'selection'``
            %
            % Output Arguments:
            %   - **completed** - [logical] false when the run was cancelled during the write
            parentFigure = obj.guiFigure();
            levelItem = sprintf('s%d', result.level - 1);
            if strcmp(layer, 'mask')
                obj.mibModel.showMask = true;
                notify(obj.mibModel, 'UpdateGuiWidgets', core.ToggleEventData({'checkboxes'}));   % the Show mask checkbox
            end
            notify(obj.mibModel, 'ShowImage');
            completed = result.completed;
            if ~completed
                message = sprintf(['Cancelled. The %s was replaced on %d of %d slices (level %s); ' ...
                    'on the other slices it is as before.'], layer, result.slicesDone, result.slicesTotal, levelItem);
                if ~isempty(parentFigure); uialert(parentFigure, message, 'Cancelled', 'Icon', 'warning'); end
                fprintf('%s\n', message);
                notify(obj.mibModel, 'StopProtocol');
                return;
            end
            if result.level > 1 && ~isempty(parentFigure)
                finerLevels = sprintf('s0-s%d', result.level - 2);
                if result.level == 2; finerLevels = 's0'; end
                uialert(parentFigure, sprintf(['The %s was computed at level %s and written at this and the coarser levels.\n\n' ...
                    'The finer levels (%s) are filled from it, by upsampling:\n' ...
                    '- for the area you view, when you zoom in;\n' ...
                    '- for the whole dataset, with Model ribbon -> Save model -> Finalize & save. Do this before ' ...
                    'exporting the model or opening it in another program.\n\n' ...
                    'The result is only as precise as level %s. For an exact full-resolution result run it ' ...
                    'at s0.'], layer, levelItem, finerLevels, levelItem), ...
                    'Computed at a coarser level', 'Icon', 'info');
            end
        end
    end

    methods (Static)
        function refused = checkWholeDatasetType(mibModel, parentFigure, errorId, BatchOpt, title)
            % CHECKWHOLEDATASETTYPE - Refuse "2D, Slice" for a result into a new store, which always holds the whole dataset.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       if controllers.BigDataOptions.checkWholeDatasetType(mibModel, parentFigure, errorId, BatchOpt, title); return; end
            %
            % The window offers it only with ``'Current overwrite (BigData)'``
            % (``updateDatasetType``), which writes the shown slice into the
            % store; this catches a batch run or a protocol, where
            % ``'2D, Slice'`` is the default of ``DatasetType`` and was silently
            % processed as the whole dataset. With ``'Current overwrite (BigData)'`` it
            % refuses a view other than XY instead (see ``levelSlices``), so a
            % tool stops before any statistics pass. The refusal goes through
            % ``reportError``: a dialog with a window, an error ``errorId``
            % without one.
            %
            % Input Arguments:
            %   - **mibModel** - models.MibModel
            %   - **parentFigure** - figure for the dialog, ``[]`` when headless
            %   - **errorId** - [char] identifier of the raised error
            %   - **BatchOpt** - the tool's BatchOpt; without ``DatasetType`` nothing is refused
            %   - **title** - [char] title of the dialog
            %
            % Return values:
            %   - **refused** - [logical] true when the run must stop
            refused = isfield(BatchOpt, 'DatasetType') && strcmp(BatchOpt.DatasetType{1}, '2D, Slice');
            if ~refused; return; end
            if ~strcmp(BatchOpt.BigData_OpenIn{1}, controllers.BigDataOptions.CurrentOverwrite)
                controllers.BigDataOptions.reportError(mibModel, parentFigure, errorId, ...
                    ['"2D, Slice" is available only with "Current overwrite (BigData)"; a new store holds the whole ' ...
                    'dataset: select "3D, Stack" or "4D, Dataset".'], title);
            elseif mibModel.I{BatchOpt.id}.orientation ~= 3
                controllers.BigDataOptions.reportError(mibModel, parentFigure, errorId, ...
                    ['"2D, Slice" on a BigData dataset processes the shown XY slice; switch the view to XY, ' ...
                    'or use "3D, Stack".'], title);
            else
                refused = false;
            end
        end

        function reportError(mibModel, parentFigure, errorId, message, title)
            % REPORTERROR - Show an error of a BigData run in a dialog, or raise it when there is no window.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       controllers.BigDataOptions.reportError(mibModel, parentFigure, errorId, message, title)
            %
            % With a window (the tool, or the MIB window in a batch run of a
            % running MIB) the message is shown and ``StopProtocol`` is sent;
            % without one (headless) it is raised with ``errorId``, so a refused
            % or failed run never returns as if it had worked.
            %
            % Input Arguments:
            %   - **mibModel** - models.MibModel
            %   - **parentFigure** - figure for the dialog, ``[]`` when headless
            %   - **errorId** - [char] identifier of the raised error
            %   - **message** - [char] text
            %   - **title** - [char] title of the dialog
            if isempty(parentFigure)
                error(errorId, '%s', message);
            end
            utils.dlgs.showErrorDialog(parentFigure, message, title);
            notify(mibModel, 'StopProtocol');
        end

        function openStoreInBuffer(mibModel, storePath, targetId)
            % OPENSTOREINBUFFER - Open an OME-Zarr store as the BigData dataset of buffer ``targetId``.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       controllers.BigDataOptions.openStoreInBuffer(mibModel, storePath, targetId)
            %
            % Replaces whatever the buffer held (the files on disk are not
            % touched). The same steps as the buffer swap of
            % ``Alignment.applyAlignmentBigData``, the viewing state reset in
            % ``showNewDataset``.
            %
            % Input Arguments:
            %   - **mibModel** - models.MibModel
            %   - **storePath** - [char] path of the store
            %   - **targetId** - [double] index of the buffer in ``mibModel.I``
            loaderOptions = struct('datasetMode', 'BigData');
            loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
            [imageInfo, files] = loader.loadMetadata({storePath}, loaderOptions);
            [image, imageInfo] = loader.loadImages(files, imageInfo, loaderOptions);
            mibModel.I{targetId}.initialize(image, imageInfo, 'BigData');
            controllers.BigDataOptions.showNewDataset(mibModel, targetId);
        end
    end

    methods (Access = private)
        function parentFigure = guiFigure(obj)
            % GUIFIGURE - The tool window, or [] in batch/headless mode.
            parentFigure = [];
            if ~isempty(obj.controller.view) && isvalid(obj.controller.view.gui)
                parentFigure = obj.controller.view.gui;
            end
        end

        function [pool, releaseWorkers, cancelled] = startPool(obj, BatchOpt, parentFigure)
            % STARTPOOL - The process pool of a run with ``BatchOpt.UseParallelComputing``; ``[]`` without it.
            %
            % The open pool is used as it is; when none is open, one of
            % ``preferences.System.cpuParallelLimit`` workers is started (about
            % 15 s for 4 workers), as the Standard filters do. A thread pool is
            % refused (``controllers:BigDataOptions:threadPool``): zarrMex and
            % the loaders need process workers. On every worker zarrMex is
            % pinned (``io.zarr.pinNativeLibrary``, as ``mib3.m`` does on the
            % client), otherwise a worker may crash when the pool closes.
            %
            % Output Arguments:
            %   - **pool** - ``parallel.Pool`` or ``[]`` (run on the client)
            %   - **releaseWorkers** - ``onCleanup`` that clears the chunk cache
            %     of every worker; keep it until the run returns. The cache holds
            %     chunks of the source (up to 512 MB per worker), and an overwrite
            %     changes them without changing their cache keys, so a later run on
            %     the workers would read the old pixels
            %   - **cancelled** - [logical] Cancel while the pool was starting
            pool = [];
            releaseWorkers = [];
            cancelled = false;
            if ~isfield(BatchOpt, 'UseParallelComputing') || ~BatchOpt.UseParallelComputing; return; end
            pool = gcp('nocreate');
            if isempty(pool)
                progressDialog = [];
                if ~isempty(parentFigure)
                    % parpool cannot stop midway; Cancel is checked once it returns
                    progressDialog = uiprogressdlg(parentFigure, 'Title', 'Parallel processing', ...
                        'Message', sprintf('Starting a parallel pool of %d workers...', ...
                        obj.mibModel.preferences.System.cpuParallelLimit), 'Indeterminate', 'on', 'Cancelable', 'on');
                    cleanupDialog = onCleanup(@() delete(progressDialog));
                end
                pool = parpool(obj.mibModel.preferences.System.cpuParallelLimit);
                if ~isempty(progressDialog) && progressDialog.CancelRequested
                    cancelled = true;
                    return;
                end
            end
            if isa(pool, 'parallel.ThreadPool')
                error('controllers:BigDataOptions:threadPool', ['The open parallel pool runs on threads; BigData ' ...
                    'processing needs a pool of processes.\nStop the pool (Home ribbon, Preferences, Parallel pool) and start again, or ' ...
                    'clear Use parallel computing.']);
            end
            wait(parfevalOnAll(pool, @io.zarr.pinNativeLibrary, 0));
            releaseWorkers = onCleanup(@() parfevalOnAll(pool, @io.zarr.ChunkCache.clear, 0));
        end

        function [cancelled, written] = processBands(~, provider, tasks, pool, progressDialog, consume)
            % PROCESSBANDS - Compute bands of a provider, on the workers of ``pool`` or on the client, and pass each to ``consume``.
            %
            % The loop of ``runToModel``, ``runToStandard`` and ``overwriteRegion``:
            % the result of ``provider.getSliceRows(z, firstRow, lastRow)`` for
            % every row of ``tasks`` goes to ``consume(taskIndex, rows)``, which
            % runs on the client and writes it (the layer of the model, the
            % array in memory, the temporary array). With a pool the provider
            % is sent to the workers once (``parallel.pool.Constant``; it opens
            % the store again there, see ``io.savers.FilteredSliceProvider``),
            % the bands are computed there and come back in the order they
            % finish, so ``consume`` must not depend on the order. At most
            % twice as many bands as workers are in flight, so the client holds
            % a few bands, not the whole result. Without a pool the bands run
            % one after the other in the order of ``tasks``.
            %
            % Cancel (``progressDialog.CancelRequested``) is checked before every
            % band, and every half second while waiting for the workers; the
            % bands in flight are then cancelled. An error of a band is raised
            % as the error of the worker, with its identifier.
            %
            % Input Arguments:
            %   - **provider** - ``io.savers.FilteredSliceProvider``
            %   - **tasks** - [n x 3] double, ``[z firstRow lastRow]`` per band
            %   - **pool** - ``parallel.Pool`` or ``[]``
            %   - **progressDialog** - ``uiprogressdlg`` or ``[]``; its value goes from 0 to 1
            %   - **consume** - function handle ``consume(taskIndex, rows)``
            %
            % Output Arguments:
            %   - **cancelled** - [logical] the user cancelled; not every band was consumed
            %   - **written** - [1 x n] logical, the bands passed to ``consume``
            cancelled = false;
            numberOfTasks = size(tasks, 1);
            written = false(1, numberOfTasks);
            if isempty(pool)
                for taskIndex = 1:numberOfTasks
                    if ~isempty(progressDialog) && progressDialog.CancelRequested; cancelled = true; return; end
                    consume(taskIndex, provider.getSliceRows(tasks(taskIndex, 1), tasks(taskIndex, 2), tasks(taskIndex, 3)));
                    written(taskIndex) = true;
                    if ~isempty(progressDialog); progressDialog.Value = taskIndex / numberOfTasks; end
                end
                return;
            end

            providerConstant = parallel.pool.Constant(provider);
            inFlight = 2 * pool.NumWorkers;
            futures = parallel.FevalFuture.empty;
            submitted = 0;
            consumed = 0;
            try
                while consumed < numberOfTasks
                    while submitted < numberOfTasks && submitted - consumed < inFlight
                        submitted = submitted + 1;
                        futures(submitted) = parfeval(pool, @controllers.BigDataOptions.workerBandRows, 1, ...
                            providerConstant, tasks(submitted, 1), tasks(submitted, 2), tasks(submitted, 3));
                    end
                    if ~isempty(progressDialog) && progressDialog.CancelRequested
                        cancelled = true;
                        cancel(futures);    % the bands in flight stop
                        return;
                    end
                    [taskIndex, rows] = fetchNext(futures, 0.5);
                    if isempty(taskIndex); continue; end    % none finished within the timeout
                    consume(taskIndex, rows);
                    written(taskIndex) = true;
                    consumed = consumed + 1;
                    if ~isempty(progressDialog); progressDialog.Value = consumed / numberOfTasks; end
                end
            catch bandError
                cancel(futures);
                % a failed band: the error of the worker, not the wrapper of fetchNext
                if strcmp(bandError.identifier, 'MATLAB:parallel:future:FetchNextFutureErrored') && ~isempty(bandError.cause)
                    remoteError = bandError.cause{1};    % a ParallelException, which rethrow refuses
                    throw(MException(remoteError.identifier, '%s', remoteError.message));
                end
                rethrow(bandError);
            end
        end

        function seconds = estimateRunSeconds(~, image, level, blockFunction, slices, channels, options)
            % ESTIMATERUNSECONDS - Rough time of a run, from two short probes of ``blockFunction`` on the middle slice; NaN when a probe fails.
            %
            % A probe reads one chunk row (at least 32 rows) of the middle slice
            % of ``slices`` with the halo (``HaloYX``, ``HaloZ``), only as many
            % whole chunk columns as keep it near 2 Mpx, and calls
            % ``blockFunction`` on it as the provider does
            % (``io.savers.FilteredSliceProvider``: ``[rows width colors]`` for
            % 2D, ``(block, z, firstRow)`` as the function takes). Reading and
            % computing are timed apart, because they scale differently: the
            % store is read in whole chunks, so the reading time is per chunk
            % pixel touched (a halo of 3 rows reads two more chunk rows, which
            % a run of tall bands reads once per band), the computing time per
            % pixel of the block. The second probe, clear of the first one's
            % halo (whose chunks the cache holds), gives both rates; what the
            % first spent more on computing is counted once per slice (a guide or
            % other per-slice set-up the band function caches). The run reads
            % each slice in bands of ``BandBytes / (8 * width * channels)`` rows,
            % each with its halo, and writes as much as it reads::
            %
            %   seconds = 1.1 * slices * (once + bands * (2 * chunkPixelsRead * readRate + bandPixels * computeRate / workers))
            %
            % ``workers`` is ``options.Workers`` (default 1), the workers of the
            % pool of a parallel run (``confirmRun``). Only the computing is
            % divided by it: reading and writing share one disk, and the
            % per-slice set-up (``once``) is repeated by every worker that gets a
            % band of the slice. On a local SSD the computing was 90-99 % of a
            % run for NonLocalMeans, LocalContrast, FastLocalLaplacian and BMxD,
            % 16-48 % for Gaussian, Median and Bilateral (2026-11-07).
            %
            % On a 2048 x 2048 x 8 store (2026-11-07) this gave 0.5-0.8 of the
            % real time for the cheap filters (Average, Median, Gaussian; about
            % 0.4 s of each run is set-up) and 1.1 for NonLocalMeans. Rough by design:
            % chunks deeper than one slice, the chunk cache and the disk or
            % network speed of the moment are not modelled. The probe width
            % differs from the slice, which a block function depending on the
            % column count can refuse: then NaN, and the dialog shows no
            % estimate (the run itself reports such an error).
            seconds = NaN;
            pyramid = image.pyramid;
            levelSize = pyramid.levelImageSizes(level, :);    % [Y X Z]
            scale = pyramid.levelScaleFactors(level, :);
            [height, width] = deal(levelSize(1), levelSize(2));
            chunk = [64 64];
            if isfield(pyramid, 'chunkSizes') && numel(pyramid.chunkSizes) >= level && numel(pyramid.chunkSizes{level}) >= 2
                chunk = double(pyramid.chunkSizes{level}(1:2));
            end
            halo = options.HaloYX;
            probeRows = min(height, chunk(1) * ceil(32 / chunk(1)));
            readRows = min(height, probeRows + 2 * halo);
            columns = min(width, chunk(2) * max(1, floor(2e6 / readRows / chunk(2))));
            z = slices(ceil(end / 2));
            zFirst = max(1, z - options.HaloZ);
            zLast = min(levelSize(3), z + options.HaloZ);
            zRead = zLast - zFirst + 1;
            firstRows = chunk(1) * floor((floor(height / 2) - 1) / chunk(1)) + 1;
            % the second probe clear of the first one's halo, whose chunks the cache would hold
            firstRows = [firstRows, min(firstRows + probeRows + chunk(1) * ceil(2 * halo / chunk(1)), max(1, height - probeRows + 1))];
            readTime = zeros(1, 2);
            computeTime = zeros(1, 2);
            chunkPixels = zeros(1, 2);
            pixels = zeros(1, 2);
            try
                for probe = 1:2
                    readFirst = max(1, firstRows(probe) - halo);
                    readLast = min(height, firstRows(probe) + probeRows - 1 + halo);
                    readOptions = struct('pyramidLevel', level, ...
                        'y', [(readFirst - 1) * scale(1) + 1, readLast * scale(1)], ...
                        'x', [1, columns * scale(2)], ...
                        'z', [(zFirst - 1) * scale(3) + 1, zLast * scale(3)]);
                    timer = tic;
                    block = image.getData('image', 3, channels, readOptions);   % [y x z c]
                    readTime(probe) = toc(timer);
                    if options.HaloZ == 0
                        block = reshape(block, size(block, 1), size(block, 2), size(block, 4));
                    end
                    timer = tic;
                    switch nargin(blockFunction)
                        case 3
                            blockFunction(block, z, readFirst);
                        case 2
                            blockFunction(block, z);
                        otherwise
                            blockFunction(block);
                    end
                    computeTime(probe) = toc(timer);
                    chunkRows = floor((readLast - 1) / chunk(1)) - floor((readFirst - 1) / chunk(1)) + 1;
                    chunkPixels(probe) = chunkRows * chunk(1) * ceil(columns / chunk(2)) * chunk(2) * zRead;
                    pixels(probe) = (readLast - readFirst + 1) * columns * zRead;
                end
            catch
                return;
            end
            readRate = readTime(2) / chunkPixels(2);
            computeRate = computeTime(2) / pixels(2);
            bandRows = max(1, min(height, floor(options.BandBytes / (8 * width * numel(channels)))));
            bands = ceil(height / bandRows);
            bandReadRows = min(height, bandRows + 2 * halo);
            bandChunkPixels = min(ceil(height / chunk(1)), ceil(bandReadRows / chunk(1)) + 1) * chunk(1) * ...
                ceil(width / chunk(2)) * chunk(2) * zRead;
            workers = 1;
            if isfield(options, 'Workers'); workers = options.Workers; end
            perBand = 2 * bandChunkPixels * readRate + bandReadRows * width * zRead * computeRate / workers;   % writing as another read
            seconds = 1.1 * numel(slices) * (max(0, computeTime(1) - computeTime(2)) + bands * perBand);
        end

        function [description, bufferId, layer] = openStoreAtPath(obj, outputPath)
            % OPENSTOREATPATH - Describe the store open in MIB at ``outputPath``, '' when none.
            %
            % Also returns the buffer that holds it and ``'image'`` or
            % ``'labels'``; ``0`` and ``''`` when none.
            description = '';
            bufferId = 0;
            layer = '';
            for id = 1:numel(obj.mibModel.I)
                dataset = obj.mibModel.I{id};
                if ismember(dataset.datasetType, {'BigData', 'Virtual'}) && ...
                        utils.bigdata.isSameStorePath(dataset.image.filename, outputPath)
                    description = sprintf('image of buffer %d', id);
                    bufferId = id;
                    layer = 'image';
                    return;
                end
                if isa(dataset.labels, 'core.MibBigDataLabels') && ...
                        utils.bigdata.isSameStorePath(dataset.labels.modelStorePath, outputPath)
                    description = sprintf('model of buffer %d', id);
                    bufferId = id;
                    layer = 'labels';
                    return;
                end
            end
        end

        function result = runOverwrite(obj, BatchOpt, level, blockFunction, options, parentFigure)
            % RUNOVERWRITE - Process the dataset ``BatchOpt.id`` and replace its image store with the result.
            %
            % The "Current overwrite (BigData)" branch of ``run``; the checks, steps and
            % what is kept are described in the class help. The confirmation
            % (``confirmRun``) comes after the checks, unless ``options.Confirmed``.
            % A ``'2D, Slice'`` run on a dataset of more than one slice goes to
            % ``overwriteSlice`` after the same checks.
            % Returns ``struct(outputPath, bufferId)`` with the store path and
            % ``id``, ``[]`` when cancelled.
            result = [];
            id = BatchOpt.id;
            dataset = obj.mibModel.I{id};
            sourcePath = char(dataset.image.filename);
            if level ~= 1
                error('controllers:BigDataOptions:overwriteLevel', ...
                    ['"%s" needs level s0: the result replaces the image, so it must keep its size.\n' ...
                     'For a coarser level write a new store.'], obj.CurrentOverwrite);
            end
            if ~isfolder(sourcePath) || io.zarr.Group(sourcePath).zarrFormat() ~= 3
                error('controllers:BigDataOptions:overwriteNotStore', ...
                    ['"%s" rewrites an OME-Zarr v3 store, but the image of this dataset is read from\n  %s\n' ...
                     'Write the result to a new store instead.'], obj.CurrentOverwrite, sourcePath);
            end
            if dataset.image.lockedState
                if isempty(parentFigure)
                    error('controllers:BigDataOptions:imageLocked', ...
                        ['The image of dataset %d is locked, so "%s" cannot replace it.\n' ...
                         'Unlock the image first, or write the result to a new store.'], id, obj.CurrentOverwrite);
                end
                if ~obj.mibModel.showLockedNotice(id, 'image'); return; end
            end

            [sourceFolder, sourceStem, sourceExtension] = fileparts(sourcePath);
            temporaryPath = fullfile(sourceFolder, [sourceStem '.mib_overwrite' sourceExtension]);
            replacedPath = fullfile(sourceFolder, [sourceStem '.mib_replaced' sourceExtension]);
            if isfolder(replacedPath)
                % left by an overwrite that stopped between the two renames: it may hold the only source copy
                error('controllers:BigDataOptions:overwriteLeftover', ...
                    ['A previous overwrite of this store did not finish and left\n  %s\n' ...
                     'Check it and delete or restore it before overwriting again.'], replacedPath);
            end
            if isfolder(temporaryPath); rmdir(temporaryPath, 's'); end   % a partial result of an earlier run
            [region, regionMask] = obj.regionOfInterest(BatchOpt, 1);

            if ~options.Confirmed && ~obj.confirmRun(BatchOpt, blockFunction, HaloYX = options.HaloYX, ...
                    HaloZ = options.HaloZ, ColChannel = options.ColChannel, BandBytes = options.BandBytes)
                return;
            end
            [pool, releaseWorkers, cancelled] = obj.startPool(BatchOpt, parentFigure); %#ok<ASGLU> kept until the run returns
            if cancelled; return; end
            slices = obj.overwriteSlices(BatchOpt);
            depth = dataset.image.pyramid.levelImageSizes(1, 3);
            if (~isempty(slices) && depth > 1) || ~isempty(region)
                % a slice or a ROI box is written into the store; the whole image swaps the store
                if isempty(slices); slices = 1:depth; end
                if obj.overwriteRegion(BatchOpt, slices, region, regionMask, temporaryPath, blockFunction, options, parentFigure, pool)
                    result = struct('outputPath', sourcePath, 'bufferId', id);
                end
                return;
            end

            try
                writtenPath = utils.bigdata.processImageToStore(dataset.image, blockFunction, temporaryPath, ...
                    Level = 1, ColChannel = options.ColChannel, HaloYX = options.HaloYX, HaloZ = options.HaloZ, ...
                    Fingerprint = options.Fingerprint, ParentFigure = parentFigure, BandBytes = options.BandBytes, Pool = pool);
            catch processError
                if isfolder(temporaryPath); rmdir(temporaryPath, 's'); end
                rethrow(processError);
            end
            if isempty(writtenPath)
                if isfolder(temporaryPath); rmdir(temporaryPath, 's'); end
                return;
            end

            % the group attributes the saver does not write (omero, ...) stay with the store
            sourceAttributes = io.zarr.Group(sourcePath).getAttributes();
            resultGroup = io.zarr.Group(temporaryPath);
            resultAttributes = resultGroup.getAttributes();
            if isstruct(sourceAttributes) && isstruct(resultAttributes)
                missingNames = setdiff(fieldnames(sourceAttributes), fieldnames(resultAttributes));
                for nameIndex = 1:numel(missingNames)
                    resultAttributes.(missingNames{nameIndex}) = sourceAttributes.(missingNames{nameIndex});
                end
                if ~isempty(missingNames); resultGroup.setAttributes(resultAttributes); end
            end

            oldImage = dataset.image;
            oldImage.closeVirtualDataset();
            try
                movefile(sourcePath, replacedPath);
                try
                    movefile(temporaryPath, sourcePath);
                catch renameError
                    movefile(replacedPath, sourcePath);
                    rethrow(renameError);
                end
            catch swapError
                % the readers were closed: reopen the unchanged source before reporting
                obj.replaceImage(dataset, oldImage, sourcePath, id);
                if isfolder(temporaryPath); rmdir(temporaryPath, 's'); end
                rethrow(swapError);
            end
            rmdir(replacedPath, 's');
            io.zarr.ChunkCache.clear();
            obj.replaceImage(dataset, oldImage, sourcePath, id);
            result = struct('outputPath', sourcePath, 'bufferId', id);
        end

        function completed = overwriteRegion(obj, BatchOpt, slices, region, regionMask, temporaryPath, blockFunction, options, parentFigure, pool)
            % OVERWRITEREGION - Process a box of slices of the dataset ``BatchOpt.id`` and write it into its image store.
            %
            % The branch of ``runOverwrite`` for the shown slice of a ``'2D,
            % Slice'`` run and for Restrict to ROI, after its checks and
            % confirmation; the steps are in the class help ("Current overwrite
            % (BigData) of the shown slice"). ``region`` is the ROI box of
            % ``s0`` from ``regionOfInterest`` (``[]``: the whole slice) and
            % ``regionMask`` its shape (``[]``: the whole box; outside it the
            % image keeps its values, ``io.savers.FilteredSliceProvider``).
            %
            % Memory is about one band of ``options.BandBytes``; the bands
            % start on whole chunk (shard) rows of ``s0``, so no chunk is
            % written by two bands. The processed box is kept in a plain Zarr
            % array at ``temporaryPath`` between the steps: the source cannot be
            % written while the bands, with their halo, are still read from it.
            % Each coarser level is rebuilt over the rows the change reaches
            % (the bilinear kernel adds a row on either side, then whole chunk
            % rows of that level) and across its full width, which
            % ``Zarr3Saver.buildLevelBand`` takes, in the level slices of the
            % processed ones.
            %
            % Errors, with the store unchanged: ``overwriteSliceLayout`` for a
            % store of another layout, ``overwriteSliceResult`` when the result
            % has another class or number of channels than the image. An error
            % while writing into the store (step 2) raises
            % ``overwriteSliceWrite``, which says the box may be partly
            % replaced; the image is reopened in both cases.
            %
            % Input Arguments:
            %   - **BatchOpt** - as for ``run``
            %   - **slices** - [double] slices of ``s0``, 1-based
            %   - **region** - ``[yFirst yLast xFirst xLast]`` of ``s0``, or ``[]``
            %   - **regionMask** - logical mask of the box, or ``[]``
            %   - **temporaryPath** - [char] path of the temporary array, removed at the end
            %   - **blockFunction**, **options** - as for ``run``
            %   - **parentFigure** - figure for the progress dialog, ``[]`` without one
            %   - **pool** - ``parallel.Pool`` that computes the bands of step 1
            %     (``processBands``), ``[]`` on the client; step 2 always runs on the client
            %
            % Output Arguments:
            %   - **completed** - [logical] false when cancelled in step 1
            completed = false;
            id = BatchOpt.id;
            dataset = obj.mibModel.I{id};
            pyramid = dataset.image.pyramid;
            sourcePath = char(dataset.image.filename);
            levelSizes = pyramid.levelImageSizes;    % [Y X Z] per level
            colors = dataset.image.colors;
            dataClass = dataset.image.dataClass;
            if isempty(region); region = [1 levelSizes(1, 1) 1 levelSizes(1, 2)]; end

            % the layout Zarr3Saver writes, which buildLevelBand rebuilds
            zFactors = [1; round(pyramid.levelScaleFactors(2:end, 3) ./ pyramid.levelScaleFactors(1:end-1, 3))];
            expectedOrder = 'yxz';
            if colors > 1; expectedOrder = 'yxzc'; end
            sameLayout = isfield(pyramid, 'axisOrder') && strcmp(char(pyramid.axisOrder), expectedOrder) && ...
                all(ismember(zFactors, [1 2])) && isequal(levelSizes(2:end, :), ...
                [ceil(levelSizes(1:end-1, 1:2) / 2), ceil(levelSizes(1:end-1, 3) ./ zFactors(2:end))]);
            if ~sameLayout
                error('controllers:BigDataOptions:overwriteSliceLayout', ...
                    ['A slice or a ROI is written into a store only with the layout MIB writes, which this store ' ...
                     'does not have:\n  %s\nOverwrite the whole image ("3D, Stack", no ROI), or write a new store.'], sourcePath);
            end
            provider = io.savers.FilteredSliceProvider(dataset.image, 1, options.ColChannel, blockFunction, ...
                HaloYX = options.HaloYX, HaloZ = options.HaloZ, Region = region, RegionMask = regionMask);
            if provider.NumChannels ~= colors || ~strcmp(provider.DataClass, dataClass)
                error('controllers:BigDataOptions:overwriteSliceResult', ...
                    ['The result has %d channel(s) of %s, the image %d of %s; a slice or a ROI is written into the ' ...
                     'store only with the channels and class of the image. Write a new store instead.'], ...
                    provider.NumChannels, provider.DataClass, colors, dataClass);
            end

            boxHeight = region(2) - region(1) + 1;
            boxWidth = region(4) - region(3) + 1;
            bandRows = floor(options.BandBytes / (8 * boxWidth * colors));
            bandRows = max(1, floor(bandRows / localRowAlign(1))) * localRowAlign(1);
            % band starts in s0 rows: the box top, then whole bands of chunk rows
            bandStarts = unique([region(1), (ceil(region(1) / bandRows) * bandRows + 1):bandRows:region(2)]);
            bandStarts = bandStarts(bandStarts <= region(2));
            bandEnds = [bandStarts(2:end) - 1, region(2)];
            boxShape = [boxHeight boxWidth numel(slices)];
            if colors > 1; boxShape = [boxShape colors]; end
            temporary = io.zarr.Array.create(temporaryPath, boxShape, dataClass, ...
                'chunkShape', [min(boxHeight, localRowAlign(1)), boxWidth, 1, boxShape(4:end)]);
            if isscalar(slices)
                what = sprintf('slice %d', slices);
            else
                what = sprintf('%d slices', numel(slices));
            end
            if ~isequal(region, [1 levelSizes(1, 1) 1 levelSizes(1, 2)]); what = [what ' in the ROI']; end

            progressDialog = [];
            if ~isempty(parentFigure)
                progressDialog = uiprogressdlg(parentFigure, 'Title', 'Overwriting the image', ...
                    'Message', sprintf('Step 1 of 2: processing %s', what), 'Cancelable', 'on');
                cleanupDialog = onCleanup(@() delete(progressDialog));
            end
            % step 1, cancelable: the processed box into the temporary array
            % one task per band, slice by slice: [z firstRow lastRow], rows of the box
            [bandIndices, sliceIndices] = ndgrid(1:numel(bandStarts), 1:numel(slices));
            tasks = [slices(sliceIndices(:)'); [bandStarts(bandIndices(:)'); bandEnds(bandIndices(:)')] - region(1) + 1]';
            try
                cancelled = obj.processBands(provider, tasks, pool, progressDialog, @localWriteTemporary);
            catch processError
                rmdir(temporaryPath, 's');
                rethrow(processError);
            end
            if cancelled
                rmdir(temporaryPath, 's');
                return;
            end

            % step 2, not cancelable: level s0, then every coarser level from the level above
            if ~isempty(progressDialog)
                progressDialog.Cancelable = 'off';
                progressDialog.Value = 0;
                progressDialog.Message = sprintf('Step 2 of 2: writing %s into the store; this step cannot be stopped', what);
            end
            oldImage = dataset.image;
            oldImage.closeVirtualDataset();
            try
                target = io.zarr.Array(fullfile(sourcePath, pyramid.levelNames{1}));
                for sliceIndex = 1:numel(slices)
                    for bandIndex = 1:numel(bandStarts)
                        boxRows = [bandStarts(bandIndex), bandEnds(bandIndex)] - region(1) + 1;
                        rows = temporary.read(localBox(boxRows, [1 boxWidth], sliceIndex));
                        target.write(reshape(rows, boxRows(2) - boxRows(1) + 1, boxWidth, 1, colors), ...
                            localBox([bandStarts(bandIndex), bandEnds(bandIndex)], region(3:4), slices(sliceIndex)));
                    end
                    if ~isempty(progressDialog); progressDialog.Value = 0.75 * sliceIndex / numel(slices); end
                end
                changedRows = region(1:2);
                levelSlices = unique(slices);
                for level = 2:size(levelSizes, 1)
                    levelSlices = unique(ceil(levelSlices / zFactors(level)));
                    % the bilinear kernel at 0.5 reaches one more source row on either side
                    changedRows = [max(1, floor((changedRows(1) - 1) / 2)), min(levelSizes(level, 1), ceil((changedRows(2) + 2) / 2))];
                    align = localRowAlign(level);
                    rebuildRows = [floor((changedRows(1) - 1) / align) * align + 1, ...
                        min(levelSizes(level, 1), ceil(changedRows(2) / align) * align)];
                    % a source block of a band about as large as a band of s0, as in saveStreamResumable
                    rowsPerBand = floor(bandRows * boxWidth / (2 * levelSizes(level - 1, 2) * zFactors(level)));
                    rowsPerBand = max(1, floor(rowsPerBand / align)) * align;
                    for levelSlice = levelSlices
                        for rowFirst = rebuildRows(1):rowsPerBand:rebuildRows(2)
                            io.savers.Zarr3Saver.buildLevelBand(sourcePath, pyramid.levelNames{level - 1}, pyramid.levelNames{level}, ...
                                levelSizes(level - 1, 1:2), levelSizes(level, 1:2), levelSlice, levelSlice, rowFirst, ...
                                min(rowFirst + rowsPerBand - 1, rebuildRows(2)), zFactors(level), levelSizes(level - 1, 3), ...
                                colors, dataClass, 'bilinear');
                        end
                    end
                    if ~isempty(progressDialog)
                        progressDialog.Value = 0.75 + 0.25 * (level - 1) / (size(levelSizes, 1) - 1);
                    end
                end
            catch writeError
                rmdir(temporaryPath, 's');
                io.zarr.ChunkCache.clear();
                obj.replaceImage(dataset, oldImage, sourcePath, id);
                error('controllers:BigDataOptions:overwriteSliceWrite', ...
                    'Writing %s into the store failed, so it may be partly replaced:\n%s', what, writeError.message);
            end
            rmdir(temporaryPath, 's');
            % the chunk keys (path and metadata time stamp) are those of the old chunks
            io.zarr.ChunkCache.clear();
            obj.replaceImage(dataset, oldImage, sourcePath, id);
            completed = true;

            function rows = localRowAlign(level)
                % rows of one chunk, or one shard when sharded, of a level
                rows = pyramid.chunkSizes{level}(1);
                if isfield(pyramid, 'shardSizes') && ~isempty(pyramid.shardSizes{level})
                    rows = max(rows, pyramid.shardSizes{level}(1));
                end
            end

            function localWriteTemporary(taskIndex, rows)
                % a processed band into the temporary array, at its slice index there
                temporary.write(reshape(rows, size(rows, 1), boxWidth, 1, colors), ...
                    localBox(tasks(taskIndex, 2:3), [1 boxWidth], sliceIndices(taskIndex)));
            end

            function box = localBox(rowRange, columnRange, slice)
                % bbox [first last+1] of rows, columns and a slice of the temporary array or of s0
                box = [rowRange(1) rowRange(2) + 1; columnRange(1) columnRange(2) + 1; slice slice + 1];
                if colors > 1; box = [box; 1 colors + 1]; end
            end
        end

        function slices = overwriteSlices(obj, BatchOpt)
            % OVERWRITESLICES - The shown slice of a "2D, Slice" run with "Current overwrite (BigData)"; ``[]`` (the whole dataset) otherwise.
            %
            % Read from ``BatchOpt.DatasetType`` by ``confirmRun`` and
            % ``runOverwrite``, so a tool passes nothing more for it. Level
            % ``s0``, the only level of an overwrite. Errors as ``levelSlices``
            % for a view other than XY; ``checkWholeDatasetType`` refuses that
            % before a tool reads anything.
            slices = [];
            if strcmp(BatchOpt.BigData_OpenIn{1}, obj.CurrentOverwrite) && isfield(BatchOpt, 'DatasetType') && ...
                    strcmp(BatchOpt.DatasetType{1}, '2D, Slice')
                slices = obj.levelSlices(BatchOpt, 1, '2D, Slice');
            end
        end

        function [region, regionMask] = regionOfInterest(obj, BatchOpt, level)
            % REGIONOFINTEREST - The box of the ROI(s) at ``level`` and its mask with Restrict to ROI; ``[]`` for the whole dataset.
            %
            % For a ``RoiAware`` tool with ``MibDataset.restrictToROI`` (the
            % Restrict to ROI checkbox of the Selection panel) a run processes
            % only the ROI selected in the
            % ROI list, or all XY ROIs when All is selected
            % (``MibDataset.selectedROI`` 0). ROIs are 2D, stored in
            % full-resolution pixels, and apply to every slice.
            %
            % The box is the union of the ROIs' boxes mapped to the level
            % (full-resolution pixel ``p`` is level pixel ``ceil(p / scale)``),
            % so a whole-slide ROI is never rasterised at full resolution: the
            % mask is drawn at the level inside the box only, with the ROI
            % vertices moved to the level (a pixel centre ``p`` is at ``(p -
            % 0.5) / scale + 0.5``) and ``core.RoiRegion.returnMask``. A
            % rectangle fills its box. The mask is ``[]`` when it covers the
            % whole box, and the region is ``[]`` when it is the whole level.
            %
            % Errors: ``noROI`` when Restrict to ROI is on but there is no ROI,
            % ``roiOrientation`` for a ROI drawn in a view other than XY.
            %
            % Output Arguments:
            %   - **region** - ``[yFirst yLast xFirst xLast]`` in level pixels, or ``[]``
            %   - **regionMask** - logical ``[boxHeight boxWidth]``, or ``[]``
            region = [];
            regionMask = [];
            dataset = obj.mibModel.I{BatchOpt.id};
            if ~obj.RoiAware || ~dataset.restrictToROI; return; end
            roiIndices = dataset.selectedROI;
            if isempty(roiIndices) || all(roiIndices == 0)
                [~, roiIndices] = dataset.hROI.getNumberOfROI(3);
            end
            roiIndices = roiIndices(roiIndices > 0);
            if isempty(roiIndices)
                error('controllers:BigDataOptions:noROI', ...
                    'Restrict to ROI is on, but the dataset has no ROI in the XY view; add one, or uncheck Restrict to ROI.');
            end
            if any([dataset.hROI.Data(roiIndices).orientation] ~= 3)
                error('controllers:BigDataOptions:roiOrientation', ...
                    'A BigData dataset is restricted only to ROIs drawn in the XY view.');
            end
            pyramid = dataset.image.pyramid;
            levelSize = pyramid.levelImageSizes(level, 1:2);   % [Y X]
            scale = pyramid.levelScaleFactors(level, 1:2);     % [y x]
            fullSize = [dataset.image.height, dataset.image.width];
            boxes = zeros(numel(roiIndices), 4);    % [yFirst yLast xFirst xLast] at the level
            for roiIndex = 1:numel(roiIndices)
                roi = dataset.hROI.Data(roiIndices(roiIndex));
                rows = min(max(round([min(roi.Y(:)), max(roi.Y(:))]), 1), fullSize(1));
                columns = min(max(round([min(roi.X(:)), max(roi.X(:))]), 1), fullSize(2));
                boxes(roiIndex, :) = [min(ceil(rows / scale(1)), levelSize(1)), min(ceil(columns / scale(2)), levelSize(2))];
            end
            region = [min(boxes(:, 1)), max(boxes(:, 2)), min(boxes(:, 3)), max(boxes(:, 4))];
            regionMask = false(region(2) - region(1) + 1, region(4) - region(3) + 1);
            shapes = core.RoiRegion();
            for roiIndex = 1:numel(roiIndices)
                roi = dataset.hROI.Data(roiIndices(roiIndex));
                roiType = roi.type;
                if iscell(roiType); roiType = roiType{1}; end
                if ismember(roiType, {'imrect', 'rectangle'})
                    box = boxes(roiIndex, :) - [region(1) region(1) region(3) region(3)] + 1;
                    regionMask(box(1):box(2), box(3):box(4)) = true;
                else
                    roi.X = (double(roi.X) - 0.5) / scale(2) + 0.5 - (region(3) - 1);
                    roi.Y = (double(roi.Y) - 0.5) / scale(1) + 0.5 - (region(1) - 1);
                    shapes.Data = roi;
                    regionMask = regionMask | logical(shapes.returnMask(1, size(regionMask, 1), size(regionMask, 2), 3, 0));
                end
            end
            if all(regionMask(:)); regionMask = []; end
            if isempty(regionMask) && isequal(region, [1 levelSize(1) 1 levelSize(2)]); region = []; end
        end

        function result = runToStandard(obj, BatchOpt, level, blockFunction, options)
            % RUNTOSTANDARD - Process the dataset ``BatchOpt.id`` at ``level`` into a Standard dataset in memory, opened in ``BigData_OpenIn``.
            %
            % The ``'Standard (in memory)'`` branch of ``run``: no store is
            % written. Level ``level`` is read in bands of rows through
            % ``io.savers.FilteredSliceProvider``, as for a store, and every band
            % goes into one ``[H W Z C]`` array, which ``MibDataset.initialize``
            % then takes as the image of the buffer (``'Current'`` or
            % ``'Container N'``), with an empty model. The new dataset gets the
            % voxel size of the level (the source's times the level scale) and
            % the bounding box origin of the source, so it overlays the source
            % (with Restrict to ROI the dataset is the box of the ROI,
            % ``regionOfInterest``, and its origin is that of the box);
            % its file name is that of ``BigData_OutputPath`` with ``.tif``
            % (``<source stem>_<suffix>.tif`` when the path is empty), not written. ``'Current'`` replaces the BigData dataset of
            % this buffer: its readers and its model are closed, the stores on
            % disk are not touched; the GUI asks first (``confirmRun``).
            %
            % **Memory.** Refused before anything is read when the image plus
            % its model (1 byte per voxel) need more than half of the memory
            % MATLAB reports as available (``memory``, Windows; elsewhere not
            % checked). The class and channels of the result come from the
            % provider's probe of the first rows, so a filter that changes the
            % class is counted right.
            %
            % Errors: ``standardTarget`` for an Open in item that is not a
            % buffer, ``standardTooLarge``, ``utils:bigdata:outputClass`` for a
            % float result (MIB images are integer). A cancel returns ``[]``
            % with every buffer as it was.
            %
            % Input Arguments:
            %   - **BatchOpt**, **blockFunction**, **options** - as for ``run``
            %   - **level** - [double] 1-based pyramid level, from ``resolveLevel``
            %
            % Output Arguments:
            %   - **result** - struct ``outputPath`` (``'Container N (Standard, in
            %     memory)'``) and ``bufferId`` ``N``; ``[]`` when cancelled
            result = [];
            dataset = obj.mibModel.I{BatchOpt.id};
            openIn = BatchOpt.BigData_OpenIn{1};
            if strcmp(openIn, 'Current')
                targetId = BatchOpt.id;
            else
                targetId = sscanf(openIn, 'Container %d');
            end
            if ~isscalar(targetId) || targetId < 1 || targetId > numel(obj.mibModel.I)
                error('controllers:BigDataOptions:standardTarget', ['"%s" (BigData_OpenIn) is not a buffer; ' ...
                    'a Standard result opens in "Current" or "Container N".'], openIn);
            end

            [region, regionMask] = obj.regionOfInterest(BatchOpt, level);
            provider = io.savers.FilteredSliceProvider(dataset.image, level, options.ColChannel, blockFunction, ...
                HaloYX = options.HaloYX, HaloZ = options.HaloZ, Region = region, RegionMask = regionMask);
            if ~ismember(provider.DataClass, {'uint8', 'uint16', 'uint32'})
                error('utils:bigdata:outputClass', ...
                    'The processing returns %s; convert the result to uint8, uint16 or uint32.', provider.DataClass);
            end
            outputSize = [provider.SliceSize(1:2), provider.NumSlices, provider.NumChannels];    % [H W Z C]
            requiredBytes = prod(outputSize) * numel(typecast(zeros(1, 1, provider.DataClass), 'uint8')) + prod(outputSize(1:3));
            try
                memoryInfo = memory;
                availableBytes = memoryInfo.MemAvailableAllArrays;
            catch
                availableBytes = Inf;   % memory() is Windows only
            end
            if requiredBytes > availableBytes / 2
                error('controllers:BigDataOptions:standardTooLarge', ['The result at level s%d needs %.1f GB with its ' ...
                    'model, more than half of the %.1f GB of memory available.\nChoose a coarser level, or write ' ...
                    'an OME-Zarr store.'], level - 1, requiredBytes / 1e9, availableBytes / 1e9);
            end
            parentFigure = obj.guiFigure();
            if ~options.Confirmed && ~obj.confirmRun(BatchOpt, blockFunction, HaloYX = options.HaloYX, ...
                    HaloZ = options.HaloZ, ColChannel = options.ColChannel, BandBytes = options.BandBytes)
                return;
            end
            [pool, releaseWorkers, cancelled] = obj.startPool(BatchOpt, parentFigure); %#ok<ASGLU> kept until the run returns
            if cancelled; return; end

            height = outputSize(1);
            width = outputSize(2);
            bandRows = max(1, min(height, floor(options.BandBytes / (8 * width * max(outputSize(4), dataset.image.colors)))));
            bandStarts = 1:bandRows:height;
            progressDialog = [];
            if ~isempty(parentFigure)
                progressDialog = uiprogressdlg(parentFigure, 'Title', 'Processing into memory', ...
                    'Message', sprintf('Level s%d, %d slice(s)', level - 1, outputSize(3)), 'Cancelable', 'on');
                cleanupDialog = onCleanup(@() delete(progressDialog));
            end
            output = zeros(outputSize, provider.DataClass);
            % one task per band, slice by slice: [z firstRow lastRow]
            [bandIndices, sliceIndices] = ndgrid(1:numel(bandStarts), 1:outputSize(3));
            firstRows = bandStarts(bandIndices(:)');
            tasks = [sliceIndices(:)'; firstRows; min(firstRows + bandRows - 1, height)]';
            if obj.processBands(provider, tasks, pool, progressDialog, @localStoreBand); return; end

            % the meta of the source, for the level and the result
            scale = dataset.image.pyramid.levelScaleFactors(level, :);    % [y x z]
            pixSize = dataset.image.pixSize;
            pixSize.y = pixSize.y * scale(1);
            pixSize.x = pixSize.x * scale(2);
            pixSize.z = pixSize.z * scale(3);
            origin = dataset.image.boundingBox([1 3 5]);
            if ~isempty(region)
                % the box of the ROI starts after region(3) - 1 columns and region(1) - 1 rows of the level
                origin = origin + [(region(3) - 1) * pixSize.x, (region(1) - 1) * pixSize.y, 0];
            end
            boundingBox = [origin(1), origin(1) + (width - 1) * pixSize.x, origin(2), origin(2) + (height - 1) * pixSize.y, ...
                origin(3), origin(3) + (outputSize(3) - 1) * pixSize.z];
            meta = dataset.image.getMeta();
            sameLook = strcmp(provider.DataClass, dataset.image.dataClass) && outputSize(4) == dataset.image.colors;
            [outputFolder, outputStem] = fileparts(char(BatchOpt.BigData_OutputPath));
            if isempty(outputStem)
                [outputFolder, outputStem] = fileparts(dataset.image.filename);
                outputStem = [outputStem '_' obj.OutputSuffix];
            end
            meta{'Filename'} = fullfile(outputFolder, [outputStem '.tif']);
            meta{'Height'} = height;
            meta{'Width'} = width;
            meta{'Depth'} = outputSize(3);
            meta{'Colors'} = outputSize(4);
            meta{'Time'} = 1;
            meta{'imgClass'} = provider.DataClass;
            meta{'MaxInt'} = double(intmax(provider.DataClass));
            meta{'pixSize'} = pixSize;
            meta{'ImageDescription'} = sprintf('BoundingBox %f %f %f %f %f %f', boundingBox);
            meta{'SliceName'} = [];
            meta{'SliceSize'} = [];
            if ~sameLook
                % the contrast and colours of the source do not fit another class or channel count
                meta{'viewPort'} = struct('min', zeros(1, outputSize(4)), ...
                    'max', repmat(meta{'MaxInt'}, 1, outputSize(4)), 'gamma', ones(1, outputSize(4)));
                meta{'lutColors'} = utils.defaults.generateLUT(outputSize(4));
            end
            if outputSize(4) == 1 && strcmp(meta{'ColorType'}, 'multichannel'); meta{'ColorType'} = 'grayscale'; end

            target = obj.mibModel.I{targetId};
            target.initialize(output, meta, 'Standard', 'labels63', obj.mibModel.preferences.System.EnableSelection);
            target.setPixSize(pixSize);
            target.updateBoundingBox(boundingBox);
            controllers.BigDataOptions.showNewDataset(obj.mibModel, targetId);
            result = struct('outputPath', sprintf('Container %d (Standard, in memory)', targetId), 'bufferId', targetId);

            function localStoreBand(taskIndex, rows)
                % the band into the array in memory; nested, so the array is filled in place
                output(tasks(taskIndex, 2):tasks(taskIndex, 3), :, tasks(taskIndex, 1), :) = ...
                    reshape(rows, size(rows, 1), width, 1, outputSize(4));
            end
        end

        function replaceImage(obj, dataset, oldImage, storePath, id)
            % REPLACEIMAGE - Reopen ``storePath`` as the image of ``dataset``, keeping every other layer.
            loaderOptions = struct('datasetMode', 'BigData');
            loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
            [imageInfo, files] = loader.loadMetadata({storePath}, loaderOptions);
            [imageData, imageInfo] = loader.loadImages(files, imageInfo, loaderOptions);
            imageInfo = utils.concatenateDictionaries(core.MibImage.initializeImgInfo(), imageInfo);
            newImage = core.MibBigDataImage(imageData, imageInfo);
            % pixSize is not set by the image constructor (MibDataset.initialize
            % sets it afterwards through setPixSize), and boundingBox is the
            % store's; keep the dataset's own values, which may have been edited
            newImage.pixSize = oldImage.pixSize;
            newImage.boundingBox = oldImage.boundingBox;
            newImage.actionLog = oldImage.actionLog;
            newImage.lutColors = oldImage.lutColors;
            newImage.maskFilename = oldImage.maskFilename;
            newImage.lockedState = oldImage.lockedState;
            if strcmp(newImage.dataClass, oldImage.dataClass)
                newImage.viewPort = oldImage.viewPort;
            end
            dataset.image = newImage;
            dataset.dim_yxzct = newImage.dim_yxzct;
            notify(obj.mibModel, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)));
        end

        function attach(obj)
            % ATTACH - Insert the views.components.BigDataOutput component as a row above the last row of the window's top grid.
            %
            % The row takes the designed height of the component, read from an
            % instance without a parent. The component itself is created in
            % the window: without a parent its panel title takes the figure
            % defaults (8 points) instead of those of the window's own panels.
            gui = obj.controller.view.gui;
            topGrid = findobj(gui.Children, 'flat', 'Type', 'uigridlayout');
            if isempty(topGrid)
                error('controllers:BigDataOptions:noGrid', ...
                    'The tool window has no top grid layout to add the BigData panel to.');
            end
            topGrid = topGrid(1);
            sizeProbe = views.components.BigDataOutput('Parent', []);
            obj.panelHeight = sizeProbe.Position(4);
            delete(sizeProbe);
            rowCount = numel(topGrid.RowHeight);
            % rows first, then the children: a child moved past the last row makes
            % the grid add a '1x' row of its own
            topGrid.RowHeight = [topGrid.RowHeight(1:end-1), {obj.panelHeight}, topGrid.RowHeight(end)];
            obj.shiftRows(topGrid, rowCount, 1);
            obj.resizeWindow(gui, obj.panelHeight + topGrid.RowSpacing);

            obj.panel = views.components.BigDataOutput(topGrid);
            obj.panel.Layout.Row = rowCount;
            columnCount = numel(topGrid.ColumnWidth);
            if columnCount > 1; obj.panel.Layout.Column = [1 columnCount]; end
            % tagged with their BatchOpt fields for updateBatchOptFromGUI_Shared
            for widgetName = {'BigData_PyramidLevel', 'BigData_Result', 'BigData_OpenIn', 'sizeLabel', 'BigData_OutputPath', 'selectOutputBtn'}
                obj.widgets.(widgetName{1}) = obj.panel.handles.(widgetName{1});
                obj.widgets.(widgetName{1}).Tag = widgetName{1};
            end
            obj.wireWidgets();
            % the font preference, as the window has it; from inside, since the
            % children of a component are hidden from a walk that starts outside it
            utils.fontSizeUpdate(obj.panel.handles.componentGridLayout, obj.mibModel.preferences.System.Font);
            obj.panelShown = true;
        end

        function wireWidgets(obj)
            % WIREWIDGETS - Set the callbacks and tooltips of the panel widgets.
            obj.widgets.BigData_PyramidLevel.Tooltip = 's0 is full resolution; a coarser level is faster';
            obj.widgets.BigData_OpenIn.Tooltip = ['Buffer for the result; "Current" replaces this dataset in its buffer and keeps the source store, ' ...
                '"Current overwrite (BigData)" rewrites the source store (unlocked image, level s0), whatever the Result'];
            obj.widgets.BigData_Result.Tooltip = ['A new OME-Zarr store, or a Standard dataset in memory when the result fits ' ...
                '(no store is written)'];
            obj.widgets.BigData_OutputPath.Tooltip = 'New OME-Zarr store with the result; the source image is not changed';
            obj.widgets.selectOutputBtn.Tooltip = 'Choose the folder for the result, or an existing .zarr3 store to replace';
            for widgetName = {'BigData_PyramidLevel', 'BigData_Result', 'BigData_OpenIn', 'BigData_OutputPath'}
                obj.widgets.(widgetName{1}).ValueChangedFcn = @(source, ~) obj.widgetChanged(source);
            end
            obj.widgets.selectOutputBtn.ButtonPushedFcn = @(~, ~) obj.selectOutput();
        end

        function showPanel(obj, shown)
            % SHOWPANEL - Show the inserted panel, or hide it: its grid row goes to 0 px and the window shrinks by the row height.
            %
            % The component stays, with its widgets and callbacks, so showing
            % it again costs only the resize. The 0 px row keeps its row
            % spacing, so the window changes by the row height only and every
            % other row keeps its size.
            if shown == obj.panelShown; return; end
            topGrid = obj.panel.Parent;
            panelRow = obj.panel.Layout.Row(1);
            if shown
                obj.resizeWindow(obj.controller.view.gui, obj.panelHeight);
                topGrid.RowHeight{panelRow} = obj.panelHeight;
            else
                topGrid.RowHeight{panelRow} = 0;
                obj.resizeWindow(obj.controller.view.gui, -obj.panelHeight);
            end
            obj.panel.Visible = matlab.lang.OnOffSwitchState(shown);
            obj.panelShown = shown;
        end

        function widgetChanged(obj, source)
            % WIDGETCHANGED - Write a panel widget into the tool's BatchOpt.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.BigDataOptions.widgetChanged(%s): triggered\n', source.Tag);
            end
            if strcmp(source.Tag, 'BigData_OutputPath'); obj.pathEditedByUser = true; end
            obj.controller.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.controller.BatchOpt, source);
            if strcmp(source.Tag, 'BigData_Result')
                % the Open in items depend on the kind of result
                obj.controller.BatchOpt = obj.addBatchOptFields(obj.controller.BatchOpt);
                obj.widgets.BigData_OpenIn.Items = obj.controller.BatchOpt.BigData_OpenIn{2};
                obj.widgets.BigData_OpenIn.Value = obj.controller.BatchOpt.BigData_OpenIn{1};
            end
            obj.updateSizeLabel();
            obj.updatePathEnable();
            if any(strcmp(source.Tag, {'BigData_OpenIn', 'BigData_Result'})); obj.updateDatasetType(true); end
        end

        function updateDatasetType(obj, isBigData)
            % UPDATEDATASETTYPE - Remove "2D, Slice" from the tool's DatasetType while the result goes to a new store.
            %
            % A new store holds the whole dataset, so a shown-slice choice
            % would be ignored; "3D, Stack" replaces it. The tool's own items
            % come back for a model output (``runToModel`` takes the shown
            % slice), for ``'Current overwrite (BigData)'`` (``overwriteSlice`` writes the
            % shown slice into the store; called again when Open in changes)
            % and for a dataset that is not BigData. Tools without a
            % ``DatasetType`` field or widget are left alone; the headless
            % refusal is ``checkWholeDatasetType``.
            if ~isfield(obj.controller.BatchOpt, 'DatasetType') || ~isfield(obj.controller.view.handles, 'DatasetType')
                return;
            end
            if isempty(obj.datasetTypeItems); obj.datasetTypeItems = obj.controller.BatchOpt.DatasetType{2}; end
            items = obj.datasetTypeItems;
            if isBigData && ~obj.ModelOutput && ~strcmp(obj.controller.BatchOpt.BigData_OpenIn{1}, obj.CurrentOverwrite)
                items = setdiff(items, {'2D, Slice'}, 'stable');
            end
            value = obj.controller.BatchOpt.DatasetType{1};
            if ~ismember(value, items); value = items{1}; end
            obj.controller.BatchOpt.DatasetType = {value, items};
            obj.controller.view.handles.DatasetType.Items = items;
            obj.controller.view.handles.DatasetType.Value = value;
        end

        function updatePathEnable(obj)
            % UPDATEPATHENABLE - Disable the widgets that do not apply: Result, Open in and Output for a model output, Output for "Current overwrite (BigData)" and a Standard result.
            if isempty(obj.panel); return; end
            openEnable = ~obj.ModelOutput;
            pathEnable = openEnable && ~strcmp(obj.controller.BatchOpt.BigData_OpenIn{1}, obj.CurrentOverwrite) && ...
                ~strcmp(obj.controller.BatchOpt.BigData_Result{1}, obj.StandardResult);
            obj.widgets.BigData_Result.Enable = matlab.lang.OnOffSwitchState(openEnable);
            obj.widgets.BigData_OpenIn.Enable = matlab.lang.OnOffSwitchState(openEnable);
            obj.widgets.BigData_OutputPath.Enable = matlab.lang.OnOffSwitchState(pathEnable);
            obj.widgets.selectOutputBtn.Enable = matlab.lang.OnOffSwitchState(pathEnable);
        end

        function selectOutput(obj)
            % SELECTOUTPUT - Choose the folder for the output store, or an existing store to replace, with uigetdir.
            %
            % A store is a folder, which uiputfile opens instead of selecting it.
            % A selected folder named ``*.zarr`` / ``*.zarr3`` is taken as the
            % store itself (run asks before replacing it); any other folder
            % receives the store under its current name, which is edited in the
            % Output field.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.BigDataOptions.selectOutput: triggered\n');
            end
            [parentFolder, storeStem, storeExtension] = fileparts(obj.controller.BatchOpt.BigData_OutputPath);
            if ~isfolder(parentFolder); parentFolder = obj.mibModel.currentDirectory; end
            selectedFolder = uigetdir(parentFolder, 'Folder for the result, or an existing Zarr store to replace');
            figure(obj.controller.view.gui);
            if isequal(selectedFolder, 0); return; end
            [~, ~, selectedExtension] = fileparts(selectedFolder);
            if any(strcmpi(selectedExtension, {'.zarr', '.zarr3'}))
                obj.widgets.BigData_OutputPath.Value = selectedFolder;
            else
                obj.widgets.BigData_OutputPath.Value = fullfile(selectedFolder, [storeStem storeExtension]);
            end
            obj.widgetChanged(obj.widgets.BigData_OutputPath);
        end

        function updateSizeLabel(obj)
            % UPDATESIZELABEL - Show the size of the result at the selected level.
            dataset = obj.mibModel.I{obj.controller.BatchOpt.id};
            level = obj.levelFromItem(obj.controller.BatchOpt.BigData_PyramidLevel{1});
            levelSize = dataset.image.pyramid.levelImageSizes(level, :);
            bytes = prod(levelSize) * dataset.image.colors * numel(typecast(zeros(1, dataset.image.dataClass), 'uint8'));
            if bytes >= 1e9
                sizeText = sprintf('%.1f GB', bytes / 1e9);
            else
                sizeText = sprintf('%.0f MB', max(1, bytes / 1e6));
            end
            obj.widgets.sizeLabel.Text = sprintf('%dx%dx%d, %s', levelSize(2), levelSize(1), levelSize(3), sizeText);
            obj.widgets.sizeLabel.Tooltip = obj.widgets.sizeLabel.Text;     % the full text when the label is cut
        end
    end

    methods (Static, Hidden)
        % Task of processBands. Public only so that parfeval can call it on a
        % pool worker; not meant to be called directly.

        function rows = workerBandRows(providerConstant, z, firstRow, lastRow)
            % WORKERBANDROWS - Rows ``firstRow..lastRow`` of slice ``z`` of the provider in ``providerConstant`` (``parallel.pool.Constant``).
            rows = providerConstant.Value.getSliceRows(z, firstRow, lastRow);
        end
    end

    methods (Static, Access = private)
        function showNewDataset(mibModel, targetId)
            % SHOWNEWDATASET - Finish buffer ``targetId`` after ``initialize`` with a new image and show it.
            %
            % For ``openStoreInBuffer`` and ``runToStandard``. ``initialize``
            % leaves the viewing slices at ``[1 1]`` and the pan window at NaN,
            % and the ``NewDataset`` listener does not reset them, so they are
            % set to the new extent here; ``Sets.datasetTypes`` is synced so
            % the dataset-type dropdown shows the new type. ``NewDataset`` is
            % sent with the buffer index, as ``listener_newDataset`` expects.
            dataset = mibModel.I{targetId};
            dataset.enableSelection = mibModel.preferences.System.EnableSelection;

            dataset.dim_yxzct = dataset.image.dim_yxzct;
            dataset.slices{1} = [1, dataset.image.height];
            dataset.slices{2} = [1, dataset.image.width];
            dataset.slices{3} = [1, dataset.image.depth];
            dataset.slices{5} = [1 1];
            dataset.slices{dataset.orientation} = [1 1];
            if isempty(dataset.axesX) || any(isnan(dataset.axesX)); dataset.axesX = [1, dataset.image.width]; end
            if isempty(dataset.axesY) || any(isnan(dataset.axesY)); dataset.axesY = [1, dataset.image.height]; end

            targetSet     = floor((targetId - 1) / mibModel.Sets.datasetsInSet) + 1;
            targetLocalId = mod(targetId - 1, mibModel.Sets.datasetsInSet) + 1;
            mibModel.Sets.datasetTypes{targetSet, targetLocalId} = dataset.datasetType;

            notify(mibModel, 'NewDataset', core.ToggleEventData(struct('index', targetId)));
            notify(mibModel, 'UpdateFileList');
        end

        function level = levelFromItem(levelItem)
            % LEVELFROMITEM - 1-based pyramid level of an ``'sN'`` item (``'s0'`` -> 1); [] when not one.
            level = sscanf(levelItem, 's%d', 1) + 1;
        end

        function shiftRows(grid, firstRow, shift)
            % SHIFTROWS - Move every child of ``grid`` placed at ``firstRow`` or below by ``shift`` rows.
            children = grid.Children;
            for childIndex = 1:numel(children)
                rows = children(childIndex).Layout.Row;
                if any(rows >= firstRow)
                    rows(rows >= firstRow) = rows(rows >= firstRow) + shift;
                    children(childIndex).Layout.Row = rows;
                end
            end
        end

        function resizeWindow(gui, extraHeight)
            % RESIZEWINDOW - Grow the window by ``extraHeight`` pixels downwards, keeping its top edge.
            %
            % A uifigure applies Position asynchronously: the window reports a
            % change back some time after it was set, and that late report
            % overwrites a newer value. Measured with drawnow only: of three resizes
            % in a row the second was lost; with a 0.3 s pause after each, none.
            % Here a resize made right after another one (the tool's own
            % moveWindowOutside before the panel is attached, or hiding / showing it in
            % quick succession) would read a stale position and undo it. So: wait
            % until the position is steady, set, and set again until it holds.
            % About 0.1 s normally, at most about 1 s.
            position = controllers.BigDataOptions.steadyPosition(gui);
            target = [position(1), position(2) - extraHeight, position(3), position(4) + extraHeight];
            for attempt = 1:10
                gui.Position = target;
                current = controllers.BigDataOptions.steadyPosition(gui);
                if all(abs(current - target) < 1); break; end
            end
        end

        function position = steadyPosition(gui)
            % STEADYPOSITION - Window position once two reads 50 ms apart agree (at most 0.5 s).
            drawnow;
            position = gui.Position;
            for attempt = 1:10
                pause(0.05);
                drawnow;
                current = gui.Position;
                if all(abs(current - position) < 1); return; end
                position = current;
            end
        end
    end
end
