function [shiftYXZ, quality, debugInfo] = featureShift(cropA, cropB, options)
% FEATURESHIFT - Feature-based transform estimate between two overlap crops.
%
% Syntax:
%   .. code-block:: matlab
%
%      [shiftYXZ, quality] = utils.stitch.featureShift(cropA, cropB)
%      [shiftYXZ, quality, debugInfo] = utils.stitch.featureShift(cropA, cropB, options)
%
% Drop-in alternative to :func:`utils.stitch.pairwiseShift` for the
% ``RegistrationMethod = 'Feature-based'`` path. Detects keypoints in each crop
% (SURF by default), matches descriptors, and RANSAC-fits an ``estgeotform2d``
% model - pure translation by default, or the model selected by
% ``options.transformType``; the full fitted matrix is returned in
% ``debugInfo.tformA``. Unlike phase correlation it does NOT rely on a large
% textured overlap: a thin shared strip with a handful of matchable blobs is
% enough, which is why it recovers small (~10%) or unknown overlaps where phase
% correlation loses the peak. Its weakness is feature-poor or strongly repetitive
% content (few / ambiguous matches) - there phase correlation still wins.
%
% **Sign convention (identical to pairwiseShift, load-bearing).** If ``cropB``
% equals ``cropA`` shifted DOWN by ``dy`` rows and RIGHT by ``dx`` columns
% (``cropB(r,c) ≈ cropA(r-dy, c-dx)``), then ``shiftYXZ = [dy dx 0]`` - so the
% composition in :func:`utils.stitch.measureAllPairs`/``measureOne`` is unchanged
% between registration methods. Derivation: ``estgeotform2d(A, B)`` returns the
% map A→B (``B ≈ transformPointsForward(tform, A)``), whose translation
% ``[tx ty] = [T(1,3) T(2,3)]`` places the feature at ``cropA(y,x)`` onto
% ``cropB(y+ty, x+tx)`` ⇒ ``dy = ty = T(2,3)``, ``dx = tx = T(1,3)``.
%
% Input Arguments:
%   - **cropA** - [numeric] reference crop from tile ``i``, ``[H W]`` or ``[H W C]``.
%   - **cropB** - [numeric] moving crop from tile ``j``, same size as ``cropA``.
%   - **options** *(optional)* - struct with fields (all optional). It accepts
%     the same ``automaticOptions`` shape produced by
%     ``controllers.Alignment.defaultAutomaticOptions`` (per-detector sub-structs
%     ``detectSURFFeatures`` …, plus ``estGeomTransform`` and
%     ``rotationInvariance``) so the shared settings dialog
%     :func:`utils.align.detectorSettingsDlg` can drive it directly:
%
%     - ``.featureDetector`` - [char] detector name understood by
%       :func:`utils.align.detectFeatures` (default: SURF).
%     - ``.detectSURFFeatures`` / ``.detectSIFTFeatures`` / … - [struct]
%       per-detector parameters (defaults mirror ``defaultAutomaticOptions``).
%     - ``.rotationInvariance`` - [logical] passed as ``extractFeatures`` ``Upright``
%       (default: ``true`` - upright descriptors, appropriate for translation).
%     - ``.downsampleFactor`` - [double ≥ 1] detect on tiles resized by
%       ``1/downsampleFactor`` (faster on big tiles); point locations are scaled
%       back to full resolution before fitting (default: ``1``).
%     - ``.estGeomTransform`` - [struct] ``.MaxNumTrials`` / ``.Confidence`` /
%       ``.MaxDistance`` for the RANSAC ``estgeotform2d`` fit.
%     - ``.featureMinInliers`` - [double] minimum RANSAC inliers to trust the fit
%       (default: ``8``); below this ``quality = 0``.
%     - ``.transformType`` - [char] ``estgeotform2d`` model:
%       ``'translation'`` (default) | ``'rigid'`` | ``'similarity'`` | ``'affine'``.
%       Non-translation models return their translation component in ``shiftYXZ``
%       and the full matrix in ``debugInfo.tformA``.
%     - ``.allowRotation`` - [logical] ``true`` (default). When ``false`` and a
%       non-translation model is requested, the measured edge is constrained to
%       carry no rotation: ``'rigid'`` falls back to the (equivalent) pure
%       translation fit, while ``'similarity'``/``'affine'`` fits are projected
%       through :func:`utils.stitch.projectLinearPart` (``R = I`` branch) and
%       the translation re-estimated over the RANSAC inliers.
%
%     Fields used only by :func:`utils.stitch.pairwiseShift` (``padPx``,
%     ``expectedShift``, ``searchRadius``, ``window``, ``subpixel``) are ignored.
%
% Output Arguments:
%   - **shiftYXZ** - [1x3 double] ``[dy dx dz]`` correction to the nominal offset
%     (``dz`` is ``0``; Z handled by the caller).
%   - **quality** - [double] in ``[0,1]``: the RANSAC inlier ratio
%     (``inliers / matched``), ``0`` when fewer than ``featureMinInliers`` inliers
%     survive or the fit fails. Comparable to the phase-correlation quality so the
%     same ``QualityThreshold`` gates both methods.
%   - **debugInfo** - struct with ``.numMatched``, ``.numInliers``, ``.status``,
%     and ``.tformA`` - the full fitted A→B transform as a 3x3 double
%     (``[x'; y'; 1] = tformA * [x; y; 1]``, crop-local pixel coordinates, empty
%     until a fit succeeds). For ``transformType = 'translation'`` its linear
%     part is the identity.
%
% **Example** - recover a known integer shift from a textured crop:
%
%   .. code-block:: matlab
%
%      base  = mat2gray(imgaussfilt(randn(256), 1.5));
%      cropA = base(20:220, 20:220);
%      cropB = base(15:215, 23:223);          % A is B shifted down 5, left 3
%      [s, q] = utils.stitch.featureShift(cropA, cropB);
%      % s ≈ [5 -3 0]

