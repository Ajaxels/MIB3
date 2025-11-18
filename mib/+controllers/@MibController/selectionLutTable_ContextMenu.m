function selectionLutTable_ContextMenu(obj, menuEntry, selectedData)
% function selectionLutTable_ContextMenu(obj, menuEntry, selectedData)
% callbacks for the context menu of the LUT table widget
% (obj.view.handles.panels.selection.handles.lutTable)
%
% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to the pressed
% 'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
% button that has the context menu (selectedData.ContextObject)
%
% Available menu options available from 'menuEntry.Tag':
% lutTableContextInsert -> insert an empty color channel
% lutTableContextCopy -> copy the selected color channel to a new one
% lutTableContextInvert -> invert the selected color channel
% lutTableContextRotate -> rotate the selected color channel
% lutTableContextShift -> shift the selected color channel
% lutTableContextSwap -> swap two color channels
% lutTableContextDelete -> delete the selected color channel
% lutTableContextSetLUT -> select new color for the selected color channel to show the the LUT mode

arguments (Input)
    obj controllers.MibController
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibController.selectionLutTable_ContextMenu: context menu for "obj.view.handles.panels.selection.handles.lutTable" -> %s\n', menuEntry.Tag);
end
selectedRows = obj.view.handles.panels.selection.handles.lutTable.UserData(:,1);

switch menuEntry.Tag
    case 'lutTableContextInsert' % insert an empty color channel
        
    case 'lutTableContextCopy' % copy the selected color channel to a new one
        
    case 'lutTableContextInvert' % invert the selected color channel
        
    case 'lutTableContextRotate' % rotate the selected color channel
        
    case 'lutTableContextShift' % shift the selected color channel
        
    case 'lutTableContextSwap' % swap two color channels
        
    case 'lutTableContextDelete' % delete the selected color channel
        
    case 'lutTableContextSetLUT' % select new color for the selected color channel to show the the LUT mode
        

end

