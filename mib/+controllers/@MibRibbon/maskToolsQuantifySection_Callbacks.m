function maskToolsQuantifySection_Callbacks(obj, hWidget, hData)
% MASKTOOLSQUANTIFYSECTION_CALLBACKS - callback on press of buttons in the Tools and Quantification sections of the Mask ribbon.
%
% Syntax:
%   function maskToolsQuantifySection_Callbacks(obj, hWidget, hData)
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
    fprintf('controllers.MibRibbon.maskToolsQuantifySection_Callbacks: Mask ribbon-> Import section pressed -> %s\n', mode);
end

switch mode
    case 'Invert'        % obj.handles.ribbonMask.export or obj.handles.ribbonMask.invert
    case 'Shown slice (2D)'       % obj.handles.ribbonMask.invert2D
    case 'Current stack (3D)'                     % obj.handles.ribbonMask.invert3D
    case 'Complete volume (4D)'                     % obj.handles.ribbonMask.invert4D
    case sprintf('Replace\nmasked areas')                     % obj.handles.ribbonMask.replaceImage
    case sprintf('Smooth\nmask')                    % obj.handles.ribbonMask.smooth
    case 'Quantify'                    % obj.handles.ribbonMask.quantify
end


end
