function stitchBtn_Callback(obj, batchModeSwitch)
% STITCHBTN_CALLBACK - Fuse all tiles into the output dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.stitchBtn_Callback()
%      obj.stitchBtn_Callback(batchModeSwitch)
%
% Input Arguments:
%   - **batchModeSwitch** *(optional)* — [logical] ``true`` when called headlessly
%     (suppresses interactive dialogs); default ``false``
%
% Fusion path depends on ``BatchOpt.OutputMode``:
%   - **In memory** — calls ``utils.stitch.fuseInMemory`` then creates a new
%     ``core.MibDataset`` and notifies ``'NewDataset'``.
%   - **OME-Zarr3 (BigData)** — asks for the pyramid/chunk/compression settings
%     (``io.savers.Zarr3Saver.optionsDialog``, the same dialog as the standard
%     "Export to Zarr3" action), calls ``utils.stitch.fuseStreaming`` to write
%     chunk-wise to an OME-Zarr file, then reopens it via
%     ``io.loaders.Zarr3VirtualSetupLoader`` and notifies ``'NewDataset'``.
%
% The project JSON sidecar is saved if ``BatchOpt.SaveProject`` is true.
%
% This is the ONLY fuse entry point — the seam inspector has no button of its
% own, so a fix made there is baked in by pressing *Stitch* here (both windows
% stay usable side by side). When the inspector still owes a global re-solve
% (auto-re-solve off, or a deferred nudge), that re-solve runs FIRST: the guard
% lives on the operation, not on one button, so the mosaic can never be fused
% from stale positions.
%

if nargin < 2; batchModeSwitch = false; end
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.stitchBtn_Callback: triggered\n');
end

% Apply any seam fix still awaiting its global re-solve before fusing.
if ~isempty(obj.inspector) && isvalid(obj.inspector) && obj.inspector.resolvePending
    obj.inspector.resolveBtn_Callback();
end

% Run any pipeline stages not done yet: layout -> measure -> solve -> canvas.
% In batch mode all stages always run from BatchOpt; in GUI mode the cached
% results of explicit Measure/Solve clicks are reused.
try
    if isempty(obj.layout)
        obj.buildLayoutFromBatchOpt();
    end

    if isempty(obj.edges)
        if obj.BatchOpt.EstimateOverlap
            estimateCancelled = obj.runOverlapEstimation();
            if estimateCancelled
                notify(obj.mibModel, 'StopProtocol');
                return;
            end
        end
        nominalPairs = utils.stitch.findNeighborPairs(obj.layout, struct('minOverlapPx', 16));
        measureOptions.qualityThreshold   = obj.BatchOpt.QualityThreshold{1};
        measureOptions.subpixel           = obj.BatchOpt.SubpixelPlacement;
        measureOptions.registrationMethod = obj.BatchOpt.RegistrationMethod{1};
        measureOptions.transformType      = obj.BatchOpt.TransformType{1};
        measureOptions.allowRotation      = obj.BatchOpt.AllowRotation;
        if strcmp(obj.BatchOpt.RegistrationMethod{1}, 'Feature-based') || ...
                ~strcmp(obj.BatchOpt.TransformType{1}, 'Translation')
            measureOptions.featureOptions = obj.buildFeatureOptions();
        end
        measureOptions.showWaitbar        = obj.BatchOpt.showWaitbar && ~batchModeSwitch;
        if measureOptions.showWaitbar && ~isempty(obj.view)
            measureOptions.parentFigure = obj.view.gui;
        else
            measureOptions.parentFigure = [];
        end
        [measuredEdges, cancelled] = utils.stitch.measureAllPairs(obj.layout, nominalPairs, measureOptions);
        if cancelled
            notify(obj.mibModel, 'StopProtocol');
            return;
        end
        obj.edges = measuredEdges;
    end

    if isempty(obj.positions)
        solverOptions.springWeight = obj.BatchOpt.NominalPositionWeight{1};
        if strcmp(obj.BatchOpt.TransformType{1}, 'Translation')
            obj.positions = utils.stitch.solveGlobalLeastSquares(obj.layout, obj.edges, solverOptions);
            obj.tforms = {};
        else
            solverOptions.transformType = obj.BatchOpt.TransformType{1};
            solverOptions.allowRotation = obj.BatchOpt.AllowRotation;
            [obj.tforms, obj.positions] = utils.stitch.solveGlobalAffine(obj.layout, obj.edges, solverOptions);
        end
        obj.canvas = [];   % canvas must match the fresh positions
    end

    if isempty(obj.canvas)
        canvasOptions = struct('zSliceFixes', obj.zSliceFixes);
        if ~isempty(obj.tforms)
            canvasOptions.tforms = obj.tforms;
        end
        obj.canvas = utils.stitch.planCanvas(obj.layout, obj.positions, canvasOptions);
    end
catch pipelineError
    if ~batchModeSwitch
        utils.dlgs.showErrorDialog(obj.view.gui, pipelineError.message, 'Stitching failed');
    else
        fprintf('Stitching batch error: %s\n', pipelineError.message);
    end
    notify(obj.mibModel, 'StopProtocol');
    return;
