function startTrainingStarDist(obj)
% STARTTRAININGSTARDIST - Train a StarDist network of the 2D Instance workflow.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.startTrainingStarDist()
%
% Trains the native MATLAB StarDist 2D implementation of the ``deepmib.stardist`` package with
% ``trainnet``, from the instance label maps written by the 2D Instance preprocessing
% (``TrainLabels`` / ``ValidationLabels``, see deepmib.saveInstanceLabelsParFor) and the images
% in ``TrainImages`` / ``ValidationImages``.
%
% **Network.** With "Starting weights" set to a pretrained StarDist model (``2D_versatile_fluo``)
% the converted model is loaded with deepmib.stardist.loadPretrained (downloaded into
% ``preferences.ExternalDirs.DeepMIBDir`` on first use) and fine-tuned; its rays, grid and
% channel count are fixed by the model, and the number of channels in "Input patch size" must
% match it. With ``'None (random)'`` a fresh network is built with the rays and grid of
% ``obj.StarDistOpt``. When the network file already exists, training can continue from it
% instead, keeping its rays and grid. The input layer takes the height and width of "Input patch
% size", which must be divisible by ``2^unetDepth * grid`` (16 for the pretrained models).
%
% **Data pipeline**, per observation (a datastore of the label files replicated "Patches per
% image" times, so each image yields that many random patches per epoch):
%
% 1. deepmib.readInstancePatch in ``'labelMap'`` mode crops a patch of the image and of the
%    label map; 90% of the patches (``config.trainForegroundOnly``) are placed on an object.
%    With augmentation it reads a margin of image around the patch
%    (deepmib.instanceAugmentationMargin);
% 2. deepmib.augmentInstanceData2D applies the enabled 2D augmentations, geometric ones to the
%    label map as well (nearest interpolation), and crops the margin, so rotated, scaled or
%    sheared patches hold real image instead of ``FillValue``;
% 3. the patch is normalised with the percentiles of its **whole** image (StarDist normalises
%    images, not patches), and deepmib.stardist.computeTargets computes the probability and
%    ray-distance targets from the augmented label map.
%
% With "Preview image patches" (Options tab, custom progress window) a fraction of the augmented
% training patches, before normalisation, is shown in the progress window with its label map in
% random colours. Validation patches are not shown.
%
% Validation crops the same windows at every evaluation when "Validation seed" is non-zero
% (one fixed seed per observation, as the SOLOv2 workflow does) and is never augmented.
%
% **Training** uses ``trainnet`` with deepmib.stardist.lossFunction and the training options of
% preprareTrainingOptions (without the accuracy metric), so the MIB progress window, "Stop
% training" and checkpoints behave as in the semantic workflows.
%
% **Thresholds.** When ``obj.StarDistOpt.OptimizeThresholds`` is set and validation images
% exist, deepmib.stardist.optimizeThresholds tunes the probability and NMS thresholds on the
% whole validation images after training (cancelable; on cancel the thresholds of the starting
% model, or the StarDist defaults 0.5 / 0.4, are kept). They are stored in the network file.
%
% **Network file** (``BatchOpt.NetworkFilename``): the usual DeepMIB variables plus
% ``StarDistConfig`` (the deepmib.stardist.defaultConfig struct of the trained network,
% including ``probThresh``, ``nmsThresh`` and ``pretrainedModel``) and ``StarDistOpt``, written
% by :func:`saveStarDistNetwork`. A pretrained model can also be used without training, see
% :func:`createStarDistFromPretrained`.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)

global mibDeepStopTraining
global mibDeepTrainingProgressStruct

if obj.mibController.matlabVersion < 24.1
    utils.dlgs.showErrorDialog(obj.view.gui, 'StarDist training requires MATLAB R2024a or newer (trainnet)', 'StarDist');
    return;
end
obj.TrainEngine = 'trainnet';

