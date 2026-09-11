function previewValidationPatches(obj)
% PREVIEWVALIDATIONPATCHES - show or export the patches that will be used for validation.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.previewValidationPatches()
%
% The validation patches are cropped at random positions, and which positions are used is
% decided by ``BatchOpt.T_RandomGeneratorValSeed``. This inspects the patches that seed
% produces, so a seed can be judged before spending a training run on it - a draw that
% happens to land mostly on background makes the validation loss a poor guide, and
% ``OutputNetwork: best-validation-loss`` then selects against a set that does not represent
% the data.
%
% A dialog offers two ways to look:
%   - **collage** - a montage of the first ``PatchPreviewOpt.noImages`` patches, scaled down
%     to ``PatchPreviewOpt.imageSize``. The appearance settings are shared with the
%     augmentation preview, so changing them there changes both.
%   - **export** - every validation patch written to ``ScoreNetwork/ValidationPatches`` at
%     **full resolution**, each as an image plus a MIB model holding its labels, so the pair
%     can be opened and inspected in MIB.
%
% Behaviour per workflow, matching what training actually does:
%   - **2D / 2.5D / 3D Semantic** - patches from a ``randomPatchExtractionDatastore`` over
%     the validation images and labels, drawn under the validation seed.
%   - **2D Instance** - patches from :func:`deepmib.readInstancePatch` using the same
%     per-observation seeds as :func:`startTrainingInstances`, so these are literally the
%     patches that will be validated on.
%   - **2D Patch-wise** - validation uses whole images from a fixed file list and never
%     moves, so there is nothing for a seed to change.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%

if strcmp(obj.BatchOpt.Workflow{1}, '2D Patch-wise')
    mgsOpt.MsgBoxOnly = true;
    mgsOpt.Icon = 'puffin_info';
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        sprintf(['The 2D Patch-wise workflow validates on whole images taken from a fixed file list,\n' ...
        'so the validation set never changes and the validation seed has no effect on it.\n\n' ...
        'There is nothing to preview here.']), {}, {}, 'Nothing to preview', mgsOpt);
    return;
end

validationSeed = obj.BatchOpt.T_RandomGeneratorValSeed{1};
patchesPerImage = obj.BatchOpt.T_PatchesPerImage{1};

% how many validation observations there are, so the dialog can state it
noValidationImages = localCountValidationImages(obj);
if noValidationImages == 0
    mgsOpt.MsgBoxOnly = true;
    mgsOpt.Icon = 'puffin_warning';
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        sprintf(['No validation images were found.\n\nCheck the "ValidationImages" folder under\n\n%s\n\n' ...
        'or set "Fraction of images for validation" and split the data first.'], ...
        obj.BatchOpt.OriginalTrainingImagesDir), {}, {}, 'No validation images', mgsOpt);
    return;
end
noObservations = noValidationImages * patchesPerImage;

exportDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'ScoreNetwork', 'ValidationPatches');
if validationSeed == 0
    seedNote = 'seed 0: the patches are re-drawn at every evaluation, so this is one example draw';
else
    seedNote = sprintf('seed %d: these exact patches are used at every evaluation', validationSeed);
end
questionText = sprintf([ ...
    'The validation set holds %d patches (%d patches per image x %d validation images).\n' ...
    'Validation %s\n\n' ...
    ' - Show collage: montage of the first %d patches, scaled to %d px, labels %s' ...
    '    (from the preview settings shared with the augmentation dialog)\n' ...
    ' - Export to disk: all %d patches at full resolution, image + MIB model for each, into\n' ...
    '   %s'], ...
    noObservations, patchesPerImage, noValidationImages, seedNote, ...
    obj.PatchPreviewOpt.noImages, obj.PatchPreviewOpt.imageSize, ...
    string(matlab.lang.OnOffSwitchState(obj.PatchPreviewOpt.labelShow)), ...
    noObservations, exportDir);

