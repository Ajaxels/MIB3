function processImages(obj, preprocessFor)
    % function processImages(obj, preprocessFor)
    % Preprocess images for training and prediction
    %
    % Parameters:
    % preprocessFor: a string with target, 'training', 'prediction'

    if nargin < 2
        mgsOpt.MsgBoxOnly = true;
        header = sprintf('processImages: the second parameter is required!');
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Preprocessing error', mgsOpt);
        return; 
    end

    % init preprocessing images for the instance segmentation
    if strcmp(obj.BatchOpt.Workflow{1}, '2D Instance')
        obj.processImagesForInstanceSegmentation(preprocessFor);
        selection = uiconfirm(obj.view.gui, ...
            sprintf('The labels were preprocessed!\n\nNow the preprocessed images needs to be split for training and validation.\nDo you want to do that now?'), ...
            'Preprocessing labels',...
            'Options', {'Split labels', 'Change preprocess to split but do not split', 'Do nothing'},...
            'DefaultOption', 1, 'CancelOption', 3,...
            'Icon', 'info');
        switch selection
            case 'Do nothing'
                obj.view.handles.PreprocessingMode.Value = 'Preprocessing is not required';
                obj.BatchOpt.PreprocessingMode{1} = 'Preprocessing is not required';
            case 'Change preprocess to split but do not split'
                obj.view.handles.PreprocessingMode.Value = 'Split files for training/validation';
                obj.BatchOpt.PreprocessingMode{1} = 'Split files for training/validation';
            case 'Split labels'
                obj.view.handles.PreprocessingMode.Value = 'Split files for training/validation';
                obj.BatchOpt.PreprocessingMode{1} = 'Split files for training/validation';
                obj.startPreprocessing();
        end
        %obj.view.handles.PreprocessingMode.Value = 'Preprocessing is not required';
        %obj.BatchOpt.PreprocessingMode{1} = 'Preprocessing is not required';
        return;
    end

    if strcmp(preprocessFor, 'training')
        imageDirIn = obj.BatchOpt.OriginalTrainingImagesDir;
        imageFilenameExtension = obj.BatchOpt.ImageFilenameExtensionTraining{1};
        trainingSwitch = 1;     % a switch indicating processing of images for training
        mibBioformatsCheck = obj.BatchOpt.BioformatsTraining;   % to use or not BioFormats reader
        BioFormatsIndices = obj.BatchOpt.BioformatsTrainingIndex{1};  % serie index for bio-formats
    elseif strcmp(preprocessFor, 'prediction')
        imageDirIn = obj.BatchOpt.OriginalPredictionImagesDir;
        imageFilenameExtension = obj.BatchOpt.ImageFilenameExtension{1};
        trainingSwitch = 0;
        mibBioformatsCheck = obj.BatchOpt.Bioformats;
        BioFormatsIndices = obj.BatchOpt.BioformatsIndex{1};  % serie index for bio-formats
    else
        mgsOpt.MsgBoxOnly = true;
        header = sprintf('processImages: the second parameter is wrong!');
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Preprocessing error', mgsOpt);
        return;
    end

    %% Load data
    if ~isfolder(fullfile(imageDirIn, 'Images'))
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.WindowWidth = 600;
        mgsOpt.WindowHeight = 200;
        msgText = sprintf('The images and models should be arranged in "Images" and "Labels" directories under\n\n%s\n\nCopy files there and try again!', imageDirIn);
        utils.dlgs.inputUniversalDlg(obj.view.gui, '', {}, {msgText}, 'Old project or missing files', mgsOpt);
        return;
    end

    if obj.BatchOpt.showWaitbar
        pwb = core.PoolWaitbar(1, sprintf('Creating image datastore\nPlease wait...'), obj.view.gui, ...
            sprintf('%s %s: processing for %s', obj.BatchOpt.Workflow{1}, obj.BatchOpt.Architecture{1}, preprocessFor));
    else
        pwb = [];
    end
    warning('off', 'MATLAB:MKDIR:DirectoryExists');

    % make datastore for images
    try
        getDataOptions.verbose = false;
        getDataOptions.mibBioformatsCheck = mibBioformatsCheck;
        getDataOptions.BioFormatsIndices = BioFormatsIndices;
        imgDS = imageDatastore(fullfile(imageDirIn, 'Images'), ...
            'FileExtensions', lower(['.' imageFilenameExtension]), ...
            'IncludeSubfolders', false, ...
            'ReadFcn', @(fn)io.loadImagesWrapper(fn, getDataOptions));
    catch err
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Missing files');
        if obj.BatchOpt.showWaitbar; delete(pwb); end
        return;
    end

    % preparing the directories
    % delete exising directories and files
    try
        if trainingSwitch
            if isfolder(fullfile(obj.BatchOpt.ResultingImagesDir, 'TrainImages'))
                rmdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'TrainImages'), 's');
            end
            if isfolder(fullfile(obj.BatchOpt.ResultingImagesDir, 'TrainLabels'))
                rmdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'TrainLabels'), 's');
            end
            if isfolder(fullfile(obj.BatchOpt.ResultingImagesDir, 'ValidationImages'))
                rmdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'ValidationImages'), 's');
            end
            if isfolder(fullfile(obj.BatchOpt.ResultingImagesDir, 'ValidationLabels'))
                rmdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'ValidationLabels'), 's');
            end
        else
            if isfolder(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'GroundTruthLabels'))
                rmdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'GroundTruthLabels'), 's');
            end
            if isfolder(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages'))
                rmdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages'), 's');
            end
        end
    catch err
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Problems with removing directories');
        if obj.BatchOpt.showWaitbar; delete(pwb); end
        return;
    end

    % make new directories
    if trainingSwitch
        mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'TrainImages'));
        mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'TrainLabels'));
        mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'ValidationImages'));
        mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'ValidationLabels'));
    else
        mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages'));
        mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores'));
        mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels'));
        mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'GroundTruthLabels'));
    end

    if obj.BatchOpt.showWaitbar
        if pwb.getCancelState(); delete(pwb); return; end
        pwb.updateText(sprintf('Acquiring class names\nPlease wait...'));
    end

    GroundTruthModelSwitch = 0;     % models exists
    classNames = {'Exterior'};

    if strcmp(obj.BatchOpt.ModelFilenameExtension{1}, 'MODEL')
        % read number of materials for the first file
        files = dir(fullfile(imageDirIn, 'Labels', '*.model'));
        if isempty(files) && trainingSwitch
            mgsOpt.MsgBoxOnly = true;
            header = sprintf('Model files are missing in\n%s', fullfile(imageDirIn, 'Labels'));
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Missing model files!', mgsOpt);
            if obj.BatchOpt.showWaitbar; delete(pwb); end
            return;
        elseif ~isempty(files)
            modelFn = fullfile(files(1).folder, files(1).name);
            res = load(modelFn, '-mat', 'modelMaterialNames');
            classNames = [{'Exterior'}; res.modelMaterialNames];    % add Exterior
            GroundTruthModelSwitch = 1;     % models exists
        end
    else
        classNames = arrayfun(@(x) sprintf('Class%.2d', x), 1:obj.BatchOpt.T_NumberOfClasses{1}-1, 'UniformOutput', false);
        classNames = [{'Exterior'}; classNames'];
        files = dir(fullfile(imageDirIn, 'Labels', lower(['*.' obj.BatchOpt.ModelFilenameExtension{1}]))); % extensions on Linux are case sensitive

        if ~isempty(files)
            GroundTruthModelSwitch = 1;     % models exists
        end
    end

    % update number of classes variables
    if trainingSwitch
        obj.BatchOpt.T_NumberOfClasses{1} = numel(classNames);
        obj.view.handles.T_NumberOfClasses.Value = obj.BatchOpt.T_NumberOfClasses{1};
        obj.view.handles.NumberOfClassesPreprocessing.Value = obj.BatchOpt.T_NumberOfClasses{1};
    end

    %% Process images and split them to training and validation dirs
    NumFiles = length(imgDS.Files);

    if trainingSwitch
        % init random generator
        if obj.BatchOpt.RandomGeneratorSeed{1} == 0
            rng('shuffle');
        else
            rng(obj.BatchOpt.RandomGeneratorSeed{1}, 'twister');
        end
        randIndices = randperm(NumFiles);   % Random permutation of integers
        validationIndices = randIndices(1:ceil(obj.BatchOpt.ValidationFraction{1}*NumFiles));   % get indices of images to be used for validation
        if numel(validationIndices) == NumFiles
            mgsOpt.MsgBoxOnly = true;
            header = sprintf('With the current settings all images are assigned to the validation set!\nPlease decrease the value in the "Fraction of images for validation" edit box and try again!');
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Validation set is too large', mgsOpt);
            if obj.BatchOpt.showWaitbar; delete(pwb); end
            return;
        end
    else
        validationIndices = zeros([NumFiles, 1]);   % do not create validation data
    end

    % define usage of parallel computing
    if obj.BatchOpt.UseParallelComputing
        parforArg = obj.view.handles.PreprocessingParForWorkers.Value;    % Maximum number of workers running in parallel
        if isempty(gcp('nocreate')); parpool(parforArg); end % create parpool
    else
        parforArg = 0;      % Maximum number of workers running in parallel, when 0 a single core used without parallel
    end

    % create local variables for parfor
    mode2D3DParFor = obj.BatchOpt.Workflow{1}(1:2);
    MaskAwayParFor = obj.BatchOpt.MaskAway;
    ResultingImagesDirParFor = obj.BatchOpt.ResultingImagesDir;
    showWaitbarParFor = obj.BatchOpt.showWaitbar;
    compressImages = obj.BatchOpt.CompressProcessedImages;
    compressModels = obj.BatchOpt.CompressProcessedModels;
    maskVariable = 'maskImg';   % variable that has mask inside *.mask files
    SingleModelTrainingFileParFor = obj.BatchOpt.SingleModelTrainingFile;

    if obj.BatchOpt.showWaitbar
        if pwb.getCancelState(); delete(pwb); return; end
        pwb.updateText(sprintf('Processing images\nPlease wait...'));
        pwb.setIncrement(10);  % set increment step to 10
    end

    maskDS = [];
    modDS = [];
    saveModelOpt = struct();

    if GroundTruthModelSwitch
        if strcmp(obj.BatchOpt.Workflow{1}(1:2), '2D')  % preprocess files for 2D networks
            if SingleModelTrainingFileParFor
                fileList = dir(fullfile(imageDirIn, 'Labels', '*.model'));
                fullModelPathFilenames = arrayfun(@(filename) fullfile(imageDirIn, 'Labels', cell2mat(filename)), {fileList.name}, 'UniformOutput', false);  % generate full paths
                modDS = matfile(fullModelPathFilenames{1});     % models

                if MaskAwayParFor && trainingSwitch     % do not use masks for prediction
                    fileList = dir(fullfile(imageDirIn, 'Masks', '*.mask'));
                    if ~isempty(fileList)
                        fullMaskPathFilenames = arrayfun(@(filename) fullfile(imageDirIn, 'Masks', cell2mat(filename)), {fileList.name}, 'UniformOutput', false);  % generate full paths
                        maskDS = matfile(fullMaskPathFilenames{1});
                    else
                        mgsOpt.MsgBoxOnly = true;
                        header = sprintf('The mask files were not found!\nPlace *.mask files under\n\n%s', fullfile(imageDirIn, 'Masks'));
                        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Mask is missing', mgsOpt);
                        if obj.BatchOpt.showWaitbar; delete(pwb); end
                        return;
                    end
                end
            else
                switch obj.BatchOpt.ModelFilenameExtension{1}
                    case 'MODEL'
                        modDS = imageDatastore(fullfile(imageDirIn, 'Labels'), ...
                            'IncludeSubfolders', false, ...
                            'FileExtensions', '.model', 'ReadFcn', @utils.deepmib.storeLoadModel);
                        % I = readimage(modDS,1);  % read model test
                        % reset(modDS);
                    otherwise
                        modDS = imageDatastore(fullfile(imageDirIn, 'Labels'), ...
                            'IncludeSubfolders', false, ...
                            'FileExtensions', lower(['.' obj.BatchOpt.ModelFilenameExtension{1}]));
                end
                if numel(modDS.Files) ~= numel(imgDS.Files)
                    mgsOpt.MsgBoxOnly = true;
                    header = sprintf('In this mode number of model files should match number of image files!');
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Files number mismatch!', mgsOpt);
                    if obj.BatchOpt.showWaitbar; delete(pwb); end
                    return;
                end

                if MaskAwayParFor && trainingSwitch     % do not use masks for prediction
                    try
                        switch obj.BatchOpt.MaskFilenameExtension{1}
                            case 'MASK'
                                maskDS = imageDatastore(fullfile(imageDirIn, 'Masks'), ...
                                    'IncludeSubfolders', false, ...
                                    'FileExtensions', '.mask', 'ReadFcn', @utils.deepmib.storeLoadImages);
                            otherwise
                                maskDS = imageDatastore(fullfile(imageDirIn, 'Masks'), ...
                                    'IncludeSubfolders', false, 'FileExtensions', lower(['.' obj.BatchOpt.MaskFilenameExtension{1}]));
                        end
                    catch err
                        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Missing masks');
                        if obj.BatchOpt.showWaitbar; delete(pwb); end
                        return;
                    end

                    if numel(maskDS.Files) ~= numel(imgDS.Files)
                        mgsOpt.MsgBoxOnly = true;
                        header = sprintf('In this mode number of mask files should match number of image files!');
                        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Number of files mismatch', mgsOpt);
                        if obj.BatchOpt.showWaitbar; delete(pwb); end
                        return;
                    end
                end
            end
        else    % preprocess files for 3D networks
            % these variable needed for parfor loop
            try
                modDS = imageDatastore(fullfile(imageDirIn, 'Labels'), ...
                    'IncludeSubfolders', false, ...
                    'FileExtensions', '.model', 'ReadFcn', @utils.deepmib.storeLoadModel);
                if MaskAwayParFor && trainingSwitch     % do not use masks for prediction
                    maskDS = imageDatastore(fullfile(imageDirIn, 'Masks'), ...
                        'IncludeSubfolders', false, ...
                        'FileExtensions', '.mask', 'ReadFcn', @utils.deepmib.storeLoadImages);
                end
            catch err
                utils.dlgs.showErrorDialog(obj.view.gui, err, 'Missing files');
                if obj.BatchOpt.showWaitbar; delete(pwb); end
                return;
            end
            %outModelFull = zeros([1 1 numel(imgDS.Files)]);
            %maskDS = zeros([1 1 numel(imgDS.Files)]);
        end    % read corresponding model
    end

    % define saveModelOpt structure for saving files
    % generate colors
    if exist('classColors', 'var') == 0
        if numel(classNames) < 7
            classColors = obj.colormap6;
        elseif numel(classNames) < 21
            classColors = obj.colormap20;
        else
            classColors = obj.colormap255;
        end
    end

    if strcmp(mode2D3DParFor, '2D')
        saveImageOpt.dimOrder = 'yxczt';
        saveModelOpt.dimOrder = 'yxczt';
    else
        saveImageOpt.dimOrder = 'yxzct';
        saveModelOpt.dimOrder = 'yxzct';
    end
    saveModelOpt.modelType = 63;
    saveModelOpt.modelMaterialNames = classNames;
    saveModelOpt.modelMaterialColors = classColors;

    if SingleModelTrainingFileParFor && ~isempty(modDS)
        if numel(modDS.Files) < NumFiles
            mgsOpt.MsgBoxOnly = true;
            header = sprintf('Number of slices in the model file is smaller than number of images\n\nYou may want to uncheck the "Single MIB model file" checkbox!');
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong model file', mgsOpt);
            if showWaitbarParFor; delete(pwb); end
            return;
        end
    end

    convertToRGB = 0;
    %             if strcmp(obj.BatchOpt.Architecture{1}, 'DeepLab v3+')
    %                 mibImg = readimage(imgDS, 1);   % read image as [height, width, color, depth]
    %                 if size(mibImg,3) == 1 % grayscale image needs to be converted to RGB
    %                     convertToRGB = 1;
    %                 end
    %                 reset(imgDS);
    %             end

    if showWaitbarParFor
        pwb.setCurrentIteration(0);
        pwb.updateMaxNumberOfIterations(NumFiles);
    end

    parfor (imgId=1:NumFiles, parforArg)
        %for imgId=1:NumFiles
        % Define output directories
        % Split data into training, validation and test sets based
        % on obj.BatchOpt.ValidationFraction{1} value
        if trainingSwitch
            if isempty(find(validationIndices == imgId, 1))    %(imgId <= floor((1-obj.BatchOpt.ValidationFraction{1})*NumFiles))
                imDir = fullfile(ResultingImagesDirParFor, 'TrainImages');
                labelDir = fullfile(ResultingImagesDirParFor, 'TrainLabels');
            else
                imDir = fullfile(ResultingImagesDirParFor, 'ValidationImages');
                labelDir = fullfile(ResultingImagesDirParFor, 'ValidationLabels');
            end
        else
            imDir = fullfile(ResultingImagesDirParFor, 'PredictionImages');
            labelDir = fullfile(ResultingImagesDirParFor, 'PredictionImages', 'GroundTruthLabels');
        end

        mibImg = readimage(imgDS, imgId);   % read image as [height, width, depth, color, time]
        if convertToRGB % grayscale image needs to be converted to RGB
            mibImg = repmat(mibImg, [1, 1, 1, 3, 1]);
        end

        [~, fnOut] = fileparts(imgDS.Files{imgId});    % get filename of the image
        %                 if obj.BatchOpt.NormalizeImages
        %                     fprintf('!!! Warning !!! Normalizing images!\n')
        %                     outImg = obj.channelWisePreProcess(outImg);     % normalize the signals, remove outliers and scale between 0 and 1
        %                 end

        % saving image
        fn = fullfile(imDir, sprintf('%s.mibImg', fnOut));
        saveImageParFor(fn, mibImg, compressImages, saveImageOpt);

        if GroundTruthModelSwitch
            if strcmp(mode2D3DParFor, '2D')
                if SingleModelTrainingFileParFor
                    mibImg = modDS.(modDS.modelVariable)(:,:,imgId);    % get 2D slice from the model
                    [~, fnModOut] = fileparts(imgDS.Files{imgId});    % get filename for the model
                    fnModOut = sprintf('Labels_%s', fnModOut);  % generate name for the output model file

                    if MaskAwayParFor && trainingSwitch
                        maskImg = maskDS.(maskVariable)(:,:,imgId);
                        mibImg = single(mibImg);
                        mibImg(maskImg==1) = NaN;
                    end
                    mibImg = categorical(mibImg, 0:numel(classNames)-1, classNames);    % convert to categorial
                else
                    mibImg = readimage(modDS, imgId);      % read corresponding model
                    if MaskAwayParFor && trainingSwitch
                        outMask = readimage(maskDS, imgId);
                        mibImg = single(mibImg);
                        mibImg(outMask==1) = NaN;
                    end
                    mibImg = categorical(mibImg, 0:numel(classNames)-1, classNames);    % convert to categorical
                    [~, fnModOut] = fileparts(modDS.Files{imgId});    % get filename for the model
                end
            else   % 3D case
                mibImg = readimage(modDS, imgId);      % read corresponding model
                if MaskAwayParFor && trainingSwitch
                    outMask = readimage(maskDS, imgId);
                    mibImg = single(mibImg);
                    mibImg(outMask==1) = NaN;
                end
                mibImg = categorical(mibImg, 0:numel(classNames)-1, classNames);    % convert to categorical
                [~, fnModOut] = fileparts(modDS.Files{imgId});    % get filename for the model
            end

            fn = fullfile(labelDir, sprintf('%s.mibCat', fnModOut));
            saveImageParFor(fn, mibImg, compressModels, saveModelOpt);
        end
        %if pwb.getCancelState(); delete(pwb); imgId = numFiles; end
        if showWaitbarParFor && mod(imgId, 10) == 1; increment(pwb); end
    end
    if obj.BatchOpt.showWaitbar; delete(pwb); end
end

