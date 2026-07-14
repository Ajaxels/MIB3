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
%   the ``estgeotform2d`` (RANSAC) settings — delegated to the shared
%   :func:`utils.align.detectorSettingsDlg` (also used by the Stitching tool).
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
% Feature-based branch — per-detector settings + RANSAC (shared dialog)
% ============================================================================
downsampleInfo = struct('field', imageDownsamplingField, 'promptText', firstInfoText, ...
    'limits', [0 imgWidth], 'round', true, ...
    'minOne', strcmp(obj.BatchOpt.Algorithm{1}, 'Automatic feature-based v2'));
[obj.automaticOptions, status] = utils.align.detectorSettingsDlg(parentFig, ...
    obj.BatchOpt.FeatureDetectorType{1}, obj.automaticOptions, downsampleInfo);
end
