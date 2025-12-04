function homeImport_Callback(obj, hWidget, hData)
% function homeImport_Callback(obj, hWidget, hData)
% callback on press of the import buttons in the Home ribbon
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
    fprintf('controllers.MibRibbon.homeImport_Callback: Load dataset pressed -> %s\n', mode);
end

switch mode
    case {'Import', 'MATLAB'}  % obj.handles.ribbonHome.import &  obj.handles.ribbonHome.importFromMatlab
    case 'System Clipboard'    % obj.handles.ribbonHome.importFromClipboard
    case 'Imaris'              % obj.handles.ribbonHome.importFromImaris
    case 'Omero'               % obj.handles.ribbonHome.importFromOmero
    case 'URL'                 % obj.handles.ribbonHome.importFromURL
end

end