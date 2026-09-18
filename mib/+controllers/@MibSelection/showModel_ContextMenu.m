function showModel_ContextMenu(obj, menuEntry, selectedData)
% SHOWMODEL_CONTEXTMENU - callbacks for the context menu of the "Show model" checkbox.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.showModel_ContextMenu(menuEntry, selectedData)
%
%
% Input Arguments:
%   - **menuEntry** - [matlab.ui.container.Menu] pressed context menu entry
%   - **selectedData** - [MenuSelectedData] menu event data; use ``.ContextObject`` to find source widget
%
% Available menu options (from `menuEntry.Tag`):
%
%   - ``'showModelContextPerObject'`` - draw an imported label overlay with one colour per
%     object instead of a single material
%
% Notes:
%   Only ``core.MibBigDataLabelsIndex`` has anything to toggle. Its
%   :attr:`core.MibBigDataLabelsIndex.renderPerObject` is applied per block read, after the
%   chunk cache, so switching it costs one redraw of the displayed slice - no re-read of the
%   store and no network request. Every other model type either has no object ids to separate
%   (the 63-material packed scheme) or already shows them, which is why
%   :func:`showModel_ContextMenuOpening` disables the entry for them.
%

arguments (Input)
    obj controllers.MibSelection
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSelection.showModel_ContextMenu: context menu for "obj.view.handles.panels.selection.handles.showModel" -> %s\n', menuEntry.Tag);
end

switch menuEntry.Tag
    case 'showModelContextPerObject' % switch an imported label overlay between one material and one colour per object
        labels = obj.mibModel.I{obj.mibModel.getActiveId()}.labels;
        % the entry is disabled for any other layer, but the buffer can be switched
        % from a shortcut while the menu is open, so the class is re-checked here
        if ~isa(labels, 'core.MibBigDataLabelsIndex'); return; end

        labels.renderPerObject = ~labels.renderPerObject;
        menuEntry.Checked = matlab.lang.OnOffSwitchState(labels.renderPerObject);
        notify(obj.mibModel, 'ShowImage');
end
end
