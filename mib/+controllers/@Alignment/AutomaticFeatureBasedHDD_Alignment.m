function AutomaticFeatureBasedHDD_Alignment(obj, parameters)
% AUTOMATICFEATUREBASEDHDD_ALIGNMENT - Streaming v1 feature-based alignment.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.AutomaticFeatureBasedHDD_Alignment(parameters)
%
% Streaming variant of :meth:`AutomaticFeatureBased_Alignment` for stacks
% that do not fit in memory. Reads slices one at a time from
% ``obj.BatchOpt.HDD_InputDir`` via :class:`matlab.io.datastore.ImageDatastore`
% configured with :func:`io.loadImagesWrapper` as its ``ReadFcn``.
%
% Two-phase fit:
%   1. **Parallel detect + extract** — every file is opened in turn (parfor
%      when ``BatchOpt.UseParallelComputing`` is set), features are detected
%      with :func:`utils.align.detectFeatures` and descriptors are extracted
%      with :func:`extractFeatures`. Only the descriptors + valid-point
%      locations are kept in memory — never the images.
%   2. **Sequential match + compose** — adjacent descriptor pairs are
%      matched, :func:`estgeotform2d` fits a robust 2-D transform, the
%      cumulative tform chain is built via legacy ``.T`` composition.
%
% Apply phase re-reads each image, warps it with :func:`imwarp` against
% the chosen ``refImgSize`` (cropped = slice 1's dims; extended = each
% slice's per-image :func:`affineOutputView`), and saves it to
% ``<InputDir>/HDD_OutputSubfolderName`` via :meth:`core.MibImage.save`.
% Cropped + extended apply loops both run under ``parfor`` when parallel
% computing is enabled.
%
% No in-memory dataset is touched — no backup, no ``NewDataset`` notify.
%
% Input Arguments:
%   - **parameters** — struct produced by :meth:`continueBtn_Callback`.
%     Reads ``TransformationType``, ``TransformationMode``, ``colorCh``,
%     ``backgroundColor``, ``useBatchMode``, ``method``,
%     ``UseParallelComputing``.

% Updates
%

% Parent figure for any dialogs
if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

parameters.detectPointsType = obj.BatchOpt.FeatureDetectorType{1};

% --- Pre-flight reminder
if ~parameters.useBatchMode
    questOpt.Icon = 'puffin_warning';
    questOpt.WindowStyle = 'modal';
    answer = utils.dlgs.inputQuestDlg(parentFig, ...
        sprintf(['Before proceeding, please load the first image of the dataset ' ...
                'into MIB so that the image dimensions, pixel size, and reference ' ...
                'frame can be derived from it.']), ...
        'HDD feature-based', 'Yes, the first image is loaded', 'Cancel', '', ...
        'Yes, the first image is loaded', questOpt);
    if isempty(answer) || strcmp(answer, 'Cancel'); return; end
end

inputDir = obj.BatchOpt.HDD_InputDir;
if ~isfolder(inputDir)
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('Input directory does not exist: "%s"', inputDir), 'HDD feature-based');
    return;
end
ext = lower(['.' obj.BatchOpt.HDD_InputFilenameExtension{1}]);

readOpt = struct();
readOpt.mibBioformatsCheck = obj.BatchOpt.HDD_BioformatsReader;
readOpt.verbose            = false;
readOpt.BioFormatsIndices  = obj.BatchOpt.HDD_BioformatsIndex{1};

try
    imgDS = imageDatastore(inputDir, ...
        'FileExtensions', ext, ...
        'IncludeSubfolders', false, ...
        'ReadFcn', @(fn) io.loadImagesWrapper(fn, readOpt));
catch ME
    utils.dlgs.showErrorDialog(parentFig, ME, 'HDD feature-based');
    return;
end
numFiles = numel(imgDS.Files);
if numFiles < 2
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('Found %d files in "%s" — need at least 2 to align.', numFiles, inputDir), ...
        'HDD feature-based');
    return;
end

% --- Settings dialog (skipped in batch and on replay)
shiftsLoaded = ~isempty(obj.shiftsX) && iscell(obj.shiftsX);
if ~parameters.useBatchMode && ~shiftsLoaded
    status = obj.updateAutomaticOptions();
    if status == 0; return; end
end

