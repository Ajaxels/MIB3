function datasetTools_Callback(obj, hWidget, hData)
% DATASETTOOLS_CALLBACK - callback on press of buttons in the Dataset tools section of the Dataset ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.datasetTools_Callback(hWidget, hData)
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
    fprintf('controllers.MibRibbon.datasetTools_Callback: Dataset tools section pressed -> %s\n', mode);
end

switch mode
    case 'Alignment'
        obj.mibController.startController('controllers.Alignment');
    case 'Crop'              % obj.handles.ribbonDataset.crop
        obj.mibController.startController('controllers.CropDataset', obj.mibController);
    case 'Resize'           % obj.handles.ribbonDataset.resize
        obj.mibController.startController('controllers.ResampleDataset');
end

end
