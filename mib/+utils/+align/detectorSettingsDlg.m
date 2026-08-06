function [automaticOptions, status] = detectorSettingsDlg(parentFigure, featureDetectorType, automaticOptions, downsampleInfo, dlgOptions)
% DETECTORSETTINGSDLG - Feature-detector settings dialog (downsampling + per-detector params + RANSAC).
%
% Syntax:
%   .. code-block:: matlab
%
%      [automaticOptions, status] = utils.align.detectorSettingsDlg( ...
%          parentFigure, featureDetectorType, automaticOptions, downsampleInfo)
%      [automaticOptions, status] = utils.align.detectorSettingsDlg( ...
%          parentFigure, featureDetectorType, automaticOptions, downsampleInfo, dlgOptions)
%
% Shared settings dialog for feature-based registration, used by both
% :class:`controllers.Alignment` (``updateAutomaticOptions``) and
% :class:`controllers.Stitching`. Pops an :func:`utils.dlgs.inputUniversalDlg`
% tailored to ``featureDetectorType``: a downsampling row, an upright-descriptor
% flag (all detectors except ORB), the per-detector parameters, and the three
% ``estgeotform2d`` (RANSAC) settings. The chosen values are written back into
% the matching fields of ``automaticOptions`` (the same struct shape produced by
% ``controllers.Alignment.defaultAutomaticOptions``).
%
% .. warning::
%
%    ``automaticOptions.rotationInvariance`` is named after MATLAB's
%    documentation heading for the ``extractFeatures`` ``Upright`` name-value
%    pair, but it holds the value of ``Upright`` itself and therefore carries the
%    OPPOSITE sense to its name: ``true`` means the keypoint orientation is NOT
%    estimated, i.e. the descriptors are upright and NOT rotation invariant. Set
%    it to ``false`` to match content that is rotated between the two images.
%    The field name is inherited from MIB2 and kept for session/project
%    round-trip compatibility; the dialog label states the ``Upright`` sense.
%
% Input Arguments:
%   - **parentFigure** - handle used as the dialog parent.
%   - **featureDetectorType** - [char] detector name (see
%     :func:`utils.align.detectFeatures` for the accepted strings).
%   - **automaticOptions** - struct with per-detector sub-structs
%     (``detectSURFFeatures`` …), ``estGeomTransform``, ``rotationInvariance``
%     (the ``Upright`` flag - see the warning above) and the downsampling field
%     named by ``downsampleInfo.field``.
%   - **downsampleInfo** - struct describing the first (downsampling) row:
%
%     - ``.field`` - [char] field in ``automaticOptions`` holding the value.
%     - ``.promptText`` - [char] label for the downsampling spinner.
%     - ``.limits`` *(optional)* - [1x2] spinner limits (default ``[0 Inf]``).
%     - ``.round`` *(optional)* - [logical] round to integer (default ``true``).
%     - ``.minOne`` *(optional)* - [logical] clamp a returned ``0`` up to ``1``
%       (default ``false``; used by the "factor" style downsampling).
%
%   - **dlgOptions** *(optional)* - struct tuning the dialog itself:
%
%     - ``.showUpright`` - [logical] show the upright-descriptor row (default
%       ``true``). Pass ``false`` when the caller already owns that decision
%       through a control of its own - :class:`controllers.Stitching` derives
%       ``rotationInvariance`` from its *Allow rotation* checkbox, so showing an
%       editable copy here would offer a second, ignored control. The stored
%       ``automaticOptions.rotationInvariance`` is then left untouched.
%
% Output Arguments:
%   - **automaticOptions** - the input struct with the edited fields applied
%     (unchanged when the user cancels).
%   - **status** - ``1`` when accepted, ``0`` when cancelled.

if ~isfield(downsampleInfo, 'limits'); downsampleInfo.limits = [0 Inf]; end
if ~isfield(downsampleInfo, 'round');  downsampleInfo.round  = true; end
if ~isfield(downsampleInfo, 'minOne'); downsampleInfo.minOne = false; end

if nargin < 5 || isempty(dlgOptions); dlgOptions = struct(); end
if ~isfield(dlgOptions, 'showUpright'); dlgOptions.showUpright = true; end

status = 0;
downsampleField = downsampleInfo.field;
dlgTitle = ['Feature detection options - ' featureDetectorType];

