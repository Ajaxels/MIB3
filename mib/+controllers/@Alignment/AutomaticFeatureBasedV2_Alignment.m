function AutomaticFeatureBasedV2_Alignment(obj, parameters)
% AUTOMATICFEATUREBASEDV2_ALIGNMENT - V2 feature-based alignment with parameter decomposition.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.AutomaticFeatureBasedV2_Alignment(parameters)
%
% Modern feature-based alignment (R2022b+). Compared to v1 this version:
%
% - Uses ``estgeotform2d`` returning :class:`rigidtform2d` /
%   :class:`simtform2d` / :class:`affinetform2d` natively; transforms are
%   composed cumulatively via the new ``.A`` (premultiply) property.
% - Stores **pairwise** transforms separately from **cumulative** ones and
%   decomposes each pairwise matrix into translation / rotation / scale
%   components so the running-average smoothing can act on each parameter
%   independently rather than on the raw matrix entries.
% - Downsamples by ``1 / imgDownsamplingFactorForAnalysis`` instead of
%   ``imgWidthForAnalysis``.
% - Computes the extended canvas via **corner projection** (transform the
%   four image corners through every cumulative tform and union their
%   bounding box) rather than from per-slice ``imref2d`` limits; gives a
%   tighter canvas.
% - Rounds translations to integer pixels when ``TransformationType ==
%   'translation'`` so the resulting stack stays free of resampling blur.
%
% Supported TransformationType: ``'translation'``, ``'rigid'``,
% ``'similarity'``, ``'affine'`` (matches MIB2 v2's allowed list).
%
% In GUI mode a diagnostic plot of the cumulative parameters is shown after
% step 1 and the user can choose **Apply current values** (no smoothing) or
% **Fix drifts** (interactive running-average smoothing loop with per-component
% control over translation, rotation and scale). In batch mode, smoothing
% runs straight from the ``BatchOpt.SubtractRunningAverage*`` fields when the
% flag is set.
%
% Input Arguments:
%   - **parameters** — struct produced by :meth:`continueBtn_Callback`.
%     Reads ``TransformationType``, ``TransformationMode``, ``colorCh``,
%     ``backgroundColor``, ``useBatchMode``, ``method``.

% Updates
%

id = obj.mibModel.getActiveId();

% Parent figure for any dialogs — ``obj.view`` is empty in batch mode
if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

parameters.detectPointsType = obj.BatchOpt.FeatureDetectorType{1};

% V2 allows only translation / rigid / similarity / affine
if ~ismember(parameters.TransformationType, {'translation', 'rigid', 'similarity', 'affine'})
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf(['TransformationType "%s" is not supported by the v2 algorithm.\n\n' ...
                'Supported types: translation, rigid, similarity, affine.'], ...
                parameters.TransformationType), 'Alignment');
    return;
end

[Height, Width, Depth] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));
if Depth < 2
    utils.dlgs.showErrorDialog(parentFig, ...
        'Automatic feature-based v2 alignment requires at least 2 slices.', 'Alignment');
    return;
end

% --- Backup the full MibDataset before any modification
backupOpt.id = id;
obj.mibModel.backup('mibDataset', 1, backupOpt);

% --- Background fill for the image warp
img5D = obj.mibModel.I{id}.image;
optionsGetData = struct('blockModeSwitch', 0);
if isnumeric(parameters.backgroundColor)
    bgImage = double(parameters.backgroundColor);
elseif strcmp(parameters.backgroundColor, 'black')
    bgImage = 0;
elseif strcmp(parameters.backgroundColor, 'white')
    bgImage = double(img5D.maxInt);
else    % 'mean'
    firstSlice = cell2mat(obj.mibModel.getData2D('image', 1, [], parameters.colorCh, optionsGetData));
    bgImage = mean(firstSlice(:));
end

% --- Downsampling factor (v2 distinctive parameter)
parameters.imgDownsamplingFactor = obj.automaticOptions.imgDownsamplingFactorForAnalysis;
ratio = 1 / parameters.imgDownsamplingFactor;

% --- Settings dialog (skipped in batch mode and on replay)
shiftsLoaded = ~isempty(obj.shiftsX) && isstruct(obj.shiftsX) && isfield(obj.shiftsX, 'cumulativeTforms');
if ~parameters.useBatchMode && ~shiftsLoaded
    status = obj.updateAutomaticOptions();
    if status == 0; return; end
    parameters.imgDownsamplingFactor = obj.automaticOptions.imgDownsamplingFactorForAnalysis;
    ratio = 1 / parameters.imgDownsamplingFactor;