% --- Reference dimensions come from the currently-loaded MIB dataset
id = obj.mibModel.getActiveId();
[Height, Width] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));
img5D = obj.mibModel.I{id}.image;

if obj.automaticOptions.imgWidthForAnalysis == 0
    parameters.imgWidthForAnalysis = Width;
else
    parameters.imgWidthForAnalysis = obj.automaticOptions.imgWidthForAnalysis;
end
ratio = parameters.imgWidthForAnalysis / Width;

% --- Background fill
if isnumeric(parameters.backgroundColor)
    bgImage = double(parameters.backgroundColor);
elseif strcmp(parameters.backgroundColor, 'black')
    bgImage = 0;
elseif strcmp(parameters.backgroundColor, 'white')
    bgImage = double(img5D.maxInt);
else    % 'mean'
    firstSlice = cell2mat(obj.mibModel.getData2D('image', 1, [], parameters.colorCh, struct('blockModeSwitch', 0)));
    bgImage = mean(firstSlice(:));
end

% --- Parallel pool setup
if parameters.UseParallelComputing
    parforArg = obj.mibModel.cpuParallelLimitMax;
    if isempty(gcp('nocreate')); parpool(parforArg); end
else
    parforArg = 0;
end

% --- Cancelable progress
pwb = [];
if obj.BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(numFiles * 2, 'HDD feature-based: detecting + matching...', ...
        parentFig, 'Alignment', true);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

% --- Per-file dimension tracking + tform storage
heightVec = zeros(numFiles, 1);
widthVec  = zeros(numFiles, 1);
tformMatrix = cell(numFiles, 1);
rbMatrix    = cell(numFiles, 1);

if shiftsLoaded
    tformMatrix = obj.shiftsX;
    rbMatrix    = obj.shiftsY;
end

% --- Phase 1: detect + match (skipped on replay)
if ~shiftsLoaded
    if ~isempty(pwb); pwb.updateText('Step 1/3: detecting features (per file)...'); end
    [featuresList, validPtsList, heightVec, widthVec, ok] = detectHDDFeatures( ...
        imgDS, numFiles, parameters, ratio, obj.automaticOptions, ...
        parforArg, pwb, parentFig);
    if ~ok; return; end

    if ~isempty(pwb)
        pwb.updateText('Step 2/3: matching + estimating per-slice transforms...');
    end

    % First slice: identity
    tformMatrix{1} = affine2d(eye(3));

    for layer = 2:numFiles
        if ~isempty(pwb)
            if pwb.getCancelState(); return; end
            if mod(layer, 10) == 0; pwb.increment(); end
        end

        indexPairs = matchFeatures(featuresList{layer - 1}, featuresList{layer});
        if isempty(indexPairs) || size(indexPairs, 1) < 3
            utils.dlgs.showErrorDialog(parentFig, ...
                sprintf(['Not enough matched points between file %d and %d (%d found, ' ...
                        '≥3 required). Adjust detector settings.'], ...
                        layer - 1, layer, size(indexPairs, 1)), 'HDD feature-based');
            return;
        end
        matchedOriginal  = validPtsList{layer - 1}(indexPairs(:, 1));
        matchedDistorted = validPtsList{layer}(indexPairs(:, 2));

        try
            tformNew = estgeotform2d(matchedDistorted, matchedOriginal, ...
                parameters.TransformationType, ...
                'MaxNumTrials', obj.automaticOptions.estGeomTransform.MaxNumTrials, ...
                'Confidence',   obj.automaticOptions.estGeomTransform.Confidence, ...
                'MaxDistance',  obj.automaticOptions.estGeomTransform.MaxDistance);
        catch ME
            utils.dlgs.showErrorDialog(parentFig, ME, ...
                sprintf('estgeotform2d failed on file %d', layer));
            return;
        end
        tformLegacy = makeLegacyTform(tformNew);

        % Compose with previous cumulative tform
        if isprop(tformLegacy, 'T') && isprop(tformMatrix{layer - 1}, 'T')
            tformLegacy.T = tformLegacy.T * tformMatrix{layer - 1}.T;
        end
        tformMatrix{layer} = tformLegacy;
    end

    % --- Optional BatchOpt-driven smoothing on stretch + shear
    if obj.BatchOpt.SubtractRunningAverage
        tformMatrix = smoothFeatureChain(tformMatrix, numFiles, obj.BatchOpt);
    end

    obj.shiftsX = tformMatrix;
    obj.shiftsY = rbMatrix;
