function datasetToolsTransform_Callback(obj, hWidget, hData)
% function datasetToolsTransform_Callback(obj, hWidget, hData)
% callback on press of buttons in the Transform button of the Dataset ribbon
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
    fprintf('controllers.MibRibbon.datasetToolsTransform_Callback: Dataset tools->Transform section pressed -> %s\n', mode);
end

switch mode
    case 'Update with new width/height'              % obj.handles.ribbonDataset.addframeWidth
    case 'Update with new dX/dY'                 % obj.handles.ribbonDataset.addframedX
    case 'Flip horizontally'              % obj.handles.ribbonDataset.flipH
    case 'Flip vertically'                 % obj.handles.ribbonDataset.flipV
    case 'Flip Z'              % obj.handles.ribbonDataset.flipZ
    case 'Flip T'                 % obj.handles.ribbonDataset.flipT
    case 'Rotate 90 degrees'              % obj.handles.ribbonDataset.rotPos90
    case 'Rotate -90 degrees'                 % obj.handles.ribbonDataset.rotNeg90
    case 'Transpose YX -> YZ'              % obj.handles.ribbonDataset.transposeYX2YZ
    case 'Transpose YX -> XZ'                 % obj.handles.ribbonDataset.transposeYX2XZ
    case 'Transpose YX -> XY'              % obj.handles.ribbonDataset.transposeYX2XY
    case 'Transpose Z <-> T'                 % obj.handles.ribbonDataset.transposeZ2T
    case 'Transpose Z <-> C'                 % obj.handles.ribbonDataset.transposeZ2C
    
end


end