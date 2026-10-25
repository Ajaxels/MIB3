function startPredictionInstances(obj)
% STARTPREDICTIONINSTANCES - predict 2D instance segmentation (SOLOv2 or StarDist) datasets.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.startPredictionInstances()
%
% Runs the trained SOLOv2 network over the prediction images using the blockedImage
% overlap-tile strategy (so large / whole-slide images are processed at native resolution
% instead of being downscaled to the network input). For each image, every detected object
% instance is saved as a unique integer index in a MIB model (background 0).
%
% An image that is no larger than the network input (``inputPatchSize``) is passed to
% ``segmentObjects`` **whole**: it needs no tiles, so no stitching mode is applied and the
% tiling settings (P_OverlappingTiles / P_OverlappingTilesPercentage) are neither used nor
% validated for it.
%
% Both 2D images and z-stacks are accepted, as in the 2D Semantic workflow:
%
%   - a 2D file is predicted directly and saved as a 2D model;
%   - a file with several z-slices is predicted slice-by-slice and saved as a single
%     3D model.
%
% The instance indices are contiguous 1..N **within each slice** and are not consistent
% between slices - linking them into 3D objects is the job of the "Merge 2D to 3D"
% button (mergeInstancesTo3D), which ignores the input indices anyway.
%
% Cross-tile stitching mode is selected with BatchOpt.P_OverlapInstancesMode:
%
%   - 'Centroid in core' (see deepmib.segmentBlockedImageInstances) - objects are emitted
%     by the tile that owns their centroid, requiring the overlap
%     (P_OverlappingTilesPercentage) to be >= the largest object;
%   - 'IoU merge' (see deepmib.segmentImageInstancesIoUMerge) - all per-tile detections are
%     kept and merged across seams when their masks agree inside the shared overlap band;
%     works for objects larger than the overlap.
%
% Both modes finish by splitting every index into its connected components
% (utils.instances.splitDisconnected), so two objects that are separated in the image never
% share an instance index.
%
% The detection confidence threshold, the merge IoU/IoA thresholds and the minimal object
% area are taken from obj.OverlapInstancesOpt (updateOverlapInstancesSettings).
% Instance prediction does not require preprocessing: images are read directly.
%
% **StarDist networks** (the network file holds ``StarDistConfig``, see startTrainingStarDist;
% the file decides, not the Architecture selected in the GUI) segment every slice with
% deepmib.stardist: normalizeImage (percentiles of the slice) -> predictMaps (tiles of
% ``obj.StarDistOpt.PredictTileSize`` whose overlap covers the receptive field, so the maps are
% seamless) -> nms on the whole slice -> polygonsToLabel. Nothing is stitched, so
% P_OverlapInstancesMode, P_OverlappingTiles and obj.OverlapInstancesOpt are not used, and
% no index is split into connected components (as in StarDist, a polygon partly covered by a
% higher-scoring one keeps its remaining pixels). Images keep their channel count, which must
% equal the ``nChannelIn`` of the network. The thresholds are those stored in the network
% (tuned after training) unless ``obj.StarDistOpt.PredictThresholds`` is ``'Custom'``.
%
% "Downsample factor for images" (``BatchOpt.P_ImageDownsamplingFactor``, values below 1
% allowed for StarDist, see selectArchitecture) gives StarDist the scale
% ``1 / factor``. With a scale other than 1 the normalised slice is zoomed to
% ``round(size * scale)`` as ``scipy.ndimage.zoom`` with order 1 (linear, corner pixels aligned,
% no antialiasing), and the kept polygon centres and ray lengths are divided by the scale before
% they are drawn at the original size, as StarDist ``predict_instances(img, scale=...)``
% (identical labels for scales 0.5-2). This lets
% a network find objects of another size than in its training images; ``2D_versatile_fluo``
% was trained on nuclei with a median equivalent diameter of 21 px (half of them 13-28 px, 90%
% 7-50 px; StarDist's DSB2018 subset, 447 images, measured 2026-10-24), hence the advice
% "factor = diameter of your nuclei / 20" in the dialogs and docs. SOLOv2 ignores the factor
% (the field is disabled for it).
%
% The whole-slice maps are kept in memory: ``(1 + nRays)`` single-precision values per grid cell,
% about 0.5 GB for a 16k x 16k slice with 32 rays and grid 2, times the square of the scale
% factor.
%
% **OME-Zarr images** (``BatchOpt.ImageFilenameExtension = 'ZARR'``) are predicted
% from one pyramid level, ``BatchOpt.BioformatsIndex`` (1 = full resolution),
% loaded whole into memory; the stores are listed and checked by
% ``checkZarrStores`` before the run, as in ``startPredictionBlockedImage``.
% With the "MIB Model format" output the ``.model`` file has the size of that
% level. With "Zarr3 (BigData model)" each image gets a uint16 BigData instance
% model store (``writeModelStore``, at most 16383 objects per slice) that mirrors
% the pyramid of the source store, at the destination confirmed by
% ``selectModelStoreDestination``. Its objects keep the per-slice numbering
% (``objects3D = false``); "Merge 2D to 3D" reads only ``.model`` files.

global mibInstanceIdCounter

% lazy init to cover instances created before this property was introduced
if isempty(obj.OverlapInstancesOpt)
    obj.OverlapInstancesOpt = struct('DetectionThreshold', 0.5, 'MergeIoU', 0.5, 'MergeIoA', 0.8, 'MinSplitArea', 100);
end
if ~isfield(obj.OverlapInstancesOpt, 'MinSplitArea')     % configs saved before this field existed
    obj.OverlapInstancesOpt.MinSplitArea = 100;
end

msg = sprintf(['!!! Warning !!!\nYou are going to start instance segmentation prediction.\n' ...
    'Confirm that your images are located under\n\n%s\n\n- Images\n'], ...
    obj.BatchOpt.OriginalPredictionImagesDir);
selection = uiconfirm(obj.view.gui, ...
    msg, 'Instance prediction', ...
    'Options', {'Confirm', 'Cancel'}, ...
    'DefaultOption', 1, 'CancelOption', 2, ...
    'Icon', 'warning');
if strcmp(selection, 'Cancel'); return; end

% check that the network file is present
if exist(obj.BatchOpt.NetworkFilename, 'file') ~= 2
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf('The network file was not found:\n\n%s', obj.BatchOpt.NetworkFilename), ...
        'Missing network');
    return;