selection = uiconfirm(obj.view.gui, questionText, 'Preview validation patches', ...
    'Options', {'Show collage', 'Export to disk', 'Cancel'}, ...
    'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'question');
if strcmp(selection, 'Cancel'); return; end

exportMode = strcmp(selection, 'Export to disk');
if exportMode
    maxPatches = Inf;       % the point of exporting is to get the whole set
else
    maxPatches = obj.PatchPreviewOpt.noImages;
end

% cropping a large validation set takes a while, especially when every patch has to be
% loaded from a whole-slide image, so the dialog can be cancelled and the collectors below
% check for it on every observation
wb = uiprogressdlg(obj.view.gui, 'Message', 'Collecting validation patches...', ...
    'Title', 'Validation patches', 'Indeterminate', 'on', 'Cancelable', 'on');

try
    if strcmp(obj.BatchOpt.Workflow{1}, '2D Instance')
        patchSet = localCollectInstancePatches(obj, validationSeed, patchesPerImage, maxPatches, wb);
    else
        patchSet = localCollectSemanticPatches(obj, validationSeed, patchesPerImage, maxPatches, wb);
    end
catch err
    delete(wb);
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Could not collect validation patches');
    return;
end

if wb.CancelRequested
    delete(wb);
    fprintf('DeepMIB: collecting the validation patches was cancelled\n');
    return;
end

if isempty(patchSet)
    delete(wb);
    mgsOpt.MsgBoxOnly = true;
    mgsOpt.Icon = 'puffin_warning';
    utils.dlgs.inputUniversalDlg(obj.view.gui, 'No validation patches could be extracted', ...
        {}, {}, 'Nothing to show', mgsOpt);
    return;
end

if exportMode
    wb.Indeterminate = 'off';
    wb.Value = 0;
    wb.Message = sprintf('Writing %d patches to disk...', numel(patchSet));
    try
        noExported = localExportPatches(obj, patchSet, exportDir, wb);
    catch err
        delete(wb);
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Could not export the validation patches');
        return;
    end
    cancelled = wb.CancelRequested;
    delete(wb);

    mgsOpt.MsgBoxOnly = true;
    mgsOpt.HeaderLines = 1;
    mgsOpt.WindowHeight = 180;
    if cancelled
        mgsOpt.Icon = 'puffin_warning';
        headerText = sprintf('Export was cancelled after %d of %d patches', noExported, numel(patchSet));
        textStr = sprintf('The files written so far are kept in\n%s', exportDir);
        dlgTitle = 'Export cancelled';
    else
        mgsOpt.Icon = 'puffin_info';
        headerText = sprintf('%d validation patches were exported at full resolution', noExported);
        textStr = sprintf('Destination:\n%s', exportDir);
        dlgTitle = 'Export finished';
    end
    utils.dlgs.inputUniversalDlg(obj.view.gui, headerText, {}, {textStr}, dlgTitle, mgsOpt);
    fprintf('DeepMIB: %d validation patches exported to\n  %s\n', noExported, exportDir);
    return;
end

localShowCollage(obj, patchSet, validationSeed);
delete(wb);
end

% -------------------------------------------------------------------------------------
function localShowCollage(obj, patchSet, validationSeed)
% montage of the collected patches, styled like the augmentation preview

collage = cell(numel(patchSet), 1);
for patchId = 1:numel(patchSet)
    patchImage = patchSet(patchId).image;
    largestSide = max(size(patchImage, 1), size(patchImage, 2));
    if largestSide > obj.PatchPreviewOpt.imageSize
        patchImage = imresize(patchImage, obj.PatchPreviewOpt.imageSize/largestSide);
    end
    if size(patchImage, 3) == 2     % pad a 2-channel image to RGB, as the augmentation preview does
        patchImage(:,:,3) = zeros([size(patchImage, 1), size(patchImage, 2)], class(patchImage));
    end
    if obj.PatchPreviewOpt.labelShow
        patchImage = insertText(patchImage, [1 1], patchSet(patchId).caption, ...
            'FontSize', obj.PatchPreviewOpt.labelSize, ...
            'TextColor', obj.PatchPreviewOpt.labelColor, ...
            'BoxColor', obj.PatchPreviewOpt.labelBgColor, ...
            'BoxOpacity', obj.PatchPreviewOpt.labelBgOpacity);
    end
    collage{patchId} = patchImage;
end

hFig = figure('Name', 'Validation patches', 'NumberTitle', 'off');
montage(collage, 'BorderSize', 5);
if validationSeed == 0
    seedText = 'Validation seed 0 - patches are re-drawn every evaluation, this is one example draw';
else
    seedText = sprintf('Validation seed %d - these exact patches are used at every evaluation', validationSeed);
end
title(sprintf('%s (showing %d)', seedText, numel(collage)), ...
    'Interpreter', 'none', 'FontWeight', 'normal');
figure(hFig);
end

% -------------------------------------------------------------------------------------
function noExported = localExportPatches(obj, patchSet, exportDir, wb)
% write each patch at full resolution as an image plus a MIB model of its labels
%
% Output Arguments:
%   - **noExported** - how many patches were written; fewer than requested when the
%     progress dialog was cancelled, in which case the files already on disk are kept

if ~isfolder(exportDir); mkdir(exportDir); end

noExported = 0;
for patchId = 1:numel(patchSet)
    if wb.CancelRequested; return; end
    wb.Value = patchId/numel(patchSet);
    baseName = sprintf('%03d_%s', patchId, patchSet(patchId).sourceName);
    imwrite(patchSet(patchId).image, fullfile(exportDir, [baseName '.tif']));
    noExported = noExported + 1;

    labelMap = patchSet(patchId).labels;
    if isempty(labelMap); continue; end

    % same MIB model layout that startPredictionInstances writes; every variable below is
    % referenced by name in the save() call, which is what MIB's model reader expects
    outputLabels = labelMap;
    modelMaterialNames = patchSet(patchId).materialNames;
    numMaterials = max(2, numel(modelMaterialNames));
    if numel(modelMaterialNames) < numMaterials
        modelMaterialNames = arrayfun(@(x) num2str(x), (1:numMaterials)', 'UniformOutput', false);
    end
    modelMaterialColors = obj.colormap255(mod((0:numMaterials-1), size(obj.colormap255, 1))+1, :);
    modelType = patchSet(patchId).modelType;
    modelVariable = 'outputLabels';
    save(fullfile(exportDir, ['Labels_' baseName '.model']), ...
        'outputLabels', 'modelMaterialNames', 'modelMaterialColors', ...
        'modelVariable', 'modelType', '-mat', '-v7.3');
end
end

% -------------------------------------------------------------------------------------
function noValidationImages = localCountValidationImages(obj)
% number of files in the validation set, without building any datastore

if strcmp(obj.BatchOpt.Workflow{1}, '2D Instance')
    noValidationImages = numel(dir(fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationLabels', '*.mat')));
else
    [validationDir, fileExtension] = localValidationImageSource(obj);
    noValidationImages = numel(dir(fullfile(validationDir, ['*' fileExtension])));
end
end

% -------------------------------------------------------------------------------------
function [validationDir, fileExtension, readFcn] = localValidationImageSource(obj)
% where the validation images live, following the same rule as startTraining

mibDeepStoreLoadImagesOpt.mibBioformatsCheck = obj.BatchOpt.BioformatsTraining;
mibDeepStoreLoadImagesOpt.BioFormatsIndices = obj.BatchOpt.BioformatsTrainingIndex{1};
mibDeepStoreLoadImagesOpt.Workflow = obj.BatchOpt.Workflow{1};

if strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Preprocessing is not required') || ...
        strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Split files for training/validation')
    validationDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationImages');
    fileExtension = lower(['.' obj.BatchOpt.ImageFilenameExtensionTraining{1}]);
    readFcn = @(fn)deepmib.storeLoadImages(fn, mibDeepStoreLoadImagesOpt);
else
    validationDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'ValidationImages');
    fileExtension = '.mibImg';
    readFcn = @deepmib.storeLoadImages;
end
end

% -------------------------------------------------------------------------------------
function patchSet = localCollectSemanticPatches(obj, validationSeed, patchesPerImage, maxPatches, wb)
% draw validation patches the way the semantic workflows do

patchSet = struct('image', {}, 'labels', {}, 'materialNames', {}, 'modelType', {}, ...
    'caption', {}, 'sourceName', {});

inputPatchSize = str2num(obj.BatchOpt.T_InputPatchSize); %#ok<ST2NM>
[validationDir, fileExtension, readFcn] = localValidationImageSource(obj);
if isempty(dir(fullfile(validationDir, ['*' fileExtension]))); return; end

valImgDS = imageDatastore(validationDir, 'FileExtensions', fileExtension, ...
    'IncludeSubfolders', false, 'ReadFcn', readFcn);

% generic class names: only the label indices matter for inspection, and deriving the
% real names would mean repeating the whole class-discovery dialog of startTraining
classNames = arrayfun(@(x) sprintf('Class%.2d', x), 1:obj.BatchOpt.T_NumberOfClasses{1}-1, 'UniformOutput', false);
classNames = [{'Exterior'}; classNames'];
pixelLabelIDs = 1:numel(classNames);

valLabelsDS = localValidationLabelDatastore(obj, classNames, pixelLabelIDs);
if isempty(valLabelsDS)
    % without labels the positions can still be drawn, the image stands in as its own
    % response exactly as the augmentation preview does
    valLabelsDS = valImgDS;
    labelsAvailable = false;
else
    labelsAvailable = true;
end

switch obj.BatchOpt.Workflow{1}(1:2)
    case {'3D', '2.'}   % '3D Semantic' and '2.5D Semantic'
        randomStoreInputPatchSize = inputPatchSize(1:3);
    otherwise
        randomStoreInputPatchSize = inputPatchSize(1:2);
end

% the seed decides the patch positions, and it must not disturb the training sequence
rngState = rng();
if validationSeed ~= 0; rng(validationSeed, 'twister'); end
patchDS = randomPatchExtractionDatastore(valImgDS, valLabelsDS, randomStoreInputPatchSize, ...
    'PatchesPerImage', patchesPerImage);
patchDS.MiniBatchSize = 1;

responseField = 'ResponsePixelLabelImage';
patchId = 0;
while hasdata(patchDS) && patchId < maxPatches && ~wb.CancelRequested
    patchBatch = read(patchDS);
    if ~ismember(responseField, patchBatch.Properties.VariableNames)
        responseField = patchBatch.Properties.VariableNames{2};
    end
    for rowId = 1:height(patchBatch)
        patchId = patchId + 1;
        if patchId > maxPatches; break; end
        patchSet(patchId).image = localMiddleSlice(patchBatch.InputImage{rowId}, randomStoreInputPatchSize);
        if labelsAvailable
            labelPatch = patchBatch.(responseField){rowId};
            labelPatch = localMiddleSlice(labelPatch, randomStoreInputPatchSize);
            if iscategorical(labelPatch)
                labelPatch = uint8(labelPatch) - 1;     % MIB models count Exterior as 0
            end
            patchSet(patchId).labels = labelPatch;
            patchSet(patchId).materialNames = classNames(2:end);
            patchSet(patchId).modelType = 63;
        else
            patchSet(patchId).labels = [];
            patchSet(patchId).materialNames = {};
            patchSet(patchId).modelType = 63;
        end
        patchSet(patchId).caption = sprintf('patch %d', patchId);
        patchSet(patchId).sourceName = sprintf('patch%03d', patchId);
    end
end
rng(rngState);
end

% -------------------------------------------------------------------------------------
function valLabelsDS = localValidationLabelDatastore(obj, classNames, pixelLabelIDs)
% build the validation label datastore, or return empty when it cannot be built

valLabelsDS = [];
try
    if strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Preprocessing is not required') || ...
            strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Split files for training/validation')
        labelsDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationLabels');
        if strcmp(obj.BatchOpt.ModelFilenameExtension{1}, 'MODEL')
            valLabelsDS = pixelLabelDatastore(labelsDir, classNames, pixelLabelIDs, ...
                'FileExtensions', '.model', 'ReadFcn', @deepmib.storeLoadModel);
        elseif strcmp(obj.BatchOpt.Workflow{1}, '2.5D Semantic')
            valLabelsDS = pixelLabelDatastore(labelsDir, classNames, pixelLabelIDs, ...
                'FileExtensions', lower(['.' obj.BatchOpt.ModelFilenameExtension{1}]), ...
                'ReadFcn', @deepmib.storeLoadImages);
        else
            valLabelsDS = pixelLabelDatastore(labelsDir, classNames, pixelLabelIDs, ...
                'FileExtensions', lower(['.' obj.BatchOpt.ModelFilenameExtension{1}]));
        end
    else
        valLabelsDS = imageDatastore(fullfile(obj.BatchOpt.ResultingImagesDir, 'ValidationLabels'), ...
            'FileExtensions', '.mibCat', 'ReadFcn', @deepmib.storeLoadCategorical);
    end
    if numel(valLabelsDS.Files) == 0; valLabelsDS = []; end
catch
    valLabelsDS = [];   % inspection is still useful without the labels
end
end

% -------------------------------------------------------------------------------------
function patchImage = localMiddleSlice(patchImage, randomStoreInputPatchSize)
% for a 3D patch show its middle slice, as the augmentation preview does

if numel(randomStoreInputPatchSize) == 3 && randomStoreInputPatchSize(3) > 1 && ~ismatrix(patchImage)
    patchImage = squeeze(patchImage(:, :, ceil(size(patchImage, 3)/2), :));
end
end

% -------------------------------------------------------------------------------------
function patchSet = localCollectInstancePatches(obj, validationSeed, patchesPerImage, maxPatches, wb)
% draw validation patches exactly as controllers.MibDeep/startTrainingInstances does

patchSet = struct('image', {}, 'labels', {}, 'materialNames', {}, 'modelType', {}, ...
    'caption', {}, 'sourceName', {});

valModelList = dir(fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationLabels', '*.mat'));
if isempty(valModelList); return; end

inputPatchSize = str2num(obj.BatchOpt.T_InputPatchSize); %#ok<ST2NM>
patchOpt.imageDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationImages');
patchOpt.patchSize = inputPatchSize(1:2);
patchOpt.objectFraction = 0.9;      % same values startTrainingInstances uses
patchOpt.minObjectArea = 4;
patchOpt.getImageOptions = struct(...
    'mibBioformatsCheck', obj.BatchOpt.BioformatsTraining, ...
    'BioFormatsIndices', obj.BatchOpt.BioformatsTrainingIndex{1}, ...
    'Workflow', obj.BatchOpt.Workflow{1});

valModelFiles = arrayfun(@(f) fullfile(f.folder, f.name), valModelList, 'UniformOutput', false);
valModelFiles = repmat(valModelFiles(:), [patchesPerImage, 1]);
noObservations = numel(valModelFiles);

% identical derivation to startTrainingInstances, so these are the same patches
observationSeeds = zeros(noObservations, 1);
if validationSeed ~= 0
    observationSeeds = mod(validationSeed * 100003 + (1:noObservations)', 2^32 - 2) + 1;
end

for observationIndex = 1:min(noObservations, maxPatches)
    if wb.CancelRequested; return; end
    observationOpt = patchOpt;
    if observationSeeds(observationIndex) ~= 0
        observationOpt.patchSeed = observationSeeds(observationIndex);
    end
    observation = deepmib.readInstancePatch(valModelFiles{observationIndex}, observationOpt);

    masks = observation{4};
    noObjects = size(masks, 3);
    % one index per instance, which is how startPredictionInstances stores them too
    labelMap = zeros(size(masks, 1), size(masks, 2), 'uint16');
    for objectId = 1:noObjects
        labelMap(masks(:, :, objectId)) = objectId;
    end

    % the preprocessed label files are named "Labels_<image>.mat"; drop that prefix so the
    % exported pair reads as <index>_<image>.tif and Labels_<index>_<image>.model rather
    % than carrying "Labels_" twice
    [~, sourceName] = fileparts(valModelFiles{observationIndex});
    sourceName = regexprep(sourceName, '^Labels_', '');
    patchSet(observationIndex).image = observation{1};
    patchSet(observationIndex).labels = labelMap;
    patchSet(observationIndex).materialNames = arrayfun(@(x) num2str(x), (1:max(2, noObjects))', 'UniformOutput', false);
    patchSet(observationIndex).modelType = 65535;
    patchSet(observationIndex).caption = sprintf('%s\n%d objects', sourceName, noObjects);
    patchSet(observationIndex).sourceName = sourceName;
end
end
