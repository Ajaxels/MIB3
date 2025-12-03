function favTool_Callback(obj, hWidget, hData)
% function favTool_Callback(obj, hWidget, hData)
% callbacks for press of obj.handles.panels.segmentation.handles.favoriteTool in
% obj.handles.panels.segmentation panel.
% Select the current tool as favorite, the favorite tools available upon
% press of the 'D' keyboard shortcut key
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibSegmentation
    hWidget matlab.ui.control.CheckBox
    hData matlab.ui.eventdata.ValueChangedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.favTool_Callback: change state of "obj.view.handles.panels.segmentation.handles.favoriteTool" -> %d\n', hWidget.Value);
end

switch hWidget.Value
    case true
        
    case false
        
end


end
