function homeExport_Callback(obj, hWidget, hData)
% function homeExport_Callback(obj, hWidget, hData)
% callback on press of buttons in the Export section of the Home ribbon
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
    fprintf('controllers.MibRibbon.homeExport_Callback: Export panel button pressed -> %s\n', mode);
end

switch mode
    case 'Save as'     % obj.handles.ribbonHome.saveFileAs — save image with dialog
        obj.mibModel.saveImage('image');
    case {'Export', 'Export to MATLAB'}     % obj.handles.ribbonHome.export & obj.handles.ribbonHome.exportToMatlab
        obj.mibModel.exportDataset('image');
    case 'Export to Imaris'     % obj.handles.ribbonHome.exportToImaris
        obj.mibModel.exportDatasetToImaris('image');
    case 'Snapshot'     % obj.handles.ribbonHome.snapshot
    case 'Movie'     % obj.handles.ribbonHome.movie
    case {'Render', 'MIB Rendering'}     % obj.handles.ribbonHome.render &  obj.handles.ribbonHome.renderMIB
    case 'MATLAB Volume Viewer'     % obj.handles.ribbonHome.renderMatlab
    case '3D viewer in Fiji'     % obj.handles.ribbonHome.renderFiji
end
end