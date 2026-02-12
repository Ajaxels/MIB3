function buffers_Callback(obj, hWidget, hData)
% buffers_Callback(obj, hWidget, hData)
% callbacks for press obj.handles.panels.activeDataset.handles.buffer1 buttons, selects the dataset
% stored in a buffer defined by the pressed button
%
% Handles the following widgets:
% - obj.handles.panels.activeDataset.handles.bufferN, where N is number 1 to 10,
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting ButtonPushedData class

arguments (Input)
    obj controllers.MibActiveDataset
    hWidget matlab.ui.control.Button
    hData {mustBeButtonEventOrEmpty} = []
end

% get index of the pressed button
buttonId = str2double(hWidget.Text);

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibActiveDataset.buffers_Callback -> button "%d" pressed\n', buttonId);
end

% generate identifier of the buffer handle
prevBufferStringId = sprintf('buffer%d', obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet));
prevDatasetId = obj.mibModel.id; % store the previous dataset index
newBufferStringId = sprintf('buffer%d', buttonId);

obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet) = buttonId; % update index of the dataset selected in the current set
obj.mibModel.id = buttonId + (obj.mibModel.Sets.selectedSet-1)*obj.mibModel.Sets.datasetsInSet; % update the selected dataset in the global index

% update the background color for the selected buffer
if ~strcmp(prevBufferStringId, newBufferStringId)
    if strcmp(obj.mibModel.I{prevDatasetId}.image.filename, 'none.tif')  % no dataset loaded
        obj.view.handles.panels.activeDataset.handles.(prevBufferStringId).BackgroundColor = obj.view.handles.panels.dirContents.handles.updateFileList.BackgroundColor;
    else
        obj.view.handles.panels.activeDataset.handles.(prevBufferStringId).BackgroundColor = [0.6 1 0.6];
    end

    % update description of the set tab
    obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.setDescription(...
        sprintf('Buffer %d:\n%s', buttonId, obj.mibModel.I{obj.mibModel.id}.image.filename));
end
obj.view.handles.panels.activeDataset.handles.(newBufferStringId).BackgroundColor = [0 1 0];

% update Dataset Type dropdown in the Datasets panel
obj.view.handles.panels.activeDataset.handles.datasetType.Value = obj.mibModel.Sets.datasetTypes{obj.mibModel.Sets.selectedSet, obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet)};

notify(obj.mibModel, 'ShowImage');

end

% Local function that performs the validation
function mustBeButtonEventOrEmpty(a)
% This function allows the input 'a' to be empty OR a specific class
if ~isempty(a) && ~isa(a, 'matlab.ui.eventdata.ButtonPushedData')
    error('Input must be a ButtonPushedData object or empty');
end
end