end

% --- Replay path: shifts loaded from .coefXY file
shiftsLoaded = ~isempty(obj.shiftsX) && isstruct(obj.shiftsX) && isfield(obj.shiftsX, 'cumulativeTforms');
if shiftsLoaded
    pairwiseTforms      = obj.shiftsX.pairwiseTforms;
    cumulativeTforms    = obj.shiftsX.cumulativeTforms;
    translations        = obj.shiftsX.translations;
    rotations           = obj.shiftsX.rotations;
    scales              = obj.shiftsX.scales;
    affine_params       = obj.shiftsX.affine_params;
else
    pairwiseTforms   = cell(Depth, 1);
    cumulativeTforms = cell(Depth, 1);
    translations     = zeros(Depth, 2);
    rotations        = zeros(Depth, 1);
    scales           = ones(Depth, 1);
    affine_params    = zeros(Depth, 4);
    affine_params(:, [1 4]) = 1;
end

% --- Set up cancelable progress
pwb = [];
if obj.BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(Depth * 2, 'V2: detecting features & matching...', ...
        parentFig, 'Alignment', true);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

% --- Step 1: fit per-slice pairwise transforms (skipped when replayed)
if ~shiftsLoaded
    if ~isempty(pwb); pwb.updateText('Step 1/2: detecting & matching features...'); end
    [pairwiseTforms, translations, rotations, scales, affine_params, ok] = ...
        fitPerSliceV2(obj, Depth, parameters, ratio, optionsGetData, ...
        pairwiseTforms, translations, rotations, scales, affine_params, pwb, parentFig);
    if ~ok; return; end

    % --- Compose cumulative parameters
    cumulativeTranslations = cumsum(translations, 1);
    cumulativeRotations    = cumsum(rotations,    1);
    cumulativeScales       = cumprod(scales,      1);
    % cumulativeAffineParams = cumsum(affine_params, 1); will not correct affine, 
    % so commulative affines are not needed, but will show them as plots

    % --- Interactive (GUI) or BatchOpt-driven (batch) smoothing
    useSmoothed = false;
    if ~parameters.useBatchMode
        [cumulativeTranslations, cumulativeRotations, cumulativeScales, useSmoothed, userCancelled] = ...
            interactiveSmoothingV2(cumulativeTranslations, cumulativeRotations, ...
                cumulativeScales, affine_params, Depth, parameters.TransformationType, parentFig);
        if userCancelled; return; end
    elseif obj.BatchOpt.SubtractRunningAverage
        [cumulativeTranslations, cumulativeRotations, cumulativeScales] = ...
            smoothCumulativeV2(cumulativeTranslations, cumulativeRotations, ...
                cumulativeScales, Depth, parameters.TransformationType, obj.BatchOpt);
        useSmoothed = true;
    end

    % --- Rebuild cumulative tforms (from smoothed parameters or raw chain)
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end
        pwb.updateText('Step 1/2: calculating cumulative tforms...'); 
    end

    cumulativeTforms{1} = affinetform2d(eye(3));
    for layer = 2:Depth
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

% --- Step 2: determine apply canvas
if ~isempty(pwb)
    if pwb.getCancelState(); return; end
    pwb.updateText('Step 2/2: calculating canvas area...'); 
end

if strcmp(parameters.TransformationMode, 'extended')
    % Project the four image corners through every cumulative tform and union
    corners = [1, 1; Width, 1; Width, Height; 1, Height];
    allX = zeros(4 * Depth, 1);
    allY = zeros(4 * Depth, 1);
    for k = 1:Depth
        warpedCorners = [corners, ones(4, 1)] * cumulativeTforms{k}.A';
        allX((k-1)*4+1:k*4) = warpedCorners(:, 1);
        allY((k-1)*4+1:k*4) = warpedCorners(:, 2);
    end
    minX = floor(min(allX));   maxX = ceil(max(allX));
    minY = floor(min(allY));   maxY = ceil(max(allY));
    outputWidth  = maxX - minX + 1;
    outputHeight = maxY - minY + 1;
    refImgSize   = imref2d([outputHeight, outputWidth], [minX, maxX], [minY, maxY]);
else                                                  % cropped
    refImgSize = imref2d([Height, Width]);
    minX = 0;
    minY = 0;
