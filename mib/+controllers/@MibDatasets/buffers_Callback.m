function buffers_Callback(obj, hWidget, hData)
% buffers_Callback(obj, hWidget, hData)
% callbacks for press obj.handles.panels.datasets.handles.buffer1 buttons, selects the dataset
% stored in a buffer defined by the pressed button
%
% Handles the following widgets:
% - obj.handles.panels.datasets.handles.bufferN, where N is number 1 to 10,
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting ButtonPushedData class

arguments (Input)
    obj controllers.MibDatasets
    hWidget matlab.ui.control.Button
    hData {mustBeButtonEventOrEmpty} = []
end

% get index of the pressed button
buttonId = str2double(hWidget.Text);

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDatasets.datasetsBuffers_Callback -> button "%d" pressed\n', buttonId);
end

% generate identifier of the buffer handle
prevBufferStringId = sprintf('buffer%d', obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet));
newBufferStringId = sprintf('buffer%d', buttonId);

obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet) = buttonId; % update index of the dataset selected in the current set
obj.mibModel.id = buttonId + (obj.mibModel.Sets.selectedSet-1)*obj.mibModel.Sets.datasetsInSet; % update the selected dataset in the global index

% update the background color for the selected buffer
if ~strcmp(prevBufferStringId, newBufferStringId)
    obj.view.handles.panels.datasets.handles.(prevBufferStringId).BackgroundColor = obj.view.handles.panels.dirContents.handles.updateFileList.BackgroundColor;

    % update description of the set tab
    obj.view.handles.figureDocs{obj.mibModel.Sets.selectedSet}.Description = sprintf('Buffer %d', buttonId);

end
obj.view.handles.panels.datasets.handles.(newBufferStringId).BackgroundColor = [0 1 0];

% update Dataset Type dropdown in the Datasets panel
obj.view.handles.panels.datasets.handles.datasetType.Value = obj.mibModel.Sets.datasetTypes{obj.mibModel.Sets.selectedSet, obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet)};

notify(obj.mibModel, 'RenderImage');

end

% Local function that performs the validation
function mustBeButtonEventOrEmpty(a)
% This function allows the input 'a' to be empty OR a specific class
if ~isempty(a) && ~isa(a, 'matlab.ui.eventdata.ButtonPushedData')
    error('Input must be a ButtonPushedData object or empty');
end
end