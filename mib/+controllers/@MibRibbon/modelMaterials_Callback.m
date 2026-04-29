function modelMaterials_Callback(obj, hWidget, hData)
% MODELMATERIALS_CALLBACK - callback on press of buttons in the Materials button of the Model ribbon.
%
% Syntax:
%   function modelMaterials_Callback(obj, hWidget, hData)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting EventData class
%

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

mode = hWidget.Text;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.modelMaterials_Callback: Model ribbon->Materials -> %s\n', mode);
end

switch mode
    case 'Rename material'      % obj.handles.ribbonModel.matRename
        obj.mibModel.materialsActions('Rename material');
    case 'Add material'      % obj.handles.ribbonModel.matAdd
        obj.mibModel.materialsActions('Add material');
    case 'Insert material'    % obj.handles.ribbonModel.matInsert
        obj.mibModel.materialsActions('Insert material');
    case 'Swap materials'      % obj.handles.ribbonModel.matSwap
        obj.mibModel.materialsActions('Swap materials');
    case 'Reorder materials'      % obj.handles.ribbonModel.matReorder
        obj.mibModel.materialsActions('Reorder materials');
    case 'Export material'    % obj.handles.ribbonModel.matExport
        obj.mibModel.materialsActions('Export material');
    case 'Save material to file'      % obj.handles.ribbonModel.matSave
        obj.mibModel.materialsActions('Save material to file');
    case 'Remove materials'      % obj.handles.ribbonModel.matRemove
        obj.mibModel.materialsActions('Remove material');
end

end
