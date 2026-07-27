function configureFeaturesBtn_Callback(obj)
% CONFIGUREFEATURESBTN_CALLBACK - Open the feature-detector settings dialog.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.configureFeaturesBtn_Callback()
%
% Pops the shared :func:`utils.align.detectorSettingsDlg` (also used by
% :class:`controllers.Alignment`) to edit the currently selected
% ``FeatureDetectorType`` parameters, the upright-descriptor flag
% (``automaticOptions.rotationInvariance``, which holds MATLAB's ``Upright``
% value — see :func:`utils.align.detectorSettingsDlg`), the detection
% downsampling factor, and the RANSAC (``estgeotform2d``) settings.
% The edited values are stored in ``obj.automaticOptions`` and applied on the
% next *Measure overlaps* / *Stitch* run of the Feature-based method. When the
% dialog is accepted and a layout is loaded, :func:`previewFeatureMatch` renders
% the resulting keypoint matches on a representative tile pair so the effect of
% the change is visible immediately (as in the Alignment feature preview).
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.configureFeaturesBtn_Callback: triggered\n');
end
featureDetectorType = obj.BatchOpt.FeatureDetectorType{1};

% First (downsampling) row: a factor where 1 = full resolution. Use the first
% tile's width for a helpful hint when a layout is already loaded.
if ~isempty(obj.layout) && isfield(obj.layout, 'tileSize') && ~isempty(obj.layout(1).tileSize)
    tileWidth = obj.layout(1).tileSize(2);
    promptText = sprintf(['Downsampling factor for feature detection (tile width = %d px)\n' ...
        '"1" — full resolution;\n"4" — downsample x4 (faster, less precise)'], tileWidth);
else
    promptText = sprintf(['Downsampling factor for feature detection\n' ...
        '"1" — full resolution;\n"4" — downsample x4 (faster, less precise)']);
end

downsampleInfo = struct('field', 'imgDownsamplingFactorForAnalysis', ...
    'promptText', promptText, 'limits', [1 64], 'round', true, 'minOne', true);

% The upright-descriptor row is suppressed: whether rotated content can be
% matched is not a separate decision here — it follows the "Allow rotation"
% checkbox in the main window (see buildFeatureOptions). Alignment, which has no
% such checkbox, still shows the row.
[obj.automaticOptions, status] = utils.align.detectorSettingsDlg(obj.view.gui, ...
    featureDetectorType, obj.automaticOptions, downsampleInfo, ...
    struct('showUpright', false));

if status == 1
    obj.updateWidgets();
    % Show the effect of the new settings on a representative tile pair, the
    % same immediate-feedback loop the Alignment feature preview provides.
    obj.previewFeatureMatch();
end
end
