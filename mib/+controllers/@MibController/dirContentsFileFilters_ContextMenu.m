function dirContentsFileFilters_ContextMenu(obj, menuEntry, selectedData)
% function dirContentsFileFilters_ContextMenu(obj, menuEntry, selectedData)
% callbacks for the context menu of the file filters widget
% (obj.handles.panels.datasets.handles.fileFilters)
%
% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to the pressed
% 'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
% button that has the context menu (selectedData.ContextObject)
%
% Available menu options available from 'menuEntry.Tag':
% fileFiltersContextRegister - register a new extension and add it to the list of available filename extensions
% fileFiltersContextUnregister - remove extension from the list of available filename extensions

arguments (Input)
    obj controllers.MibController
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

switch menuEntry.Tag
    case 'fileFiltersContextRegister'
        fprintf('Pressed: obj.controller.dirContentsFileFilters_ContextMenu -> %s\n', menuEntry.Tag);
    case 'fileFiltersContextUnregister'
        fprintf('Pressed: obj.controller.dirContentsFileFilters_ContextMenu -> %s\n', menuEntry.Tag);
end

end