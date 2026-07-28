function updateWidgets(obj)
% UPDATEWIDGETS - Refresh all GUI widgets from current BatchOpt state.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateWidgets()
%
% No-op without a view (batch protocols and headless runs hold the same state
% in ``BatchOpt`` — there is simply nothing to render it into).
%

if isempty(obj.view); return; end
handles = obj.view.handles;

% ---- Input group ----
handles.LayoutSource.Items  = obj.BatchOpt.LayoutSource{2};
handles.LayoutSource.Value  = obj.BatchOpt.LayoutSource{1};
obj.updateInfoLabel();          % short description of the selected layout source (guarded)
obj.refreshInputPathWidget();   % uieditfield (string) or uilistbox (per-path items)
handles.SubfolderMode.Value = obj.BatchOpt.SubfolderMode;
% SubfolderMode (tiles are folder Z-stacks) drives folder collection for Grid /
% Filename pattern only; a position file names folders directly and Bio-Formats
% reads whole series, so it is n/a for those two sources.
handles.SubfolderMode.Enable = ismember(obj.BatchOpt.LayoutSource{1}, {'Grid', 'Filename pattern'});

% ---- Grid group ----
% Rows/Cols/TileOrder apply only to the Grid source; Overlap X/Y + Estimate
% overlap also apply to the Filename pattern source (both carry grid indices).
isGrid = strcmp(obj.BatchOpt.LayoutSource{1}, 'Grid');
usesOverlap = ismember(obj.BatchOpt.LayoutSource{1}, {'Grid', 'Filename pattern'});
handles.GridRows.Value   = obj.BatchOpt.GridRows{1};
handles.GridRows.Limits  = obj.BatchOpt.GridRows{2};
handles.GridRows.Enable  = isGrid;
handles.GridCols.Value   = obj.BatchOpt.GridCols{1};
handles.GridCols.Limits  = obj.BatchOpt.GridCols{2};
handles.GridCols.Enable  = isGrid;
handles.TileOrder.Items  = obj.BatchOpt.TileOrder{2};
handles.TileOrder.Value  = obj.BatchOpt.TileOrder{1};
handles.TileOrder.Enable = isGrid;
% With overlap estimation enabled the spinners are read-only displays of the
% estimated value — the estimator does not use the entered overlap at all.
overlapEditable = usesOverlap && ~obj.BatchOpt.EstimateOverlap;
handles.OverlapX.Value   = obj.BatchOpt.OverlapX{1};
handles.OverlapX.Limits  = obj.BatchOpt.OverlapX{2};
handles.OverlapX.Enable  = overlapEditable;
handles.OverlapY.Value   = obj.BatchOpt.OverlapY{1};
handles.OverlapY.Limits  = obj.BatchOpt.OverlapY{2};
handles.OverlapY.Enable  = overlapEditable;
if isfield(handles, 'EstimateOverlap')   % widget may not exist in the mlapp yet
    handles.EstimateOverlap.Value  = obj.BatchOpt.EstimateOverlap;
    handles.EstimateOverlap.Enable = usesOverlap;
end

% ---- Registration group ----
handles.TransformType.Items     = obj.BatchOpt.TransformType{2};
handles.TransformType.Value     = obj.BatchOpt.TransformType{1};
isTranslation = strcmp(obj.BatchOpt.TransformType{1}, 'Translation');
if isfield(handles, 'AllowRotation')   % widget may not exist in the mlapp yet
    handles.AllowRotation.Value  = obj.BatchOpt.AllowRotation;
    handles.AllowRotation.Enable = ~isTranslation;   % moot for pure translation
end
if isfield(handles, 'RegistrationMethod')   % widget may not exist in the mlapp yet
    handles.RegistrationMethod.Items = obj.BatchOpt.RegistrationMethod{2};
    % Any non-translation transform implies the feature-based estimator
    % (phase correlation can only measure translation): the dropdown locks
    % AND displays what will actually run. BatchOpt keeps the user's own
    % choice, restored when they return to Translation.
    if isTranslation
        handles.RegistrationMethod.Value = obj.BatchOpt.RegistrationMethod{1};
    else
        handles.RegistrationMethod.Value = 'Feature-based';
    end
    handles.RegistrationMethod.Enable = isTranslation;
end
% Feature-detector selector + Settings button are only meaningful when the
% feature-based estimator will run — the Feature-based method, or any
% non-translation transform (which forces it).
usesFeatures = strcmp(obj.BatchOpt.RegistrationMethod{1}, 'Feature-based') || ~isTranslation;
if isfield(handles, 'FeatureDetectorType')   % widget may not exist in the mlapp yet
    handles.FeatureDetectorType.Items  = obj.BatchOpt.FeatureDetectorType{2};
    handles.FeatureDetectorType.Value  = obj.BatchOpt.FeatureDetectorType{1};
    handles.FeatureDetectorType.Enable = usesFeatures;
end
if isfield(handles, 'configureFeaturesBtn')   % widget may not exist in the mlapp yet
    handles.configureFeaturesBtn.Enable = usesFeatures;
end
handles.QualityThreshold.Value  = obj.BatchOpt.QualityThreshold{1};
handles.QualityThreshold.Limits = obj.BatchOpt.QualityThreshold{2};
handles.NominalPositionWeight.Value  = obj.BatchOpt.NominalPositionWeight{1};
handles.NominalPositionWeight.Limits = obj.BatchOpt.NominalPositionWeight{2};
handles.SubpixelPlacement.Value      = obj.BatchOpt.SubpixelPlacement;

% ---- Output group ----
handles.OutputMode.Items  = obj.BatchOpt.OutputMode{2};
handles.OutputMode.Value  = obj.BatchOpt.OutputMode{1};
handles.OutputPath.Value  = obj.BatchOpt.OutputPath;
handles.BlendMode.Items   = obj.BatchOpt.BlendMode{2};
handles.BlendMode.Value   = obj.BatchOpt.BlendMode{1};
handles.SaveProject.Value = obj.BatchOpt.SaveProject;

% ---- Enable / disable output path based on output mode ----
isZarr = strcmp(obj.BatchOpt.OutputMode{1}, 'OME-Zarr3 (BigData)');
handles.OutputPath.Enable      = isZarr;
handles.selectOutputBtn.Enable = isZarr;

% The seam inspector needs a measured + solved state to review.
if isfield(handles, 'inspectSeamsBtn')   % widget may not exist in the mlapp yet
    handles.inspectSeamsBtn.Enable = ~isempty(obj.edges) && ~isempty(obj.positions);
end

% ---- Status labels reflecting cached state ----
numTiles = numel(obj.layout);
numEdges = numel(obj.edges);
handles.statusLabel.Text = sprintf('%d tiles | %d edges measured | solved: %s', ...
    numTiles, numEdges, ternary(~isempty(obj.positions), 'yes', 'no'));

% Alignment-quality chip. Rendered here rather than only after a solve, so it
% follows every change to the edge set — excluding a seam in the inspector
% changes which edges the worst-pixel-match is taken over, and a chip left
% quoting the pre-exclusion verdict would be wrong.
obj.refreshQualityChip();

end

% =========================================================================
function result = ternary(condition, trueValue, falseValue)
if condition
    result = trueValue;
else
    result = falseValue;
end
end
