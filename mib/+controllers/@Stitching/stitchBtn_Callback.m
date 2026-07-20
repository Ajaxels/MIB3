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
%   - **OME-Zarr (BigData)** — calls ``utils.stitch.fuseStreaming`` to write
%     chunk-wise to an OME-Zarr file, then reopens it via
%     ``io.loaders.Zarr3VirtualSetupLoader`` and notifies ``'NewDataset'``.
%
% The project JSON sidecar is saved if ``BatchOpt.SaveProject`` is true.
%

if nargin < 2; batchModeSwitch = false; end
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.stitchBtn_Callback: triggered\n');
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
            obj.runOverlapEstimation();
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
        obj.edges = utils.stitch.measureAllPairs(obj.layout, nominalPairs, measureOptions);
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

    activeId = obj.mibModel.getActiveId();
    obj.mibModel.I{activeId} = core.MibDataset(fusedVolume, imageMetadata, 'Standard', 'labels63');
    notify(obj.mibModel, 'NewDataset');

elseif strcmp(outputMode, 'OME-Zarr (BigData)')
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
        else
            notify(obj.mibModel, 'StopProtocol');
            return;
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

        notify(obj.mibModel, 'NewDataset');
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

        utils.stitch.saveProject(projectPath, obj.layout, obj.edges, ...
            obj.positions, struct(), outputInfo, obj.tforms, obj.zSliceFixes);
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
