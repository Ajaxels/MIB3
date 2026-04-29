function imageColors_Callbacks(obj, hWidget, hData)
% IMAGECOLORS_CALLBACKS - callback on press of the color channel buttons in the Image ribbon.
%
% Syntax:
%   function imageColors_Callbacks(obj, hWidget, hData)
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
    fprintf('controllers.MibRibbon.imageColors_Callbacks: Image ribbon->Color channels -> %s\n', mode);
end

switch mode
    case 'Insert empty channel...'  % obj.handles.ribbonImage.colorsInsert
    case 'Copy channel...'          % obj.handles.ribbonImage.colorsCopy
    case 'Invert channel...'        % obj.handles.ribbonImage.colorsInvert
    case 'Rotate channel...'        % obj.handles.ribbonImage.colorsRotate
    case 'Shift channel...'         % obj.handles.ribbonImage.colorsShift
    case 'Swap channel...'          % obj.handles.ribbonImage.colorsSwap
    case 'Delete channel...'        % obj.handles.ribbonImage.colorsDelete
end


end
