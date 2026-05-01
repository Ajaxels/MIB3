function brushPanel_Callback(obj, hWidget, hData, mode)
% BRUSHPANEL_CALLBACK - Callback for brush, 3D ball, and spot tool widgets.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.brushPanel_Callback(hWidget, hData, mode)
%
% Handles callbacks for brush, 3D ball, and spot segmentation tool widgets in the Segmentation panel.
% Supports brush size, eraser factor, clustering mode, and interpolation settings configuration.
%
% Input Arguments:
%   - **hWidget** — [matlab.ui.control.Button | matlab.ui.control.CheckBox | matlab.ui.control.Spinner | matlab.ui.control.DropDown] pressed widget; operation identified via ``hWidget.Tag`` (when provided):
%
%     - ``'brushRadius'`` — adjust brush size/radius
%     - ``'eraserFactor'`` — set eraser magnification factor
%     - ``'interpolationSettings'`` — open interpolation settings dialog
%     - ``'brushUseClustering'`` — enable/select clustering mode
%     - ``'clustersPar1'`` — set clustering mode parameter 1
%     - ``'clustersPar2'`` — set clustering mode parameter 2
%
%   - **hData** — [matlab.ui.eventdata.ValueChangedData] event data from widget
%   - **mode** — *(optional)* [char] widget identifier; when provided, ``hWidget`` and ``hData`` are ignored
%
% Output Arguments:
%   None
%
% **Example** — set brush clustering mode via direct call:
%
%   .. code-block:: matlab
%
%      obj.brushPanel_Callback([], [], obj.handles.brushUseClustering.SelectedObject.Text)
%
if nargin < 4; mode = hWidget.Tag; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.brushPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'brushRadius' % change of the brush size
        selectedSet = obj.mibModel.Sets.selectedSet;
        obj.mibController.cImageDoc{selectedSet}.updateBrushCursorOffset();
        obj.mibController.cImageDoc{selectedSet}.updateBrushCursor();
    case 'eraserFactor' % change of the eraser magnifier factor
        obj.mibModel.preferences.SegmTools.Brush.EraserRadiusFactor = obj.handles.eraserFactor.Value;
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'interpolationSettings' % set the interpolation settings
        obj.updateInterpolationSettings();
    case 'brushUseClustering' % selection of the clustering mode
        switch obj.handles.brushUseClustering.SelectedObject.Text
            case 'No clusters'
                
            case 'Watershed'
                obj.handles.clustersPar1.Value = obj.mibModel.preferences.SegmTools.Superpixels.NoWatershed;
                obj.handles.clustersPar2.Value = obj.mibModel.preferences.SegmTools.Superpixels.InvertWatershed;
                obj.handles.clustersPar2.Limits = [0 1];
            case 'SLIC'
                obj.handles.clustersPar1.Value = obj.mibModel.preferences.SegmTools.Superpixels.NoSLIC;
                obj.handles.clustersPar2.Limits = [1 Inf];
                obj.handles.clustersPar2.Value = obj.mibModel.preferences.SegmTools.Superpixels.CompactSLIC;
        end
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s -> %s\n', mode, hWidget.SelectedObject.Text);
    case 'clustersPar1' % clustering mode parameter 1:
        if strcmp(obj.handles.brushUseClustering.SelectedObject.Text, 'Watershed')
            obj.mibModel.preferences.SegmTools.Superpixels.NoWatershed = obj.handles.clustersPar1.Value;
        else
            obj.mibModel.preferences.SegmTools.Superpixels.NoSLIC = obj.handles.clustersPar1.Value;
        end
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'clustersPar2' % clustering mode parameter 2:
        if strcmp(obj.handles.brushUseClustering.SelectedObject.Text, 'Watershed')
            obj.mibModel.preferences.SegmTools.Superpixels.InvertWatershed = obj.handles.clustersPar2.Value;
        else
            obj.mibModel.preferences.SegmTools.Superpixels.CompactSLIC = obj.handles.clustersPar2.Value;
        end
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
end

end
