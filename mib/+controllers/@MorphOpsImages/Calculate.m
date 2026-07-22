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
%   - **batchModeSwitch** — *(optional)* logical; when ``true`` skips backup
%     and ``returnBatchOpt`` call (default ``false``)
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MorphOpsImages.Calculate: triggered\n');
end
if nargin < 2; batchModeSwitch = false; end

id = obj.BatchOpt.id;

if isempty(obj.view)
    parentFigure = obj.mibModel.mibGUI;
else
    parentFigure = obj.view.gui;
end

colorChannelIndex = find(ismember(obj.BatchOpt.ColorChannel{2}, obj.BatchOpt.ColorChannel(1))) - 1;
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

%% Backup — skip for 4D datasets (too large) and in batch mode
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
        %% 3D mode — operate on full volume
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
        %% 2D mode — per-slice
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
notify(obj.mibModel, 'ShowImage');
if ~batchModeSwitch; obj.returnBatchOpt(); end

end
