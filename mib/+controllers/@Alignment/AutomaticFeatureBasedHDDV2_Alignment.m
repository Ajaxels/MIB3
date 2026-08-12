function AutomaticFeatureBasedHDDV2_Alignment(obj, parameters)
% AUTOMATICFEATUREBASEDHDDV2_ALIGNMENT - Streaming v2 feature-based alignment.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.AutomaticFeatureBasedHDDV2_Alignment(parameters)
%
% Streaming variant of :meth:`AutomaticFeatureBasedV2_Alignment` for stacks
% that do not fit in memory. Reads slices one at a time from
% ``obj.BatchOpt.HDD_InputDir`` via :class:`matlab.io.datastore.ImageDatastore`
% configured with :func:`io.loadImagesWrapper` as its ``ReadFcn``.
%
% V2 specifics (vs the v1 HDD variant):
%
% - Uses ``estgeotform2d`` returning :class:`affinetform2d` natively; tforms
%   are composed via the modern ``.A`` (premultiply) property.
% - Stores **pairwise** transforms separately from **cumulative** ones and
%   decomposes each pairwise matrix into translation / rotation / scale so
%   the running-average smoothing can act on each parameter independently.
% - Downsamples by ``1 / imgDownsamplingFactorForAnalysis``.
% - Builds the extended canvas via **corner projection**: transform the
%   four image corners through every cumulative tform and union their
%   bounding box.
% - Rounds translations to integer pixels when
%   ``TransformationType == 'translation'``.
%
% Two-phase fit:
%   1. **Parallel detect + extract** (parfor when ``UseParallelComputing``
%      is set). Only descriptors + valid-point locations are kept in memory.
%   2. **Sequential match + compose** - adjacent descriptor pairs are
%      matched, ``estgeotform2d`` fits a robust 2-D transform, the
%      pairwise tform is stored and decomposed.
%
% Apply phase re-reads each image, warps it with :func:`imwarp` against the
% chosen ``OutputView`` (cropped = max input dims; extended = the union
% canvas computed by corner projection), and saves the result to
% ``<InputDir>/HDD_OutputSubfolderName`` via :meth:`core.MibImage.save`.
% The apply loop runs under ``parfor`` when parallel computing is enabled.
%
% No in-memory dataset is touched - no backup, no ``NewDataset`` notify.
%
% Input Arguments:
%   - **parameters** - struct produced by :meth:`continueBtn_Callback`.
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

% V2 supports only translation / rigid / similarity / affine
if ~ismember(parameters.TransformationType, {'translation', 'rigid', 'similarity', 'affine'})
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf(['TransformationType "%s" is not supported by the v2 algorithm.\n\n' ...
                'Supported types: translation, rigid, similarity, affine.'], ...
                parameters.TransformationType), 'HDD feature-based v2');
    return;
end

% --- Pre-flight reminder
if ~parameters.useBatchMode
    questOpt.Icon = 'puffin_warning';
    questOpt.WindowStyle = 'modal';
    questOpt.WindowWidth = 500;
    answer = utils.dlgs.inputQuestDlg(parentFig, ...
        sprintf(['Before proceeding, please load the first image of the dataset ' ...
                'into MIB so that the image dimensions, pixel size, and reference ' ...
                'frame can be derived from it.']), ...
        'HDD feature-based v2', 'Yes, the first image is loaded', 'Cancel', ...
        'Yes, the first image is loaded', questOpt);
    if isempty(answer) || strcmp(answer, 'Cancel'); return; end
end

inputDir = obj.BatchOpt.HDD_InputDir;
if ~isfolder(inputDir)
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('Input directory does not exist: "%s"', inputDir), 'HDD feature-based v2');
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
    utils.dlgs.showErrorDialog(parentFig, ME, 'HDD feature-based v2');
    return;
end
numFiles = numel(imgDS.Files);
if numFiles < 2
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('Found %d files in "%s" - need at least 2 to align.', numFiles, inputDir), ...
        'HDD feature-based v2');
    return;
end

