function modelExport_Callback(obj, hWidget, hData)
% function modelExport_Callback(obj, hWidget, hData)
% callback on press of buttons in the Export section of the Model ribbon
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
    fprintf('controllers.MibRibbon.modelExport_Callback: Model ribbon->Import -> %s\n', mode);
end

switch mode
    case {'Export', 'Export model to MATLAB'}    % obj.handles.ribbonModel.export or obj.handles.ribbonModel.exportToMatlab
    case 'Export model to Imaris as volume'      % obj.handles.ribbonModel.exportToImaris
    case 'Save'                                  % obj.handles.ribbonModel.save — save using existing filename
        obj.mibModel.save('labels');

    case sprintf('Save\nmodel as...')            % obj.handles.ribbonModel.saveAs — save with dialog
        obj.mibModel.save('labels', []);
end

end