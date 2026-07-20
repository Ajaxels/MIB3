function previewFeatureMatch(obj)
% PREVIEWFEATUREMATCH - Visualise feature matches on a representative tile pair.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.previewFeatureMatch()
%
% Feature-based tuning aid, mirroring
% :func:`controllers.Alignment.previewFeaturesBtn_Callback`. Picks the first
% overlapping tile pair from the current ``obj.layout``, reads both FULL tiles
% (feature matching uses whole tiles, not the thin nominal overlap strip),
% detects + matches keypoints with the selected ``FeatureDetectorType`` and the
% parameters in ``obj.automaticOptions``, robust-fits a translation
% (``estgeotform2d`` RANSAC), and renders the two tiles **stitched at the
% recovered offset** (``imfuse`` false-colour: tile *i* green, tile *j* magenta,
% grey where they agree) with the inlier keypoints marked on top. A clean seam
% and tightly overlapping green/magenta keypoints mean a good registration; the
% recovered shift and inlier ratio are shown in the title, so the effect of a
% settings change is visible immediately — the feedback loop the Alignment
% preview provides.
%
% No stitching is applied. Requires a layout with at least one overlapping pair
% (select input tiles first); shows an informational dialog otherwise.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.previewFeatureMatch: triggered\n');
end

parentFig = obj.view.gui;

if numel(obj.layout) < 2
    infoOptions.MsgBoxOnly  = true;
    infoOptions.Icon        = 'puffin_info';
    infoOptions.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(parentFig, ...
        'Load at least two overlapping tiles first (Browse), then adjust the feature settings to preview the matches.', ...
        {}, {}, 'Feature preview', infoOptions);
    return;
end

% First overlapping XY pair (feature matching is a within-layer registration).
pairs = utils.stitch.findNeighborPairs(obj.layout, struct('minOverlapPx', 16));
xyPairs = pairs(~strcmp({pairs.direction}, 'z'));
if isempty(xyPairs)
    infoOptions.MsgBoxOnly  = true;
    infoOptions.Icon        = 'puffin_info';
    infoOptions.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(parentFig, ...
        'No overlapping tile pair found in the current layout — cannot preview feature matches.', ...
        {}, {}, 'Feature preview', infoOptions);
    return;
end
pair = xyPairs(1);

% Read the two FULL tiles (first channel; middle Z slice for 3D stacks).
readerFcn = utils.stitch.makeTileReader(obj.layout);
imageA = midSliceGray(readerFcn(pair.i));
imageB = midSliceGray(readerFcn(pair.j));

% Detector + parameters from the current selection.
featureOptions = obj.buildFeatureOptions();
featureDetectorType = featureOptions.featureDetector;

% Optional detection downsampling (scale matched locations back afterwards).
scaleBack = 1;
if featureOptions.downsampleFactor > 1
    ratio = 1 / featureOptions.downsampleFactor;
    imageA = imresize(imageA, ratio, 'bilinear');
    imageB = imresize(imageB, ratio, 'bilinear');
    scaleBack = featureOptions.downsampleFactor;
end

pointsA = utils.align.detectFeatures(imageA, featureDetectorType, featureOptions);
pointsB = utils.align.detectFeatures(imageB, featureDetectorType, featureOptions);
if isempty(pointsA) || isempty(pointsB) || pointsA.Count < 3 || pointsB.Count < 3
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('Too few features detected with "%s". Loosen the detector threshold and retry.', ...
                featureDetectorType), 'Feature preview');
    return;
end

if strcmp(featureDetectorType, 'Oriented FAST and rotated BRIEF (ORB)')
    [featuresA, validA] = extractFeatures(imageA, pointsA);
    [featuresB, validB] = extractFeatures(imageB, pointsB);
else
    [featuresA, validA] = extractFeatures(imageA, pointsA, 'Upright', featureOptions.rotationInvariance);
    [featuresB, validB] = extractFeatures(imageB, pointsB, 'Upright', featureOptions.rotationInvariance);
end

indexPairs = matchFeatures(featuresA, featuresB, 'Unique', true);
if isempty(indexPairs)
    utils.dlgs.showErrorDialog(parentFig, ...
        'No matching descriptors found. Adjust the detector settings and retry.', ...
        'Feature preview');
    return;
end
matchedA = validA(indexPairs(:, 1));
matchedB = validB(indexPairs(:, 2));