% --- Replay path: shifts loaded from .coefXY file
shiftsLoaded = ~isempty(obj.shiftsX) && isstruct(obj.shiftsX) && isfield(obj.shiftsX, 'cumulativeTforms');

% --- Settings dialog (skipped in batch and on replay)
if ~parameters.useBatchMode && ~shiftsLoaded
    status = obj.updateAutomaticOptions();
    if status == 0; return; end
end

% --- Reference dimensions come from the currently-loaded MIB dataset
id = obj.mibModel.getActiveId();
[Height, Width] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));
img5D = obj.mibModel.I{id}.image;

parameters.imgDownsamplingFactor = obj.automaticOptions.imgDownsamplingFactorForAnalysis;
ratio = 1 / parameters.imgDownsamplingFactor;

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
    parforArg = obj.mibModel.preferences.System.cpuParallelLimit;
    if isempty(gcp('nocreate')); parpool(parforArg); end
else
    parforArg = 0;
end

% --- Cancelable progress
pwb = [];
if obj.BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(numFiles*2, 'HDD v2: detecting + matching...', ...
        parentFig, 'Alignment', true);
    stepIncrement = max([1 floor(numFiles/10)]);
    pwb.setIncrement(stepIncrement);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

% --- Per-file dimension tracking + parameter storage
heightVec        = zeros(numFiles, 1);
widthVec         = zeros(numFiles, 1);
pairwiseTforms   = cell(numFiles, 1);
cumulativeTforms = cell(numFiles, 1);
translations     = zeros(numFiles, 2);
rotations        = zeros(numFiles, 1);
scales           = ones(numFiles, 1);
affine_params    = zeros(numFiles, 4);
affine_params(:, [1 4]) = 1;

if shiftsLoaded
    pairwiseTforms   = obj.shiftsX.pairwiseTforms;
    cumulativeTforms = obj.shiftsX.cumulativeTforms;
    translations     = obj.shiftsX.translations;
    rotations        = obj.shiftsX.rotations;
    scales           = obj.shiftsX.scales;
    affine_params    = obj.shiftsX.affine_params;
    if isfield(obj.shiftsX, 'heightVec'); heightVec = obj.shiftsX.heightVec; end
    if isfield(obj.shiftsX, 'widthVec');  widthVec  = obj.shiftsX.widthVec;  end
end

