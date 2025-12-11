function type_Callback(obj, hWidget, hData)
% function type_Callback(obj, hWidget, hData)
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
    obj controllers.MibActiveDataset
    hWidget matlab.ui.control.DropDown
    hData matlab.ui.eventdata.ValueChangedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibActiveDataset.type_Callbacks: selection of "obj.handles.panels.activeDataset.handles.datasetType" -> "%s"\n',  hWidget.Value);
end

% update obj.mibModel.Sets.datasetTypes
obj.mibModel.Sets.datasetTypes{obj.mibModel.Sets.selectedSet, obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet)} = hWidget.Value;

switch hWidget.Value % Get the selected dataset type from the dropdown
    case 'Std'
        % Set the standard mode when dataset is loaded into memory
    case 'Virtual'
        % Set the virtual mode
    case 'BigData'
        % Placeholder for future big data handling
end
