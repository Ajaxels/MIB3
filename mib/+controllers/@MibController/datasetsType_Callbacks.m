function datasetsType_Callbacks(obj, hWidget, hData)
% function datasetsType_Callbacks(obj, hWidget, hData)
% callback for selection of entry in Datasets.datasetType dropdown to choose the type of the dataset stored 
% in the selected buffer/container.
% Available options
% - Std -> standard MIB dataset, loaded completely into memory
% - Virtual -> the virtual mode, when the data is loaded from disk on demand
% - BigData -> to work with pyramidal/chunked data formats [for future development]
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibController
    hWidget matlab.ui.control.DropDown
    hData matlab.ui.eventdata.ValueChangedData
end

switch hWidget.Value % Get the selected dataset type from the dropdown
    case 'Std'
        % Set the standard mode when dataset is loaded into memory
        fprintf('Callback for selection in obj.handles.panels.datasets.handles.datasetType -> %s\n', hWidget.Value);
    case 'Virtual'
        % Set the virtual mode
        fprintf('Callback for selection in obj.handles.panels.datasets.handles.datasetType -> %s\n', hWidget.Value);
    case 'BigData'
        % Placeholder for future big data handling
        fprintf('Callback for selection in obj.handles.panels.datasets.handles.datasetType -> %s\n', hWidget.Value);
end
