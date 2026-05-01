function modelExport_Callback(obj, hWidget, hData)
% MODELEXPORT_CALLBACK - callback on press of buttons in the Export section of the Model ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.modelExport_Callback(hWidget, hData)
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
    fprintf('controllers.MibRibbon.modelExport_Callback: Model ribbon->Import -> %s\n', mode);
end

switch mode
    case {'Export', 'Export model to MATLAB'}    % obj.handles.ribbonModel.export or obj.handles.ribbonModel.exportToMatlab
        obj.mibModel.exportDataset('model');

    case 'Export model to Imaris as volume'      % obj.handles.ribbonModel.exportToImaris
        obj.mibModel.exportDatasetToImaris('model');

    case 'Export model to another MIB dataset'   % obj.handles.ribbonModel.exportToMIB
        obj.mibModel.exportDatasetToMib('model');

    case sprintf('Save\nmodel')                                  % obj.handles.ribbonModel.save — save using existing filenam
        obj.mibModel.saveLabels();

    case sprintf('Save\nmodel as...')            % obj.handles.ribbonModel.saveAs — save with dialog
        obj.mibModel.saveLabels([]);
end

end
