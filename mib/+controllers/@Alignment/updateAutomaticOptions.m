function status = updateAutomaticOptions(obj)
% UPDATEAUTOMATICOPTIONS - Interactive settings dialog for the feature-based / AMST options.
%
% Syntax:
%   .. code-block:: matlab
%
%      status = obj.updateAutomaticOptions()
%
% Pops an :func:`utils.dlgs.inputUniversalDlg` settings dialog tailored to
% the currently selected ``Algorithm``:
%
% - ``AMST: median-smoothed template`` — image downsampling + pyramid
%   levels + ``imregconfig`` optimizer parameters (maximum iterations,
%   gradient-magnitude tolerance, min / max step length, relaxation
%   factor).
% - ``Automatic feature-based`` / ``Automatic feature-based v2`` —
%   image downsampling, rotation-invariance flag, the per-detector
%   parameters for the currently selected ``FeatureDetectorType``, and
%   the ``estgeotform2d`` (RANSAC) settings.
%
% Updates ``obj.automaticOptions`` in place; the algorithm methods read
% from there.
%
% Output Arguments:
%   - **status** — ``1`` when the user clicked OK and settings were
%     applied; ``0`` when the dialog was cancelled.

% Updates
%

status = 0;

% Parent figure for the dialog
if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

% Current image width (used in the downsampling prompt text)
id = obj.mibModel.getActiveId();
[~, imgWidth] = obj.mibModel.I{id}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));

% Which downsampling field is active for the current algorithm
if strcmp(obj.BatchOpt.Algorithm{1}, 'Automatic feature-based v2')
    imageDownsamplingField = 'imgDownsamplingFactorForAnalysis';
    firstInfoText = sprintf(['Downsampling factor for detection (image width = %d px)\n' ...
        '"1" — full resolution; "4" — downsample x4 (faster, less precise)'], imgWidth);
else
    imageDownsamplingField = 'imgWidthForAnalysis';
    firstInfoText = sprintf(['Image width for detection (current image = %d px)\n' ...
        '"0" — full resolution; smaller values are faster but less precise'], imgWidth);
end

% ============================================================================
% AMST branch — register-to-template optimizer parameters
% ============================================================================
if strcmp(obj.BatchOpt.Algorithm{1}, 'AMST: median-smoothed template')
    dlgTitle = 'AMST settings';
    prompts = {
        firstInfoText, ...
        'Number of multi-level image pyramid levels', ...
        'Maximum number of iterations', ...
        'Gradient magnitude tolerance', ...
        'Minimum step length (smaller → slower but more accurate)', ...
        'Maximum (initial) step length (larger → faster but may diverge)', ...
        'Relaxation factor (rate at which the optimizer reduces step size)'};
    defAns = {
        obj.automaticOptions.(imageDownsamplingField), ...
        obj.automaticOptions.amst.PyramidLevels, ...
        obj.automaticOptions.amst.MaximumIterations, ...
        obj.automaticOptions.amst.GradientMagnitudeTolerance, ...
        obj.automaticOptions.amst.MinimumStepLength, ...
        obj.automaticOptions.amst.MaximumStepLength, ...
        obj.automaticOptions.amst.RelaxationFactor};
    dlgOpt.PromptLines  = [3, 1, 1, 1, 2, 2, 2];
    dlgOpt.WindowWidth  = 720;
    dlgOpt.WindowStyle  = 'modal';
    dlgOpt.HelpUrl      = 'https://se.mathworks.com/help/images/ref/registration.optimizer.regularstepgradientdescent.html';
    dlgOpt.Icon         = 'puffin_question';

    answer = utils.dlgs.inputUniversalDlg(parentFig, '', prompts, defAns, dlgTitle, dlgOpt);
    if isempty(answer); return; end

    obj.automaticOptions.(imageDownsamplingField)        = answer{1};
    obj.automaticOptions.amst.PyramidLevels              = answer{2};
    obj.automaticOptions.amst.MaximumIterations          = answer{3};
    obj.automaticOptions.amst.GradientMagnitudeTolerance = answer{4};
    obj.automaticOptions.amst.MinimumStepLength          = answer{5};
    obj.automaticOptions.amst.MaximumStepLength          = answer{6};
    obj.automaticOptions.amst.RelaxationFactor           = answer{7};
    status = 1;
    return;
end

% ============================================================================
% Feature-based branch — per-detector settings + RANSAC
% ============================================================================
featureDetectorType = obj.BatchOpt.FeatureDetectorType{1};
dlgTitle = ['Feature detection options — ' featureDetectorType];

% --- Pre-build the RANSAC (estgeotform2d) prompts + defaults; they're appended
%     to every per-detector dialog as the last three rows.
estGeomPrompts = {
    sprintf('RANSAC: maximum number of random trials\n(positive integer; increase for robustness)'), ...
    sprintf('RANSAC: confidence of finding inliers\n(0..100; increase for robustness)'), ...
    sprintf('RANSAC: maximum distance in pixels (positive number)')};
