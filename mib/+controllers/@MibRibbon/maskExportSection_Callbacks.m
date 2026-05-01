function maskExportSection_Callbacks(obj, hWidget, hData)
% MASKEXPORTSECTION_CALLBACKS - callback on press of buttons in the Export section of the Mask ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.maskExportSection_Callbacks(hWidget, hData)
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
    fprintf('controllers.MibRibbon.maskExportSection_Callbacks: Mask ribbon-> Import section pressed -> %s\n', mode);
end

switch mode
    case {'Export', 'Export mask to MATLAB'}        % obj.handles.ribbonMask.export or obj.handles.ribbonMask.exportToMatlab
        obj.mibModel.exportDataset('mask');
    case 'Export mask to Imaris'                     % obj.handles.ribbonMask.exportToImaris
        obj.mibModel.exportDatasetToImaris('mask');
    case 'Export mask to another MIB dataset'       % obj.handles.ribbonMask.exportToMIB
        obj.mibModel.exportDatasetToMib('mask');
    case sprintf('Save\nmask')                      % obj.handles.ribbonMask.saveMask
        obj.mibModel.save('mask');
end


end
