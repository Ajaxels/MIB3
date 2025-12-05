function gui_Callbacks(obj, hWidget, hData)
% function gui_Callbacks(obj, hWidget, hData)
% callbacks for widgets of some the Status bar obj.handles.status
%
% Parameters:
% hWidget: handle to the pressed widget
% hWidget.tag -> char, identifier the widget
%
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibStatusBar
    hWidget {mustBeA(hWidget, {'matlab.ui.internal.toolstrip.base.Action'})}
    hData {mustBeA(hData, {'matlab.ui.internal.toolstrip.base.ToolstripEventData'})}
end

mode = hWidget.Description;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibStatusBar.gui_Callbacks: "obj.view.handles.status -> %s"\n', mode);
end

switch mode
    case 'Use the system directory selection dialog to define the working directory'
    case 'Enter the working directory'
    case 'Copy the current working directory to clipboard'
    case 'Open the current working directory in a system file browser'
    case 'Define the zoom level'
end

end