end

% --- Phase 2: read + warp + save each image to the output directory
if ~isempty(pwb)
    pwb.updateText('Step 3/3: warping + saving images...');
    pwb.setCurrentIteration(0);
end

outputDir = fullfile(inputDir, obj.BatchOpt.HDD_OutputSubfolderName);
if ~isfolder(outputDir); mkdir(outputDir); end

saveOpt = saveOptionsFromExt(obj.BatchOpt.HDD_OutputFileExtension{1});
saveOpt.showWaitbar = false;
saveOpt.silent      = true;
saveOpt.overwrite   = true;

imgDS.reset();
outputExt   = lower(['.' obj.BatchOpt.HDD_OutputFileExtension{1}]);
isCropped   = strcmp(parameters.TransformationMode, 'cropped');

if isCropped
    % Reference frame = slice 1's dims (matches MIB2)
    if isempty(heightVec) || heightVec(1) == 0
        refImgSize = imref2d([Height, Width]);
    else
        refImgSize = imref2d([heightVec(1), widthVec(1)]);
    end

    % Apply in parallel
    files = imgDS.Files;
    parfor (layer = 1:numFiles, parforArg)
        if isempty(tformMatrix{layer}); continue; end
        try
            imgIn5D = io.loadImagesWrapper(files{layer}, readOpt);
        catch
            continue;
        end
        [iWarped, ~] = imwarp(squeeze(imgIn5D(:,:,1,:,1)), tformMatrix{layer}, ...
            'cubic', 'OutputView', refImgSize, 'FillValues', double(bgImage));
        saveOneImage(iWarped, files{layer}, outputDir, outputExt, saveOpt);
    end
    if ~isempty(pwb); pwb.setCurrentIteration(numFiles); end
else
    % Extended view — per-slice affineOutputView "CenterOutput", then
    % canvas computed from the union of XWorld / YWorld limits
    Hmax = max(heightVec);  Wmax = max(widthVec);
    if Hmax == 0; Hmax = Height; Wmax = Width; end
    for layer = 1:numFiles
        if isempty(tformMatrix{layer}); continue; end
        rbMatrix{layer} = affineOutputView([Hmax, Wmax], tformMatrix{layer}, ...
            'BoundsStyle', 'CenterOutput');
    end

    xmin = zeros(numFiles, 1);  xmax = zeros(numFiles, 1);
    ymin = zeros(numFiles, 1);  ymax = zeros(numFiles, 1);
    for layer = 1:numFiles
        if isempty(rbMatrix{layer}); continue; end
        xmin(layer) = floor(rbMatrix{layer}.XWorldLimits(1));
        xmax(layer) = floor(rbMatrix{layer}.XWorldLimits(2));
        ymin(layer) = floor(rbMatrix{layer}.YWorldLimits(1));
        ymax(layer) = floor(rbMatrix{layer}.YWorldLimits(2));
    end
    dx = min(xmin);
    dy = min(ymin);
    nWidth  = max(xmax) - dx + abs(dx);
    nHeight = max(ymax) - dy + abs(dy);

    files = imgDS.Files;
    parfor (layer = 1:numFiles, parforArg)
        if isempty(tformMatrix{layer}); continue; end
        try
            imgIn5D = io.loadImagesWrapper(files{layer}, readOpt);
        catch
            continue;
        end
        % Anchor this slice's rbMatrix into the union canvas frame
        rbL = rbMatrix{layer};
        rbL.XWorldLimits = rbL.XWorldLimits - ceil((max(widthVec)  - min(widthVec))  / 2) - dx * 2;
        rbL.YWorldLimits = rbL.YWorldLimits - (max(heightVec) - min(heightVec)) - dy;
        rbL.ImageSize    = [nHeight, nWidth];

        iWarped = imwarp(squeeze(imgIn5D(:,:,1,:,1)), tformMatrix{layer}, 'cubic', ...
            'OutputView', rbL, 'FillValues', double(bgImage));
        saveOneImage(iWarped, files{layer}, outputDir, outputExt, saveOpt);
    end
    if ~isempty(pwb); pwb.setCurrentIteration(numFiles); end
