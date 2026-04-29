function  homeSelectRecentDir_Callback(obj, recentDir)
% HOMESELECTRECENTDIR_CALLBACK - callback on selection of the recent directory.
%
% Syntax:
%   function  homeSelectRecentDir_Callback(obj, recentDir)
%
% in a list (obj.view.handles.ribbonHome.loadFile.Popup) under the Open image button (obj.view.handles.ribbonHome.loadFile) of
% the Home ribbon (obj.view.handles.ribbonHome)
%
% Input Arguments:
%   - **recentDir** — char with the full directory path
%

arguments (Input)
    obj controllers.MibRibbon
    recentDir char = ''
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.homeSelectRecentDir_Callback: selection of directory\n');
end

obj.mibModel.currentDirectory = recentDir;
obj.mibController.cStatus.handles.currentDirectory.Value = obj.mibModel.currentDirectory;
obj.mibController.cDirContents.updateFileList_Callback();
end
