function maskImportSection_Callbacks(obj, hWidget, hData)
% MASKIMPORTSECTION_CALLBACKS - callback on press of buttons in the Import section of the Mask ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.maskImportSection_Callbacks(hWidget, hData)
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
    fprintf('controllers.MibRibbon.maskImportSection_Callbacks: Mask ribbon-> Import section pressed -> %s\n', mode);
end

switch mode
    case sprintf('Clear\nmask')      % obj.handles.ribbonMask.clear
    case sprintf('Load\nmask')   % obj.handles.ribbonMask.load
    case {'Import', 'Import mask from MATLAB'}  % obj.handles.ribbonMask.import or obj.handles.ribbonMask.importFromMatlab
        obj.mibModel.importDataset('mask');
    case 'Import mask from another MIB dataset'      % obj.handles.ribbonMask.importFromMIB
        obj.mibModel.importDatasetFromMib('mask');
end


end
