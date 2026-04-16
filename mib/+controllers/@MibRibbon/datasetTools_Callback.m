function datasetTools_Callback(obj, hWidget, hData)
% function datasetTools_Callback(obj, hWidget, hData)
% callback on press of buttons in the Dataset tools section of the Dataset ribbon
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
    fprintf('controllers.MibRibbon.datasetTools_Callback: Dataset tools section pressed -> %s\n', mode);
end

switch mode
    case 'Crop'              % obj.handles.ribbonDataset.crop
        obj.mibController.startController('controllers.CropDataset', obj.mibController);
    case 'Resize'                 % obj.handles.ribbonDataset.resize
end

end