end

% --- Step 2: apply transforms
if ~isempty(pwb)
    if pwb.getCancelState(); return; end
    pwb.updateText('Step 2/2: warping...'); 
    pwb.updateIndeterminateMode(true);
end
ok = applyV2(obj, id, Depth, cumulativeTforms, refImgSize, minX, minY, ...
    bgImage, strcmp(parameters.TransformationMode, 'extended'), pwb);
if ~ok; return; end

% --- Bounding-box shift (extended mode only)
if strcmp(parameters.TransformationMode, 'extended')
    maxXshift = minX;
    maxYshift = minY;
    maxZshift = 0;
    ds = obj.mibModel.I{id};
    switch ds.orientation
        case 3
            maxXshift = maxXshift * ds.image.pixSize.x;
            maxYshift = maxYshift * ds.image.pixSize.y;
        case 2
            maxZshift = maxXshift * ds.image.pixSize.z;
            maxYshift = maxYshift * ds.image.pixSize.y;
            maxXshift = 0;
        case 1
            maxZshift = maxXshift * ds.image.pixSize.z;
            maxXshift = maxYshift * ds.image.pixSize.x;
            maxYshift = 0;
    end
    obj.mibModel.I{id}.updateBoundingBox([], [maxXshift, maxYshift, maxZshift]);
end

% --- Persist alignment state as a struct so it can replayed
alignStruct = struct();
alignStruct.pairwiseTforms   = pairwiseTforms;
alignStruct.cumulativeTforms = cumulativeTforms;
alignStruct.translations     = translations;
alignStruct.rotations        = rotations;
alignStruct.scales           = scales;
alignStruct.affine_params    = affine_params;
obj.shiftsX = alignStruct;
obj.shiftsY = [];

% --- Save tforms / rbMatrix to file if requested
if obj.BatchOpt.SaveShiftsToFile
    saveV2ToFile(obj, id, parameters.useBatchMode, parentFig, alignStruct);
end

obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
    'Aligned using %s; type=%s, mode=%s, detector=%s, imgScale=%d, rotation=%d', ...
    parameters.method, parameters.TransformationType, parameters.TransformationMode, ...
    parameters.detectPointsType, parameters.imgDownsamplingFactor, ...
    1 - obj.automaticOptions.rotationInvariance));

% keepBackup=true so the 'mibDataset' snapshot stored by backup() above is
% not wiped by listener_newDataset.
notify(obj.mibModel, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)));
notify(obj.mibModel, 'ShowImage');
end

% =============================================================================
function [pairwiseTforms, translations, rotations, scales, affine_params, ok] = ...
    fitPerSliceV2(obj, Depth, parameters, ratio, optionsGetData, ...
    pairwiseTforms, translations, rotations, scales, affine_params, pwb, parentFig)
% Walk slices 2..Depth: detect features on each consecutive pair,
% RANSAC-fit a 2-D transform via ``estgeotform2d``, store the pairwise
% transform plus its decomposed translation / rotation / scale components.

ok = false;

original = cell2mat(obj.mibModel.getData2D('image', 1, [], parameters.colorCh, optionsGetData));
if ratio ~= 1; original = imresize(original, ratio, 'bicubic'); end
ptsOriginal = utils.align.detectFeatures(original, parameters.detectPointsType, obj.automaticOptions);
if isempty(ptsOriginal)
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('No features detected on slice 1 with "%s".', parameters.detectPointsType), ...
        'Alignment');
    return;
end
if ~strcmp(parameters.detectPointsType, 'Oriented FAST and rotated BRIEF (ORB)')
    [featuresOriginal, validPtsOriginal] = extractFeatures(original, ptsOriginal, ...
        'Upright', obj.automaticOptions.rotationInvariance);
else
    [featuresOriginal, validPtsOriginal] = extractFeatures(original, ptsOriginal);
end
validPtsOriginal.Location = validPtsOriginal.Location / ratio;

% update progress bar
if ~isempty(pwb)
    stepIncrement = max([1 floor(Depth/10)]);
    pwb.updateMaxNumberOfIterations(Depth);
    pwb.setCurrentIteration(0);
    pwb.setIncrement(stepIncrement);
end

