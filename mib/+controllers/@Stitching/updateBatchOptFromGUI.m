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

obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);

% When layout source or overlap-estimation mode changes, update grid-group
% enable states (overlap spinners are read-only while estimation is enabled)
isEstimateWidget = isfield(obj.view.handles, 'EstimateOverlap') && ...
    isequal(hObject, obj.view.handles.EstimateOverlap);
if isequal(hObject, obj.view.handles.LayoutSource) || isEstimateWidget
    isGrid = strcmp(obj.BatchOpt.LayoutSource{1}, 'Grid');
    overlapEditable = isGrid && ~obj.BatchOpt.EstimateOverlap;
    obj.view.handles.GridRows.Enable   = isGrid;
    obj.view.handles.GridCols.Enable   = isGrid;
    obj.view.handles.TileOrder.Enable  = isGrid;
    obj.view.handles.OverlapX.Enable   = overlapEditable;
    obj.view.handles.OverlapY.Enable   = overlapEditable;
    if isfield(obj.view.handles, 'EstimateOverlap')
        obj.view.handles.EstimateOverlap.Enable = isGrid;
    end
end

% Layout-parameter changes invalidate the current layout: rebuild it from the
% updated BatchOpt (input path already chosen) and refresh the preview when one
% is on screen, so the user sees the new arrangement immediately.
layoutWidgetNames = {'GridRows', 'GridCols', 'TileOrder', ...
    'OverlapX', 'OverlapY', 'SubfolderMode', 'InputPath'};
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

% When output mode changes, update output path enable state
if isequal(hObject, obj.view.handles.OutputMode)
    isZarr = strcmp(obj.BatchOpt.OutputMode{1}, 'OME-Zarr (BigData)');
    obj.view.handles.OutputPath.Enable      = isZarr;
    obj.view.handles.selectOutputBtn.Enable = isZarr;
end

end
