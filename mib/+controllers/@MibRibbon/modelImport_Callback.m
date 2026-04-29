function modelImport_Callback(obj, hWidget, hData)
% MODELIMPORT_CALLBACK - callback on press of buttons in the Import section of the Model ribbon.
%
% Syntax:
%   function modelImport_Callback(obj, hWidget, hData)
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
    fprintf('controllers.MibRibbon.modelImport_Callback: Model ribbon->Import -> %s\n', mode);
end

switch mode
    case sprintf('New\nmodel')      % obj.handles.ribbonModel.new
        obj.mibModel.createModel();
    case sprintf('Load\nmodel')     % obj.handles.ribbonModel.load
        obj.mibModel.loadModel();
    case {'Import', 'Import model from MATLAB'}   % obj.handles.ribbonModel.import
        obj.mibModel.importDataset('model');
    case 'Import model from another MIB dataset'    % obj.handles.ribbonModel.importFromMIB
        obj.mibModel.importDatasetFromMib('model');
end

end
