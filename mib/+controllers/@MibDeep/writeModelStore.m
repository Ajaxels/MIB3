function writeModelStore(obj, outputLabels, storePath, pyramid, zarrFormat, materialNames, materialColors)
% WRITEMODELSTORE - write a prediction of one pyramid level as a BigData model store.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.writeModelStore(outputLabels, storePath, pyramid, zarrFormat, materialNames, materialColors)
%
% Used by ``startPredictionBlockedImage`` (semantic workflows) and
% ``startPredictionInstances`` (2D Instance) for the "Zarr3 (BigData model)"
% output. Creates a ``core.MibBigDataLabels`` store at ``storePath`` that mirrors
% ``pyramid``, the pyramid of the source image, so the store opens as an
% editable model of that image in the BigData mode.
%
% The prediction, made at level ``obj.BatchOpt.BioformatsIndex{1}``, is written
% exactly to that level (``setData63`` with ``'everything'``, never smoothed).
% ``setData63`` propagates it to the coarser levels by nearest-neighbour
% downsampling, raises ``maxIndexUsed`` and sets the level map to the predicted
% level where the prediction has labels. The finer levels are not written: they
% are reconstructed from the predicted level when read (``materializeForRead``)
% or by "Finalize & save" (``materializeAll``), so no full-resolution array is
% built here.
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
% (a codec name, or a struct with ``configuration.level``).
% ``.DownsampleMethod = 'mode'`` replaces the nearest-neighbour coarser levels
% written by ``setData63`` with a majority vote over blocks of the predicted
% level (``io.savers.Zarr3Saver.blockReduce2D``, or ``blockReduce3D`` for a level
% that also halves Z), each coarser level reduced directly from the predicted
% level rather than cascaded. The predicted level is cropped or padded
% (replicate) to whole blocks first, so the reduction stays vectorised. Level
% shapes and scale factors are not configurable, see
% ``updateModelOutputSettings``.
%
% A store that fails to write is removed together with its level-map side
% file, so no partial store is left that would open as a valid model, and the
% error is rethrown.
%
% Input Arguments:
%   - **outputLabels** - [numeric] labels at the size of the predicted level,
%     ``[height, width]`` or ``[height, width, depth]``; 0 = background
%   - **storePath** - [char] model store to create (``.zarr3`` or ``.zarr2``);
%     an existing folder is replaced, the caller confirms that beforehand
%   - **pyramid** - [struct] ``levelImageSizes``, ``levelScaleFactors``,
%     ``chunkSizes``, ``axisOrder`` of the source image, from ``checkZarrStores``
%   - **zarrFormat** - [numeric] 2 or 3
%   - **materialNames** - [cell] class names without Exterior; ``{}`` for an
%     instance model
%   - **materialColors** - [numeric] ``[N x 3]`` colours of the classes, at least
%     one row per name; ignored for an instance model

    predictedLevel = obj.BatchOpt.BioformatsIndex{1};
    levelSize = pyramid.levelImageSizes(predictedLevel, :);
    fullSize = pyramid.levelImageSizes(1, :);
    if ~isequal(size(outputLabels, 1:3), levelSize)
        error('MibDeep:writeModelStore:levelSizeMismatch', ...
            'Size of the prediction (%s) does not match level %d of the image (%s)', ...
            num2str(size(outputLabels, 1:3)), predictedLevel, num2str(levelSize));
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
    if max(outputLabels, [], 'all') > labelsStore.materialMask
        error('MibDeep:writeModelStore:tooManyObjects', ...
            'The prediction has %d objects in one slice, but a BigData model store holds at most %d', ...
            max(outputLabels, [], 'all'), labelsStore.materialMask);
    end

    try
        labelsStore.createStore(fullSize, storePath, storePyramid, zarrFormat);
        labelsStore.setData63(cast(outputLabels, labelsStore.containerClass), 'everything', 3, [], ...
            struct('pyramidLevel', predictedLevel));
        if strcmp(obj.ZarrModelOpt.DownsampleMethod, 'mode')
            % replace the nearest-neighbour coarser levels written by setData63 with a
            % majority vote over blocks of the predicted level
            sourceLabels = reshape(cast(outputLabels, labelsStore.containerClass), levelSize);
            for coarserLevel = predictedLevel+1:size(labelsStore.modelLevelSizes, 1)
                targetSize = labelsStore.modelLevelSizes(coarserLevel, :);
                factors = labelsStore.modelScaleFactors(coarserLevel, :) ./ labelsStore.modelScaleFactors(predictedLevel, :);
                blockFactors = round(factors);
                if all(abs(factors - blockFactors) < 1e-9)
                    % crop or pad (replicate) to whole blocks, which keeps
                    % blockReduce on its vectorised path; a level of ceil(size/2)
                    % would otherwise send the whole level through its
                    % per-pixel loop
                    wholeSize = targetSize .* blockFactors;
                    blocks = sourceLabels(1:min(end, wholeSize(1)), 1:min(end, wholeSize(2)), 1:min(end, wholeSize(3)));
                    blocks = padarray(blocks, max(0, wholeSize - size(blocks, 1:3)), 'replicate', 'post');
                else
                    blocks = sourceLabels;   % non-integer factors: blockReduce's block-boundary loop
                end
                if targetSize(3) == size(blocks, 3)
                    % Z is kept: every slice is reduced on its own (passed as channels)
                    coarserLabels = io.savers.Zarr3Saver.blockReduce2D(blocks, targetSize(1), targetSize(2), @mode);
                else
                    coarserLabels = io.savers.Zarr3Saver.blockReduce3D(blocks, targetSize(1), targetSize(2), targetSize(3), @mode);
                end
                labelsStore.writePackedLevel(coarserLevel, coarserLabels, [1 targetSize(1)], [1 targetSize(2)], [1 targetSize(3)]);
            end
        end
        if isInstanceModel
            labelsStore.materialNames = {'1'; '2'};
            labelsStore.materialColors = rand(65535, 3);
            labelsStore.objects3D = false;
        else
            labelsStore.materialNames = cellstr(materialNames(:));
            labelsStore.materialColors = materialColors(1:numel(materialNames), :);
        end
        labelsStore.closeStore();   % persists the level map and the material names
    catch err
        if isfolder(storePath); rmdir(storePath, 's'); end
        levelMapPath = core.MibBigDataLabels.levelMapPathFor(storePath);
        if isfile(levelMapPath); delete(levelMapPath); end
        rethrow(err);
    end
end