% trainnet leaves its loop as soon as the OutputFcn requests a stop, so none of the
% dltrain-specific stop handling of the SOLOv2 workflow applies
mibDeepTrainingProgressStruct = struct();
mibDeepTrainingProgressStruct.emergencyBrake = false;
mibDeepTrainingProgressStruct.dltrainBasedTrainer = false;
mibDeepTrainingProgressStruct.CheckpointPath = '';
mibDeepTrainingProgressStruct.spinDownActive = false;

msg = sprintf('You are going to start training of a StarDist network!\n\nConfirm that the preprocessed instance labels and the images are located under\n\n%s\n\n%s\n%s\n%s\n%s', ...
    obj.BatchOpt.OriginalTrainingImagesDir, '- TrainImages', '- TrainLabels', '- ValidationImages', '- ValidationLabels');
selection = uiconfirm(obj.view.gui, msg, 'StarDist training', ...
    'Options', {'Confirm', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'warning');
if strcmp(selection, 'Cancel'); return; end

obj.selectGPUDevice();

%% Patch size
inputPatchSize = str2num(obj.BatchOpt.T_InputPatchSize); %#ok<ST2NM>
if numel(inputPatchSize) ~= 4
    localMessage(obj, 'Wrong patch size', ...
        sprintf('Provide the "Input patch size" as 4 numbers: height, width, depth, colors\n\nFor example "256 256 1 1" for single-channel images'));
    return;
end
if inputPatchSize(3) > 1
    inputPatchSize(3) = 1;
    obj.BatchOpt.T_InputPatchSize = num2str(inputPatchSize);
    obj.view.handles.T_InputPatchSize.Value = obj.BatchOpt.T_InputPatchSize;
end
if inputPatchSize(1) ~= inputPatchSize(2) && obj.BatchOpt.T_augmentation && obj.AugOpt2D.Rotation90.Enable
    localMessage(obj, 'Rotation90 is not available', ...
        sprintf('Rotation augmentations are only implemented for square input patches.\n\nUse a square "Input patch size" or set the probability of Rotation90 to 0'));
    return;
end

%% Files
trainLabelsDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'TrainLabels');
trainImagesDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'TrainImages');
valLabelsDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationLabels');
valImagesDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationImages');
trainList = dir(fullfile(trainLabelsDir, '*.mat'));
if isempty(trainList)
    localMessage(obj, 'Missing files', sprintf(['Preprocessed label files (*.mat) are missing in\n\n%s\n\n' ...
        'Preprocess the labels and split the data for training/validation first'], trainLabelsDir));
    return;
end
valList = dir(fullfile(valLabelsDir, '*.mat'));
patchesPerImage = obj.BatchOpt.T_PatchesPerImage{1};
totalObservations = numel(trainList) * patchesPerImage;
if totalObservations < obj.BatchOpt.T_MiniBatchSize{1}
    localMessage(obj, 'Wrong configuration', sprintf(['The mini-batch size (%d) should not exceed\n' ...
        'Patches per image (%d) x number of images (%d) = %d'], ...
        obj.BatchOpt.T_MiniBatchSize{1}, patchesPerImage, numel(trainList), totalObservations));
    return;
end

%% Starting network and configuration
progressDlg = uiprogressdlg(obj.view.gui, 'Message', 'Preparing the network...', ...
    'Title', 'StarDist training', 'Cancelable', 'on');
cleanupDlg = onCleanup(@() localDeleteDialog(progressDlg));

startFrom = 'new';
if isfile(obj.BatchOpt.NetworkFilename)
    [~, netName, netExt] = fileparts(obj.BatchOpt.NetworkFilename);
    answer = uiconfirm(obj.view.gui, sprintf('The network file "%s" already exists.\n\nStart a new training (the file is overwritten when training finishes) or continue training the existing network?', ...
        [netName netExt]), 'Network exists', 'Options', {'Start new training', 'Continue training', 'Cancel'}, ...
        'DefaultOption', 1, 'CancelOption', 3);
    switch answer
        case 'Cancel'; return;
        case 'Continue training'; startFrom = 'continue';
    end
