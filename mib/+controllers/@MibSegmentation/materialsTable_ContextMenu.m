function materialsTable_ContextMenu(obj, menuEntry, selectedData)
% function materialsTable_ContextMenu(obj, menuEntry, selectedData)
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