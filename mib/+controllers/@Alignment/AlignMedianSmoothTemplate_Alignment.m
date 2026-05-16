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
% :func:`medfilt3` using a ``[1, 1, MedianSize]`` neighbourhood — the
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
% Optional running-average smoothing of stretch + shear is applied from
% ``BatchOpt.SubtractRunningAverage*`` when the flag is set; the
% interactive figure-plot flow from MIB2 is deferred.
%
% AMST is **cropped-mode only** (matches MIB2 behaviour).
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
        parforArg = obj.mibModel.cpuParallelLimitMax;
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

    % --- Optional BatchOpt-driven running-average smoothing
    if obj.BatchOpt.SubtractRunningAverage
        tformMatrix = smoothAmstChain(tformMatrix, Depth, obj.BatchOpt);
    end
end

% Verify at least one usable transform
anyTform = any(~cellfun(@isempty, tformMatrix));
if ~anyTform
    utils.dlgs.showErrorDialog(parentFig, ...
        'No transforms were produced — registration may have failed on every slice.', ...
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
function tformMatrix = smoothAmstChain(tformMatrix, Depth, BatchOpt)
% Apply running-average smoothing to the stretch + shear components of
% the legacy ``.T`` matrices, driven entirely by BatchOpt knobs (no
% interactive dialog).

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

if BatchOpt.SubtractRunningAverageFixStretch
    x_stretch = x_stretch - utils.align.windv(x_stretch, halfwidth) + 1;
    y_stretch = y_stretch - utils.align.windv(y_stretch, halfwidth) + 1;
end
if BatchOpt.SubtractRunningAverageFixShear
    x_shear = x_shear - utils.align.windv(x_shear, halfwidth);
    y_shear = y_shear - utils.align.windv(y_shear, halfwidth);
end

for k = 2:vec_length
    if ~hasTform(k); continue; end
    tformMatrix{k}.T(1,1) = x_stretch(k - 1);
    tformMatrix{k}.T(2,2) = y_stretch(k - 1);
    tformMatrix{k}.T(2,1) = x_shear(k - 1);
    tformMatrix{k}.T(1,2) = y_shear(k - 1);
end
end

% =============================================================================
function safeDeleteWaitbar(pwb)
if ~isempty(pwb) && isvalid(pwb)
    pwb.deletePoolWaitbar();
end
end
