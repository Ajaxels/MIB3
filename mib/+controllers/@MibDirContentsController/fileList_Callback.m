function fileList_Callback(obj, hWidget, hData)
% function fileList_Callback(obj, hWidget, hData)
% callback for double click on a filename in obj.handles.panels.dirContents.handles.fileList
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting ButtonPushedData class

arguments (Input)
    obj controllers.MibDirContentsController
    hWidget matlab.ui.control.ListBox
    hData matlab.ui.eventdata.DoubleClickedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDirContentsController.fileList_Callback: Double clicked on: obj.handles.panels.dirContents.handles.fileList\n');
end
end
