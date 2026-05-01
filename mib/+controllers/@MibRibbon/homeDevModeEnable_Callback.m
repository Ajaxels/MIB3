function homeDevModeEnable_Callback(obj, hWidget, hData)
% HOMEDEVMODEENABLE_CALLBACK - Enable or disable developer mode that shows handles of widgets in.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.homeDevModeEnable_Callback(hWidget, hData)
%
% tooltips

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.homeDevTest_Callback: pressed\n');
end

statusText = 'DISABLED';
if hData.EventData.NewValue
    statusText = 'ENABLED';
end
% update DeveloperMode switch
obj.mibModel.preferences.System.DeveloperMode = hData.EventData.NewValue;

options.MsgBoxOnly = true;
options.Icon       = 'puffin_info';
options.HeaderLines = 1;
infoText = 'Restart MIB to update tooltips!';
utils.dlgs.inputUniversalDlg(obj.view.gui, sprintf('The developer mode was %s!', statusText), {infoText}, {infoText}, 'Info', options);

end
