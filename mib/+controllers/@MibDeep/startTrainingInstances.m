function startTrainingInstances(obj)
% STARTTRAININGINSTANCES - perform training of instance segmentation network.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.startTrainingInstances()
%

global counter;     % for patch test
global mibDeepStopTraining
global mibDeepTrainingProgressStruct

counter = 1;

% mibDeepTrainingProgressStruct is a global that is only cleared on a successful finish
% (see end of this file). A previous or crashed run can therefore leave it populated with
% dead figure/hPlot handles and a 'sendNextReportAtEpoch' field. Because trainSOLOV2 fires
% its first OutputFcn call at iteration 1 (not 0), deepmib.customTrainingProgressDisplay
% relies on that field being absent to decide it must (re)initialise the window - so a
% stale field makes it skip init and update deleted graphics. Reset that state here so the
% progress window is rebuilt fresh for every instance-training run.
if isfield(mibDeepTrainingProgressStruct, 'UIFigure') && ~isempty(mibDeepTrainingProgressStruct.UIFigure) && isvalid(mibDeepTrainingProgressStruct.UIFigure)
    delete(mibDeepTrainingProgressStruct.UIFigure);
end
if isfield(mibDeepTrainingProgressStruct, 'sendNextReportAtEpoch')
    mibDeepTrainingProgressStruct = rmfield(mibDeepTrainingProgressStruct, 'sendNextReportAtEpoch');
end

mibDeepTrainingProgressStruct.emergencyBrake = false;   % emergency brake without finishing the weights

% instance segmentation trains via trainSOLOV2 -> images.dltrain.internal.dltrain, whose
% trainer keeps iterating its outer "for epoch = 1:MaxEpochs" loop after a stop request.
% deepmib.customTrainingProgressDisplay and deepmib.stopTrainingWithoutPlots use this flag
% to apply the two mitigations described in deepmib.suspendCheckpointSaving
mibDeepTrainingProgressStruct.dltrainBasedTrainer = true;
mibDeepTrainingProgressStruct.CheckpointPathSuspended = false;
mibDeepTrainingProgressStruct.spinDownActive = false;   % true once a stop has been requested
if obj.BatchOpt.T_SaveProgress
    mibDeepTrainingProgressStruct.CheckpointPath = fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork');
else
    mibDeepTrainingProgressStruct.CheckpointPath = '';
end
% a previous run killed with Ctrl+C may have left the checkpoint folder renamed
deepmib.suspendCheckpointSaving('restoreOrphaned');

msg = sprintf(['You are going to start training of an instance segmentation network!\n\nConfirm that your images located under\n\n%s\n\n%s\n%s\n%s\n%s\n\n' ...
    'Please also make sure that number of files with labels match number of files with images!\n\n' ...
    'Note on stopping this workflow early:\n' ...
    '- "Stop training" finalizes the run properly, but MATLAB still has to walk through the epochs that were left, which costs roughly a minute per 1000 remaining epochs\n' ...
    '- "Emergency brake" stops immediately and rebuilds the network from the most recent checkpoint, so keep "Save checkpoint networks" enabled if you plan to use it'], ...
    obj.BatchOpt.OriginalTrainingImagesDir, ...
    '- TrainImages', '- TrainLabels', ...
    '- ValidationImages', '- ValidationLabels');

selection = uiconfirm(obj.view.gui, ...
    msg, 'Preprocessing',...
    'Options',{'Confirm', 'Cancel'},...
    'DefaultOption',1,'CancelOption',2,...
    'Icon', 'warning');
if strcmp(selection, 'Cancel'); return; end


% Reset GPU
obj.selectGPUDevice();

%% Create Random Patch Extraction Datastore for Training
% create image data store
% obj.TrainingProgress = struct();
% obj.TrainingProgress.stopTraining = false;
% obj.TrainingProgress.emergencyBrake = false;

% check input patch size
inputPatchSize = str2num(obj.BatchOpt.T_InputPatchSize); %#ok<ST2NM>
if numel(inputPatchSize) ~= 4
    mgsOpt.MsgBoxOnly = true;
    header = sprintf(['Please provide the "Input patch size" (BatchOpt.T_InputPatchSize) as 4 numbers that define\n' ...
        'height, width, depth, colors\n\nFor example:\n' ...
        '"800, 800, 1, 3" for SOLOv2 of 3 color channel images\n' ...
        '"1280, 800, 1, 1" for SOLOv2 of 1 color channel images\n\n' ...
        'Please note that the width and height should be multiples of 32 and color are 1 or 3']);
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong patch size', mgsOpt);
    return;
end

%   check for rectangular shape of the input patch
if inputPatchSize(1)~=inputPatchSize(2) && obj.BatchOpt.T_augmentation
    if (strcmp(obj.BatchOpt.Workflow{1}(1:2), '2D') && obj.AugOpt2D.Rotation90.Enable )
        mgsOpt.MsgBoxOnly = true;
        header = sprintf(['Rotation augmentations are only implemented for input patches that have a square shape!\n\n' ...
            'How to fix (one of these options):\n   a) set probability of Rotation90 augmentations to 0\n' ...
                '   b) make sure that the input patch size has a square shape as "%d %d %d %d"\n' ...
                '   c)   if Rotation90 is required rotate the original dataset (images and labels) and save it as ' ...
                'additional files to be used for training'], ...
                inputPatchSize(1), inputPatchSize(1), inputPatchSize(3), inputPatchSize(4));
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Rotation90 is not available', mgsOpt);
        return;
    end
end

% fix the 3rd value in the input patch size for 2D networks
if strcmp(obj.BatchOpt.Workflow{1}(1:2), '2D') && inputPatchSize(3) > 1
    inputPatchSize(3) = 1;
    obj.BatchOpt.T_InputPatchSize = num2str(inputPatchSize);
    obj.view.handles.T_InputPatchSize.Value = obj.BatchOpt.T_InputPatchSize;
end

% check whether it is needed to continue the previous training
% or start a new one
checkPointRestoreFile = '';     % selected FULL filename for the network restore
checkPointFiles = {'Start new training'};  % place maker for the checkpoint networks

if exist(obj.BatchOpt.NetworkFilename, 'file') == 2
    [~, currentNetFile, netExt] = fileparts(obj.BatchOpt.NetworkFilename);
    currentNetFile = {[currentNetFile netExt]};     % already existing network
    checkPointFiles = [checkPointFiles, currentNetFile];
end

if obj.BatchOpt.T_SaveProgress  % checkpoint networks
    warning('off', 'MATLAB:MKDIR:DirectoryExists');
    mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork'));
end

