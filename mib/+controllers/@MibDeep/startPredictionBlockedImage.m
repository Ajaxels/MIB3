function startPredictionBlockedImage(obj)
% STARTPREDICTIONBLOCKEDIMAGE - predict 2D/3D datasets using the blockedImage class.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.startPredictionBlockedImage()
%
% requires R2021a or newer
%
% **OME-Zarr images** (``BatchOpt.ImageFilenameExtension = 'ZARR'``). Each zarr
% store (v2 or v3, detected per store) is predicted from one pyramid level,
% ``BatchOpt.BioformatsIndex`` (1 = full resolution). Zarr stores are larger than
% memory as a rule, so a store is never loaded whole: ``predictZarrStore`` reads
% it in Z-slabs, predicts each slab and writes it to the outputs before reading
% the next one (the slab depth, the halo of the 2.5D/3D networks and the memory
% check are described there). The stores are listed and checked by
% ``checkZarrStores`` before any output is deleted or the network is loaded
% (level present in every store, integer pixels). Stores are folders, so the
% datastore is an ``arrayDatastore`` of store indices, and ``predictionFiles``
% replaces ``imgDS.Files`` for the file names. Preprocessing for prediction is not
% available for zarr images.
%
% With the standard model formats the result is saved at the resolution of the
% predicted level. TIF files and the zarr stores are written slab by slab; "MIB
% Model format" and the AM, mibImg and mat score files hold the whole level in one
% array, so ``predictZarrStore`` gathers them and they are saved here as for other
% images (its memory check counts them).
%
% **BigData model output** (``BatchOpt.P_ModelFiles = 'Zarr3 (BigData model)'``,
% any type of input images; here the semantic workflows, 2D Instance is in
% ``startPredictionInstances``). For each image ``writeModelStore`` creates a
% ``core.MibBigDataLabels`` store. For zarr images it mirrors the pyramid of the
% source store, so it opens as an editable model of the image in BigData mode, and
% it is written slab by slab (``createModelStore``, ``writeModelStoreSlab``); the
% finer levels are left to the level map, so no full-resolution array is built.
% Other images have no pyramid: one is generated from the size of the prediction
% (``writeModelStore``). The destination (``Labels_<image name>.zarr3`` next to the
% images by default, see ``obj.ZarrModelOpt``) and the overwriting of existing
% stores are confirmed by ``selectModelStoreDestination`` before the run, once
% the list of images is known. With ``BatchOpt.P_ModelFiles = 'Do not generate'``
% no model files are written.
%
% **BigData score output** (``BatchOpt.P_ScoreFiles = 'Zarr3 (BigData)'``, any type
% of input images, the semantic workflows only, checked in ``start``). Each image
% gets ``Score_<image name>.zarr3`` (``.zarr2`` as set), an *image* store, not a
% model: the scores of the predicted level as uint8 (0-255) with one channel per
% class (``[y x z c]``; the Exterior class only with
% ``obj.ScoreExportOpt.IncludeExterior``). It is written by
% ``io.savers.Zarr3Saver.save`` (for zarr images ``saveStream``, fed slab by slab
% by ``predictZarrStore``) with the settings of ``obj.ScoreExportOpt``
% (``updateScoreExportSettings``: format, destination, levels, chunks, shards,
% compression, downsampling method). For zarr images the pyramid is that of the
% image from the predicted level down (that level becomes level 1 of the store)
% and the voxel size is the image's scaled to the predicted level. Other images get
% an automatic XY pyramid (chunk ``[256 256 16]``) and voxel size 1. The group
% carries the ``mibPredictionScores`` attribute (class names), so
% ``MibDeep.isPredictionStore`` keeps the store out of the next prediction. The
% destination is chosen by ``selectModelStoreDestination(..., 'score')``.

    % detect 2D or 3D architecture
    if ismember(obj.BatchOpt.Workflow{1}, {'3D Semantic'})
        if obj.BatchOpt.P_DynamicMasking == true
            mgsOpt.MsgBoxOnly = true;
            mgsOpt.headerLines = 2;
            mgsOpt.WindowHeight = 180;
            utils.dlgs.inputUniversalDlg(obj.view.gui, 'Unfortunately, the dynamic masking mode is not yet implemented for 3D architectures!', {}, {'Please uncheck "Dynamic masking" checkbox in the Predict tab'}, 'Not implemented', mgsOpt);
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

        msg = sprintf('You are going to start prediction without preprocessing!\nConfirm that your images are located under\n\n%s\n\n%s\n%s\n\n%s', ...
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

    % OME-Zarr images: each store is predicted from one pyramid level, slab by slab
    % (predictZarrStore); check every store before anything is deleted or the network is loaded
    zarrInput = strcmp(obj.BatchOpt.ImageFilenameExtension{1}, 'ZARR');
    zarrOutput = strcmp(obj.BatchOpt.P_ModelFiles{1}, 'Zarr3 (BigData model)');
    zarrScores = strcmp(obj.BatchOpt.P_ScoreFiles{1}, 'Zarr3 (BigData)');   % zarr outputs are available for any type of input images
    if zarrInput
        if preprocessedSwitch
            mgsOpt.MsgBoxOnly = true;
            utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                sprintf('ZARR images are predicted without preprocessing\n\nSet "Preprocess for" to "Training" or "Preprocessing is not required"'), ...
                {}, {}, 'Not available', mgsOpt);
            return;
        end
        [zarrList, zarrStores, cancelled] = checkZarrStores(obj);
        if cancelled; return; end
    end

    % get settings for export of score files
    % {'Do not generate', 'Use AM format', 'Use Matlab non-compressed format', 'Use Matlab compressed format', 'Use Matlab non-compressed format (range 0-1)', 'Zarr3 (BigData)'};
    if strcmp(obj.BatchOpt.P_ScoreFiles{1}, 'Do not generate')
        generateScoreFiles = 0;
    else
        generateScoreFiles = find(ismember(obj.BatchOpt.P_ScoreFiles{2}, obj.BatchOpt.P_ScoreFiles{1}))-1;
        % 1-> 'Use AM format'
        % 2-> 'Use Matlab non-compressed format'
        % 3-> 'Use Matlab compressed format'
        % 4-> 'Use Matlab non-compressed format (range 0-1)'
        % 5-> 'Zarr3 (BigData)'

        saveImageOpt.dimOrder = 'yxczt';    % for 2D or saveImageOpt.dimOrder = 'yxzct'; for 3D
    end

    maxIterations = 1;
    currentIteration = 0;
    incrementStep = 1;
    if obj.BatchOpt.showWaitbar
        pwb = uiprogressdlg(obj.view.gui, ...
            'Title', 'Predicting dataset', ...
            'Message', 'Creating image store for prediction...', ...
            'Cancelable', true, ...
            'Value', 0);
    end

    % prepare options for loading of images
    mibDeepStoreLoadImagesOpt.mibBioformatsCheck = obj.BatchOpt.Bioformats;
    mibDeepStoreLoadImagesOpt.BioFormatsIndices = obj.BatchOpt.BioformatsIndex{1};
    mibDeepStoreLoadImagesOpt.Workflow = obj.BatchOpt.Workflow{1};

    % make a datastore for images
    try
        if zarrInput
            % zarr stores are folders, imageDatastore can not list them; the datastore
            % gives the index of the store, which predictZarrStore reads slab by slab
            imgDS = arrayDatastore((1:numel(zarrList))', 'OutputType', 'same');
        elseif preprocessedSwitch   % with preprocessing
            imgDS = imageDatastore(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages'), ...
                'FileExtensions', '.mibImg', 'ReadFcn', @deepmib.storeLoadImages);
        else    % without preprocessing
            fnExtention = lower(['.' obj.BatchOpt.ImageFilenameExtension{1}]);
            if strcmp(obj.BatchOpt.Workflow{1}, '2D Patch-wise' )
                filelist = dir(obj.BatchOpt.OriginalPredictionImagesDir);
                if sum([filelist.isdir]) == 2  % no directories present, predict images under obj.BatchOpt.OriginalPredictionImagesDir
                    imgDS = imageDatastore(obj.BatchOpt.OriginalPredictionImagesDir, ...
                        'FileExtensions', fnExtention, ...
                        'IncludeSubfolders', false, ...
                        'ReadFcn', @(fn)deepmib.storeLoadImages(fn, mibDeepStoreLoadImagesOpt));
                else
                    if isfolder(fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images'))
                        imgDS = imageDatastore(fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Images'), ...
                            'FileExtensions', fnExtention, ...
                            'IncludeSubfolders', false, ...
                            'ReadFcn', @(fn)deepmib.storeLoadImages(fn, mibDeepStoreLoadImagesOpt));
                    else
                        % patch-wise segmentation of individual patches
                        % stored under subfolders
                        imgDS = imageDatastore(fullfile(obj.BatchOpt.OriginalPredictionImagesDir), ...
                            'FileExtensions', fnExtention, ...
                            'IncludeSubfolders', true, ...
                            "LabelSource", "foldernames", ...
                            'ReadFcn', @(fn)deepmib.storeLoadImages(fn, mibDeepStoreLoadImagesOpt));
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
                    if strcmp(res, 'Cancel');  if obj.BatchOpt.showWaitbar; close(pwb); end; return; end
                    imagesSubfolder = [];
                end

                % semantic segmentation or patch-wise segmentation of large images
                imgDS = imageDatastore(fullfile(obj.BatchOpt.OriginalPredictionImagesDir, imagesSubfolder), ...
                    'FileExtensions', fnExtention, ...
                    'IncludeSubfolders', false, ...
                    'ReadFcn', @(fn)deepmib.storeLoadImages(fn, mibDeepStoreLoadImagesOpt));
            end
        end
    catch err
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Missing files');
        if obj.BatchOpt.showWaitbar; close(pwb); end
        return;
    end
    if zarrInput
        predictionFiles = zarrList;
    else
        predictionFiles = imgDS.Files;
    end

    % destinations of the zarr stores (model and score files of any type of input images),
    % confirmed before anything is deleted
    writtenStores = {};
    if zarrOutput
        [storePaths, zarrFormat, cancelled, resumeModelStores] = selectModelStoreDestination(obj, predictionFiles, 'model', zarrInput);
        if cancelled; if obj.BatchOpt.showWaitbar; close(pwb); end; return; end
    end
    if zarrScores
        [scoreStorePaths, scoreZarrFormat, cancelled, resumeScoreStores] = selectModelStoreDestination(obj, predictionFiles, 'score', zarrInput);
        if cancelled; if obj.BatchOpt.showWaitbar; close(pwb); end; return; end
    end

    % creating output directories
    warning('off', 'MATLAB:MKDIR:DirectoryExists');
    % check whether the output folder exists and whether there are
    % some files in there; stores to be resumed (and the level maps of the model
    % stores) are kept
    keptPaths = {};
    if zarrOutput
        keptPaths = [keptPaths, storePaths(resumeModelStores), ...
            cellfun(@core.MibBigDataLabels.levelMapPathFor, storePaths(resumeModelStores), 'UniformOutput', false)];
    end
    if zarrScores; keptPaths = [keptPaths, scoreStorePaths(resumeScoreStores)]; end
    [outputModelFiles, outputModelStores] = listOutputs(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels'), keptPaths);
    [outputScoreFiles, outputScoreStores] = listOutputs(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores'), keptPaths);
    noOutputModelFiles = numel(outputModelFiles) + numel(outputModelStores);
    noOutputScoreFiles = numel(outputScoreFiles) + numel(outputScoreStores);
    if noOutputModelFiles > 0 || noOutputScoreFiles > 0
        selection = uiconfirm(obj.view.gui, ...
            sprintf(['The destination directories:\n- PredictionImages/ResultsModels\n- PredictionImages/ResultsScores\n\n' ...
            'in\n%s\n\n' ...
            'are not empty!\n\nShell the destination folders be emptied and prediction started?'], obj.BatchOpt.ResultingImagesDir), ...
            'Destination folders are not empty',...
            'Icon','warning');
        if strcmp(selection, 'Cancel'); if obj.BatchOpt.showWaitbar; close(pwb); end; return; end
        cellfun(@delete, [outputModelFiles, outputScoreFiles]);
        cellfun(@(storePath) rmdir(storePath, 's'), [outputModelStores, outputScoreStores]);
    end

    % isfolder(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels'))
    mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores'));
    mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels'));

    if obj.BatchOpt.showWaitbar
        if pwb.CancelRequested; close(pwb); return; end
        extraWaitbarInfo = '';
        if patchwisePatchesPredictSwitch; extraWaitbarInfo = ' for the patch-wise mode'; end
        pwb.Message = sprintf('Loading network%s\nPlease wait...', extraWaitbarInfo);
    end
    % loading: 'net', 'TrainingOptStruct', 'classNames',
    % 'inputPatchSize', 'outputPatchSize', 'BatchOpt' variables
    load(obj.BatchOpt.NetworkFilename, '-mat');

    % make sure that the network matches the selected workflow,
    % otherwise blockedImage/apply fails with a cryptic BlockSize error
    workflowErrorText = '';
    if exist('BatchOpt', 'var') && isfield(BatchOpt, 'Workflow') && ~strcmp(BatchOpt.Workflow{1}, obj.BatchOpt.Workflow{1})
        workflowErrorText = sprintf(['The network was trained for the "%s" workflow,' ...
            'but the "%s" workflow is currently selected.\n\n' ...
            'Please select the "%s" workflow and start prediction again'], ...
            BatchOpt.Workflow{1}, obj.BatchOpt.Workflow{1}, BatchOpt.Workflow{1});
    elseif strcmp(obj.BatchOpt.Workflow{1}, '2.5D Semantic') && inputPatchSize(3) < 2
        workflowErrorText = sprintf(['The "2.5D Semantic" workflow is selected, but the network input patch' ...
            'has only one slice in depth (%s), i.e. it is a 2D network.\n\n' ...
            'Please select the "2D Semantic" workflow, or retrain the network' ...
            'with an odd depth of 3 or more (for example, "%d %d 3 %d")'], ...
            strtrim(num2str(inputPatchSize, '%d ')), inputPatchSize(1), inputPatchSize(2), inputPatchSize(4));
    end
    if ~isempty(workflowErrorText)
        if obj.BatchOpt.showWaitbar; close(pwb); end
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.headerLines = 1;
        mgsOpt.WindowHeight = 240;
        mgsOpt.WindowWidth = 500;
        utils.dlgs.inputUniversalDlg(obj.view.gui, 'Network does not match the selected workflow', {}, {workflowErrorText}, 'Wrong workflow', mgsOpt);
        return;
    end

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

    noFiles = numel(predictionFiles);
    if obj.BatchOpt.showWaitbar
        if pwb.CancelRequested; close(pwb); return; end
        pwb.Message = sprintf('Starting prediction%s\nPlease wait...', extraWaitbarInfo);
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
        maxIterations = noFiles * progressUpdatesPerFile;
    end

    t1 = tic;
    if obj.BatchOpt.showWaitbar; progressDialog = pwb; else; progressDialog = []; end

    while hasdata(imgDS)
        % check for Cancel
        if obj.BatchOpt.showWaitbar && pwb.CancelRequested; close(pwb); return; end

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

        [~, fn] = fileparts(predictionFiles{id});
        if zarrInput; fn = regexprep(fn, '\.ome$', '', 'ignorecase'); end   % 'name.ome.zarr' -> 'name'

        if zarrScores
            % settings of the score store: an image store of the predicted level, one channel per class
            scoreOpt = obj.ScoreExportOpt;
            scoreMetadata.pixSize = struct('x', 1, 'y', 1, 'z', 1);   % the voxel size of images that are not zarr is not known here
            if zarrInput
                % the predicted level becomes level 1; the coarser levels of the image follow
                predictedLevel = obj.BatchOpt.BioformatsIndex{1};
                imagePyramid = zarrStores(id).pyramid;
                levelRange = predictedLevel:size(imagePyramid.levelImageSizes, 1);
                scoreSaveOpt = io.savers.Zarr3Saver.optionsFromPyramid(struct('axisOrder', imagePyramid.axisOrder, ...
                    'levelImageSizes', imagePyramid.levelImageSizes(levelRange, :), ...
                    'levelScaleFactors', imagePyramid.levelScaleFactors(levelRange, :), ...
                    'chunkSizes', {imagePyramid.chunkSizes(levelRange)}));
                % voxel size of the predicted level, so the scores line up with the image
                levelScale = imagePyramid.levelScaleFactors(predictedLevel, :);   % [y x z]
                scoreMetadata.pixSize = zarrStores(id).pixSize;
                scoreMetadata.pixSize.y = scoreMetadata.pixSize.y*levelScale(1);
                scoreMetadata.pixSize.x = scoreMetadata.pixSize.x*levelScale(2);
                scoreMetadata.pixSize.z = scoreMetadata.pixSize.z*levelScale(3);
            else
                % no pyramid to follow: XY halvings until the smaller side is below 256 pixels
                scoreSaveOpt = struct('silent', true, 'ChunkSize', [256 256 16], 'DownsampleStrategy', 'XY only');
            end
            scoreSaveOpt.ZarrFormat = scoreZarrFormat;
            scoreSaveOpt.DownsampleMethod = scoreOpt.DownsampleMethod;
            if scoreOpt.Levels > 0; scoreSaveOpt.Levels = scoreOpt.Levels; end
            if all(scoreOpt.ChunkSize > 0); scoreSaveOpt.ChunkSize = scoreOpt.ChunkSize; end
            if scoreZarrFormat == 2
                scoreSaveOpt.ShardSize = [];    % no sharding in zarr v2
            elseif all(scoreOpt.ShardSize > 0)
                scoreSaveOpt.ShardSize = scoreOpt.ShardSize;
            end
            scoreSaveOpt.Compressors = scoreOpt.Compressors;
            if ~strcmp(scoreSaveOpt.Compressors, 'none')
                scoreCompressionLevel = scoreOpt.CompressionLevel;
                if strcmp(scoreSaveOpt.Compressors, 'gzip'); scoreCompressionLevel = min(scoreCompressionLevel, 9); end
                scoreSaveOpt.Compressors = struct('name', scoreSaveOpt.Compressors, 'configuration', struct('level', scoreCompressionLevel));
            end
            scoreClassNames = cellstr(classNames(:))';
            if ~obj.ScoreExportOpt.IncludeExterior; scoreClassNames(1) = []; end
        end

        if zarrInput
            % zarr stores are larger than memory as a rule: the store is read, predicted
            % and written slab by slab; only the formats written whole below are gathered
            read(imgDS);    % the index of the store
            predictOpt = struct('net', net, 'inputPatchSize', inputPatchSize, 'outputPatchSize', outputPatchSize, ...
                'blockSize', blockSize, 'padShift', padShift, 'dataDimension', dataDimension, ...
                'patchwiseWorkflowSwitch', patchwiseWorkflowSwitch, 'classNames', {classNames}, ...
                'generateScoreFiles', generateScoreFiles, 'executionEnvironment', executionEnvironment, ...
                'fn', fn, 'pwb', progressDialog, 'fileIndex', id, 'noFiles', noFiles, 'startTime', t1, ...
                'modelStorePath', '', 'tifFilename', '', 'scoreStorePath', '', ...
                'keepLabels', strcmp(obj.BatchOpt.P_ModelFiles{1}, 'MIB Model format') || patchwiseWorkflowSwitch, ...
                'keepScores', generateScoreFiles > 0 && ~zarrScores);
            if zarrOutput
                predictOpt.modelStorePath = storePaths{id};
                predictOpt.resumeModel = resumeModelStores(id);
                predictOpt.zarrFormat = zarrFormat;
                predictOpt.modelMaterialNames = classNames(2:end);     % remove Exterior
                predictOpt.modelMaterialColors = [modelMaterialColors; obj.modelMaterialColors];
            end
            if ismember(obj.BatchOpt.P_ModelFiles{1}, {'TIF compressed format', 'TIF uncompressed format'})
                predictOpt.tifFilename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', ['Labels_' fn '.tif']);
                predictOpt.tifCompression = 'none';
                if strcmp(obj.BatchOpt.P_ModelFiles{1}, 'TIF compressed format'); predictOpt.tifCompression = 'lzw'; end
            end
            if zarrScores
                predictOpt.scoreStorePath = scoreStorePaths{id};
                predictOpt.resumeScores = resumeScoreStores(id);
                predictOpt.scoreSaveOpt = scoreSaveOpt;
                predictOpt.scoreMetadata = scoreMetadata;
                predictOpt.scoreClassNames = scoreClassNames;
            end
            try
                [outputLabels, scoreImg, cancelled] = obj.predictZarrStore(zarrStores(id), predictOpt);
            catch err
                if obj.BatchOpt.showWaitbar; close(pwb); end
                if ~isempty(writtenStores)
                    fprintf('DeepMIB: stores written before the error:\n%s\n', strjoin(writtenStores, newline));
                end
                rethrow(err);
            end
            if cancelled
                if obj.BatchOpt.showWaitbar; close(pwb); end
                if ~isempty(writtenStores)
                    fprintf('DeepMIB: prediction cancelled; stores written before:\n%s\n', strjoin(writtenStores, newline));
                end
                return;
            end
            if zarrOutput
                writtenStores{end+1} = storePaths{id}; %#ok<AGROW>
                fprintf('DeepMIB: model store written: %s\n', storePaths{id});
            end
            if zarrScores
                writtenStores{end+1} = scoreStorePaths{id}; %#ok<AGROW>
                fprintf('DeepMIB: score store written: %s\n', scoreStorePaths{id});
            end
        else
            vol = read(imgDS);

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
                vol = utils.resizeImage3d(vol, [], imResizeOpt);
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

                    [outputLabelsCurrent, scoreImgCurrent, cancelled] = obj.processBlocksBlockedImage(subVol, zValue, net, ...
                        inputPatchSize, outputPatchSize, blockSize, padShift, ...
                        dataDimension, patchwiseWorkflowSwitch, patchwisePatchesPredictSwitch, ...
                        classNames, generateScoreFiles, executionEnvironment, fn, progressDialog);
                    if cancelled; if obj.BatchOpt.showWaitbar; close(pwb); end; return; end

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
                    if obj.BatchOpt.showWaitbar && pwb.CancelRequested; close(pwb); return; end

                    % update progress bar
                    if obj.BatchOpt.showWaitbar && zValue >= nextWaitbarIterationFromZ
                        elapsedTime = toc(t1);
                        currIteration = currentIteration + 1;
                        timerValue = elapsedTime/currIteration*(maxIterations - currIteration);
                        pwb.Message = sprintf('%s\nHold on ~%.0f:%.2d mins left...', fn, floor(timerValue/60), mod(round(timerValue),60));
                        currentIteration = currentIteration + incrementStep;
                        pwb.Value = min(1, currentIteration / maxIterations);
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
                        incrementStep = 1;
                    else
                        use3DdatasetWith2Dnet = false;
                        incrementStep = progressUpdatesPerFile;
                    end
                elseif dataDimension == 3
                    use3DdatasetWith2Dnet = false;
                    incrementStep = progressUpdatesPerFile;
                else
                    use3DdatasetWith2Dnet = false;
                    incrementStep = 1;
                end

                if use3DdatasetWith2Dnet
                    for zValue = 1:volDepth
                        [outputLabelsCurrent, scoreImgCurrent, cancelled] = obj.processBlocksBlockedImage(squeeze(vol(:,:,zValue,:)), zValue, net, ...
                            inputPatchSize, outputPatchSize, blockSize, padShift, ...
                            dataDimension, patchwiseWorkflowSwitch, patchwisePatchesPredictSwitch, ...
                            classNames, generateScoreFiles, executionEnvironment, fn, progressDialog);
                        if cancelled; if obj.BatchOpt.showWaitbar; close(pwb); end; return; end
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
                        if obj.BatchOpt.showWaitbar && pwb.CancelRequested; close(pwb); return; end
                        % update progress bar
                        if obj.BatchOpt.showWaitbar && zValue >= nextWaitbarIterationFromZ
                            elapsedTime = toc(t1);
                            currIteration = currentIteration + 1;
                            timerValue = elapsedTime/currIteration*(maxIterations - currIteration);
                            pwb.Message = sprintf('%s\nHold on ~%.0f:%.2d mins left...', fn, floor(timerValue/60), mod(round(timerValue),60));
                            currentIteration = currentIteration + incrementStep;
                            pwb.Value = min(1, currentIteration / maxIterations);
                            nextWaitbarIterationFromZ = nextWaitbarIterationFromZ + volDepth/progressUpdatesPerFile;
                        end
                    end
                else
                    zValue = NaN;
                    [outputLabels, scoreImg, cancelled] = obj.processBlocksBlockedImage(vol, zValue, net, ...
                        inputPatchSize, outputPatchSize, blockSize, padShift, ...
                        dataDimension, patchwiseWorkflowSwitch, patchwisePatchesPredictSwitch, ...
                        classNames, generateScoreFiles, executionEnvironment, fn, progressDialog);
                    if cancelled; if obj.BatchOpt.showWaitbar; close(pwb); end; return; end
                    
                    % remove exterior
                    if generateScoreFiles > 0 && ~obj.ScoreExportOpt.IncludeExterior
                        scoreImg = scoreImg(:,:,2:end,:);
                    end

                    % check for Cancel
                    if obj.BatchOpt.showWaitbar && pwb.CancelRequested; close(pwb); return; end
                    % update progress bar
                    if obj.BatchOpt.showWaitbar
                        elapsedTime = toc(t1);
                        currIteration = currentIteration + 1;
                        timerValue = elapsedTime/currIteration*(maxIterations - currIteration);
                        pwb.Message = sprintf('%s\nHold on ~%.0f:%.2d mins left...', fn, floor(timerValue/60), mod(round(timerValue),60));
                        currentIteration = currentIteration + incrementStep;
                        pwb.Value = min(1, currentIteration / maxIterations);
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
                outputLabels = utils.resizeImage3d(outputLabels, [], imResizeOpt);

                % % smooth models for 2 classes outputs
                if numClasses == 2
                    % utils.doImageFiltering takes the ImageFilters BatchOpt format
                    smoothOptions.SourceLayer = {'labels'};
                    smoothOptions.FilterName = {'Gaussian'};
                    smoothOptions.Mode3D = dataDimension == 3;
                    smoothOptions.Sigma = {obj.BatchOpt.P_ImageDownsamplingFactor{1}+1};
                    smoothOptions.HSize = num2str(obj.BatchOpt.P_ImageDownsamplingFactor{1}*2+1);
                    smoothOptions.Padding = {'replicate'};
                    smoothOptions.PaddingValue = {0};
                    smoothOptions.FilterDomain = {'auto'};
                    smoothOptions.showWaitbar = false;
                    outputLabels = utils.doImageFiltering(outputLabels, smoothOptions);
                end

                if generateScoreFiles > 0
                    imResizeOpt.imgType = '4D';
                    scoreImg = utils.resizeImage3d(scoreImg, [], imResizeOpt);
                end
            end
        end

        % Save results; for zarr images the TIF files and the zarr stores are
        % already written by predictZarrStore
        if ~patchwisePatchesPredictSwitch % standard semantic segmentation mode or patch-wise mode when prediction images are not in patches
            % depending on the selected output type
            modelFormat = obj.BatchOpt.P_ModelFiles{1};
            if zarrInput && ismember(modelFormat, {'TIF compressed format', 'TIF uncompressed format', 'Zarr3 (BigData model)'})
                modelFormat = 'written by predictZarrStore';
            end
            switch modelFormat
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
                    imwrite(outputLabels(:,:,1), filename, 'tif', 'WriteMode', 'overwrite', 'Description', sprintf('DeepMIB segmentation: %s %s', obj.BatchOpt.Workflow{1}, obj.BatchOpt.Architecture{1}), 'Compression', tifCompression);
                    if dataDimension ~= 2 || use3DdatasetWith2Dnet % 2.5D and 3D case dataDimension == 2.5 or dataDimension == 3
                        for sliceId = 2:size(outputLabels, 3)
                            imwrite(outputLabels(:,:,sliceId), filename, 'tif', 'WriteMode', 'append', 'Compression', tifCompression);
                        end
                    end
                case 'Zarr3 (BigData model)'
                    % a BigData model store of an image that is not zarr, see writeModelStore
                    if obj.BatchOpt.showWaitbar && pwb.CancelRequested; close(pwb); return; end
                    modelMaterialNames = classNames(2:end);     % remove Exterior
                    modelMaterialColors = [modelMaterialColors; obj.modelMaterialColors];
                    imagePyramid = [];  % images that are not zarr have no pyramid, writeModelStore generates one
                    try
                        obj.writeModelStore(outputLabels, storePaths{id}, imagePyramid, zarrFormat, ...
                            modelMaterialNames, modelMaterialColors);
                    catch err
                        if obj.BatchOpt.showWaitbar; close(pwb); end
                        if ~isempty(writtenStores)
                            fprintf('DeepMIB: model stores written before the error:\n%s\n', strjoin(writtenStores, newline));
                        end
                        rethrow(err);
                    end
                    writtenStores{end+1} = storePaths{id}; %#ok<AGROW>
                    fprintf('DeepMIB: model store written: %s\n', storePaths{id});
            end
            %
            %                     % save score map
            if generateScoreFiles > 0
                if zarrScores && zarrInput
                    % 'Zarr3 (BigData)' of a zarr image: written slab by slab by predictZarrStore
                elseif zarrScores    % 'Zarr3 (BigData)', the options are set before the prediction
                    % an image store of the predicted level, one channel per class
                    if obj.BatchOpt.showWaitbar && pwb.CancelRequested; close(pwb); return; end
                    try
                        % [y x c z] -> [y x z c]
                        io.savers.Zarr3Saver().save(permute(scoreImg, [1 2 4 3]), scoreMetadata, scoreStorePaths{id}, scoreSaveOpt);
                        scoreGroup = io.zarr.Group(scoreStorePaths{id});
                        scoreAttributes = scoreGroup.getAttributes();
                        scoreAttributes.mibPredictionScores = struct('classNames', {scoreClassNames});   % keeps the store out of the next prediction
                        scoreGroup.setAttributes(scoreAttributes);
                    catch err
                        if isfolder(scoreStorePaths{id}); rmdir(scoreStorePaths{id}, 's'); end
                        if obj.BatchOpt.showWaitbar; close(pwb); end
                        if ~isempty(writtenStores)
                            fprintf('DeepMIB: stores written before the error:\n%s\n', strjoin(writtenStores, newline));
                        end
                        rethrow(err);
                    end
                    writtenStores{end+1} = scoreStorePaths{id}; %#ok<AGROW>
                    fprintf('DeepMIB: score store written: %s\n', scoreStorePaths{id});
                elseif generateScoreFiles == 1    % 'Use AM format'
                    filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', ['Score_' fn '.am']);
                    amiraOpt.overwrite = 1;
                    amiraOpt.showWaitbar = 0;
                    amiraOpt.verbose = false;
                    % scoreImg is [H W C] (pure 2D) or [H W C D] (2.5D / 3D / use3DdatasetWith2Dnet);
                    % bitmap2amiraMesh expects [H W D C T] - trailing singleton handles the 2D case
                    io.AmiraMesh.bitmap2amiraMesh(filename, permute(scoreImg, [1 2 4 3]), [], amiraOpt);
                elseif generateScoreFiles == 4   %  4=='Use Matlab non-compressed format (range 0-1)'
                    filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', ['Score_' fn '.mat']);
                    deepmib.saveImageParFor(filename, scoreImg, false, saveImageOpt);
                else  % 2=='Use Matlab non-compressed format', 3=='Use Matlab compressed format'
                    filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsScores', ['Score_' fn '.mibImg']);
                    deepmib.saveImageParFor(filename, scoreImg, generateScoreFiles, saveImageOpt);
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
    eventdata = core.ToggleEventData(4);    % scale scoring by factor 5
    notify(obj.mibModel, 'UpdateUserScore', eventdata);
    if obj.BatchOpt.showWaitbar; close(pwb); end

    if zarrInput && (zarrOutput || zarrScores) && obj.BatchOpt.showWaitbar
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.Icon = 'puffin_info';
        mgsOpt.WindowWidth = 560;
        mgsOpt.WindowHeight = 260;
        finishedText = sprintf('%d store(s) were written.', numel(writtenStores));
        if zarrOutput
            finishedText = sprintf('%s\nOpen the image in the BigData mode and load its model store: Model -> Load model', finishedText);
        end
        if zarrScores
            finishedText = sprintf('%s\nScore stores (Score_<image name>) are images with a channel per class: open them in the BigData mode', finishedText);
        end
        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
            finishedText, ...
            {}, {strjoin(writtenStores, newline)}, 'Prediction finished', mgsOpt);
    end
end

function [files, stores] = listOutputs(folder, keptPaths)
% files and zarr stores (folders) in an output folder, except keptPaths
files = {};
stores = {};
if ~isfolder(folder); return; end
outputList = dir(folder);
outputList(ismember({outputList.name}, {'.', '..'})) = [];
paths = fullfile({outputList.folder}, {outputList.name});
isKept = ismember(paths, keptPaths);
isStore = [outputList.isdir] & ~cellfun(@isempty, regexpi({outputList.name}, '\.zarr[23]?$', 'once'));
files = paths(~[outputList.isdir] & ~isKept);
stores = paths(isStore & ~isKept);
end
