function maskImportExportSection_Callbacks(obj, hWidget, hData)
% MASKIMPORTEXPORTSECTION_CALLBACKS - callback on press of buttons in the Export section of the Mask ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.maskImportExportSection_Callbacks(hWidget, hData)
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
    fprintf('controllers.MibRibbon.maskImportExportSection_Callbacks: Mask ribbon-> Import/Export section pressed -> %s\n', mode);
end

switch mode
    case sprintf('Clear\nmask')      % obj.handles.ribbonMask.clear
        obj.mibModel.clearMask('4D, Dataset');
    case sprintf('Load\nmask')   % obj.handles.ribbonMask.load
        obj.mibModel.loadMask();
    case {'Import', 'Import mask from MATLAB'}  % obj.handles.ribbonMask.import or obj.handles.ribbonMask.importFromMatlab
        obj.mibModel.importDataset('mask');
    case 'Import mask from another MIB dataset'      % obj.handles.ribbonMask.importFromMIB
        obj.mibModel.importDatasetFromMib('mask');
    case {'Export', 'Export mask to MATLAB'}        % obj.handles.ribbonMask.export or obj.handles.ribbonMask.exportToMatlab
        obj.mibModel.exportDataset('mask');
    case 'Export mask to Imaris'                     % obj.handles.ribbonMask.exportToImaris
        obj.mibModel.exportDatasetToImaris('mask');
    case 'Export mask to another MIB dataset'       % obj.handles.ribbonMask.exportToMIB
        obj.mibModel.exportDatasetToMib('mask');
    case sprintf('Save\nmask')                      % obj.handles.ribbonMask.saveMask
        obj.mibModel.saveMask([]);
end


end
