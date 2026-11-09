function Calculate(obj, batchModeSwitch)
% CALCULATE - Apply morphological operations to the image layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.Calculate()
%       obj.Calculate(batchModeSwitch)
%
% Input Arguments:
%   - **batchModeSwitch** - *(optional)* logical; when ``true`` skips backup
%     and ``returnBatchOpt`` call (default ``false``)
%
% A BigData dataset is processed by ``localCalculateBigData`` into a new
% OME-Zarr store instead; a Virtual dataset is refused (raised as
% ``controllers:MorphOpsImages:virtual`` when headless).
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MorphOpsImages.Calculate: triggered\n');
end
if nargin < 2; batchModeSwitch = false; end

obj.BatchOpt.id = obj.mibModel.getActiveId();
id = obj.BatchOpt.id;

if isempty(obj.view)
    parentFigure = obj.mibModel.mibGUI;     % [] headless: errors are raised
else
    parentFigure = obj.view.gui;
end

switch obj.mibModel.I{id}.datasetType
    case 'BigData'      % read-only image: processed into a new store
        localCalculateBigData(obj, parentFigure, batchModeSwitch);
        return;
    case 'Virtual'
        controllers.BigDataOptions.reportError(obj.mibModel, parentFigure, 'controllers:MorphOpsImages:virtual', ...
            sprintf('Morphological operations are not available in virtual mode.\nPlease switch to the memory-resident mode and try again.'), ...
            'Not implemented');
        return;
end

colorChannelIndex = find(ismember(obj.BatchOpt.ColorChannel{2}, obj.BatchOpt.ColorChannel(1))) - 1;
if colorChannelIndex == 0; colorChannelIndex = NaN; end     % 'All' -> NaN, all color channels in get/setData
se             = obj.getStrelElement();
hValue         = str2num(obj.BatchOpt.StrelSize); %#ok<ST2NM>
conn           = str2double(obj.BatchOpt.Connectivity{1});
multiplyFactor = obj.BatchOpt.Multiply{1};
smoothHSize    = obj.BatchOpt.SmoothHSize{1};
smoothSigma    = obj.BatchOpt.SmoothSigma{1};

depth = obj.mibModel.I{id}.image.depth;
time  = obj.mibModel.I{id}.image.time;

getDataOptions.roiId = -1;
getDataOptions.id    = id;

%% Backup - skip for 4D datasets (too large) and in batch mode
if ~batchModeSwitch
    backupOptions.id = id;
    switch obj.BatchOpt.DatasetType{1}
        case '2D, Slice'
            obj.mibModel.backup('image', 0, backupOptions);
        case '3D, Stack'
            obj.mibModel.backup('image', 1, backupOptions);
        case '4D, Dataset'
            if time == 1
                obj.mibModel.backup('image', 1, backupOptions);
            end
    end
end

%% Time range
switch obj.BatchOpt.DatasetType{1}
    case '2D, Slice'
        timeStart = obj.mibModel.I{id}.slices{5}(1);
        timeEnd   = timeStart;
        maxIndex  = 1;
    case '3D, Stack'
        timeStart = obj.mibModel.I{id}.slices{5}(1);
        timeEnd   = timeStart;
        maxIndex  = depth;
    case '4D, Dataset'
        timeStart = 1;
        timeEnd   = time;
        maxIndex  = depth * time;
end

if obj.BatchOpt.showWaitbar
    progressBar = uiprogressdlg(parentFigure, 'Value', 0, 'Cancelable', 'on', ...
        'Message', 'Please wait...', 'Title', [obj.BatchOpt.MorphOperation{1} ' filter']);
    progressStep = floor(maxIndex/20);
end

if smoothHSize > 0
    smoothFilter = fspecial('gaussian', smoothHSize, smoothSigma);
end

progressIndex = 0;

