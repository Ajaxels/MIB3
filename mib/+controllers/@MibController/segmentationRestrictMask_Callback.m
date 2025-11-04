function segmentationRestrictMask_Callback(obj, hWidget, hData)
% function segmentationRestrictMask_Callback(obj, hWidget, hData)
% callbacks for press of obj.handles.panels.segmentation.handles.restrictMask in
% obj.handles.panels.segmentation panel. Restrict selection to the mask layer
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibController
    hWidget matlab.ui.control.CheckBox
    hData matlab.ui.eventdata.ValueChangedData
end

switch hWidget.Value
    case true
        fprintf('mibController.segmentationRestrictMask_Callback: press of obj.handles.panels.segmentation.handles.restrictMask: %d\n', hWidget.Value);
    case false
        fprintf('mibController.segmentationRestrictMask_Callback: press of obj.handles.panels.segmentation.handles.restrictMask: %d\n', hWidget.Value);
end


end