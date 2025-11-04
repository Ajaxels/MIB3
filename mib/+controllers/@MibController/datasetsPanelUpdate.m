function datasetsPanelUpdate(obj, src, evtData)
% function datasetsPanelUpdate(obj, src, evtData)
% update widgets of the Datasets panel
% 
% This function is triggered either as a MibController.listener to
% MibModel->DatasetsPanelUpdate event or as a method of
% MibController.datasetsPanelUpdate() to update widgets of the Datasets
% panel (obj.view.handles.panels.datasets / obj.view.handles.panels.datasets.handles)
%
% Parameters:
% src: handle to MibModel when called as a listener, from MibController it is not provided
% evtData: event data information, when called as a listener, from MibController it is not provided
%
%|
% @b Examples:
% @code
% obj.datasetsPanelUpdate(); // call from MibController, update widgets of the Datasets panel using MibModel values
% @endcode
% @code
% notify(obj, 'DatasetsPanelUpdate'); // call from MibModel, update widgets of the Datasets panel using MibModel values
% @endcode

% arguments
%     obj controllers.MibController
%     src models.MibModel
%     evtData event.EventData
% end

% find an index of the previously pressed button and the set
prevSelectedDatasetIndex = mod(obj.mibModel.id-1, obj.mibModel.Sets.datasetsInSet)+1; % without the correction mod(20, 10) == 0, while should be 10
% get currently selected index
newSelectedDatasetIndex = obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet);

% update set names and the currently selected set
obj.view.handles.panels.datasets.handles.sets.Items = obj.mibModel.Sets.names;
obj.view.handles.panels.datasets.handles.sets.Value = obj.mibModel.Sets.names(obj.mibModel.Sets.selectedSet);

% update the button background, when buttons in the sets are different
if newSelectedDatasetIndex ~= prevSelectedDatasetIndex
    prevBufferStringId = sprintf('buffer%d', prevSelectedDatasetIndex);
    obj.view.handles.panels.datasets.handles.(prevBufferStringId).BackgroundColor = obj.view.handles.panels.dirContents.handles.updateFileList.BackgroundColor;
end

% callback for the buffer button press
newBufferStringId = sprintf('buffer%d', newSelectedDatasetIndex);
obj.datasetsBuffers_Callback(obj.view.handles.panels.datasets.handles.(newBufferStringId));
end