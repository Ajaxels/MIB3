function imageMode_Callback(obj, hWidget, hData)
% IMAGEMODE_CALLBACK - callback on press of buttons in the Mode section of the Image ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.imageMode_Callback(hWidget, hData)
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
    case {'Grayscale', 'Multi-channel', 'HSV color', 'Indexed', '8 bit', '16 bit', '32 bit'}
        BatchOpt.Target = {mode};
        obj.mibModel.changeImageMode(BatchOpt);
    otherwise
        return;
end


end
