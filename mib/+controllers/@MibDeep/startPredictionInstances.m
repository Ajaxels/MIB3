function startPredictionInstances(obj)
% STARTPREDICTIONINSTANCES - predict 2D instance segmentation (SOLOv2) datasets.
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
% The detection confidence threshold and the merge IoU/IoA thresholds are taken from
% obj.OverlapInstancesOpt (updateOverlapInstancesSettings).
% Instance prediction does not require preprocessing: images are read directly.

global mibInstanceIdCounter

% lazy init to cover instances created before this property was introduced
if isempty(obj.OverlapInstancesOpt)
    obj.OverlapInstancesOpt = struct('DetectionThreshold', 0.5, 'MergeIoU', 0.5, 'MergeIoA', 0.8);
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
    predictionImagesDir = fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images');
    if ~isfolder(predictionImagesDir)
        predictionImagesDir = obj.BatchOpt.OriginalPredictionImagesDir;
    end
    fnExtension = lower(['.' obj.BatchOpt.ImageFilenameExtension{1}]);
    imgDS = imageDatastore(predictionImagesDir, ...
        'FileExtensions', fnExtension, ...
        'IncludeSubfolders', false, ...
        'ReadFcn', @(fn)deepmib.storeLoadImages(fn, mibDeepStoreLoadImagesOpt));
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
if ~obj.BatchOpt.P_OverlappingTiles
    if strcmp(stitchingMode, 'IoU merge')
        % IoU merge needs an overlap band to compare detections across seams
        overlapPercentage = 5;
        warning('MibDeep:startPredictionInstances:noOverlap', ...
            'The "IoU merge" stitching requires overlapping tiles; a default %d%% overlap will be used', overlapPercentage);
    else
        overlapPercentage = 0;
    end
end
blockSize = [inputPatchSize(1), inputPatchSize(2)];
padShift = ceil(blockSize * overlapPercentage / 100);
blockSize = blockSize - padShift*2;     % core size (apply adds the border back)
if any(blockSize < 16)
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf(['The selected overlap percentage (%d%%) leaves a tile core of only [%d x %d] pixels\n' ...
        'for the input patch size [%d x %d].\n\nPlease decrease the overlap percentage!'], ...
        overlapPercentage, blockSize(1), blockSize(2), inputPatchSize(1), inputPatchSize(2)), ...
        'Overlap too large');
    if obj.BatchOpt.showWaitbar; close(pwb); end
    return;
end
predictionThreshold = obj.OverlapInstancesOpt.DetectionThreshold;

t1 = tic;
noFiles = numel(imgDS.Files);
id = 1;
while hasdata(imgDS)
    if obj.BatchOpt.showWaitbar && pwb.CancelRequested; close(pwb); return; end
    % io.loadImagesWrapper always returns [height, width, depth, color, time], so the
    % depth is read explicitly instead of guessing it from a squeezed array (where a
    % grayscale z-stack and an RGB 2D image are indistinguishable)
    vol = read(imgDS);
    [imgHeight, imgWidth, imgDepth, ~, noTimePoints] = size(vol, 1:5);
    [~, fn] = fileparts(imgDS.Files{id});
    if noTimePoints > 1
        warning('MibDeep:startPredictionInstances:timePointsIgnored', ...
            '%s contains %d time points, only the first one is predicted', fn, noTimePoints);
    end

    outputLabels = zeros([imgHeight, imgWidth, imgDepth], 'uint32');
    maxInstancesPerSlice = 0;
    totalInstances = 0;
    for sliceId = 1:imgDepth
        if obj.BatchOpt.showWaitbar && pwb.CancelRequested; close(pwb); return; end
        sliceImg = squeeze(vol(:, :, sliceId, :, 1));    % [height, width, color]
        if size(sliceImg, 3) == 1            % dynamically convert grayscale to RGB
            sliceImg = repmat(sliceImg, [1, 1, 3]);
        end

        % tile the slice and segment each tile, stitching instances across the seams
        try
            switch stitchingMode
                case 'IoU merge'
                    % keep all per-tile detections and merge those agreeing in the overlap band
                    mergeOptions.coreSize = blockSize;
                    mergeOptions.borderSize = padShift;
                    mergeOptions.threshold = predictionThreshold;
                    mergeOptions.executionEnvironment = executionEnvironment;
                    mergeOptions.iouThreshold = obj.OverlapInstancesOpt.MergeIoU;
                    mergeOptions.ioaThreshold = obj.OverlapInstancesOpt.MergeIoA;
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
            end
        catch err
            utils.dlgs.showErrorDialog(obj.view.gui, err, 'Instance prediction error');
            if obj.BatchOpt.showWaitbar; close(pwb); end
            return;
        end

        % relabel to a contiguous 1..N index range within this slice; the indices are
        % deliberately not made unique across the stack - utils.stitchInstances2Dto3D
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
end
