function modelMaterials_Callback(obj, hWidget, hData)
% function modelMaterials_Callback(obj, hWidget, hData)
% callback on press of buttons in the Materials button of the Model ribbon
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting EventData class

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
        %widgetHandles.matSwap.ItemPushedFcn = @(src, event)obj.controller.cSegmentation.materialsTable_Materials_ContextMenu(src, event);
    case 'Add material'      % obj.handles.ribbonModel.matAdd
    case 'Insert material'    % obj.handles.ribbonModel.matInsert
    case 'Swap materials'      % obj.handles.ribbonModel.matSwap
    case 'Reorder materials'      % obj.handles.ribbonModel.matReorder
    case 'Export material'    % obj.handles.ribbonModel.matExport
    case 'Save material to file'      % obj.handles.ribbonModel.matSave
    case 'Remove materials'      % obj.handles.ribbonModel.matRemove
end

end