for layer = 2:Depth
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end
        if mod(layer, stepIncrement)==0; pwb.increment(); end
    end

    distorted = cell2mat(obj.mibModel.getData2D('image', layer, [], parameters.colorCh, optionsGetData));
    if ratio ~= 1; distorted = imresize(distorted, ratio, 'bicubic'); end

    ptsDistorted = utils.align.detectFeatures(distorted, parameters.detectPointsType, obj.automaticOptions);
    if isempty(ptsDistorted)
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf('No features detected on slice %d with "%s".', layer, parameters.detectPointsType), ...
            'Alignment');
        return;
    end
    if ~strcmp(parameters.detectPointsType, 'Oriented FAST and rotated BRIEF (ORB)')
        [featuresDistorted, validPtsDistorted] = extractFeatures(distorted, ptsDistorted, ...
            'Upright', obj.automaticOptions.rotationInvariance);
    else
        [featuresDistorted, validPtsDistorted] = extractFeatures(distorted, ptsDistorted);
    end
    validPtsDistorted.Location = validPtsDistorted.Location / ratio;

    indexPairs = matchFeatures(featuresOriginal, featuresDistorted);
    if isempty(indexPairs) || size(indexPairs, 1) < 3
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf(['Not enough matched points between slice %d and %d (%d found, ≥3 required).\n\n' ...
                    'Adjust feature-detector settings to produce more points.'], ...
                    layer - 1, layer, size(indexPairs, 1)), 'Alignment');
        return;
    end
    matchedOriginal  = validPtsOriginal(indexPairs(:, 1));
    matchedDistorted = validPtsDistorted(indexPairs(:, 2));

    % % Show putative point matches.
    % figure;
    % matchedOriginalTemp = matchedOriginal;
    % matchedOriginalTemp.Location = matchedOriginalTemp.Location * ratio;
    % matchedDistortedTemp = matchedDistorted;
    % matchedDistortedTemp.Location = matchedDistortedTemp.Location * ratio;
    % showMatchedFeatures(original,distorted,matchedOriginalTemp,matchedDistortedTemp);
    % title('Putatively matched points (including outliers)');

    % https://se.mathworks.com/help/images/migrate-geometric-transformations-to-premultiply-convention.html?requestedDomain=

    try
        tform = estgeotform2d(matchedDistorted, matchedOriginal, ...
            parameters.TransformationType, ...
            'MaxNumTrials', obj.automaticOptions.estGeomTransform.MaxNumTrials, ...
            'Confidence',   obj.automaticOptions.estGeomTransform.Confidence, ...
            'MaxDistance',  obj.automaticOptions.estGeomTransform.MaxDistance);
    catch ME
        utils.dlgs.showErrorDialog(parentFig, ME, 'AutomaticFeatureBasedV2_Alignment', ...
            sprintf('estgeotform2d failed on slice %d', layer));
        return;
    end

    % Store pairwise transform as a uniform ``affinetform2d`` (works for
    % translation / rigid / similarity / affine output types).
    T = tform.A;
    pairwiseTforms{layer} = affinetform2d(T);

    % % debug preview
    % figure(1234);
    % showMatchedFeatures(original,distorted,matchedOriginal,matchedDistorted);
    % title("Matched Points");
    % figure(1235);
    % inlierPtsDistorted = matchedDistorted(inlierIdx,:);
    % inlierPtsOriginal  = matchedOriginal(inlierIdx,:);
    % showMatchedFeatures(original,distorted,inlierPtsOriginal,inlierPtsDistorted);
    % title("Removed outliers");

    % T = [ a,  b,  tx ]
    %     [ c,  d,  ty ]
    %     [ 0,  0,   1 ]
    % the top-left 2x2 block ([a, b; c, d]) handles scaling, rotation, and shear
    % the third column ([tx, ty]) handles translation.
    % the last row is always [0, 0, 1] for 2D transformations
    %
    % TRANSLATION:
    % T = [ 1,  0,  tx ]
    %     [ 0,  1,  ty ]
    %     [ 0,  0,   1 ]
    % where
    % T(1,1) = a = 1: No scaling or rotation (identity)
    % T(1,2) = b = 0: No shear or rotation
    % T(2,1) = c = 0: No shear or rotation
    % T(2,2) = d = 1: No scaling or rotation (identity)
    % T(1,3) = tx: Translation in x-direction
    % T(2,3) = ty: Translation in y-direction
    %
    % RIGID (preserves distances and angles (rotation + translation, no scaling))
    % T = [ cos(θ), -sin(θ),  tx ]
    %     [ sin(θ),  cos(θ),  ty ]
    %     [      0,       0,   1 ]
    % where
    % T(1,1) = a = cos(θ): Cosine of rotation angle.
    % T(1,2) = b = -sin(θ): Negative sine of rotation angle.
    % T(2,1) = c = sin(θ): Sine of rotation angle.
    % T(2,2) = d = cos(θ): Cosine of rotation angle.
    %
    % SIMILARITY (preserves angles (rotation + uniform scaling + translation))
    %   T = [ s*cos(θ), -s*sin(θ),  tx ]
    %       [ s*sin(θ),  s*cos(θ),  ty ]
    %       [        0,         0,   1 ]
    % where
    % T(1,1) = a = s * cos(θ): Scale times cosine of rotation angle.
    % T(1,2) = b = -s * sin(θ): Negative scale times sine of rotation angle.
    % T(2,1) = c = s * sin(θ): Scale times sine of rotation angle.
    % T(2,2) = d = s * cos(θ): Scale times cosine of rotation angle.
    %
    % AFFINE (full affine transformation (scaling, rotation, shear, translation))
    % T = [ a,  b,  tx ]
    %     [ c,  d,  ty ]
    %     [ 0,  0,   1 ]
    % T(1,1) = a: General scaling/shear/rotation component (diagonal ~1 for identity-like).
    % T(1,2) = b: Shear/rotation component (off-diagonal ~0 for identity-like).
    % T(2,1) = c: Shear/rotation component (off-diagonal ~0 for identity-like).
    % T(2,2) = d: General scaling/shear/rotation component (diagonal ~1 for identity-like).

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

    % Roll forward
    featuresOriginal = featuresDistorted;
    validPtsOriginal = validPtsDistorted;