end

% --- Save tforms / rbMatrix to file if requested
if obj.BatchOpt.SaveShiftsToFile
    saveHDDTformsToFile(obj, id, parameters.useBatchMode, parentFig, ...
        tformMatrix, rbMatrix, heightVec, widthVec);
end

obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
    'HDD-aligned using %s; type=%s, mode=%s, detector=%s, output → %s', ...
    parameters.method, parameters.TransformationType, parameters.TransformationMode, ...
    parameters.detectPointsType, outputDir));
end

% =============================================================================
function [featuresList, validPtsList, heightVec, widthVec, ok] = detectHDDFeatures( ...
    imgDS, numFiles, parameters, ratio, automaticOptions, parforArg, pwb, parentFig)
% Parfor over every file: load, detect features, extract descriptors. Only
% the descriptors + valid-point locations + dimensions are kept in memory.

ok = false;
featuresList = cell(numFiles, 1);
validPtsList = cell(numFiles, 1);
heightVec    = zeros(numFiles, 1);
widthVec     = zeros(numFiles, 1);
files = imgDS.Files;

detectPointsType   = parameters.detectPointsType;
colorCh            = parameters.colorCh;
rotationInvariance = automaticOptions.rotationInvariance;
readFcn = imgDS.ReadFcn;

% Snapshot dimensions to detect errors before parfor returns
errorFlag = false(numFiles, 1);
errorMsgs = cell(numFiles, 1);

parfor (layer = 1:numFiles, parforArg)
    try
        img5D = readFcn(files{layer});
    catch ME
        errorFlag(layer) = true;
        errorMsgs{layer} = sprintf('Read failed (file %d: %s): %s', ...
            layer, files{layer}, ME.message);
        continue;
    end
    [heightVec(layer), widthVec(layer), ~, nColors, ~] = size(img5D, 1:5);

    if colorCh > nColors; ch = 1; else; ch = colorCh; end
    distorted = squeeze(img5D(:, :, 1, ch, 1));
    if ratio ~= 1; distorted = imresize(distorted, ratio, 'bicubic'); end

    ptsDistorted = utils.align.detectFeatures(distorted, detectPointsType, automaticOptions);
    if isempty(ptsDistorted)
        errorFlag(layer) = true;
        errorMsgs{layer} = sprintf('No features detected on file %d', layer);
        continue;
    end
    if ~strcmp(detectPointsType, 'Oriented FAST and rotated BRIEF (ORB)')
        [featuresList{layer}, validPtsList{layer}] = extractFeatures(distorted, ...
            ptsDistorted, 'Upright', rotationInvariance);
    else
        [featuresList{layer}, validPtsList{layer}] = extractFeatures(distorted, ptsDistorted);
    end
    validPtsList{layer}.Location = validPtsList{layer}.Location / ratio;
    if ~isempty(pwb) && mod(layer, 10) == 0; pwb.increment(); end
end

if any(errorFlag)
    firstErr = find(errorFlag, 1);
    utils.dlgs.showErrorDialog(parentFig, errorMsgs{firstErr}, 'HDD feature-based');
    return;
end
ok = true;
end

% =============================================================================
function tformLegacy = makeLegacyTform(tform)
% Convert estgeotform2d's modern types (rigidtform2d / simtform2d /
% affinetform2d / projtform2d) back to the legacy ``.T`` form so the
% cumulative ``t.T = t.T * prev.T`` composition keeps working.

if isprop(tform, 'T')
    tformLegacy = tform;
    return;
