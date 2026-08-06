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
% settings change is visible immediately - the feedback loop the Alignment
% preview provides.
%
% A ``downsampleFactor`` above 1 affects DETECTION ONLY: keypoints are found on
% resized copies and their locations scaled back, while the composite is
% always BUILT from the full-resolution tiles (the title notes the detection
% scale). For real-world tile sizes that composite can exceed a GPU's max
% texture side (commonly ~16384 px) - MATLAB then creates the image object
% without error, but the driver silently fails to rasterize it while the
% point/tie-line overlay still renders, i.e. only markers show, no image. To
% avoid this, the composite is downsized for DISPLAY ONLY past a safe cap
% (title notes the display scale too); detection/matching/the fitted shift are
% unaffected.
%
% No stitching is applied. Requires a layout with at least one overlapping pair
% (select input tiles first); shows an informational dialog otherwise.
%
% Shows a Cancelable progress dialog spanning tile reading, feature
% detection/matching, transform fitting, AND composite building + the
% display-downsize step above - reading/warping/fusing full-resolution tiles
% off disk can take a noticeable time for large files, and without it the app
% would look frozen. Cancel is polled between stages (read A, read B, detect,
% match, fit, build composite, resize for display); since each stage itself is
% one blocking call, a click takes effect at the next stage boundary, not
% mid-call. Cancelling closes the dialog and returns without opening the
% preview figure.
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
        'No overlapping tile pair found in the current layout - cannot preview feature matches.', ...
        {}, {}, 'Feature preview', infoOptions);
    return;
end
pair = xyPairs(1);

% Reading full-resolution tiles off disk and detecting/matching features on them
% can take a noticeable time for large files - show progress so the app does not
% look frozen while it prepares the preview, and let the user bail out of it.
progressDialog = uiprogressdlg(parentFig, 'Value', 0, 'Cancelable', 'on', ...
    'Message', 'Reading tile images...', 'Title', 'Feature preview');

% Read the two FULL tiles (first channel; middle Z slice for 3D stacks).
readerFcn = utils.stitch.makeTileReader(obj.layout);
imageA = midSliceGray(readerFcn(pair.i));
progressDialog.Value = 0.2;
drawnow;
if progressDialog.CancelRequested; delete(progressDialog); return; end
imageB = midSliceGray(readerFcn(pair.j));
progressDialog.Value = 0.35;
drawnow;
if progressDialog.CancelRequested; delete(progressDialog); return; end

% Detector + parameters from the current selection.
featureOptions = obj.buildFeatureOptions();
featureDetectorType = featureOptions.featureDetector;

% Optional detection downsampling. Detection/matching run on the RESIZED copies,
% but imageA/imageB stay full-resolution: the fitted tform is in full-resolution
% units (locations are scaled back before the fit), so the composite and the
% overlaid keypoints below must be in that same frame - mixing a full-resolution
% tform with downsampled images places the tiles at factor-times the true offset.
scaleBack = 1;
detectA = imageA;
detectB = imageB;
if featureOptions.downsampleFactor > 1
    ratio = 1 / featureOptions.downsampleFactor;
    detectA = imresize(imageA, ratio, 'bilinear');
    detectB = imresize(imageB, ratio, 'bilinear');
    scaleBack = featureOptions.downsampleFactor;
end

progressDialog.Message = 'Detecting features...';
drawnow;
pointsA = utils.align.detectFeatures(detectA, featureDetectorType, featureOptions);
pointsB = utils.align.detectFeatures(detectB, featureDetectorType, featureOptions);
progressDialog.Value = 0.6;
if progressDialog.CancelRequested; delete(progressDialog); return; end
if isempty(pointsA) || isempty(pointsB) || pointsA.Count < 3 || pointsB.Count < 3
    delete(progressDialog);
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('Too few features detected with "%s". Loosen the detector threshold and retry.', ...
                featureDetectorType), 'Feature preview');
    return;
end

if strcmp(featureDetectorType, 'Oriented FAST and rotated BRIEF (ORB)')
    [featuresA, validA] = extractFeatures(detectA, pointsA);
    [featuresB, validB] = extractFeatures(detectB, pointsB);
else
    [featuresA, validA] = extractFeatures(detectA, pointsA, 'Upright', featureOptions.rotationInvariance);
    [featuresB, validB] = extractFeatures(detectB, pointsB, 'Upright', featureOptions.rotationInvariance);
end

progressDialog.Message = 'Matching features...';
progressDialog.Value = 0.75;
drawnow;
if progressDialog.CancelRequested; delete(progressDialog); return; end
indexPairs = matchFeatures(featuresA, featuresB, 'Unique', true);
if isempty(indexPairs)
    delete(progressDialog);
    utils.dlgs.showErrorDialog(parentFig, ...
        'No matching descriptors found. Adjust the detector settings and retry.', ...
        'Feature preview');
    return;