end

starDistOpt = obj.StarDistOpt;
pretrainedModel = 'none';
try
    if strcmp(startFrom, 'continue')
        saved = load(obj.BatchOpt.NetworkFilename, '-mat', 'net', 'StarDistConfig');
        if ~isfield(saved, 'StarDistConfig')
            localMessage(obj, 'Not a StarDist network', sprintf('%s was not trained with the StarDist architecture', obj.BatchOpt.NetworkFilename));
            return;
        end
        config = saved.StarDistConfig;
        weights = localWeightsFromNetwork(saved.net);
        if isfield(config, 'pretrainedModel'); pretrainedModel = config.pretrainedModel; end
    elseif strcmp(obj.BatchOpt.T_StartingWeights{1}, 'None (random)')
        config = deepmib.stardist.defaultConfig(struct('nRays', starDistOpt.NRays, 'grid', [1 1] * starDistOpt.Grid));
        weights = struct();
    else
        pretrainedModel = obj.BatchOpt.T_StartingWeights{1};
        [model, cancelled] = deepmib.stardist.loadPretrained(pretrainedModel, ...
            obj.mibModel.preferences.ExternalDirs.DeepMIBDir, progressDlg);
        if cancelled; return; end
        progressDlg.Cancelable = 'on';
        progressDlg.Indeterminate = 'off';
        config = model.config;
        weights = localWeightsFromNetwork(model.net);
    end
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'StarDist network');
    return;
end
config.patchSize = inputPatchSize(1:2);
config.normalizePercentiles = starDistOpt.NormalizePercentiles;
config.pretrainedModel = pretrainedModel;
config = deepmib.stardist.defaultConfig(config);

if config.nChannelIn ~= inputPatchSize(4)
    if strcmp(startFrom, 'new') && strcmp(pretrainedModel, 'none')
        config.nChannelIn = inputPatchSize(4);     % a fresh network takes the channel count of the patch
    else
        localMessage(obj, 'Wrong number of colors', sprintf(['The network expects %d color channel(s), while "Input patch size" has %d.\n\n' ...
            'Set the fourth number of "Input patch size" to %d'], config.nChannelIn, inputPatchSize(4), config.nChannelIn));
        return;
    end
end
divisor = 2^config.unetDepth * config.grid;
if any(mod(config.patchSize, divisor) ~= 0)
    nearestBelow = max(divisor, floor(config.patchSize ./ divisor) .* divisor);
    localMessage(obj, 'Wrong patch size', sprintf(['The height and the width of "Input patch size" must be multiples of %d for this StarDist network.\n\n' ...
        'Current: %d x %d, for example use %d x %d'], divisor(1), config.patchSize, nearestBelow));
    return;
end

%% Datastores
if progressDlg.CancelRequested; return; end
progressDlg.Message = 'Creating datastores...';
progressDlg.Value = 0.2;

if obj.BatchOpt.T_RandomGeneratorSeed{1} == 0
    rng('shuffle');
else
    rng(obj.BatchOpt.T_RandomGeneratorSeed{1}, 'twister');
end

loadImageOpt.mibBioformatsCheck = obj.BatchOpt.BioformatsTraining;
loadImageOpt.BioFormatsIndices = obj.BatchOpt.BioformatsTrainingIndex{1};
loadImageOpt.Workflow = obj.BatchOpt.Workflow{1};

patchOpt.imageDir = trainImagesDir;
patchOpt.patchSize = config.patchSize;
patchOpt.objectFraction = config.trainForegroundOnly;
patchOpt.minObjectArea = 0;
patchOpt.getImageOptions = loadImageOpt;
patchOpt.outputFormat = 'labelMap';
patchOpt.normalizePercentiles = config.normalizePercentiles;

