function dirContentsBioFormats_Callback(obj, hWidget, hData)
% function dirContentsBioFormats_Callback(obj, hWidget, hData)
% callback for selection of the bio-formats reader by press on obj.handles.panels.dirContents.handles.bioFormats
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
    fprintf('controllers.MibController.dirContentsBioFormats_Callback: clicked on "obj.view.handles.panels.dirContents.handles.bioFormats" -> state=%d\n', hWidget.Value);
end

end