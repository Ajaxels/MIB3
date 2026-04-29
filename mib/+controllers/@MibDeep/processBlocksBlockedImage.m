function [outputLabels, scoreImg, cancelled] = processBlocksBlockedImage(obj, vol, zValue, net, ...
        inputPatchSize, outputPatchSize, blockSize, padShift, ...
        dataDimension, patchwiseWorkflowSwitch, patchwisePatchesPredictSwitch, ...
        classNames, generateScoreFiles, executionEnvironment, fn, pwb)
% PROCESSBLOCKSBLOCKEDIMAGE - Segment one image volume using the blockedImage overlap-tile strategy.
%
% Syntax:
%   function [outputLabels, scoreImg, cancelled] = processBlocksBlockedImage(obj, vol, zValue, net,  inputPatchSize, outputPatchSize, blockSize, padShift,  dataDimension, patchwiseWorkflowSwitch, patchwisePatchesPredictSwitch,  classNames, generateScoreFiles, executionEnvironment, fn, pwb)
%
% Converts the input volume to a blockedImage, divides it into tiles of
% blockSize (with optional border padding for overlap or valid-padding
% networks), calls utils.deepmib.segmentBlockedImage on every tile via
% blockedImage/apply, then gathers and crops the results back to the
% original image extent.  Supports 2D, 2.5D, and 3D networks, patch-wise
% classification, dynamic masking, and optional score-map generation.
%
% Input Arguments:
%   - **obj** — MibDeep controller instance
%   - **vol** — input image volume
%     - 2D  — [height, width, colors]
%     - 2.5D/3D — [height, width, depth, colors]
%   - **zValue** — z-slice index used when building output filenames for the 2.5D
%     per-slice loop; pass NaN for full-volume (2D / 3D) calls
%   - **net** — trained deep learning network loaded from the network file
%   - **inputPatchSize** — patch size expected by the network [height, width, colors]
%     or [height, width, depth, colors]
%   - **outputPatchSize** — network output patch size; equals inputPatchSize for
%     'same' padding, smaller for 'valid' padding
%   - **blockSize** — effective tile footprint passed to blockedImage/apply; already
%     reduced by padShift when overlap-tile mode is active
%   - **padShift** — border overlap in pixels [height, width] or [height, width, depth];
%     zero when overlap-tile mode is off
%   - **dataDimension** — numeric, dataset/network dimensionality
%     - 2   — 2D network
%     - 2.5 — 2.5D (Z-context) network
%     - 3   — 3D network
%   - **patchwiseWorkflowSwitch** — logical; true for the '2D Patch-wise' workflow
%     where the Exterior class is not removed and per-patch CSV files are written
%   - **patchwisePatchesPredictSwitch** — logical; true when prediction images are
%     stored in class-named subfolders (patch classification mode) — skips
%     the gather/crop post-processing
%   - **classNames** — cell array of class name strings loaded from the network file
%   - **generateScoreFiles** — score-file format selector
%     - 0 — do not generate score files
%     - 1 — AmiraMesh (.am)
%     - 2 — MATLAB non-compressed (.mibImg)
%     - 3 — MATLAB compressed (.mibImg)
%     - 4 — MATLAB non-compressed, range 0–1 (.mat)
%   - **executionEnvironment** — string passed to segmentBlockedImage
%     - 'cpu' — CPU only
%     - 'gpu' — single GPU
%     - 'multi-gpu' — multiple GPUs (patch-wise only)
%     - 'parallel' — parallel pool
%   - **fn** — base filename (no extension) of the current image; used when writing
%     per-patch CSV score/label files
%   - **pwb** — *(optional)* uiprogressdlg handle used to check for user
%     cancellation between the pre-apply and post-apply stages; pass [] when
%     no progress dialog is active
%
% Output Arguments:
%   - **outputLabels** — predicted label matrix (uint8); [] when cancelled
%   - **scoreImg** — probability/score map array; [] when cancelled, 0 when
%     generateScoreFiles == 0
%   - **cancelled** — logical; true when the user pressed Cancel on pwb
%
% Usage:
%   Example 1 - Typical call from startPredictionBlockedImage (2D full-volume path)::
%
%     % Typical call from startPredictionBlockedImage (2D full-volume path):
%     [outputLabels, scoreImg, cancelled] = obj.processBlocksBlockedImage( ...
%         vol, NaN, net, inputPatchSize, outputPatchSize, blockSize, padShift, ...
%         2, false, false, classNames, 0, 'gpu', 'myImage', pwb);
%     if cancelled; close(pwb); return; end
%

    % Updates
    % 24.04.2025 - added pwb parameter and cancelled output for cancel support
    
    cancelled = false;

    % define padding method for blocks
    if verLessThan('matlab', '9.14')
        padMethod = 'replicate';
    else
        padMethod = 'symmetric';
    end

    if dataDimension == 2
        vol = squeeze(vol);  % MIB3 stores 2D images as [Y,X,1,C]; squeeze to [Y,X,C]
    end
    if dataDimension == 2 && size(vol, 3) ~= inputPatchSize(4)
        % dynamically convert grayscale to RGB if needed
        vol = repmat(vol, [1, 1, 3]);
    end

    extraPaddingPixels = 0;
    if obj.view.handles.P_ExtraPaddingPercentage.Value > 0 && ~patchwiseWorkflowSwitch % pad the image
        extraPaddingPixels = ceil(max(inputPatchSize(1:2))*obj.view.handles.P_ExtraPaddingPercentage.Value/100);
        vol = padarray(vol, [extraPaddingPixels extraPaddingPixels], 'symmetric', 'both');
    end

    % get number of colors in vol
    if strcmp(obj.BatchOpt.Architecture{1}(1:3), 'Z2C')
        noColors = size(vol, numel(blockSize));
        dataDimension = 2;
    else
        noColors = size(vol, numel(blockSize)+1);
    end

    vol = blockedImage(vol, ...     % % [height, width, color] or  [height, width, depth, color]
        'Adapter', images.blocked.InMemory);    % convert to blockedimage

    % detect blocks for the dynamic masking mode
    if obj.BatchOpt.P_DynamicMasking
        bls = obj.generateDynamicMaskingBlocks(vol, blockSize, noColors);
    else
        % just init with something to make sure that the following
        % condition will work
        bls.ImageNumber = 1;
    end

    if ~isempty(pwb) && pwb.CancelRequested; outputLabels = []; scoreImg = []; cancelled = true; return; end

    if numel(bls.ImageNumber) > 0
        blockedImageWaitBarStatus = false; % due to a bug switch off waitbar for blockedImage/apply
        if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'same')     % same
            if obj.BatchOpt.P_OverlappingTiles == false
                if obj.BatchOpt.P_DynamicMasking
                    [outputLabels, scoreImg] = apply(vol, ...       % apply(blockedImage, function, parameters)
                        @(block, blockInfo) utils.deepmib.segmentBlockedImage(block, net, dataDimension, patchwiseWorkflowSwitch, generateScoreFiles, executionEnvironment, padShift), ...
                        'Adapter', images.blocked.InMemory, ...
                        'Level', 1, ...
                        'PadPartialBlocks', true, ...
                        'UseParallel', false,...
                        'DisplayWaitbar', blockedImageWaitBarStatus, ...
                        'BatchSize', obj.BatchOpt.P_MiniBatchSize{1}, ...
                        'PadMethod', padMethod, ...
                        'BlockLocationSet', bls);
                else
                    [outputLabels, scoreImg] = apply(vol, ...       % apply(blockedImage, function, parameters)
                        @(block, blockInfo) utils.deepmib.segmentBlockedImage(block, net, dataDimension, patchwiseWorkflowSwitch, generateScoreFiles, executionEnvironment, padShift), ...
                        'Adapter', images.blocked.InMemory, ...
                        'Level', 1, ...
                        'PadPartialBlocks', true, ...
                        'BlockSize', blockSize,...
                        'UseParallel', false,...
                        'DisplayWaitbar', blockedImageWaitBarStatus, ...
                        'PadMethod', padMethod, ...
                        'BatchSize', obj.BatchOpt.P_MiniBatchSize{1});
                end
            else % same + overlap
                %padShift = ceil(inputPatchSize(1)*obj.BatchOpt.P_OverlappingTilesPercentage{1}/100);
                if obj.BatchOpt.P_DynamicMasking
                    [outputLabels, scoreImg] = apply(vol, ...       % apply(blockedImage, function, parameters)
                        @(block, blockInfo) utils.deepmib.segmentBlockedImage(block, net, dataDimension, patchwiseWorkflowSwitch, generateScoreFiles, executionEnvironment, padShift), ...
                        'Adapter', images.blocked.InMemory, ...
                        'Level', 1, ...
                        'PadPartialBlocks', true, ...
                        'BorderSize', padShift,... %'BorderSize', repmat(padShift, [1, numel(blockSize)]),...
                        'UseParallel', false,...
                        'DisplayWaitbar', blockedImageWaitBarStatus, ...
                        'PadMethod', padMethod, ...
                        'BatchSize', obj.BatchOpt.P_MiniBatchSize{1}, ...
                        'BlockLocationSet', bls);
                else
                    [outputLabels, scoreImg] = apply(vol, ...       % apply(blockedImage, function, parameters)
                        @(block, blockInfo) utils.deepmib.segmentBlockedImage(block, net, dataDimension, patchwiseWorkflowSwitch, generateScoreFiles, executionEnvironment, padShift), ...
                        'Adapter', images.blocked.InMemory, ...
                        'Level', 1, ...
                        'PadPartialBlocks', true, ...
                        'BlockSize', blockSize,...  % blockSize-padShift*2
                        'BorderSize', padShift,...   % 'BorderSize', repmat(padShift, [1, numel(blockSize)]),...
                        'UseParallel', false,...
                        'DisplayWaitbar', blockedImageWaitBarStatus, ...
                        'PadMethod', padMethod, ...
                        'BatchSize', obj.BatchOpt.P_MiniBatchSize{1}); % 'PadMethod', 'replicate', ... % 'symmetric'
                end
            end
        else    % valid padding
            if obj.BatchOpt.P_DynamicMasking
                [outputLabels, scoreImg] = apply(vol, ...       % apply(blockedImage, function, parameters)
                    @(block, blockInfo) utils.deepmib.segmentBlockedImage(block, net, dataDimension, patchwiseWorkflowSwitch, generateScoreFiles, executionEnvironment, padShift), ...
                    'Adapter', images.blocked.InMemory, ...
                    'Level', 1, ...
                    'PadPartialBlocks', true, ...
                    'BorderSize', (inputPatchSize(1:numel(blockSize)) - outputPatchSize(1:numel(blockSize))) / 2,...  %  [(inputPatchSize(1)-outputPatchSize(1))/2 (inputPatchSize(2)-outputPatchSize(2))/2]
                    'UseParallel', false,...
                    'DisplayWaitbar', blockedImageWaitBarStatus, ...
                    'BatchSize', obj.BatchOpt.P_MiniBatchSize{1}, ...
                    'PadMethod', padMethod, ...
                    'BlockLocationSet', bls);
            else
                [outputLabels, scoreImg] = apply(vol, ...       % apply(blockedImage, function, parameters)
                    @(block, blockInfo) utils.deepmib.segmentBlockedImage(block, net, dataDimension, patchwiseWorkflowSwitch, generateScoreFiles, executionEnvironment, padShift), ...
                    'Adapter', images.blocked.InMemory, ...
                    'Level', 1, ...
                    'PadPartialBlocks', true, ...
                    'BlockSize', blockSize,...  	% outputPatchSize(1:numel(outputPatchSize)-1) or [outputPatchSize(1) outputPatchSize(2)]
                    'BorderSize', (inputPatchSize(1:numel(blockSize)) - outputPatchSize(1:numel(blockSize))) / 2,...  %  [(inputPatchSize(1)-outputPatchSize(1))/2 (inputPatchSize(2)-outputPatchSize(2))/2]
                    'UseParallel', false,...
                    'PadMethod', padMethod, ...
                    'DisplayWaitbar', blockedImageWaitBarStatus, ...
                    'BatchSize', obj.BatchOpt.P_MiniBatchSize{1});
            end
        end
    else
        if dataDimension == 2
            outputLabels = blockedImage(ones([vol.Size(1) vol.Size(2)], 'uint8'), ...     % % [height, width] or  [height, width, depth]
                'Adapter', images.blocked.InMemory);    % convert to blockedimage
            scoreImg = blockedImage(ones([vol.Size(1) vol.Size(2), numel(classNames)], 'uint8'), ...     % % [height, width, classes]
                'Adapter', images.blocked.InMemory);    % convert to blockedimage
        elseif dataDimension == 2.5
            outputLabels = blockedImage(ones([vol.Size(1) vol.Size(2)], 'uint8'), ...     % [height, width, classes]
                'Adapter', images.blocked.InMemory);    % convert to blockedimage
            scoreImg = blockedImage(ones([vol.Size(1) vol.Size(2),  numel(classNames)], 'uint8'), ...     % % [height, width, classes]
                'Adapter', images.blocked.InMemory);    % convert to blockedimage
        else    % 3D case dataDimension == 2.5 or dataDimension == 3
            outputLabels = blockedImage(ones([vol.Size(1) vol.Size(2), vol.Size(3)], 'uint8'), ...     % [height, width, depth, classes]
                'Adapter', images.blocked.InMemory);    % convert to blockedimage
            scoreImg = blockedImage(ones([vol.Size(1) vol.Size(2),  vol.Size(3), numel(classNames)], 'uint8'), ...     % % [height, width, classes]
                'Adapter', images.blocked.InMemory);    % convert to blockedimage
        end
    end

    if ~isempty(pwb) && pwb.CancelRequested; outputLabels = []; scoreImg = []; cancelled = true; return; end

    %[~, fn] = fileparts(imgDS.Files{id});
    if ~patchwisePatchesPredictSwitch % standard semantic segmentation mode or patch-wise mode when prediction images are not in patches
        outputLabels = gather(outputLabels, 'Level', 1); % convert blocked image to normal matrix

        if ~patchwiseWorkflowSwitch
            outputLabels = outputLabels - 1;    % remove the first "exterior" class

            % additional cropping from the right-side may be required
            if dataDimension < 3         % 2D and 2.5D cases
                if sum(abs(size(outputLabels) - vol.Size(1:2))) ~= 0
                    outputLabels = outputLabels(1:size(vol.Source, 1), 1:size(vol.Source, 2), :);
                end
            else                % 2.5D and 3D case dataDimension == 2.5 or dataDimension == 3
                if sum(abs(size(outputLabels) - vol.Size(1:3))) ~= 0
                    outputLabels = outputLabels(1:size(vol.Source, 1), 1:size(vol.Source, 2), 1:size(vol.Source, 3), :);
                end
            end
        else
            outputLabels = uint8(outputLabels);
            % generate CSV files for the patch-wise segmentations
            if isnan(zValue)
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', sprintf('Labels_%s_%.4d.csv', fn, zValue));
            else
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', sprintf('Labels_%s.csv', fn));
            end
            writematrix(outputLabels, filename, 'FileType' , 'Text');

            % upscale the resulting labels
            if obj.BatchOpt.P_PatchWiseUpsample
                if obj.BatchOpt.P_OverlappingTiles
                    outHeight = (inputPatchSize(1)-padShift(1)*2)*size(outputLabels,1);
                    outWidth = (inputPatchSize(2)-padShift(2)*2)*size(outputLabels,2);
                else
                    outHeight = inputPatchSize(1)*size(outputLabels,1);
                    outWidth = inputPatchSize(2)*size(outputLabels,2);
                end
                dummyLabels = imresize(outputLabels, [outHeight, outWidth], 'nearest');
                outputLabels = dummyLabels(1:size(vol.Source, 1), 1:size(vol.Source, 2));
            end
        end

        % remove additional padding
        if extraPaddingPixels > 0
            outputLabels = outputLabels(extraPaddingPixels+1:end-extraPaddingPixels, extraPaddingPixels+1:end-extraPaddingPixels, :, :);
        end

        % save/generate score map
        if generateScoreFiles > 0
            scoreImg = gather(scoreImg, 'Level', 1); % convert blocked image to normal matrix
            % additional cropping from the right-side may be required
            if dataDimension < 3         % 2D case
                if ~patchwiseWorkflowSwitch
                    % trim the long end if needed
                    if sum(abs(size(scoreImg, 1:2) - vol.Size(1:2))) ~= 0
                        scoreImg = scoreImg(1:size(vol.Source, 1), 1:size(vol.Source, 2), :);
                    end
                else
                    % generate CSV files for the patch-wise segmentations
                    if isnan(zValue)
                        filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', sprintf('Score_%s_%.4d.csv', fn, zValue));
                    else
                        filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', sprintf('Score_%s.csv', fn));
                    end

                    % generate score table with probabilities
                    % of each class
                    T = table();
                    for classId = 1:size(scoreImg, 3)
                        T.(classNames{classId}) =  scoreImg(:,:,classId);
                    end
                    writetable(T, filename, 'FileType' , 'Text');

                    scoreImg = uint8(scoreImg*255); % convert to uint8 and scale 0-255
                    if obj.BatchOpt.P_PatchWiseUpsample
                        % upscale the resulting scores
                        dummyLabels = zeros([inputPatchSize(1)*size(scoreImg,1), inputPatchSize(2)*size(scoreImg,2), size(scoreImg, 3)], 'uint8');
                        for colCh=1:size(scoreImg, 3)
                            dummyLabels(:,:,colCh) = imresize(scoreImg(:,:,colCh), [inputPatchSize(1)*size(scoreImg,1), inputPatchSize(2)*size(scoreImg,2)], 'nearest');
                        end
                        scoreImg = dummyLabels(1:size(vol.Source, 1), 1:size(vol.Source, 2), :);
                    end
                end
            else                % 3D case
                if sum(abs(size(scoreImg, 1:3) - vol.Size(1:3))) ~= 0
                    scoreImg = scoreImg(1:size(vol.Source, 1), 1:size(vol.Source, 2), 1:size(vol.Source, 3), :);
                end
                scoreImg = permute(scoreImg, [1 2 4 3]);    % convert to [height, width, color, depth]
            end

            % remove extra padding from the full image
            if extraPaddingPixels > 0
                scoreImg = scoreImg(extraPaddingPixels+1:end-extraPaddingPixels, extraPaddingPixels+1:end-extraPaddingPixels, :, :);
            end
        end
    else    % patchwisePatchesPredictSwitch == true, patch-wise mode, when each patch is contained in its own subfolder
        outputLabels = gather(outputLabels, 'Level', 1); % convert blocked image to normal matrix
        %patchWiseOutout.PredictedClass{id} = char(outputLabels);
        %scoreImg = gather(scoreImg, 'Level', 1); % convert blocked image to normal matrix
        %patchWiseOutout.MaxProbability(id,:) = squeeze(max(scoreImg,[], 1:2))';
    end
end