for t = timeStart:timeEnd
    getDataOptions.t = [t t];

    if strcmp(obj.BatchOpt.Mode{1}, '3D')
        %% 3D mode - operate on full volume
        imageData     = obj.mibModel.getData3D('image', t, 3, colorChannelIndex, getDataOptions);
        processedData = cell([numel(imageData), 1]);

        for roiIndex = 1:numel(imageData)
            processedData{roiIndex} = zeros(size(imageData{roiIndex}), class(imageData{roiIndex}));
            for colorChannel = 1:size(imageData{roiIndex}, 3)
                volumeSlice = squeeze(imageData{roiIndex}(:,:,colorChannel,:));
                switch obj.BatchOpt.MorphOperation{1}
                    case 'Bottom-hat filtering'
                        processedData{roiIndex}(:,:,colorChannel,:) = permute(imbothat(volumeSlice, se),            [1 2 4 3]);
                    case 'Clear border'
                        processedData{roiIndex}(:,:,colorChannel,:) = permute(imclearborder(volumeSlice, conn),     [1 2 4 3]);
                    case 'Morphological closing'
                        processedData{roiIndex}(:,:,colorChannel,:) = permute(imclose(volumeSlice, se),             [1 2 4 3]);
                    case 'Dilate image'
                        processedData{roiIndex}(:,:,colorChannel,:) = permute(imdilate(volumeSlice, se),            [1 2 4 3]);
                    case 'Erode image'
                        processedData{roiIndex}(:,:,colorChannel,:) = permute(imerode(volumeSlice, se),             [1 2 4 3]);
                    case 'Fill regions'
                        processedData{roiIndex}(:,:,colorChannel,:) = permute(imfill(volumeSlice),                  [1 2 4 3]);
                    case 'H-maxima transform'
                        processedData{roiIndex}(:,:,colorChannel,:) = permute(imhmax(volumeSlice, hValue(1), conn), [1 2 4 3]);
                    case 'H-minima transform'
                        processedData{roiIndex}(:,:,colorChannel,:) = permute(imhmin(volumeSlice, hValue(1), conn), [1 2 4 3]);
                    case 'Morphological opening'
                        processedData{roiIndex}(:,:,colorChannel,:) = permute(imopen(volumeSlice, se),              [1 2 4 3]);
                    case 'Top-hat filtering'
                        processedData{roiIndex}(:,:,colorChannel,:) = permute(imtophat(volumeSlice, se),            [1 2 4 3]);
                end
            end

            switch obj.BatchOpt.ActionToResult{1}
                case 'None'
                    processedData{roiIndex} = processedData{roiIndex} * multiplyFactor;
                case 'AddToImage'
                    processedData{roiIndex} = imageData{roiIndex} + processedData{roiIndex} * multiplyFactor;
                case 'SubtractFromImage'
                    processedData{roiIndex} = imageData{roiIndex} - processedData{roiIndex} * multiplyFactor;
            end
        end

        obj.mibModel.setData3D(processedData, 'image', t, 3, colorChannelIndex, getDataOptions);

        if obj.BatchOpt.showWaitbar && mod(progressIndex, progressStep) == 0
            progressIndex = progressIndex + depth;
            progressBar.Value = min(progressIndex / maxIndex, 1);
            progressBar.Message = sprintf('Doing %s slice %d of %d\nPlease wait...', obj.BatchOpt.MorphOperation{1}, progressIndex, maxIndex);
            if progressBar.CancelRequested
                delete(progressBar);
                return;
            end
        end

    else
        %% 2D mode - per-slice
        currentOrientation = obj.mibModel.I{id}.orientation;
        if strcmp(obj.BatchOpt.DatasetType{1}, '2D, Slice')
            startSlice = obj.mibModel.I{id}.slices{currentOrientation}(1);
            endSlice   = startSlice;
        else
            [~,~,endSlice,~,~] = obj.mibModel.I{id}.getDatasetDimensions('image', currentOrientation, []);
            startSlice = 1;
        end

        for sliceIndex = startSlice:endSlice
            imageData = obj.mibModel.getData2D('image', sliceIndex, [], colorChannelIndex, getDataOptions);

            processedData = cell([numel(imageData), 1]);
            for roiIndex = 1:numel(imageData)
                processedData{roiIndex} = zeros(size(imageData{roiIndex}), class(imageData{roiIndex}));
                for colorChannel = 1:size(imageData{roiIndex}, 3)
                    slicePlane = imageData{roiIndex}(:,:,colorChannel);
                    switch obj.BatchOpt.MorphOperation{1}
                        case 'Bottom-hat filtering';     processedData{roiIndex}(:,:,colorChannel) = imbothat(slicePlane, se);
                        case 'Clear border';             processedData{roiIndex}(:,:,colorChannel) = imclearborder(slicePlane, conn);
                        case 'Morphological closing';    processedData{roiIndex}(:,:,colorChannel) = imclose(slicePlane, se);
                        case 'Dilate image';             processedData{roiIndex}(:,:,colorChannel) = imdilate(slicePlane, se);
                        case 'Erode image';              processedData{roiIndex}(:,:,colorChannel) = imerode(slicePlane, se);
                        case 'Fill regions';             processedData{roiIndex}(:,:,colorChannel) = imfill(slicePlane);
                        case 'H-maxima transform';       processedData{roiIndex}(:,:,colorChannel) = imhmax(slicePlane, hValue(1), conn);
                        case 'H-minima transform';       processedData{roiIndex}(:,:,colorChannel) = imhmin(slicePlane, hValue(1), conn);
                        case 'Morphological opening';    processedData{roiIndex}(:,:,colorChannel) = imopen(slicePlane, se);
                        case 'Top-hat filtering';        processedData{roiIndex}(:,:,colorChannel) = imtophat(slicePlane, se);
                    end
                    if smoothHSize > 0
                        processedData{roiIndex}(:,:,colorChannel) = ...
                            imfilter(processedData{roiIndex}(:,:,colorChannel), smoothFilter, 'replicate');
                    end
                end

                switch obj.BatchOpt.ActionToResult{1}
                    case 'None'
                        processedData{roiIndex} = processedData{roiIndex} * multiplyFactor;
                    case 'AddToImage'
                        processedData{roiIndex} = imageData{roiIndex} + processedData{roiIndex} * multiplyFactor;
                    case 'SubtractFromImage'
                        processedData{roiIndex} = imageData{roiIndex} - processedData{roiIndex} * multiplyFactor;
                end
            end

            obj.mibModel.setData2D(processedData, 'image', sliceIndex, [], colorChannelIndex, getDataOptions);

            if obj.BatchOpt.showWaitbar
                progressIndex = progressIndex + 1;
                progressBar.Value = min(progressIndex / maxIndex, 1);
                progressBar.Message = sprintf('Doing %s (slice %d of %d)\nPlease wait...', obj.BatchOpt.MorphOperation{1}, progressIndex, maxIndex);
                if progressBar.CancelRequested
                    delete(progressBar);
                    return;
                end
            end
        end
    end
