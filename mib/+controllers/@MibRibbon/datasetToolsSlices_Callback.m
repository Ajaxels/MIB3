function datasetToolsSlices_Callback(obj, hWidget, hData)
% function datasetToolsSlices_Callback(obj, hWidget, hData)
% callback on press of buttons in the Slices button of the Dataset ribbon
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
    fprintf('controllers.MibRibbon.datasetToolsSlices_Callback: Dataset tools->Slices section pressed -> %s\n', mode);
end

switch mode
    case 'Copy slice...'              % obj.handles.ribbonDataset.sliceCopy
    case 'Insert empty slice(s)...'                 % obj.handles.ribbonDataset.sliceInsert
    case 'Interval slicing...'              % obj.handles.ribbonDataset.sliceInterval
    case 'Swap slices...'                 % obj.handles.ribbonDataset.sliceSwap
    case 'Delete slice(s)...'              % obj.handles.ribbonDataset.sliceDelete
    case 'Delete frame(s)...'                 % obj.handles.ribbonDataset.sliceFrameDelete
end


end