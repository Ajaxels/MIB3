function restrictMask_Callback(obj, hWidget, hData)
% function restrictMask_Callback(obj, hWidget, hData)
% callbacks for press of obj.handles.panels.segmentation.handles.restrictMask in
% obj.handles.panels.segmentation panel. Restrict selection to the mask layer
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
    fprintf('controllers.MibSegmentationController.restrictMask_Callback: change state of "obj.view.handles.panels.segmentation.handles.restrictMask" -> %d\n', hWidget.Value);
end

switch hWidget.Value
    case true

    case false

end


end