end
ok = true;
end

% =============================================================================
function [cumT, cumR, cumS] = smoothCumulativeV2(cumT, cumR, cumS, Depth, ...
    transformType, BatchOpt)
% Apply running-average smoothing to the cumulative parameter arrays. The
% interactive figure-driven flow from MIB2 is replaced with straight
% BatchOpt-driven smoothing: each subtract flag enables smoothing of the
% corresponding parameter set; ``SubtractRunningAverageStep`` drives the
% half-width; per-parameter exclude-jump thresholds come from
% ``SubtractRunningAverage*Jumps`` fields (legacy names with stretch/shear
% are mapped onto the v2 names so the existing BatchOpt knobs work).

halfwidth = BatchOpt.SubtractRunningAverageStep{1};
if halfwidth > floor(Depth/2 - 1)
    halfwidth = max(1, floor(Depth/2 - 1));
end
% v1-vs-v2 BatchOpt name mapping (v2 fields fall back to v1 stretch/shear)
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
function [cumT, cumR, cumS, useSmoothed, cancelled] = interactiveSmoothingV2( ...
    cumT, cumR, cumS, affine_params, Depth, transformType, parentFig)
% Interactive running-average smoothing dialog with parameter plots.
% Plots cumulative alignment parameters, asks the user whether to apply
% the current values or fix drifts with running-average smoothing.
% When "Fix drifts" is chosen, loops through a settings dialog where
% the user adjusts the smoothing half-width and per-component flags
% until satisfied.

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
plotCumulativeV2(hFig125, noRows, noCols, cumT, cumR, cumS, affine_params, Depth, transformType);

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
maxHalfwidth = max(1, floor(Depth/2 - 1));
halfWidthDefault = min(25, maxHalfwidth);

prompts = {'Half-width of the averaging window'; 'Fix translation'; 'Exclude jumps higher than (0=off):'};
defAns = {struct('Spinner',true,'Value',halfWidthDefault,'Limits',[1 maxHalfwidth],'Step',1,'Round',true); ...
           true; ...
           struct('Spinner',true,'Value',0,'Limits',[0 Inf],'Step',1,'Round',false)};

if ismember(transformType, {'rigid', 'similarity', 'affine'})
    prompts = [prompts; {'Fix rotations'; 'Exclude jumps higher than (0=off):'}];
    defAns = [defAns; {true; struct('Spinner',true,'Value',0,'Limits',[0 Inf],'Step',1,'Round',false)}];
end
if ismember(transformType, {'similarity', 'affine'})
    prompts = [prompts; {'Fix scales'; 'Exclude jumps higher than (0=off):'}];
    defAns = [defAns; {true; struct('Spinner',true,'Value',0,'Limits',[0 Inf],'Step',1,'Round',false)}];
