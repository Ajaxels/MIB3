function AutomaticFeatureBased_Alignment(obj, parameters)
% AUTOMATICFEATUREBASED_ALIGNMENT - Align a stack with automatically detected feature matches.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.AutomaticFeatureBased_Alignment(parameters)
%
% Walks the stack slice by slice, detects features with the user-selected
% detector (:func:`utils.align.detectFeatures`), extracts descriptors,
% matches them, and fits a robust 2-D transform with ``estgeotform2d``
% (MSAC inlier selection). Transforms are composed cumulatively so each
% slice is aligned to slice 1's coordinate frame.
%
% Two apply modes (chosen via ``parameters.TransformationMode``):
%
% - ``'cropped'``  — original canvas preserved; each slice warped with
%   ``imwarp(..., 'OutputView', imref2d([H, W]))`` and written back via
%   :meth:`setData2D`.
% - ``'extended'`` — canvas grows to fit the union of all warped slices;
%   the image canvas is replaced atomically and service-layer containers
%   are pre-resized before :meth:`setData4D`.
%
% Running-average smoothing of the per-slice scale + shear parameters is
% available in two modes: interactive (GUI) and batch.  In interactive mode
% the raw scaling and shear curves are plotted (figure 125) and the user
% chooses whether to apply smoothing and tunes the half-width / exclude-peaks
% settings in a loop until satisfied; the smoothed values are written back
% into ``tformMatrix{*}.T`` *before* the apply phase.  In batch mode
% smoothing runs automatically from the ``BatchOpt.SubtractRunningAverage*``
% fields when ``BatchOpt.SubtractRunningAverage`` is set.
%
% Cancellation: a :class:`core.PoolWaitbar` is constructed with
% ``Cancelable = true`` whenever ``BatchOpt.showWaitbar`` is set; cancel
% state is polled at each phase boundary and immediately before each
% write. The ``automaticOptions`` settings dialog from MIB2 is currently
% skipped — the algorithm runs with whatever defaults already exist in
% ``obj.automaticOptions``.
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

% Resolve the feature detector type from the widget / BatchOpt
parameters.detectPointsType = obj.BatchOpt.FeatureDetectorType{1};

[Height, Width, Depth] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));
if Depth < 2
    utils.dlgs.showErrorDialog(parentFig, ...
        'Automatic feature-based alignment requires at least 2 slices.', 'AutomaticFeatureBased_Alignment');
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

% --- Downsampling ratio: match the size used by previewFeaturesBtn
if obj.automaticOptions.imgWidthForAnalysis == 0
    parameters.imgWidthForAnalysis = Width;
else
    parameters.imgWidthForAnalysis = obj.automaticOptions.imgWidthForAnalysis;
end

% --- Replay path: shifts loaded from .coefXY file
shiftsLoaded = ~isempty(obj.shiftsX) && iscell(obj.shiftsX);
if shiftsLoaded
    tformMatrix = obj.shiftsX;
    rbMatrix    = obj.shiftsY;
else
    tformMatrix = cell(Depth, 1);
    rbMatrix    = cell(Depth, 1);
end

% --- Settings dialog (skipped in batch mode and on replay)
if ~parameters.useBatchMode && ~shiftsLoaded
    status = obj.updateAutomaticOptions();
    if status == 0; return; end
    if obj.automaticOptions.imgWidthForAnalysis == 0
        parameters.imgWidthForAnalysis = Width;
    else
        parameters.imgWidthForAnalysis = obj.automaticOptions.imgWidthForAnalysis;
    end
end

% --- Set up cancelable progress
pwb = [];
if obj.BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(Depth * 2, 'Detecting features & matching...', parentFig, 'Alignment', true);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

% --- Step 1: fit per-slice cumulative transforms (skipped when replayed)
if ~shiftsLoaded
    if ~isempty(pwb); pwb.updateText('Step 1/2: detecting & matching features...'); end
    [tformMatrix, ok] = fitPerSliceFeatureTransforms(obj, id, Depth, Width, ...
        parameters, tformMatrix, optionsGetData, pwb, parentFig);
    if ~ok; return; end

    % --- Interactive (GUI) or BatchOpt-driven (batch) smoothing of stretch + shear
    if ~parameters.useBatchMode
        [tformMatrix, userCancelled] = interactiveSmoothingV1(tformMatrix, Depth, parentFig);
        if userCancelled; return; end
    elseif obj.BatchOpt.SubtractRunningAverage
        tformMatrix = smoothTformChain(tformMatrix, Depth, obj.BatchOpt);
    end
