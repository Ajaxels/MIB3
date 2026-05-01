function materialsTable_Materials_ContextMenu(obj, menuEntry, selectedData)
% MATERIALSTABLE_MATERIALS_CONTEXTMENU - Callback for materials management context menu.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.materialsTable_Materials_ContextMenu(menuEntry, selectedData)
%
% Handles material management operations from two context menu sources:
%   - Segmentation table widget ``Materials...`` entry (``obj.handles.materialsTableContextMat``)
%   - Ribbon menu ``Models → Materials`` (``obj.view.handles.model.materials``)
%
% Supports material creation, modification, deletion, reordering, and export operations.
%
% Input Arguments:
%   - **menuEntry** — [matlab.ui.container.Menu | matlab.ui.internal.toolstrip.base.Action] handle to the pressed context menu entry; operation identified via ``menuEntry.Text``
%   - **selectedData** — [matlab.ui.eventdata.MenuSelectedData | matlab.ui.internal.toolstrip.base.ToolstripEventData] event data from menu
%
% Output Arguments:
%   None
%
% **Supported menu operations (menuEntry.Text):**
%   - ``'Rename material'`` — rename the selected material
%   - ``'Add material'`` — add new material to the end of the model
%   - ``'Insert material'`` — insert new material at selected position
%   - ``'Swap materials'`` — exchange two material positions
%   - ``'Reorder materials'`` — open dialog to reorder all materials
%   - ``'Export material'`` — export selected material to file
%   - ``'Save material to file'`` — save selected material as reusable template
%   - ``'Remove materials'`` — delete selected material from model
%


arguments (Input)
    obj controllers.MibSegmentation
    menuEntry {mustBeA(menuEntry, {'matlab.ui.container.Menu', 'matlab.ui.internal.toolstrip.base.Action'})} 
    selectedData {mustBeA(selectedData, {'matlab.ui.eventdata.MenuSelectedData', 'matlab.ui.internal.toolstrip.base.ToolstripEventData'})} 
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.materialsTable_Materials_ContextMenu: context menu for "obj.view.handles.panels.segmentation.handles.materialsTable"->Materials -> selected "%s"\n', menuEntry.Text);
end

switch menuEntry.Text
    case 'Rename material'
        obj.mibModel.materialsActions('Rename material');
    case 'Add material'
        obj.mibModel.materialsActions('Add material');
    case 'Insert material'
        obj.mibModel.materialsActions('Insert material');
    case 'Swap materials'
        obj.mibModel.materialsActions('Swap materials');
    case 'Reorder materials'
        obj.mibModel.materialsActions('Reorder materials');
    case 'Export material'
        obj.mibModel.materialsActions('Export material');
    case 'Save material to file'
        obj.mibModel.materialsActions('Save material to file');
    case 'Remove materials'
        obj.mibModel.materialsActions('Remove material');
end

end