end

dlgOpt.okBtnText = 'Continue';
dlgOpt.LabelPosition = 'left';
dlgOpt.WindowHeight = 210;

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
    plotCumulativeV2(hFig126, noRows, noCols, smoothT, smoothR, smoothS, affine_params, Depth, transformType);

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
        % "Change window size" — loop with updated defaults
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
function plotCumulativeV2(hFig, noRows, noCols, cumT, cumR, cumS, ...
    affine_params, Depth, transformType)
% Plot cumulative V2 alignment parameters into the given figure.

figure(hFig);
clf(hFig);
subplot(noRows, noCols, 1);
plot(2:Depth, cumT(2:end, 1), '.-', 2:Depth, cumT(2:end, 2), '.-');
title('Translation'); legend('x-axis', 'y-axis', 'Location', 'best'); grid on;

if ismember(transformType, {'rigid', 'similarity', 'affine'})
    subplot(noRows, noCols, 2);
    plot(2:Depth, cumR(2:end), '.-'); title('Rotations'); grid on;
end
if ismember(transformType, {'similarity', 'affine'})
    subplot(noRows, noCols, 3);
    plot(2:Depth, cumS(2:end), '.-'); title('Scales'); grid on;
end
if strcmp(transformType, 'affine')
    subplot(noRows, noCols, 5);
    plot(2:Depth, affine_params(2:end, 1), '.-');
    title('Affine a (scaling/shear/rotation, ~1)'); grid on;
    subplot(noRows, noCols, 6);
    plot(2:Depth, affine_params(2:end, 2), '.-');
    title('Affine b (shear/rotation, ~0)'); grid on;
    subplot(noRows, noCols, 7);
    plot(2:Depth, affine_params(2:end, 3), '.-');
    title('Affine c (shear/rotation, ~0)'); grid on;
    subplot(noRows, noCols, 8);
    plot(2:Depth, affine_params(2:end, 4), '.-');
    title('Affine d (scaling/shear/rotation, ~1)'); grid on;
end
end

% =============================================================================
function ok = applyV2(obj, id, Depth, cumulativeTforms, refImgSize, ...
    dxCanvas, dyCanvas, bgImage, isExtended, pwb)
% Warp image + service layers using the cumulative tforms and the
% pre-computed reference image size. In extended mode ``refImgSize``
% carries the union canvas's world limits; in cropped mode it's the
% original ``imref2d([H, W])``. Annotations are pushed through the
% same cumulative tform; in extended mode they are additionally shifted
% by ``(-dxCanvas, -dyCanvas)`` so they land in the new canvas frame.

ok = false;
optionsGetData = struct('blockModeSwitch', 0);
ds       = obj.mibModel.I{id};
img5D    = ds.image;
nColors  = img5D.colors;
nTime    = img5D.time;
imgClass = class(img5D.data);
isLabels63 = isa(ds.labels, 'core.MibLabels63');

newH = refImgSize.ImageSize(1);
newW = refImgSize.ImageSize(2);
canvasChanged = isExtended && (newH ~= img5D.height || newW ~= img5D.width);

% update progress bar
if ~isempty(pwb)
    %stepIncrement = max([1 floor(Depth/10)]);
    %pwb.updateMaxNumberOfIterations(Depth);
    %pwb.setCurrentIteration(0);
    %pwb.setIncrement(stepIncrement);
    pwb.updateText('Step 2/2: warping the image layer...');
end

% --- Warp every image slice
Iout = zeros(newH, newW, Depth, nColors, imgClass) + cast(bgImage, imgClass);
for layer = 1:Depth
    slice2D = cell2mat(obj.mibModel.getData2D('image', layer, [], NaN, optionsGetData));
    warped  = imwarp(slice2D, cumulativeTforms{layer}, 'cubic', ...
        'OutputView', refImgSize, 'FillValues', double(bgImage));
    Iout(:, :, layer, :) = reshape(warped, newH, newW, 1, nColors);
end

if canvasChanged
    % Replace the image canvas atomically
    img5D.data   = reshape(Iout, [newH, newW, Depth, nColors, nTime]);
    img5D.height    = newH;
    img5D.width     = newW;
    img5D.dim_yxzct = [newH, newW, Depth, nColors, nTime];

    ds.dim_yxzct = img5D.dim_yxzct;
    oldSlices = ds.slices;
    ds.slices{1} = [1, newH];
    ds.slices{2} = [1, newW];
    ds.slices{ds.orientation} = repmat(oldSlices{ds.orientation}(1), 1, 2);
