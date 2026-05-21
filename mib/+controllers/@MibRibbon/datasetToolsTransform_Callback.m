function datasetToolsTransform_Callback(obj, hWidget, hData)
% DATASETTOOLSTRANSFORM_CALLBACK - callback on press of buttons in the Transform button of the Dataset ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.datasetToolsTransform_Callback(hWidget, hData)
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
    fprintf('controllers.MibRibbon.datasetToolsTransform_Callback: Dataset tools->Transform section pressed -> %s\n', mode);
end

% Normalize ' <-> ' → '<->' for BatchOpt compatibility
mode = strrep(mode, ' <-> ', '<->');

BatchOpt.Transform = {mode};
obj.mibModel.transformDataset(BatchOpt);


end
