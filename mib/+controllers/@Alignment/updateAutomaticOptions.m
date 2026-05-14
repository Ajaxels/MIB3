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
        '"1" — full resolution;\n"4" — downsample x4 (faster, less precise)'], imgWidth);
else
    imageDownsamplingField = 'imgWidthForAnalysis';
    firstInfoText = sprintf(['Image width for detection (current image = %d px)\n' ...
        '"0" — full resolution;\nsmaller values are faster but less precise'], imgWidth);
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
        sprintf('Minimum step length\n(smaller → slower but more accurate)'), ...
        sprintf('Maximum (initial) step length\n(larger → faster but may diverge)'), ...
        sprintf('Relaxation factor\n(rate at which the optimizer reduces step size)')};
    defAns = {
        struct('Spinner',true,'Value',obj.automaticOptions.(imageDownsamplingField),'Limits',[0 imgWidth],'Step',1, 'Round',true), ...
        struct('Spinner',true,'Value',obj.automaticOptions.amst.PyramidLevels,'Limits',[1 Inf],'Step',1, 'Round',true), ...
        struct('Spinner',true,'Value',obj.automaticOptions.amst.MaximumIterations,'Limits',[1 Inf],'Step',1, 'Round',true), ...
        struct('Spinner',true,'Value',obj.automaticOptions.amst.GradientMagnitudeTolerance,'Limits',[0 Inf],'Step',1, 'Round',false), ...
        struct('Spinner',true,'Value',obj.automaticOptions.amst.MinimumStepLength,'Limits',[0 Inf],'Step',1, 'Round',false), ...
        struct('Spinner',true,'Value',obj.automaticOptions.amst.MaximumStepLength,'Limits',[0 Inf],'Step',1, 'Round',false), ...
        struct('Spinner',true,'Value',obj.automaticOptions.amst.RelaxationFactor,'Limits',[0 Inf],'Step',1, 'Round',false)};
    dlgOpt.WindowWidth  = 560;
    dlgOpt.WindowHeight  = 300;
    dlgOpt.WindowStyle  = 'modal';
    dlgOpt.LabelPosition  = 'left';
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
    sprintf('RANSAC: maximum distance in pixels\n(positive number)')};
estGeomDefs = {
    struct('Spinner',true,'Value',obj.automaticOptions.estGeomTransform.MaxNumTrials,'Limits',[1 Inf],'Step',1, 'Round',true), ...
    struct('Spinner',true,'Value',obj.automaticOptions.estGeomTransform.Confidence,'Limits',[1 Inf],'Step',1, 'Round',false), ...
    struct('Spinner',true,'Value',obj.automaticOptions.estGeomTransform.MaxDistance,'Limits',[1 Inf],'Step',1, 'Round',true)};

dlgOpt = struct('WindowWidth', 560, 'WindowStyle', 'modal', 'Icon', 'puffin_question', 'LabelPosition', 'left', 'Focus', 1);

% --- ORB has a different shape (no rotationInvariance row, ScaleFactor/NumLevels)
isORB = strcmp(featureDetectorType, 'Oriented FAST and rotated BRIEF (ORB)');