end
matchedA = validA(indexPairs(:, 1));
matchedB = validB(indexPairs(:, 2));

% Robust translation fit (RANSAC), matching utils.stitch.featureShift.
progressDialog.Message = 'Fitting transform...';
progressDialog.Value = 0.9;
drawnow;
if progressDialog.CancelRequested; delete(progressDialog); return; end
try
    [tform, inlierIdx, status] = estgeotform2d( ...
        matchedA.Location * scaleBack, matchedB.Location * scaleBack, 'translation', ...
        'MaxNumTrials', featureOptions.estGeomTransform.MaxNumTrials, ...
        'Confidence',   featureOptions.estGeomTransform.Confidence, ...
        'MaxDistance',  featureOptions.estGeomTransform.MaxDistance);
catch fitError
    delete(progressDialog);
    utils.dlgs.showErrorDialog(parentFig, fitError, 'Feature preview: fit failed');
    return;
end
if status ~= 0
    delete(progressDialog);
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
% overlap is drawn aligned - a clean seam means the registration is good.
% Full-resolution tiles here can be large, so this stays under the same
% progress dialog as the rest of the preparation.
progressDialog.Message = 'Building composite...';
progressDialog.Value = 0.95;
drawnow;
if progressDialog.CancelRequested; delete(progressDialog); return; end
invTform = invert(tform);
refA = imref2d(size(imageA));
[warpedB, refB] = imwarp(imageB, invTform);
[composite, refComposite] = imfuse(imageA, refA, warpedB, refB, ...
    'falsecolor', 'Scaling', 'joint', 'ColorChannels', [2 1 2]);   % A→green, B→magenta, grey=agreement

% Inlier keypoint locations in the composite's pixel coordinates. Detected
% locations are scaled back to full resolution first (the frame the composite and
% invTform live in); tile-A points are then already in A's frame, tile-B points
% are pushed through invTform into it.
inlierA = matchedA(inlierIdx).Location * scaleBack;              % [x y] in A frame
inlierBinA = transformPointsForward(invTform, matchedB(inlierIdx).Location * scaleBack);
[ax, ay] = worldToIntrinsicSafe(refComposite, inlierA(:, 1),    inlierA(:, 2));
[bx, by] = worldToIntrinsicSafe(refComposite, inlierBinA(:, 1), inlierBinA(:, 2));

% The composite is always built from the FULL-resolution tiles regardless of
% the detection downsampleFactor (a downsample setting only thins out
% keypoint search, it does not shrink the tiles themselves) - with tiles the
% size of a real microscope mosaic (tens of thousands of px/side) the fused
% canvas can exceed a GPU's max texture side (commonly ~16384 px). MATLAB then
% builds the image object without error but the driver silently fails to
% rasterize it, while the vector point/tie-line overlay below still renders -
% which looks exactly like "only the points show, no images". Downsize the
% composite for DISPLAY ONLY past a safe cap; detection, matching and the
% fitted shift above already ran at the user-chosen resolution and are
% unaffected.
maxPreviewDim = 4096;
compositeMaxDim = max(size(composite, 1), size(composite, 2));
displayScale = min(1, maxPreviewDim / compositeMaxDim);
if displayScale < 1
    progressDialog.Message = 'Resizing preview...';
    progressDialog.Value = 0.98;
    drawnow;
    if progressDialog.CancelRequested; delete(progressDialog); return; end
    composite = imresize(composite, displayScale, 'bilinear');
    ax = ax * displayScale; ay = ay * displayScale;
    bx = bx * displayScale; by = by * displayScale;
end
delete(progressDialog);

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
% after stitching - a short green→magenta tie-line means a small residual.
plot(hAxes, [ax, bx]', [ay, by]', 'y-', 'LineWidth', 0.5);
plot(hAxes, ax, ay, 'go', 'MarkerSize', 6, 'LineWidth', 1);
plot(hAxes, bx, by, 'm+', 'MarkerSize', 6, 'LineWidth', 1);
hold(hAxes, 'off');
% Say when detection ran downsampled - otherwise a changed factor gives no visible
% feedback (the composite is always drawn at full resolution).
if scaleBack > 1
    detectionNote = sprintf(', detected at 1/%g scale', scaleBack);
else
    detectionNote = '';
end
if displayScale < 1
    displayNote = sprintf(', displayed at 1/%.3g scale', 1 / displayScale);
else
    displayNote = '';
end
title(hAxes, sprintf('Tiles %d ↔ %d stitched - %d/%d inliers (ratio %.2f), shift [dy %.1f, dx %.1f] px%s%s', ...
    pair.i, pair.j, nnz(inlierIdx), numel(inlierIdx), inlierRatio, shiftYX(1), shiftYX(2), detectionNote, displayNote));

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