end

% Skipping straight to Stitch (no manual Optimize positions click) never runs
% optimizePositions_Callback, which is what normally refreshes the layout
% preview at the solved positions — so without this call the preview would
% still show the nominal layout (or nothing) while a wrong tile
% order/grid/overlap silently fuses. No-op in batch/headless mode (obj.view
% is empty).
obj.previewLayoutBtn_Callback();

outputMode = obj.BatchOpt.OutputMode{1};
blendMode  = obj.BatchOpt.BlendMode{1};

fuseOptions.blendMode    = blendMode;
fuseOptions.showWaitbar  = obj.BatchOpt.showWaitbar && ~batchModeSwitch;
if ~batchModeSwitch && ~isempty(obj.view)
    fuseOptions.parentFigure = obj.view.gui;
else
    fuseOptions.parentFigure = [];
end

if strcmp(outputMode, 'In memory')
    % --- In-memory fusion ---
    try
        fusedVolume = utils.stitch.fuseInMemory(obj.layout, obj.canvas, fuseOptions);
    catch fuseError
        if ~batchModeSwitch
            utils.dlgs.showErrorDialog(fuseOptions.parentFigure, fuseError.message, 'Fusion failed');
        end
        notify(obj.mibModel, 'StopProtocol');
        return;
    end

    % Create MibDataset from fused volume (pattern from ChunkingImport.m:448-453)
    imageMetadata = core.MibImage.initializeImgInfo( ...
        'Height', size(fusedVolume, 1), 'Width', size(fusedVolume, 2), ...
        'Depth', size(fusedVolume, 3), 'Colors', size(fusedVolume, 4), ...
        'imgClass', class(fusedVolume));

    % initializeImgInfo defaults MaxInt/viewPort.max to the 8-bit ceiling
    % (255); sync them to the fused data's actual class (mirrors
    % io.loaders.BaseImageLoader.finalizeImgInfo) so a 16-bit+ mosaic isn't
    % displayed saturated white.
    switch class(fusedVolume)
        case {'single', 'double'}
            imageMetadata{'MaxInt'} = realmax(class(fusedVolume));
        otherwise
            imageMetadata{'MaxInt'} = double(intmax(class(fusedVolume)));
    end
    viewPort = imageMetadata{'viewPort'};
    viewPort.max = imageMetadata{'MaxInt'};
    imageMetadata{'viewPort'} = viewPort;

    activeId = obj.mibModel.getActiveId();
    obj.mibModel.I{activeId} = core.MibDataset(fusedVolume, imageMetadata, 'Standard', 'labels63');
    notify(obj.mibModel, 'NewDataset');

