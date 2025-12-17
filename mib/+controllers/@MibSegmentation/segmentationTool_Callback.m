function segmentationTool_Callback(obj, hWidget, hData)
% function segmentationTool_Callback(obj, hWidget, hData)
% callbacks for press of obj.handles.panels.segmentation.handles.segmTool dropdown in
% obj.handles.panels.segmentation panel. 
% Select segmentation tool
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibSegmentation
    hWidget matlab.ui.control.DropDown
    hData matlab.ui.eventdata.ValueChangedData
end

if obj.mibModel.preferences.System.DeveloperMode
    % obj.mibController.cSegmentation.segmentationTool_Callback
    fprintf('controllers.MibSegmentation.segmentationTool_Callback: -> "%s"\n', hWidget.Value);
end

obj.view.handles.panels.segmentation.handles.panelLines3D.Visible = 'off';
obj.view.handles.panels.segmentation.handles.panelAnnotations.Visible = 'off';
obj.view.handles.panels.segmentation.handles.panelBrush.Visible = 'off';
obj.view.handles.panels.segmentation.handles.panelThresholding.Visible = 'off';
obj.view.handles.panels.segmentation.handles.panelDrag.Visible = 'off';
obj.view.handles.panels.segmentation.handles.panelLasso.Visible = 'off';
obj.view.handles.panels.segmentation.handles.panelMagicwand.Visible = 'off';
obj.view.handles.panels.segmentation.handles.panelMembrane.Visible = 'off';
obj.view.handles.panels.segmentation.handles.panelSAM.Visible = 'off';  

switch obj.view.handles.panels.segmentation.handles.segmTool.Value
    case {'3D ball', 'Spot'}
        obj.view.handles.panels.segmentation.handles.brushUseClustering.Visible = 'off';
        obj.view.handles.panels.segmentation.handles.panelBrush.Visible = 'on';
    case '3D lines'
        obj.view.handles.panels.segmentation.handles.panelLines3D.Visible = 'on';
    case 'Annotations'
        obj.view.handles.panels.segmentation.handles.panelAnnotations.Visible = 'on';
    case 'Brush'
        obj.view.handles.panels.segmentation.handles.brushUseClustering.Visible = 'on';
        obj.view.handles.panels.segmentation.handles.panelBrush.Visible = 'on';
    case 'BW thresholding'
        obj.view.handles.panels.segmentation.handles.panelThresholding.Visible = 'on';
    case 'Drag&Drop materials'
        obj.view.handles.panels.segmentation.handles.panelDrag.Visible = 'on'; 
    case 'Lasso'
        obj.view.handles.panels.segmentation.handles.lassoObjectPicker.Visible = 'off';
        obj.view.handles.panels.segmentation.handles.lassoCustomParameters.Visible = 'on';
        obj.view.handles.panels.segmentation.handles.panelLasso.Visible = 'on'; 
    case 'MagicWand/RegionGrowing'
        obj.view.handles.panels.segmentation.handles.panelMagicwand.Visible = 'on'; 
    case 'Membrane ClickTracker'
        obj.view.handles.panels.segmentation.handles.panelMembrane.Visible = 'on'; 
    case 'Object picker'
        obj.view.handles.panels.segmentation.handles.lassoCustomParameters.Visible = 'off';
        obj.view.handles.panels.segmentation.handles.lassoObjectPicker.Visible = 'on';
        obj.view.handles.panels.segmentation.handles.panelLasso.Visible = 'on'; 
    case 'Segment-anything model'
        obj.view.handles.panels.segmentation.handles.panelSAM.Visible = 'on';  
end


end