if nargin < 3; options = struct(); end
options = mergeDefaults(options);

shiftYXZ  = [0 0 0];
quality   = 0;
debugInfo = struct('numMatched', 0, 'numInliers', 0, 'status', -1, 'tformA', []);

% Grayscale, single, rescaled to [0,1] so detector thresholds behave consistently
% regardless of the tile's native dynamic range.
imageA = normalizeGray(cropA);
imageB = normalizeGray(cropB);
if size(imageA, 1) < 4 || size(imageA, 2) < 4
    return;
end

% Optional downsampling for detection: resize by 1/factor, then scale the matched
% point locations back to full resolution before fitting (like utils.align.fitPerSliceV2).
scaleBack = 1;
if options.downsampleFactor > 1
    ratio = 1 / options.downsampleFactor;
    imageA = imresize(imageA, ratio, 'bilinear');
    imageB = imresize(imageB, ratio, 'bilinear');
    scaleBack = options.downsampleFactor;
    if size(imageA, 1) < 4 || size(imageA, 2) < 4
        return;
    end
end

% detectFeatures reads its parameters from per-detector sub-structs of options.
pointsA = utils.align.detectFeatures(imageA, options.featureDetector, options);
pointsB = utils.align.detectFeatures(imageB, options.featureDetector, options);
if isempty(pointsA) || isempty(pointsB) || pointsA.Count < 3 || pointsB.Count < 3
    return;
end

% Upright = rotationInvariance flag (mirrors fitPerSliceV2). ORB has no Upright.
if strcmp(options.featureDetector, 'Oriented FAST and rotated BRIEF (ORB)')
    [featuresA, validA] = extractFeatures(imageA, pointsA);
    [featuresB, validB] = extractFeatures(imageB, pointsB);
else
    [featuresA, validA] = extractFeatures(imageA, pointsA, 'Upright', options.rotationInvariance);
    [featuresB, validB] = extractFeatures(imageB, pointsB, 'Upright', options.rotationInvariance);
end

indexPairs = matchFeatures(featuresA, featuresB, 'Unique', true);
debugInfo.numMatched = size(indexPairs, 1);
if size(indexPairs, 1) < options.featureMinInliers
    return;
end
% Matched locations scaled back to full resolution (Mx2 [x y]).
matchedA = validA(indexPairs(:, 1)).Location * scaleBack;
matchedB = validB(indexPairs(:, 2)).Location * scaleBack;

% RANSAC-fit the selected model A->B. estgeotform2d returns the inlier mask and a
% status code (0 = success, 1 = too few points, 2 = not enough inliers).
try
    [tform, inlierIdx, status] = estgeotform2d(matchedA, matchedB, options.transformType, ...
        'MaxDistance', options.estGeomTransform.MaxDistance, ...
        'MaxNumTrials', options.estGeomTransform.MaxNumTrials, ...
        'Confidence', options.estGeomTransform.Confidence);
catch
    return;
end
debugInfo.status = status;
if status ~= 0
    return;
end

