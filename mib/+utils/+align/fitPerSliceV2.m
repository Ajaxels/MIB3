function [pairwiseTforms, translations, rotations, scales, affine_params, ok] = ...
    fitPerSliceV2(obj, Depth, parameters, ratio, readSliceFcn, ...
    pairwiseTforms, translations, rotations, scales, affine_params, pwb, parentFig)
% FITPERSLICEV2 - Per-slice pairwise feature-based transform fitting (v2 algorithm).
%
% Syntax:
%   .. code-block:: matlab
%
%      [pairwiseTforms, translations, rotations, scales, affine_params, ok] = ...
%          utils.align.fitPerSliceV2(obj, Depth, parameters, ratio, readSliceFcn, ...
%          pairwiseTforms, translations, rotations, scales, affine_params, pwb, parentFig)
%
% Walks slices ``2..Depth``: detects features on each consecutive pair,
% RANSAC-fits a 2-D transform via ``estgeotform2d``, and stores the pairwise
% transform plus its decomposed translation / rotation / scale components.
% Shared by the in-memory (``AutomaticFeatureBasedV2_Alignment``) and BigData
% (``AutomaticFeatureBasedV2BigData_Alignment``) paths - they differ ONLY in the
% per-slice read, which the caller supplies as ``readSliceFcn``:
%
%   - In-memory: ``@(n) cell2mat(obj.mibModel.getData2D('image', n, [], colCh, opt))``.
%   - BigData: ``@(n) squeeze(ds.image.getData('image', 3, colCh, struct('pyramidLevel', L, 'z', [n n])))``
%     - reads the FULL level-L slice directly, bypassing the view-dependent
%     ``getData2D`` (which returns only the visible viewport for a pyramid).
%
% Input Arguments:
%   - **obj** - :class:`controllers.Alignment` (uses ``obj.automaticOptions``).
%   - **Depth** - [numeric] number of Z-slices.
%   - **parameters** - struct with ``detectPointsType``, ``TransformationType``.
%   - **ratio** - [numeric] extra analysis downsampling (``1`` = none).
%   - **readSliceFcn** - [function handle] ``@(sliceIndex) -> 2-D grayscale slice``.
%   - **pairwiseTforms / translations / rotations / scales / affine_params** -
%     pre-allocated accumulators (see caller).
%   - **pwb** - [:class:`core.PoolWaitbar`] or ``[]``.
%   - **parentFig** - parent figure for error dialogs.
%
% Output Arguments:
%   - **pairwiseTforms** - ``{Depth x 1}`` cell of ``affinetform2d``.
%   - **translations / rotations / scales / affine_params** - decomposed params.
%   - **ok** - [logical] ``false`` on cancel / detection failure.
%
% See also: utils.align.detectFeatures, utils.align.smoothCumulativeV2,
% controllers.Alignment.AutomaticFeatureBasedV2_Alignment

ok = false;

original = readSliceFcn(1);
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

    distorted = readSliceFcn(layer);
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

    % Store pairwise transform as a uniform ``affinetform2d``.
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

    % Roll forward
    featuresOriginal = featuresDistorted;
    validPtsOriginal = validPtsDistorted;
end
ok = true;
end
