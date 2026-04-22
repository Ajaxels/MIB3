function startPrediction2D(obj)
    % function startPrediction2D(obj)
    % predict datasets for 2D taken to a separate function for
    % better performance

    if strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Preprocessing is not required') || ...
            strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Split files for training/validation') || ...
            strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Training')
        preprocessedSwitch = false;

        msg = sprintf('!!! Warning !!!\nYou are going to start prediction without preprocessing!\nConfirm that your images are located under\n\n%s\n\n%s\n%s\n\n', ...
            obj.BatchOpt.OriginalPredictionImagesDir, ...
            '- Images', '- Labels (optionally, when ground truth is present)');

        selection = uiconfirm(obj.view.gui, ...
            msg, 'Preprocessing',...
            'Options',{'Confirm', 'Cancel'},...
            'DefaultOption', 1, 'CancelOption', 2,...
            'Icon', 'warning');
        if strcmp(selection, 'Cancel'); return; end
    else
        preprocessedSwitch = true;
        msg = sprintf('Have images for prediction were preprocessed?\n\nIf not, please switch to the Directories and Preprocessing tab and preprocess images for prediction');
        selection = uiconfirm(obj.view.gui, ...
            msg, 'Preprocessing',...
            'Options',{'Yes', 'No'},...
            'DefaultOption', 1, 'CancelOption', 2);
        if strcmp(selection, 'No'); return; end
    end

    % get settings for export of score files
    % {'Do not generate', 'Use AM format', 'Use Matlab non-compressed format', 'Use Matlab compressed format'};
    if strcmp(obj.BatchOpt.P_ScoreFiles{1}, 'Do not generate')
        generateScoreFiles = 0;
    else
        generateScoreFiles = find(ismember(obj.BatchOpt.P_ScoreFiles{2}, obj.BatchOpt.P_ScoreFiles{1}))-1;
        % 1-> 'Use AM format'
        % 2-> 'Use Matlab non-compressed format'
        % 3-> 'Use Matlab compressed format'
        % 4-> 'Use Matlab non-compressed format (range 0-1)'
        saveImageOpt.dimOrder = 'yxczt';    % for 2D or saveImageOpt.dimOrder = 'yxzct'; for 3D
    end

    if obj.BatchOpt.showWaitbar; pwb = core.PoolWaitbar(1, 'Creating image store for prediction...', obj.view.gui, 'Predicting dataset'); end

    % creating output directories
    warning('off', 'MATLAB:MKDIR:DirectoryExists');
    % check whether the output folder exists and whether there are
    % some files in there
    noOutputModelFiles = 0;
    noOutputScoreFiles = 0;
    if isfolder(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels'))
        outputList = dir(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels'));
        noOutputModelFiles = abs(sum([outputList.isdir]-1));
    end
    if isfolder(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores'))
        outputList = dir(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores'));
        noOutputScoreFiles = abs(sum([outputList.isdir]-1));
    end
    if noOutputModelFiles > 0 || noOutputScoreFiles > 0
        selection = uiconfirm(obj.view.gui, ...
            sprintf('!!! Warning !!!\n\nThe destination directories:\n- PredictionImages/ResultsModels\n- PredictionImages/ResultsScores\n\nare not empty!\n\nShell the destination folders be emptied and prediction started?'), ...
            'Destination folders are not empty',...
            'Icon','warning');
        if strcmp(selection, 'Cancel'); if obj.BatchOpt.showWaitbar; delete(obj.wb); end; return; end
        if noOutputModelFiles > 0
            delete(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', '*'));
        end
        if noOutputScoreFiles > 0
            delete(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', '*'));
        end
    end

    mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores'));
    mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels'));

    % prepare options for loading of images
    mibDeepStoreLoadImagesOpt.mibBioformatsCheck = obj.BatchOpt.Bioformats;
    mibDeepStoreLoadImagesOpt.BioFormatsIndices = obj.BatchOpt.BioformatsIndex{1};
    mibDeepStoreLoadImagesOpt.Workflow = obj.BatchOpt.Workflow{1};
    % make a datastore for images
    try
        if preprocessedSwitch   % with preprocessing
            imgDS = imageDatastore(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages'), ...
                'FileExtensions', '.mibImg', 'ReadFcn', @utils.deepmib.storeLoadImages);
        else    % without preprocessing
            fnExtention = lower(['.' obj.BatchOpt.ImageFilenameExtension{1}]);
            imgDS = imageDatastore(fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images'), ...
                'FileExtensions', fnExtention, ...
                'IncludeSubfolders', false, ...
                'ReadFcn', @(fn)utils.deepmib.storeLoadImages(fn, mibDeepStoreLoadImagesOpt));
        end
    catch err
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Missing files');
        if obj.BatchOpt.showWaitbar; delete(obj.wb); end
        return;
    end

    if obj.BatchOpt.showWaitbar
        if pwb.getCancelState(); delete(pwb); return; end
        pwb.updateText('Loading network...');
    end
    % loading: 'net', 'TrainingOptStruct', 'classNames',
    % 'inputPatchSize', 'outputPatchSize', 'BatchOpt' variables
    load(obj.BatchOpt.NetworkFilename, '-mat');

    numClasses = numel(classNames); %#ok<USENS>
    if exist('classColors', 'var')
        modelMaterialColors = classColors;  %#ok<PROP> % loaded from network file
    else
        modelMaterialColors = rand([numClasses, 3]);
    end

    % correct tile overlapping strategy for the valid padding
    if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'valid')
        obj.BatchOpt.P_OverlappingTiles = false;
        obj.view.Figure.P_OverlappingTiles.Enable = 'off';
        obj.view.Figure.P_OverlappingTiles.Value = false;
    end

    %% Start prediction
    % Use the overlap-tile strategy to predict the labels for each volume.
    % Each test volume is padded to make the input size a multiple of the output size
    % of the network and compensates for the effects of valid convolution.
    % The overlap-tile algorithm selects overlapping patches, predicts the labels
    % for each patch by using the semanticseg function, and then recombines the patches.
    t1 = tic;
    noFiles = numel(imgDS.Files);
    if obj.BatchOpt.showWaitbar
        if pwb.getCancelState(); delete(pwb); return; end
        pwb.updateText(sprintf('Starting prediction\nPlease wait...'));
        pwb.increaseMaxNumberOfIterations(noFiles);
    end
    id = 1;     % indices of files
    patchCount = 1; % counter of processed patches
    nDims = 2;  % number of dimensions for data, 2

    % select gpu or cpu for prediction and define executionEnvironment
    selectedIndex = find(ismember(obj.view.Figure.GPUDropDown.Items, obj.view.Figure.GPUDropDown.Value));
    switch obj.view.Figure.GPUDropDown.Value
        case 'CPU only'
            if numel(obj.view.Figure.GPUDropDown.Items) > 2 % i.e. GPU is present
                gpuDevice([]);  % CPU only mode
            end
            executionEnvironment = 'cpu';
        case 'Multi-GPU'
            mgsOpt.MsgBoxOnly = true;
            header = sprintf('Multi-GPU mode cannot be yet used for prediction. Please select a GPU from the list and restart prediction!');
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Ops!', mgsOpt);
            if obj.BatchOpt.showWaitbar; delete(obj.wb); end
            return;
            %executionEnvironment = 'multi-gpu';
        case 'Parallel'
            executionEnvironment = 'parallel';
        otherwise
            gpuDevice(selectedIndex);   % choose selected GPU device
            executionEnvironment = 'gpu';
    end

    while hasdata(imgDS)
        vol = squeeze(read(imgDS));  % [height, width, depth, color] for 2D
        if size(vol, 3) ~= inputPatchSize(4)
            % dynamically convert grayscale to RGB if needed
            vol = repmat(vol, [1, 1, 3]);
        end

        volSize = size(vol, (1:2));
        [height, width, color] = size(vol);
        [~, fn] = fileparts(imgDS.Files{id});

        % for tiled procedure see ToDo\CoderGPU\StartPrediction2D_tiled_strategy.m
        if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'same')     % same
            if obj.BatchOpt.P_OverlappingTiles == false
                if height == inputPatchSize(1) && width == inputPatchSize(2)
                    [outputLabels, ~, scoreImg] = semanticseg(squeeze(vol), net, ...
                        'OutputType', 'uint8', 'ExecutionEnvironment', executionEnvironment, ...
                        'MiniBatchSize', obj.BatchOpt.P_MiniBatchSize{1});
                    if generateScoreFiles > 0 && generateScoreFiles < 4
                        scoreImg = uint8(scoreImg*255);
                    end
                else
                    % find padding size for the dataset to match
                    % input patch size
                    padSize(1) = ceil(height/inputPatchSize(1))*inputPatchSize(1) - height;
                    padSize(2) = ceil(width/inputPatchSize(2))*inputPatchSize(2) - width;
                    padSizePre = floor(padSize/2);
                    padSizePost = ceil(padSize/2);
                    volPadded = vol;
                    if sum(padSizePre)>0; volPadded = padarray(volPadded, padSizePre, 'symmetric', 'pre'); end
                    if sum(padSizePost)>0; volPadded = padarray(volPadded, padSizePost, 'symmetric', 'post'); end

                    [outputLabels, ~, scoreImg] = semanticseg(squeeze(volPadded), net, ...
                        'OutputType', 'uint8', 'ExecutionEnvironment', executionEnvironment,...
                        'MiniBatchSize', obj.BatchOpt.P_MiniBatchSize{1}');

                    % Remove the padding if needed
                    if sum(padSizePre)+sum(padSizePost)>0
                        outputLabels = outputLabels(padSizePre(1)+1:end-padSizePost(1), ...
                            padSizePre(2)+1:end-padSizePost(2));
                        if generateScoreFiles > 0
                            scoreImg = scoreImg(padSizePre(1)+1:end-padSizePost(1), ...
                                padSizePre(2)+1:end-padSizePost(2), :);
                            if generateScoreFiles < 4
                                scoreImg = uint8(scoreImg*255);
                            end
                        end
                    end

                end
            else        % the section below is for obj.BatchOpt.P_OverlappingTiles == true
                % pad the image to include extended areas due to
                % the overlapping strategy
                if strcmp(obj.BatchOpt.Architecture{1}, 'DeepLab v3+')
                    obj.BatchOpt.T_EncoderDepth{1} = 4;
                end

                %padShift = (obj.BatchOpt.T_FilterSize{1}-1)*obj.BatchOpt.T_EncoderDepth{1};
                padShift = ceil(inputPatchSize(1)*obj.BatchOpt.P_OverlappingTilesPercentage{1}/100);

                padSize  = repmat(padShift, [1 nDims]);
                volPadded = padarray(vol, padSize, 0, 'both');

                % pad image to have dimensions as multiples of patchSize
                [heightPad, widthPad, colorPad] = size(volPadded);
                outputPatchSize = max(inputPatchSize-padShift*2, 1);  % recompute output patch size, it is smaller than input patch size

                padSize(1) = ceil(heightPad/outputPatchSize(1))*outputPatchSize(1) + padShift*2 - heightPad;
                padSize(2) = ceil(widthPad/outputPatchSize(2))*outputPatchSize(2) + padShift*2 - widthPad;
                volPadded = padarray(volPadded, padSize, 0, 'post');

                [heightPad, widthPad, colorPad] = size(volPadded);
                outputLabels = zeros([heightPad, widthPad], 'uint8');
                if generateScoreFiles > 0 && generateScoreFiles < 4
                    scoreImg = zeros([heightPad, widthPad, numClasses], 'uint8');
                    multiplyScoreFactor = 255;
                elseif generateScoreFiles == 4
                    scoreImg = zeros([heightPad, widthPad, numClasses], 'single');
                    multiplyScoreFactor = 1;
                end


                for j = 1:outputPatchSize(2):widthPad-outputPatchSize(2)+1
                    for i = 1:outputPatchSize(1):heightPad-outputPatchSize(1)+1
                        patch = volPadded( i:i+inputPatchSize(1)-1,...
                            j:j+inputPatchSize(2)-1, :);
                        [patchSeg, ~, scoreBlock] = semanticseg(squeeze(patch), net, ...
                            'OutputType', 'uint8', 'ExecutionEnvironment', executionEnvironment,...
                            'MiniBatchSize', obj.BatchOpt.P_MiniBatchSize{1});
                        x1 = i + padShift - 1;
                        y1 = j + padShift - 1;

                        outputLabels(x1:x1+outputPatchSize(1)-1, ...
                            y1:y1+outputPatchSize(2)-1) = patchSeg(padShift:padShift+outputPatchSize(1)-1, ...
                            padShift:padShift+outputPatchSize(2)-1);

                        if generateScoreFiles > 0
                            scoreImg(x1:x1+outputPatchSize(1)-1, ...
                                y1:y1+outputPatchSize(2)-1,:) = scoreBlock(padShift:padShift+outputPatchSize(1)-1, ...
                                padShift:padShift+outputPatchSize(2)-1, ...
                                :)*multiplyScoreFactor;
                        end
                        patchCount = patchCount + 1;
                    end
                end

                % Remove the padding
                outputLabels = outputLabels(padShift+1:padShift+height, padShift+1:padShift+width);
                if generateScoreFiles > 0
                    scoreImg = scoreImg(padShift+1:padShift+height, padShift+1:padShift+width, :);
                end
            end
        else    % the section below is for obj.BatchOpt.T_ConvolutionPadding{1} == 'valid'
            padSizePre  = (inputPatchSize(1:2)-outputPatchSize(1:2))/2; %+ BatchOpt.T_EncoderDepth{1}/2;
            padSizePost = (inputPatchSize(1:2)-outputPatchSize(1:2))/2 + (outputPatchSize(1:2)-mod(volSize, outputPatchSize(1:2)));
            volPadded = vol;
            volPadded = padarray(volPadded, padSizePre, 'symmetric', 'pre');
            volPadded = padarray(volPadded, padSizePost, 'symmetric', 'post');

            % add correction factor for padding of input images
            encDepth = obj.BatchOpt.T_EncoderDepth{1};     % encoder depth
            filterSize = obj.BatchOpt.T_FilterSize{1}; % filter size
            % Amount of pixels to be excluded due to downsampling in the network
            excludedPixels = sum(2.^(1:encDepth).*(filterSize-1));
            % Compute the input size required to produce even sizes at the max pooling layers.
            reqImageSize = 2^encDepth.* ceil((size(volPadded) - excludedPixels ) / 2^encDepth) + excludedPixels;
            % Compute the additional amount of padding needed to meet the size requirements.
            additionalPaddingPost = reqImageSize - size(volPadded);
            % Add additional padding
            volPadded = padarray(volPadded, additionalPaddingPost(1:2), 'symmetric', 'post');

            [outputLabels, ~, scoreImg] = semanticseg(squeeze(volPadded), net, ...
                'OutputType', 'uint8', 'ExecutionEnvironment', executionEnvironment, ...
                'MiniBatchSize', obj.BatchOpt.P_MiniBatchSize{1});

            % Crop out the extra padded region.
            outputLabels = outputLabels(1:volSize(1), 1:volSize(2));
            if generateScoreFiles > 0 && generateScoreFiles < 4
                scoreImg = uint8(scoreImg(1:volSize(1), 1:volSize(2), :)*255);
            elseif generateScoreFiles == 4
                scoreImg = scoreImg(1:volSize(1), 1:volSize(2), :);
            end
        end

        % Save generated model files
        outputLabels = outputLabels - 1;    % remove the first "exterior" class

        % get filename template
        [~, fn] = fileparts(imgDS.Files{id});
        % depending on the selected output type
        switch obj.BatchOpt.P_ModelFiles{1}
            case 'MIB Model format'
                modelMaterialNames = classNames;
                modelMaterialNames(1) = [];     % remove Exterior
                modelMaterialColors = [modelMaterialColors; obj.modelMaterialColors]; %#ok<AGROW,PROP>
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', ['Labels_' fn '.model']);
                %rawFn = ls(fullfile(projDir, ImageSource, '01_input_images', '*.am'));
                %amHeader = getAmiraMeshHeader(fullfile(projDir, ImageSource, '01_input_images', rawFn));
                %BoundingBox = amHeader(find(ismember({amHeader.Name}', 'BoundingBox'))).Value;
                modelVariable = 'outputLabels';
                modelType = 63;
                if exist('BoundingBox','var') == 0
                    save(filename, 'outputLabels', 'modelMaterialNames', 'modelMaterialColors', ...
                        'modelVariable', 'modelType', '-mat', '-v7.3');
                else
                    save(filename, 'outputLabels', 'modelMaterialNames', 'modelMaterialColors', ...
                        'BoundingBox', 'modelVariable', 'modelType', '-mat', '-v7.3');
                end
            case 'TIF compressed format'
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', ['Labels_' fn '.tif']);
                imwrite(outputLabels, filename, 'tif', 'WriteMode', 'overwrite', 'Description', sprintf('DeepMIB segmentation: %s %s', obj.BatchOpt.Workflow{1}, obj.BatchOpt.Architecture{1}), 'Compression', 'lzw');
            case 'TIF uncompressed format'
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', ['Labels_' fn '.tif']);
                imwrite(outputLabels, filename, 'tif', 'WriteMode', 'overwrite', 'Description', sprintf('DeepMIB segmentation: %s %s', obj.BatchOpt.Workflow{1}, obj.BatchOpt.Architecture{1}), 'Compression', 'none');
        end

        % save score map
        if generateScoreFiles > 0
            if generateScoreFiles == 1    % 'Use AM format'
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', ['Score_' fn '.am']);
                amiraOpt.overwrite = 1;
                amiraOpt.showWaitbar = 0;
                amiraOpt.verbose = false;
                % scoreImg is [H W C] (pure 2D) or [H W C D] (2.5D / 3D / use3DdatasetWith2Dnet);
                % bitmap2amiraMesh expects [H W D C T] - trailing singleton handles the 2D case
                io.AmiraMesh.bitmap2amiraMesh(filename, permute(scoreImg, [1 2 4 3]), [], amiraOpt);
            elseif generateScoreFiles == 4   %  4=='Use Matlab non-compressed format (range 0-1)'
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', ['Score_' fn '.mat']);
                utils.deepmib.saveImageParFor(filename, scoreImg, false, saveImageOpt);
            else  % 2=='Use Matlab non-compressed format', 3=='Use Matlab compressed format',
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', ['Score_' fn '.mibImg']);
                utils.deepmib.saveImageParFor(filename, scoreImg, generateScoreFiles, saveImageOpt);
            end
        end

        % copy original file to the results for easier evaluation
        if obj.BatchOpt.showWaitbar
            if pwb.getCancelState(); delete(pwb); return; end
            elapsedTime = toc(t1);
            timerValue = elapsedTime/id*(noFiles-id);
            pwb.updateText(sprintf('%s\nHold on ~%.0f:%.2d mins left...', fn, floor(timerValue/60), mod(round(timerValue),60)));
            pwb.increment();
        end
        id=id+1;
    end
    fprintf('Prediction finished: ');
    toc(t1)
    % count user's points
    obj.mibModel.preferences.Users.Tiers.numberOfInferencedDeepNetworks = obj.mibModel.preferences.Users.Tiers.numberOfInferencedDeepNetworks+1;
    eventdata = core.ToggleEventData(4);    % scale scoring by factor 5
    notify(obj.mibModel, 'UpdateUserScore', eventdata);

    if obj.BatchOpt.showWaitbar; delete(pwb); end
end

