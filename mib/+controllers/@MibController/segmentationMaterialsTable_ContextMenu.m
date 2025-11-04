function segmentationMaterialsTable_ContextMenu(obj, menuEntry, selectedData)
% function segmentationMaterialsTable_ContextMenu(obj, menuEntry, selectedData)
% callbacks for the context menu of the segmentation table widget
% (obj.handles.panels.segmentation.handles.materialsTable)
%
% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to the pressed
% 'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
% button that has the context menu (selectedData.ContextObject)
%
% Available menu options available from 'menuEntry.Tag':
% materialsTableContextShowSelected -> show only the selected material
% materialsTableContextRename -> rename the selected material
% materialsTableContextSetColor -> update color for the selected material
% materialsTableContextQuant -> quantify the selected material
% materialsTableContextUnlink -> unlink the selected material from the Add to column

arguments (Input)
    obj controllers.MibController
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

switch menuEntry.Tag
    case 'materialsTableContextShowSelected'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext -> %s\n', menuEntry.Tag);
    case 'materialsTableContextRename'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext -> %s\n', menuEntry.Tag);
    case 'materialsTableContextSetColor'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext -> %s\n', menuEntry.Tag);
    case 'materialsTableContextQuant'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext -> %s\n', menuEntry.Tag);
    case 'materialsTableContextUnlink'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext -> %s\n', menuEntry.Tag);
end
