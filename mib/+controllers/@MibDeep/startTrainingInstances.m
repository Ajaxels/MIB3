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
            if obj.BatchOpt.T_SaveProgress
                delete(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', '*.mat'));     % delete all score matlab files
            end
            % make directories for export of the training scores
            if obj.BatchOpt.T_ExportTrainingPlots
                delete(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', '*.csv'));     % delete all csv files
                delete(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', '*.score'));     % delete all score matlab files
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
else
    % make directories for export of the training scores
    if obj.BatchOpt.T_ExportTrainingPlots
        delete(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', '*.csv'));     % delete all csv files
        delete(fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', '*.score'));     % delete all score matlab files
    end
end

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
    if ~isempty(valModelList)
        valPatchOpt = patchOpt;
        valPatchOpt.imageDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationImages');
        valModelFiles = arrayfun(@(f) fullfile(f.folder, f.name), valModelList, 'UniformOutput', false);
        valLabelsDS = fileDatastore(valModelFiles(:), ...
            'ReadFcn', @(fn)deepmib.readInstancePatch(fn, valPatchOpt));
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
    if isempty(valLabelsDS) || numel(valLabelsDS.Files) == 0
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
try
    mibDeepStopTraining = false;

    [net, info] = trainSOLOV2(...
        labelsDS, ...
        lgraph, ...
        TrainingOptions, ...
        'FreezeSubNetwork', 'backbone');
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
            if mibDeepTrainingProgressStruct.useCustomProgressPlot && isfield(mibDeepTrainingProgressStruct, 'StopTrainingButton')
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
            [net, info] = trainSOLOV2(labelsDS, lgraph, TrainingOptions, 'FreezeSubNetwork', 'backbone');
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
if ~emergencyBrakeUsed && isstruct(info) && isfield(info, 'OutputNetworkIteration')
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

if showWaitbarLocal
    obj.wb = uiprogressdlg(obj.view.gui, 'Message', 'Finalizing training...', ...
        'Title', 'Finalize training', 'Cancelable', 'on');
end

if mibDeepTrainingProgressStruct.useCustomProgressPlot && isfield(mibDeepTrainingProgressStruct, 'UILossAxes') && isvalid(mibDeepTrainingProgressStruct.UILossAxes)
    hold(mibDeepTrainingProgressStruct.UILossAxes, 'on');
    % add a vertical line at the selected iteration indicating the picked network.
    % OutputNetworkIteration can be empty (e.g. when training was retried without
    % validation) - skip the marker line in that case to avoid a plot size mismatch
    if isfield(info, 'OutputNetworkIteration') && ~isempty(info.OutputNetworkIteration)
        mibDeepTrainingProgressStruct.hPlot(3) = plot(mibDeepTrainingProgressStruct.UILossAxes, [info.OutputNetworkIteration, info.OutputNetworkIteration], mibDeepTrainingProgressStruct.UILossAxes.YLim, '-');
        mibDeepTrainingProgressStruct.hPlot(3).Color = [0 .7 0];
        mibDeepTrainingProgressStruct.UILossAxes.Legend.String = {'Training'  'Validation'  sprintf('Picked iteration: %d', info.OutputNetworkIteration)};
    end
    % add last point to the plot
    if ~isempty(mibDeepTrainingProgressStruct.hPlot(1).XData) && mibDeepTrainingProgressStruct.hPlot(1).XData(end) < numel(info.TrainingLoss)
        warning('off','MATLAB:gui:array:InvalidArrayShape');
        mibDeepTrainingProgressStruct.hPlot(1).XData = [mibDeepTrainingProgressStruct.hPlot(1).XData, numel(info.TrainingLoss)];
        mibDeepTrainingProgressStruct.hPlot(1).YData = [mibDeepTrainingProgressStruct.hPlot(1).YData, info.TrainingLoss(end)];
        if isfield(info, 'ValidationLoss')
            mibDeepTrainingProgressStruct.hPlot(2).XData = [mibDeepTrainingProgressStruct.hPlot(2).XData numel(info.ValidationLoss)];
            mibDeepTrainingProgressStruct.hPlot(2).YData = [mibDeepTrainingProgressStruct.hPlot(2).YData info.ValidationLoss(end)];
        end
        warning('on','MATLAB:gui:array:InvalidArrayShape');
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
save(obj.BatchOpt.NetworkFilename, 'net', 'TrainingOptStruct', 'AugOpt2DStruct', 'AugOpt3DStruct', 'InputLayerOpt', ...
    'ActivationLayerOpt', 'SegmentationLayerOpt', 'DynamicMaskOpt', 'OverlapInstancesOpt', ...
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
end
if showWaitbarLocal
    obj.wb.Value = 1;
    delete(obj.wb);
end

if mibDeepTrainingProgressStruct.useCustomProgressPlot
    mibDeepTrainingProgressStruct.StopTrainingButton.BackgroundColor = [0 1 0];
    mibDeepTrainingProgressStruct.StopTrainingButton.Text = 'Finished!!!';
end

if obj.SendReports.T_SendReports && numel(info.TrainingLoss) >= mibDeepTrainingProgressStruct.maxNoIter && ...
        obj.SendReports.sendWhenFinished && ...
        mibDeepTrainingProgressStruct.sendNextReportAtEpoch ~= -1
    [~, fn] = fileparts(obj.BatchOpt.NetworkFilename);
    % SOLOv2 info has fewer fields than semantic training (no accuracy/validation
    % metrics); fetch each metric defensively so the report never errors
    infoVal = @(fieldName) iInfoLastValue(info, fieldName);
    if mibDeepTrainingProgressStruct.useCustomProgressPlot
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