end

if obj.BatchOpt.showWaitbar; delete(progressBar); end

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfMorphOps = obj.mibModel.preferences.Users.Tiers.numberOfMorphOps + 1;
notify(obj.mibModel, 'UpdateUserScore', core.ToggleEventData(2));    % scale scoring by factor 2

notify(obj.mibModel, 'ShowImage');
if ~batchModeSwitch; obj.returnBatchOpt(); end

end

% ---------------------------------------------------------------------------
function localCalculateBigData(obj, parentFigure, batchModeSwitch)
% LOCALCALCULATEBIGDATA - Morphological operation of a BigData image into a new OME-Zarr store.
%
% The whole dataset is processed at level ``BatchOpt.BigData_PyramidLevel`` in
% bands of rows (``controllers.BigDataOptions.run``); ``DatasetType``
% ``'2D, Slice'`` only with ``'Current overwrite (BigData)'``, which writes the shown
% slice into the store (``checkWholeDatasetType``). Offered only where a band with a halo gives the whole-slice result,
% in 2D mode as the GUI uses for them:
%
% - *Dilate image*, *Erode image* - halo ``floor(n/2)`` rows, ``n`` the height
%   of the structuring element: the furthest row a pixel looks at;
% - *Morphological opening* / *closing*, *Top-hat* / *Bottom-hat filtering* -
%   twice that, an erosion and a dilation in a row;
% - plus ``floor(SmoothHSize/2)`` for the Gaussian smoothing of the result.
%
% Rows beyond the halo are cropped, so every band equals the Standard result
% on the whole slice bit for bit. Not offered: *Clear border*, *Fill regions*,
% *H-maxima* / *H-minima transform* (morphological reconstruction: a region
% can reach the border, or a peak can be raised, from any distance), and the
% 3D mode (reachable only from a batch protocol; its operations are those).
% The channels not selected are copied. Errors are shown in a dialog, or
% raised as ``controllers:MorphOpsImages:bigData`` when headless.
BatchOpt = obj.BatchOpt;
operation = BatchOpt.MorphOperation{1};
errorId = 'controllers:MorphOpsImages:bigData';
title = 'BigData morphological operations';
if controllers.BigDataOptions.checkWholeDatasetType(obj.mibModel, parentFigure, errorId, BatchOpt, title); return; end
switch operation
    case {'Dilate image', 'Erode image'}
        passes = 1;
    case {'Morphological opening', 'Morphological closing', 'Top-hat filtering', 'Bottom-hat filtering'}
        passes = 2;
    otherwise
        controllers.BigDataOptions.reportError(obj.mibModel, parentFigure, errorId, sprintf(['"%s" is not ' ...
            'available for BigData datasets: it follows connected regions of any size, so it cannot be ' ...
            'computed in parts.\nAvailable: Bottom-hat filtering, Morphological closing, Dilate image, ' ...
            'Erode image, Morphological opening, Top-hat filtering.'], operation), title);
        return;