% read one patch now: a channel mismatch or an unreadable image is reported here with a
% clear message instead of from inside trainnet
try
    firstPatch = deepmib.readInstancePatch(fullfile(trainList(1).folder, trainList(1).name), patchOpt);
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Training images');
    return;
end
if size(firstPatch{1}, 3) ~= config.nChannelIn
    localMessage(obj, 'Wrong number of colors', sprintf(['The training images have %d color channel(s), the network expects %d.\n\n' ...
        'Use images with %d channel(s), or train a new network from random weights'], ...
        size(firstPatch{1}, 3), config.nChannelIn, config.nChannelIn));
    return;
end

trainFiles = arrayfun(@(f) fullfile(f.folder, f.name), trainList, 'UniformOutput', false);
trainFiles = repmat(trainFiles(:), [patchesPerImage, 1]);
% the training patches are read with a margin of real image that the geometric augmentations
% rotate, scale or shear into the patch before it is cropped back (no fill inside the image);
% validation patches are not augmented and keep patchOpt
trainPatchOpt = patchOpt;
if obj.BatchOpt.T_augmentation
    status = obj.setAugFuncHandles('2D');
    if status == 0; return; end
    augOpt.AugOpt2D = obj.AugOpt2D;
    augOpt.Aug2DFuncNames = obj.Aug2DFuncNames;
    augOpt.Aug2DFuncProbability = obj.Aug2DFuncProbability;
    augOpt.patchSize = config.patchSize;
    trainPatchOpt.margin = deepmib.instanceAugmentationMargin(augOpt, config.patchSize);
    trainPatchOpt.fillValue = obj.AugOpt2D.FillValue;
end
trainDS = fileDatastore(trainFiles, 'ReadFcn', @(fn) deepmib.readInstancePatch(fn, trainPatchOpt));
if obj.BatchOpt.T_augmentation
    trainDS = transform(trainDS, @(dataIn) deepmib.augmentInstanceData2D(dataIn, augOpt));
end
previewOpt.enabled = obj.BatchOpt.O_CustomTrainingProgressWindow && obj.BatchOpt.O_PreviewImagePatches;
% the semantic workflows draw at this rate per mini-batch (their augmentation receives the
% whole batch), this transform sees one patch at a time
previewOpt.fraction = obj.BatchOpt.O_FractionOfPreviewPatches{1} / obj.BatchOpt.T_MiniBatchSize{1};
trainDS = transform(trainDS, @(dataIn) localTrainingPair(dataIn, config, previewOpt));

valDS = [];
if ~isempty(valList)
    valPatchOpt = patchOpt;
    valPatchOpt.imageDir = valImagesDir;
    valFiles = arrayfun(@(f) fullfile(f.folder, f.name), valList, 'UniformOutput', false);
    valFiles = repmat(valFiles(:), [patchesPerImage, 1]);
    numValObservations = numel(valFiles);
    % fixed windows at every evaluation when the validation seed is non-zero, so the
    % validation loss is comparable between evaluations (same convention as SOLOv2)
    baseSeed = obj.BatchOpt.T_RandomGeneratorValSeed{1};
    valSeeds = zeros(numValObservations, 1);
    if baseSeed ~= 0
        valSeeds = mod(baseSeed * 100003 + (1:numValObservations)', 2^32 - 2) + 1;
    end
    valDS = transform(arrayDatastore((1:numValObservations)', 'ReadSize', 1), ...
        @(index) localValidationPair(index, valFiles, valSeeds, valPatchOpt, config));
end

%% Network
if progressDlg.CancelRequested; return; end
progressDlg.Message = 'Creating the network...';
progressDlg.Value = 0.4;
try
    net = deepmib.stardist.createNetwork(config, weights);
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'StarDist network');
    return;
end

%% Training options
mibDeepTrainingProgressStruct.iterPerEpoch = floor(totalObservations / obj.BatchOpt.T_MiniBatchSize{1});
mibDeepTrainingProgressStruct.maxNoIter = mibDeepTrainingProgressStruct.iterPerEpoch * obj.TrainingOpt.MaxEpochs;
obj.wb = progressDlg;   % preprareTrainingOptions deletes obj.wb when it fails
TrainingOptions = obj.preprareTrainingOptions(valDS);
if isempty(TrainingOptions) || isstruct(TrainingOptions); return; end
TrainingOptions.TargetDataFormats = "SSCB";

% config file, written before training like the other workflows
[configPath, configFn] = fileparts(obj.BatchOpt.NetworkFilename);
obj.saveConfig(fullfile(configPath, [configFn '.mibCfg']));
if progressDlg.CancelRequested; return; end
delete(progressDlg);

%% Train
obj.view.handles.TrainButton.Text = 'Stop training';
obj.view.handles.TrainButton.BackgroundColor = utils.themeColors(obj.view.gui).dialogAction;
drawnow;
mibDeepStopTraining = false;
lossFcn = @(Y, T) deepmib.stardist.lossFunction(Y, T, config);
try
    [net, info] = trainnet(trainDS, net, lossFcn, TrainingOptions);
catch err
    localResetTrainButton(obj);
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'StarDist training error');
    return;
