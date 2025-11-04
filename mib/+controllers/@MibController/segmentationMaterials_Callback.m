function segmentationMaterials_Callback(obj, menuEntry, selectedData)
% function segmentationMaterials_Callback(obj, menuEntry, selectedData)
% callbacks for the context menu of
% - Segmentation table widget -> Materials...  entry (obj.view.handles.panels.segmentation.handles.materialsTableContextMat)
% - Menu ribbon -> Models -> Materials (obj.view.handles.model.materials)
%
% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to the pressed
% 'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
% button that has the context menu (selectedData.ContextObject)
%
% Available menu options available from 'menuEntry.Text':
% 'Rename material' -> rename the selected material
% 'Add material' -> add a new material to the model
% 'Insert material' -> insert a new material to the model
% 'Swap materials' ->  swap positions of the two materials
% 'Reorder materials' -> reorder materials
% 'Export material' -> export the selected material
% 'Save material to file' -> save the selected material
% 'Remove materials' -> remove the selected material


arguments (Input)
    obj controllers.MibController
    menuEntry {mustBeA(menuEntry, {'matlab.ui.container.Menu', 'matlab.ui.internal.toolstrip.base.Action'})} 
    selectedData {mustBeA(selectedData, {'matlab.ui.eventdata.MenuSelectedData', 'matlab.ui.internal.toolstrip.base.ToolstripEventData'})} 
end

switch menuEntry.Text
    case 'Rename material'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext (or menu) -> %s\n', menuEntry.Text);
    case 'Add material'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext (or menu) -> %s\n', menuEntry.Text);
    case 'Insert material'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext (or menu) -> %s\n', menuEntry.Text);
    case 'Swap materials'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext (or menu) -> %s\n', menuEntry.Text);
    case 'Reorder materials'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext (or menu) -> %s\n', menuEntry.Text);
    case 'Export material'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext (or menu) -> %s\n', menuEntry.Text);
    case 'Save material to file'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext (or menu) -> %s\n', menuEntry.Text);
    case 'Remove materials'
        fprintf('Pressed: obj.handles.panels.segmentation.handles.materialsTableContext (or menu) -> %s\n', menuEntry.Text);
end

end