function updateBatchOptFromGUI(obj, hObject)
% UPDATEBATCHOPTFROMGUI - Sync obj.BatchOpt from a changed widget.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateBatchOptFromGUI(hObject)
%
% Input Arguments:
%   - **hObject** — handle to the AppDesigner widget that changed
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.updateBatchOptFromGUI: %s -> %s\n', hObject.Tag, num2str(hObject.Value));
end
obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);

% When layout source or overlap-estimation mode changes, update grid-group
% enable states (overlap spinners are read-only while estimation is enabled)
isEstimateWidget = isfield(obj.view.handles, 'EstimateOverlap') && ...
    isequal(hObject, obj.view.handles.EstimateOverlap);
if isequal(hObject, obj.view.handles.LayoutSource) || isEstimateWidget
    isGrid = strcmp(obj.BatchOpt.LayoutSource{1}, 'Grid');
    usesOverlap = ismember(obj.BatchOpt.LayoutSource{1}, {'Grid', 'Filename pattern'});
    obj.view.handles.SubfolderMode.Enable = usesOverlap;
    overlapEditable = usesOverlap && ~obj.BatchOpt.EstimateOverlap;
    obj.view.handles.GridRows.Enable   = isGrid;
    obj.view.handles.GridCols.Enable   = isGrid;
    obj.view.handles.TileOrder.Enable  = isGrid;
    obj.view.handles.OverlapX.Enable   = overlapEditable;
    obj.view.handles.OverlapY.Enable   = overlapEditable;
    if isfield(obj.view.handles, 'EstimateOverlap')
        obj.view.handles.EstimateOverlap.Enable = usesOverlap;
    end
end

% Layout-parameter changes invalidate the current layout: rebuild it from the
% updated BatchOpt (input path already chosen) and refresh the preview when one
% is on screen, so the user sees the new arrangement immediately.
% (SubfolderMode is excluded: toggling it changes how InputPath is interpreted,
% so the user must re-select the input rather than auto-rebuilding from stale data.)
layoutWidgetNames = {'GridRows', 'GridCols', 'TileOrder', ...
    'OverlapX', 'OverlapY', 'InputPath'};
isLayoutWidget = false;
for nameIdx = 1:numel(layoutWidgetNames)
    if isequal(hObject, obj.view.handles.(layoutWidgetNames{nameIdx}))
        isLayoutWidget = true;
        break;
    end
end
if isLayoutWidget && ~isempty(obj.BatchOpt.InputPath)
    try
        obj.buildLayoutFromBatchOpt();
        obj.updateWidgets();
        if ~isempty(obj.view.handles.previewAxes.Children)
            obj.previewLayoutBtn_Callback();
        end
    catch buildError
        utils.dlgs.showErrorDialog(obj.view.gui, buildError.message, 'Layout rebuild failed');
    end
end

% When the registration method changes, enable/disable the feature-detector
% selector and its Settings button (feature-based only).
if isfield(obj.view.handles, 'RegistrationMethod') && isequal(hObject, obj.view.handles.RegistrationMethod)
    isFeatureBased = strcmp(obj.BatchOpt.RegistrationMethod{1}, 'Feature-based');
    if isfield(obj.view.handles, 'FeatureDetectorType')
        obj.view.handles.FeatureDetectorType.Enable = isFeatureBased;
    end
    if isfield(obj.view.handles, 'configureFeaturesBtn')
        obj.view.handles.configureFeaturesBtn.Enable = isFeatureBased;
    end
end

% When output mode changes, update output path enable state
if isequal(hObject, obj.view.handles.OutputMode)
    isZarr = strcmp(obj.BatchOpt.OutputMode{1}, 'OME-Zarr (BigData)');
    obj.view.handles.OutputPath.Enable      = isZarr;
    obj.view.handles.selectOutputBtn.Enable = isZarr;
end

end
