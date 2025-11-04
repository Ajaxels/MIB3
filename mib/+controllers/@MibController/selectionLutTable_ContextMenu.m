function selectionLutTable_ContextMenu(obj, menuEntry, selectedData)
% function selectionLutTable_ContextMenu(obj, menuEntry, selectedData)
% callbacks for the context menu of the LUT table widget
% (obj.handles.panels.selection.handles.lutTable)
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

switch menuEntry.Tag
    case 'lutTableContextInsert' % insert an empty color channel
        fprintf('Pressed: obj.handles.panels.selection.handles.lutTableContext -> %s\n', menuEntry.Tag);
    case 'lutTableContextCopy' % copy the selected color channel to a new one
        fprintf('Pressed: obj.handles.panels.selection.handles.lutTableContext -> %s\n', menuEntry.Tag);
    case 'lutTableContextInvert' % invert the selected color channel
        fprintf('Pressed: obj.handles.panels.selection.handles.lutTableContext -> %s\n', menuEntry.Tag);
    case 'lutTableContextRotate' % rotate the selected color channel
        fprintf('Pressed: obj.handles.panels.selection.handles.lutTableContext -> %s\n', menuEntry.Tag);
    case 'lutTableContextShift' % shift the selected color channel
        fprintf('Pressed: obj.handles.panels.selection.handles.lutTableContext -> %s\n', menuEntry.Tag);
    case 'lutTableContextSwap' % swap two color channels
        fprintf('Pressed: obj.handles.panels.selection.handles.lutTableContext -> %s\n', menuEntry.Tag);
    case 'lutTableContextDelete' % delete the selected color channel
        fprintf('Pressed: obj.handles.panels.selection.handles.lutTableContext -> %s\n', menuEntry.Tag);
    case 'lutTableContextSetLUT' % select new color for the selected color channel to show the the LUT mode
        fprintf('Pressed: obj.handles.panels.selection.handles.lutTableContext -> %s\n', menuEntry.Tag);

end

