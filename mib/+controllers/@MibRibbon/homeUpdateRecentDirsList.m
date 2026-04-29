function homeUpdateRecentDirsList(obj)
% HOMEUPDATERECENTDIRSLIST - update the recent directories list (obj.view.handles.ribbonHome.loadFile.Popup) under the Open image button (obj.view.handles.ribbonHome.loadFile) of.
%
% Syntax:
%   function homeUpdateRecentDirsList(obj)
%
% the Home ribbon (obj.view.handles.ribbonHome)
%
% Triggered on listening to MibModel->UpdateRecentDirsList event (notify(obj.mibModel, 'UpdateRecentDirsList');
% called in models.MibModel.loadImages function

arguments (Input)
    obj controllers.MibRibbon
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.homeUpdateRecentDirsList: update the list of recent directories\n');
end

% get alias for Dirs
Dirs = obj.mibModel.preferences.System.Dirs;

popupList = matlab.ui.internal.toolstrip.PopupList;
% add header
header = matlab.ui.internal.toolstrip.PopupListHeader('Recent directories');
popupList.add(header);

if ~isempty(Dirs.RecentDirs)
    import matlab.ui.internal.toolstrip.ListItem
    
    for i=1:numel(Dirs.RecentDirs)
        dirPath = Dirs.RecentDirs{i};
        listItemHandle = ListItem(dirPath);
        listItemHandle.ItemPushedFcn = @(src, evt)obj.homeSelectRecentDir_Callback(dirPath);
        popupList.add(listItemHandle);
    end
end

% add popup popupList to the button
obj.view.handles.ribbonHome.loadFile.Popup = popupList;

end
