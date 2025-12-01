function restrictMaterial_Callback(obj, hWidget, hData)
% function restrictMaterial_Callback(obj, hWidget, hData)
% callbacks for press of obj.handles.panels.segmentation.handles.restrictMaterial in
% obj.handles.panels.segmentation panel.
% Restrict selection to the selected material in obj.handles.panels.segmentation.handles.materialsTable
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibSegmentationController
    hWidget matlab.ui.control.CheckBox
    hData matlab.ui.eventdata.ValueChangedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentationController.restrictMaterial_Callback: change state of "obj.view.handles.panels.segmentation.handles.restrictMaterial" -> %d\n', hWidget.Value);
end

switch hWidget.Value
    case true

    case false

end

end