end

localMarkPickedIteration(info);

%% Thresholds
thresholdsReport = 'not tuned';
if starDistOpt.OptimizeThresholds && ~isempty(valList)
    [config, thresholdsReport] = localOptimizeThresholds(obj, net, config, valList, valImagesDir, loadImageOpt);
end

%% Save
try
    obj.saveStarDistNetwork(obj.BatchOpt.NetworkFilename, net, config, inputPatchSize);
catch err
    localResetTrainButton(obj);
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Saving the network failed');
    return;
end

if obj.BatchOpt.T_ExportTrainingPlots
    localExportTrainingHistory(obj, info);
end

if isfield(mibDeepTrainingProgressStruct, 'useCustomProgressPlot') && mibDeepTrainingProgressStruct.useCustomProgressPlot && ...
        isfield(mibDeepTrainingProgressStruct, 'StopTrainingButton') && isvalid(mibDeepTrainingProgressStruct.StopTrainingButton)
    mibDeepTrainingProgressStruct.StopTrainingButton.BackgroundColor = [0 1 0];
    mibDeepTrainingProgressStruct.StopTrainingButton.Text = 'Finished!!!';
end

obj.mibModel.preferences.Users.Tiers.numberOfTrainedDeepNetworks = obj.mibModel.preferences.Users.Tiers.numberOfTrainedDeepNetworks + 1;
notify(obj.mibModel, 'UpdateUserScore', core.ToggleEventData(10));
mibDeepTrainingProgressStruct = struct();
localResetTrainButton(obj);

[~, netName, netExt] = fileparts(obj.BatchOpt.NetworkFilename);
localMessage(obj, 'StarDist training finished', sprintf(['The network was saved to\n%s\n\n' ...
    'Rays: %d, grid: %d x %d, starting weights: %s\n' ...
    'Detection thresholds: probability %.3f, NMS overlap %.2f (%s)'], ...
    [netName netExt], config.nRays, config.grid, pretrainedModel, config.probThresh, config.nmsThresh, thresholdsReport), ...
    'puffin_info');
end

% -------------------------------------------------------------------------------------
function out = localTrainingPair(dataIn, config, previewOpt)
% {image, labelMap, normValues} -> {normalised image, targets}; the whole-image percentiles
% come from deepmib.readInstancePatch, the formula is that of deepmib.stardist.normalizeImage.
% With previewOpt (training only) a fraction of the augmented patches is shown in the MIB
% training progress window, as augmentAndCrop2dPatchMultiGPU does for the semantic workflows
if nargin > 2 && previewOpt.enabled && rand < previewOpt.fraction
    localPreviewPatch(dataIn{1}, dataIn{2});