if isORB
    % Row 1: downsampling. Row 2-3: ORB params. Row 4-6: RANSAC.
    prompts = [{firstInfoText}, ...
               {sprintf('Scale factor for image decomposition\n(integer > 1)')}, ...
               {sprintf('Number of decomposition levels\n(integer ≥ 1)')}, ...
               estGeomPrompts];
    defAns  = {obj.automaticOptions.(imageDownsamplingField), ...
               obj.automaticOptions.detectORBFeatures.ScaleFactor, ...
               obj.automaticOptions.detectORBFeatures.NumLevels, ...
               estGeomDefs{:}}; %#ok<CCAT>
    dlgOpt.WindowHeight = 300;

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
                sprintf('Strongest feature threshold\n(decrease for more blobs; non-negative scalar)'), ...
                sprintf('Number of octaves\n(integer ≥ 1; typical 1..4)'), ...
                sprintf('Number of scale levels per octave\n(integer ≥ 3; typical 3..6)')}];
             
            defAns = [defAns, {
                struct('Spinner',true,'Value',obj.automaticOptions.detectSURFFeatures.MetricThreshold,'Limits',[0 Inf],'Step',1, 'Round',true), ...
                struct('Spinner',true,'Value',obj.automaticOptions.detectSURFFeatures.NumOctaves,'Limits',[1 Inf],'Step',1, 'Round',true), ...
                struct('Spinner',true,'Value',obj.automaticOptions.detectSURFFeatures.NumScaleLevels,'Limits',[1 Inf],'Step',1, 'Round',true) }];
           dlgOpt.WindowHeight = 370;
    
        case 'Blobs: Detect scale invariant feature transform (SIFT)'
            prompts = [prompts, {
                sprintf('Contrast threshold\n(non-negative scalar in [0,1])'), ...
                sprintf('Edge threshold\n(non-negative scalar ≥ 1)'), ...
                sprintf('Number of layers in each octave\n(integer ≥ 1)'), ...
                sprintf('Sigma of the Gaussian\n(scalar; typical [1,2])')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',obj.automaticOptions.detectSIFTFeatures.ContrastThreshold,'Limits',[0 1],'Step',0.1, 'Round',false), ...
                struct('Spinner',true,'Value',obj.automaticOptions.detectSIFTFeatures.EdgeThreshold,'Limits',[1 Inf],'Step',1, 'Round',false), ...
                struct('Spinner',true,'Value',obj.automaticOptions.detectSIFTFeatures.NumLayersInOctave,'Limits',[1 Inf],'Step',1, 'Round',true), ...
                struct('Spinner',true,'Value',obj.automaticOptions.detectSIFTFeatures.Sigma,'Limits',[0 Inf],'Step',0.1, 'Round',false) }];
            dlgOpt.WindowHeight = 400;
        case 'Regions: Maximally Stable Extremal Regions (MSER) algorithm'
            prompts = [prompts, {
                sprintf('Step size between intensity threshold levels\n(typical 0.8..4)'), ...
                sprintf('Region area range in pixels\ntwo-element vector [minArea maxArea]'), ...
                sprintf('Maximum area variation\n(positive scalar; typical 0.1..1)')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',obj.automaticOptions.detectMSERFeatures.ThresholdDelta,'Limits',[0 Inf],'Step',0.1, 'Round',false), ...
                num2str(obj.automaticOptions.detectMSERFeatures.RegionAreaRange), ...
                struct('Spinner',true,'Value',obj.automaticOptions.detectMSERFeatures.MaxAreaVariation,'Limits',[0 Inf],'Step',0.1, 'Round',false) }];
            dlgOpt.WindowHeight = 370;
        case 'Corners: Harris-Stephens algorithm'
            prompts = [prompts, {
                sprintf('Minimum accepted corner quality\n(scalar in [0,1])'), ...
                sprintf('Gaussian filter dimension\n(odd integer in [3, min(size(I))])')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',obj.automaticOptions.detectHarrisFeatures.MinQuality,'Limits',[0 1],'Step', 0.1, 'Round',false), ...
                struct('Spinner',true,'Value',obj.automaticOptions.detectHarrisFeatures.FilterSize,'Limits',[3 Inf],'Step',2, 'Round',true) }];
           dlgOpt.WindowHeight = 330;
        case 'Corners: Binary Robust Invariant Scalable Keypoints (BRISK)'
            prompts = [prompts, {
                sprintf('Minimum contrast\n(scalar in [0,1])'), ...
                sprintf('Minimum corner quality\n(scalar in [0,1])'), ...
                sprintf('Number of octaves\n(integer ≥ 0; typical 1..4)')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',obj.automaticOptions.detectBRISKFeatures.MinContrast,'Limits',[0 1],'Step', 0.1, 'Round',false), ...
                struct('Spinner',true,'Value',obj.automaticOptions.detectBRISKFeatures.MinQuality,'Limits',[0 1],'Step', 0.1, 'Round',false), ...
                struct('Spinner',true,'Value',obj.automaticOptions.detectBRISKFeatures.NumOctaves,'Limits',[1 Inf],'Step', 1, 'Round',true) }];
            dlgOpt.WindowHeight = 360;
        case 'Corners: Features from Accelerated Segment Test (FAST)'
            prompts = [prompts, {
                sprintf('Minimum corner quality\n(scalar in [0,1])'), ...
                sprintf('Minimum intensity difference between corner\nand surrounding\n(scalar in [0,1])')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',obj.automaticOptions.detectFASTFeatures.MinQuality,'Limits',[0 1],'Step', 0.1, 'Round',false), ...
                struct('Spinner',true,'Value',obj.automaticOptions.detectFASTFeatures.MinContrast,'Limits',[0 1],'Step', 0.1, 'Round',false) }];
            dlgOpt.WindowHeight = 360;

        case 'Corners: Minimum Eigenvalue algorithm'
            prompts = [prompts, {
                sprintf('Minimum corner quality (scalar in [0,1])'), ...
                sprintf('Gaussian filter dimension (odd integer ≥ 3)')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',obj.automaticOptions.detectMinEigenFeatures.MinQuality,'Limits',[0 1],'Step', 0.1, 'Round',false), ...
                struct('Spinner',true,'Value',obj.automaticOptions.detectMinEigenFeatures.FilterSize,'Limits',[3 Inf],'Step', 2, 'Round',true) }];
           dlgOpt.WindowHeight = 310;
        otherwise
            utils.dlgs.showErrorDialog(parentFig, ...
                sprintf('Unknown FeatureDetectorType: "%s"', featureDetectorType), ...
                'controllers.Alignment->updateAutomaticOptions');
            return;
    end

    prompts = [prompts, estGeomPrompts];
    defAns  = [defAns,  estGeomDefs];
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
