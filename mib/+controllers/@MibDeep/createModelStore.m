function [labelsStore, predictedLevel] = createModelStore(obj, storePath, pyramid, predictionSize, zarrFormat, materialNames, materialColors, resume)
% CREATEMODELSTORE - create an empty BigData model store for the prediction of one image, or reopen an interrupted one.
%
% Syntax:
%   .. code-block:: matlab
%
%       [labelsStore, predictedLevel] = obj.createModelStore(storePath, pyramid, predictionSize, zarrFormat, materialNames, materialColors)
%       [labelsStore, predictedLevel] = obj.createModelStore(..., resume)
%
% First step of the "Zarr3 (BigData model)" output. Creates a
% ``core.MibBigDataLabels`` store at ``storePath`` that mirrors ``pyramid``, the
% pyramid of the source image, so the store opens as an editable model of that
% image in the BigData mode. The labels are then written with
% ``writeModelStoreSlab``, all at once (``writeModelStore``) or slab by slab
% (``predictZarrStore``), and the store is finished with
% ``labelsStore.closeStore()``, which persists the level map and the material
% names set here.
%
% Two layouts:
%
%   - semantic models (``materialNames`` given): packed uint8 store, 63
%     materials; a model with more than 63 classes uses the uint16 layout;
%   - instance models (``materialNames`` empty): uint16 store with up to 16383
%     objects, the names ``{'1'; '2'}`` and generated colours MIB uses for
%     instance models, and ``objects3D = false`` because the 2D Instance
%     prediction numbers objects per slice. "Merge 2D to 3D" reads only
%     ``.model`` files, so the slices of a z-stack store are not linked.
%
% ``obj.ZarrModelOpt`` (``updateModelOutputSettings``) adjusts the store: with
% ``.Levels > 0`` only that many of the finest levels are created (the
% predicted level must be among them, checked by
% ``selectModelStoreDestination``); a non-zero ``.ChunkSize`` ``[y x z]``
% replaces the image chunks on every level (clamped to the level size by
% ``createStore``); ``.ShardSize`` (chunks per shard ``[y x z]``, all > 0 to
% enable, as in the standard zarr export dialog) shards a zarr v3 store through
% ``labelsStore.ShardFactors``; ``.Compressors`` and ``.CompressionLevel`` set
% the codec, passed in the form ``io.savers.Zarr3Saver.optionsDialog`` returns
% (a codec name, or a struct with ``configuration.level``). Level shapes and
% scale factors are not configurable, see ``updateModelOutputSettings``.
%
% With ``resume = true`` the existing store at ``storePath`` (an interrupted
% ``predictZarrStore`` run) is opened instead (``labelsStore.openStore``, which
% loads the level map that run saved after each slab), and the material names and
% colours are set as for a new store. Its level sizes must equal those the
% settings give, otherwise ``MibDeep:createModelStore:cannotResume`` is raised
% and the store is left as it is.
%
% A store that fails to be created is removed together with its level-map side
% file and the error is rethrown (a reopened store is never removed). After a
% successful call the caller owns the cleanup: ``writeModelStore`` removes
% ``storePath`` and ``core.MibBigDataLabels.levelMapPathFor(storePath)`` on a
% later error, so that no partial store is left that would open as a valid
% model; ``predictZarrStore`` keeps a partial store to be resumed, marked by its
% record file (``MibDeep.PredictionRecordFile``).
%
% Input Arguments:
%   - **storePath** - [char] model store to create (``.zarr3`` or ``.zarr2``);
%     an existing folder is replaced, the caller confirms that beforehand
%   - **pyramid** - [struct] ``levelImageSizes``, ``levelScaleFactors``,
%     ``chunkSizes``, ``axisOrder`` of the source image, from ``checkZarrStores``;
%     ``[]`` for an image that is not zarr: a pyramid is then generated from
%     ``predictionSize`` (level 1, XY halvings, ``obj.ZarrModelOpt.Levels``
%     levels or automatic, chunk ``[256 256 16]``), and the prediction is level 1
%     whatever ``BatchOpt.BioformatsIndex`` is
%   - **predictionSize** - [1x3 numeric] ``[height, width, depth]`` of the
%     prediction; must equal the predicted level of ``pyramid``
%   - **zarrFormat** - [numeric] 2 or 3
%   - **materialNames** - [cell] class names without Exterior; ``{}`` for an
%     instance model
%   - **materialColors** - [numeric] ``[N x 3]`` colours of the classes, at least
%     one row per name; ignored for an instance model
%   - **resume** - *(optional)* [logical] reopen the existing store at
%     ``storePath`` instead of creating it, default false
%
% Output Arguments:
%   - **labelsStore** - [core.MibBigDataLabels] the open store
%   - **predictedLevel** - [numeric] level of the store the prediction belongs to

    if isempty(pyramid)
        % an image that is not zarr has no pyramid to mirror: the prediction is level 1 of
        % a generated pyramid (XY halvings, the plan of the zarr export, 16 slices per chunk)
        predictedLevel = 1;
        levelOptions = struct('DownsampleStrategy', 'XY only');
        if obj.ZarrModelOpt.Levels > 0; levelOptions.Levels = obj.ZarrModelOpt.Levels; end
        plan = io.savers.Zarr3Saver.computeLevelPlan(predictionSize(1), predictionSize(2), predictionSize(3), ...
            struct('x', 1, 'y', 1, 'z', 1), levelOptions);
        pyramid = struct('axisOrder', 'yxz', ...
            'levelImageSizes', [[plan.Yl]', [plan.Xl]', [plan.Zl]'], ...
            'levelScaleFactors', [[plan.cumXYFactor]', [plan.cumXYFactor]', [plan.cumZFactor]'], ...
            'chunkSizes', {repmat({[256 256 16]}, 1, numel(plan))});
    else
        predictedLevel = obj.BatchOpt.BioformatsIndex{1};
    end
    levelSize = pyramid.levelImageSizes(predictedLevel, :);
    fullSize = pyramid.levelImageSizes(1, :);
    if ~isequal(predictionSize(1:3), levelSize)
        error('MibDeep:writeModelStore:levelSizeMismatch', ...
            'Size of the prediction (%s) does not match level %d of the image (%s)', ...
            num2str(predictionSize(1:3)), predictedLevel, num2str(levelSize));
    end
    isInstanceModel = isempty(materialNames);

    % settings of obj.ZarrModelOpt: number of levels, chunks and compression
    storePyramid = pyramid;
    numLevels = size(pyramid.levelImageSizes, 1);
    if obj.ZarrModelOpt.Levels > 0
        % fewer levels drop the coarsest ones; selectModelStoreDestination has
        % checked that the predicted level is kept
        numLevels = min(numLevels, obj.ZarrModelOpt.Levels);
        storePyramid.levelImageSizes = pyramid.levelImageSizes(1:numLevels, :);
        storePyramid.levelScaleFactors = pyramid.levelScaleFactors(1:numLevels, :);
        storePyramid.chunkSizes = pyramid.chunkSizes(1:numLevels);
    end
    if all(obj.ZarrModelOpt.ChunkSize > 0)
        % createStore reads the chunk of each level in the axis order of the
        % pyramid, so place [y x z] at their positions in that order
        axisOrder = char(storePyramid.axisOrder);
        chunkVector = ones(1, numel(axisOrder));
        [~, yxzPositions] = ismember('yxz', axisOrder);
        validAxes = yxzPositions > 0;
        chunkVector(yxzPositions(validAxes)) = obj.ZarrModelOpt.ChunkSize(validAxes);
        storePyramid.chunkSizes = repmat({chunkVector}, 1, numLevels);
    end
    compressor = obj.ZarrModelOpt.Compressors;
    compressionLevel = obj.ZarrModelOpt.CompressionLevel;
    if compressionLevel < 1; compressionLevel = 7; end   % 0 = "codec default" in earlier versions
    if strcmp(compressor, 'gzip'); compressionLevel = min(compressionLevel, 9); end
    if ~strcmp(compressor, 'none')
        compressor = struct('name', compressor, 'configuration', struct('level', compressionLevel));
    end

    labelsStore = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
    labelsStore.Compressors = compressor;
    if zarrFormat == 3 && isfield(obj.ZarrModelOpt, 'ShardSize') && all(obj.ZarrModelOpt.ShardSize > 0)
        labelsStore.ShardFactors = obj.ZarrModelOpt.ShardSize;   % chunks per shard [y x z]
    end
    if isInstanceModel || numel(materialNames) > 63
        labelsStore.setLayout('uint16');
    end

    if nargin > 7 && resume
        labelsStore.openStore(storePath);
        if ~isequal(labelsStore.modelLevelSizes, storePyramid.levelImageSizes)
            error('MibDeep:createModelStore:cannotResume', ...
                ['Cannot resume %s: its pyramid levels differ from those of the settings of the model files\n\n' ...
                'Restore the settings of the interrupted run, or choose "Overwrite" to predict it again'], storePath);
        end
    end

    try
        if nargin < 8 || ~resume
            labelsStore.createStore(fullSize, storePath, storePyramid, zarrFormat);
        end
        if isInstanceModel
            labelsStore.materialNames = {'1'; '2'};
            labelsStore.materialColors = rand(65535, 3);
            labelsStore.objects3D = false;
        else
            labelsStore.materialNames = cellstr(materialNames(:));
            labelsStore.materialColors = materialColors(1:numel(materialNames), :);
        end
    catch err
        if nargin > 7 && resume; rethrow(err); end   % an interrupted store is never removed here
        if isfolder(storePath); rmdir(storePath, 's'); end
        levelMapPath = core.MibBigDataLabels.levelMapPathFor(storePath);
        if isfile(levelMapPath); delete(levelMapPath); end
        rethrow(err);
    end
end