% --- Phase 1: detect features (skipped on replay)
if ~shiftsLoaded
    if ~isempty(pwb); pwb.updateText('Step 1/3: detecting features (per file)...'); end
    [featuresList, validPtsList, heightVec, widthVec, ok] = detectHDDFeaturesV2( ...
        imgDS, numFiles, parameters, ratio, obj.automaticOptions, ...
        parforArg, pwb, parentFig);
    if ~ok; return; end

    if ~isempty(pwb)
        pwb.updateText('Step 2/3: matching + estimating per-slice transforms...');
    end

    % First slice: identity
    pairwiseTforms{1} = affinetform2d(eye(3));

    % Fix RANSAC seed so estgeotform2d is reproducible across runs and
    % matches the in-memory variant for direct comparison.
    rng(0, 'twister');

    for layer = 2:numFiles
        if ~isempty(pwb)
            if pwb.getCancelState(); return; end
            if mod(layer, stepIncrement) == 0; pwb.increment(); end
        end

        indexPairs = matchFeatures(featuresList{layer - 1}, featuresList{layer});
        if isempty(indexPairs) || size(indexPairs, 1) < 3
            utils.dlgs.showErrorDialog(parentFig, ...
                sprintf(['Not enough matched points between file %d and %d (%d found, ' ...
                        '≥3 required). Adjust detector settings.'], ...
                        layer - 1, layer, size(indexPairs, 1)), 'HDD feature-based v2');
            return;
        end
        matchedOriginal  = validPtsList{layer - 1}(indexPairs(:, 1));
        matchedDistorted = validPtsList{layer}(indexPairs(:, 2));

        try
            tform = estgeotform2d(matchedDistorted, matchedOriginal, ...
                parameters.TransformationType, ...
                'MaxNumTrials', obj.automaticOptions.estGeomTransform.MaxNumTrials, ...
                'Confidence',   obj.automaticOptions.estGeomTransform.Confidence, ...
                'MaxDistance',  obj.automaticOptions.estGeomTransform.MaxDistance);
        catch ME
            utils.dlgs.showErrorDialog(parentFig, ME, ...
                sprintf('estgeotform2d failed on file %d', layer));
            return;
        end

        % Store pairwise tform as a uniform ``affinetform2d``
        T = tform.A;
        pairwiseTforms{layer} = affinetform2d(T);

        % Decompose into translation / rotation / scale parameters
        translations(layer, :) = [T(1, 3), T(2, 3)];
        if ismember(parameters.TransformationType, {'rigid', 'similarity', 'affine'})
            rotations(layer) = atan2(T(2, 1), T(1, 1));
        end
        if ismember(parameters.TransformationType, {'similarity', 'affine'})
            scales(layer) = sqrt(T(1, 1)^2 + T(2, 1)^2);
        end
        if strcmp(parameters.TransformationType, 'affine')
            affine_params(layer, :) = [T(1, 1), T(1, 2), T(2, 1), T(2, 2)];
        end
    end

    % --- Compose cumulative parameters
    cumulativeTranslations = cumsum(translations, 1);
    cumulativeRotations    = cumsum(rotations,    1);
    cumulativeScales       = cumprod(scales,      1);

    % --- Interactive (GUI) or BatchOpt-driven (batch) smoothing
    useSmoothed = false;
    if ~parameters.useBatchMode
        [cumulativeTranslations, cumulativeRotations, cumulativeScales, useSmoothed, userCancelled] = ...
            interactiveSmoothingV2HDD(cumulativeTranslations, cumulativeRotations, ...
                cumulativeScales, affine_params, numFiles, parameters.TransformationType, parentFig);
        if userCancelled; return; end
    elseif obj.BatchOpt.SubtractRunningAverage
        [cumulativeTranslations, cumulativeRotations, cumulativeScales] = ...
            smoothCumulativeV2HDD(cumulativeTranslations, cumulativeRotations, ...
                cumulativeScales, numFiles, parameters.TransformationType, obj.BatchOpt);
        useSmoothed = true;
    end

    % --- Rebuild cumulative tforms (from smoothed parameters or raw chain)
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end
        pwb.updateText('Step 2/3: calculating cumulative tforms...');
    end

    cumulativeTforms{1} = affinetform2d(eye(3));
    for layer = 2:numFiles
        if useSmoothed
            T = pairwiseTforms{layer}.A;
            T(1, 3) = cumulativeTranslations(layer, 1);
            T(2, 3) = cumulativeTranslations(layer, 2);
            switch parameters.TransformationType
                case 'rigid'
                    theta = cumulativeRotations(layer);
                    R = [cos(theta), -sin(theta); sin(theta), cos(theta)];
                    T(1:2, 1:2) = R;
                case {'similarity', 'affine'}
                    theta = cumulativeRotations(layer);
                    s = cumulativeScales(layer);
                    R = [cos(theta), -sin(theta); sin(theta), cos(theta)];
                    T(1:2, 1:2) = s * R;
            end
        else
            T = pairwiseTforms{layer}.A * cumulativeTforms{layer - 1}.A;
        end
        cumulativeTforms{layer} = affinetform2d(T);

        % Round translations to integer pixels for pure-translation mode
        if strcmp(parameters.TransformationType, 'translation')
            cumulativeTforms{layer}.A(1, 3) = round(cumulativeTforms{layer}.A(1, 3));
            cumulativeTforms{layer}.A(2, 3) = round(cumulativeTforms{layer}.A(2, 3));
        end
    end
end

% --- Phase 2: determine apply canvas (corner projection - mirrors v2 in-memory)
if ~isempty(pwb)
    if pwb.getCancelState(); return; end
    pwb.updateText('Step 3/3: calculating canvas area...');