if isfolder(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork'))
    progressFiles = dir(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', '*.mat'));
    if ~isempty(progressFiles)
        [~, idx]=sort([progressFiles.datenum], 'descend');      % sort in time order
        checkPointFiles = [checkPointFiles {progressFiles(idx).name}];
    end
end

if numel(checkPointFiles) > 1
    prompts = {'Select the check point:'};
    defAns = {checkPointFiles, 1};
    dlgTitle = 'Select checkpoint';
    options.Header = sprintf(['Files with training checkpoints were detected.\n' ...
        'Please select the checkpoint to continue, if you choose "Start new training" the checkpoint directory ' ...
        'will be cleared from the older checkpoints and the new training session initiated:']);
    options.HeaderLines = 5;
    options.WindowWidth = 630;
    [answer, selPosition] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    switch selPosition
        case 1  % start new training
            % Only the checkpoint networks are cleared. They are named by
            % images.dltrain as "net_checkpoint__<iteration>__<timestamp>.mat" with no
            % reference to the run, so they accumulate across runs and clutter the
            % restore dialog above (at ~70 MB each).
            % The score, CSV, PNG and FIG files are NOT deleted: every one of them is
            % written with a "<yyMMddHHmm>_<network name>" prefix, so runs cannot
            % overwrite each other and the history of a project stays intact.
            if obj.BatchOpt.T_SaveProgress
                delete(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', 'net_checkpoint__*.mat'));
            end
        case 2  % continue from the loaded net
            if exist(obj.BatchOpt.NetworkFilename, 'file') == 2     % when the mibDeep file is present
                checkPointRestoreFile = obj.BatchOpt.NetworkFilename;
            else    % if mibDeep file is not present
                checkPointRestoreFile = fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', answer{1});
            end
        otherwise  % continue from the checkpoint
            checkPointRestoreFile = fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', answer{1});
    end
end
% nothing is deleted here: the exported files carry a per-run prefix, see above

trainTimer = tic;

try
    showWaitbarLocal = obj.BatchOpt.showWaitbar;
    showWaitbarLocal = false;
    if showWaitbarLocal
        obj.wb = uiprogressdlg(obj.view.gui, 'Message', 'Creating datastores...', ...
            'Title', 'Preparing training', 'Cancelable', 'on');
    end

    % Build patch-based training datastores. In the 2D Instance workflow the network is
    % trained on native-resolution patches cropped on-the-fly from the label maps
    % (memory-friendly for large / whole-slide images). Each image contributes
    % "Patches per image" random patches per epoch (object-seeded + uniform mix).
    trainLabelsDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'TrainLabels');
    trainImagesDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'TrainImages');

    % options for loading of images
    mibDeepStoreLoadImagesOpt.mibBioformatsCheck = obj.BatchOpt.BioformatsTraining;
    mibDeepStoreLoadImagesOpt.BioFormatsIndices = obj.BatchOpt.BioformatsTrainingIndex{1};
    mibDeepStoreLoadImagesOpt.Workflow = obj.BatchOpt.Workflow{1};

    modelFileList = dir(fullfile(trainLabelsDir, '*.mat'));
    if isempty(modelFileList)
        mgsOpt.MsgBoxOnly = true;
        header = sprintf(['Preprocessed label files (*.mat) are missing in\n\n%s\n\n' ...
            'Preprocess the labels and split the data for training/validation first!'], trainLabelsDir);
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Missing files', mgsOpt);
        if showWaitbarLocal; delete(obj.wb); end
        return;
    end
    numImages = numel(modelFileList);
    patchesPerImage = obj.BatchOpt.T_PatchesPerImage{1};
    totalObservations = numImages * patchesPerImage;

    % check that the number of observations is larger than the mini-batch size
    if totalObservations < obj.BatchOpt.T_MiniBatchSize{1}
        mgsOpt.MsgBoxOnly = true;
        header = sprintf(['The Mini-batch size (%d) should be smaller than\n' ...
            'Patches_per_image (%d) x Number_of_images (%d) = %d\n\n' ...
            'Solve by (one of the options):\n-Decrease mini-batch size\n' ...
            '-Increase patches per image\n-Increase number of training images'], ...
            obj.BatchOpt.T_MiniBatchSize{1}, patchesPerImage, numImages, totalObservations);
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong configuration', mgsOpt);
        if showWaitbarLocal; delete(obj.wb); end
        return;
    end

    % init random generator
    if obj.BatchOpt.T_RandomGeneratorSeed{1} == 0
        rng('shuffle');
    else
        rng(obj.BatchOpt.T_RandomGeneratorSeed{1}, 'twister');
    end

    % options for cropping patches from the label maps
    patchOpt.imageDir = trainImagesDir;
    patchOpt.patchSize = inputPatchSize(1:2);   % [height width]
    patchOpt.objectFraction = 0.9;      % ~90% object-seeded, ~10% uniform-random patches
    patchOpt.minObjectArea = 4;         % drop tiny remnants left after cropping
    patchOpt.getImageOptions = mibDeepStoreLoadImagesOpt;

    % replicate the file list so each image yields "Patches per image" patches per epoch
    trainModelFiles = arrayfun(@(f) fullfile(f.folder, f.name), modelFileList, 'UniformOutput', false);
    trainModelFiles = repmat(trainModelFiles(:), [patchesPerImage, 1]);
    labelsDS = fileDatastore(trainModelFiles, ...
        'ReadFcn', @(fn)deepmib.readInstancePatch(fn, patchOpt));

    noFiles = totalObservations;    % used below for the iteration-count estimate

    %% Create Datastore for Validation
    if showWaitbarLocal
        if obj.wb.CancelRequested; deepmib.stopTrainingCallback(obj.wb); return; end
        obj.wb.Value = 0.25;
        obj.wb.Message = 'Create a datastore for validation...';
    end

    valModelList = dir(fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationLabels', '*.mat'));
    noValidationObservations = 0;
    if ~isempty(valModelList)
        valPatchOpt = patchOpt;
        valPatchOpt.imageDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationImages');
        valModelFiles = arrayfun(@(f) fullfile(f.folder, f.name), valModelList, 'UniformOutput', false);
        % replicate like the training list above, so validation averages over
        % "Patches per image" windows per image rather than a single one; a handful of
        % patches makes the validation loss too noisy to compare between evaluations
        valModelFiles = repmat(valModelFiles(:), [patchesPerImage, 1]);
        noValidationObservations = numel(valModelFiles);

        % Unlike training, validation must crop the SAME windows at every evaluation,
        % otherwise the curve reports which crops were drawn as much as how good the
        % network is - and "best-validation-loss" then picks the luckiest draw. Give each
        % observation its own fixed seed, following the same convention as the training
        % seed: 0 means "do not fix anything", any other value is reproducible. It is a
        % separate setting because the two want opposite things - training benefits from
        % fresh patches every epoch, validation from patches that never move.
        baseSeed = obj.BatchOpt.T_RandomGeneratorValSeed{1};
        valObservationSeeds = zeros(noValidationObservations, 1);
        if baseSeed ~= 0
            % keep the result in [1, 2^32-2] so a wrap can never produce 0, which is the
            % value reserved below to mean "unseeded"
            valObservationSeeds = mod(baseSeed * 100003 + (1:noValidationObservations)', 2^32 - 2) + 1;
        end

        % an indexed datastore rather than a fileDatastore: the replicated file names are
        % identical strings, so the observation index is the only way to give each replica
        % a distinct patch
        valLabelsDS = transform(...
            arrayDatastore((1:noValidationObservations)', 'ReadSize', 1), ...
            @(observationIndex) iReadValidationPatch(observationIndex, valModelFiles, valObservationSeeds, valPatchOpt));
    else    % do not use validation
        valLabelsDS = [];
    end
    
    % randomPatchExtractionDatastore -> not compatible with fileDatastore
    % %% generate random patch datastores
    % switch obj.BatchOpt.Workflow{1}(1:2)
    %     case {'3D', '2.'}   % ; '2.5D Semantic' and '3D Semantic'
    %         randomStoreInputPatchSize = inputPatchSize(1:3);
    %     case '2D'
    %         randomStoreInputPatchSize = inputPatchSize(1:2);
    % end
    % 
    % % Augmenter needs to be applied to the patches later
    % % after initialization using transform function
    % patchDS = randomPatchExtractionDatastore(imgDS, labelsDS, randomStoreInputPatchSize, ...
    %     'PatchesPerImage', obj.BatchOpt.T_PatchesPerImage{1});
    % 
    % patchDS.MiniBatchSize = obj.BatchOpt.T_MiniBatchSize{1};
    % 
    % % create random patch extraction datastore for validation
    % if ~isempty(valImgDS)
    %     valPatchDS = randomPatchExtractionDatastore(valImgDS, valLabelsDS, randomStoreInputPatchSize, ...
    %         'PatchesPerImage', obj.BatchOpt.T_PatchesPerImage{1});
    % else
    %     valPatchDS = [];
    % end
    % if ~isempty(valPatchDS)
    %     valPatchDS.MiniBatchSize = obj.BatchOpt.T_MiniBatchSize{1};
    % end
    % %                     % test
    % %                     imgTest = read(AugTrainDS);
    % %                     imtool(imgTest.InputImage{1});
    % %                     imtool(uint8(imgTest.ResponsePixelLabelImage{1}), []);
    % %                     reset(AugTrainDS);


    %% create network
    if showWaitbarLocal
        if obj.wb.CancelRequested; deepmib.stopTrainingCallback(obj.wb); return; end
        obj.wb.Message = 'Creating the network...';
        obj.wb.Value = 0.4;
    end

    previewSwitch = 0; % 1 - the generated network is only for preview, i.e. weights of classes won't be calculated
    
    % get input patch size
    % note: instance images are always converted to RGB (see matReadInstanceLabels),
    % so the SOLOv2 network input always has 3 colour channels
    inputPatchSize = str2num(obj.BatchOpt.T_InputPatchSize); %#ok<ST2NM>
    inputPatchSize = [inputPatchSize([1 2]) 3];
    outputPatchSize = inputPatchSize;

    % single-class instance segmentation: all objects share the "object" class.
    % Use a cellstr so it matches solov2 ClassNames (cell) and the categorical
    % categories produced during preprocessing (see matReadInstanceLabels)
    classNames = {'object'};
    classColors = obj.modelMaterialColors(1, :);

    try
        if isempty(checkPointRestoreFile)
            switch obj.BatchOpt.Architecture{1}
                case 'SOLOv2'
                    switch obj.BatchOpt.T_EncoderNetwork{1}
                        case 'Resnet18'
                            detectorName = 'light-resnet18-coco';
                        case 'Resnet50'
                            detectorName = 'resnet50-coco';
                    end
            end
            lgraph = solov2(detectorName, ...
                classNames, ...
                "InputSize", inputPatchSize);
        else
            % resume training from an existing network / checkpoint file;
            % SOLOv2 saves the trained detector object in the 'net' variable
            res = load(checkPointRestoreFile, '-mat');
            if ~isfield(res, 'net')
                error('The selected checkpoint file does not contain a "net" variable');
            end
            lgraph = res.net;   % solov2 detector object
            if isfield(res, 'outputPatchSize'); outputPatchSize = res.outputPatchSize; end
            if isfield(res, 'inputPatchSize'); inputPatchSize = res.inputPatchSize; end
        end
    catch err
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Network initialization problem');
        if showWaitbarLocal; delete(obj.wb); end
        return;
    end

    %% Augment the training data using a datastore transform
    % Geometric augmentations are applied to image + instance masks together and the
    % bounding boxes are recomputed from the warped masks; intensity/colour jitter is
    % applied to the image only. Validation data is never augmented.
    if obj.BatchOpt.T_augmentation
        status = obj.setAugFuncHandles('2D');   % populate obj.Aug2DFuncNames / obj.Aug2DFuncProbability
        if status == 0
            if showWaitbarLocal; delete(obj.wb); end
            return;
        end
        mibDeepInstanceAugOpt.AugOpt2D = obj.AugOpt2D;
        mibDeepInstanceAugOpt.Aug2DFuncNames = obj.Aug2DFuncNames;
        mibDeepInstanceAugOpt.Aug2DFuncProbability = obj.Aug2DFuncProbability;
        labelsDS = transform(labelsDS, @(dataIn)deepmib.augmentInstanceData2D(dataIn, mibDeepInstanceAugOpt));
    end

    % %% Augment the training and validation data by using the transform function with custom preprocessing
    % if showWaitbarLocal
    %     if obj.wb.CancelRequested; deepmib.stopTrainingCallback(obj.wb); return; end
    %     obj.wb.Message = 'Defing augmentation...';
    %     obj.wb.Value = 0.75;
    % end
    % 
    % % operations specified by the helper function augmentAndCrop3dPatch.
    % % The augmentAndCrop3dPatch function performs these operations:
    % % Randomly rotate and reflect training data to make the training more robust.
    % % The function does not rotate or reflect validation data.
    % % Crop response patches to the output size of the network (outputPatchSize: height x width x depth x classes)
    % switch obj.BatchOpt.Workflow{1}(1:2)
    %     case {'3D', '2.'}   % '2.5D Semantic' and '3D Semantic'
    %         % define options for the augmenter function
    %         mibDeepAugmentOpt.Workflow = obj.BatchOpt.Workflow{1};
    %         mibDeepAugmentOpt.Aug3DFuncNames = obj.Aug3DFuncNames;
    %         mibDeepAugmentOpt.AugOpt3D = obj.AugOpt3D;
    %         mibDeepAugmentOpt.Aug3DFuncProbability = obj.Aug3DFuncProbability;
    %         mibDeepAugmentOpt.T_ConvolutionPadding = obj.BatchOpt.T_ConvolutionPadding{1};
    % 
    %         mibDeepAugmentOpt.O_PreviewImagePatches = obj.BatchOpt.O_PreviewImagePatches;
    %         mibDeepAugmentOpt.O_FractionOfPreviewPatches = obj.BatchOpt.O_FractionOfPreviewPatches{1};
    %         mibDeepAugmentOpt.T_NumberOfClasses = obj.BatchOpt.T_NumberOfClasses{1};
    % 
    %         augmentFunctionHandle = @deepmib.augmentAndCrop3dPatchMultiGPU; % make a handle to the function to use
    % 
    %         % % define augmenting function; the functions are essentially the same, but the multi-gpu
    %         % % version does not have access to MibDeep and obj.TrainingProgress
    %         % if ismember(obj.view.Figure.GPUDropDown.Value, {'Multi-GPU', 'Parallel'})
    %         %     augmentFunctionHandle = @deepmib.augmentAndCrop3dPatchMultiGPU; % make a handle to the function to use
    %         % else
    %         %     mibDeepAugmentOpt.O_PreviewImagePatches = obj.BatchOpt.O_PreviewImagePatches;
    %         %     mibDeepAugmentOpt.O_FractionOfPreviewPatches = obj.BatchOpt.O_FractionOfPreviewPatches{1};
    %         %     augmentFunctionHandle = @obj.augmentAndCrop3dPatch; % make a handle to the function to use
    %         % end
    % 
    %         if obj.BatchOpt.T_augmentation
    %             status  = obj.setAugFuncHandles('3D');
    %             if status == 0
    %                 if showWaitbarLocal; delete(obj.wb); end
    %                 return;
    %             end
    % 
    %             AugTrainDS = transform(patchDS, @(patchIn, info)augmentFunctionHandle(patchIn, info, inputPatchSize(1:3), outputPatchSize, 'aug', mibDeepAugmentOpt), 'IncludeInfo', true);
    %             if ~isempty(valPatchDS)
    %                 valDS = transform(valPatchDS, @(patchIn, info)augmentFunctionHandle(patchIn, info, inputPatchSize(1:3), outputPatchSize, 'crop', mibDeepAugmentOpt), 'IncludeInfo', true);
    %             else
    %                 valDS = [];
    %             end
    %         else
    %             if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'valid')
    %                 % crop responses to the output size of the network
    %                 AugTrainDS = transform(patchDS, @(patchIn, info)augmentFunctionHandle(patchIn, info, inputPatchSize(1:3), outputPatchSize, 'crop', mibDeepAugmentOpt), 'IncludeInfo', true);
    %                 if ~isempty(valPatchDS)
    %                     valDS = transform(valPatchDS, @(patchIn, info)augmentFunctionHandle(patchIn, info, inputPatchSize(1:3), outputPatchSize, 'crop', mibDeepAugmentOpt), 'IncludeInfo', true);
    %                 else
    %                     valDS = [];
    %                 end
    % 
    %             else
    %                 % no cropping needed for the same padding
    %                 AugTrainDS = transform(patchDS, @(patchIn, info)augmentFunctionHandle(patchIn, info, inputPatchSize, outputPatchSize, 'show', mibDeepAugmentOpt), 'IncludeInfo', true);
    %                 valDS = valPatchDS;
    %             end
    %         end
    %     case '2D'
    %         % define options for the augmenter function
    %         mibDeepAugmentOpt.Workflow = obj.BatchOpt.Workflow{1};
    %         mibDeepAugmentOpt.Aug2DFuncNames = obj.Aug2DFuncNames;
    %         mibDeepAugmentOpt.AugOpt2D = obj.AugOpt2D;
    %         mibDeepAugmentOpt.Aug2DFuncProbability = obj.Aug2DFuncProbability;
    %         mibDeepAugmentOpt.T_ConvolutionPadding = obj.BatchOpt.T_ConvolutionPadding{1};
    % 
    %         % define augmenting function; the functions are essentially the same, but the multi-gpu
    %         % version does not have access to MibDeep and obj.TrainingProgress
    %         mibDeepAugmentOpt.O_PreviewImagePatches = obj.BatchOpt.O_PreviewImagePatches;
    %         mibDeepAugmentOpt.O_FractionOfPreviewPatches = obj.BatchOpt.O_FractionOfPreviewPatches{1};
    %         mibDeepAugmentOpt.T_NumberOfClasses = obj.BatchOpt.T_NumberOfClasses{1};
    % 
    %         augmentFunctionHandle = @deepmib.augmentAndCrop2dPatchMultiGPU; % make a handle to the function to use
    % 
    %         % if ismember(obj.view.Figure.GPUDropDown.Value, {'Multi-GPU', 'Parallel'})
    %         %     augmentFunctionHandle = @deepmib.augmentAndCrop2dPatchMultiGPU; % make a handle to the function to use
    %         % else
    %         %     mibDeepAugmentOpt.O_PreviewImagePatches = obj.BatchOpt.O_PreviewImagePatches;
    %         %     mibDeepAugmentOpt.O_FractionOfPreviewPatches = obj.BatchOpt.O_FractionOfPreviewPatches{1};
    %         %     augmentFunctionHandle = @obj.augmentAndCrop2dPatch; % make a handle to the function to use
    %         % end
    % 
    %         if obj.BatchOpt.T_augmentation
    %             % define augmentation
    %             status = obj.setAugFuncHandles('2D');
    %             if status == 0
    %                 if showWaitbarLocal; delete(obj.wb); end
    %                 return;
    %             end
    % 
    %             AugTrainDS = transform(patchDS, @(patchIn, info)augmentFunctionHandle(patchIn, info, inputPatchSize, outputPatchSize, 'aug', mibDeepAugmentOpt), ...
    %                 'IncludeInfo', true);
    %             %                         for i=1:50
    %             %                             I = read(AugTrainDS);
    %             %                             if size(I.inpVol{1},3) == 2
    %             %                                 I.inpVol{1}(:,:,3) = zeros([size(I.inpVol{1}, 1), size(I.inpVol{1}, 2)]);
    %             %                             end
    %             %                             figure(1)
    %             %                             imshowpair(I.inpVol{1}, uint8(I.inpResponse{1}),'montage');
    %             %                         end
    % 
    %             if ~isempty(valPatchDS)
    %                 valDS = transform(valPatchDS, @(patchIn, info)augmentFunctionHandle(patchIn, info, inputPatchSize, outputPatchSize, 'crop', mibDeepAugmentOpt), 'IncludeInfo', true);
    %             else
    %                 valDS = [];
    %             end
    %         else
    %             if strcmp(obj.BatchOpt.T_ConvolutionPadding{1}, 'valid')
    %                 % crop responses to the output size of the network
    %                 AugTrainDS = transform(patchDS, @(patchIn, info)augmentFunctionHandle(patchIn, info, inputPatchSize, outputPatchSize, 'crop', mibDeepAugmentOpt), 'IncludeInfo', true);
    %                 if ~isempty(valPatchDS)
    %                     valDS = transform(valPatchDS, @(patchIn, info)augmentFunctionHandle(patchIn, info, inputPatchSize, outputPatchSize, 'crop', mibDeepAugmentOpt), 'IncludeInfo', true);
    %                 else
    %                     valDS = [];
    %                 end
    %             else
    %                 AugTrainDS = transform(patchDS, @(patchIn, info)augmentFunctionHandle(patchIn, info, inputPatchSize, outputPatchSize, 'show', mibDeepAugmentOpt), 'IncludeInfo', true);
    %                 % https://se.mathworks.com/help/deeplearning/ug/image-augmentation-using-image-processing-toolbox.html
    %                 valDS = valPatchDS;
    %             end
    %         end
    % end

    % calculate max number of iterations
    mibDeepTrainingProgressStruct.maxNoIter = ...        % as noImages*PatchesPerImage*MaxEpochs/Minibatch
        ceil((noFiles-mod(noFiles, obj.BatchOpt.T_MiniBatchSize{1}))/obj.BatchOpt.T_MiniBatchSize{1}) * obj.TrainingOpt.MaxEpochs;

    mibDeepTrainingProgressStruct.iterPerEpoch = ...
        mibDeepTrainingProgressStruct.maxNoIter / obj.TrainingOpt.MaxEpochs;

    % generate training options structure
    
    % validation is attempted when a validation set is available; if trainSOLOV2
    % rejects it at runtime we retry once without validation (see below)
    if noValidationObservations == 0
        valLabelsDS = [];
    end
    TrainingOptions = obj.preprareTrainingOptionsInstances(valLabelsDS);

    %% Train Network
    % After configuring the training options and the data source, train the 3-D U-Net network
    % by using the trainNetwork function.
    if showWaitbarLocal
        if obj.wb.CancelRequested; deepmib.stopTrainingCallback(obj.wb); return; end
        obj.wb.Message = 'Starting trainining...';
        obj.wb.Value = 0.9;
    end
    modelDateTime = datestr(now, 'dd-mmm-yyyy-HH-MM-SS');

    % the network (new or restored from checkpoint) was already prepared above
    % during network creation; no additional layer surgery is needed for SOLOv2

    if showWaitbarLocal
        if obj.wb.CancelRequested; deepmib.stopTrainingCallback(obj.wb); return; end
        obj.wb.Message = 'Preparing structures and saving configs...';
        obj.wb.Value = 0.95;
    end
    BatchOpt = obj.BatchOpt;
    % generate TrainingOptStruct, because TrainingOptions is 'TrainingOptionsADAM' class
    AugOpt2DStruct = obj.AugOpt2D;
    AugOpt3DStruct = obj.AugOpt3D;
    InputLayerOpt = obj.InputLayerOpt;
    TrainingOptStruct = obj.TrainingOpt;
    ActivationLayerOpt = obj.ActivationLayerOpt;
    SegmentationLayerOpt = obj.SegmentationLayerOpt;
    DynamicMaskOpt = obj.DynamicMaskOpt;

    % generate config file; the config file is the same as *.mibDeep but without 'net' field
    [configPath, configFn] = fileparts(obj.BatchOpt.NetworkFilename);
    obj.saveConfig(fullfile(configPath, [configFn '.mibCfg']));

    if showWaitbarLocal
        if obj.wb.CancelRequested; deepmib.stopTrainingCallback(obj.wb); return; end
        delete(obj.wb);
    end
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Network problem');
    if showWaitbarLocal; delete(obj.wb); end
    return;
end

obj.view.handles.TrainButton.Text = 'Stop training';
obj.view.handles.TrainButton.BackgroundColor = 'g'; %[1 .5 0]; % 0.7686    0.9020    0.9882
drawnow;
fprintf('Preparation for training is finished, elapsed time: %f\n', toc(trainTimer));

trainTimer = tic;
emergencyBrakeUsed = false;     % network was recovered from a checkpoint, info is synthetic

% "Starting weights" decides what happens to the COCO-pretrained backbone.
% A frozen backbone is faster and less prone to overfitting on very small datasets, but
% leaves the features tuned to natural photographs; letting it train adapts them to
% microscopy data and needs a much lower learning rate - low enough that the two do not
% share one setting, which is why "frozen then trainable" runs them as separate phases.
% trainSOLOV2 also accepts 'backboneAndNeck', which freezes more and is not exposed.
switch obj.BatchOpt.T_StartingWeights{1}
    case 'COCO, frozen backbone'
        freezeSubNetwork = 'backbone';
    case 'COCO, frozen then trainable'
        freezeSubNetwork = 'backbone';      % phase 1; phase 2 switches it to 'none'
    otherwise
        freezeSubNetwork = 'none';
end
twoPhaseSchedule = strcmp(obj.BatchOpt.T_StartingWeights{1}, 'COCO, frozen then trainable');

if twoPhaseSchedule
    % Phase 1 is capped at a share of the total epochs and may end earlier if the loss
    % goes flat; whatever it leaves unused is handed to phase 2, so the total epoch
    % budget the user asked for is preserved either way.
    frozenPhaseEpochs = max(1, round(obj.TrainingOpt.MaxEpochs * obj.StartingWeightsOpt.MaxFrozenFraction));
    phaseOverrides = struct('MaxEpochs', frozenPhaseEpochs);
    % cleared explicitly rather than relying on the end-of-run reset of the global: a run
    % that errored out during finalization would otherwise leave a stale flag behind and
    % the next run would skip its trainable phase without ever having trained
    mibDeepTrainingProgressStruct.phaseSwitchRequested = false;
    mibDeepTrainingProgressStruct.collapseDetected = false;
    mibDeepTrainingProgressStruct.zeroDetectionEvaluations = 0;
    % Plateau detection lives in the custom progress window's OutputFcn, so without that
    % window there is nothing watching the loss - fall back to the epoch cap alone.
    if obj.BatchOpt.O_CustomTrainingProgressWindow && ~strcmp(obj.TrainingOpt.Plots, 'none')
        % both fractions are shares of the *total* epoch budget, so the earliest and the
        % latest switch are expressed on the same scale the user set MaxEpochs on
        minFrozenIterations = ceil(obj.TrainingOpt.MaxEpochs * obj.StartingWeightsOpt.MinFrozenFraction * ...
            mibDeepTrainingProgressStruct.iterPerEpoch);
        phaseOverrides.plateauDetection = struct(...
            'WindowEpochs', obj.StartingWeightsOpt.PlateauWindowEpochs, ...
            'Tolerance', obj.StartingWeightsOpt.PlateauTolerance, ...
            'MinIterations', minFrozenIterations);
        % Deliberately not bounded by minFrozenIterations: a collapsed head shows itself
        % within a few hundred iterations, and the whole point is to stop before the
        % epoch cap burns hours on a run that cannot produce a network.
        if obj.StartingWeightsOpt.CollapseEvaluations > 0
            phaseOverrides.collapseDetection = struct(...
                'Evaluations', obj.StartingWeightsOpt.CollapseEvaluations);
        end
    else
        warning('DeepMIB:instancePlateau', ...
            ['the custom training progress window is disabled, so the frozen phase cannot watch the loss; ' ...
            'it will run the full %d epochs before unfreezing'], frozenPhaseEpochs);
    end
    TrainingOptions = obj.preprareTrainingOptionsInstances(valLabelsDS, phaseOverrides);
    fprintf('DeepMIB: phase 1 of 2, backbone frozen, up to %d epochs at a learn rate of %g\n', ...
        frozenPhaseEpochs, obj.TrainingOpt.InitialLearnRate);
end

try
    mibDeepStopTraining = false;

    [net, info] = trainSOLOV2(...
        labelsDS, ...
        lgraph, ...
        TrainingOptions, ...
        'FreezeSubNetwork', freezeSubNetwork);
    %'ExperimentMonitor', 'none');
catch err
    % a stop request renames the checkpoint folder out of the way; put it back before any
    % branch below reads it or gives up on the run
    deepmib.suspendCheckpointSaving('restore');

    % The Emergency brake button breaks out of trainSOLOV2 by throwing from the datastore
    % ReadFcn (see deepmib.readInstancePatch), the only way to leave the trainer without
    % walking through every remaining epoch. The trained network never gets returned in that
    % case, so rebuild it from the newest checkpoint on disk.
    % The flag is trusted ahead of the identifier because the error travels out through
    % minibatchqueue, which may wrap it and replace the identifier on the way
    if mibDeepTrainingProgressStruct.emergencyBrake || strcmp(err.identifier, 'DeepMIB:userEmergencyStop')
        [net, info] = iRecoverNetworkFromCheckpoint(...
            fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork'), mibDeepTrainingProgressStruct);
        if isempty(net)
            mgsOpt.MsgBoxOnly = true;
            mgsOpt.Icon = 'puffin_error';
            mgsOpt.HeaderLines = 4;
            header = sprintf(['Training was stopped by the Emergency brake, but no checkpoint file was found in\n\n%s\n\n' ...
                'The network could not be restored. Enable "Save checkpoint networks" before the run to be able to use the Emergency brake.'], ...
                fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork'));
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'No checkpoint to restore', mgsOpt);
            if isfield(mibDeepTrainingProgressStruct, 'useCustomProgressPlot') && mibDeepTrainingProgressStruct.useCustomProgressPlot && ...
                    isfield(mibDeepTrainingProgressStruct, 'StopTrainingButton')
                mibDeepTrainingProgressStruct.StopTrainingButton.Text = 'Train';
                mibDeepTrainingProgressStruct.StopTrainingButton.BackgroundColor = [0.7686    0.9020    0.9882];
            end
            obj.view.handles.TrainButton.Text = 'Train';
            obj.view.handles.TrainButton.BackgroundColor = [0.7686    0.9020    0.9882];
            return;
        end
        emergencyBrakeUsed = true;
    % SOLOv2 validation support can be version-dependent; when a validation set was
    % provided, retry once without validation before reporting the error to the user
    elseif ~isempty(valLabelsDS)
        warning('DeepMIB:instanceValidation', ...
            'trainSOLOV2 failed with validation data (%s); retrying without validation', err.message);

        % The failed attempt has already run up to the first validation event (~1 epoch)
        % and drawn that part of the training curve in the custom progress window. The
        % retry restarts trainSOLOV2 from iteration 1, so unless we reset the progress
        % display it would append the new curve on top of the old one (the curve
        % "jumping back to the beginning"). Close the old window and drop the
        % sendNextReportAtEpoch field so the OutputFcn re-initialises a fresh plot on the
        % retry's first call (see deepmib.customTrainingProgressDisplay).
        if isfield(mibDeepTrainingProgressStruct, 'useCustomProgressPlot') && mibDeepTrainingProgressStruct.useCustomProgressPlot
            if isfield(mibDeepTrainingProgressStruct, 'UIFigure') && ~isempty(mibDeepTrainingProgressStruct.UIFigure) && isvalid(mibDeepTrainingProgressStruct.UIFigure)
                delete(mibDeepTrainingProgressStruct.UIFigure);
            end
            if isfield(mibDeepTrainingProgressStruct, 'sendNextReportAtEpoch')
                mibDeepTrainingProgressStruct = rmfield(mibDeepTrainingProgressStruct, 'sendNextReportAtEpoch');
            end
        end

        try
            TrainingOptions = obj.preprareTrainingOptionsInstances([]);
            [net, info] = trainSOLOV2(labelsDS, lgraph, TrainingOptions, 'FreezeSubNetwork', freezeSubNetwork);
        catch err2
            utils.dlgs.showErrorDialog(obj.view.gui, err2, 'Train instance network error');
            return;
        end
    else
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Train instance network error');
        return;
    end
end

% trainSOLOV2 (dltrain-based) returns info as a STRUCT ARRAY with one row per logged
% iteration, and OutputNetworkIteration as a per-row logical flag marking the row whose
% network was selected as output (see images.dltrain.internal.dltrain.m: "info(end
% /BestNetworkIteration-matching row).OutputNetworkIteration = true"). This differs from
% trainNetwork/trainnet, which return a SCALAR struct with vector-valued fields and a
% scalar OutputNetworkIteration iteration number - the shape the finalisation/reporting
% code below (shared with the semantic workflow, see controllers.MibDeep/startTraining)
% expects. Dot-indexing a field on a multi-row struct array (e.g. info.TrainingLoss)
% expands into a comma-separated list, which crashes any function called on it directly
% (e.g. isempty(info.OutputNetworkIteration) errors "Too many input arguments" once there
% is more than one row). Normalise here, once, right after info is produced, so every
% downstream use of "info" below - and the fieldnames(info) CSV export loop further down -
% sees the familiar scalar-struct/vector-field shape.
% put the checkpoint folder back before any finalisation step reads or writes it; a
% graceful stop leaves it renamed (see deepmib.suspendCheckpointSaving)
deepmib.suspendCheckpointSaving('restore');

% iRecoverNetworkFromCheckpoint already produces info in the normalised shape
if ~emergencyBrakeUsed
    info = iNormalizeTrainingInfo(info);
end
% The progress window that is on screen belongs to whichever phase ran last and counts its
% own iterations from 1, while "info" may be the concatenation of both phases. Keep the
% last phase's record separately: everything drawn into that window has to use it, or the
% picked-iteration marker lands off the end of the axes and the curve is stretched to the
% combined length. Exports use the concatenated "info".
lastPhaseInfo = info;

%% Phase 2 of the "COCO, frozen then trainable" schedule
% The backbone is unfrozen and training continues from the network phase 1 produced, at a
% much lower learning rate. FreezeSubNetwork is an argument of trainSOLOV2 rather than a
% property of the detector, so it applies to the restored weights exactly as it would to a
% fresh solov2() - only the weights carry over.
% Skipped when the user stopped the run or used the Emergency brake: both mean "stop", and
% silently starting a second phase would ignore that.
if twoPhaseSchedule && ~emergencyBrakeUsed
    plateauReached = isfield(mibDeepTrainingProgressStruct, 'phaseSwitchRequested') && ...
        mibDeepTrainingProgressStruct.phaseSwitchRequested;
    % A collapsed frozen phase looks exactly like a converged one in the loss curve, so it
    % has to be tested separately - see the collapse detector in
    % deepmib.customTrainingProgressDisplay for what it measures and why.
    collapseDetected = isfield(mibDeepTrainingProgressStruct, 'collapseDetected') && ...
        mibDeepTrainingProgressStruct.collapseDetected;
    userStopped = mibDeepStopTraining && ~plateauReached && ~collapseDetected;

    if collapseDetected
        collapseMessage = sprintf([ ...
            'The frozen phase collapsed: validation mAP stayed at 0.000 for %d consecutive evaluations, ' ...
            'so the network is detecting nothing at all.\n\n' ...
            'The backbone was NOT unfrozen. Unfreezing cannot repair a saturated detection head - the ' ...
            'trainable phase runs at a much smaller learn rate and would only spend hours confirming the ' ...
            'same result.\n\n' ...
            'The usual cause is too large an initial learn rate. With the adam solver this workflow needs ' ...
            'about 0.001; 0.003 and above collapse the head within a few hundred iterations. The 0.01 in ' ...
            'the "Initial learn rate" tooltip is the sgdm default and does not apply to adam.\n\n' ...
            'Lower the initial learn rate in the training settings and start the run again.'], ...
            obj.StartingWeightsOpt.CollapseEvaluations);
        fprintf('DeepMIB: %s\n', collapseMessage);
        collapseDlgOpt.MsgBoxOnly = true;
        collapseDlgOpt.Icon = 'puffin_warning';
        collapseDlgOpt.HeaderLines = 12;
        utils.dlgs.inputUniversalDlg(obj.view.gui, collapseMessage, {}, {}, ...
            'Frozen phase collapsed', collapseDlgOpt);
    elseif userStopped
        fprintf('DeepMIB: training was stopped during the frozen phase, the trainable phase is skipped\n');
    else
        frozenInfo = info;
        frozenNet = net;
        % epochs the frozen phase actually used; a plateau stop can leave a large unused
        % remainder, which is handed to the trainable phase
        if isfield(frozenInfo, 'Epoch') && ~isempty(frozenInfo.Epoch)
            frozenEpochsUsed = max(frozenInfo.Epoch);
        else
            frozenEpochsUsed = frozenPhaseEpochs;
        end
        frozenIterationsUsed = numel(frozenInfo.TrainingLoss);
        trainablePhaseEpochs = max(1, obj.TrainingOpt.MaxEpochs - frozenEpochsUsed);
        % capped at the frozen-phase rate so the trainable phase can never end up taking
        % larger steps than the phase that only had to move randomly initialized heads
        trainableLearnRate = min(obj.StartingWeightsOpt.TrainableLearnRate, obj.TrainingOpt.InitialLearnRate);
        if trainableLearnRate < obj.StartingWeightsOpt.TrainableLearnRate
            fprintf(['DeepMIB: the trainable-phase learn rate was capped from %g to the frozen-phase rate %g\n' ...
                '  (a trainable backbone should never take larger steps than a frozen one)\n'], ...
                obj.StartingWeightsOpt.TrainableLearnRate, trainableLearnRate);
        end

        fprintf('DeepMIB: phase 2 of 2, backbone trainable, %d epochs at a learn rate of %g\n', ...
            trainablePhaseEpochs, trainableLearnRate);

        % Always keep the frozen-phase network, independently of "Save checkpoint
        % networks". It is the only moment in the run where a network of a genuinely
        % different kind exists, it is what the trainable phase is compared against, and
        % without it a failure in phase 2 would leave nothing to fall back on. The
        % "frozenPhaseEnd" suffix names it; the "net_checkpoint__" prefix is kept so the
        % resume dialog and iRecoverNetworkFromCheckpoint both find it.
        try
            checkpointDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork');
            if ~isfolder(checkpointDir); mkdir(checkpointDir); end
            phaseCheckpointName = fullfile(checkpointDir, ...
                sprintf('net_checkpoint__frozenPhaseEnd_%d__%s.mat', frozenIterationsUsed, ...
                char(datetime('now', 'Format', 'yyyy_MM_dd__HH_mm_ss'))));
            % "net" still holds the frozen-phase network here, and that is the variable
            % name every restore path in this file loads by
            save(phaseCheckpointName, 'net', 'inputPatchSize', 'outputPatchSize', '-mat', '-v7.3');
            fprintf('DeepMIB: the frozen-phase network was saved as\n  %s\n', phaseCheckpointName);
        catch saveErr
            % never let a failed bookkeeping save cost the run
            warning('DeepMIB:frozenPhaseCheckpoint', ...
                'could not save the frozen-phase network (%s); training continues', saveErr.message);
        end

        % The phase 1 window is about to be destroyed, so its plot has to be captured now
        % or it is gone for good - unlike the curve itself, which survives in the
        % concatenated info and the exported CSVs.
        frozenSnapshotOk = iSaveProgressSnapshot(obj, mibDeepTrainingProgressStruct, '_frozenPhase');

        % the trainer restarts its iteration counter, so give the progress display a clean
        % window rather than letting phase 2 draw on top of the phase 1 curve; the missing
        % sendNextReportAtEpoch field is what makes the OutputFcn rebuild it
        if isfield(mibDeepTrainingProgressStruct, 'useCustomProgressPlot') && mibDeepTrainingProgressStruct.useCustomProgressPlot
            if isfield(mibDeepTrainingProgressStruct, 'UIFigure') && ~isempty(mibDeepTrainingProgressStruct.UIFigure) && isvalid(mibDeepTrainingProgressStruct.UIFigure)
                if frozenSnapshotOk
                    delete(mibDeepTrainingProgressStruct.UIFigure);
                else
                    % the PNG could not be captured (locked screen), so leave this window
                    % on screen instead of destroying the only live copy of the phase 1
                    % curve; its own "Save plot" button still works, because that callback
                    % holds its own reference to this figure. Phase 2 builds a new window.
                    mibDeepTrainingProgressStruct.UIFigure.Name = ...
                        'DeepMIB training, frozen phase - press "Save plot" to store this plot';
                end
            end
            if isfield(mibDeepTrainingProgressStruct, 'sendNextReportAtEpoch')
                mibDeepTrainingProgressStruct = rmfield(mibDeepTrainingProgressStruct, 'sendNextReportAtEpoch');
            end
        end
        mibDeepTrainingProgressStruct.phaseSwitchRequested = false;
        mibDeepTrainingProgressStruct.spinDownActive = false;
        mibDeepTrainingProgressStruct.plateauLoss = [];     % phase 2 has no plateau detector
        mibDeepStopTraining = false;

        mibDeepTrainingProgressStruct.maxNoIter = ...
            ceil((noFiles - mod(noFiles, obj.BatchOpt.T_MiniBatchSize{1}))/obj.BatchOpt.T_MiniBatchSize{1}) * trainablePhaseEpochs;
        mibDeepTrainingProgressStruct.iterPerEpoch = mibDeepTrainingProgressStruct.maxNoIter / trainablePhaseEpochs;

        try
            TrainingOptions = obj.preprareTrainingOptionsInstances(valLabelsDS, ...
                struct('MaxEpochs', trainablePhaseEpochs, 'InitialLearnRate', trainableLearnRate));
            [net, info] = trainSOLOV2(labelsDS, frozenNet, TrainingOptions, 'FreezeSubNetwork', 'none');
            deepmib.suspendCheckpointSaving('restore');
            info = iNormalizeTrainingInfo(info);
            lastPhaseInfo = info;   % what the on-screen phase-2 window is showing
            info = iConcatenateTrainingInfo(frozenInfo, info, frozenIterationsUsed);
        catch err
            deepmib.suspendCheckpointSaving('restore');
            if mibDeepTrainingProgressStruct.emergencyBrake || strcmp(err.identifier, 'DeepMIB:userEmergencyStop')
                [recoveredNet, recoveredInfo] = iRecoverNetworkFromCheckpoint(...
                    fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork'), mibDeepTrainingProgressStruct);
                if isempty(recoveredNet)
                    % nothing to restore, keep what the frozen phase produced rather than
                    % losing the whole run
                    net = frozenNet;
                    info = frozenInfo;

                    net = frozenNet;
                    lastPhaseInfo = frozenInfo;
                else
                    net = recoveredNet;
                    lastPhaseInfo = recoveredInfo;
                    info = iConcatenateTrainingInfo(frozenInfo, recoveredInfo, frozenIterationsUsed);
                    emergencyBrakeUsed = true;
                end
            else
                % the frozen phase succeeded, so report the failure but still save its
                % network - discarding it would throw away hours of finished work
                utils.dlgs.showErrorDialog(obj.view.gui, err, ...
                    'Trainable phase failed, saving the frozen-phase network');
                net = frozenNet;
                info = frozenInfo;

                net = frozenNet;
                lastPhaseInfo = frozenInfo;
            end
        end
    end
end

if showWaitbarLocal
    obj.wb = uiprogressdlg(obj.view.gui, 'Message', 'Finalizing training...', ...
        'Title', 'Finalize training', 'Cancelable', 'on');
end

if isfield(mibDeepTrainingProgressStruct, 'useCustomProgressPlot') && mibDeepTrainingProgressStruct.useCustomProgressPlot && ...
        isfield(mibDeepTrainingProgressStruct, 'UILossAxes') && isvalid(mibDeepTrainingProgressStruct.UILossAxes)
    hold(mibDeepTrainingProgressStruct.UILossAxes, 'on');
    % Everything below is drawn into the window of the phase that ran last, so it uses
    % lastPhaseInfo and its local iteration numbers. Using the concatenated "info" here
    % put the picked-iteration marker past the end of the axes (7280 on a plot that
    % stopped at 1556) and stretched the curve to the combined length.
    lastPhaseIterations = numel(lastPhaseInfo.TrainingLoss);

    % add a vertical line at the selected iteration indicating the picked network.
    % OutputNetworkIteration can be empty (e.g. when training was retried without
    % validation) - skip the marker line in that case to avoid a plot size mismatch
    if isfield(lastPhaseInfo, 'OutputNetworkIteration') && ~isempty(lastPhaseInfo.OutputNetworkIteration)
        pickedIteration = lastPhaseInfo.OutputNetworkIteration;
        mibDeepTrainingProgressStruct.hPlot(3) = plot(mibDeepTrainingProgressStruct.UILossAxes, [pickedIteration, pickedIteration], mibDeepTrainingProgressStruct.UILossAxes.YLim, '-');
        mibDeepTrainingProgressStruct.hPlot(3).Color = [0 .7 0];
        mibDeepTrainingProgressStruct.UILossAxes.Legend.String = {'Training'  'Validation'  sprintf('Picked iteration: %d', pickedIteration)};
    end
    % add last point to the plot
    if ~isempty(mibDeepTrainingProgressStruct.hPlot(1).XData) && mibDeepTrainingProgressStruct.hPlot(1).XData(end) < lastPhaseIterations
        warning('off','MATLAB:gui:array:InvalidArrayShape');
        mibDeepTrainingProgressStruct.hPlot(1).XData = [mibDeepTrainingProgressStruct.hPlot(1).XData, lastPhaseIterations];
        mibDeepTrainingProgressStruct.hPlot(1).YData = [mibDeepTrainingProgressStruct.hPlot(1).YData, lastPhaseInfo.TrainingLoss(end)];
        % ValidationLoss is padded with NaN on the iterations where no validation ran, so
        % the last element is usually NaN; take the last one that actually holds a value
        if isfield(lastPhaseInfo, 'ValidationLoss')
            lastValidation = find(~isnan(lastPhaseInfo.ValidationLoss), 1, 'last');
            if ~isempty(lastValidation)
                mibDeepTrainingProgressStruct.hPlot(2).XData = [mibDeepTrainingProgressStruct.hPlot(2).XData lastValidation];
                mibDeepTrainingProgressStruct.hPlot(2).YData = [mibDeepTrainingProgressStruct.hPlot(2).YData lastPhaseInfo.ValidationLoss(lastValidation)];
            end
        end
        warning('on','MATLAB:gui:array:InvalidArrayShape');
    end
    % a stopped run ends well before the planned number of iterations, so bring the axis
    % back to where the data actually ends instead of leaving the full budget on screen
    if lastPhaseIterations > 0
        xlim(mibDeepTrainingProgressStruct.UILossAxes, [0, lastPhaseIterations]);
    end
    hold(mibDeepTrainingProgressStruct.UILossAxes, 'off');
end

if showWaitbarLocal
    if obj.wb.CancelRequested; deepmib.stopTrainingCallback(obj.wb); return; end
    obj.wb.Message = 'Saving network...';
    obj.wb.Value = 0.3;
end

% do emergency brake, use the recent check point for restoring the network parameters
if mibDeepTrainingProgressStruct.emergencyBrake && (obj.BatchOpt.Workflow{1}(1) == '3' || strcmp(obj.BatchOpt.Workflow{1}, 'SegNet'))
    if isfolder(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork'))
        progressFiles = dir(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', '*.mat'));
        if ~isempty(progressFiles)
            [~, idx]=sort([progressFiles.datenum], 'descend');      % sort in time order
            checkPointRestoreFile = fullfile(progressFiles(idx(1)).folder, progressFiles(idx(1)).name);
            load(checkPointRestoreFile, 'net', '-mat');
        end
    end
end

OverlapInstancesOpt = obj.OverlapInstancesOpt;
StartingWeightsOpt = obj.StartingWeightsOpt;   %#ok<NASGU> saved below, records the two-phase schedule that produced this network
save(obj.BatchOpt.NetworkFilename, 'net', 'TrainingOptStruct', 'AugOpt2DStruct', 'AugOpt3DStruct', 'InputLayerOpt', ...
    'ActivationLayerOpt', 'SegmentationLayerOpt', 'DynamicMaskOpt', 'OverlapInstancesOpt', 'StartingWeightsOpt', ...
    'classNames', 'classColors', 'inputPatchSize', 'outputPatchSize', 'BatchOpt', '-mat', '-v7.3');

if showWaitbarLocal
    if obj.wb.CancelRequested; deepmib.stopTrainingCallback(obj.wb); return; end
    obj.wb.Message = 'Exporting training plots...';
    obj.wb.Value = 0.7;
end

if obj.BatchOpt.T_ExportTrainingPlots
    %if showWaitbarLocal; if ~isvalid(obj.wb); return; end; waitbar(0.99, obj.wb, 'Saving training plots...'); end
    datetimeTag = char(datetime('now', 'format', 'yyMMddHHmm'));
    [~, fnTemplate] = fileparts(obj.BatchOpt.NetworkFilename);
    fnTemplate = [datetimeTag, '_', fnTemplate];
    if exist(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork'), 'dir') ~= 7
        mkdir(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork'));
    end
    save(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', [fnTemplate '.score']), 'info', '-mat', '-v7.3');
    fieldNames = fieldnames(info);
    for fieldId = 1:numel(fieldNames)
        writematrix(info.(fieldNames{fieldId}), ...
            fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', [fnTemplate '_' fieldNames{fieldId} '.csv']));
    end
    % snapshot of the finished progress window, as the semantic workflow does at the end of
    % controllers.MibDeep/startTraining
    iSaveProgressSnapshot(obj, mibDeepTrainingProgressStruct, '');
end
if showWaitbarLocal
    obj.wb.Value = 1;
    delete(obj.wb);
end

% Every read of mibDeepTrainingProgressStruct from here on is guarded with isfield: pressing
% "Stop training" a second time takes deepmib.stopTrainingCallback down its 'Stopping...'
% branch, which detaches the progress window by resetting the global to an empty struct.
% That happens while this finalization code is still running, so the fields it wants can
% disappear between two consecutive statements.
if isfield(mibDeepTrainingProgressStruct, 'useCustomProgressPlot') && mibDeepTrainingProgressStruct.useCustomProgressPlot && ...
        isfield(mibDeepTrainingProgressStruct, 'StopTrainingButton') && isvalid(mibDeepTrainingProgressStruct.StopTrainingButton)
    mibDeepTrainingProgressStruct.StopTrainingButton.BackgroundColor = [0 1 0];
    mibDeepTrainingProgressStruct.StopTrainingButton.Text = 'Finished!!!';
end

if obj.SendReports.T_SendReports && obj.SendReports.sendWhenFinished && ...
        isfield(mibDeepTrainingProgressStruct, 'maxNoIter') && ...
        numel(info.TrainingLoss) >= mibDeepTrainingProgressStruct.maxNoIter && ...
        isfield(mibDeepTrainingProgressStruct, 'sendNextReportAtEpoch') && ...
        mibDeepTrainingProgressStruct.sendNextReportAtEpoch ~= -1
    [~, fn] = fileparts(obj.BatchOpt.NetworkFilename);
    % SOLOv2 info has fewer fields than semantic training (no accuracy/validation
    % metrics); fetch each metric defensively so the report never errors
    infoVal = @(fieldName) iInfoLastValue(info, fieldName);
    if isfield(mibDeepTrainingProgressStruct, 'useCustomProgressPlot') && mibDeepTrainingProgressStruct.useCustomProgressPlot
        mgsText = sprintf(['DeepMIB training of "%s" network\n' ...
            '%s\n' ...
            'Iteration Number: %s\n\n' ...
            '%s\n%s\n%s\n\n' ...
            'Training Loss: %f\n' ...
            'Training Accuracy: %f\n' ...
            'Validation Loss: %f\n' ...
            'Validation Accuracy: %f\n' ...
            'Final Validation Loss: %f\n' ...
            'Final Validation Accuracy: %f\n' ...
            'Output Network Iteration: %d\n'], ...
            fn, ...
            mibDeepTrainingProgressStruct.Epoch.Text, mibDeepTrainingProgressStruct.IterationNumberValue.Text, ...
            mibDeepTrainingProgressStruct.StartTime.Text, mibDeepTrainingProgressStruct.ElapsedTime.Text, mibDeepTrainingProgressStruct.TimeToGo.Text, ...
            infoVal('TrainingLoss'), infoVal('TrainingAccuracy'), ...
            infoVal('ValidationLoss'), infoVal('ValidationAccuracy'), ...
            infoVal('FinalValidationLoss'), infoVal('FinalValidationAccuracy'), ...
            infoVal('OutputNetworkIteration'));
    else
        mgsText = sprintf(['DeepMIB training of "%s" network\n' ...
            'Training Loss: %f\n' ...
            'Training Accuracy: %f\n' ...
            'Validation Loss: %f\n' ...
            'Validation Accuracy: %f\n' ...
            'Final Validation Loss: %f\n' ...
            'Final Validation Accuracy: %f\n' ...
            'Output Network Iteration: %d\n'], ...
            fn, infoVal('TrainingLoss'), infoVal('TrainingAccuracy'), ...
            infoVal('ValidationLoss'), infoVal('ValidationAccuracy'), ...
            infoVal('FinalValidationLoss'), infoVal('FinalValidationAccuracy'), ...
            infoVal('OutputNetworkIteration'));
    end
    sendmail(obj.SendReports.TO_email, sprintf('DeepMIB: training of %s is over!', fn), mgsText);
end

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfTrainedDeepNetworks = obj.mibModel.preferences.Users.Tiers.numberOfTrainedDeepNetworks+1;
eventdata = core.ToggleEventData(10);    % scale scoring by factor 5
notify(obj.mibModel, 'UpdateUserScore', eventdata);

mibDeepTrainingProgressStruct =  struct();
obj.view.handles.TrainButton.Text = 'Train';
obj.view.handles.TrainButton.BackgroundColor = [0.7686    0.9020    0.9882];

fprintf('Training is finished, elapsed time: %f\n', toc(trainTimer));
end

function snapshotOk = iSaveProgressSnapshot(obj, progressStruct, nameSuffix)
% write a PNG (and a .fig) of the custom training progress window
%
% Mirrors what controllers.MibDeep/startTraining does for the semantic workflows, and is
% called twice by the two-phase schedule: once when the frozen phase ends, because that
% window is deleted before the trainable phase starts, and once when the run finishes.
% The name matches the sibling .score and CSV files so a run's outputs group together.
%
% Input Arguments:
%   - **progressStruct** - the mibDeepTrainingProgressStruct with the live UIFigure
%   - **nameSuffix** - appended to the file name, e.g. ``'_frozenPhase'``; ``''`` for the
%     snapshot of the finished run
%
% Output Arguments:
%   - **snapshotOk** - [logical] false when the PNG could not be produced. deepmib.saveTrainingPlot
%     works by grabbing the screen rectangle the window occupies (``java.awt.Robot``), which
%     returns an all-black image while the workstation is locked - a long training run left
%     overnight is exactly when that happens. The caller uses this to keep the window on
%     screen so the plot can still be saved by hand from its "Save plot" button.
%
% Nothing here is worth failing a run over, so every step is inside a try.

snapshotOk = false;
if ~obj.BatchOpt.T_ExportTrainingPlots; return; end
if ~obj.BatchOpt.O_CustomTrainingProgressWindow; return; end
if ~isfield(progressStruct, 'UIFigure') || isempty(progressStruct.UIFigure) || ~isvalid(progressStruct.UIFigure)
    return;
end

try
    scoreDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork');
    if ~isfolder(scoreDir); mkdir(scoreDir); end
    [~, networkName] = fileparts(obj.BatchOpt.NetworkFilename);
    snapshotTemplate = [char(datetime('now', 'format', 'yyMMddHHmm')), '_', networkName, nameSuffix];

    % The .fig goes first and does not involve the screen at all, so the plot is
    % recoverable with openfig() even when the capture below produces nothing usable
    figName = fullfile(scoreDir, [snapshotTemplate '.fig']);
    savefig(progressStruct.UIFigure, figName);

    % saveTrainingPlot grabs the screen rectangle the window occupies, so it has to be
    % on top and finished redrawing before the capture
    pngName = fullfile(scoreDir, [snapshotTemplate '.png']);
    figure(progressStruct.UIFigure);
    drawnow;
    deepmib.saveTrainingPlot([], [], progressStruct, pngName);

    % A locked or blanked screen yields an all-black grab. Keeping that file would be
    % worse than having none: it looks like a saved plot until it is opened.
    capturedImage = imread(pngName);
    if nnz(capturedImage) / numel(capturedImage) < 0.01
        delete(pngName);
        warning('DeepMIB:trainingSnapshotBlank', ...
            ['the training plot could not be captured, the screen was most likely locked.\n' ...
            'The plot was still saved as a figure:\n  %s\nReopen it with openfig(...), or use ' ...
            '"Save plot" in the progress window, which stays open for this reason.'], figName);
        return;
    end
    snapshotOk = true;
catch snapshotErr
    warning('DeepMIB:trainingSnapshot', ...
        'could not save the training plot snapshot (%s)', snapshotErr.message);
end
end

% -------------------------------------------------------------------------------------
function info = iNormalizeTrainingInfo(info)
% reshape trainSOLOV2 training info into the scalar-struct/vector-field form used elsewhere
%
% trainSOLOV2 (dltrain-based) returns info as a STRUCT ARRAY with one row per logged
% iteration, and OutputNetworkIteration as a per-row logical flag marking the row whose
% network was selected as output (see images.dltrain.internal.dltrain.m: "info(end
% /BestNetworkIteration-matching row).OutputNetworkIteration = true"). This differs from
% trainNetwork/trainnet, which return a SCALAR struct with vector-valued fields and a
% scalar OutputNetworkIteration iteration number - the shape the finalisation/reporting
% code (shared with the semantic workflow, see controllers.MibDeep/startTraining) expects.
% Dot-indexing a field on a multi-row struct array (e.g. info.TrainingLoss) expands into a
% comma-separated list, which crashes any function called on it directly (e.g.
% isempty(info.OutputNetworkIteration) errors "Too many input arguments" once there is more
% than one row).

if ~isstruct(info) || ~isfield(info, 'OutputNetworkIteration'); return; end

infoRows = info;
outputRow = find([infoRows.OutputNetworkIteration], 1);
info = struct();
infoFieldNames = setdiff(fieldnames(infoRows), 'OutputNetworkIteration', 'stable');
for infoFieldIdx = 1:numel(infoFieldNames)
    info.(infoFieldNames{infoFieldIdx}) = [infoRows.(infoFieldNames{infoFieldIdx})];
end
if isempty(outputRow)
    info.OutputNetworkIteration = [];
else
    info.OutputNetworkIteration = infoRows(outputRow).Iteration;
end
end

% -------------------------------------------------------------------------------------
function info = iConcatenateTrainingInfo(firstInfo, secondInfo, iterationOffset)
% join the training info of the two phases into one continuous record
%
% The trainer restarts its Iteration and Epoch counters for the second phase, so both are
% shifted by what the first phase used; every other field is a plain per-iteration series
% and is simply appended. Only fields present in both phases survive - a metric that ran in
% one phase but not the other cannot form a continuous curve, and a ragged field would
% break the CSV export loop, which writes one row per field.

info = struct();
sharedFields = intersect(fieldnames(firstInfo), fieldnames(secondInfo), 'stable');
epochOffset = 0;
if ismember('Epoch', sharedFields) && ~isempty(firstInfo.Epoch)
    epochOffset = max(firstInfo.Epoch);
end
% TimeElapsed restarts at zero for the second trainSOLOV2 call the same way Iteration and
% Epoch do, which made the exported CSV jump backwards at the phase boundary (11:24:56 in
% the last frozen row, then 00:00:12 in the first trainable one)
timeOffset = 0;
if ismember('TimeElapsed', sharedFields) && ~isempty(firstInfo.TimeElapsed)
    timeOffset = max(firstInfo.TimeElapsed);
end

for fieldIdx = 1:numel(sharedFields)
    fieldName = sharedFields{fieldIdx};
    if strcmp(fieldName, 'OutputNetworkIteration')
        % the network that was kept comes from the second phase
        if isempty(secondInfo.OutputNetworkIteration)
            info.OutputNetworkIteration = [];
        else
            info.OutputNetworkIteration = secondInfo.OutputNetworkIteration + iterationOffset;
        end
        continue;
    end
    firstValues = reshape(firstInfo.(fieldName), 1, []);
    secondValues = reshape(secondInfo.(fieldName), 1, []);
    switch fieldName
        case 'Iteration'
            secondValues = secondValues + iterationOffset;
        case 'Epoch'
            secondValues = secondValues + epochOffset;
        case 'TimeElapsed'
            secondValues = secondValues + timeOffset;
    end
    info.(fieldName) = [firstValues, secondValues];
end
end

% -------------------------------------------------------------------------------------
function out = iReadValidationPatch(observationIndex, valModelFiles, valObservationSeeds, valPatchOpt)
% read one validation observation, cropping the same window on every evaluation
%
% arrayDatastore hands the index over wrapped in a cell; a seed of 0 means the user asked
% for unseeded sampling, in which case no patchSeed is set and readInstancePatch falls back
% to the global stream (the pre-existing behaviour).

if iscell(observationIndex); observationIndex = observationIndex{1}; end
if valObservationSeeds(observationIndex) ~= 0
    valPatchOpt.patchSeed = valObservationSeeds(observationIndex);
end
out = deepmib.readInstancePatch(valModelFiles{observationIndex}, valPatchOpt);
end

function [net, info] = iRecoverNetworkFromCheckpoint(checkpointDir, progressStruct)
% rebuild the network and a minimal training-info struct after an Emergency brake
%
% trainSOLOV2 never returns when the OutputFcn throws, so the network is taken from the
% newest checkpoint file written by images.dltrain.internal.CheckpointSaver and the loss
% curve is taken from the points the custom progress window has already collected. The
% recovered network is therefore up to CheckpointFrequency epochs behind the point where
% the user pressed the button.

net = [];
info = struct();

checkpointFiles = dir(fullfile(checkpointDir, 'net_checkpoint__*.mat'));
if isempty(checkpointFiles)     % fall back to any checkpoint-looking file
    checkpointFiles = dir(fullfile(checkpointDir, '*.mat'));
end
if isempty(checkpointFiles); return; end

[~, newestIndex] = max([checkpointFiles.datenum]);
checkpointFilename = fullfile(checkpointFiles(newestIndex).folder, checkpointFiles(newestIndex).name);
loadedCheckpoint = load(checkpointFilename, 'net', '-mat');
if ~isfield(loadedCheckpoint, 'net'); return; end
net = loadedCheckpoint.net;

% reuse the decimated curve already held by the progress window; it is the only record of
% the run left once trainSOLOV2 has been aborted
if isfield(progressStruct, 'TrainXvecIndex') && progressStruct.TrainXvecIndex > 1
    lastPoint = progressStruct.TrainXvecIndex - 1;
    info.Iteration = reshape(progressStruct.TrainXvec(1:lastPoint), 1, []);
    info.TrainingLoss = reshape(progressStruct.TrainLoss(1:lastPoint), 1, []);
else
    info.Iteration = [];
    info.TrainingLoss = [];
end
if isfield(progressStruct, 'ValidationXvecIndex') && progressStruct.ValidationXvecIndex > 1
    lastValidationPoint = progressStruct.ValidationXvecIndex - 1;
    info.ValidationLoss = reshape(progressStruct.ValidationLoss(1:lastValidationPoint), 1, []);
end
info.OutputNetworkIteration = [];   % no "picked iteration" marker for a recovered network

fprintf('DeepMIB: Emergency brake, the network was restored from "%s"\n', checkpointFilename);
end

function value = iInfoLastValue(info, fieldName)
% return the last element of an info field, or NaN when the field is absent
% (SOLOv2 training info does not include accuracy/validation metrics)
if isfield(info, fieldName) && ~isempty(info.(fieldName))
    value = info.(fieldName)(end);
else
    value = NaN;
end
end