else
    % Cropped mode — write back per slice
    for layer = 1:Depth
        obj.mibModel.setData2D(squeeze(Iout(:, :, layer, :)), 'image', layer, [], NaN, optionsGetData);
    end
end
clear Iout;

% --- Service layers
if ~isempty(pwb)
    pwb.updateText('Step 2/2: warping the service layers...');
end

if isLabels63
    warpAndWriteServiceCanvas(obj, id, 'everything', cumulativeTforms, refImgSize, ...
        canvasChanged, Depth, nTime, 'uint8', 0);
else
    if ds.modelExist
        warpAndWriteServiceCanvas(obj, id, 'labels', cumulativeTforms, refImgSize, ...
            canvasChanged, Depth, nTime, class(ds.labels.data), NaN);
    end
    if ds.maskExist
        warpAndWriteServiceCanvas(obj, id, 'mask', cumulativeTforms, refImgSize, ...
            canvasChanged, Depth, nTime, 'uint8', 0);
    end
    if ds.enableSelection
        warpAndWriteServiceCanvas(obj, id, 'selection', cumulativeTforms, refImgSize, ...
            canvasChanged, Depth, nTime, 'uint8', NaN);
    end
end

% --- Annotations
if ds.annotations.getLabelsNumber() > 0
    for layer = 1:Depth
        [labelsList, labelValues, labelPositions, indices] = ds.getSliceLabels(layer);
        if isempty(labelsList); continue; end
        [labelPositions(:, 2), labelPositions(:, 3)] = transformPointsForward( ...
            cumulativeTforms{layer}, labelPositions(:, 2), labelPositions(:, 3));
        if isExtended
            labelPositions(:, 2) = labelPositions(:, 2) - dxCanvas;
            labelPositions(:, 3) = labelPositions(:, 3) - dyCanvas;
        end
        ds.annotations.updateLabels(indices, labelsList, labelPositions, labelValues);
    end
end
ok = true;
end

% =============================================================================
function warpAndWriteServiceCanvas(obj, id, layerType, cumulativeTforms, ...
    refImgSize, canvasChanged, Depth, nTime, dataClass, colArg)
% Warp a single service layer (nearest neighbour) with the same
% ``OutputView`` as the image, pre-resizing the layer container when the
% canvas grew (``canvasChanged`` true).

src = obj.mibModel.getData4D(layerType, [], colArg);
src = squeeze(cell2mat(src));
newH = refImgSize.ImageSize(1);
newW = refImgSize.ImageSize(2);
out3D = zeros(newH, newW, Depth, dataClass);
for layer = 1:Depth
    out3D(:, :, layer) = imwarp(src(:, :, layer), cumulativeTforms{layer}, ...
        'nearest', 'OutputView', refImgSize, 'FillValues', 0);
end

if canvasChanged
    switch layerType
        case 'labels';     ds = obj.mibModel.I{id}.labels;
        case 'mask';       ds = obj.mibModel.I{id}.mask;
        case 'selection';  ds = obj.mibModel.I{id}.selection;
        case 'everything'; ds = obj.mibModel.I{id}.labels;
    end
    ds.data   = zeros([newH, newW, Depth, nTime], dataClass);
    ds.height    = newH;
    ds.width     = newW;
    if isprop(ds, 'depth'); ds.depth = Depth; end
    ds.dim_yxzct = [newH, newW, Depth, 1, nTime];
end
obj.mibModel.setData4D(out3D, layerType, [], colArg);
end

% =============================================================================
function saveV2ToFile(obj, id, useBatchMode, parentFig, alignStruct)
% Save the v2 alignment struct (pairwise + cumulative tforms + decomposed
% parameters) to a ``.coefXY`` file via ``save(..., '-struct', ...)``.

if useBatchMode
    fn = obj.mibModel.I{id}.image.sliceName('Filename');
    [pathstr, name, ~] = fileparts(fn);
    fullPath = fullfile(pathstr, [name '_align.coefXY']);
elseif ~isempty(obj.view) && isvalid(obj.view) && isfield(obj.view.handles, 'saveShiftsXYpath')
    fullPath = obj.view.handles.saveShiftsXYpath.Value;
else
    return;
end
fprintf('Saving v2 alignment struct to file: %s ... ', fullPath);
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