end
if isa(tform, 'projtform2d')
    tformLegacy = projective2d(tform.A');
else
    tformLegacy = affine2d(tform.A');
end
end

% =============================================================================
function tformMatrix = smoothFeatureChain(tformMatrix, numFiles, BatchOpt)
% Apply running-average smoothing to the stretch + shear components of
% the cumulative ``.T`` chain. Mirrors :func:`AutomaticFeatureBased_Alignment`'s
% local ``smoothTformChain`` but indexes from slice 1 onward (the HDD
% variant treats slice 1 as identity rather than skipping it).

vec_length = numel(tformMatrix);
hasTform = false(vec_length, 1);
for k = 2:vec_length
    hasTform(k) = ~isempty(tformMatrix{k}) && isprop(tformMatrix{k}, 'T');
end
if ~any(hasTform); return; end

x_stretch = arrayfun(@(k) tformMatrix{k}.T(1,1), 1:vec_length);
y_stretch = arrayfun(@(k) tformMatrix{k}.T(2,2), 1:vec_length);
x_shear   = arrayfun(@(k) tformMatrix{k}.T(2,1), 1:vec_length);
y_shear   = arrayfun(@(k) tformMatrix{k}.T(1,2), 1:vec_length);

halfwidth = BatchOpt.SubtractRunningAverageStep{1};
if halfwidth > floor(numFiles/2 - 1)
    halfwidth = max(1, floor(numFiles/2 - 1));
end
excludeStretch = BatchOpt.SubtractRunningAverageExcludeStretchPeaks{1};
excludeShear   = BatchOpt.SubtractRunningAverageExcludeShearPeaks{1};

if BatchOpt.SubtractRunningAverageFixStretch
    x_stretch = utils.align.runningAverageSmoothPoints(x_stretch, halfwidth, excludeStretch) + 1;
    y_stretch = utils.align.runningAverageSmoothPoints(y_stretch, halfwidth, excludeStretch) + 1;
end
if BatchOpt.SubtractRunningAverageFixShear
    x_shear = utils.align.runningAverageSmoothPoints(x_shear, halfwidth, excludeShear);
    y_shear = utils.align.runningAverageSmoothPoints(y_shear, halfwidth, excludeShear);
end

for k = 2:vec_length
    if ~hasTform(k); continue; end
    tformMatrix{k}.T(1,1) = x_stretch(k);
    tformMatrix{k}.T(2,2) = y_stretch(k);
    tformMatrix{k}.T(2,1) = x_shear(k);
    tformMatrix{k}.T(1,2) = y_shear(k);
end
end

% =============================================================================
function saveOneImage(iWarped, srcFile, outputDir, outputExt, saveOpt)
% Wrap a 2-D / 3-D warped slice into a ``core.MibImage`` and save to disk.
[~, baseName, ~] = fileparts(srcFile);
[h, w, c] = size(iWarped, 1:3);
mibImg = core.MibImage(reshape(iWarped, [h, w, 1, c, 1]));
mibImg.save(fullfile(outputDir, [baseName outputExt]), saveOpt);
end

% =============================================================================
function saveOpt = saveOptionsFromExt(extLabel)
switch extLabel
    case 'AM';   saveOpt.Format = 'Amira Mesh binary (*.am)';
    case 'JPG';  saveOpt.Format = 'Joint Photographic Experts Group (*.jpg)';
    case 'MRC';  saveOpt.Format = 'MRC format for IMOD (*.mrc)';
    case 'NRRD'; saveOpt.Format = 'NRRD Data Format (*.nrrd)';
    case 'PNG';  saveOpt.Format = 'Portable Network Graphics (*.png)';
    case 'TIF';  saveOpt.Format = 'TIF format uncompressed (*.tif)';
    otherwise;   saveOpt.Format = 'TIF format uncompressed (*.tif)';
end
end

% =============================================================================
function saveHDDTformsToFile(obj, id, useBatchMode, parentFig, ...
    tformMatrix, rbMatrix, heightVec, widthVec)
% Persist tformMatrix + rbMatrix + per-file dimensions to a ``.coefXY`` file.

if useBatchMode
    fn = obj.mibModel.I{id}.image.sliceName('Filename');
    [pathstr, name, ~] = fileparts(fn);
    fullPath = fullfile(pathstr, [name '_align.coefXY']);
elseif ~isempty(obj.view) && isvalid(obj.view) && isfield(obj.view.handles, 'saveShiftsXYpath')
    fullPath = obj.view.handles.saveShiftsXYpath.Value;
else
    return;
end
fprintf('Saving HDD feature-based transforms to file: %s ... ', fullPath);
try
    save(fullPath, 'tformMatrix', 'rbMatrix', 'heightVec', 'widthVec');
    fprintf('done!\n');
catch ME
    fprintf('failed.\n');
    utils.dlgs.showErrorDialog(parentFig, ME, 'Save shifts');
end
end

% =============================================================================
function safeDeleteWaitbar(pwb)
if ~isempty(pwb) && isvalid(pwb)
    pwb.deletePoolWaitbar();
end
end