elseif strcmp(outputMode, 'OME-Zarr3 (BigData)')
    % --- Streaming fusion to OME-Zarr ---
    outputPath = obj.BatchOpt.OutputPath;
    if isempty(outputPath)
        if ~batchModeSwitch
            [outputFile, outputFolder] = uiputfile({'*.zarr3', 'OME-Zarr v3 files (*.zarr3)'}, ...
                'Save stitched dataset as OME-Zarr', 'stitched.zarr3');
            if isequal(outputFile, 0)
                return;
            end
            outputPath = fullfile(outputFolder, outputFile);
            obj.zarrExportOptions = [];   % new path → re-ask pyramid settings
        else
            notify(obj.mibModel, 'StopProtocol');
            return;
        end
    end

    % Collect pyramid/chunk/compression settings once (same dialog as the
    % standard "Export to Zarr3" action); cache them so re-fusing to the same
    % path after a seam fix reuses the choice instead of re-prompting. Batch
    % runs and a pre-seeded cache skip the dialog.
    if ~batchModeSwitch && isempty(obj.zarrExportOptions)
        datasetInfo = struct('Y', obj.canvas.size(1), 'X', obj.canvas.size(2), ...
            'Z', obj.canvas.size(3), 'pixSize', obj.canvas.pixSize);
        zarrOptions = io.savers.Zarr3Saver.optionsDialog(obj.view.gui, ...
            obj.mibModel.mibPath, false, datasetInfo);
        if isempty(zarrOptions)
            return;   % user cancelled the settings dialog
        end
        obj.zarrExportOptions = zarrOptions;
    end
    if ~isempty(obj.zarrExportOptions)
        zarrFields = fieldnames(obj.zarrExportOptions);
        for zarrFieldIdx = 1:numel(zarrFields)
            fuseOptions.(zarrFields{zarrFieldIdx}) = obj.zarrExportOptions.(zarrFields{zarrFieldIdx});
        end
    end

    try
        utils.stitch.fuseStreaming(obj.layout, obj.canvas, outputPath, fuseOptions);
    catch fuseError
        if ~batchModeSwitch
            utils.dlgs.showErrorDialog(fuseOptions.parentFigure, fuseError.message, 'Streaming fusion failed');
        end
        notify(obj.mibModel, 'StopProtocol');
        return;
    end

    % Reopen as BigData (pattern from applyAlignmentBigData.m:357-374)
    try
        activeId = obj.mibModel.getActiveId();
        loaderOptions = struct('datasetMode', 'BigData');
        zarr3Loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
        [imageInfo, fileList] = zarr3Loader.loadMetadata({outputPath}, loaderOptions);
        [virtualImage, imageInfo] = zarr3Loader.loadImages(fileList, imageInfo, loaderOptions);
        obj.mibModel.I{activeId}.initialize(virtualImage, imageInfo, 'BigData');
        obj.mibModel.I{activeId}.enableSelection = obj.mibModel.preferences.System.EnableSelection;

        % initialize() leaves viewing slices at [1 1]; reset to the new extent
        % (mirrors applyAlignmentBigData / MibDataset.cropDataset)
        newDataset = obj.mibModel.I{activeId};
        newDataset.dim_yxzct = newDataset.image.dim_yxzct;
        newDataset.slices{1} = [1, newDataset.image.height];
        newDataset.slices{2} = [1, newDataset.image.width];
        newDataset.slices{3} = [1, newDataset.image.depth];
        newDataset.slices{5} = repmat(min([newDataset.slices{5}(1), newDataset.image.time]), 1, 2);
        newDataset.slices{newDataset.orientation} = [1, 1];

        % Sync Sets.datasetTypes for the swapped buffer (applyAlignmentBigData.m:401-404)
        % — the Datasets panel's type dropdown (MibActiveDataset.buffers_Callback)
        % reads this cache, not dataset.datasetType directly, so without this the
        % panel keeps showing "Standard" even though the buffer is now BigData.
        targetSet     = floor((activeId - 1) / obj.mibModel.Sets.datasetsInSet) + 1;
        targetLocalId = mod(activeId - 1, obj.mibModel.Sets.datasetsInSet) + 1;
        obj.mibModel.Sets.datasetTypes{targetSet, targetLocalId} = newDataset.datasetType;

        notify(obj.mibModel, 'NewDataset');
        % NewDataset alone does not repaint the type dropdown: listener_newDataset
        % only fires 'DatasetsPanelUpdate' when the active SET changes, which an
        % in-place buffer swap never does. Fire it explicitly (CropDataset.m
        % pattern: "sync datasetType widget in Datasets panel") so the widget
        % actually re-reads the Sets.datasetTypes value just written above.
        notify(obj.mibModel, 'DatasetsPanelUpdate');
    catch reopenError
        if ~batchModeSwitch
            utils.dlgs.showErrorDialog(fuseOptions.parentFigure, ...
                sprintf('Fusion complete but failed to reopen: %s', reopenError.message), ...
                'Reopen failed');
        end
    end
end

% Save sidecar project
if obj.BatchOpt.SaveProject
    try
        projectPath = resolveProjectPath(obj.BatchOpt.InputPath);

        outputInfo.outputMode = outputMode;
        outputInfo.blendMode  = blendMode;
        if ~isempty(obj.canvas)
            outputInfo.canvasSize = obj.canvas.size;
        end

        % The settings block (schema v3) records the parameters this mosaic was
        % produced with, so Load project can restore the dialog or reuse them.
        utils.stitch.saveProject(projectPath, obj.layout, obj.edges, ...
            obj.positions, obj.solverInfo, outputInfo, obj.tforms, ...
            obj.zSliceFixes, obj.collectProjectSettings());
    catch saveError
        if ~batchModeSwitch
            utils.dlgs.showErrorDialog(fuseOptions.parentFigure, ...
                sprintf('Stitching complete but project save failed: %s', saveError.message), ...
                'Save warning');
        end
    end
end

obj.returnBatchOpt(obj.BatchOpt);
notify(obj.mibModel, 'ShowImage');

end

% =========================================================================
function projectPath = resolveProjectPath(inputPath)
% RESOLVEPROJECTPATH - Pick a valid sidecar path from InputPath, which may be a
% single folder / file, a position/Bio-Formats file, OR a newline-joined list of
% tile folders (multi-select). fileparts on the whole multi-line string yields a
% bogus folder, so pick the first EXISTING entry and derive the folder from it.
projectBase = 'stitch_project';

entries = {};
if ~isempty(inputPath)
    entries = strtrim(strsplit(inputPath, newline));
    entries = entries(~cellfun(@isempty, entries));
end

firstExisting = '';
for entryIdx = 1:numel(entries)
    if isfile(entries{entryIdx}) || isfolder(entries{entryIdx})
        firstExisting = entries{entryIdx};
        break;
    end
end

if isempty(firstExisting)
    projectFolder = pwd;
elseif isfolder(firstExisting)
    if isscalar(entries)
        projectFolder = firstExisting;                 % single tile folder → inside it
    else
        projectFolder = fileparts(firstExisting);      % multi-folder → common parent
    end
elseif isscalar(entries)                               % a single file (position/Bio-Formats)
    [projectFolder, projectBase, ~] = fileparts(firstExisting);
else                                                   % multi-select tile FILES → their folder,
    projectFolder = fileparts(firstExisting);          % generic project name (not tile_01…)
end

projectPath = fullfile(projectFolder, [projectBase, '.mibstitch.json']);
end
