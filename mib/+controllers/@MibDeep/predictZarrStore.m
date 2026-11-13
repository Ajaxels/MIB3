function [outputLabels, scoreImg, cancelled] = predictZarrStore(obj, storeInfo, predictOpt)
% PREDICTZARRSTORE - predict one zarr image store slab by slab, without loading it whole.
%
% Syntax:
%   .. code-block:: matlab
%
%       [outputLabels, scoreImg, cancelled] = obj.predictZarrStore(storeInfo, predictOpt)
%
% Used by ``startPredictionBlockedImage`` (semantic workflows, Blocked-image
% engine) for ZARR images. Zarr stores are larger than memory as a rule, so the
% predicted level (``BatchOpt.BioformatsIndex``) is read in Z-slabs of the full
% XY extent (``deepmib.readZarrSlab``), each slab is predicted with
% ``processBlocksBlockedImage`` and its results are written to the outputs
% before the next slab is read. Memory follows the slab, not the level.
%
% **Prediction of a slab** gives the result of the prediction of the whole level:
%
%   - 2D: each slice on its own;
%   - 2.5D: each slice with ``floor(depth/2)`` neighbours on both sides, read
%     with the slab (the halo), mirrored only at the ends of the level; the block
%     depth is set to the network depth and its Z border to 0 here, as the
%     whole-level loop does, since ``predictOpt.blockSize`` comes from the overlap
%     settings;
%   - 3D: the slab is predicted with a halo of whole blocks
%     (``ceil(border/blockZ)*blockZ``, border = the overlap or the valid-padding
%     border in Z), and only the slab is kept. The slab depth is a multiple of
%     the block depth, so the block grid and the context of every block are those
%     of the whole level; the halo blocks are predicted twice.
%
% ``BatchOpt.P_ImageDownsamplingFactor`` resizes each slab in XY and the results
% back, as for the whole level (2D and 2.5D; with 3D networks ``start`` refuses
% a factor other than 1 for ZARR images).
%
% **Outputs** (``predictOpt``):
%
%   - ``.modelStorePath`` - "Zarr3 (BigData model)": the store is created
%     (``createModelStore``) before the first slab and each slab is written to it
%     (``writeModelStoreSlab``);
%   - ``.tifFilename`` - "TIF (un)compressed format": slices are appended to the
%     file slab by slab;
%   - ``.scoreStorePath`` - "Zarr3 (BigData)" scores: written by
%     ``io.savers.Zarr3Saver.saveStreamResumable`` (without a pool), which pulls
%     the score slices from a ``deepmib.PredictionSliceProvider``, so the slabs
%     are predicted from inside the saver. The Z-downsampled levels of the store
%     are built after the last slab, from the level above read back from the
%     store (no Cancel there);
%   - ``.keepLabels``/``.keepScores`` - the formats written whole by the caller
%     ("MIB Model format", the patch-wise CSV results; AM, mibImg, mat scores):
%     the slabs are gathered into ``outputLabels``/``scoreImg``, the only arrays
%     of the level size this method holds.
%
% **Slab depth** is the least common multiple of, in order: the block depth (3D),
% the Z factor of the coarsest level of the model store relative to the
% predicted level (each coarser slice then comes from one slab), the Z chunk of
% the predicted level of the image (every chunk is read once) and the Z chunk of
% the model store. While the estimated memory exceeds 80% of the largest possible
% array (``memory``, Windows only), the last term is dropped, and then the depth
% is reduced in steps of the first one. When even the minimal slab does not fit,
% the user may continue or cancel. The estimate counts the slab with its halo,
% its labels and scores, the processing copies (one slice for 2D/2.5D, the slab
% for 3D), the buffer of ``saveStream`` (three write depths of score slices) and
% the gathered outputs.
%
% **Cancel and errors.** ``predictOpt.pwb`` is checked before every slab and
% inside ``processBlocksBlockedImage``. A network read error is retried first
% (``deepmib.readZarrSlab``). On a cancel or an error the zarr stores of this
% image are kept to be resumed and the TIF file is removed; then
% ``cancelled = true`` is returned, or the original error is rethrown (inside the
% saver it would arrive wrapped as ``io:Zarr3Saver:taskFailed``, so the error of
% the slab is kept and raised instead).
%
% **Resume.** Both stores hold ``MibDeep.PredictionRecordFile`` while they are
% written, removed when the image is done; it marks the store as an unfinished
% prediction (``MibDeep.isPredictionStore``, the "Resume" choice of
% ``selectModelStoreDestination``) and holds the fingerprint of the run: names
% (without folders) of the image and the network, the size of the network file,
% the level and its size, and every setting that changes the prediction. Names
% without folders let a run started on another workstation be resumed.
%
%   - model store (``.resumeModel``): the record also holds the slices written
%     (``finishedSlices``, always a whole number of slabs from slice 1) and the
%     downsampling method of the coarser levels; it is rewritten after every
%     slab, after the level map (``labelsStore.saveLevelMap``), through a
%     temporary file. The store is reopened (``createModelStore(..., true)``);
%     a different fingerprint, method or level sizes raises
%     ``MibDeep:predictZarrStore:cannotResume`` or
%     ``MibDeep:createModelStore:cannotResume`` and changes nothing;
%   - score store (``.resumeScores``): the saver keeps its own record of the
%     written slabs and is called with ``Resume = true`` and the fingerprint as
%     ``SourceFingerprint`` (``io:Zarr3Saver:cannotResume`` when they differ).
%     It asks the provider for its first missing slice.
%
% Prediction restarts at the first slab some output lacks: slabs that the model
% store holds and that end before the slice the saver asks for are skipped. The
% slab grid is recomputed in each run, so a different slab depth (other memory)
% only repeats a few slices. A TIF file and the gathered outputs
% (``.keepLabels``, ``.keepScores``) are always made from slice 1.
%
% **Command window.** One line when the image starts (level, size, number and
% depth of the slabs, what is resumed), one when it is done, with the number of
% slabs predicted in this run and the elapsed time (h:mm:ss), and on a cancel or
% an error the slab where it stopped, the elapsed time, the error message and
% the kept stores.
%
% Input Arguments:
%   - **storeInfo** - [struct] one element of ``zarrStores`` from ``checkZarrStores``
%   - **predictOpt** - [struct] with fields:
%
%     - ``.net``, ``.inputPatchSize``, ``.outputPatchSize``, ``.blockSize``,
%       ``.padShift``, ``.dataDimension`` (2, 2.5, 3), ``.patchwiseWorkflowSwitch``,
%       ``.classNames``, ``.generateScoreFiles``, ``.executionEnvironment`` - as
%       for ``processBlocksBlockedImage``
%     - ``.fn`` - [char] image name, for the progress dialog and the CSV files
%     - ``.pwb`` - [uiprogressdlg] or ``[]``
%     - ``.fileIndex``, ``.noFiles``, ``.startTime`` (``tic``) - for the progress
%     - ``.modelStorePath`` - [char] or ``''``; with ``.zarrFormat``,
%       ``.modelMaterialNames``, ``.modelMaterialColors``
%     - ``.tifFilename`` - [char] or ``''``; with ``.tifCompression``
%     - ``.scoreStorePath`` - [char] or ``''``; with ``.scoreSaveOpt``,
%       ``.scoreMetadata``, ``.scoreClassNames`` (the group attribute
%       ``mibPredictionScores``)
%     - ``.keepLabels``, ``.keepScores`` - [logical]
%     - ``.resumeModel``, ``.resumeScores`` - *(optional)* [logical] continue the
%       interrupted model or score store, default false
%
% Output Arguments:
%   - **outputLabels** - [uint8] ``[height, width, depth]`` with ``.keepLabels``,
%     ``[]`` otherwise
%   - **scoreImg** - ``[height, width, classes, depth]`` with ``.keepScores``,
%     ``[]`` otherwise; without the Exterior class unless
%     ``obj.ScoreExportOpt.IncludeExterior``
%   - **cancelled** - [logical] true when the user pressed Cancel

    outputLabels = [];
    scoreImg = [];
    cancelled = false;
    cancelId = 'MibDeep:predictZarrStore:cancelled';

    level = obj.BatchOpt.BioformatsIndex{1};
    levelSize = storeInfo.pyramid.levelImageSizes(level, :);
    [height, width, depth] = deal(levelSize(1), levelSize(2), levelSize(3));
    numColors = storeInfo.colors;
    bytesPerPixel = numel(typecast(cast(0, storeInfo.imgClass), 'uint8'));
    dataDimension = predictOpt.dataDimension;
    numClasses = numel(predictOpt.classNames);
    numScoreClasses = numClasses - ~obj.ScoreExportOpt.IncludeExterior;
    scoreBytes = 1;
    if predictOpt.generateScoreFiles == 4; scoreBytes = 4; end   % the 0-1 range format keeps single
    writeModel = ~isempty(predictOpt.modelStorePath);
    writeTif = ~isempty(predictOpt.tifFilename);
    writeScores = ~isempty(predictOpt.scoreStorePath);
    downsampleFactor = obj.BatchOpt.P_ImageDownsamplingFactor{1};

    % --- halo and the base unit of the slab depth ------------------------
    contextHalf = 0;    % 2.5D: neighbours on each side of a slice
    halo = 0;           % slices read on each side of the slab
    baseDepth = 1;
    switch dataDimension
        case 2.5
            contextHalf = floor(predictOpt.inputPatchSize(3)/2);
            halo = contextHalf;
            % a block of a 2.5D network is the whole network depth, without Z overlap
            % (the caller passes the block size of the overlap settings, as for 3D)
            predictOpt.blockSize(3) = predictOpt.inputPatchSize(3);
            predictOpt.padShift(3) = 0;
        case 3
            baseDepth = predictOpt.blockSize(3);
            border = 0;
            if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'valid')
                border = (predictOpt.inputPatchSize(3) - predictOpt.outputPatchSize(3))/2;
            elseif obj.BatchOpt.P_OverlappingTiles
                border = predictOpt.padShift(3);
            end
            halo = ceil(border/baseDepth)*baseDepth;
    end

    % --- slab depth: alignment terms, most important first ---------------
    axisOrder = char(storeInfo.pyramid.axisOrder);
    imageChunk = storeInfo.pyramid.chunkSizes{level};
    imageChunkZ = 1;
    if any(axisOrder == 'z'); imageChunkZ = imageChunk(axisOrder == 'z'); end
    depthTerms = baseDepth;
    if writeModel
        numModelLevels = size(storeInfo.pyramid.levelScaleFactors, 1);
        if obj.ZarrModelOpt.Levels > 0; numModelLevels = min(numModelLevels, obj.ZarrModelOpt.Levels); end
        zFactors = storeInfo.pyramid.levelScaleFactors(level:numModelLevels, 3) / storeInfo.pyramid.levelScaleFactors(level, 3);
        depthTerms(end+1) = max(1, round(max(zFactors)));
    end
    depthTerms(end+1) = imageChunkZ;
    if writeModel
        modelChunkZ = imageChunkZ;
        if all(obj.ZarrModelOpt.ChunkSize > 0); modelChunkZ = obj.ZarrModelOpt.ChunkSize(3); end
        depthTerms(end+1) = modelChunkZ;
    end

    try
        memoryInfo = memory();
        availableBytes = memoryInfo.MaxPossibleArrayBytes;
    catch
        availableBytes = Inf;   % memory() is available only on Windows
    end
    memoryBudget = 0.8*availableBytes;
    % the depth stays a multiple of baseDepth (the 3D block grid); a depth beyond
    % the level is one slab of the whole level
    numTerms = numel(depthTerms);
    slabDepth = lcmOfTerms(depthTerms(1:numTerms));
    while estimateBytes(min(depth, slabDepth)) > memoryBudget && numTerms > 1
        numTerms = numTerms - 1;
        slabDepth = lcmOfTerms(depthTerms(1:numTerms));
    end
    while estimateBytes(min(depth, slabDepth)) > memoryBudget && slabDepth > baseDepth
        slabDepth = slabDepth - baseDepth;
    end
    slabDepth = min(depth, slabDepth);
    if estimateBytes(slabDepth) > memoryBudget && ~isempty(predictOpt.pwb)
        selection = uiconfirm(obj.view.gui, ...
            sprintf(['Predicting %s at level %d needs about %.1f GB of memory even with the smallest slab ' ...
            '(%d slice(s) of %d x %d pixels), while %.1f GB is available.\n\n' ...
            'Select a coarser level (a larger number) or continue at your own risk'], ...
            predictOpt.fn, level, estimateBytes(slabDepth)/1e9, slabDepth, width, height, availableBytes/1e9), ...
            'Not enough memory', 'Options', {'Continue', 'Cancel'}, ...
            'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
        if strcmp(selection, 'Cancel'); cancelled = true; return; end
    end
    slabStarts = 1:slabDepth:depth;
    slabEnds = min(depth, slabStarts + slabDepth - 1);
    numSlabs = numel(slabStarts);
    slabIndex = 0;

    % --- resume: what an interrupted run has already written ---------------
    recordFile = controllers.MibDeep.PredictionRecordFile;
    fingerprint = predictionFingerprint();
    resumeModel = writeModel && isfield(predictOpt, 'resumeModel') && predictOpt.resumeModel;
    resumeScores = writeScores && isfield(predictOpt, 'resumeScores') && predictOpt.resumeScores;
    modelDoneSlices = 0;
    if resumeModel
        modelDoneSlices = readModelRecord();   % errors when the store was predicted with other settings
    end
    % slices written to every output that is not the score store; the score store
    % keeps its own record (Zarr3Saver.saveStreamResumable) and asks for its first
    % missing slice. TIF files and the gathered formats always start from slice 1.
    doneSlices = depth;
    if writeModel; doneSlices = modelDoneSlices; end
    if writeTif || predictOpt.keepLabels || predictOpt.keepScores; doneSlices = 0; end

    fprintf('DeepMIB: %s, level %d (%d x %d x %d), predicting in %d slab(s) of %d slice(s)\n', ...
        predictOpt.fn, level, width, height, depth, numSlabs, slabDepth);
    if resumeModel
        fprintf('DeepMIB: %s, resuming: the model store holds slices 1-%d of %d\n', predictOpt.fn, modelDoneSlices, depth);
    end
    if resumeScores
        fprintf('DeepMIB: %s, resuming the score store from its first missing slice\n', predictOpt.fn);
    end
    storeTimer = tic;
    slabsPredicted = 0;

    % --- predict -----------------------------------------------------------
    levelArray = deepmib.readZarrSlab([], storeInfo, level);
    labelsStore = [];
    tifStarted = false;
    cancelRequested = false;    % set by predictNextSlab: inside the saver a cancel arrives as a task error
    slabError = [];             % the original error of predictNextSlab, which the saver wraps
    scoreMarkerWritten = resumeScores;
    try
        if writeModel
            [labelsStore, predictedLevel] = obj.createModelStore(predictOpt.modelStorePath, storeInfo.pyramid, ...
                levelSize, predictOpt.zarrFormat, predictOpt.modelMaterialNames, predictOpt.modelMaterialColors, resumeModel);
            if ~resumeModel; writeRecord(predictOpt.modelStorePath, 0); end
        end
        if writeScores
            provider = deepmib.PredictionSliceProvider([height, width, depth, numScoreClasses, 1], 'uint8', @predictNextSlab);
            scoreOptions = predictOpt.scoreSaveOpt;
            scoreOptions.silent = true;
            scoreOptions.showWaitbar = false;
            scoreOptions.Resume = resumeScores;
            scoreOptions.SourceFingerprint = fingerprint;
            io.savers.Zarr3Saver().saveStreamResumable(provider, predictOpt.scoreMetadata, predictOpt.scoreStorePath, scoreOptions, []);
            scoreGroup = io.zarr.Group(predictOpt.scoreStorePath);
            scoreAttributes = scoreGroup.getAttributes();
            scoreAttributes.mibPredictionScores = struct('classNames', {predictOpt.scoreClassNames});   % keeps the store out of the next prediction
            scoreGroup.setAttributes(scoreAttributes);
        else
            slabIndex = sum(slabEnds <= doneSlices);    % slabs every output already holds
            while slabIndex < numSlabs
                predictNextSlab(slabStarts(slabIndex + 1));
            end
        end
        if writeModel
            labelsStore.closeStore();   % persists the level map and the material names
            deleteRecord(predictOpt.modelStorePath);
        end
        if writeScores; deleteRecord(predictOpt.scoreStorePath); end
        fprintf('DeepMIB: %s, level %d predicted, %d of %d slab(s) in this run, elapsed time %s\n', ...
            predictOpt.fn, level, slabsPredicted, numSlabs, elapsedText(toc(storeTimer)));
    catch err
        if ~isempty(slabError); err = slabError; end    % not the wrapper of the saver
        cancelled = cancelRequested || strcmp(err.identifier, cancelId);
        if cancelled
            fprintf('DeepMIB: %s, cancelled at slab %d of %d after %s\n', ...
                predictOpt.fn, slabIndex, numSlabs, elapsedText(toc(storeTimer)));
        else
            fprintf('DeepMIB: %s, stopped at slab %d of %d (slices %d-%d) after %s: %s\n', ...
                predictOpt.fn, slabIndex, numSlabs, slabStarts(max(1, slabIndex)), ...
                slabEnds(max(1, slabIndex)), elapsedText(toc(storeTimer)), err.message);
        end
        % the zarr stores are kept to be resumed; a TIF file is written again from slice 1
        if writeTif && isfile(predictOpt.tifFilename); delete(predictOpt.tifFilename); end
        keptStores = {};
        if writeModel && isfile(fullfile(predictOpt.modelStorePath, recordFile))
            keptStores{end+1} = predictOpt.modelStorePath;
        end
        if writeScores && isfolder(predictOpt.scoreStorePath); keptStores{end+1} = predictOpt.scoreStorePath; end
        if ~isempty(keptStores)
            fprintf(['DeepMIB: the partial stores are kept; press Predict with the same settings and choose ' ...
                '"Resume" to continue, or delete them:\n%s\n'], strjoin(keptStores, newline));
        end
        outputLabels = [];
        scoreImg = [];
        if cancelled; return; end
        rethrow(err);
    end

    function [slabScores, zFirst] = predictNextSlab(requestedZ)
        % predict the slab after the current one (skipping those all outputs hold, up
        % to the one with requestedZ), write it to the outputs, return its scores and
        % its first slice
        try
            [slabScores, zFirst] = predictSlab(requestedZ);
        catch slabErr
            slabError = slabErr;
            rethrow(slabErr);
        end
    end

    function [slabScores, zFirst] = predictSlab(requestedZ)
        if ~isempty(predictOpt.pwb) && predictOpt.pwb.CancelRequested
            cancelRequested = true;
            error(cancelId, 'Cancelled');
        end
        if writeScores && ~scoreMarkerWritten
            % the saver has created the store: mark it as an unfinished prediction
            writeRecord(predictOpt.scoreStorePath, NaN);
            scoreMarkerWritten = true;
        end
        slabIndex = slabIndex + 1;
        while slabIndex < numSlabs && slabEnds(slabIndex) <= doneSlices && slabEnds(slabIndex) < requestedZ
            slabIndex = slabIndex + 1;
        end
        zFirst = slabStarts(slabIndex);
        zLast = min(depth, zFirst + slabDepth - 1);
        readFirst = max(1, zFirst - halo);
        readLast = min(depth, zLast + halo);
        vol = deepmib.readZarrSlab(levelArray, storeInfo, level, [readFirst readLast]);   % [y x z c]

        if downsampleFactor ~= 1    % XY only, 2D and 2.5D
            resizeOptions = struct('imgType', '4D', 'showWaitbar', false, ...
                'width', round(width/downsampleFactor), 'height', round(height/downsampleFactor), ...
                'depth', size(vol, 3));
            vol = utils.resizeImage3d(vol, [], resizeOptions);
        end

        slabLength = zLast - zFirst + 1;
        slabLabels = [];
        slabScores = [];
        if dataDimension == 3
            [slabLabels, slabScores, isCancelled] = obj.processBlocksBlockedImage(vol, NaN, predictOpt.net, ...
                predictOpt.inputPatchSize, predictOpt.outputPatchSize, predictOpt.blockSize, predictOpt.padShift, ...
                dataDimension, predictOpt.patchwiseWorkflowSwitch, false, ...
                predictOpt.classNames, predictOpt.generateScoreFiles, predictOpt.executionEnvironment, predictOpt.fn, predictOpt.pwb);
            if isCancelled; error(cancelId, 'Cancelled'); end
            coreSlices = (zFirst - readFirst) + (1:slabLength);
            slabLabels = slabLabels(:, :, coreSlices);
            if predictOpt.generateScoreFiles > 0; slabScores = slabScores(:, :, :, coreSlices); end
        else
            for z = zFirst:zLast
                if dataDimension == 2
                    unitVol = squeeze(vol(:, :, z - readFirst + 1, :));    % [y x c]
                else    % 2.5D: the slice with its neighbours, mirrored at the ends of the level
                    contextSlices = max(1, z - contextHalf):min(depth, z + contextHalf);
                    unitVol = vol(:, :, contextSlices - readFirst + 1, :);
                    unitVol = padarray(unitVol, [0, 0, max(0, contextHalf - z + 1)], 'symmetric', 'pre');
                    unitVol = padarray(unitVol, [0, 0, max(0, z + contextHalf - depth)], 'symmetric', 'post');
                end
                [sliceLabels, sliceScores, isCancelled] = obj.processBlocksBlockedImage(unitVol, z, predictOpt.net, ...
                    predictOpt.inputPatchSize, predictOpt.outputPatchSize, predictOpt.blockSize, predictOpt.padShift, ...
                    dataDimension, predictOpt.patchwiseWorkflowSwitch, false, ...
                    predictOpt.classNames, predictOpt.generateScoreFiles, predictOpt.executionEnvironment, predictOpt.fn, predictOpt.pwb);
                if isCancelled; error(cancelId, 'Cancelled'); end
                if isempty(slabLabels)
                    slabLabels = zeros([size(sliceLabels, 1), size(sliceLabels, 2), slabLength], 'uint8');
                    if predictOpt.generateScoreFiles > 0
                        slabScores = zeros([size(sliceScores, 1), size(sliceScores, 2), size(sliceScores, 3), slabLength], class(sliceScores));
                    end
                end
                slabLabels(:, :, z - zFirst + 1) = sliceLabels(:, :, 1);
                if predictOpt.generateScoreFiles > 0; slabScores(:, :, :, z - zFirst + 1) = sliceScores; end
            end
        end
        clear vol;

        if downsampleFactor ~= 1    % back to the size of the level
            resizeOptions = struct('imgType', '3D', 'showWaitbar', false, 'method', 'nearest', ...
                'width', width, 'height', height, 'depth', slabLength);
            slabLabels = utils.resizeImage3d(slabLabels, [], resizeOptions);
            if numClasses == 2
                % smooth the models of 2 classes, as for images that are not zarr
                smoothOptions.SourceLayer = {'labels'};
                smoothOptions.FilterName = {'Gaussian'};
                smoothOptions.Mode3D = false;
                smoothOptions.Sigma = {downsampleFactor + 1};
                smoothOptions.HSize = num2str(downsampleFactor*2 + 1);
                smoothOptions.Padding = {'replicate'};
                smoothOptions.PaddingValue = {0};
                smoothOptions.FilterDomain = {'auto'};
                smoothOptions.showWaitbar = false;
                slabLabels = utils.doImageFiltering(slabLabels, smoothOptions);
            end
            if predictOpt.generateScoreFiles > 0    % [y x c z] -> [y x z c] for the resize
                resizeOptions.imgType = '4D';
                resizeOptions.method = 'bicubic';
                slabScores = permute(utils.resizeImage3d(permute(slabScores, [1 2 4 3]), [], resizeOptions), [1 2 4 3]);
            end
        end
        if predictOpt.generateScoreFiles > 0 && ~obj.ScoreExportOpt.IncludeExterior
            slabScores = slabScores(:, :, 2:end, :);
        end

        % --- outputs of the slab ---
        if writeModel
            obj.writeModelStoreSlab(labelsStore, slabLabels, predictedLevel, zFirst);
            % the record follows the data: slices 1..zLast are in the store (earlier
            % slabs were written in this run or are part of the resumed record)
            labelsStore.saveLevelMap();
            writeRecord(predictOpt.modelStorePath, zLast);
        end
        if writeTif
            for sliceId = 1:slabLength
                if ~tifStarted
                    imwrite(slabLabels(:, :, sliceId), predictOpt.tifFilename, 'tif', 'WriteMode', 'overwrite', ...
                        'Description', sprintf('DeepMIB segmentation: %s %s', obj.BatchOpt.Workflow{1}, obj.BatchOpt.Architecture{1}), ...
                        'Compression', predictOpt.tifCompression);
                    tifStarted = true;
                else
                    imwrite(slabLabels(:, :, sliceId), predictOpt.tifFilename, 'tif', 'WriteMode', 'append', ...
                        'Compression', predictOpt.tifCompression);
                end
            end
        end
        if predictOpt.keepLabels
            if isempty(outputLabels)
                outputLabels = zeros([size(slabLabels, 1), size(slabLabels, 2), depth], 'uint8');
            end
            outputLabels(:, :, zFirst:zLast) = slabLabels;
        end
        if predictOpt.keepScores
            if isempty(scoreImg)
                scoreImg = zeros([size(slabScores, 1), size(slabScores, 2), size(slabScores, 3), depth], class(slabScores));
            end
            scoreImg(:, :, :, zFirst:zLast) = slabScores;
        end

        if ~isempty(predictOpt.pwb)
            progress = (predictOpt.fileIndex - 1 + zLast/depth)/predictOpt.noFiles;
            secondsLeft = toc(predictOpt.startTime)/progress*(1 - progress);
            predictOpt.pwb.Value = min(1, progress);
            predictOpt.pwb.Message = sprintf('%s\nslices %d-%d of %d, ~%.0f:%.2d min left...', ...
                predictOpt.fn, zFirst, zLast, depth, floor(secondsLeft/60), mod(round(secondsLeft), 60));
        end
        slabsPredicted = slabsPredicted + 1;
    end

    function fingerprint = predictionFingerprint()
        % what the outputs were predicted from: a resume must find the same. Names
        % without folders and the size of the network file, so a run started on
        % another workstation (another drive letter for the share) can be resumed
        [~, imageName, imageExtension] = fileparts(char(storeInfo.groupPath));
        [~, networkName, networkExtension] = fileparts(char(obj.BatchOpt.NetworkFilename));
        networkInfo = dir(char(obj.BatchOpt.NetworkFilename));
        networkBytes = 0;
        if ~isempty(networkInfo); networkBytes = networkInfo(1).bytes; end
        fingerprint = struct('image', [imageName imageExtension], 'level', level, 'levelSize', levelSize, ...
            'network', [networkName networkExtension], 'networkBytes', networkBytes, ...
            'workflow', obj.BatchOpt.Workflow{1}, 'architecture', obj.BatchOpt.Architecture{1}, ...
            'padding', obj.BatchOpt.T_ConvolutionPadding{1}, ...
            'overlappingTiles', logical(obj.BatchOpt.P_OverlappingTiles), ...
            'overlapPercent', obj.BatchOpt.P_OverlappingTilesPercentage{1}, ...
            'extraPaddingPercent', obj.view.handles.P_ExtraPaddingPercentage.Value, ...
            'downsampleFactor', downsampleFactor, ...
            'dynamicMasking', logical(obj.BatchOpt.P_DynamicMasking), 'dynamicMaskOpt', [], ...
            'inputPatchSize', predictOpt.inputPatchSize, 'outputPatchSize', predictOpt.outputPatchSize, ...
            'blockSize', predictOpt.blockSize, 'padShift', predictOpt.padShift, ...
            'classNames', {cellstr(string(predictOpt.classNames(:)))}, ...
            'scoreFormat', predictOpt.generateScoreFiles, 'includeExterior', logical(obj.ScoreExportOpt.IncludeExterior));
        if fingerprint.dynamicMasking; fingerprint.dynamicMaskOpt = obj.DynamicMaskOpt; end
    end

    function finishedSlices = readModelRecord()
        % slices of an interrupted run that the model store holds
        recordPath = fullfile(predictOpt.modelStorePath, recordFile);
        if ~isfile(recordPath)
            error('MibDeep:predictZarrStore:cannotResume', ...
                'Cannot resume %s: it holds no record of an interrupted prediction', predictOpt.modelStorePath);
        end
        record = jsondecode(fileread(recordPath));
        if ~isfield(record, 'fingerprint') || ~isequal(record.fingerprint, jsondecode(jsonencode(fingerprint))) || ...
                ~isfield(record, 'modelDownsampleMethod') || ~strcmp(record.modelDownsampleMethod, obj.ZarrModelOpt.DownsampleMethod)
            error('MibDeep:predictZarrStore:cannotResume', ...
                ['Cannot resume %s: it was predicted from another image, level or network, or with other ' ...
                'prediction settings\n\nRestore the settings of the interrupted run, or choose "Overwrite" to predict it again'], ...
                predictOpt.modelStorePath);
        end
        finishedSlices = record.finishedSlices;
    end

    function writeRecord(storePath, finishedSlices)
        % the record of an unfinished prediction in the store; written to a temporary
        % file and moved, so a crash never leaves half a record
        recordPath = fullfile(storePath, recordFile);
        record = struct('fingerprint', fingerprint, 'finishedSlices', finishedSlices, ...
            'modelDownsampleMethod', obj.ZarrModelOpt.DownsampleMethod);   % how the coarser levels of a model store are made
        fileId = fopen([recordPath '.tmp'], 'w');
        fwrite(fileId, jsonencode(record), 'char');
        fclose(fileId);
        movefile([recordPath '.tmp'], recordPath, 'f');
    end

    function deleteRecord(storePath)
        if isfile(fullfile(storePath, recordFile)); delete(fullfile(storePath, recordFile)); end
    end

    function bytes = estimateBytes(slabSlices)
        % memory needed with slabs of slabSlices slices, see the docblock
        sliceVoxels = height*width;
        readSlices = min(depth, slabSlices + 2*halo);
        scoreSliceBytes = numScoreClasses*scoreBytes*(predictOpt.generateScoreFiles > 0);
        bytes = sliceVoxels*(readSlices*numColors*bytesPerPixel ...    % the slab with its halo
            + slabSlices*(3 + 2*scoreSliceBytes));                     % labels and their copy in setData63, scores
        if dataDimension == 3   % blockedImage copies of the slab: image, labels, scores
            bytes = bytes + sliceVoxels*readSlices*(numColors*bytesPerPixel + 2 + 2*numClasses*scoreBytes);
        else                    % one slice (with its context) through blockedImage, RGB for gray 2D
            bytes = bytes + sliceVoxels*((2*contextHalf + 1)*max(3, numColors)*bytesPerPixel*2 + 2 + 2*numClasses*scoreBytes);
        end
        if writeScores      % saveStream buffers about three write depths of score slices
            writeDepth = 16;
            if isfield(predictOpt.scoreSaveOpt, 'ChunkSize') && numel(predictOpt.scoreSaveOpt.ChunkSize) >= 3
                writeDepth = predictOpt.scoreSaveOpt.ChunkSize(3);
            end
            if isfield(predictOpt.scoreSaveOpt, 'ShardSize') && numel(predictOpt.scoreSaveOpt.ShardSize) >= 3
                writeDepth = writeDepth*predictOpt.scoreSaveOpt.ShardSize(3);
            end
            bytes = bytes + 3*min(depth, writeDepth)*sliceVoxels*numScoreClasses;
        end
        if predictOpt.keepLabels; bytes = bytes + sliceVoxels*depth; end
        if predictOpt.keepScores; bytes = bytes + sliceVoxels*depth*numScoreClasses*scoreBytes; end
    end
end

function text = elapsedText(seconds)
% elapsed time as h:mm:ss
text = sprintf('%d:%02d:%02d', floor(seconds/3600), floor(mod(seconds, 3600)/60), floor(mod(seconds, 60)));
end

function value = lcmOfTerms(terms)
% least common multiple of positive integers
value = 1;
for termIndex = 1:numel(terms)
    value = lcm(value, max(1, round(terms(termIndex))));
end
end
