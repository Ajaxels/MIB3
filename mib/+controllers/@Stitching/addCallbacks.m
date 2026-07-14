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

end