% --- RANSAC (estgeotform2d) rows, appended to every dialog as the last three.
estGeomPrompts = {
    sprintf('RANSAC: maximum number of random trials\n(positive integer; increase for robustness)'), ...
    sprintf('RANSAC: confidence of finding inliers\n(0..100; increase for robustness)'), ...
    sprintf('RANSAC: maximum distance in pixels\n(positive number)')};
estGeomDefs = {
    struct('Spinner',true,'Value',automaticOptions.estGeomTransform.MaxNumTrials,'Limits',[1 Inf],'Step',1, 'Round',true), ...
    struct('Spinner',true,'Value',automaticOptions.estGeomTransform.Confidence,'Limits',[1 Inf],'Step',1, 'Round',false), ...
    struct('Spinner',true,'Value',automaticOptions.estGeomTransform.MaxDistance,'Limits',[1 Inf],'Step',1, 'Round',true)};

downsampleDef = struct('Spinner',true,'Value',automaticOptions.(downsampleField), ...
    'Limits',downsampleInfo.limits,'Step',1,'Round',downsampleInfo.round);

dlgOpt = struct('WindowWidth', 560, 'WindowStyle', 'modal', 'Icon', 'puffin_question', ...
    'LabelPosition', 'left', 'Focus', 1);

isORB = strcmp(featureDetectorType, 'Oriented FAST and rotated BRIEF (ORB)');

if isORB
    prompts = [{downsampleInfo.promptText}, ...
               {sprintf('Scale factor for image decomposition\n(integer > 1)')}, ...
               {sprintf('Number of decomposition levels\n(integer ≥ 1)')}, ...
               estGeomPrompts];
    defAns  = [{downsampleDef}, ...
               {automaticOptions.detectORBFeatures.ScaleFactor}, ...
               {automaticOptions.detectORBFeatures.NumLevels}, ...
               estGeomDefs];
    dlgOpt.WindowHeight = 300;

    answer = utils.dlgs.inputUniversalDlg(parentFigure, '', prompts, defAns, dlgTitle, dlgOpt);
    if isempty(answer); return; end

    automaticOptions.detectORBFeatures.ScaleFactor = answer{2};
    automaticOptions.detectORBFeatures.NumLevels   = answer{3};
