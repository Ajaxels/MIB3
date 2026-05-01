function lutTable_ContextMenu(obj, menuEntry, selectedData)
% LUTTABLE_CONTEXTMENU - callbacks for the context menu of the LUT table widget.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.lutTable_ContextMenu(menuEntry, selectedData)
%
%
% Input Arguments:
%   - **menuEntry** — [matlab.ui.container.Menu] pressed context menu entry
%   - **selectedData** — [MenuSelectedData] menu event data; use ``.ContextObject`` to find source widget
%
% Available menu options (from `menuEntry.Tag`):
%
%   - ``'lutTableContextInsert'`` — insert an empty color channel
%   - ``'lutTableContextCopy'`` — copy selected color channel to a new one
%   - ``'lutTableContextInvert'`` — invert selected color channel
%   - ``'lutTableContextRotate'`` — rotate selected color channel
%   - ``'lutTableContextShift'`` — shift selected color channel
%   - ``'lutTableContextSwap'`` — swap two color channels
%   - ``'lutTableContextDelete'`` — delete selected color channel
%   - ``'lutTableContextSetLUT'`` — select new color for selected color channel (LUT mode)
%

arguments (Input)
    obj controllers.MibSelection
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSelection.lutTable_ContextMenu: context menu for "obj.view.handles.panels.selection.handles.lutTable" -> %s\n', menuEntry.Tag);
end

% cancel if no row selected
if isempty(obj.view.handles.panels.selection.handles.lutTable.UserData); return; end

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


