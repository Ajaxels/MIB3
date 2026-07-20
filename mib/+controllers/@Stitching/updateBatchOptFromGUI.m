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
    obj.updateInfoLabel();         % refresh the layout-source description (guarded)
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
% is on screen, so the user sees the new arrangement immediately. This includes
% LayoutSource itself — picking a Grid input and then switching to Filename
% pattern must re-derive the arrangement, not keep the grid guess (Measure
% would silently measure the stale pairs otherwise).
% (SubfolderMode is excluded: toggling it changes how InputPath is interpreted,
% so the user must re-select the input rather than auto-rebuilding from stale data.)
layoutWidgetNames = {'LayoutSource', 'GridRows', 'GridCols', 'TileOrder', ...
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
        if isequal(hObject, obj.view.handles.LayoutSource)
            % The current input may simply be incompatible with the NEW source
            % (e.g. a tile-file list after switching to Position file). Keeping
            % the layout built by the OLD source would be worse — drop it and
            % ask for a re-select via the status label (no modal error: this is
            % a normal step of changing the source, not a failure).
            obj.layout    = [];
            obj.edges     = [];
            obj.positions = [];
            obj.tforms    = {};
            obj.canvas    = [];
            obj.zSliceFixes = [];
            % Tear down edit-mode ROIs (same cleanup as previewLayoutBtn_Callback)
            % before wiping the now-meaningless preview.
            for listenerIdx = 1:numel(obj.roiListeners)
                if isvalid(obj.roiListeners{listenerIdx}); delete(obj.roiListeners{listenerIdx}); end
            end
            obj.roiListeners = {};
            if ~isempty(obj.tileROIs)
                delete(obj.tileROIs(isvalid(obj.tileROIs)));
                obj.tileROIs = images.roi.Rectangle.empty;
            end
            cla(obj.view.handles.previewAxes);
            obj.updateWidgets();
            obj.view.handles.statusLabel.Text = sprintf( ...
                'Layout source changed — re-select the input (%s)', buildError.message);
        else
            utils.dlgs.showErrorDialog(obj.view.gui, buildError.message, 'Layout rebuild failed');
        end
    end
end

% When the registration method or the transform model changes, refresh the
% dependent enable states: the feature-detector selector + Settings button run
% whenever the feature-based estimator will (Feature-based method, or any
% non-translation transform, which forces it); the rotation checkbox is moot
% for pure translation; the method dropdown is fixed to feature-based then too.
isTranslation = strcmp(obj.BatchOpt.TransformType{1}, 'Translation');
usesFeatures = strcmp(obj.BatchOpt.RegistrationMethod{1}, 'Feature-based') || ~isTranslation;
isMethodWidget = isfield(obj.view.handles, 'RegistrationMethod') && ...
    isequal(hObject, obj.view.handles.RegistrationMethod);
isTransformWidget = isfield(obj.view.handles, 'TransformType') && ...
    isequal(hObject, obj.view.handles.TransformType);
isAllowRotationWidget = isfield(obj.view.handles, 'AllowRotation') && ...
    isequal(hObject, obj.view.handles.AllowRotation);
if isMethodWidget || isTransformWidget
    if isfield(obj.view.handles, 'FeatureDetectorType')
        obj.view.handles.FeatureDetectorType.Enable = usesFeatures;
    end
    if isfield(obj.view.handles, 'configureFeaturesBtn')
        obj.view.handles.configureFeaturesBtn.Enable = usesFeatures;
    end
    if isfield(obj.view.handles, 'AllowRotation')
        obj.view.handles.AllowRotation.Enable = ~isTranslation;
    end
    if isfield(obj.view.handles, 'RegistrationMethod')
        obj.view.handles.RegistrationMethod.Enable = isTranslation;
    end
end

% Changing the transform model or the rotation lock invalidates the measured
% edges (they carry model-specific transforms) and everything downstream —
% force a re-measure.
if isTransformWidget || isAllowRotationWidget
    obj.edges     = struct('i', {}, 'j', {}, 'direction', {}, 'nominal', {});
    obj.positions = [];
    obj.tforms    = {};
    obj.canvas    = [];
    obj.updateWidgets();
end

% When output mode changes, update output path enable state
if isequal(hObject, obj.view.handles.OutputMode)
    isZarr = strcmp(obj.BatchOpt.OutputMode{1}, 'OME-Zarr (BigData)');
    obj.view.handles.OutputPath.Enable      = isZarr;
    obj.view.handles.selectOutputBtn.Enable = isZarr;
end

end
