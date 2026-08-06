function AlignMedianSmoothTemplate_Alignment(obj, parameters)
% ALIGNMEDIANSMOOTHTEMPLATE_ALIGNMENT - Align a stack to its own median-smoothed template (AMST).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.AlignMedianSmoothTemplate_Alignment(parameters)
%
% Intensity-based registration aligning each slice to a **median-smoothed
% version of the same stack**. Smoothing is applied along Z with
% :func:`medfilt3` using a ``[1, 1, MedianSize]`` neighbourhood - the
% template at slice *k* is the median of the surrounding slices, which
% compensates for local deformations that pure feature matching cannot
% fix. The dataset is expected to have been pre-aligned with drift
% correction first; this stage refines the result.
%
% Per-slice registration uses :func:`imregtform` in *monomodal* mode with
% optimizer parameters drawn from ``obj.automaticOptions.amst``. Supported
% TransformationType values come from :func:`imregtform`: ``translation``,
% ``rigid``, ``similarity``, ``affine``. ``projective`` is rejected with
% an error dialog (``imregtform`` does not support it).
%
% Running-average smoothing of stretch + shear is available in two modes:
% interactive (GUI) and batch.  In interactive mode the raw scaling and
% shear curves are plotted (figure 125) and the user chooses whether to
% apply smoothing and tunes the half-width / exclude-peaks settings in a
% loop until satisfied; the smoothed values are written back into
% ``tformMatrix{*}.T`` *before* the apply phase.  In batch mode smoothing
% runs automatically from the ``BatchOpt.SubtractRunningAverage*`` fields
% when ``BatchOpt.SubtractRunningAverage`` is set.
%
% AMST is **cropped-mode only** (matches MIB2 behaviour).
%
% Input Arguments:
%   - **parameters** - struct produced by :meth:`continueBtn_Callback`.
%     Reads ``TransformationType``, ``TransformationMode``, ``colorCh``,
%     ``backgroundColor``, ``useBatchMode``, ``method``.

% Updates
%

id = obj.mibModel.getActiveId();

% Parent figure for any dialogs - ``obj.view`` is empty in batch mode
if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

% --- Reject extended mode + projective transformType
if ~strcmp(parameters.TransformationMode, 'cropped')
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('AMST currently supports only the "cropped" transformation mode.\n\nSwitch TransformationMode and retry.'), 'Alignment');
    return;
end
if strcmp(parameters.TransformationType, 'projective')
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('AMST does not support "projective" transforms (imregtform limitation).\n\nUse translation, rigid, similarity, or affine.'), 'Alignment');
    return;
end
if ~ismember(parameters.TransformationType, {'translation', 'rigid', 'similarity', 'affine'})
    % imregtform only accepts these four; map common synonyms
    if strcmp(parameters.TransformationType, 'nonreflectivesimilarity')
        parameters.TransformationType = 'similarity';
    else
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf('AMST does not support "%s"\n\n(imregtform accepts translation / rigid / similarity / affine).', parameters.TransformationType), 'Alignment');
        return;
    end
end

% --- Confirm pre-alignment expectation
if ~parameters.useBatchMode
    questOpt.Icon = 'puffin_question';
    questOpt.WindowStyle = 'modal';
    answer = utils.dlgs.inputQuestDlg(parentFig, ...
        sprintf(['AMST expects a pre-aligned stack.\n\n' ...
                'If the dataset has not yet been roughly aligned (e.g. with ' ...
                'Drift correction), AMST may diverge\n Continue?']), ...
        'Pre-alignment', 'Yes, continue', 'Cancel', 'Yes, continue', questOpt);
    if isempty(answer) || strcmp(answer, 'Cancel'); return; end
end

[Height, Width, Depth] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));
if Depth < 3
    utils.dlgs.showErrorDialog(parentFig, 'AMST requires at least 3 slices.', 'Alignment');
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

% --- Downsampling ratio for the registration step
if obj.automaticOptions.imgWidthForAnalysis == 0
    parameters.imgWidthForAnalysis = Width;
else
    parameters.imgWidthForAnalysis = obj.automaticOptions.imgWidthForAnalysis;
end
ratio = parameters.imgWidthForAnalysis / Width;

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
    ratio = parameters.imgWidthForAnalysis / Width;
end

% --- Set up cancelable progress
pwb = [];
if obj.BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(Depth, 'AMST: median-smoothed template alignment...', ...
        parentFig, 'Alignment', true);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