end

% Use per-file dimensions for accurate corner projection
Hmax = max(heightVec);  Wmax = max(widthVec);
if Hmax == 0; Hmax = Height; Wmax = Width; end

if strcmp(parameters.TransformationMode, 'extended')
    allX = zeros(4 * numFiles, 1);
    allY = zeros(4 * numFiles, 1);
    for k = 1:numFiles
        if isempty(cumulativeTforms{k}); continue; end
        H_k = heightVec(k); if H_k == 0; H_k = Hmax; end
        W_k = widthVec(k);  if W_k == 0; W_k = Wmax; end
        corners = [1, 1; W_k, 1; W_k, H_k; 1, H_k];
        warpedCorners = [corners, ones(4, 1)] * cumulativeTforms{k}.A';
        allX((k-1)*4+1:k*4) = warpedCorners(:, 1);
        allY((k-1)*4+1:k*4) = warpedCorners(:, 2);
    end
    minX = floor(min(allX));   maxX = ceil(max(allX));
    minY = floor(min(allY));   maxY = ceil(max(allY));
    outputWidth  = maxX - minX + 1;
    outputHeight = maxY - minY + 1;
    refImgSize   = imref2d([outputHeight, outputWidth], [minX, maxX], [minY, maxY]);
else                                                    % cropped
    refImgSize = imref2d([Hmax, Wmax]);
end

% --- Phase 3: read + warp + save each image to the output directory
if ~isempty(pwb)
    pwb.updateText('Step 3/3: warping + saving images...');
    pwb.setCurrentIteration(0);
    pwb.setIncrement(1);
    pwb.updateMaxNumberOfIterations(numFiles);
end

outputDir = fullfile(inputDir, obj.BatchOpt.HDD_OutputSubfolderName);
if ~isfolder(outputDir); mkdir(outputDir); end

saveOpt = saveOptionsFromExt(obj.BatchOpt.HDD_OutputFileExtension{1});
saveOpt.showWaitbar = false;
saveOpt.silent      = true;
saveOpt.overwrite   = true;

files     = imgDS.Files;
outputExt = lower(['.' obj.BatchOpt.HDD_OutputFileExtension{1}]);

% imwarp with OutputView=refImgSize already positions the warped content
% correctly within the full canvas (background = bgImage). No manual tiling.
parfor (layer = 1:numFiles, parforArg)
    if isempty(cumulativeTforms{layer}); continue; end
    try
        imgIn5D = io.loadImagesWrapper(files{layer}, readOpt);
    catch
        continue;
    end
    img2D = squeeze(imgIn5D(:,:,1,:,1));  % [H, W, C]

    iWarped = imwarp(img2D, cumulativeTforms{layer}, 'cubic', ...
        'OutputView', refImgSize, 'FillValues', double(bgImage));
    saveOneImage(iWarped, files{layer}, outputDir, outputExt, saveOpt);
    if ~isempty(pwb); pwb.increment(); end
end

% --- Persist alignment state as a struct so it can be replayed
alignStruct = struct();
alignStruct.pairwiseTforms   = pairwiseTforms;
alignStruct.cumulativeTforms = cumulativeTforms;
alignStruct.translations     = translations;
alignStruct.rotations        = rotations;
alignStruct.scales           = scales;
alignStruct.affine_params    = affine_params;
alignStruct.heightVec        = heightVec;
alignStruct.widthVec         = widthVec;
obj.shiftsX = alignStruct;
obj.shiftsY = [];

% --- Save tforms / params to file if requested
if obj.BatchOpt.SaveShiftsToFile
    saveV2HDDToFile(obj, id, parameters.useBatchMode, parentFig, alignStruct);
end

obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
    'HDD-aligned v2 using %s; type=%s, mode=%s, detector=%s, scale=%d, output → %s', ...
    parameters.method, parameters.TransformationType, parameters.TransformationMode, ...
    parameters.detectPointsType, parameters.imgDownsamplingFactor, outputDir));
