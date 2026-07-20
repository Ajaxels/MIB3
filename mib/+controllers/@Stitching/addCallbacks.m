function addCallbacks(obj)
% ADDCALLBACKS - Wire all GUI widget callbacks for the Stitching controller.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.addCallbacks()
%
% BatchOpt-linked widgets are named exactly as their BatchOpt fields
% (ChildView copies the component name into the Tag, which
% utils.updateBatchOptFromGUI_Shared uses as the field name).
%

handles = obj.view.handles;

% Close request
obj.view.gui.CloseRequestFcn = @(~, ~) obj.closeWindow();

% ---- Input group ----
handles.LayoutSource.ValueChangedFcn  = @(src, ~) obj.updateBatchOptFromGUI(src);
% Only sync typed input when InputPath is an editable text field. As a uilistbox
% it is a display of the Browse-selected paths — selecting a row must NOT
% overwrite BatchOpt.InputPath with the single selected item.
if ~isprop(handles.InputPath, 'Items')
    handles.InputPath.ValueChangedFcn = @(src, ~) obj.updateBatchOptFromGUI(src);
end
handles.selectInputBtn.ButtonPushedFcn = @(~, ~) obj.selectInputBtn_Callback();
handles.SubfolderMode.ValueChangedFcn = @(src, ~) obj.updateBatchOptFromGUI(src);

% ---- Grid group ----
handles.GridRows.ValueChangedFcn      = @(src, ~) obj.updateBatchOptFromGUI(src);
handles.GridCols.ValueChangedFcn      = @(src, ~) obj.updateBatchOptFromGUI(src);
handles.TileOrder.ValueChangedFcn     = @(src, ~) obj.updateBatchOptFromGUI(src);
handles.OverlapX.ValueChangedFcn      = @(src, ~) obj.updateBatchOptFromGUI(src);
handles.OverlapY.ValueChangedFcn      = @(src, ~) obj.updateBatchOptFromGUI(src);
if isfield(handles, 'EstimateOverlap')   % widget may not exist in the mlapp yet
    handles.EstimateOverlap.ValueChangedFcn = @(src, ~) obj.updateBatchOptFromGUI(src);
end

% ---- Registration group ----
handles.TransformType.ValueChangedFcn    = @(src, ~) obj.updateBatchOptFromGUI(src);
if isfield(handles, 'AllowRotation')   % widget may not exist in the mlapp yet
    handles.AllowRotation.ValueChangedFcn = @(src, ~) obj.updateBatchOptFromGUI(src);
end
if isfield(handles, 'RegistrationMethod')   % widget may not exist in the mlapp yet
    handles.RegistrationMethod.ValueChangedFcn = @(src, ~) obj.updateBatchOptFromGUI(src);
end
if isfield(handles, 'FeatureDetectorType')   % widget may not exist in the mlapp yet
    handles.FeatureDetectorType.ValueChangedFcn = @(src, ~) obj.updateBatchOptFromGUI(src);
end
if isfield(handles, 'configureFeaturesBtn')   % widget may not exist in the mlapp yet
    handles.configureFeaturesBtn.ButtonPushedFcn = @(~, ~) obj.configureFeaturesBtn_Callback();
end
handles.QualityThreshold.ValueChangedFcn = @(src, ~) obj.updateBatchOptFromGUI(src);
handles.NominalPositionWeight.ValueChangedFcn = @(src, ~) obj.updateBatchOptFromGUI(src);
handles.SubpixelPlacement.ValueChangedFcn = @(src, ~) obj.updateBatchOptFromGUI(src);

% ---- Output group ----
handles.OutputMode.ValueChangedFcn    = @(src, ~) obj.updateBatchOptFromGUI(src);
handles.OutputPath.ValueChangedFcn    = @(src, ~) obj.updateBatchOptFromGUI(src);
handles.selectOutputBtn.ButtonPushedFcn = @(~, ~) obj.selectOutputPath_Callback();
handles.BlendMode.ValueChangedFcn     = @(src, ~) obj.updateBatchOptFromGUI(src);
handles.SaveProject.ValueChangedFcn   = @(src, ~) obj.updateBatchOptFromGUI(src);

% ---- Action buttons ----
if isfield(handles, 'inspectSeamsBtn')   % widget may not exist in the mlapp yet
    handles.inspectSeamsBtn.ButtonPushedFcn = @(~, ~) obj.inspectSeams_Callback();