% --- Step 1: fit per-slice transforms (skipped when replayed)
if ~shiftsLoaded
    if ~isempty(pwb); pwb.updateText('Step 1/3: building median template...'); end

    % Pull the full 3-D image at the chosen colour channel
    movingImg = cell2mat(obj.mibModel.getData3D('image', [], 3, parameters.colorCh, optionsGetData));
    movingImg = squeeze(movingImg);    % [H, W, Z]
    if ratio ~= 1
        movingImg = imresize(movingImg, ratio, 'bicubic');
    end

    % Median-smooth along Z (template)
    medianZ = obj.BatchOpt.MedianSize{1};
    fixedImg = medfilt3(movingImg, [1, 1, max(1, medianZ)], 'replicate');

    % imregconfig: monomodal optimizer driven by automaticOptions.amst
    [optimizer, metric] = imregconfig('monomodal');
    optimizer.MaximumIterations          = obj.automaticOptions.amst.MaximumIterations;
    optimizer.GradientMagnitudeTolerance = obj.automaticOptions.amst.GradientMagnitudeTolerance;
    optimizer.MinimumStepLength          = obj.automaticOptions.amst.MinimumStepLength;
    optimizer.MaximumStepLength          = obj.automaticOptions.amst.MaximumStepLength;
    optimizer.RelaxationFactor           = obj.automaticOptions.amst.RelaxationFactor;
    pyramidLevels = obj.automaticOptions.amst.PyramidLevels;
    transformType = parameters.TransformationType;

    % Parallel pool setup (optional)
    if obj.BatchOpt.UseParallelComputing
        parforArg = obj.mibModel.preferences.System.cpuParallelLimit;
        if isempty(gcp('nocreate')); parpool(parforArg); end
    else
        parforArg = 0;
    end

    if ~isempty(pwb); pwb.updateText('Step 2/3: registering slices to template...'); end

    parfor (layer = 1:Depth, parforArg)
        try
            tform = imregtform(movingImg(:, :, layer), fixedImg(:, :, layer), ...
                transformType, optimizer, metric, 'PyramidLevels', pyramidLevels);
        catch
            tform = [];
        end
        if ~isempty(tform)
            % Scale translation back to full resolution (legacy .T layout:
            % T(3,1) = tx, T(3,2) = ty)
            tform.T(3, 1) = tform.T(3, 1) * (1 / ratio);
            tform.T(3, 2) = tform.T(3, 2) * (1 / ratio);
        end
        tformMatrix{layer} = tform;
        if ~isempty(pwb); pwb.increment(); end
    end

    clear movingImg fixedImg;

    if ~isempty(pwb) && pwb.getCancelState(); return; end

    % --- Interactive (GUI) or BatchOpt-driven (batch) smoothing of stretch + shear
    if ~parameters.useBatchMode
        [tformMatrix, userCancelled] = interactiveSmoothingAmst(tformMatrix, Depth, parentFig);
        if userCancelled; return; end
    elseif obj.BatchOpt.SubtractRunningAverage
        tformMatrix = smoothAmstChain(tformMatrix, Depth, obj.BatchOpt);
    end
end

% Verify at least one usable transform
anyTform = any(~cellfun(@isempty, tformMatrix));
if ~anyTform
    utils.dlgs.showErrorDialog(parentFig, ...
        'No transforms were produced - registration may have failed on every slice.', ...
        'Alignment');
    return;
end

% --- Step 2: apply transforms (cropped only)
if ~isempty(pwb); pwb.updateText('Step 3/3: warping slices...'); end
refImgSize = imref2d([Height, Width]);
applyCroppedMode(obj, id, Depth, tformMatrix, refImgSize, bgImage, pwb);
rbMatrix(:) = {refImgSize};

% --- Transform annotations
if obj.mibModel.I{id}.annotations.getLabelsNumber() > 0
    relocateAnnotations(obj, id, Depth, tformMatrix, rbMatrix, true, 0, 0);
end

% --- Persist transforms so subsequent runs / save-shifts pick them up
obj.shiftsX = tformMatrix;
obj.shiftsY = rbMatrix;

% --- Save tforms / rbMatrix to file if requested
if obj.BatchOpt.SaveShiftsToFile
    saveTformsToFile(obj, id, parameters.useBatchMode, parentFig, 'AMST alignment');
end

obj.mibModel.I{id}.image.updateActionLog(sprintf( ...
    'Aligned using %s; type=%s, mode=%s, medianZ=%d, imgWidth=%d', ...
    parameters.method, parameters.TransformationType, parameters.TransformationMode, ...
    obj.BatchOpt.MedianSize{1}, parameters.imgWidthForAnalysis));