numInliers = nnz(inlierIdx);
debugInfo.numInliers = numInliers;
if numInliers < options.featureMinInliers
    return;
end

T = double(tform.A);               % 3x3, translation in the 3rd column
if ~options.allowRotation && ~strcmpi(options.transformType, 'translation')
    % Rotation lock for similarity/affine: project the fitted linear part
    % (R = I branch of the polar decomposition) and re-estimate the translation
    % as the least-squares fit over the RANSAC inliers with the linear part fixed.
    projectedM = utils.stitch.projectLinearPart(T(1:2, 1:2), options.transformType, false);
    inlierA = double(matchedA(inlierIdx, :));               % Mx2 [x y] (Locations are single)
    inlierB = double(matchedB(inlierIdx, :));
    projectedC = mean(inlierB - inlierA * projectedM', 1)';
    T = [projectedM, projectedC; 0 0 1];
end
shiftYXZ = [T(2, 3), T(1, 3), 0];  % [dy dx dz] in the pairwiseShift convention (double, like pairwiseShift)
debugInfo.tformA = T;              % full fitted A->B model (identity linear part for 'translation')

% Quality = inlier ratio in [0,1]; a clean translation overlap yields a high
% ratio, repetitive/ambiguous content a low one.
quality = double(numInliers) / double(size(indexPairs, 1));
quality = max(min(quality, 1), 0);
end

% =====================================================================
function options = mergeDefaults(options)
% MERGEDEFAULTS - Fill any missing fields with the defaultAutomaticOptions shape.
if ~isfield(options, 'featureDetector') || isempty(options.featureDetector)
    options.featureDetector = 'Blobs: Speeded-Up Robust Features (SURF) algorithm';
end
if ~isfield(options, 'rotationInvariance'); options.rotationInvariance = true; end
if ~isfield(options, 'downsampleFactor') || options.downsampleFactor < 1
    options.downsampleFactor = 1;
end
if ~isfield(options, 'featureMinInliers'); options.featureMinInliers = 8; end
if ~isfield(options, 'transformType') || isempty(options.transformType)
    options.transformType = 'translation';
end
if ~isfield(options, 'allowRotation'); options.allowRotation = true; end
% Rigid without rotation IS a translation - fit the smaller model directly.
if ~options.allowRotation && strcmpi(options.transformType, 'rigid')
    options.transformType = 'translation';
end
options = fillStruct(options, 'detectSURFFeatures', ...
    struct('MetricThreshold', 500, 'NumOctaves', 3, 'NumScaleLevels', 4));
options = fillStruct(options, 'detectSIFTFeatures', ...
    struct('ContrastThreshold', 0.0133, 'EdgeThreshold', 10, 'NumLayersInOctave', 3, 'Sigma', 1.6));
options = fillStruct(options, 'detectMSERFeatures', ...
    struct('ThresholdDelta', 2, 'RegionAreaRange', [30 14000], 'MaxAreaVariation', 0.25));
options = fillStruct(options, 'detectHarrisFeatures',   struct('MinQuality', 0.01, 'FilterSize', 5));
options = fillStruct(options, 'detectBRISKFeatures',    struct('MinContrast', 0.2, 'MinQuality', 0.1, 'NumOctaves', 4));
options = fillStruct(options, 'detectFASTFeatures',     struct('MinQuality', 0.1, 'MinContrast', 0.1));
options = fillStruct(options, 'detectMinEigenFeatures', struct('MinQuality', 0.01, 'FilterSize', 5));
options = fillStruct(options, 'detectORBFeatures',      struct('ScaleFactor', 1.2, 'NumLevels', 8));
options = fillStruct(options, 'estGeomTransform', ...
    struct('MaxNumTrials', 1000, 'Confidence', 99, 'MaxDistance', 1.5));
end

% =====================================================================
function options = fillStruct(options, fieldName, defaultStruct)
% FILLSTRUCT - Set options.(fieldName) to defaultStruct only when absent/empty.
if ~isfield(options, fieldName) || isempty(options.(fieldName))
    options.(fieldName) = defaultStruct;
end
end

% =====================================================================
function g = normalizeGray(img)
% NORMALIZEGRAY - Collapse to single-channel single in [0,1] for detection.
img = single(img);
if size(img, 3) > 1
    img = mean(img, 3);
end
img = img(:, :, 1);
lo = min(img(:));
hi = max(img(:));
if hi > lo
    g = (img - lo) / (hi - lo);
else
    g = zeros(size(img), 'single');
end
end
