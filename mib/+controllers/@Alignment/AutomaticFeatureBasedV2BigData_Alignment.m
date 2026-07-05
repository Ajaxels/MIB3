function AutomaticFeatureBasedV2BigData_Alignment(obj, parameters)
% AUTOMATICFEATUREBASEDV2BIGDATA_ALIGNMENT - Automatic feature-based v2 (affine) for BigData.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.AutomaticFeatureBasedV2BigData_Alignment(parameters)
%
% Feature-based affine alignment for disk-backed pyramidal (BigData) stores.
% Two-pass streaming:
%
%   - **Pass 1** runs the shared per-slice fit (:func:`utils.align.fitPerSliceV2`)
%     on slices read at the analysis pyramid level ``parameters.pyramidLevel``.
%     When a coarse level is chosen the level already downsamples, so the v2
%     analysis factor is forced to 1 (no double downsampling). Cumulative
%     parameters are composed and optionally smoothed (interactive in GUI,
%     BatchOpt-driven in batch) — the smoothing acts on the small level-L
%     parameter vectors.
%   - Cumulative transforms are **conjugated to level 0** (``T0 = S*TL*inv(S)``,
%     ``S = diag([s s 1])`` — the linear block is unchanged, the translation
%     column is multiplied by the level scale ``s``). The extended canvas is
%     computed by corner projection at level-0 dims. The level-0 transforms are
%     handed to :meth:`applyAlignmentBigData` with ``mode = 'affine'``, which
%     streams a NEW aligned OME-Zarr v3 image (+ ``Labels_<stem>.zarr3``) and
%     swaps the active buffer. The source store is never modified.
%
% Input Arguments:
%   - **parameters** — struct built by :meth:`continueBtn_Callback`; BigData
%     fields ``isBigData`` (true), ``pyramidLevel``, ``outputPath``, plus
%     ``TransformationType`` (translation/rigid/similarity/affine),
%     ``TransformationMode``, ``colorCh``, ``backgroundColor``, ``useBatchMode``.
%
% See also: utils.align.fitPerSliceV2, controllers.Alignment.applyAlignmentBigData,
% controllers.Alignment.AutomaticFeatureBasedV2_Alignment

id = obj.mibModel.getActiveId();
ds = obj.mibModel.I{id};

if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

parameters.detectPointsType = obj.BatchOpt.FeatureDetectorType{1};

% v2 allows only translation / rigid / similarity / affine
if ~ismember(parameters.TransformationType, {'translation', 'rigid', 'similarity', 'affine'})
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf(['TransformationType "%s" is not supported by the v2 algorithm.\n\n' ...
                'Supported types: translation, rigid, similarity, affine.'], ...
                parameters.TransformationType), 'Alignment');
    return;
end

[Height, Width, Depth] = ds.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));
if Depth < 2
    utils.dlgs.showErrorDialog(parentFig, ...
        'Automatic feature-based v2 alignment requires at least 2 slices.', 'Alignment');
    return;
end
if ds.orientation ~= 3
    utils.dlgs.showErrorDialog(parentFig, ...
        'BigData alignment currently supports XY (orientation 3) datasets only.', 'Alignment');
    return;
end

% --- Analysis pyramid level + its full-res scale factors
L  = parameters.pyramidLevel;
sf = ds.image.pyramid.levelScaleFactors(L, :);   % [yScale xScale zScale]
scaleY = sf(1);
scaleX = sf(2);

% --- Background fill (numeric); 'mean' resolved from a level-L slice
if isnumeric(parameters.backgroundColor)
    bgImage = double(parameters.backgroundColor);
elseif strcmpi(parameters.backgroundColor, 'white')
    bgImage = double(ds.image.maxInt);
elseif strcmpi(parameters.backgroundColor, 'mean')
    firstSlice = cell2mat(obj.mibModel.getData2D('image', 1, [], parameters.colorCh, ...
        struct('blockModeSwitch', 0, 'pyramidLevel', L)));
    bgImage = mean(double(firstSlice(:)));
