function updateWidgets(obj)
% UPDATEWIDGETS - Refresh all GUI widgets from current BatchOpt state.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateWidgets()
%

handles = obj.view.handles;

% ---- Input group ----
handles.LayoutSource.Items  = obj.BatchOpt.LayoutSource{2};
handles.LayoutSource.Value  = obj.BatchOpt.LayoutSource{1};
handles.InputPath.Value     = obj.BatchOpt.InputPath;
handles.SubfolderMode.Value = obj.BatchOpt.SubfolderMode;

% ---- Grid group (enable only when layout source is Grid) ----
isGrid = strcmp(obj.BatchOpt.LayoutSource{1}, 'Grid');
handles.GridRows.Value   = obj.BatchOpt.GridRows{1};
handles.GridRows.Limits  = obj.BatchOpt.GridRows{2};
handles.GridRows.Enable  = isGrid;
handles.GridCols.Value   = obj.BatchOpt.GridCols{1};
handles.GridCols.Limits  = obj.BatchOpt.GridCols{2};
handles.GridCols.Enable  = isGrid;
handles.TileOrder.Items  = obj.BatchOpt.TileOrder{2};
handles.TileOrder.Value  = obj.BatchOpt.TileOrder{1};
handles.TileOrder.Enable = isGrid;
handles.OverlapX.Value   = obj.BatchOpt.OverlapX{1};
handles.OverlapX.Limits  = obj.BatchOpt.OverlapX{2};
handles.OverlapX.Enable  = isGrid;
handles.OverlapY.Value   = obj.BatchOpt.OverlapY{1};
handles.OverlapY.Limits  = obj.BatchOpt.OverlapY{2};
handles.OverlapY.Enable  = isGrid;

% ---- Registration group ----
handles.TransformType.Items     = obj.BatchOpt.TransformType{2};
handles.TransformType.Value     = obj.BatchOpt.TransformType{1};
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
isZarr = strcmp(obj.BatchOpt.OutputMode{1}, 'OME-Zarr (BigData)');
handles.OutputPath.Enable      = isZarr;
handles.selectOutputBtn.Enable = isZarr;

% ---- Status labels reflecting cached state ----
numTiles = numel(obj.layout);
numEdges = numel(obj.edges);
handles.statusLabel.Text = sprintf('%d tiles | %d edges measured | solved: %s', ...
    numTiles, numEdges, ternary(~isempty(obj.positions), 'yes', 'no'));

end

% =========================================================================
function result = ternary(condition, trueValue, falseValue)
if condition
    result = trueValue;
else
    result = falseValue;
end
end
