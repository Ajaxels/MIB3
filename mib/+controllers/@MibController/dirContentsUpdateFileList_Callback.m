function dirContentsUpdateFileList_Callback(obj, hWidget, hData)
% function dirContentsUpdateFileList_Callback(obj, hWidget, hData)
% callback for click on the
% obj.handles.panels.dirContents.handles.updateFileList button to update
% the list of files shown in obj.handles.panels.dirContents.handles.fileList
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibController
    hWidget matlab.ui.control.Button
    hData matlab.ui.eventdata.ButtonPushedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibController.dirContentsUpdateFileList_Callback: clicked on: "obj.view.handles.panels.dirContents.handles.updateFileList"\n');
end

end
