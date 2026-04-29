function datasetMetadata_Callback(obj, hWidget, hData)
% DATASETMETADATA_CALLBACK - callback on press of buttons in the Metadata section of the Dataset ribbon.
%
% Syntax:
%   function datasetMetadata_Callback(obj, hWidget, hData)
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
    fprintf('controllers.MibRibbon.datasetMetadata_Callback: Dataset tools->Metadata section pressed -> %s\n', mode);
end

switch mode
    case 'Action log'              % obj.handles.ribbonDataset.log
    case 'Metadata'                 % obj.handles.ribbonDataset.info
end


end
