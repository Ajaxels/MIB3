function modelRender_Callback(obj, hWidget, hData)
% MODELRENDER_CALLBACK - callback on press of buttons in the Render button of the Model ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.modelRender_Callback(hWidget, hData)
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
    fprintf('controllers.MibRibbon.modelRender_Callback: Model ribbon->Render -> %s\n', mode);
end

switch mode
    case {'Render', 'MIB rendering'}      % obj.handles.ribbonModel.render or obj.handles.ribbonModel.renderMIB
    case 'MATLAB isosurface'      % obj.handles.ribbonModel.renderMatlab
    case 'MATLAB isosurface and export to Imaris'      % obj.handles.ribbonModel.renderMatlabImaris
    case 'MATLAB volume viewer'      % obj.handles.ribbonModel.renderMatlabVolView
    case 'Fiji volume viewer'      % obj.handles.ribbonModel.renderFiji
    case 'Imaris surface'      % obj.handles.ribbonModel.renderImaris
end

end