end

% OME-Zarr images: each store is predicted from one pyramid level loaded into
% memory; check every store before anything is deleted or the network is loaded
zarrInput = strcmp(obj.BatchOpt.ImageFilenameExtension{1}, 'ZARR');
zarrOutput = strcmp(obj.BatchOpt.P_ModelFiles{1}, 'Zarr3 (BigData model)');
if zarrInput
    [zarrList, zarrStores, cancelled] = obj.checkZarrStores();
    if cancelled; return; end
    if zarrOutput
        [storePaths, zarrFormat, cancelled] = obj.selectModelStoreDestination(zarrList);
        if cancelled; return; end
        writtenStores = {};
    end
end

if obj.BatchOpt.showWaitbar
    pwb = uiprogressdlg(obj.view.gui, ...
        'Title', 'Predicting instances', ...
        'Message', 'Creating image store for prediction...', ...
        'Cancelable', true, 'Value', 0);
end

% prepare output directories
warning('off', 'MATLAB:MKDIR:DirectoryExists');
outputModelsDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels');
if isfolder(outputModelsDir)
    outputList = dir(fullfile(outputModelsDir, '*.model'));
    if ~isempty(outputList)
        selection = uiconfirm(obj.view.gui, ...
            sprintf('!!! Warning !!!\n\nThe destination folder\n- PredictionImages/ResultsModels\n\nis not empty!\n\nEmpty it and start prediction?'), ...
            'Destination folder is not empty', ...
            'Options', {'Empty and continue', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
        if strcmp(selection, 'Cancel'); if obj.BatchOpt.showWaitbar; close(pwb); end; return; end
        delete(fullfile(outputModelsDir, '*'));
    end
end
mkdir(outputModelsDir);

% prepare options for loading of images
mibDeepStoreLoadImagesOpt.mibBioformatsCheck = obj.BatchOpt.Bioformats;
mibDeepStoreLoadImagesOpt.BioFormatsIndices = obj.BatchOpt.BioformatsIndex{1};
mibDeepStoreLoadImagesOpt.Workflow = obj.BatchOpt.Workflow{1};

% make a datastore for the prediction images (read raw images directly)
try
    if zarrInput
        % zarr stores are folders, imageDatastore can not list them; each store is
        % read at the selected level, from the image group resolved by checkZarrStores
        mibDeepStoreLoadImagesOpt.ZarrLevel = obj.BatchOpt.BioformatsIndex{1};
        zarrReadOptions = repmat(mibDeepStoreLoadImagesOpt, [numel(zarrList), 1]);
        for fileId = 1:numel(zarrList)
            if ~strcmp(zarrStores(fileId).groupPath, zarrList{fileId})
                zarrReadOptions(fileId).ZarrGroupPath = zarrStores(fileId).groupPath;
            end
        end
        imgDS = transform(arrayDatastore((1:numel(zarrList))', 'OutputType', 'same'), ...
            @(fileId) deepmib.storeLoadImages(zarrList{fileId}, zarrReadOptions(fileId)));
        predictionFiles = zarrList;
    else
        predictionImagesDir = fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images');
        if ~isfolder(predictionImagesDir)
            predictionImagesDir = obj.BatchOpt.OriginalPredictionImagesDir;
        end
        fnExtension = lower(['.' obj.BatchOpt.ImageFilenameExtension{1}]);
        imgDS = imageDatastore(predictionImagesDir, ...
            'FileExtensions', fnExtension, ...
            'IncludeSubfolders', false, ...
            'ReadFcn', @(fn)deepmib.storeLoadImages(fn, mibDeepStoreLoadImagesOpt));
        predictionFiles = imgDS.Files;
    end
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Missing files');
    if obj.BatchOpt.showWaitbar; close(pwb); end
    return;
end

if obj.BatchOpt.showWaitbar
    if pwb.CancelRequested; close(pwb); return; end
    pwb.Message = 'Loading network...';
end
% loads 'net', 'classNames', 'classColors', 'inputPatchSize', 'BatchOpt', ...
res = load(obj.BatchOpt.NetworkFilename, '-mat');
net = res.net;
inputPatchSize = res.inputPatchSize;

% a StarDist network file carries StarDistConfig; its thresholds were tuned after training
isStarDist = isfield(res, 'StarDistConfig');
if isStarDist
    starDistConfig = deepmib.stardist.defaultConfig(res.StarDistConfig);
    if strcmp(obj.StarDistOpt.PredictThresholds, 'Custom')
        starDistProbThresh = obj.StarDistOpt.ProbThresh;
        starDistNmsThresh = obj.StarDistOpt.NmsThresh;
    else
        starDistProbThresh = starDistConfig.probThresh;
        starDistNmsThresh = starDistConfig.nmsThresh;
    end
    starDistScale = 1 / obj.BatchOpt.P_ImageDownsamplingFactor{1};
end

% select gpu or cpu for prediction and define executionEnvironment
selectedIndex = find(ismember(obj.view.Figure.GPUDropDown.Items, obj.view.Figure.GPUDropDown.Value));
switch obj.view.Figure.GPUDropDown.Value
    case 'CPU only'
        if numel(obj.view.Figure.GPUDropDown.Items) > 2     % i.e. GPU is present
            gpuDevice([]);  % CPU only mode
        end
        executionEnvironment = 'cpu';
    case {'Multi-GPU', 'Parallel'}
        executionEnvironment = 'auto';
    otherwise
        gpuDevice(selectedIndex);   % choose selected GPU device
        executionEnvironment = 'gpu';
end

% define the tile (block) size and overlap for the blockedImage strategy
stitchingMode = obj.BatchOpt.P_OverlapInstancesMode{1};     % 'Centroid in core' or 'IoU merge'
overlapPercentage = obj.BatchOpt.P_OverlappingTilesPercentage{1};
overlapDefaulted = false;
if ~obj.BatchOpt.P_OverlappingTiles
    if strcmp(stitchingMode, 'IoU merge')
        % IoU merge needs an overlap band to compare detections across seams
        overlapPercentage = 5;
        overlapDefaulted = true;
    else
        overlapPercentage = 0;
    end
end
blockSize = [inputPatchSize(1), inputPatchSize(2)];
padShift = ceil(blockSize * overlapPercentage / 100);
blockSize = blockSize - padShift*2;     % core size (apply adds the border back)
% Neither the defaulted-overlap warning nor the core-too-small error may fire for a run
% whose images all fit the network input: such images are segmented whole and the tiling
% settings are never used, so complaining about them is noise (and the error would refuse
% a run that has nothing to refuse). Both are deferred to the first slice actually tiled.
tilingSettingsChecked = false;
predictionThreshold = obj.OverlapInstancesOpt.DetectionThreshold;

t1 = tic;
noFiles = numel(predictionFiles);
id = 1;
while hasdata(imgDS)
    if obj.BatchOpt.showWaitbar && pwb.CancelRequested; close(pwb); return; end
    % io.loadImagesWrapper always returns [height, width, depth, color, time], so the
    % depth is read explicitly instead of guessing it from a squeezed array (where a
    % grayscale z-stack and an RGB 2D image are indistinguishable)
    vol = read(imgDS);
    [imgHeight, imgWidth, imgDepth, ~, noTimePoints] = size(vol, 1:5);
    [~, fn] = fileparts(predictionFiles{id});
    if zarrInput; fn = regexprep(fn, '\.ome$', '', 'ignorecase'); end   % 'name.ome.zarr' -> 'name'
    if noTimePoints > 1
        warning('MibDeep:startPredictionInstances:timePointsIgnored', ...
            '%s contains %d time points, only the first one is predicted', fn, noTimePoints);
    end

    % an image no larger than the network input is passed to segmentObjects whole: tiling
    % it would only invent seams to stitch back together, and the tile grid would pad the
    % image up to the core size, feeding the network context that is not in the data
    fitsInOnePatch = imgHeight <= inputPatchSize(1) && imgWidth <= inputPatchSize(2);

    if isStarDist && size(vol, 4) ~= starDistConfig.nChannelIn
        utils.dlgs.showErrorDialog(obj.view.gui, sprintf(['%s has %d color channel(s), while the StarDist network ' ...
            'expects %d.\n\nPredict images with %d channel(s) or train a network for these images.'], ...
            fn, size(vol, 4), starDistConfig.nChannelIn, starDistConfig.nChannelIn), 'Wrong number of colors');
        if obj.BatchOpt.showWaitbar; close(pwb); end
        return;
    end

    outputLabels = zeros([imgHeight, imgWidth, imgDepth], 'uint32');
    maxInstancesPerSlice = 0;
    totalInstances = 0;
    for sliceId = 1:imgDepth
        if obj.BatchOpt.showWaitbar && pwb.CancelRequested; close(pwb); return; end
        sliceImg = squeeze(vol(:, :, sliceId, :, 1));    % [height, width, color]
        if size(sliceImg, 3) == 1 && ~isStarDist     % SOLOv2 expects RGB, StarDist the native channels
            sliceImg = repmat(sliceImg, [1, 1, 3]);
        end

        % tile the slice and segment each tile, stitching instances across the seams
        try
            if isStarDist
                % StarDist: the dense maps are tiled with enough overlap to be seamless, and
                % the objects are found once on the whole slice, so nothing is stitched
                normalizedSlice = deepmib.stardist.normalizeImage(sliceImg, starDistConfig.normalizePercentiles);
                if starDistScale ~= 1
                    % as StarDist predict_instances(scale=...): zoom as scipy.ndimage.zoom
                    % with order 1 (corner pixels aligned, linear, no antialiasing)
                    scaledSize = max(1, round([imgHeight, imgWidth] * starDistScale));
                    rowQuery = (0:scaledSize(1)-1) * (imgHeight-1) / max(1, scaledSize(1)-1);
                    colQuery = (0:scaledSize(2)-1) * (imgWidth-1) / max(1, scaledSize(2)-1);
                    scaledSlice = zeros([scaledSize, size(normalizedSlice, 3)], 'single');
                    for channelId = 1:size(normalizedSlice, 3)
                        interpolant = griddedInterpolant({0:imgHeight-1, 0:imgWidth-1}, ...
                            double(normalizedSlice(:, :, channelId)), 'linear');
                        scaledSlice(:, :, channelId) = interpolant({rowQuery, colQuery});
                    end
                    normalizedSlice = scaledSlice;
                end
                [probMap, distMap] = deepmib.stardist.predictMaps(net, normalizedSlice, starDistConfig, ...
                    struct('tileSize', [1 1] * obj.StarDistOpt.PredictTileSize, 'executionEnvironment', executionEnvironment));
                [points, scores, rayDist] = deepmib.stardist.nms(probMap, distMap, starDistConfig.grid, ...
                    starDistProbThresh, starDistNmsThresh);
                % polygons found on the zoomed image are drawn at the original size
                sliceLabels = deepmib.stardist.polygonsToLabel(points / starDistScale, rayDist / starDistScale, ...
                    scores, [imgHeight, imgWidth]);
            elseif fitsInOnePatch
                % no tiles, no seams, no stitching: one segmentObjects call on the slice
                [masks, ~, scores] = segmentObjects(net, sliceImg, ...
                    'Threshold', predictionThreshold, ...
                    'SelectStrongest', true, ...
                    'ExecutionEnvironment', executionEnvironment);
                sliceLabels = zeros([imgHeight, imgWidth], 'uint32');
                if ~isempty(scores)
                    % paint low scores first so higher-scored instances win on overlap,
                    % as deepmib.segmentBlockedImageInstances does
                    [~, paintOrder] = sort(scores, 'ascend');
                    instanceId = 0;
                    for maskId = paintOrder(:)'
                        instanceId = instanceId + 1;
                        sliceLabels(masks(:, :, maskId)) = instanceId;
                    end
                end
                % the repair both stitching modes end with, needed here too: a single
                % detection whose mask covers two separate objects must not give them
                % one index
                sliceLabels = utils.instances.splitDisconnected(sliceLabels, ...
                    struct('connectivity', 8, 'minObjectPixels', obj.OverlapInstancesOpt.MinSplitArea));
            else
                if ~tilingSettingsChecked
                    % first slice that is genuinely tiled - only now do the tiling settings matter
                    if any(blockSize < 16)
                        utils.dlgs.showErrorDialog(obj.view.gui, ...
                            sprintf(['The selected overlap percentage (%d%%) leaves a tile core of only [%d x %d] pixels\n' ...
                            'for the input patch size [%d x %d].\n\nPlease decrease the overlap percentage!'], ...
                            overlapPercentage, blockSize(1), blockSize(2), inputPatchSize(1), inputPatchSize(2)), ...
                            'Overlap too large');
                        if obj.BatchOpt.showWaitbar; close(pwb); end
                        return;
                    end
                    if overlapDefaulted
                        warning('MibDeep:startPredictionInstances:noOverlap', ...
                            'The "IoU merge" stitching requires overlapping tiles; a default %d%% overlap will be used', overlapPercentage);
                    end
                    tilingSettingsChecked = true;
                end
                switch stitchingMode
                    case 'IoU merge'
                        % keep all per-tile detections and merge those agreeing in the overlap band
                        mergeOptions.coreSize = blockSize;
                        mergeOptions.borderSize = padShift;
                        mergeOptions.threshold = predictionThreshold;
                        mergeOptions.executionEnvironment = executionEnvironment;
                        mergeOptions.iouThreshold = obj.OverlapInstancesOpt.MergeIoU;
                        mergeOptions.ioaThreshold = obj.OverlapInstancesOpt.MergeIoA;
                        mergeOptions.minSplitArea = obj.OverlapInstancesOpt.MinSplitArea;
                        sliceLabels = deepmib.segmentImageInstancesIoUMerge(sliceImg, net, mergeOptions);
                    otherwise   % 'Centroid in core'
                        mibInstanceIdCounter = 0;   % reset the global unique-instance-ID counter for this slice
                        bim = blockedImage(sliceImg, 'Adapter', images.blocked.InMemory);
                        labelBim = apply(bim, ...
                            @(block, blockInfo) deepmib.segmentBlockedImageInstances(block, net, predictionThreshold, executionEnvironment), ...
                            'Adapter', images.blocked.InMemory, ...
                            'Level', 1, ...
                            'PadPartialBlocks', true, ...
                            'BlockSize', blockSize, ...
                            'BorderSize', padShift, ...
                            'PadMethod', 'symmetric', ...
                            'UseParallel', false, ...
                            'DisplayWaitbar', false);
                        sliceLabels = gather(labelBim, 'Level', 1);
                        % crop away the padding added for partial blocks
                        sliceLabels = sliceLabels(1:imgHeight, 1:imgWidth);
                        % same repair as pass 4 of the IoU merge: a single segmentObjects
                        % detection whose mask covers two neighbouring objects is emitted by
                        % the tile owning "its" centroid and would otherwise give both objects
                        % one index
                        sliceLabels = utils.instances.splitDisconnected(sliceLabels, ...
                            struct('connectivity', 8, 'minObjectPixels', obj.OverlapInstancesOpt.MinSplitArea));
                end
            end
        catch err
            utils.dlgs.showErrorDialog(obj.view.gui, err, 'Instance prediction error');
            if obj.BatchOpt.showWaitbar; close(pwb); end
            return;
        end

        % relabel to a contiguous 1..N index range within this slice; the indices are
        % deliberately not made unique across the stack - utils.instances.stitch2Dto3D
        % relabels every slice internally, and a per-slice range keeps the model type small
        uniqueIds = unique(sliceLabels(sliceLabels > 0));
        numInstances = numel(uniqueIds);
        if numInstances > 0
            remap = zeros(double(max(uniqueIds))+1, 1, 'uint32');
            remap(uniqueIds+1) = uint32(1:numInstances);
            sliceLabels = remap(uint32(sliceLabels)+1);
        end
        outputLabels(:, :, sliceId) = sliceLabels;
        maxInstancesPerSlice = max(maxInstancesPerSlice, numInstances);
        totalInstances = totalInstances + numInstances;

        if obj.BatchOpt.showWaitbar && imgDepth > 1
            pwb.Message = sprintf('%s\nslice %d / %d, %d objects so far...', ...
                fn, sliceId, imgDepth, totalInstances);
            pwb.Value = min(1, (id - 1 + sliceId/imgDepth)/noFiles);
        end
    end
    if imgDepth == 1; outputLabels = outputLabels(:, :, 1); end   % 2D file -> 2D model

    if zarrOutput
        % a uint16 BigData instance model store (up to 16383 objects per slice)
        % mirroring the pyramid of the source store, see writeModelStore
        if obj.BatchOpt.showWaitbar && pwb.CancelRequested; close(pwb); return; end
        try
            obj.writeModelStore(outputLabels, storePaths{id}, zarrStores(id).pyramid, zarrFormat, {}, []);
        catch err
            if obj.BatchOpt.showWaitbar; close(pwb); end
            if ~isempty(writtenStores)
                fprintf('DeepMIB: model stores written before the error:\n%s\n', strjoin(writtenStores, newline));
            end
            utils.dlgs.showErrorDialog(obj.view.gui, err, 'Instance prediction error');
            return;
        end
        writtenStores{end+1} = storePaths{id}; %#ok<AGROW>
        fprintf('DeepMIB: model store written: %s\n', storePaths{id});
        id = id + 1;
        if obj.BatchOpt.showWaitbar; pwb.Value = min(1, (id-1)/noFiles); end
        continue;
    end

    % Instance models always use a large model type (>= 65535). Never type 63/255: the
    % packed small-material schemes (MibLabels63) cap materials/colours, which makes the
    % display colormap smaller than the label values and crashes labeloverlay in getRGBimage.
    if maxInstancesPerSlice <= 65535
        modelType = 65535;
        outputLabels = uint16(outputLabels);
    else
        modelType = 4294967295;
    end
    % >255-material MIB models use numeric material names carrying the index itself.
    % Always provide at least 2 materials: MIB's materials table (updateMaterialsTable)
    % renders two representative rows for >255 models and indexes materialNames{1:2},
    % so an empty or single-object prediction must still carry >= 2 entries.
    numMaterials = max(2, maxInstancesPerSlice);
    modelMaterialNames = arrayfun(@(x) num2str(x), (1:numMaterials)', 'UniformOutput', false);
    % one colour per material (cycled palette) so the colormap always covers all labels
    modelMaterialColors = obj.colormap255(mod((0:numMaterials-1), size(obj.colormap255, 1))+1, :);
    modelVariable = 'outputLabels';
    filename = fullfile(outputModelsDir, ['Labels_' fn '.model']);
    save(filename, 'outputLabels', 'modelMaterialNames', 'modelMaterialColors', ...
        'modelVariable', 'modelType', '-mat', '-v7.3');

    if obj.BatchOpt.showWaitbar
        if pwb.CancelRequested; close(pwb); return; end
        elapsedTime = toc(t1);
        timerValue = elapsedTime/id*(noFiles-id);
        if imgDepth > 1
            objectsInfo = sprintf('%d objects in %d slices', totalInstances, imgDepth);
        else
            objectsInfo = sprintf('%d objects', totalInstances);
        end
        pwb.Message = sprintf('%s (%s)\nHold on ~%.0f:%.2d mins left...', ...
            fn, objectsInfo, floor(timerValue/60), mod(round(timerValue), 60));
        pwb.Value = min(1, id/noFiles);
    end
    id = id + 1;
end
fprintf('Instance prediction finished: ');
toc(t1)

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfInferencedDeepNetworks = obj.mibModel.preferences.Users.Tiers.numberOfInferencedDeepNetworks + 1;
eventdata = core.ToggleEventData(4);
notify(obj.mibModel, 'UpdateUserScore', eventdata);

if obj.BatchOpt.showWaitbar; close(pwb); end

if zarrInput && zarrOutput && obj.BatchOpt.showWaitbar
    mgsOpt.MsgBoxOnly = true;
    mgsOpt.Icon = 'puffin_info';
    mgsOpt.WindowWidth = 560;
    mgsOpt.WindowHeight = 260;
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        sprintf(['%d model store(s) were written; in z-stacks the objects are numbered per slice.\n' ...
        'Open the image in the BigData mode and load its model store: Model -> Load model'], numel(writtenStores)), ...
        {}, {strjoin(writtenStores, newline)}, 'Prediction finished', mgsOpt);
end
end
