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
%   - **menuEntry** - [matlab.ui.container.Menu] pressed context menu entry
%   - **selectedData** - [MenuSelectedData] menu event data; use ``.ContextObject`` to find source widget
%
% Available menu options (from `menuEntry.Tag`):
%
%   - ``'lutTableContextInsert'`` - insert an empty color channel
%   - ``'lutTableContextCopy'`` - copy selected color channel to a new one
%   - ``'lutTableContextInvert'`` - invert selected color channel
%   - ``'lutTableContextRotate'`` - rotate selected color channel
%   - ``'lutTableContextShift'`` - shift selected color channel
%   - ``'lutTableContextSwap'`` - swap two color channels
%   - ``'lutTableContextDelete'`` - delete selected color channel
%   - ``'lutTableContextSetLUT'`` - select new color for selected color channel (LUT mode)
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
        obj.mibModel.colorChannelActions('Insert empty channel', selectedRows);
    case 'lutTableContextCopy' % copy the selected color channel to a new one
        obj.mibModel.colorChannelActions('Copy channel', selectedRows);
    case 'lutTableContextInvert' % invert the selected color channel
        obj.mibModel.colorChannelActions('Invert channel', selectedRows);
    case 'lutTableContextRotate' % rotate the selected color channel
        obj.mibModel.colorChannelActions('Rotate channel', selectedRows);
    case 'lutTableContextShift' % shift the selected color channel
        obj.mibModel.colorChannelActions('Shift channel', selectedRows);
    case 'lutTableContextSwap' % swap two color channels
        obj.mibModel.colorChannelActions('Swap channels', selectedRows);
    case 'lutTableContextDelete' % delete the selected color channel
        obj.mibModel.colorChannelActions('Delete channel', selectedRows);
    case 'lutTableContextSetLUT' % select new color for the selected color channel to show the the LUT mode
        if obj.handles.lutColors.Value == 0
            uialert(obj.view.gui, ...
                sprintf(['The colors for the color channels may be selected only in the LUT mode!\n\n' ...
                         'To enable the LUT mode please select the LUT checkbox\n' ...
                         '(Selection and View Settings Panel->LUT checkbox)']), ...
                'Requires LUT color mode!', 'Icon', 'warning');
            return;
        end
        channelIndex = selectedRows(1);
        lutColors = obj.mibModel.I{obj.mibModel.id}.image.lutColors;
        newColor = uisetcolor(lutColors(channelIndex, :), sprintf('Set color for channel %d', channelIndex));
        if isscalar(newColor); return; end
        lutColors(channelIndex, :) = newColor;
        obj.mibModel.I{obj.mibModel.id}.image.lutColors = lutColors;
        obj.lutTable_update_fromModel();
        obj.handles.lutTable.Selection = [];
        drawnow;
        notify(obj.mibModel, 'ShowImage');
end


