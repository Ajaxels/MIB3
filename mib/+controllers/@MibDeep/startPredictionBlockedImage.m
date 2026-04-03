function startPredictionBlockedImage(obj)
    % function startPredictionBlockedImage(obj)
    % predict 2D/3D datasets using the blockedImage class
    % requires R2021a or newer

    % detect 2D or 3D architecture
    if ismember(obj.BatchOpt.Workflow{1}, {'3D Semantic'})
        if obj.BatchOpt.P_DynamicMasking == true
            mgsOpt.MsgBoxOnly = true;
            mgsOpt.Header = sprintf('Unfortunately, the dynamic masking mode is not yet implemented for 3D architectures!\n\nPlease uncheck "Dynamic masking" checkbox in the Predict tab');
            mgsOpt.Icon = 'puffin_error';
            utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Not implemented', mgsOpt);
            return;
        end
    end

    % detect dimension for the data
    switch obj.BatchOpt.Workflow{1}
        case {'2D Semantic', '2D Patch-wise'}
            dataDimension = 2;
        case '2.5D Semantic'
            dataDimension = 2.5;
        case '3D Semantic'
            dataDimension = 3;
    end

    if strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Preprocessing is not required') || ...
            strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Split files for training/validation') || ...
            strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Training')
        preprocessedSwitch = false;

        msg = sprintf('!!! Warning !!!\nYou are going to start prediction without preprocessing!\nConfirm that your images are located under\n\n%s\n\n%s\n%s\n\n%s', ...
            obj.BatchOpt.OriginalPredictionImagesDir, ...
            '- Images', '- Labels (optionally, when ground truth is present)', ...
            'Patch-wise mode is also allowing to have patches stored in subfolders');

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

    % detect patch-wise mode
    patchwiseWorkflowSwitch = false;
    patchwisePatchesPredictSwitch = false; % additional switch specifying prediction of patches that are stored in subfolders within Predict directory
    if strcmp(obj.BatchOpt.Workflow{1}, '2D Patch-wise')
        patchwiseWorkflowSwitch = true;
    end

    % get settings for export of score files
    % {'Do not generate', 'Use AM format', 'Use Matlab non-compressed format', 'Use Matlab compressed format', 'Use Matlab non-compressed format (range 0-1)'};
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

    if obj.BatchOpt.showWaitbar
        % make uiprogressdlg based waitbar
        pwb = PoolWaitbar(1, 'Creating image store for prediction...', [], 'Predicting dataset', obj.view.gui);
    end

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
            sprintf(['!!! Warning !!!\n\n' ...
            'The destination directories:\n- PredictionImages/ResultsModels\n- PredictionImages/ResultsScores\n\n' ...
            'in\n%s\n\n' ...
            'are not empty!\n\nShell the destination folders be emptied and prediction started?'], obj.BatchOpt.ResultingImagesDir), ...
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

    % isfolder(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels'))
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
                'FileExtensions', '.mibImg', 'ReadFcn', @mibDeepStoreLoadImages);
        else    % without preprocessing
            fnExtention = lower(['.' obj.BatchOpt.ImageFilenameExtension{1}]);
            if strcmp(obj.BatchOpt.Workflow{1}, '2D Patch-wise' )
                filelist = dir(obj.BatchOpt.OriginalPredictionImagesDir);
                if sum([filelist.isdir]) == 2  % no directories present, predict images under obj.BatchOpt.OriginalPredictionImagesDir
                    imgDS = imageDatastore(obj.BatchOpt.OriginalPredictionImagesDir, ...
                        'FileExtensions', fnExtention, ...
                        'IncludeSubfolders', false, ...
                        'ReadFcn', @(fn)mibDeepStoreLoadImages(fn, mibDeepStoreLoadImagesOpt));
                else
                    if isfolder(fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images'))
                        imgDS = imageDatastore(fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images'), ...
                            'FileExtensions', fnExtention, ...
                            'IncludeSubfolders', false, ...
                            'ReadFcn', @(fn)mibDeepStoreLoadImages(fn, mibDeepStoreLoadImagesOpt));
                    else
                        % patch-wise segmentation of individual patches
                        % stored under subfolders
                        imgDS = imageDatastore(fullfile(obj.BatchOpt.OriginalPredictionImagesDir), ...
                            'FileExtensions', fnExtention, ...
                            'IncludeSubfolders', true, ...
                            "LabelSource", "foldernames", ...
                            'ReadFcn', @(fn)mibDeepStoreLoadImages(fn, mibDeepStoreLoadImagesOpt));
                        if numel(unique(imgDS.Labels)) < 1
                            ME = MException('MyComponent:noSuchVariable:MissingFiles', ...
                                ['For the patch-wise mode the files needs to be arranged under "Images"/"Labels" subfolders\n' ...
                                'or under subfolders with names of each image class!\n\n' ...
                                'Please check directory with images for Prediction']);
                            throw(ME);
                        end
                        patchwisePatchesPredictSwitch = true;
                    end
                end
            else
                imagesSubfolder = 'Images';
                if ~isfolder(fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images'))
                    res = uiconfirm(obj.view.gui, ...
                        sprintf(['It is recommended to keep images for prediction under "Images" subfolder within the directory specified in \n\n' ...
                        '"Directories and Preprocessing" -> \n\t\t\t"Directory with images for prediction"\n\n' ...
                        'However "Images" subfolder was not found!\n\nWould you like to continue and predict images that are located under:\n' ...
                        '%s'], obj.BatchOpt.OriginalPredictionImagesDir), ...
                        'Missing Images subfolder', ...
                        'Options', {'Predict images','Cancel'}, ...
                        'Icon', 'warning');
                    if strcmp(res, 'Cancel');  if obj.BatchOpt.showWaitbar; delete(obj.wb); end; return; end
                    imagesSubfolder = [];
                end

                % semantic segmentation or patch-wise segmentation of large images
                imgDS = imageDatastore(fullfile(obj.BatchOpt.OriginalPredictionImagesDir, imagesSubfolder), ...
                    'FileExtensions', fnExtention, ...
                    'IncludeSubfolders', false, ...
                    'ReadFcn', @(fn)mibDeepStoreLoadImages(fn, mibDeepStoreLoadImagesOpt));
            end

            % if isfolder(fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images'))
            %     % semantic segmentation or patch-wise segmentation of large images
            %     imgDS = imageDatastore(fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images'), ...
            %         'FileExtensions', fnExtention, ...
            %         'IncludeSubfolders', false, ...
            %         'ReadFcn', @(fn)mibDeepStoreLoadImages(fn, mibDeepStoreLoadImagesOpt));
            % else
            %     % patch-wise segmentation of individual patches
            %     % stored under subfolders
            %     imgDS = imageDatastore(fullfile(obj.BatchOpt.OriginalPredictionImagesDir), ...
            %         'FileExtensions', fnExtention, ...
            %         'IncludeSubfolders', true, ...
            %         "LabelSource", "foldernames", ...
            %         'ReadFcn', @(fn)mibDeepStoreLoadImages(fn, mibDeepStoreLoadImagesOpt));
            %     if numel(unique(imgDS.Labels)) < 2
            %         ME = MException('MyComponent:noSuchVariable:MissingFiles', ...
            %             ['For the patch-wise mode the files needs to be arranged under "Images"/"Labels" subfolders\n' ...
            %             'or under subfolders with names of each image class!\n\n' ...
            %             'Please check directory with images for Prediction']);
            %         throw(ME);
            %     end
            %     patchwisePatchesPredictSwitch = true;
            % end
        end
    catch err
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Missing files');
        if obj.BatchOpt.showWaitbar; delete(obj.wb); end
        return;
    end

    if obj.BatchOpt.showWaitbar
        if pwb.getCancelState(); delete(pwb); return; end
        extraWaitbarInfo = '';
        if patchwisePatchesPredictSwitch; extraWaitbarInfo = ' for the patch-wise mode'; end
        pwb.updateText(sprintf('Loading network%s\nPlease wait...', extraWaitbarInfo));
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
        obj.view.Figure.P_OverlappingTilesPercentage.Enable = 'off';
    end

    %% Start prediction
    % Use the overlap-tile strategy to predict the labels for each volume.
    % Each test volume is padded to make the input size a multiple of the output size
    % of the network and compensates for the effects of valid convolution.
    % The overlap-tile algorithm selects overlapping patches, predicts the labels
    % for each patch by using the semanticseg function, and then recombines the patches.

    noFiles = numel(imgDS.Files);
    if obj.BatchOpt.showWaitbar
        if pwb.getCancelState(); delete(pwb); return; end   % check for cancel
        pwb.updateText(sprintf('Starting prediction%s\nPlease wait...', extraWaitbarInfo));
    end
    id = 1;     % indices of files

    %% TO DO:
    % 1. check situation, when the dataset for prediction is
    % smaller that then dataset for training: 2D and 3D cases
    % 2. check different padvalue in the code below: volPadded = padarray (vol, padSize, 0, 'post');

    % select gpu or cpu for prediction and define executionEnvironment
    selectedIndex = find(ismember(obj.view.Figure.GPUDropDown.Items, obj.view.Figure.GPUDropDown.Value));
    switch obj.view.Figure.GPUDropDown.Value
        case 'CPU only'
            if numel(obj.view.Figure.GPUDropDown.Items) > 2 % i.e. GPU is present
                gpuDevice([]);  % CPU only mode
            end
            executionEnvironment = 'cpu';
        case 'Multi-GPU'
            if patchwiseWorkflowSwitch
                % in the patchwise workflow classify function
                % compatible with multi-gpu is used
                executionEnvironment = 'multi-gpu';
            else
                % in other workflows semanticseg is used with is
                % not compatible with multi-gpu
                executionEnvironment = 'gpu';
            end

        case 'Parallel'
            executionEnvironment = 'parallel';
        otherwise
            gpuDevice(selectedIndex);   % choose selected GPU device
            executionEnvironment = 'gpu';
    end

    if patchwisePatchesPredictSwitch % images in Predict folder is stored in subfolders named as class names
        filenamesCell = strrep(imgDS.Files, imgDS.Folders, '');
        classNamesStr = repmat(strjoin(string(classNames'), ', '), [noFiles, 1]);
        try
            % works in R2023b, but does not in R2023a
            path1 = arrayfun(@fileparts, imgDS.Files, 'UniformOutput', true);
            [~, realClassCell] = arrayfun(@fileparts, path1, 'UniformOutput', true);
        catch err
            % works in R2023a
            path1 = arrayfun(@fileparts, imgDS.Files, 'UniformOutput', false);
            [~, realClassCell] = arrayfun(@fileparts, path1, 'UniformOutput', false);
        end
        predictedClassCell = cell([noFiles, 1]);
        probabilityMatrix = zeros([noFiles, numel(classNames)]);
        patchWiseOutout = table(filenamesCell, classNamesStr, realClassCell, predictedClassCell, probabilityMatrix);
        patchWiseOutout.Properties.VariableNames = {'Filename', 'ClassNames', 'RealClass', 'PredictedClass', 'MaxProbability'};
    end

    % use %% type of the progress dialog to use 5% increments, i.e.
    % for each file the progress bar will be updated 20 times to
    % follow the progress
    %if strcmp(obj.BatchOpt.Workflow{1}, '2.5D Semantic') && obj.BatchOpt.showWaitbar
    progressUpdatesPerFile = 1;
    if obj.BatchOpt.showWaitbar
        progressUpdatesPerFile = 20;
        pwb.updateMaxNumberOfIterations(noFiles*progressUpdatesPerFile);
    end

    t1 = tic;

    while hasdata(imgDS)
        % check for Cancel
        if obj.BatchOpt.showWaitbar && pwb.getCancelState(); delete(pwb); return; end

        % update block size
        if dataDimension == 2         % 2D case
            padShift = [0 0]; % pad shift for the overlap mode
            blockSize = [inputPatchSize(1) inputPatchSize(2)];
        else                % 2.5D and 3D case dataDimension == 2.5 or dataDimension == 3
            padShift = [0 0 0]; % pad shift for the overlap mode
            blockSize = [inputPatchSize(1) inputPatchSize(2) inputPatchSize(3)];
        end

        % correct block size depending on padding method and overlap mode
        if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'same') && obj.BatchOpt.P_OverlappingTiles % same padding + overlap mode
            %padShift = ceil(inputPatchSize(1)*obj.BatchOpt.P_OverlappingTilesPercentage{1}/100);
            padShift = ceil(inputPatchSize(1:numel(blockSize))*obj.BatchOpt.P_OverlappingTilesPercentage{1}/100);  % padShift(y,x,z) or padShift(y,x)
            blockSize = blockSize-padShift*2;
        elseif strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'valid')    % valid padding
            if dataDimension == 2 % 2D case
                blockSize = outputPatchSize(1:2);
            else    % 2.5D and 3D case dataDimension == 2.5 or dataDimension == 3
                blockSize = outputPatchSize(1:numel(outputPatchSize)-1);
            end
        end

        % read image
        vol = read(imgDS);
        [~, fn] = fileparts(imgDS.Files{id});

        % downsample the input image corresponding to the
        % downsampling factor
        if obj.BatchOpt.P_ImageDownsamplingFactor{1} ~= 1
            imResizeOpt.imgType = '3D';
            imResizeOpt.showWaitbar = false;
            if dataDimension == 2
                [imgHeight, imgWidth, noColors] = size(vol);
                imgDepth = 1;
            else
                [imgHeight, imgWidth, imgDepth, noColors] = size(vol);
            end
            if noColors > 1; imResizeOpt.imgType = '4D'; end
            imResizeOpt.width = round(imgWidth/obj.BatchOpt.P_ImageDownsamplingFactor{1});  % new width value, overrides the scale parameter
            imResizeOpt.height = round(imgHeight/obj.BatchOpt.P_ImageDownsamplingFactor{1});  % new height value, overrides the scale parameter
            imResizeOpt.depth = imgDepth;
            if dataDimension == 3 % for 3D downsample all dimensions
                imResizeOpt.depth = round(imgDepth/obj.BatchOpt.P_ImageDownsamplingFactor{1}); % % new depth value, overrides the scale parameter
            end
            vol = mibResize3d(vol, [], imResizeOpt);
        end

        % depth of the volume
        volDepth = size(vol, 3);
        nextWaitbarIterationFromZ = volDepth/progressUpdatesPerFile; % z-value when the progress bar needs to be updated

        if strcmp(obj.BatchOpt.Workflow{1}, '2.5D Semantic')
            blockSize(3) = inputPatchSize(3);   % update blockSize for 2.5D networks
            padShift(3) = 0;
            paddingValue = floor(inputPatchSize(3)/2);

            for zValue = 1:volDepth
                if zValue <= paddingValue
                    subVol = padarray(vol(:,:,max([zValue-paddingValue,1]):zValue+paddingValue), [0, 0, paddingValue-zValue+1], 'symmetric', 'pre');
                elseif zValue > volDepth-paddingValue
                    subVol = padarray(vol(:,:, zValue-paddingValue:min([zValue+paddingValue,volDepth])), [0, 0, zValue-volDepth+paddingValue], 'symmetric', 'post');
                else
                    subVol = vol(:,:,zValue-paddingValue:zValue+paddingValue);
                end

                [outputLabelsCurrent, scoreImgCurrent] = obj.processBlocksBlockedImage(subVol, zValue, net, ...
                    inputPatchSize, outputPatchSize, blockSize, padShift, ...
                    dataDimension, patchwiseWorkflowSwitch, patchwisePatchesPredictSwitch, ...
                    classNames, generateScoreFiles, executionEnvironment, fn);

                if zValue == 1
                    outputLabels = zeros([size(outputLabelsCurrent,1), size(outputLabelsCurrent,2), volDepth], 'uint8');
                    if generateScoreFiles > 0
                        if obj.ScoreExportOpt.IncludeExterior
                            noOutputClasses = size(scoreImgCurrent,3);
                        else
                            noOutputClasses = size(scoreImgCurrent,3)-1;
                        end
                        scoreImg = zeros([size(scoreImgCurrent,1), size(scoreImgCurrent,2), noOutputClasses, volDepth], class(scoreImgCurrent));
                    else
                        scoreImg = 0;
                    end
                end
                outputLabels(:,:,zValue) = outputLabelsCurrent; % (:,:,paddingValue+1);
                if generateScoreFiles > 0
                    % remove exterior
                    if ~obj.ScoreExportOpt.IncludeExterior; scoreImgCurrent = scoreImgCurrent(:,:,2:end,:); end
                    scoreImg(:,:,:,zValue) = scoreImgCurrent; % (:,:,:,paddingValue+1);
                end

                % check for Cancel
                if obj.BatchOpt.showWaitbar && pwb.getCancelState(); delete(pwb); return; end

                % update progress bar
                if obj.BatchOpt.showWaitbar && zValue >= nextWaitbarIterationFromZ
                    elapsedTime = toc(t1);
                    currIteration = pwb.getCurrentIteration()+1;
                    timerValue = elapsedTime/currIteration*(pwb.getMaxNumberOfIterations()-currIteration);
                    pwb.updateText(sprintf('%s\nHold on ~%.0f:%.2d mins left...', fn, floor(timerValue/60), mod(round(timerValue),60)));
                    pwb.increment();
                    nextWaitbarIterationFromZ = nextWaitbarIterationFromZ + volDepth/progressUpdatesPerFile;
                end
            end
        else   % '2D Semantic', '3D Semantic', '2D Patch-wise'
            % detect whether to use 2D net with 3D datasets, in this
            % case the full volume will be loaded and processed
            % slice-by-slice
            if dataDimension == 2       % 2D case
                if volDepth > 3 && size(vol, 3) ~= inputPatchSize(4)
                    use3DdatasetWith2Dnet = true;
                    pwb.setIncrement(1);
                else
                    use3DdatasetWith2Dnet = false;
                    pwb.setIncrement(progressUpdatesPerFile);
                end
            elseif dataDimension == 3
                use3DdatasetWith2Dnet = false;
                pwb.setIncrement(progressUpdatesPerFile);
            else
                use3DdatasetWith2Dnet = false;
                pwb.setIncrement(1);
            end

            if use3DdatasetWith2Dnet
                for zValue = 1:volDepth
                    [outputLabelsCurrent, scoreImgCurrent] = obj.processBlocksBlockedImage(squeeze(vol(:,:,zValue,:)), zValue, net, ...
                        inputPatchSize, outputPatchSize, blockSize, padShift, ...
                        dataDimension, patchwiseWorkflowSwitch, patchwisePatchesPredictSwitch, ...
                        classNames, generateScoreFiles, executionEnvironment, fn);
                    if zValue == 1
                        outputLabels = zeros([size(outputLabelsCurrent,1), size(outputLabelsCurrent,2), volDepth], 'uint8');
                        if generateScoreFiles > 0
                            if obj.ScoreExportOpt.IncludeExterior
                                noOutputClasses = size(scoreImgCurrent,3);
                            else
                                noOutputClasses = size(scoreImgCurrent,3)-1;
                            end
                            scoreImg = zeros([size(scoreImgCurrent,1), size(scoreImgCurrent,2), noOutputClasses, volDepth], class(scoreImgCurrent));
                        else
                            scoreImg = 0;
                        end
                    end
                    outputLabels(:,:,zValue) = outputLabelsCurrent;
                    if generateScoreFiles > 0
                        % remove exterior
                        if ~obj.ScoreExportOpt.IncludeExterior; scoreImgCurrent = scoreImgCurrent(:,:,2:end,:); end
                        scoreImg(:,:,:,zValue) = scoreImgCurrent;
                    end

                    % check for Cancel
                    if obj.BatchOpt.showWaitbar && pwb.getCancelState(); delete(pwb); return; end
                    % update progress bar
                    if obj.BatchOpt.showWaitbar && zValue >= nextWaitbarIterationFromZ
                        elapsedTime = toc(t1);
                        currIteration = pwb.getCurrentIteration()+1;
                        timerValue = elapsedTime/currIteration*(pwb.getMaxNumberOfIterations()-currIteration);
                        pwb.updateText(sprintf('%s\nHold on ~%.0f:%.2d mins left...', fn, floor(timerValue/60), mod(round(timerValue),60)));
                        pwb.increment();
                        nextWaitbarIterationFromZ = nextWaitbarIterationFromZ + volDepth/progressUpdatesPerFile;
                    end
                end
            else
                zValue = NaN;
                [outputLabels, scoreImg] = obj.processBlocksBlockedImage(vol, zValue, net, ...
                    inputPatchSize, outputPatchSize, blockSize, padShift, ...
                    dataDimension, patchwiseWorkflowSwitch, patchwisePatchesPredictSwitch, ...
                    classNames, generateScoreFiles, executionEnvironment, fn);
                
                % remove exterior
                if generateScoreFiles > 0 && ~obj.ScoreExportOpt.IncludeExterior
                    scoreImg = scoreImg(:,:,2:end,:);
                end

                % check for Cancel
                if obj.BatchOpt.showWaitbar && pwb.getCancelState(); delete(pwb); return; end
                % update progress bar
                if obj.BatchOpt.showWaitbar
                    elapsedTime = toc(t1);
                    currIteration = pwb.getCurrentIteration()+1;
                    timerValue = elapsedTime/currIteration*(pwb.getMaxNumberOfIterations()-currIteration);
                    pwb.updateText(sprintf('%s\nHold on ~%.0f:%.2d mins left...', fn, floor(timerValue/60), mod(round(timerValue),60)));
                    pwb.increment();
                end
            end
        end

        % upsample results beased on downsampling factor
        if obj.BatchOpt.P_ImageDownsamplingFactor{1} ~= 1
            imResizeOpt.imgType = '3D';
            imResizeOpt.width = imgWidth;  % upsample width value, overrides the scale parameter
            imResizeOpt.height = imgHeight;  % upsample height value, overrides the scale parameter
            imResizeOpt.depth = imgDepth;
            imResizeOpt.method = 'nearest';
            outputLabels = mibResize3d(outputLabels, [], imResizeOpt);

            % % smooth models for 2 classes outputs
            if numClasses == 2
                smoothOptions.dataType = '3D';
                smoothOptions.fitType = 'Gaussian';
                smoothOptions.showWaitbar = false;
                smoothOptions.sigma = obj.BatchOpt.P_ImageDownsamplingFactor{1}+1;
                if dataDimension == 3
                    smoothOptions.filters3DCheck = 1;
                    smoothOptions.hSize = [obj.BatchOpt.P_ImageDownsamplingFactor{1}*2+1 obj.BatchOpt.P_ImageDownsamplingFactor{1}*2+1];
                else
                    smoothOptions.filters3DCheck = 0;
                    smoothOptions.hSize = obj.BatchOpt.P_ImageDownsamplingFactor{1}*2+1;
                end
                outputLabels = mibDoImageFiltering(outputLabels, smoothOptions);
            end

            if generateScoreFiles > 0
                imResizeOpt.imgType = '4D';
                scoreImg = mibResize3d(scoreImg, [], imResizeOpt);
            end
        end

        % Save results
        if ~patchwisePatchesPredictSwitch % standard semantic segmentation mode or patch-wise mode when prediction images are not in patches
            % depending on the selected output type
            switch obj.BatchOpt.P_ModelFiles{1}
                case 'MIB Model format'
                    modelMaterialNames = classNames;
                    if ~patchwiseWorkflowSwitch; modelMaterialNames(1) = []; end % remove Exterior

                    modelMaterialColors = [modelMaterialColors; obj.modelMaterialColors]; %#ok<AGROW,PROP>
                    filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', ['Labels_' fn '.model']);
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
                    imwrite(outputLabels(:,:,1), filename, 'tif', 'WriteMode', 'overwrite', 'Description', sprintf('DeepMIB segmentation: $s %s', obj.BatchOpt.Workflow{1}, obj.BatchOpt.Architecture{1}), 'Compression', tifCompression);
                    if dataDimension ~= 2 || use3DdatasetWith2Dnet % 2.5D and 3D case dataDimension == 2.5 or dataDimension == 3
                        for sliceId = 2:size(outputLabels, 3)
                            imwrite(outputLabels(:,:,sliceId), filename, 'tif', 'WriteMode', 'append', 'Compression', tifCompression);
                        end
                    end
            end
            %
            %                     % save score map
            if generateScoreFiles > 0
                if generateScoreFiles == 1    % 'Use AM format'
                    filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', ['Score_' fn '.am']);
                    amiraOpt.overwrite = 1;
                    amiraOpt.showWaitbar = 0;
                    amiraOpt.verbose = false;
                    bitmap2amiraMesh(filename, scoreImg, [], amiraOpt);
                elseif generateScoreFiles == 4   %  4=='Use Matlab non-compressed format (range 0-1)'
                    filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', ['Score_' fn '.mat']);
                    saveImageParFor(filename, scoreImg, false, saveImageOpt);
                else  % 2=='Use Matlab non-compressed format', 3=='Use Matlab compressed format'
                    filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', ['Score_' fn '.mibImg']);
                    saveImageParFor(filename, scoreImg, generateScoreFiles, saveImageOpt);
                end
            end
        else    % patchwisePatchesPredictSwitch == true, patch-wise mode, when each patch is contained in its own subfolder
            %                     outputLabels = gather(outputLabels, 'Level', 1); % convert blocked image to normal matrix
            patchWiseOutout.PredictedClass{id} = char(outputLabels);
            scoreImg = gather(scoreImg, 'Level', 1); % convert blocked image to normal matrix
            patchWiseOutout.MaxProbability(id,:) = squeeze(max(scoreImg,[], 1:2))';
        end
        id=id+1;
    end

    % save the resulting file
    if patchwisePatchesPredictSwitch == true
        % generate CSV files for the patch-wise segmentations
        filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', 'patchPredictionResults.csv');
        writetable(patchWiseOutout, filename, 'FileType' , 'Text');
        filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', 'patchPredictionResults.mat');
        save(filename, 'patchWiseOutout', '-mat');
    end
    fprintf('Prediction finished: ');
    toc(t1)

    % count user's points
    obj.mibModel.preferences.Users.Tiers.numberOfInferencedDeepNetworks = obj.mibModel.preferences.Users.Tiers.numberOfInferencedDeepNetworks+1;
    eventdata = ToggleEventData(4);    % scale scoring by factor 5
    notify(obj.mibModel, 'UpdateUserScore', eventdata);
    if obj.BatchOpt.showWaitbar; delete(pwb); end
end