end

% Verify we have at least one usable transform
anyTform = any(~cellfun(@isempty, tformMatrix));
if ~anyTform
    utils.dlgs.showErrorDialog(parentFig, 'No transforms were produced — check feature detector settings.', 'Alignment');
    return;
end

% --- Step 2: apply transforms
if ~isempty(pwb)
    if pwb.getCancelState(); return; end
    pwb.updateText('Step 2/2: warping...'); 
    %pwb.updateIndeterminateMode(true);
end

refImgSize = imref2d([Height, Width]);
if strcmp(parameters.TransformationMode, 'cropped')
    if ~isempty(pwb); pwb.updateText('Step 2/2: warping (cropped)...'); end
    applyCroppedMode(obj, id, Depth, tformMatrix, refImgSize, bgImage, pwb);
    rbMatrix(:) = {refImgSize};
    dxCanvas = 0;
    dyCanvas = 0;
else
    if ~isempty(pwb); pwb.updateText('Step 2/2: warping (extended)...'); end
    [dxCanvas, dyCanvas, rbMatrix] = applyExtendedMode(obj, id, Depth, ...
        tformMatrix, rbMatrix, bgImage, pwb);
    if isempty(dxCanvas); return; end
end

% --- Transform annotations
if obj.mibModel.I{id}.annotations.getLabelsNumber() > 0
    relocateAnnotations(obj, id, Depth, tformMatrix, rbMatrix, ...
        strcmp(parameters.TransformationMode, 'cropped'), dxCanvas, dyCanvas);
end

% --- Bounding-box shift (extended mode only)
if strcmp(parameters.TransformationMode, 'extended')
    maxXshift = dxCanvas;
    maxYshift = dyCanvas;
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

% --- Persist transforms so subsequent runs / save-shifts pick them up
obj.shiftsX = tformMatrix;
obj.shiftsY = rbMatrix;

% --- Save tforms / rbMatrix to file if requested
if obj.BatchOpt.SaveShiftsToFile
    saveTformsToFile(obj, id, parameters.useBatchMode, parentFig, 'feature-based alignment');
end

obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
    'Aligned using %s; type=%s, mode=%s, detector=%s, imgWidth=%d, rotation=%d', ...
    parameters.method, parameters.TransformationType, parameters.TransformationMode, ...
    parameters.detectPointsType, parameters.imgWidthForAnalysis, ...
    1 - obj.automaticOptions.rotationInvariance));

% keepBackup=true so the 'mibDataset' snapshot stored by backup() above is
% not wiped by listener_newDataset.
notify(obj.mibModel, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)));
notify(obj.mibModel, 'ShowImage');
end

% =============================================================================
function [tformMatrix, ok] = fitPerSliceFeatureTransforms(obj, ~, Depth, Width, ...
    parameters, tformMatrix, optionsGetData, pwb, parentFig)
% Walk slices 2..Depth: detect features on the previous + current slice,
% match descriptors, RANSAC-fit a 2-D transform with ``estgeotform2d``,
% and compose with the previous slice's cumulative transform. The first
% slice's reference image is kept across iterations to avoid re-detecting
% it; only the new "distorted" slice is detected each pass.

ok = false;
ratio = parameters.imgWidthForAnalysis / Width;

% Detect features on slice 1 (the reference)
original = cell2mat(obj.mibModel.getData2D('image', 1, [], parameters.colorCh, optionsGetData));
if ratio ~= 1; original = imresize(original, ratio, 'bicubic'); end
ptsOriginal = utils.align.detectFeatures(original, parameters.detectPointsType, obj.automaticOptions);
if isempty(ptsOriginal)
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf(['No features detected on slice 1 with "%s".\n\n' ...
                'Adjust the detector settings and retry.'], parameters.detectPointsType), ...
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

