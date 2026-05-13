function previewFeaturesBtn_Callback(obj)
% PREVIEWFEATURESBTN_CALLBACK - Visualise feature matches between two consecutive slices.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.previewFeaturesBtn_Callback()
%
% Detects features on the current slice and the next slice using the
% feature detector selected in the ``FeatureDetectorType`` widget, matches
% the descriptors, robust-fits a 2-D geometric transform (RANSAC via
% ``estgeotform2d``), and renders the matches in a dedicated figure
% (two subplots — *with outliers* and *inliers only*). No alignment is
% applied; this is a tuning aid for the feature-based alignment
% algorithms.
%
% The downsampling ratio matches what the alignment algorithm itself
% would use:
%
% - ``Automatic feature-based``    → ``imgWidthForAnalysis / Width``
% - ``Automatic feature-based v2`` → ``1 / imgDownsamplingFactorForAnalysis``
%
% No-op for ``AMST: median-smoothed template`` (the *Preview* button is
% relabeled *Settings* in that mode).

% Updates
%

% Parent figure for any dialogs — ``obj.view`` is empty in batch mode
if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

% --- Let the user tune detector / RANSAC parameters first
status = obj.updateAutomaticOptions();
if status == 0; return; end
if strcmp(obj.BatchOpt.Algorithm{1}, 'AMST: median-smoothed template'); return;  end


id = obj.mibModel.getActiveId();
optionsGetData = struct('blockModeSwitch', 0);
[~, Width, Depth] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, optionsGetData);
if Depth < 2
    utils.dlgs.showErrorDialog(parentFig, ...
        'Feature preview requires at least two slices in the active dataset.', ...
        'Alignment');
    return;
end

% Colour channel
colorCh = find(ismember(obj.BatchOpt.ColorChannel{2}, obj.BatchOpt.ColorChannel{1}));
if isempty(colorCh); colorCh = 1; end

% Downsampling ratio (matches AutomaticFeatureBased*Alignment behaviour)
switch obj.BatchOpt.Algorithm{1}
    case 'Automatic feature-based'
        if obj.automaticOptions.imgWidthForAnalysis == 0
            ratio = 1;
        else
            ratio = obj.automaticOptions.imgWidthForAnalysis / Width;
        end
    case 'Automatic feature-based v2'
        ratio = 1 / obj.automaticOptions.imgDownsamplingFactorForAnalysis;
    otherwise
        ratio = 1;
end

% Pick the slice pair — current + next, clamped to the end of the stack
sliceNo = obj.mibModel.I{id}.slices{obj.mibModel.I{id}.orientation}(1);
if sliceNo >= Depth; sliceNo = Depth - 1; end

original  = cell2mat(obj.mibModel.getData2D('image', sliceNo,     [], colorCh, optionsGetData));
distorted = cell2mat(obj.mibModel.getData2D('image', sliceNo + 1, [], colorCh, optionsGetData));
if isempty(original) || isempty(distorted)
    utils.dlgs.showErrorDialog(parentFig, ...
        'Feature preview requires at least two images to be loaded.', 'Alignment');
    return;
end
if ratio ~= 1
    original  = imresize(original,  ratio, 'bicubic');
    distorted = imresize(distorted, ratio, 'bicubic');
end

% --- Detect features
featureDetectorType = obj.BatchOpt.FeatureDetectorType{1};
ptsOriginal  = utils.align.detectFeatures(original,  featureDetectorType, obj.automaticOptions);
ptsDistorted = utils.align.detectFeatures(distorted, featureDetectorType, obj.automaticOptions);
if isempty(ptsOriginal) || isempty(ptsDistorted)
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('No features detected with "%s". Adjust detector settings and retry.', ...
                featureDetectorType), 'Alignment');
    return;
end

% --- Extract feature descriptors
if ~strcmp(featureDetectorType, 'Oriented FAST and rotated BRIEF (ORB)')
    [featuresOriginal,  validPtsOriginal]  = extractFeatures(original,  ptsOriginal, ...
        'Upright', obj.automaticOptions.rotationInvariance);
    [featuresDistorted, validPtsDistorted] = extractFeatures(distorted, ptsDistorted, ...
        'Upright', obj.automaticOptions.rotationInvariance);
else
    [featuresOriginal,  validPtsOriginal]  = extractFeatures(original,  ptsOriginal);
    [featuresDistorted, validPtsDistorted] = extractFeatures(distorted, ptsDistorted);
end

% --- Match descriptors
indexPairs = matchFeatures(featuresOriginal, featuresDistorted);
if isempty(indexPairs)
    utils.dlgs.showErrorDialog(parentFig, ...
        'No matching descriptors found. Adjust detector settings and retry.', ...
        'Alignment');
    return;
end
matchedOriginal  = validPtsOriginal(indexPairs(:, 1));
matchedDistorted = validPtsDistorted(indexPairs(:, 2));

% --- Robust transform fit (RANSAC)
try
    [~, inlierIdx] = estgeotform2d(matchedDistorted, matchedOriginal, ...
        obj.BatchOpt.TransformationType{1}, ...
        'MaxNumTrials', obj.automaticOptions.estGeomTransform.MaxNumTrials, ...
        'Confidence',   obj.automaticOptions.estGeomTransform.Confidence, ...
        'MaxDistance',  obj.automaticOptions.estGeomTransform.MaxDistance);
catch ME
    utils.dlgs.showErrorDialog(parentFig, ME, 'Not enough points');
    return;
end

% --- Render in a dedicated figure (uifigure so it shows above the AppContainer)
hFig = findall(groot, 'Type', 'figure', 'Tag', 'mib_FeaturePreview');
if isempty(hFig)
    hFig = figure('Tag', 'mib_FeaturePreview', 'NumberTitle', 'off', ...
        'Name', 'MIB: feature preview');
else
    figure(hFig);
    clf(hFig);
end
hS1 = subplot(1, 2, 1, 'Parent', hFig);
showMatchedFeatures(original, distorted, matchedOriginal, matchedDistorted, 'Parent', hS1);
title(hS1, sprintf('Matched points with outliers (slice %d → %d)', sliceNo, sliceNo + 1));
hS2 = subplot(1, 2, 2, 'Parent', hFig);
showMatchedFeatures(original, distorted, ...
    matchedOriginal(inlierIdx, :), matchedDistorted(inlierIdx, :), 'Parent', hS2);
title(hS2, sprintf('Inliers only (%d / %d)', nnz(inlierIdx), numel(inlierIdx)));

end
