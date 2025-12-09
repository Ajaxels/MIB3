function homePreferences_Callback(obj, hWidget, hData)
% function homePreferences_Callback(obj, hWidget, hData)
% callback on press of the preferences section buttons in the Home ribbon
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting EventData class

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

mode = hWidget.Text;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.homePreferences_Callback: button in the preferences section pressed -> %s\n', mode);
end

switch mode
    case {'Load layout', 'Load local default layout'}   % obj.handles.ribbonHome.loadLayout or obj.handles.ribbonHome.loadLayoutLocalDefault
        obj.mibController.loadLayout('localDefault');
    case 'Load custom layout'                           % obj.handles.ribbonHome.loadLayoutCustom
        obj.mibController.loadLayout('custom');
    case 'Load MIB default layout'                      % obj.handles.ribbonHome.loadLayoutMibDefault
        obj.mibController.loadLayout('globalDefault');
    case {'Save layout', 'Save the current layout as default'}  % obj.handles.ribbonHome.saveLayout or obj.handles.ribbonHome.saveLayoutLocalDefault
        obj.mibController.saveLayout('localDefault');
    case 'Save the current layout in a custom file'             % obj.handles.ribbonHome.saveLayoutCustom
        obj.mibController.saveLayout('custom');
    case 'Save the current layout as MIB default'               % obj.handles.ribbonHome.saveLayoutMibDefault
        obj.mibController.saveLayout('globalDefault');
    case 'Preferences'                  % obj.handles.ribbonHome.preferences
        obj.mibController.startController('controllers.Preferences', obj);  % a new appdesigner version
    case 'Help'                         % obj.handles.ribbonHome.help
    case 'Open MIB help'                % obj.handles.ribbonHome.helpMenu
    case 'Tip of the day'               % obj.handles.ribbonHome.tipOfDay
        obj.mibModel.preferences.Tips.ShowTips = true;
        obj.mibController.startController('controllers.WelcomeTips');
    case 'Support on image.sc'          % obj.handles.ribbonHome.support
    case 'Personal support session'     % obj.handles.ribbonHome.call4help
    case 'API class reference'          % obj.handles.ribbonHome.classReference
    case 'Check for update'             % obj.handles.ribbonHome.checkUpdate
    case 'Your personal stats'          % obj.handles.ribbonHome.personalStats
    case 'Licenses'                     % obj.handles.ribbonHome.licenses
    case 'About MIB'                    % obj.handles.ribbonHome.about
end


end