% Fix RANSAC seed so estgeotform2d is reproducible across runs and
% matches the HDD variant for direct comparison.
rng(0, 'twister');

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
            sprintf(['No features detected on slice %d with "%s".\n\n' ...
                    'Adjust the detector settings and retry.'], ...
                    layer, parameters.detectPointsType), 'Alignment');
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
    if isempty(indexPairs)
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf('No matching descriptors between slice %d and %d. Adjust detector settings.', layer - 1, layer), ...
            'Alignment');
        return;
    end
    matchedOriginal  = validPtsOriginal(indexPairs(:, 1));
    matchedDistorted = validPtsDistorted(indexPairs(:, 2));

    % Show putative point matches.
    %                     figure;
    %                     matchedOriginalTemp = matchedOriginal;
    %                     matchedOriginalTemp.Location = matchedOriginalTemp.Location * ratio;
    %                     matchedDistortedTemp = matchedDistorted;
    %                     matchedDistortedTemp.Location = matchedDistortedTemp.Location * ratio;
    %                     showMatchedFeatures(original,distorted,matchedOriginalTemp,matchedDistortedTemp);
    %                     title('Putatively matched points (including outliers)');

    if size(matchedOriginal, 1) < 3
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf(['Only %d matched points between slice %d and %d — at least 3 are required.\n\n' ...
                    'Adjust feature-detector settings to produce more points.'], size(matchedOriginal, 1), layer - 1, layer), ...
                    'Alignment');
        return;
    end

    try
        % Find a transformation corresponding to the matching point pairs using the
        % statistically robust M-estimator SAmple Consensus (MSAC) algorithm, which
        % is a variant of the RANSAC algorithm. It removes outliers while computing
        % the transformation matrix. You may see varying results of the transformation
        % computation because of the random sampling employed by the MSAC algorithm.
        [tform, inlierIdx] = estgeotform2d(matchedDistorted, matchedOriginal, ...
            parameters.TransformationType, ...
            'MaxNumTrials', obj.automaticOptions.estGeomTransform.MaxNumTrials, ...
            'Confidence',   obj.automaticOptions.estGeomTransform.Confidence, ...
            'MaxDistance',  obj.automaticOptions.estGeomTransform.MaxDistance);

        %     figure(1234);
        %     showMatchedFeatures(original,distorted,matchedOriginal,matchedDistorted);
        %     title("Matched Points");
        %     figure(1235);
        %     inlierPtsDistorted = matchedDistorted(inlierIdx,:);
        %     inlierPtsOriginal  = matchedOriginal(inlierIdx,:);
        %     showMatchedFeatures(original,distorted,inlierPtsOriginal,inlierPtsDistorted);
        %     title("Removed outliers");

    catch ME
        utils.dlgs.showErrorDialog(parentFig, ME, ...
            sprintf('estgeotform2d failed on slice %d', layer));
        return;
    end

    % Wrap the rigid2d / affine2d / projective2d returned by estgeotform2d
    % into the legacy ``.T`` form so we can compose cumulatively.
    tformLegacy = makeLegacyTform(tform);

    % Compose with the previously broadcast transform
    % https://se.mathworks.com/help/images/matrix-representation-of-geometric-transformations.html
    if isempty(tformMatrix{layer})
        tformMatrix(layer:end) = {tformLegacy};
    else
        if isprop(tformLegacy, 'T') && isprop(tformMatrix{layer}, 'T')
            tformLegacy.T = tformLegacy.T * tformMatrix{layer}.T;
        end
        tformMatrix(layer:end) = {tformLegacy};
    end

    % The distorted slice becomes the new "original" for the next pass
    featuresOriginal = featuresDistorted;
    validPtsOriginal = validPtsDistorted;
    % Quieten unused-output lint
    matchedOriginal = matchedOriginal(inlierIdx, :); %#ok<NASGU>
end
ok = true;
end

% =============================================================================
function tformLegacy = makeLegacyTform(tform)
% ESTGEOTFORM2D returns the new premultiply types (``rigidtform2d`` /
% ``simtform2d`` / ``affinetform2d`` / ``projtform2d``) whose ``.A``
% property holds a 3x3 row-major matrix. Convert to the legacy ``.T``
% (transpose-of-A) form used by the rest of the alignment pipeline so
% cumulative ``t.T = t.T * prev.T`` composition keeps working.

if isprop(tform, 'T')
    tformLegacy = tform;
    return;
end