% Robust translation fit (RANSAC), matching utils.stitch.featureShift.
try
    [tform, inlierIdx, status] = estgeotform2d( ...
        matchedA.Location * scaleBack, matchedB.Location * scaleBack, 'translation', ...
        'MaxNumTrials', featureOptions.estGeomTransform.MaxNumTrials, ...
        'Confidence',   featureOptions.estGeomTransform.Confidence, ...
        'MaxDistance',  featureOptions.estGeomTransform.MaxDistance);
catch fitError
    utils.dlgs.showErrorDialog(parentFig, fitError, 'Feature preview: fit failed');
    return;
end
if status ~= 0
    utils.dlgs.showErrorDialog(parentFig, ...
        'RANSAC could not fit a translation from the matches. Adjust the detector settings and retry.', ...
        'Feature preview');
    return;
end
T = double(tform.A);
shiftYX = [T(2, 3), T(1, 3)];   % [dy dx], same convention as featureShift
inlierRatio = nnz(inlierIdx) / numel(inlierIdx);

% ---- Build the STITCHED composite: place both tiles at the recovered offset.
% tform maps A->B, so its inverse warps tile B into tile A's coordinate frame;
% imfuse then blends them on the shared union canvas (green = tile i, magenta =
% tile j, grey where they agree). imwarp/imfuse compute the referencing so the
% overlap is drawn aligned — a clean seam means the registration is good.
invTform = invert(tform);
refA = imref2d(size(imageA));
[warpedB, refB] = imwarp(imageB, invTform);
[composite, refComposite] = imfuse(imageA, refA, warpedB, refB, ...
    'falsecolor', 'Scaling', 'joint', 'ColorChannels', [2 1 2]);   % A→green, B→magenta, grey=agreement

% Inlier keypoint locations in the composite's pixel coordinates: tile-A points
% are already in A's frame; tile-B points are pushed through invTform into it.
inlierA = matchedA(inlierIdx).Location;                          % [x y] in A frame
inlierBinA = transformPointsForward(invTform, matchedB(inlierIdx).Location);
[ax, ay] = worldToIntrinsicSafe(refComposite, inlierA(:, 1),    inlierA(:, 2));
[bx, by] = worldToIntrinsicSafe(refComposite, inlierBinA(:, 1), inlierBinA(:, 2));

% ---- Render in a dedicated tagged figure (reused across previews).
hFig = findall(groot, 'Type', 'figure', 'Tag', 'mib_StitchFeaturePreview');
if isempty(hFig)
    hFig = figure('Tag', 'mib_StitchFeaturePreview', 'NumberTitle', 'off', ...
        'Name', 'MIB: stitch feature preview');
else
    figure(hFig);
    clf(hFig);
end
hAxes = axes('Parent', hFig);
imshow(composite, 'Parent', hAxes);
hold(hAxes, 'on');
% Matched inliers: the two tiles' keypoints should land on top of each other
% after stitching — a short green→magenta tie-line means a small residual.
plot(hAxes, [ax, bx]', [ay, by]', 'y-', 'LineWidth', 0.5);
plot(hAxes, ax, ay, 'go', 'MarkerSize', 6, 'LineWidth', 1);
plot(hAxes, bx, by, 'm+', 'MarkerSize', 6, 'LineWidth', 1);
hold(hAxes, 'off');
title(hAxes, sprintf('Tiles %d ↔ %d stitched — %d/%d inliers (ratio %.2f), shift [dy %.1f, dx %.1f] px', ...
    pair.i, pair.j, nnz(inlierIdx), numel(inlierIdx), inlierRatio, shiftYX(1), shiftYX(2)));

end

% =====================================================================
function g = midSliceGray(tile)
% MIDSLICEGRAY - Middle Z slice, first channel, as a single-channel image.
% makeTileReader returns [H W D C]; feature detection wants a 2-D image.
midZ = max(1, ceil(size(tile, 3) / 2));
g = tile(:, :, midZ, 1);
end

% =====================================================================
function [xi, yi] = worldToIntrinsicSafe(spatialRef, xw, yw)
% WORLDTOINTRINSICSAFE - World→intrinsic pixel coords for overlaying points on
% the imfuse composite (its intrinsic frame == the union world frame).
[xi, yi] = worldToIntrinsic(spatialRef, xw, yw);
end