end
image = single(dataIn{1});
normValues = single(dataIn{3});
for channelId = 1:size(image, 3)
    image(:, :, channelId) = (image(:, :, channelId) - normValues(1, channelId)) / ...
        (normValues(2, channelId) - normValues(1, channelId) + single(1e-20));
end
out = {image, deepmib.stardist.computeTargets(dataIn{2}, config)};
end

function localPreviewPatch(patchImage, labelMap)
% augmented image patch and its instance label map (random colours) in the progress window
global mibDeepTrainingProgressStruct
if ~isfield(mibDeepTrainingProgressStruct, 'UIFigure') || ~isvalid(mibDeepTrainingProgressStruct.UIFigure); return; end
if size(patchImage, 3) == 2
    patchImage(:, :, 3) = 0;
    patchImage = uint8(double(patchImage) * (255 / max(1, double(max(patchImage(:))))));
end
image(mibDeepTrainingProgressStruct.imgPatch, patchImage, 'CDataMapping', 'scaled');
image(mibDeepTrainingProgressStruct.labelPatch, label2rgb(labelMap, 'lines', 'k', 'shuffle'));
drawnow;
end

function out = localValidationPair(index, valFiles, valSeeds, valPatchOpt, config)
% one validation observation; a non-zero seed crops the same window at every evaluation
if iscell(index); index = index{1}; end
patchOpt = valPatchOpt;
if valSeeds(index) ~= 0
    patchOpt.patchSeed = valSeeds(index);
end
out = localTrainingPair(deepmib.readInstancePatch(valFiles{index}, patchOpt), config);
end

function weights = localWeightsFromNetwork(net)
% learnables of a StarDist dlnetwork as weights.(layerName).kernel / .bias, the form that
% deepmib.stardist.createNetwork loads, so a network can be rebuilt for another patch size
weights = struct();
learnables = net.Learnables;
for rowId = 1:height(learnables)
    value = gather(extractdata(learnables.Value{rowId}));
    switch learnables.Parameter{rowId}
        case 'Weights'
            weights.(learnables.Layer{rowId}).kernel = value;
        case 'Bias'
            weights.(learnables.Layer{rowId}).bias = value;
    end
end
end

function [config, report] = localOptimizeThresholds(obj, net, config, valList, valImagesDir, loadImageOpt)
% tune probThresh / nmsThresh on the whole validation images; keeps config on cancel
progressDlg = uiprogressdlg(obj.view.gui, 'Message', 'Loading validation images...', ...
    'Title', 'Tuning StarDist thresholds', 'Cancelable', 'on');
cleanupDlg = onCleanup(@() localDeleteDialog(progressDlg));
images = cell(numel(valList), 1);
labels = cell(numel(valList), 1);
for fileId = 1:numel(valList)
    if progressDlg.CancelRequested; report = 'tuning cancelled, thresholds of the starting network kept'; return; end
    progressDlg.Value = 0.1 * fileId / numel(valList);
    data = load(fullfile(valList(fileId).folder, valList(fileId).name));
    image = squeeze(deepmib.storeLoadImages(fullfile(valImagesDir, data.imageFilename), loadImageOpt));
    images{fileId} = deepmib.stardist.normalizeImage(image, config.normalizePercentiles);
    labels{fileId} = data.instanceLabelMap;
end
progressDlg.Message = sprintf('Tuning the detection thresholds on %d validation image(s)...', numel(valList));
executionEnvironment = 'auto';
if strcmp(obj.view.Figure.GPUDropDown.Value, 'CPU only'); executionEnvironment = 'cpu'; end
[probThresh, nmsThresh, accuracy, cancelled] = deepmib.stardist.optimizeThresholds(net, images, labels, config, ...
    struct('progressDlg', progressDlg, 'executionEnvironment', executionEnvironment));
if cancelled
    report = 'tuning cancelled, thresholds of the starting network kept';
    return;
end
config.probThresh = probThresh;
config.nmsThresh = nmsThresh;
report = sprintf('tuned on the validation images, accuracy %.3f', accuracy);
end