if isa(tform, 'rigidtform2d') || isa(tform, 'simtform2d')
    tformLegacy = affine2d(tform.A');
elseif isa(tform, 'affinetform2d')
    tformLegacy = affine2d(tform.A');
elseif isa(tform, 'projtform2d')
    tformLegacy = projective2d(tform.A');
else
    % Fall back: try to expose .A → affine2d transpose
    tformLegacy = affine2d(tform.A');
end
end

% =============================================================================
function [tformMatrix, userCancelled] = interactiveSmoothingV1(tformMatrix, Depth, parentFig)
% INTERACTIVESMOOTHINGV1 - Interactive plot + running-average smoothing for
% cumulative scale/shear tform parameters in the v1 feature-based alignment.
%
% Plots the raw scaling and shear components (figure 125) and asks the user
% whether to proceed as-is, apply running-average smoothing, or quit.
% The smoothing-settings dialog runs in a loop until the user accepts or
% cancels.

userCancelled = false;
vec_length = numel(tformMatrix);

% Extract raw scale/shear components from the cumulative tform chain
x_stretch = arrayfun(@(k) tformMatrix{k}.T(1,1), 2:vec_length);
y_stretch = arrayfun(@(k) tformMatrix{k}.T(2,2), 2:vec_length);
x_shear   = arrayfun(@(k) tformMatrix{k}.T(2,1), 2:vec_length);
y_shear   = arrayfun(@(k) tformMatrix{k}.T(1,2), 2:vec_length);
sliceIndices = 2:vec_length;

% --- Plot raw parameters
figure(125);
subplot(2, 1, 1);
plot(sliceIndices, x_stretch, '.-', sliceIndices, y_stretch, '.-');
title('Scaling');  legend('x-axis', 'y-axis');
subplot(2, 1, 2);
plot(sliceIndices, x_shear, '.-', sliceIndices, y_shear, '.-');
title('Shear');  legend('x-axis', 'y-axis');

% --- First decision dialog
questOpt.Icon = 'puffin_question';
questOpt.WindowStyle = 'normal';
answer1 = utils.dlgs.inputQuestDlg(parentFig, ...
    'Align the stack using detected displacements?', 'Align dataset', ...
    'Apply current values', 'Fix drifts', 'Quit alignment', 'Apply current values', questOpt);
if isempty(answer1) || strcmp(answer1, 'Quit alignment')
    userCancelled = true;
    return;
end
if strcmp(answer1, 'Apply current values')
    return;  % apply without smoothing
end

% --- Smoothing loop
halfWidthMax     = max(1, floor(Depth / 2 - 1));
halfWidthDefault = min(25, halfWidthMax);
fixStretch          = true;
excludeStretchPeaks = 0;
fixShear            = true;
excludeShearPeaks   = 0;

notOk = true;
while notOk
    % Smoothing-settings dialog
    prompts = {'Half-width of averaging window', ...
               'Fix stretching', ...
               'Exclude stretch peaks higher than (0 = off)', ...
               'Fix shear', ...
               'Exclude shear peaks higher than (0 = off)'};
    defAns = {struct('Spinner', true, 'Value', halfWidthDefault, 'Limits', [1 halfWidthMax], 'Step', 1, 'Round', false), ...
              fixStretch,  ...
              struct('Spinner', true, 'Value', excludeStretchPeaks, 'Limits', [0 Inf], 'Step', 0.01, 'Round', false), ...
              fixShear, ...
              struct('Spinner', true, 'Value', excludeShearPeaks, 'Limits', [0 Inf], 'Step', 0.01, 'Round', false)};
    dlgOpt.LabelPosition = 'left';
    dlgOpt.WindowHeight = 210;
    answer2 = utils.dlgs.inputUniversalDlg(parentFig, '', prompts, defAns, 'Correction settings', dlgOpt);
    if isempty(answer2)
        userCancelled = true;
        return;
    end
    halfWidthDefault    = answer2{1};
    fixStretch          = logical(answer2{2});
    excludeStretchPeaks = answer2{3};
    fixShear            = logical(answer2{4});
    excludeShearPeaks   = answer2{5};

    % Apply smoothing
    if fixStretch
        x_stretch2 = utils.align.runningAverageSmoothPoints(x_stretch, halfWidthDefault, excludeStretchPeaks) + 1;
        y_stretch2 = utils.align.runningAverageSmoothPoints(y_stretch, halfWidthDefault, excludeStretchPeaks) + 1;
    else
        x_stretch2 = x_stretch;
        y_stretch2 = y_stretch;
    end
    if fixShear
        x_shear2 = utils.align.runningAverageSmoothPoints(x_shear, halfWidthDefault, excludeShearPeaks);
        y_shear2 = utils.align.runningAverageSmoothPoints(y_shear, halfWidthDefault, excludeShearPeaks);
    else
        x_shear2 = x_shear;
        y_shear2 = y_shear;
    end

    % Re-plot smoothed parameters
    figure(125);
    subplot(2, 1, 1);
    plot(sliceIndices, x_stretch2, '.-', sliceIndices, y_stretch2, '.-');
    title('Scaling, fixed');  legend('x-axis', 'y-axis');
    subplot(2, 1, 2);
    plot(sliceIndices, x_shear2, '.-', sliceIndices, y_shear2, '.-');
    title('Shear, fixed');  legend('x-axis', 'y-axis');

    % Second decision dialog
    answer3 = utils.dlgs.inputQuestDlg(parentFig, ...
        'Align the stack using detected displacements?', 'Fix drifts', ...
        'Apply values', 'Change window size', 'Quit alignment', 'Apply values', questOpt);
    if isempty(answer3) || strcmp(answer3, 'Quit alignment')
        userCancelled = true;
        return;
    end
    if strcmp(answer3, 'Apply values')
        % Write smoothed values back into the tform chain.
        % Assign the full T matrix at once — element-level assignment triggers
        % the affine2d setter with an intermediate state and fails validation.
        for k = 2:vec_length
            if isempty(tformMatrix{k}) || ~isprop(tformMatrix{k}, 'T'); continue; end
            Tk = tformMatrix{k}.T;
            Tk(1,1) = x_stretch2(k - 1);
            Tk(2,2) = y_stretch2(k - 1);
            Tk(2,1) = x_shear2(k - 1);
            Tk(1,2) = y_shear2(k - 1);
            tformMatrix{k}.T = Tk;
        end
        notOk = false;
    end
    % else "Change window size" → loop with updated defAns
end
end

% =============================================================================
function tformMatrix = smoothTformChain(tformMatrix, Depth, BatchOpt)
% Apply running-average smoothing to the cumulative tform chain. Reads
% the BatchOpt knobs set by the GUI: ``SubtractRunningAverageStep`` and
% the per-channel fix flags + exclude-peak thresholds.

vec_length = numel(tformMatrix);
hasTform = false(vec_length, 1);
for k = 2:vec_length
    hasTform(k) = ~isempty(tformMatrix{k}) && isprop(tformMatrix{k}, 'T');
end
if ~any(hasTform); return; end

x_stretch = arrayfun(@(k) tformMatrix{k}.T(1,1), 2:vec_length);
y_stretch = arrayfun(@(k) tformMatrix{k}.T(2,2), 2:vec_length);
x_shear   = arrayfun(@(k) tformMatrix{k}.T(2,1), 2:vec_length);
y_shear   = arrayfun(@(k) tformMatrix{k}.T(1,2), 2:vec_length);

halfwidth = BatchOpt.SubtractRunningAverageStep{1};
if halfwidth > floor(Depth/2 - 1)
    halfwidth = max(1, floor(Depth/2 - 1));
end
excludeStretchPeaks = BatchOpt.SubtractRunningAverageExcludeStretchPeaks{1};
excludeShearPeaks   = BatchOpt.SubtractRunningAverageExcludeShearPeaks{1};

if BatchOpt.SubtractRunningAverageFixStretch
    x_stretch = utils.align.runningAverageSmoothPoints(x_stretch, halfwidth, excludeStretchPeaks) + 1;
    y_stretch = utils.align.runningAverageSmoothPoints(y_stretch, halfwidth, excludeStretchPeaks) + 1;
end
if BatchOpt.SubtractRunningAverageFixShear
    x_shear = utils.align.runningAverageSmoothPoints(x_shear, halfwidth, excludeShearPeaks);
    y_shear = utils.align.runningAverageSmoothPoints(y_shear, halfwidth, excludeShearPeaks);
end

for k = 2:vec_length
    if ~hasTform(k); continue; end
    Tk = tformMatrix{k}.T;
    Tk(1,1) = x_stretch(k - 1);
    Tk(2,2) = y_stretch(k - 1);
    Tk(2,1) = x_shear(k - 1);
    Tk(1,2) = y_shear(k - 1);
    tformMatrix{k}.T = Tk;
end
end

% =============================================================================
function safeDeleteWaitbar(pwb)
if ~isempty(pwb) && isvalid(pwb)
    pwb.deletePoolWaitbar();
end
end
