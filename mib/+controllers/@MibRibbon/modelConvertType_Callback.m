function modelConvertType_Callback(obj, hWidget, hData)
% MODELCONVERTTYPE_CALLBACK - callback on press of the convert model type buttons in the Model ribbon.
%
% Syntax:
%   function modelConvertType_Callback(obj, hWidget, hData)
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
    fprintf('controllers.MibRibbon.modelConvertType_Callback: Model ribbon->Covert type -> %s\n', mode);
end

switch mode
    case '63 materials'  % obj.handles.ribbonModel.mat63
    case '255 materials'          % obj.handles.ribbonModel.mat255
    case '65535 materials'        % obj.handles.ribbonModel.mat65535
    case '4294967295 materials'        % obj.handles.ribbonModel.mat4294967295
    case '2D objects conn4'         % obj.handles.ribbonModel.indexed2dconn4
    case '2D objects conn8'          % obj.handles.ribbonModel.indexed2dconn8
    case '3D objects conn4'        % obj.handles.ribbonModel.indexed3dconn4
    case '3D objects conn8'        % obj.handles.ribbonModel.indexed3dconn8
end

end
