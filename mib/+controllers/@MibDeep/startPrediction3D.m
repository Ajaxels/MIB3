function startPrediction3D(obj)
    % function startPrediction3D(obj)
    % predict datasets for 3D networks taken to a separate function
    % to improve performance

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
        saveImageOpt.dimOrder = 'yxzct';
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

    % prepeare options for loading of images
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
    end
    id = 1;     % indices of files
    patchCount = 1; % counter of processed patches

    %% TO DO:
    % 1. check situation, when the dataset for prediction is
    % smaller that then dataset for training: 2D and 3D cases
    % 2. check different padvalue in the code below: volPadded = padarray (vol, padSize, 0, 'post');

    nDims = 3;  % number of dimensions for data, 2 or 3

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
        vol = read(imgDS);
        volSize = size(vol, (1:3));
        [height, width, depth, color] = size(vol);
        [~, fn] = fileparts(imgDS.Files{id});

        if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'same')     % same
            if obj.BatchOpt.P_OverlappingTiles == false
                if height == inputPatchSize(1) && width == inputPatchSize(2)  && depth == inputPatchSize(3)     % 3.5552
                    [outputLabels, ~, scoreImg] = semanticseg(squeeze(vol), net, ...
                        'OutputType', 'uint8', 'ExecutionEnvironment', executionEnvironment, ...
                        'MiniBatchSize', obj.BatchOpt.P_MiniBatchSize{1});
                    if generateScoreFiles > 0 && generateScoreFiles < 4; scoreImg = uint8(scoreImg*255); end
                else    % 5.6641 sec
                    % pad image to have dimensions as multiples of patchSize
                    % see more in
                    % \\ad.helsinki.fi\home\i\ibelev\Documents\MATLAB\Examples\R2019b\deeplearning_shared\SemanticSegOfMultispectralImagesUsingDeepLearningExample\segmentImage.m
                    padSize(1) = inputPatchSize(1) - mod(height, inputPatchSize(1));
                    padSize(2) = inputPatchSize(2) - mod(width, inputPatchSize(2));
                    padSize(3) = inputPatchSize(3) - mod(depth, inputPatchSize(3));
                    volPadded = padarray(vol, padSize, 0, 'post');

                    [heightPad, widthPad, depthPad, colorPad] = size(volPadded);

                    outputLabels = zeros([heightPad, widthPad, depthPad], 'uint8');
                    if generateScoreFiles > 1 && generateScoreFiles < 4
                        scoreImg = zeros([heightPad, widthPad, depthPad, numClasses], 'uint8');
                        multipleScoreFactor = 255;
                    elseif generateScoreFiles == 4
                        scoreImg = zeros([heightPad, widthPad, depthPad, numClasses], 'single');
                        multipleScoreFactor = 1;
                    end

                    if obj.BatchOpt.showWaitbar
                        if pwb.getCancelState(); delete(pwb); return; end
                        iterNo = numel(1:inputPatchSize(3):depthPad) * ...
                            numel(1:inputPatchSize(2):widthPad) * ...
                            numel(1:inputPatchSize(1):heightPad);
                        pwb.increaseMaxNumberOfIterations(iterNo);
                    end

                    for k = 1:inputPatchSize(3):depthPad
                        for j = 1:inputPatchSize(2):widthPad
                            for i = 1:inputPatchSize(1):heightPad
                                patch = volPadded( i:i+inputPatchSize(1)-1,...
                                    j:j+inputPatchSize(2)-1,...
                                    k:k+inputPatchSize(3)-1,:);
                                [patchSeg, ~, scoreBlock] = semanticseg(squeeze(patch), net, ...
                                    'OutputType', 'uint8', 'ExecutionEnvironment', executionEnvironment, ...
                                    'MiniBatchSize', obj.BatchOpt.P_MiniBatchSize{1});

                                % act0 = activations(net, squeeze(patch),'ImageInputLayer');
                                % imtool(act0,[]);
                                % lName = 'Encoder-Stage-1-Conv-1';
                                % lName = 'Encoder-Stage-3-Conv-1';
                                % act1 = activations(net, squeeze(patch),lName);
                                % sz = size(act1);
                                % act1 = reshape(act1,[sz(1) sz(2) 1 sz(3)]);
                                % I = imtile(mat2gray(act1(:,:,:,1:min([size(act1, 4), 36]))),'GridSize',[6 6]);
                                % figure(1)
                                % imshow(I)

                                outputLabels(i:i+outputPatchSize(1)-1, ...
                                    j:j+outputPatchSize(2)-1, ...
                                    k:k+outputPatchSize(3)-1) = patchSeg;
                                if generateScoreFiles > 0
                                    scoreImg(i:i+outputPatchSize(1)-1, ...
                                        j:j+outputPatchSize(2)-1, ...
                                        k:k+outputPatchSize(3)-1,:) = scoreBlock*multipleScoreFactor;
                                end
                                if obj.BatchOpt.showWaitbar
                                    if pwb.getCancelState(); delete(pwb); return; end
                                    elapsedTime = toc(t1);
                                    if mod(patchCount, 10)
                                        timerValue = elapsedTime/patchCount*(pwb.getMaxNumberOfIterations()-patchCount);
                                        pwb.updateText(sprintf('%s\nHold on ~%.0f:%.2d mins left...', fn, floor(timerValue/60), mod(round(timerValue),60)));
                                    end
                                    pwb.increment();
                                end
                                patchCount = patchCount + 1;
                            end
                        end
                    end
                    % Remove the padding
                    outputLabels = outputLabels(1:height, 1:width, 1:depth);
                    if generateScoreFiles > 0; scoreImg = scoreImg(1:height, 1:width, 1:depth, :); end
                end
            else        % the section below is for obj.BatchOpt.P_OverlappingTiles == true
                % pad the image to include extended areas due to the overlapping strategy
                %padShift = (obj.BatchOpt.T_FilterSize{1}-1)*obj.BatchOpt.T_EncoderDepth{1};
                padShift = ceil(inputPatchSize(1)*obj.BatchOpt.P_OverlappingTilesPercentage{1}/100);
                padSize  = repmat(padShift, [1 nDims]);
                volPadded = padarray(vol, padSize, 0, 'both');

                % pad image to have dimensions as multiples of patchSize
                [heightPad, widthPad, depthPad, colorPad] = size(volPadded);
                outputPatchSize = max(inputPatchSize-padShift*2, 1);  % recompute output patch size, it is smaller than input patch size

                padSize(1) = ceil(heightPad/outputPatchSize(1))*outputPatchSize(1) + padShift*2 - heightPad;
                padSize(2) = ceil(widthPad/outputPatchSize(2))*outputPatchSize(2) + padShift*2 - widthPad;
                padSize(3) = ceil(depthPad/outputPatchSize(3))*outputPatchSize(3) + padShift*2 - depthPad;
                volPadded = padarray(volPadded, padSize, 0, 'post');

                [heightPad, widthPad, depthPad, colorPad] = size(volPadded);
                outputLabels = zeros([heightPad, widthPad, depthPad], 'uint8');
                if generateScoreFiles > 0 && multipleScoreFactor < 4
                    scoreImg = zeros([heightPad, widthPad, depthPad, numClasses], 'uint8');
                    multipleScoreFactor = 255;
                elseif generateScoreFiles == 4
                    scoreImg = zeros([heightPad, widthPad, depthPad, numClasses], 'single');
                    multipleScoreFactor = 1;
                end

                if obj.BatchOpt.showWaitbar
                    iterNo = numel(1:outputPatchSize(3):depthPad-outputPatchSize(3)+1) * ...
                        numel(1:outputPatchSize(2):widthPad-outputPatchSize(2)+1) * ...
                        numel(1:outputPatchSize(1):heightPad-outputPatchSize(1)+1);
                    pwb.increaseMaxNumberOfIterations(iterNo);
                end

                for k = 1:outputPatchSize(3):depthPad-outputPatchSize(3)+1
                    for j = 1:outputPatchSize(2):widthPad-outputPatchSize(2)+1
                        for i = 1:outputPatchSize(1):heightPad-outputPatchSize(1)+1
                            %try
                            patch = volPadded( i:i+inputPatchSize(1)-1,...
                                j:j+inputPatchSize(2)-1,...
                                k:k+inputPatchSize(3)-1,:);
                            %catch err
                            %    0
                            %end
                            [patchSeg, ~, scoreBlock] = semanticseg(squeeze(patch), net, ...
                                'OutputType', 'uint8', 'ExecutionEnvironment', executionEnvironment, ...
                                'MiniBatchSize', obj.BatchOpt.P_MiniBatchSize{1});
                            x1 = i + padShift - 1;
                            y1 = j + padShift - 1;
                            z1 = min(k + padShift - 1, depthPad);

                            outputLabels(x1:x1+outputPatchSize(1)-1, ...
                                y1:y1+outputPatchSize(2)-1, ...
                                z1:z1+outputPatchSize(3)-1) = patchSeg(padShift:padShift+outputPatchSize(1)-1, ...
                                padShift:padShift+outputPatchSize(2)-1, ...
                                padShift:padShift+outputPatchSize(3)-1);
                            if generateScoreFiles > 0
                                scoreImg(x1:x1+outputPatchSize(1)-1, ...
                                    y1:y1+outputPatchSize(2)-1, ...
                                    z1:z1+outputPatchSize(3)-1,:) = scoreBlock(padShift:padShift+outputPatchSize(1)-1, ...
                                    padShift:padShift+outputPatchSize(2)-1, ...
                                    padShift:padShift+outputPatchSize(3)-1,:)*multipleScoreFactor;
                            end

                            if obj.BatchOpt.showWaitbar
                                if pwb.getCancelState(); delete(pwb); return; end
                                elapsedTime = toc(t1);
                                if mod(patchCount, 10)
                                    timerValue = elapsedTime/patchCount*(pwb.getMaxNumberOfIterations()-patchCount);
                                    pwb.updateText(sprintf('%s\nHold on ~%.0f:%.2d mins left...', fn, floor(timerValue/60), mod(round(timerValue),60)));
                                end
                                pwb.increment();
                            end
                            patchCount = patchCount + 1;
                        end
                    end
                end

                % Remove the padding
                outputLabels = outputLabels(padShift+1:padShift+height, padShift+1:padShift+width, padShift+1:padShift+depth);
                if generateScoreFiles > 0
                    scoreImg = scoreImg(padShift+1:padShift+height, padShift+1:padShift+width, padShift+1:padShift+depth, :);
                end
            end
        else    % the section below is for obj.BatchOpt.T_ConvolutionPadding{1} == 'valid'
            padSizePre  = (inputPatchSize(1:3)-outputPatchSize(1:3))/2;
            padSizePost = (inputPatchSize(1:3)-outputPatchSize(1:3))/2 + (outputPatchSize(1:3)-mod(volSize,outputPatchSize(1:3)));
            volPadded = padarray(vol, padSizePre, 'symmetric', 'pre');
            volPadded = padarray(volPadded, padSizePost, 'symmetric', 'post');

            [heightPad, widthPad, depthPad, colorPad] = size(volPadded);

            outputLabels = zeros([height, width, depth], 'uint8');
            if generateScoreFiles > 0 && generateScoreFiles < 4
                scoreImg = zeros([height, width, depth, numClasses], 'uint8');
                multipleScoreFactor = 255;
            elseif generateScoreFiles == 4
                scoreImg = zeros([height, width, depth, numClasses], 'single');
                multipleScoreFactor = 1;
            end

            if obj.BatchOpt.showWaitbar
                if pwb.getCancelState(); delete(pwb); return; end
                iterNo = numel(1:outputPatchSize(3):depthPad-inputPatchSize(3)+1) * ...
                    numel(1:outputPatchSize(2):widthPad-inputPatchSize(2)+1) * ...
                    numel(1:outputPatchSize(1):heightPad-inputPatchSize(1)+1);
                pwb.increaseMaxNumberOfIterations(iterNo);
            end

            %                     % ----- test making patches for parallel computing ----
            %                     patchIndex = 1;
            %                     for k = 1:outputPatchSize(3):depthPad-inputPatchSize(3)+1
            %                         for j = 1:outputPatchSize(2):widthPad-inputPatchSize(2)+1
            %                             for i = 1:outputPatchSize(1):heightPad-inputPatchSize(1)+1
            %                                 patch{patchIndex} = squeeze(volPadded( i:i+inputPatchSize(1)-1,...
            %                                     j:j+inputPatchSize(2)-1,...
            %                                     k:k+inputPatchSize(3)-1,:));
            %                                 patchIndex = patchIndex + 1;
            %                             end
            %                         end
            %                     end
            %
            %                     scoreBlock = cell([patchIndex-1 1]);
            %                     parfor (patchId = 1:patchIndex-1, 2)
            %                         [patch{patchId}, ~, scoreBlock{patchId}] = semanticseg(patch{patchId}, net, 'OutputType', 'uint8', 'ExecutionEnvironment', executionEnvironment);
            %                     end
            %
            %                     patchId = 1;
            %                     for k = 1:outputPatchSize(3):depthPad-inputPatchSize(3)+1
            %                         for j = 1:outputPatchSize(2):widthPad-inputPatchSize(2)+1
            %                             for i = 1:outputPatchSize(1):heightPad-inputPatchSize(1)+1
            %                                 outputLabels(i:i+outputPatchSize(1)-1, ...
            %                                              j:j+outputPatchSize(2)-1, ...
            %                                              k:k+outputPatchSize(3)-1) = patch{patchId};
            %                                 scoreImg(i:i+outputPatchSize(1)-1, ...
            %                                          j:j+outputPatchSize(2)-1, ...
            %                                          k:k+outputPatchSize(3)-1,:) = scoreBlock{patchId}*255;
            %                                 patchId = patchId + 1;
            %                             end
            %                         end
            %                     end
            %                     % ------------- end of parfor procedure ------

            % Overlap-tile strategy for segmentation of volumes.
            for k = 1:outputPatchSize(3):depthPad-inputPatchSize(3)+1
                for j = 1:outputPatchSize(2):widthPad-inputPatchSize(2)+1
                    for i = 1:outputPatchSize(1):heightPad-inputPatchSize(1)+1
                        patch = volPadded( i:i+inputPatchSize(1)-1,...
                            j:j+inputPatchSize(2)-1,...
                            k:k+inputPatchSize(3)-1,:);
                        [patchSeg, ~, scoreBlock] = semanticseg(squeeze(patch), net, ...
                            'OutputType', 'uint8', 'ExecutionEnvironment', executionEnvironment, ...
                            'MiniBatchSize', obj.BatchOpt.P_MiniBatchSize{1});

                        outputLabels(i:i+outputPatchSize(1)-1, ...
                            j:j+outputPatchSize(2)-1, ...
                            k:k+outputPatchSize(3)-1) = patchSeg;
                        if generateScoreFiles > 0
                            scoreImg(i:i+outputPatchSize(1)-1, ...
                                j:j+outputPatchSize(2)-1, ...
                                k:k+outputPatchSize(3)-1,:) = scoreBlock*multipleScoreFactor;
                        end
                        if obj.BatchOpt.showWaitbar
                            if pwb.getCancelState(); delete(pwb); return; end
                            elapsedTime = toc(t1);
                            if mod(patchCount, 10)
                                timerValue = elapsedTime/patchCount*(pwb.getMaxNumberOfIterations()-patchCount);
                                pwb.updateText(sprintf('%s\nHold on ~%.0f:%.2d mins left...', fn, floor(timerValue/60), mod(round(timerValue),60)));
                            end
                            pwb.increment();
                        end
                        patchCount = patchCount + 1;
                    end
                end
            end

            % Crop out the extra padded region.
            outputLabels = outputLabels(1:height, 1:width, 1:depth);
            if generateScoreFiles > 1; scoreImg = scoreImg(1:height, 1:width, 1:depth, :); end
        end
        if obj.BatchOpt.showWaitbar; pwb.updateText('Saving results...'); end

        % Save results
        outputLabels = outputLabels - 1;    % remove the first "exterior" class
        % get filename template
        [~, fn] = fileparts(imgDS.Files{id});

        % depending on the selected output type
        switch obj.BatchOpt.P_ModelFiles{1}
            case 'MIB Model format'
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', ['Labels_' fn '.model']);

                %modelMaterialNames = {classNames{2:end}}';
                modelMaterialNames = classNames;
                modelMaterialNames(1) = [];
                modelMaterialColors = [modelMaterialColors; obj.modelMaterialColors]; %#ok<AGROW,PROP>

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
            case {'TIF compressed format', 'TIF uncompressed format'}
                if strcmp(obj.BatchOpt.P_ModelFiles{1}, 'TIF compressed format')
                    tifCompression = 'lzw';
                else
                    tifCompression = 'none';
                end
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', ['Labels_' fn '.tif']);
                imwrite(outputLabels(:,:,1), filename, 'tif', 'WriteMode', 'overwrite', 'Description', sprintf('DeepMIB segmentation: %s %s', obj.BatchOpt.Workflow{1}, obj.BatchOpt.Architecture{1}), 'Compression', tifCompression);
                for sliceId = 2:size(outputLabels, 3)
                    imwrite(outputLabels(:,:,sliceId), filename, 'tif', 'WriteMode', 'append', 'Compression', tifCompression);
                end
        end

        % check for cancel
        if obj.BatchOpt.showWaitbar && pwb.getCancelState(); delete(pwb); return; end

        % save score map
        if generateScoreFiles > 0
            if generateScoreFiles == 1    % 'Use AM format'
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', ['Score_' fn '.am']);
                %scoreImg = uint8(scoreImg*255);     % convert to 8bit and scale between 0-255
                scoreImg = permute(scoreImg, [1 2 4 3]);    % convert to [height, width, color, depth]

                amiraOpt.overwrite = 1;
                amiraOpt.showWaitbar = 0;
                amiraOpt.verbose = false;
                bitmap2amiraMesh(filename, scoreImg, [], amiraOpt);
            elseif generateScoreFiles == 4   %  4=='Use Matlab non-compressed format (range 0-1)'
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', ['Score_' fn '.mat']);
                utils.deepmib.saveImageParFor(filename, scoreImg, false, saveImageOpt);
            else    % 2=='Use Matlab non-compressed format', 3=='Use Matlab compressed format'
                filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', ['Score_' fn '.mibImg']);
                utils.deepmib.saveImageParFor(filename, scoreImg, generateScoreFiles-2, saveImageOpt);
            end
        end

        % copy original file to the results for easier evaluation
        %copyfile(fullfile(projDir, ImageSource, '01_input_images', rawFn), outputDir);
        if obj.BatchOpt.showWaitbar
            if obj.BatchOpt.showWaitbar && pwb.getCancelState(); delete(pwb); return; end
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