else
    % ``rotationInvariance`` IS MATLAB's ``Upright`` flag and carries its sense:
    % true = orientation not estimated = descriptors NOT rotation invariant. The
    % label must therefore describe the checked state as "upright / no rotation",
    % not as "rotation invariant" (see the docblock). Callers that own the
    % decision elsewhere (Stitching's "Allow rotation") drop the row entirely.
    if dlgOptions.showUpright
        prompts = {downsampleInfo.promptText, sprintf(['Upright descriptors: assume no rotation\n' ...
            '(uncheck to match rotated images)'])};
        defAns  = {downsampleDef, logical(automaticOptions.rotationInvariance)};
    else
        prompts = {downsampleInfo.promptText};
        defAns  = {downsampleDef};
    end
    % Per-detector rows start after the fixed leading rows; every answer index
    % below is relative to this so adding/removing a leading row cannot desync
    % the read-back from the build.
    firstParam = numel(prompts) + 1;

    switch featureDetectorType
        case 'Blobs: Speeded-Up Robust Features (SURF) algorithm'
            prompts = [prompts, {
                sprintf('Strongest feature threshold\n(decrease for more blobs; non-negative scalar)'), ...
                sprintf('Number of octaves\n(integer ≥ 1; typical 1..4)'), ...
                sprintf('Number of scale levels per octave\n(integer ≥ 3; typical 3..6)')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',automaticOptions.detectSURFFeatures.MetricThreshold,'Limits',[0 Inf],'Step',1, 'Round',true), ...
                struct('Spinner',true,'Value',automaticOptions.detectSURFFeatures.NumOctaves,'Limits',[1 Inf],'Step',1, 'Round',true), ...
                struct('Spinner',true,'Value',automaticOptions.detectSURFFeatures.NumScaleLevels,'Limits',[1 Inf],'Step',1, 'Round',true) }];
            dlgOpt.WindowHeight = 395;
        case 'Blobs: Detect scale invariant feature transform (SIFT)'
            prompts = [prompts, {
                sprintf('Contrast threshold\n(non-negative scalar in [0,1])'), ...
                sprintf('Edge threshold\n(non-negative scalar ≥ 1)'), ...
                sprintf('Number of layers in each octave\n(integer ≥ 1)'), ...
                sprintf('Sigma of the Gaussian\n(scalar; typical [1,2])')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',automaticOptions.detectSIFTFeatures.ContrastThreshold,'Limits',[0 1],'Step',0.1, 'Round',false), ...
                struct('Spinner',true,'Value',automaticOptions.detectSIFTFeatures.EdgeThreshold,'Limits',[1 Inf],'Step',1, 'Round',false), ...
                struct('Spinner',true,'Value',automaticOptions.detectSIFTFeatures.NumLayersInOctave,'Limits',[1 Inf],'Step',1, 'Round',true), ...
                struct('Spinner',true,'Value',automaticOptions.detectSIFTFeatures.Sigma,'Limits',[0 Inf],'Step',0.1, 'Round',false) }];
            dlgOpt.WindowHeight = 425;
        case 'Regions: Maximally Stable Extremal Regions (MSER) algorithm'
            prompts = [prompts, {
                sprintf('Step size between intensity threshold levels\n(typical 0.8..4)'), ...
                sprintf('Region area range in pixels\ntwo-element vector [minArea maxArea]'), ...
                sprintf('Maximum area variation\n(positive scalar; typical 0.1..1)')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',automaticOptions.detectMSERFeatures.ThresholdDelta,'Limits',[0 Inf],'Step',0.1, 'Round',false), ...
                num2str(automaticOptions.detectMSERFeatures.RegionAreaRange), ...
                struct('Spinner',true,'Value',automaticOptions.detectMSERFeatures.MaxAreaVariation,'Limits',[0 Inf],'Step',0.1, 'Round',false) }];
            dlgOpt.WindowHeight = 395;
        case 'Corners: Harris-Stephens algorithm'
            prompts = [prompts, {
                sprintf('Minimum accepted corner quality\n(scalar in [0,1])'), ...
                sprintf('Gaussian filter dimension\n(odd integer in [3, min(size(I))])')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',automaticOptions.detectHarrisFeatures.MinQuality,'Limits',[0 1],'Step', 0.1, 'Round',false), ...
                struct('Spinner',true,'Value',automaticOptions.detectHarrisFeatures.FilterSize,'Limits',[3 Inf],'Step',2, 'Round',true) }];
            dlgOpt.WindowHeight = 355;
        case 'Corners: Binary Robust Invariant Scalable Keypoints (BRISK)'
            prompts = [prompts, {
                sprintf('Minimum contrast\n(scalar in [0,1])'), ...
                sprintf('Minimum corner quality\n(scalar in [0,1])'), ...
                sprintf('Number of octaves\n(integer ≥ 0; typical 1..4)')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',automaticOptions.detectBRISKFeatures.MinContrast,'Limits',[0 1],'Step', 0.1, 'Round',false), ...
                struct('Spinner',true,'Value',automaticOptions.detectBRISKFeatures.MinQuality,'Limits',[0 1],'Step', 0.1, 'Round',false), ...
                struct('Spinner',true,'Value',automaticOptions.detectBRISKFeatures.NumOctaves,'Limits',[1 Inf],'Step', 1, 'Round',true) }];
            dlgOpt.WindowHeight = 385;
        case 'Corners: Features from Accelerated Segment Test (FAST)'
            prompts = [prompts, {
                sprintf('Minimum corner quality\n(scalar in [0,1])'), ...
                sprintf('Minimum intensity difference between corner\nand surrounding\n(scalar in [0,1])')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',automaticOptions.detectFASTFeatures.MinQuality,'Limits',[0 1],'Step', 0.1, 'Round',false), ...
                struct('Spinner',true,'Value',automaticOptions.detectFASTFeatures.MinContrast,'Limits',[0 1],'Step', 0.1, 'Round',false) }];
            dlgOpt.WindowHeight = 385;
        case 'Corners: Minimum Eigenvalue algorithm'
            prompts = [prompts, {
                sprintf('Minimum corner quality (scalar in [0,1])'), ...
                sprintf('Gaussian filter dimension (odd integer ≥ 3)')}];
            defAns = [defAns, {
                struct('Spinner',true,'Value',automaticOptions.detectMinEigenFeatures.MinQuality,'Limits',[0 1],'Step', 0.1, 'Round',false), ...
                struct('Spinner',true,'Value',automaticOptions.detectMinEigenFeatures.FilterSize,'Limits',[3 Inf],'Step', 2, 'Round',true) }];
            dlgOpt.WindowHeight = 335;
        otherwise
            utils.dlgs.showErrorDialog(parentFigure, ...
                sprintf('Unknown FeatureDetectorType: "%s"', featureDetectorType), ...
                'utils.align.detectorSettingsDlg');
            return;
    end

    % The per-detector heights above assume the two-line upright row is present.
    if ~dlgOptions.showUpright
        dlgOpt.WindowHeight = dlgOpt.WindowHeight - 45;
    end

    prompts = [prompts, estGeomPrompts];
    defAns  = [defAns,  estGeomDefs];
    answer = utils.dlgs.inputUniversalDlg(parentFigure, '', prompts, defAns, dlgTitle, dlgOpt);
    if isempty(answer); return; end

    if dlgOptions.showUpright
        automaticOptions.rotationInvariance = logical(answer{2});
    end

    switch featureDetectorType
        case 'Blobs: Speeded-Up Robust Features (SURF) algorithm'
            automaticOptions.detectSURFFeatures.MetricThreshold = answer{firstParam};
            automaticOptions.detectSURFFeatures.NumOctaves      = answer{firstParam+1};
            automaticOptions.detectSURFFeatures.NumScaleLevels  = answer{firstParam+2};
        case 'Blobs: Detect scale invariant feature transform (SIFT)'
            automaticOptions.detectSIFTFeatures.ContrastThreshold = answer{firstParam};
            automaticOptions.detectSIFTFeatures.EdgeThreshold     = answer{firstParam+1};
            automaticOptions.detectSIFTFeatures.NumLayersInOctave = answer{firstParam+2};
            automaticOptions.detectSIFTFeatures.Sigma             = answer{firstParam+3};
        case 'Regions: Maximally Stable Extremal Regions (MSER) algorithm'
            automaticOptions.detectMSERFeatures.ThresholdDelta = answer{firstParam};
            regionAreaRange = str2num(answer{firstParam+1}); %#ok<ST2NM>
            if ~isempty(regionAreaRange) && numel(regionAreaRange) == 2
                automaticOptions.detectMSERFeatures.RegionAreaRange = regionAreaRange;
            end
            automaticOptions.detectMSERFeatures.MaxAreaVariation = answer{firstParam+2};
        case 'Corners: Harris-Stephens algorithm'
            automaticOptions.detectHarrisFeatures.MinQuality = answer{firstParam};
            automaticOptions.detectHarrisFeatures.FilterSize = answer{firstParam+1};
        case 'Corners: Binary Robust Invariant Scalable Keypoints (BRISK)'
            automaticOptions.detectBRISKFeatures.MinContrast = answer{firstParam};
            automaticOptions.detectBRISKFeatures.MinQuality  = answer{firstParam+1};
            automaticOptions.detectBRISKFeatures.NumOctaves  = answer{firstParam+2};
        case 'Corners: Features from Accelerated Segment Test (FAST)'
            automaticOptions.detectFASTFeatures.MinQuality  = answer{firstParam};
            automaticOptions.detectFASTFeatures.MinContrast = answer{firstParam+1};
        case 'Corners: Minimum Eigenvalue algorithm'
            automaticOptions.detectMinEigenFeatures.MinQuality = answer{firstParam};
            automaticOptions.detectMinEigenFeatures.FilterSize = answer{firstParam+1};
    end
end

% --- RANSAC settings are the last three entries in every dialog variant.
automaticOptions.estGeomTransform.MaxNumTrials = answer{end - 2};
automaticOptions.estGeomTransform.Confidence   = answer{end - 1};
automaticOptions.estGeomTransform.MaxDistance  = answer{end};

% --- Downsampling (first entry); optionally clamp 0 up to 1 for "factor" style.
downsampleValue = answer{1};
if downsampleInfo.minOne && downsampleValue == 0
    downsampleValue = 1;
end
automaticOptions.(downsampleField) = downsampleValue;

status = 1;
end
