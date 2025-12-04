function datasetCalibration_Callback(obj, hWidget, hData)
% function datasetCalibration_Callback(obj, hWidget, hData)
% callback on press of buttons in the Calibration section of the Dataset ribbon
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
    fprintf('controllers.MibRibbon.datasetCalibration_Callback: Dataset tools->Calibration section pressed -> %s\n', mode);
end

switch mode
    case 'Copy slice...'              % obj.handles.ribbonDataset.scalebar
    case 'Insert empty slice(s)...'                 % obj.handles.ribbonDataset.boundingbox
    case 'Interval slicing...'              % obj.handles.ribbonDataset.voxels
end


end