end
handles.previewLayoutBtn.ButtonPushedFcn   = @(~, ~) obj.previewLayoutBtn_Callback();
if isfield(handles, 'editLayoutCheckbox')   % widget may not exist in the mlapp yet
    % Toggling edit mode just redraws the preview in the matching mode.
    handles.editLayoutCheckbox.ValueChangedFcn = @(~, ~) obj.previewLayoutBtn_Callback();
end
handles.measureOverlaps.ButtonPushedFcn    = @(~, ~) obj.measureOverlaps_Callback();
handles.optimizePositions.ButtonPushedFcn  = @(~, ~) obj.optimizePositions_Callback();
handles.stitchBtn.ButtonPushedFcn          = @(~, ~) obj.stitchBtn_Callback(false);
handles.saveProjectBtn.ButtonPushedFcn     = @(~, ~) obj.saveProjectBtn_Callback();
handles.loadProjectBtn.ButtonPushedFcn     = @(~, ~) obj.loadProjectBtn_Callback();
handles.helpButton.ButtonPushedFcn         = @(~, ~) obj.helpBtn_Callback();
handles.closeButton.ButtonPushedFcn        = @(~, ~) obj.closeWindow();

% ---- tooltips (set here so the mlapp stays layout-only) --------------------
% BatchOpt-linked widgets reuse the batch-mode tooltips — one source of truth
% for the GUI and the Batch processing tool alike.
batchTooltips = obj.BatchOpt.mibBatchTooltip;
tooltipFields = fieldnames(batchTooltips);
for fieldIdx = 1:numel(tooltipFields)
    setTooltip(handles, tooltipFields{fieldIdx}, batchTooltips.(tooltipFields{fieldIdx}));
end

setTooltip(handles, 'selectInputBtn', sprintf( ...
    ['Browse for the input, as the Layout source expects:\n' ...
     'Grid / Filename pattern — multi-select the tile image files (Ctrl+A);\n' ...
     'with "Tiles are folders" on, select one folder per tile Z-stack.\n' ...
     'Position file — pick the .txt/.csv. Bio-Formats — pick the image files.']));
setTooltip(handles, 'selectOutputBtn', ...
    'Browse for the OME-Zarr output location (used when Output mode = OME-Zarr3 (BigData)).');
setTooltip(handles, 'previewLayoutBtn', ...
    'Draw the tile arrangement on the preview: nominal positions before the solve, SOLVED positions after (the title says which).');
setTooltip(handles, 'editLayoutCheckbox', ...
    'Make the previewed tiles draggable to correct a wrong arrangement by hand — drag them roughly into place, then re-run Measure overlaps and Optimize positions.');
setTooltip(handles, 'previewAxes', ...
    'Tile arrangement preview — numbered tile rectangles; tick "Edit layout" to drag them.');
setTooltip(handles, 'measureOverlaps', ...
    'Step 1 — measure the actual pairwise shift of every overlapping tile pair with the selected registration method.');
setTooltip(handles, 'optimizePositions', sprintf( ...
    ['Step 2 — one global least-squares solve of all tile positions from the\n' ...
     'measured pairs. The result chip rates it by the solver residual AND by\n' ...
     're-reading the pixels at every seam — trust the chip, not just the RMSE.']));
setTooltip(handles, 'stitchBtn', ...
    'Step 3 — fuse the mosaic at the solved positions with the selected blend mode and open it in MIB (in-memory, or streamed OME-Zarr for larger-than-RAM mosaics).');
setTooltip(handles, 'inspectSeamsBtn', sprintf( ...
    ['Review the seams worst-first and fix bad ones by hand: drag, Shift+click\n' ...
     'cross-correlation, two-click landmark match; Fix Z aligns consecutive\n' ...
     'mosaic slices. Use it when the rating chip is orange or red.']));
setTooltip(handles, 'saveProjectBtn', ...
    'Save the stitch project sidecar (.mibstitch.json): layout, measured seams, solved positions, review decisions and Fix Z corrections.');
setTooltip(handles, 'loadProjectBtn', ...
    'Load a saved .mibstitch.json project to continue reviewing or re-fuse without re-measuring.');
setTooltip(handles, 'configureFeaturesBtn', ...
    'Tune the feature detector (thresholds, RANSAC, downsampling); accepting shows the matched keypoints on the first overlapping pair.');
setTooltip(handles, 'helpButton', 'Open the Stitch documentation.');
setTooltip(handles, 'closeButton', 'Close the Stitching tool.');

end

% =====================================================================
function setTooltip(handles, widgetName, text)
% SETTOOLTIP - Guarded: skip absent widgets and ones without a Tooltip property.
if isfield(handles, widgetName) && isprop(handles.(widgetName), 'Tooltip')
    handles.(widgetName).Tooltip = text;
end
end
