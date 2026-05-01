function datasetTypeChange_Callback(obj, hWidget, hData)
% DATASETTYPECHANGE_CALLBACK - callback for selection of entry in Datasets.datasetType dropdown to choose the type of the dataset stored.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.datasetTypeChange_Callback(hWidget, hData)
%
% in the selected buffer/container.
% Available options
% - Standard standard MIB dataset, loaded completely into memory
% - Virtual the virtual mode, when the data is loaded from disk on demand
% - BigData to work with pyramidal/chunked data formats [for future development]
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting data class
%

arguments (Input)
    obj controllers.MibActiveDataset
    hWidget matlab.ui.control.DropDown
    hData matlab.ui.eventdata.ValueChangedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibActiveDataset.datasetTypeChange_Callback: selection of "obj.handles.panels.activeDataset.handles.datasetType" -> "%s"\n',  hWidget.Value);
end

% confirm the operation
selection = uiconfirm(obj.view.gui, ...
    sprintf('You are going to switch to the %s mode\nThe current dataset will be closed!', hWidget.Value), ...
    'Switch dataset mode', 'Icon', 'warning', 'DefaultOption', 2);
if strcmp(selection, 'Cancel')
    hWidget.Value = hData.PreviousValue;
    return; 
end

initWithImage = [];
switch hWidget.Value % Get the selected dataset type from the dropdown
    case 'Standard'
        % Set the standard mode when dataset is loaded into memory
        fn = fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.png');
        initWithImage = imread(fn);
        newMode = 1;
    case 'Virtual'
        % Set the virtual mode
        newMode = 2;
        initWithImage = {fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.h5')};
    case 'BigData'
        % Placeholder for future big data handling
        newMode = 3;
end

updatedMode = obj.mibModel.I{obj.mibModel.id}.switchDatasetMode(newMode, obj.mibModel.preferences.System.EnableSelection, initWithImage);
if updatedMode~=newMode; return; end

% update obj.mibModel.Sets.datasetTypes
obj.mibModel.Sets.datasetTypes{obj.mibModel.Sets.selectedSet, obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet)} = hWidget.Value;

% new dataset and update widgets
notify(obj.mibModel, 'NewDataset');

% update the list of files
obj.mibController.cDirContents.updateFileList_Callback();
