function maskExportSection_Callbacks(obj, hWidget, hData)
% function maskExportSection_Callbacks(obj, hWidget, hData)
% callback on press of buttons in the Export section of the Mask ribbon
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
    fprintf('controllers.MibRibbon.maskExportSection_Callbacks: Mask ribbon-> Import section pressed -> %s\n', mode);
end

switch mode
    case {'Export', 'Export mask to MATLAB'}        % obj.handles.ribbonMask.export or obj.handles.ribbonMask.exportToMatlab
    case 'Export mask to another MIB dataset'       % obj.handles.ribbonMask.exportToMIB
    case sprintf('Save\nmask')                      % obj.handles.ribbonMask.saveMask
end


end