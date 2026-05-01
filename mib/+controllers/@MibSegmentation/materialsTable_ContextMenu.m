function materialsTable_ContextMenu(obj, menuEntry, selectedData)
% MATERIALSTABLE_CONTEXTMENU - Callback for materials table context menu operations.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.materialsTable_ContextMenu(menuEntry, selectedData)
%
% Handles context menu operations on the materials table (``obj.handles.materialsTable``).
% Supports material visualization, renaming, color selection, quantification, and unlinking.
%
% Input Arguments:
%   - **menuEntry** — [matlab.ui.container.Menu] handle to the pressed context menu entry; operation identified via ``menuEntry.Tag``
%   - **selectedData** — [matlab.ui.eventdata.MenuSelectedData] event data containing the table object (``selectedData.ContextObject``)
%
% Output Arguments:
%   None
%
% **Supported menu operations (menuEntry.Tag):**
%   - ``'materialsTableContextShowSelected'`` — show only the selected material in view
%   - ``'materialsTableContextRename'`` — rename the selected material
%   - ``'materialsTableContextSetColor'`` — open color picker to change material color
%   - ``'materialsTableContextQuant'`` — open quantification dialog for selected material
%   - ``'materialsTableContextUnlink'`` — unlink material from "Add to" reference material
%

arguments (Input)
    obj controllers.MibSegmentation
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.materialsTable_ContextMenu: context menu for "obj.view.handles.panels.segmentation.handles.materialsTable" -> selected "%s (%s)"\n', menuEntry.Text, menuEntry.Tag);
end

switch menuEntry.Tag
    case 'materialsTableContextShowSelected'
        id = obj.mibModel.getActiveId();
        obj.mibModel.I{id}.showAllMaterials = 1 - obj.mibModel.I{id}.showAllMaterials;    % invert the showAll toggle status
        menuEntry.Checked = logical(obj.mibModel.I{id}.showAllMaterials);
        obj.mibController.showImage();
        
    case 'materialsTableContextRename'
        obj.mibModel.materialsActions('Rename material');
    case 'materialsTableContextSetColor'
        cellIndices = obj.handles.materialsTable.Selection;
        if isempty(cellIndices); return; end
        cellIndices(2) = 1;
        obj.materialsTable_CellSelectionCallback(cellIndices);    
    case 'materialsTableContextQuant'
        obj.mibController.startController('controllers.Quantification');
    case 'materialsTableContextUnlink'
        if strcmp(menuEntry.Checked, 'off')
            % unlink Materials and AddTo columns
            obj.mibModel.I{obj.mibModel.id}.unlinkMaterials = true;
            menuEntry.Checked = 'on';
        else
            % link Materials and AddTo columns
            obj.mibModel.I{obj.mibModel.id}.unlinkMaterials = false;
            menuEntry.Checked = 'off';
        end
        obj.restrictMaterial_Callback();
end

end