else   % 'black'
    bgImage = 0;
end

% --- Analysis downsampling. The pyramid level already downsamples XY, so force
% the v2 analysis factor to 1 when a coarse level is chosen (avoid double
% downsampling). At level 1 the user's factor still applies.
if L > 1
    ratio = 1;
    parameters.imgDownsamplingFactor = 1;
else
    parameters.imgDownsamplingFactor = obj.automaticOptions.imgDownsamplingFactorForAnalysis;
    ratio = 1 / parameters.imgDownsamplingFactor;
end

% --- Feature-detector settings dialog (GUI only)
if ~parameters.useBatchMode
    status = obj.updateAutomaticOptions();
    if status == 0; return; end
    if L == 1
        parameters.imgDownsamplingFactor = obj.automaticOptions.imgDownsamplingFactorForAnalysis;
        ratio = 1 / parameters.imgDownsamplingFactor;
    end
end

% --- Cancelable progress
pwb = [];
if obj.BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(Depth, sprintf('V2 BigData: detecting & matching at level %d...', L), ...
        parentFig, 'BigData alignment', true);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

% =====================================================================
% Pass 1 — per-slice pairwise fit at level L (shared helper)
% =====================================================================
% Read the FULL level-L slice directly (bypass getData2D, which returns only
% the visible viewport for a pyramidal image).
readSliceFcn = @(sliceIndex) squeeze(ds.image.getData('image', 3, parameters.colorCh, ...
    struct('pyramidLevel', L, 'z', [sliceIndex, sliceIndex])));
pairwiseTforms   = cell(Depth, 1);
translations     = zeros(Depth, 2);
rotations        = zeros(Depth, 1);
scales           = ones(Depth, 1);
affine_params    = zeros(Depth, 4);
affine_params(:, [1 4]) = 1;

[pairwiseTforms, translations, rotations, scales, affine_params, ok] = ...
    utils.align.fitPerSliceV2(obj, Depth, parameters, ratio, readSliceFcn, ...
    pairwiseTforms, translations, rotations, scales, affine_params, pwb, parentFig);
if ~ok; return; end

% --- Compose cumulative parameters (level-L)
cumulativeTranslations = cumsum(translations, 1);
cumulativeRotations    = cumsum(rotations,    1);
cumulativeScales       = cumprod(scales,      1);

% --- Smoothing (interactive in GUI, BatchOpt-driven in batch)
useSmoothed = false;
if ~parameters.useBatchMode
    [cumulativeTranslations, cumulativeRotations, cumulativeScales, useSmoothed, userCancelled] = ...
        utils.align.interactiveSmoothingV2(cumulativeTranslations, cumulativeRotations, ...
            cumulativeScales, affine_params, Depth, parameters.TransformationType, parentFig);
    if userCancelled; return; end
elseif obj.BatchOpt.SubtractRunningAverage
    [cumulativeTranslations, cumulativeRotations, cumulativeScales] = ...
        utils.align.smoothCumulativeV2(cumulativeTranslations, cumulativeRotations, ...
            cumulativeScales, Depth, parameters.TransformationType, obj.BatchOpt);
    useSmoothed = true;
end

% --- Rebuild cumulative tforms at level L (mirrors in-memory v2)
cumulativeTformsL = cell(Depth, 1);
cumulativeTformsL{1} = affinetform2d(eye(3));
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
                sVal = cumulativeScales(layer);
                R = [cos(theta), -sin(theta); sin(theta), cos(theta)];
                T(1:2, 1:2) = sVal * R;
        end
    else
        T = pairwiseTforms{layer}.A * cumulativeTformsL{layer - 1}.A;
    end
    cumulativeTformsL{layer} = affinetform2d(T);
    if strcmp(parameters.TransformationType, 'translation')
        cumulativeTformsL{layer}.A(1, 3) = round(cumulativeTformsL{layer}.A(1, 3));
        cumulativeTformsL{layer}.A(2, 3) = round(cumulativeTformsL{layer}.A(2, 3));
    end
end

