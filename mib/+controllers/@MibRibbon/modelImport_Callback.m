function modelImport_Callback(obj, hWidget, hData)
% function modelImport_Callback(obj, hWidget, hData)
% callback on press of buttons in the Import section of the Model ribbon
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
    fprintf('controllers.MibRibbon.modelImport_Callback: Model ribbon->Import -> %s\n', mode);
end

switch mode
    case sprintf('New\nmodel')      % obj.handles.ribbonModel.new
        obj.mibModel.createModel();
    case sprintf('Load\nmodel')     % obj.handles.ribbonModel.load
        obj.mibModel.loadModel();
    case sprintf('Import\nmodel')   % obj.handles.ribbonModel.import
   
end

end