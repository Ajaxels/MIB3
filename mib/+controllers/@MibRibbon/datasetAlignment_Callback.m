function datasetAlignment_Callback(obj, hWidget, hData)
% DATASETALIGNMENT_CALLBACK - callback on press of buttons in the Alignment section of the Dataset ribbon.
%
% Syntax:
%   function datasetAlignment_Callback(obj, hWidget, hData)
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
    fprintf('controllers.MibRibbon.datasetAlignment_Callback: Alignment section pressed -> %s\n', mode);
end

end