% keepBackup=true so the 'mibDataset' snapshot stored by backup() above is
% not wiped by listener_newDataset.
notify(obj.mibModel, 'NewDataset', core.ToggleEventData(struct('index', id, 'keepBackup', true)));
notify(obj.mibModel, 'ShowImage');
end

% =============================================================================
function [tformMatrix, userCancelled] = interactiveSmoothingAmst(tformMatrix, Depth, parentFig)
% INTERACTIVESMOOTHINGAMST - Interactive plot + running-average smoothing
% for cumulative scale/shear tform parameters produced by AMST. Mirrors
% the v1 feature-based interactiveSmoothingV1 pattern: plot raw stretch +
% shear (figure 125), three-way confirmation dialog, settings loop that
% re-plots after each smoothing pass, full-matrix .T write-back.

userCancelled = false;
vec_length = numel(tformMatrix);

% Extract raw scale/shear components from the tform chain (skip k=1)
x_stretch = arrayfun(@(k) safeT(tformMatrix{k}, 1, 1), 2:vec_length);
y_stretch = arrayfun(@(k) safeT(tformMatrix{k}, 2, 2), 2:vec_length);
x_shear   = arrayfun(@(k) safeT(tformMatrix{k}, 2, 1), 2:vec_length);
y_shear   = arrayfun(@(k) safeT(tformMatrix{k}, 1, 2), 2:vec_length);
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
    'Align the stack using detected displacements?', 'AMST', ...
    'Apply current values', 'Fix drifts', 'Quit alignment', 'Apply current values', questOpt);
if isempty(answer1) || strcmp(answer1, 'Quit alignment')
    userCancelled = true;
    return;
end
if strcmp(answer1, 'Apply current values')
    return;
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
    prompts = {'Half-width of averaging window', ...
               'Fix stretching', ...
               'Exclude stretch peaks higher than (0 = off)', ...
               'Fix shear', ...
               'Exclude shear peaks higher than (0 = off)'};
    defAns = {struct('Spinner', true, 'Value', halfWidthDefault, 'Limits', [1 halfWidthMax], 'Step', 1, 'Round', false), ...
              fixStretch, ...
              struct('Spinner', true, 'Value', excludeStretchPeaks, 'Limits', [0 Inf], 'Step', 0.01, 'Round', false), ...
              fixShear, ...
              struct('Spinner', true, 'Value', excludeShearPeaks, 'Limits', [0 Inf], 'Step', 0.01, 'Round', false)};
    dlgOpt.LabelPosition = 'left';
    dlgOpt.WindowHeight = 210;
    answer2 = utils.dlgs.inputUniversalDlg(parentFig, '', prompts, defAns, 'AMST correction settings', dlgOpt);
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
        'Apply smoothed displacements to the AMST tforms?', 'AMST', ...
        'Apply values', 'Change window size', 'Quit alignment', 'Apply values', questOpt);
    if isempty(answer3) || strcmp(answer3, 'Quit alignment')
        userCancelled = true;
        return;
    end
    if strcmp(answer3, 'Apply values')
        % Write smoothed values back. Assign the full T matrix at once -
        % element-level assignment triggers the affine2d setter with an
        % intermediate state and fails validation.
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
function v = safeT(tform, r, c)
% Return T(r,c) for a tform with a .T property, or the identity-element
% default (1 on the diagonal, 0 off-diagonal) when the slice has no tform.
if ~isempty(tform) && isprop(tform, 'T')
    v = double(tform.T(r, c));
elseif r == c
    v = 1;
else
    v = 0;
end
end

% =============================================================================
function tformMatrix = smoothAmstChain(tformMatrix, Depth, BatchOpt)
% Batch-mode running-average smoothing of stretch + shear, driven entirely
% by BatchOpt knobs. Mirrors v1's smoothTformChain (same .T extraction +
% full-matrix write-back).

vec_length = numel(tformMatrix);
hasTform = false(vec_length, 1);
for k = 2:vec_length
    hasTform(k) = ~isempty(tformMatrix{k}) && isprop(tformMatrix{k}, 'T');
end
if ~any(hasTform); return; end

x_stretch = arrayfun(@(k) double(tformMatrix{k}.T(1,1)), 2:vec_length);
y_stretch = arrayfun(@(k) double(tformMatrix{k}.T(2,2)), 2:vec_length);
x_shear   = arrayfun(@(k) double(tformMatrix{k}.T(2,1)), 2:vec_length);
y_shear   = arrayfun(@(k) double(tformMatrix{k}.T(1,2)), 2:vec_length);

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
