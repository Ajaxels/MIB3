function fileFilters_Callback(obj, hWidget, hData)
% function fileFilters_Callback(obj, hWidget, hData)
% callback for selection of a file filter in the Directory contents panel, 
% the parent widget is obj.handles.panels.dirContents.handles.fileFilters
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting ButtonPushedData class

arguments (Input)
    obj controllers.MibDirContents
    hWidget matlab.ui.control.DropDown
    hData matlab.ui.eventdata.ValueChangedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDirContents.fileFilters_Callback: selection of "obj.view.handles.panels.dirContents.handles.fileFilters" value = "%s"\n', hWidget.Value);
end

obj.mibModel.selectedFileFilter{obj.mibModel.useBioFormats+1} = obj.view.handles.panels.dirContents.handles.fileFilters.Value;
obj.updateFileList_Callback();
end
