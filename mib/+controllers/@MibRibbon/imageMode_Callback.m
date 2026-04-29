function imageMode_Callback(obj, hWidget, hData)
% IMAGEMODE_CALLBACK - callback on press of buttons in the Mode section of the Image ribbon.
%
% Syntax:
%   function imageMode_Callback(obj, hWidget, hData)
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
    fprintf('controllers.MibRibbon.imageMode_Callback: Image ribbon-> Mode section pressed -> %s\n', mode);
end

switch mode
    case 'Grayscale'              % obj.handles.ribbonImage.grayscale
    case 'Multi-channel'                 % obj.handles.ribbonImage.multichannel
    case 'HSV color'                 % obj.handles.ribbonImage.hsv
    case 'Indexed'                 % obj.handles.ribbonImage.indexed
    case '8 bit'                 % obj.handles.ribbonImage.bit8
    case '16 bit'                 % obj.handles.ribbonImage.bit16
    case '32 bit'                 % obj.handles.ribbonImage.bit32
end


end
