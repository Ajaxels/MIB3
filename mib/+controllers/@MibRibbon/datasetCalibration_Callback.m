function datasetCalibration_Callback(obj, hWidget, hData)
% DATASETCALIBRATION_CALLBACK - callback on press of buttons in the Calibration section of the Dataset ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.datasetCalibration_Callback(hWidget, hData)
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
    fprintf('controllers.MibRibbon.datasetCalibration_Callback: Dataset tools->Calibration section pressed -> %s\n', mode);
end

switch mode
    case 'Scale bar'              % obj.handles.ribbonDataset.scalebar
    case 'Bounding box'           % obj.handles.ribbonDataset.boundingbox
        obj.mibController.startController('controllers.BoundingBox');  % a new appdesigner version
    case 'Voxels'                % obj.handles.ribbonDataset.voxels
        obj.updateVoxelSizes();
end


end
