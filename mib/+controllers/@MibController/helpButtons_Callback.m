function helpButtons_Callback(obj, hWidget, hData)
% function helpButtons_Callback(obj, hWidget, hData)
% callback for click on the Help buttons in various panels of MIB
% The function is triggered by clicks on
% - obj.handles.panels.dirContents.handles.help
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibController
    hWidget matlab.ui.control.Button
    hData matlab.ui.eventdata.ButtonPushedData
end

switch hWidget.Tag
    case 'dirContentsHelp'
        if obj.mibModel.preferences.System.DeveloperMode
            fprintf('controllers.MibController.helpButtons_Callback: clicked on "obj.handles.panels.dirContents.handles.help" -> %s\n', hWidget.Tag);
        end
    case 'segmentationHelp'
        if obj.mibModel.preferences.System.DeveloperMode
            fprintf('controllers.MibController.helpButtons_Callback: clicked on "obj.handles.panels.segmentation.handles.help" -> %s\n', hWidget.Tag);
        end
    case 'roiHelp'
        if obj.mibModel.preferences.System.DeveloperMode
            fprintf('controllers.MibController.helpButtons_Callback: clicked on "obj.handles.panels.roi.handles.help" -> %s\n', hWidget.Tag);
        end
end
end
