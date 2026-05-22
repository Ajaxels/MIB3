function imageColors_Callbacks(obj, hWidget, hData)
% IMAGECOLORS_CALLBACKS - callback on press of the color channel buttons in the Image ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.imageColors_Callbacks(hWidget, hData)
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
        obj.mibModel.colorChannelActions('Insert empty channel');
    case 'Copy channel...'          % obj.handles.ribbonImage.colorsCopy
        obj.mibModel.colorChannelActions('Copy channel');
    case 'Invert channel...'        % obj.handles.ribbonImage.colorsInvert
        obj.mibModel.colorChannelActions('Invert channel');
    case 'Rotate channel...'        % obj.handles.ribbonImage.colorsRotate
        obj.mibModel.colorChannelActions('Rotate channel');
    case 'Shift channel...'         % obj.handles.ribbonImage.colorsShift
        obj.mibModel.colorChannelActions('Shift channel');
    case 'Swap channel...'          % obj.handles.ribbonImage.colorsSwap
        obj.mibModel.colorChannelActions('Swap channels');
    case 'Delete channel...'        % obj.handles.ribbonImage.colorsDelete
        obj.mibModel.colorChannelActions('Delete channel');
end


end
