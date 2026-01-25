function brushPanel_Callback(obj, hWidget, hData, mode)
% brushPanel_Callback(obj, hWidget, hData)
% Callbacks for widgets in the Segmentation panel->Brush/3D ball/Spot tool
%
% Parameters:
% hWidget: handle to the pressed widget
% hWidget.Tag -> identifier the widget, used when the same operation
% is called from menu, when empty or missing hWidget.Tag is used as an identifier
% 'brushRadius' -> change of the brush size
% 'eraserFactor' -> change of the eraser magnifier factor
% 'interpolationSettings' -> set the interpolation settings
% 'brushUseClustering' -> selection of the clustering mode
% 'clustersPar1' -> clustering mode parameter 1:
% 'clustersPar2' -> clustering mode parameter 2:
% hData: handle to supporting data class
% mode: char with the identifier of the widget, see above, the other parameters are empty in this case
% 
% Example:
% <code>
% // make a callback for selection of brush clustering
% obj.brushPanel_Callback([], [], obj.handles.brushUseClustering.SelectedObject.Text)
% <endcode>
if nargin < 4; mode = hWidget.Tag; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.brushPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'brushRadius' % change of the brush size
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'eraserFactor' % change of the eraser magnifier factor
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s -> %d\n', mode, hWidget.Value);
    case 'interpolationSettings' % set the interpolation settings
        %fprintf('Clicked on a widget of the segmentation panel->Brush/3D ball/Spot tool (obj.handles.panels.segmentation): %s\n', mode);
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