function localMarkPickedIteration(info)
% green line at the iteration of the returned network in the MIB progress window
global mibDeepTrainingProgressStruct
if ~isfield(mibDeepTrainingProgressStruct, 'useCustomProgressPlot') || ~mibDeepTrainingProgressStruct.useCustomProgressPlot || ...
        ~isfield(mibDeepTrainingProgressStruct, 'UILossAxes') || ~isvalid(mibDeepTrainingProgressStruct.UILossAxes) || ...
        ~isfield(info, 'OutputNetworkIteration') || isempty(info.OutputNetworkIteration)
    return;
end
axesHandle = mibDeepTrainingProgressStruct.UILossAxes;
hold(axesHandle, 'on');
pickedLine = plot(axesHandle, [info.OutputNetworkIteration, info.OutputNetworkIteration], axesHandle.YLim, '-');
pickedLine.Color = [0 .7 0];
axesHandle.Legend.String = {'Training', 'Validation', sprintf('Picked iteration: %d', info.OutputNetworkIteration)};
hold(axesHandle, 'off');
end

function localExportTrainingHistory(obj, info)
% training history tables to Results\ScoreNetwork, as the semantic trainnet path does
global mibDeepTrainingProgressStruct
scoreDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork');
if ~isfolder(scoreDir); mkdir(scoreDir); end
datetimeTag = char(datetime('now', 'format', 'yyMMddHHmm'));
[~, fnTemplate] = fileparts(obj.BatchOpt.NetworkFilename);
fnTemplate = [datetimeTag, '_', fnTemplate];
save(fullfile(scoreDir, [fnTemplate '.score']), 'info', '-mat', '-v7.3');
fieldNames = fieldnames(info);
for fieldId = 1:numel(fieldNames)
    if istable(info.(fieldNames{fieldId})) && ~isempty(info.(fieldNames{fieldId}))
        writetable(info.(fieldNames{fieldId}), fullfile(scoreDir, [fnTemplate '_' fieldNames{fieldId} '.csv']));
    end
end
if isfield(mibDeepTrainingProgressStruct, 'UIFigure') && isvalid(mibDeepTrainingProgressStruct.UIFigure)
    try
        deepmib.saveTrainingPlot([], [], mibDeepTrainingProgressStruct, fullfile(scoreDir, [datetimeTag '_Train_' fnTemplate '.png']));
        savefig(mibDeepTrainingProgressStruct.UIFigure, fullfile(scoreDir, [datetimeTag '_Train_' fnTemplate '.fig']));
    catch
        % the snapshot is a convenience; the history tables above are the record
    end
end
end

function localMessage(obj, title, text, icon)
% message box; 'puffin_warning' unless another icon is given. The height is computed from the
% wrapped lines of the text, because the automatic estimate of inputUniversalDlg counts the
% line breaks of plain text twice and makes the window far too tall
if nargin < 4; icon = 'puffin_warning'; end
msgOpt.MsgBoxOnly = true;
msgOpt.Icon = icon;
msgOpt.HeaderLines = 1;
msgOpt.WindowWidth = 520;
charsPerLine = floor((msgOpt.WindowWidth - 140) / 7);
textLines = strsplit(text, newline);
wrappedLines = sum(max(1, ceil(cellfun(@numel, textLines) / charsPerLine)));
msgOpt.WindowHeight = min(800, 130 + 20 * wrappedLines);
utils.dlgs.inputUniversalDlg(obj.view.gui, title, {''}, {text}, title, msgOpt);
end

function localResetTrainButton(obj)
obj.view.handles.TrainButton.Text = 'Train';
obj.view.handles.TrainButton.BackgroundColor = utils.themeColors(obj.view.gui).panelBlue;
end

function localDeleteDialog(dialogHandle)
if ~isempty(dialogHandle) && isvalid(dialogHandle); delete(dialogHandle); end
end