estGeomDefs = {
    obj.automaticOptions.estGeomTransform.MaxNumTrials, ...
    obj.automaticOptions.estGeomTransform.Confidence, ...
    obj.automaticOptions.estGeomTransform.MaxDistance};
estGeomLines = [3, 2, 1];

dlgOpt = struct('WindowWidth', 760, 'WindowStyle', 'modal', 'Icon', 'puffin_question');

% --- ORB has a different shape (no rotationInvariance row, ScaleFactor/NumLevels)
isORB = strcmp(featureDetectorType, 'Oriented FAST and rotated BRIEF (ORB)');

if isORB
    % Row 1: downsampling. Row 2-3: ORB params. Row 4-6: RANSAC.
    prompts = [{firstInfoText}, ...
               {sprintf('Scale factor for image decomposition (integer > 1)')}, ...
               {sprintf('Number of decomposition levels (integer ≥ 1)')}, ...
               estGeomPrompts];
    defAns  = {obj.automaticOptions.(imageDownsamplingField), ...
               obj.automaticOptions.detectORBFeatures.ScaleFactor, ...
               obj.automaticOptions.detectORBFeatures.NumLevels, ...
               estGeomDefs{:}}; %#ok<CCAT>
    dlgOpt.PromptLines = [3, 2, 2, estGeomLines];

    answer = utils.dlgs.inputUniversalDlg(parentFig, '', prompts, defAns, dlgTitle, dlgOpt);
    if isempty(answer); return; end

    obj.automaticOptions.detectORBFeatures.ScaleFactor = answer{2};
    obj.automaticOptions.detectORBFeatures.NumLevels   = answer{3};