end

% =============================================================================
function [featuresList, validPtsList, heightVec, widthVec, ok] = detectHDDFeaturesV2( ...
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

errorFlag = false(numFiles, 1);
errorMsgs = cell(numFiles, 1);
stepIncrement = max([1 floor(numFiles/10)]);

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
    if ~isempty(pwb) && mod(layer, stepIncrement) == 0; pwb.increment(); end
end

if any(errorFlag)
    firstErr = find(errorFlag, 1);
    utils.dlgs.showErrorDialog(parentFig, errorMsgs{firstErr}, 'HDD feature-based v2');
    return;
end
ok = true;
end

% =============================================================================
function [cumT, cumR, cumS] = smoothCumulativeV2HDD(cumT, cumR, cumS, numFiles, ...
    transformType, BatchOpt)
% Batch-mode running-average smoothing of the cumulative parameter arrays.
% Mirrors :func:`AutomaticFeatureBasedV2_Alignment`'s local
% ``smoothCumulativeV2`` so the HDD and in-memory v2 variants produce
% identical smoothing.

halfwidth = BatchOpt.SubtractRunningAverageStep{1};
if halfwidth > floor(numFiles/2 - 1)
    halfwidth = max(1, floor(numFiles/2 - 1));
end
% v1 BatchOpt-name mapping (v2 fields fall back to v1 stretch/shear)
excludeTranslation = BatchOpt.SubtractRunningAverageExcludeStretchPeaks{1};
excludeRotation    = BatchOpt.SubtractRunningAverageExcludeShearPeaks{1};
excludeScale       = BatchOpt.SubtractRunningAverageExcludeStretchPeaks{1};

if BatchOpt.SubtractRunningAverageFixStretch
    cumT(:, 1) = utils.align.runningAverageSmoothPoints(cumT(:, 1), halfwidth, excludeTranslation);
    cumT(:, 2) = utils.align.runningAverageSmoothPoints(cumT(:, 2), halfwidth, excludeTranslation);
end
if BatchOpt.SubtractRunningAverageFixShear && ismember(transformType, {'rigid', 'similarity', 'affine'})
    cumR = utils.align.runningAverageSmoothPoints(cumR, halfwidth, excludeRotation);
end
if BatchOpt.SubtractRunningAverageFixStretch && ismember(transformType, {'similarity', 'affine'})
    cumS = utils.align.runningAverageSmoothPoints(cumS, halfwidth, excludeScale) + 1;
end
end

% =============================================================================
function [cumT, cumR, cumS, useSmoothed, cancelled] = interactiveSmoothingV2HDD( ...
    cumT, cumR, cumS, affine_params, numFiles, transformType, parentFig)
% Interactive running-average smoothing dialog with parameter plots.
% Mirrors :func:`AutomaticFeatureBasedV2_Alignment`'s local
% ``interactiveSmoothingV2`` so the HDD and in-memory v2 variants share the
% same user flow (uses ``numFiles`` instead of ``Depth``).

useSmoothed = false;
cancelled = false;

% --- Subplot layout depends on transform type
switch transformType
    case 'translation';  noRows = 1; noCols = 1;
    case 'rigid';        noRows = 1; noCols = 2;
    case 'similarity';   noRows = 1; noCols = 3;
    case 'affine';       noRows = 2; noCols = 4;
end

% --- Plot original cumulative parameters (figure 125)
hFig125 = figure(125);
hFig125.Name = 'Cumulative alignment parameters';
plotCumulativeV2HDD(hFig125, noRows, noCols, cumT, cumR, cumS, affine_params, numFiles, transformType);

% --- First question: apply as-is or fix drifts?
questOpt.Icon = 'puffin_question';
questOpt.WindowStyle = 'normal';
answer1 = utils.dlgs.inputQuestDlg(parentFig, ...
    'Align the stack using detected displacements?', 'Align dataset', ...
    'Apply current values', 'Fix drifts', 'Quit alignment', 'Apply current values', questOpt);
if isempty(answer1) || strcmp(answer1, 'Quit alignment')
    cancelled = true;
    if isvalid(hFig125); close(hFig125); end
    return;
end
if strcmp(answer1, 'Apply current values')
    if isvalid(hFig125); close(hFig125); end
    return;
end

% --- "Fix drifts" smoothing loop
maxHalfwidth = max(1, floor(numFiles/2 - 1));
halfWidthDefault = min(25, maxHalfwidth);

prompts = {'Half-width of the averaging window'; 'Fix translation'; 'Exclude jumps higher than (0=off):'};
defAns = {struct('Spinner',true,'Value',halfWidthDefault,'Limits',[1 maxHalfwidth],'Step',1,'Round',true); ...
           true; ...
           struct('Spinner',true,'Value',0,'Limits',[0 Inf],'Step',1,'Round',false)};
dlgOpt.okBtnText = 'Continue';
dlgOpt.LabelPosition = 'left';
dlgOpt.WindowHeight = 210;

if ismember(transformType, {'rigid', 'similarity', 'affine'})
    prompts = [prompts; {'Fix rotations'; 'Exclude jumps higher than (0=off):'}];
    defAns  = [defAns;  {true; struct('Spinner',true,'Value',0,'Limits',[0 Inf],'Step',1,'Round',false)}];
end
if ismember(transformType, {'similarity', 'affine'})
    prompts = [prompts; {'Fix scales'; 'Exclude jumps higher than (0=off):'}];
    defAns  = [defAns;  {true; struct('Spinner',true,'Value',0,'Limits',[0 Inf],'Step',1,'Round',false)}];
    dlgOpt.WindowHeight = 260;
end

hFig126 = [];
notOk = true;
while notOk
    answer = utils.dlgs.inputUniversalDlg(parentFig, '', prompts, defAns, 'Correction settings', dlgOpt);
    if isempty(answer)
        cancelled = true;
        if isvalid(hFig125); close(hFig125); end
        if ~isempty(hFig126) && isvalid(hFig126); close(hFig126); end
        return;
    end

    halfwidth = answer{1};
    fixTranslation = answer{2};
    excludeTranslationJumps = answer{3};

    fixRotation = false;
    fixScale = false;
    excludeRotationJumps = 0;
    excludeScaleJumps = 0;
    idx = 4;
    if ismember(transformType, {'rigid', 'similarity', 'affine'})
        fixRotation = answer{idx};
        excludeRotationJumps = answer{idx + 1};
        idx = idx + 2;
    end
    if ismember(transformType, {'similarity', 'affine'})
        fixScale = answer{idx};
        excludeScaleJumps = answer{idx + 1};
    end

    % Apply smoothing
    smoothT = cumT;
    if fixTranslation
        smoothT(:, 1) = utils.align.runningAverageSmoothPoints(cumT(:, 1), halfwidth, excludeTranslationJumps);
        smoothT(:, 2) = utils.align.runningAverageSmoothPoints(cumT(:, 2), halfwidth, excludeTranslationJumps);
    end
    smoothR = cumR;
    if fixRotation
        smoothR = utils.align.runningAverageSmoothPoints(cumR, halfwidth, excludeRotationJumps);
    end
    smoothS = cumS;
    if fixScale
        smoothS = utils.align.runningAverageSmoothPoints(cumS, halfwidth, excludeScaleJumps) + 1;
    end

    % Plot smoothed parameters (figure 126)
    if isempty(hFig126) || ~isvalid(hFig126)
        hFig126 = figure(126);
    end
    hFig126.Name = 'Smoothed alignment parameters';
    hFig126.Position = hFig125.Position;
    plotCumulativeV2HDD(hFig126, noRows, noCols, smoothT, smoothR, smoothS, affine_params, numFiles, transformType);

    answer2 = utils.dlgs.inputQuestDlg(parentFig, ...
        'Align the stack using detected displacements?', 'Align dataset', ...
        'Apply values', 'Change window size', 'Quit alignment', 'Apply current values', questOpt);
    if isempty(answer2) || strcmp(answer2, 'Quit alignment')
        cancelled = true;
        if isvalid(hFig125); close(hFig125); end
        if isvalid(hFig126); close(hFig126); end
        return;
    end

    if strcmp(answer2, 'Apply values')
        cumT = smoothT;
        cumR = smoothR;
        cumS = smoothS;
        useSmoothed = true;
        notOk = false;
    else
        % "Change window size" - loop with updated defaults
        defAns{1} = struct('Spinner',true,'Value',halfwidth,'Limits',[1 maxHalfwidth],'Step',1,'Round',true);
        defAns{2} = fixTranslation;
        defAns{3} = struct('Spinner',true,'Value',excludeTranslationJumps,'Limits',[0 Inf],'Step',1,'Round',false);
        idx = 4;
        if ismember(transformType, {'rigid', 'similarity', 'affine'})
            defAns{idx}   = fixRotation;
            defAns{idx+1} = struct('Spinner',true,'Value',excludeRotationJumps,'Limits',[0 Inf],'Step',1,'Round',false);
            idx = idx + 2;
        end
        if ismember(transformType, {'similarity', 'affine'})
            defAns{idx}   = fixScale;
            defAns{idx+1} = struct('Spinner',true,'Value',excludeScaleJumps,'Limits',[0 Inf],'Step',1,'Round',false);
        end
    end
end

if isvalid(hFig125); close(hFig125); end
if ~isempty(hFig126) && isvalid(hFig126); close(hFig126); end
end

% =============================================================================
function plotCumulativeV2HDD(hFig, noRows, noCols, cumT, cumR, cumS, ...
    affine_params, numFiles, transformType)
% Plot cumulative V2 alignment parameters into the given figure.

figure(hFig);
clf(hFig);
subplot(noRows, noCols, 1);
plot(2:numFiles, cumT(2:end, 1), '.-', 2:numFiles, cumT(2:end, 2), '.-');
title('Translation'); legend('x-axis', 'y-axis', 'Location', 'best'); grid on;

if ismember(transformType, {'rigid', 'similarity', 'affine'})
    subplot(noRows, noCols, 2);
    plot(2:numFiles, cumR(2:end), '.-'); title('Rotations'); grid on;
end
if ismember(transformType, {'similarity', 'affine'})
    subplot(noRows, noCols, 3);
    plot(2:numFiles, cumS(2:end), '.-'); title('Scales'); grid on;
end
if strcmp(transformType, 'affine')
    subplot(noRows, noCols, 5);
    plot(2:numFiles, affine_params(2:end, 1), '.-');
    title('Affine a (scaling/shear/rotation, ~1)'); grid on;
    subplot(noRows, noCols, 6);
    plot(2:numFiles, affine_params(2:end, 2), '.-');
    title('Affine b (shear/rotation, ~0)'); grid on;
    subplot(noRows, noCols, 7);
    plot(2:numFiles, affine_params(2:end, 3), '.-');
    title('Affine c (shear/rotation, ~0)'); grid on;
    subplot(noRows, noCols, 8);
    plot(2:numFiles, affine_params(2:end, 4), '.-');
    title('Affine d (scaling/shear/rotation, ~1)'); grid on;
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
function saveV2HDDToFile(obj, id, useBatchMode, parentFig, alignStruct)
% Persist the v2 alignment struct to a ``.coefXY`` file via
% ``save(..., '-struct', ...)``.

if useBatchMode
    fn = obj.mibModel.I{id}.image.sliceName('Filename');
    [pathstr, name, ~] = fileparts(fn);
    fullPath = fullfile(pathstr, [name '_align.coefXY']);
elseif ~isempty(obj.view) && isvalid(obj.view) && isfield(obj.view.handles, 'saveShiftsXYpath')
    fullPath = obj.view.handles.saveShiftsXYpath.Value;
else
    return;
end
fprintf('Saving HDD v2 alignment struct to file: %s ... ', fullPath);
try
    save(fullPath, '-struct', 'alignStruct');
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
