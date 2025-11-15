function segmentationFavTool_Callback(obj, hWidget, hData)
% function segmentationFavTool_Callback(obj, hWidget, hData)
% callbacks for press of obj.handles.panels.segmentation.handles.favoriteTool in
% obj.handles.panels.segmentation panel.
% Select the current tool as favorite, the favorite tools available upon
% press of the 'D' key shortkey
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibController
    hWidget matlab.ui.control.CheckBox
    hData matlab.ui.eventdata.ValueChangedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibController.segmentationFavTool_Callback: change state of "obj.view.handles.panels.segmentation.handles.favoriteTool" -> %d\n', hWidget.Value);
end

switch hWidget.Value
    case true
        
    case false
        
end


end