else
    % Non-ORB: Row 1 = downsampling, Row 2 = rotation invariance (checkbox),
    % then per-detector rows, then RANSAC.
    prompts = {firstInfoText, 'Rotation invariance (descriptors orientation-agnostic)'};
    defAns  = {obj.automaticOptions.(imageDownsamplingField), ...
               logical(obj.automaticOptions.rotationInvariance)};

    switch featureDetectorType
        case 'Blobs: Speeded-Up Robust Features (SURF) algorithm'
            prompts = [prompts, {
                sprintf('Strongest feature threshold (decrease for more blobs; non-negative scalar)'), ...
                sprintf('Number of octaves (integer ≥ 1; typical 1..4)'), ...
                sprintf('Number of scale levels per octave (integer ≥ 3; typical 3..6)')}];
            defAns = [defAns, {
                obj.automaticOptions.detectSURFFeatures.MetricThreshold, ...
                obj.automaticOptions.detectSURFFeatures.NumOctaves, ...
                obj.automaticOptions.detectSURFFeatures.NumScaleLevels}];
            detectorLines = [2, 1, 1];

        case 'Blobs: Detect scale invariant feature transform (SIFT)'
            prompts = [prompts, {
                sprintf('Contrast threshold (non-negative scalar in [0,1])'), ...
                sprintf('Edge threshold (non-negative scalar ≥ 1)'), ...
                sprintf('Number of layers in each octave (integer ≥ 1)'), ...
                sprintf('Sigma of the Gaussian (scalar; typical [1,2])')}];
            defAns = [defAns, {
                obj.automaticOptions.detectSIFTFeatures.ContrastThreshold, ...
                obj.automaticOptions.detectSIFTFeatures.EdgeThreshold, ...
                obj.automaticOptions.detectSIFTFeatures.NumLayersInOctave, ...
                obj.automaticOptions.detectSIFTFeatures.Sigma}];
            detectorLines = [2, 2, 1, 1];

        case 'Regions: Maximally Stable Extremal Regions (MSER) algorithm'
            prompts = [prompts, {
                sprintf('Step size between intensity threshold levels (typical 0.8..4)'), ...
                sprintf('Region area range in pixels — two-element vector [minArea maxArea]'), ...
                sprintf('Maximum area variation (positive scalar; typical 0.1..1)')}];
            defAns = [defAns, {
                obj.automaticOptions.detectMSERFeatures.ThresholdDelta, ...
                num2str(obj.automaticOptions.detectMSERFeatures.RegionAreaRange), ...
                obj.automaticOptions.detectMSERFeatures.MaxAreaVariation}];
            detectorLines = [2, 2, 1];

        case 'Corners: Harris-Stephens algorithm'
            prompts = [prompts, {
                sprintf('Minimum accepted corner quality (scalar in [0,1])'), ...
                sprintf('Gaussian filter dimension (odd integer in [3, min(size(I))])')}];
            defAns = [defAns, {
                obj.automaticOptions.detectHarrisFeatures.MinQuality, ...
                obj.automaticOptions.detectHarrisFeatures.FilterSize}];
            detectorLines = [2, 2];

        case 'Corners: Binary Robust Invariant Scalable Keypoints (BRISK)'
            prompts = [prompts, {
                sprintf('Minimum contrast (scalar in [0,1])'), ...
                sprintf('Minimum corner quality (scalar in [0,1])'), ...
                sprintf('Number of octaves (integer ≥ 0; typical 1..4)')}];
            defAns = [defAns, {
                obj.automaticOptions.detectBRISKFeatures.MinContrast, ...
                obj.automaticOptions.detectBRISKFeatures.MinQuality, ...
                obj.automaticOptions.detectBRISKFeatures.NumOctaves}];
            detectorLines = [2, 2, 1];

        case 'Corners: Features from Accelerated Segment Test (FAST)'
            prompts = [prompts, {
                sprintf('Minimum corner quality (scalar in [0,1])'), ...
                sprintf('Minimum intensity difference between corner and surrounding (scalar in [0,1])')}];
            defAns = [defAns, {
                obj.automaticOptions.detectFASTFeatures.MinQuality, ...
                obj.automaticOptions.detectFASTFeatures.MinContrast}];
            detectorLines = [2, 2];

        case 'Corners: Minimum Eigenvalue algorithm'
            prompts = [prompts, {
                sprintf('Minimum corner quality (scalar in [0,1])'), ...
                sprintf('Gaussian filter dimension (odd integer ≥ 3)')}];
            defAns = [defAns, {
                obj.automaticOptions.detectMinEigenFeatures.MinQuality, ...
                obj.automaticOptions.detectMinEigenFeatures.FilterSize}];
            detectorLines = [2, 2];

        otherwise
            utils.dlgs.showErrorDialog(parentFig, ...
                sprintf('Unknown FeatureDetectorType: "%s"', featureDetectorType), ...
                'Settings');
            return;
    end

    prompts = [prompts, estGeomPrompts];
    defAns  = [defAns,  estGeomDefs];
    dlgOpt.PromptLines = [3, 1, detectorLines, estGeomLines];

    answer = utils.dlgs.inputUniversalDlg(parentFig, '', prompts, defAns, dlgTitle, dlgOpt);
    if isempty(answer); return; end

    obj.automaticOptions.rotationInvariance = logical(answer{2});

    switch featureDetectorType
        case 'Blobs: Speeded-Up Robust Features (SURF) algorithm'
            obj.automaticOptions.detectSURFFeatures.MetricThreshold = answer{3};
            obj.automaticOptions.detectSURFFeatures.NumOctaves      = answer{4};
            obj.automaticOptions.detectSURFFeatures.NumScaleLevels  = answer{5};
        case 'Blobs: Detect scale invariant feature transform (SIFT)'
            obj.automaticOptions.detectSIFTFeatures.ContrastThreshold = answer{3};
            obj.automaticOptions.detectSIFTFeatures.EdgeThreshold     = answer{4};
            obj.automaticOptions.detectSIFTFeatures.NumLayersInOctave = answer{5};
            obj.automaticOptions.detectSIFTFeatures.Sigma             = answer{6};
        case 'Regions: Maximally Stable Extremal Regions (MSER) algorithm'
            obj.automaticOptions.detectMSERFeatures.ThresholdDelta   = answer{3};
            % RegionAreaRange returned as a string from the text edit — parse to vector
            rar = str2num(answer{4}); %#ok<ST2NM>
            if ~isempty(rar) && numel(rar) == 2
                obj.automaticOptions.detectMSERFeatures.RegionAreaRange = rar;
            end
            obj.automaticOptions.detectMSERFeatures.MaxAreaVariation = answer{5};
        case 'Corners: Harris-Stephens algorithm'
            obj.automaticOptions.detectHarrisFeatures.MinQuality = answer{3};
            obj.automaticOptions.detectHarrisFeatures.FilterSize = answer{4};
        case 'Corners: Binary Robust Invariant Scalable Keypoints (BRISK)'
            obj.automaticOptions.detectBRISKFeatures.MinContrast = answer{3};
            obj.automaticOptions.detectBRISKFeatures.MinQuality  = answer{4};
            obj.automaticOptions.detectBRISKFeatures.NumOctaves  = answer{5};
        case 'Corners: Features from Accelerated Segment Test (FAST)'
            obj.automaticOptions.detectFASTFeatures.MinQuality  = answer{3};
            obj.automaticOptions.detectFASTFeatures.MinContrast = answer{4};
        case 'Corners: Minimum Eigenvalue algorithm'
            obj.automaticOptions.detectMinEigenFeatures.MinQuality = answer{3};
            obj.automaticOptions.detectMinEigenFeatures.FilterSize = answer{4};
    end
end

% --- RANSAC settings (last 3 entries in every non-ORB and ORB dialog)
obj.automaticOptions.estGeomTransform.MaxNumTrials = answer{end - 2};
obj.automaticOptions.estGeomTransform.Confidence   = answer{end - 1};
obj.automaticOptions.estGeomTransform.MaxDistance  = answer{end};

% --- Guard against zero downsampling factor for v2
if strcmp(obj.BatchOpt.Algorithm{1}, 'Automatic feature-based v2') && answer{1} == 0
    answer{1} = 1;
end
obj.automaticOptions.(imageDownsamplingField) = answer{1};

status = 1;
end
