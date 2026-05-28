function modelQuantification_Callback(obj, hWidget, hData)
% MODELQUANTIFICATION_CALLBACK - callback on press of the Quantification button in the Model ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.modelQuantification_Callback(hWidget, hData)
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

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.modelQuantification_Callback: Model ribbon->Quantification -> obj.handles.ribbonModel.quantification\n');
end


end