end
if strcmp(BatchOpt.Mode{1}, '3D')
    controllers.BigDataOptions.reportError(obj.mibModel, parentFigure, errorId, ...
        'On BigData datasets the morphological operations run in the 2D mode only.', title);
    return;
end
dataset = obj.mibModel.I{BatchOpt.id};
channels = 1:dataset.image.colors;
if ~strcmp(BatchOpt.ColorChannel{1}, 'All')
    channels = sscanf(BatchOpt.ColorChannel{1}, 'ColCh %d');
end

morphOptions.operation = operation;
morphOptions.strel = obj.getStrelElement();
morphOptions.channels = channels;
morphOptions.multiply = BatchOpt.Multiply{1};
morphOptions.action = BatchOpt.ActionToResult{1};
morphOptions.smoothFilter = [];
if BatchOpt.SmoothHSize{1} > 0
    morphOptions.smoothFilter = fspecial('gaussian', BatchOpt.SmoothHSize{1}, BatchOpt.SmoothSigma{1});
end
haloYX = passes * floor(size(morphOptions.strel.Neighborhood, 1) / 2) + floor(BatchOpt.SmoothHSize{1} / 2);
blockFunction = @(block) localMorphBlock(block, morphOptions);
fingerprint = jsonencode(rmfield(BatchOpt, intersect(fieldnames(BatchOpt), {'mibBatchTooltip', 'id', ...
    'BigData_OutputPath', 'BigData_OpenIn', 'showWaitbar'})));
try
    result = obj.bigDataOptions.run(BatchOpt, blockFunction, HaloYX = haloYX, Fingerprint = fingerprint);
catch err
    controllers.BigDataOptions.reportError(obj.mibModel, parentFigure, errorId, ...
        sprintf('The morphological operation of the BigData dataset failed:\n%s', err.message), title);
    return;
end
if isempty(result)      % cancelled; nothing is left on disk
    notify(obj.mibModel, 'StopProtocol');
    return;
end

obj.bigDataOptions.reportStoreResult(result, sprintf('%s (%s %s) of %s, level %s -> %s', operation, ...
    BatchOpt.StrelShape{1}, BatchOpt.StrelSize, dataset.image.filename, BatchOpt.BigData_PyramidLevel{1}, ...
    result.outputPath));
obj.mibModel.preferences.Users.Tiers.numberOfMorphOps = obj.mibModel.preferences.Users.Tiers.numberOfMorphOps + 1;
notify(obj.mibModel, 'UpdateUserScore', core.ToggleEventData(2));
if ~batchModeSwitch; obj.returnBatchOpt(); end
end

% ---------------------------------------------------------------------------
function out = localMorphBlock(block, morphOptions)
% LOCALMORPHBLOCK - The operation on the selected channels of one band ``[rows width colors]``.
% The arithmetic of the Standard 2D path: smoothing of the result, then the
% multiplication and the action, in the class of the image.
out = block;
se = morphOptions.strel;
for channel = morphOptions.channels
    plane = block(:, :, channel);
    switch morphOptions.operation
        case 'Bottom-hat filtering';  processed = imbothat(plane, se);
        case 'Morphological closing'; processed = imclose(plane, se);
        case 'Dilate image';          processed = imdilate(plane, se);
        case 'Erode image';           processed = imerode(plane, se);
        case 'Morphological opening'; processed = imopen(plane, se);
        case 'Top-hat filtering';     processed = imtophat(plane, se);
    end
    if ~isempty(morphOptions.smoothFilter)
        processed = imfilter(processed, morphOptions.smoothFilter, 'replicate');
    end
    switch morphOptions.action
        case 'None';              out(:, :, channel) = processed * morphOptions.multiply;
        case 'AddToImage';        out(:, :, channel) = plane + processed * morphOptions.multiply;
        case 'SubtractFromImage'; out(:, :, channel) = plane - processed * morphOptions.multiply;
    end
end
end