% =====================================================================
% Conjugate cumulative tforms L -> 0 (translation column x scale)
% =====================================================================
cumulativeTforms0 = cell(Depth, 1);
for layer = 1:Depth
    A = cumulativeTformsL{layer}.A;
    A(1, 3) = A(1, 3) * scaleX;
    A(2, 3) = A(2, 3) * scaleY;
    cumulativeTforms0{layer} = affinetform2d(A);
end

% =====================================================================
% Level-0 output canvas (corner projection) + origin offset
% =====================================================================
if strcmp(parameters.TransformationMode, 'extended')
    corners = [1, 1; Width, 1; Width, Height; 1, Height];
    allX = zeros(4 * Depth, 1);
    allY = zeros(4 * Depth, 1);
    for k = 1:Depth
        warpedCorners = [corners, ones(4, 1)] * cumulativeTforms0{k}.A';
        allX((k-1)*4+1:k*4) = warpedCorners(:, 1);
        allY((k-1)*4+1:k*4) = warpedCorners(:, 2);
    end
    minX0 = floor(min(allX));   maxX0 = ceil(max(allX));
    minY0 = floor(min(allY));   maxY0 = ceil(max(allY));
    newW0 = maxX0 - minX0 + 1;
    newH0 = maxY0 - minY0 + 1;
    originShiftX = minX0 - 1;   % pixels; new canvas origin vs original frame
    originShiftY = minY0 - 1;
else   % cropped
    newW0 = Width;   newH0 = Height;
    originShiftX = 0;   originShiftY = 0;
end

% Bake the origin offset into the level-0 tforms so the provider can use a
% default OutputView imref2d([newH0 newW0]) (unit pixels): content world x maps
% to output pixel (x - originShift).
Tt = [1 0 -originShiftX; 0 1 -originShiftY; 0 0 1];
bakedTforms = cell(Depth, 1);
for layer = 1:Depth
    bakedTforms{layer} = affinetform2d(Tt * cumulativeTforms0{layer}.A);
end

% =====================================================================
% Apply (streamed new store + buffer swap)
% =====================================================================
if ~isempty(pwb); pwb.updateText('Writing the aligned BigData store...'); end

tformInfo = struct();
tformInfo.mode            = 'affine';
tformInfo.tforms          = bakedTforms;
tformInfo.outputSize      = [newH0, newW0];
tformInfo.originShift     = [originShiftX, originShiftY];
tformInfo.backgroundValue = bgImage;

% --- Capture + warp annotations into the new-canvas frame. The buffer swap
% re-initialises the dataset (wiping annotations), so applyAlignmentBigData
% re-adds these warped labels afterwards. Positions are [z x y t]; the baked
% tforms already include the origin offset, so the warped x/y land directly in
% the new canvas.
if ds.annotations.getLabelsNumber() > 0
    [aText, aVal, aPos] = ds.annotations.getLabels();   % aPos = [z x y t]
    warpedPos = aPos;
    for a = 1:size(aPos, 1)
        zSlice = round(aPos(a, 1));
        if zSlice < 1 || zSlice > Depth; continue; end
        [wx, wy] = transformPointsForward(bakedTforms{zSlice}, aPos(a, 2), aPos(a, 3));
        warpedPos(a, 2) = wx;
        warpedPos(a, 3) = wy;
    end
    tformInfo.annotations = struct('labelText', {aText}, ...
        'labelPositions', warpedPos, 'labelValues', aVal);
end

% Persist level-0 alignment state for optional save/replay
alignStruct = struct('cumulativeTforms', {cumulativeTforms0}, ...
    'pairwiseTforms', {pairwiseTforms}, 'translations', translations, ...
    'rotations', rotations, 'scales', scales, 'affine_params', affine_params);
obj.shiftsX = alignStruct;
obj.shiftsY = [];

obj.applyAlignmentBigData(parameters, tformInfo);

end

% =============================================================================
function safeDeleteWaitbar(pwb)
if ~isempty(pwb) && isvalid(pwb)
    pwb.deletePoolWaitbar();
end
end
