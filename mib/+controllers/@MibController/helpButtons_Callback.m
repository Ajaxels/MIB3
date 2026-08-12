function helpButtons_Callback(obj, hWidget, hData)
% HELPBUTTONS_CALLBACK - callback for click on the Help buttons in various panels of MIB.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.helpButtons_Callback(hWidget, hData)
%
% The function is triggered by clicks on
% - obj.handles.panels.dirContents.handles.help
%
% Input Arguments:
%   - **hWidget** - handle to the pressed widget
%   - **hData** - handle to supporting data class
%
% Output Arguments:
%   (none)
%

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
        helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'panels', 'dircontents', 'index.html');
        utils.openHelpPage(helpFilPath, 'http://mib.helsinki.fi/help/main3/user-interface/panels/dircontents/index.html');
    case 'segmentationHelp'
        if obj.mibModel.preferences.System.DeveloperMode
            fprintf('controllers.MibController.helpButtons_Callback: clicked on "obj.handles.panels.segmentation.handles.help" -> %s\n', hWidget.Tag);
        end
        helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'panels', 'segm', 'index.html');
        utils.openHelpPage(helpFilPath, 'http://mib.helsinki.fi/help/main3/user-interface/panels/segm/index.html');
    case 'roiHelp'
        if obj.mibModel.preferences.System.DeveloperMode
            fprintf('controllers.MibController.helpButtons_Callback: clicked on "obj.handles.panels.roi.handles.help" -> %s\n', hWidget.Tag);
        end
        helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'panels', 'roi', 'index.html');
        utils.openHelpPage(helpFilPath, 'http://mib.helsinki.fi/help/main3/user-interface/panels/roi/index.html');
end
end
