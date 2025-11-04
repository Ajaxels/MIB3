function dirContentsFileFilters_Callback(obj, hWidget, hData)
% function dirContentsFileFilters_Callback(obj, hWidget, hData)
% callback for selection of a file filter in the Directory contents panel, 
% the parent widget is obj.handles.panels.dirContents.handles.fileFilters
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting ButtonPushedData class

arguments (Input)
    obj controllers.MibController
    hWidget matlab.ui.control.DropDown
    hData matlab.ui.eventdata.ValueChangedData
end

fprintf('Callback for obj.handles.panels.dirContents.handles.fileFilters, value = "%s"\n', hWidget.Value);
end
