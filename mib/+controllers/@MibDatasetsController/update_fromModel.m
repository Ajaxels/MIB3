function update_fromModel(obj, src, evtData)
% function update_fromModel(obj, src, evtData)
% update widgets of the Datasets panel from obj.mibModel
% 
% This function is triggered either as a MibDatasetsController.listener to
% MibModel->DatasetsPanelUpdate event or as a method of
% MibDatasetsController.datasetsPanelUpdate() to update widgets of the Datasets
% panel (obj.view.handles.panels.datasets / obj.handles)
%
% Parameters:
% src: handle to MibModel when called as a listener, from MibDatasetsController it is not provided
% evtData: event data information, when called as a listener, from MibDatasetsController it is not provided
%
%|
% @b Examples:
% @code
% obj.update_fromModel(); // call from MibDatasetsController, update widgets of the Datasets panel using MibModel values
% @endcode
% @code
% notify(obj, 'DatasetsPanelUpdate'); // call from MibModel, update widgets of the Datasets panel using MibModel values
% @endcode

% arguments
%     obj controllers.MibDatasetsController
%     src models.MibModel
%     evtData event.EventData
% end

% find an index of the previously pressed button and the set
prevSelectedDatasetIndex = mod(obj.mibModel.id-1, obj.mibModel.Sets.datasetsInSet)+1; % without the correction mod(20, 10) == 0, while should be 10
% get currently selected index
newSelectedDatasetIndex = obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet);
% get index of the previously selected set
prevSelectedSet = ceil(obj.mibModel.id/obj.mibModel.Sets.datasetsInSet);

% update set names and the currently selected set
obj.handles.sets.Items = obj.mibModel.Sets.names;
obj.handles.sets.Value = obj.mibModel.Sets.names(obj.mibModel.Sets.selectedSet);

%% Modify Figure-Documents

% add a new matlab.ui.internal.FigureDocument to match number of sets
noSets = numel(obj.mibModel.Sets.names); % get number of sets
% Check for addition of a new set
if numel(obj.view.handles.figureDocs) < noSets 
    % Add a new figure-based document
    figOptions.Title = sprintf('%s', obj.mibModel.Sets.names{end});
    figOptions.DocumentGroupTag = obj.view.handles.imageViewDocGroup.Tag;
    obj.view.handles.figureDocs{noSets} = matlab.ui.internal.FigureDocument(figOptions);
    obj.view.handles.figureDocs{noSets}.EnableDockControls = true;
    obj.view.handles.figureDocs{noSets}.Closable = false;
    % obj.view.handles.figureDocs{noSets}.CanCloseFcn

    obj.view.handles.figureDocs{noSets}.Figure.AutoResizeChildren = 'off';
    obj.view.handles.imView{noSets} = views.components.ImageView('Parent', obj.view.handles.figureDocs{noSets}.Figure, ...
        'Units', 'normalized', 'Position', [0 0 1 1]);
    
    % add callbacks
    obj.view.handles.imView{noSets}.handles.lastSlice.ButtonPushedFcn = @(src, event)obj.imViewPanel_Callbacks(src, event);
    obj.view.handles.imView{noSets}.handles.sliceNumberSlider.ValueChangingFcn = @(src, event)obj.imViewPanel_Callbacks(src, event);
    obj.view.handles.imView{noSets}.handles.firstSlice.ButtonPushedFcn = @(src, event)obj.imViewPanel_Callbacks(src, event);
    obj.view.handles.imView{noSets}.handles.sliceNumber.ValueChangedFcn = @(src, event)obj.imViewPanel_Callbacks(src, event);
    obj.view.handles.imView{noSets}.handles.frameNumber.ValueChangedFcn = @(src, event)obj.imViewPanel_Callbacks(src, event);
    obj.view.handles.imView{noSets}.handles.firstFrame.ButtonPushedFcn = @(src, event)obj.imViewPanel_Callbacks(src, event);
    obj.view.handles.imView{noSets}.handles.frameNumberSlider.ValueChangingFcn = @(src, event)obj.imViewPanel_Callbacks(src, event);
    obj.view.handles.imView{noSets}.handles.lastFrame.ButtonPushedFcn = @(src, event)obj.imViewPanel_Callbacks(src, event);

    % add component to the figure-document
    obj.view.gui.add(obj.view.handles.figureDocs{noSets});
    
    % update description of the set tab
    drawnow;
    obj.view.handles.figureDocs{obj.mibModel.Sets.selectedSet}.Description = sprintf('Buffer %d', obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet)); 
elseif numel(obj.view.handles.figureDocs) > noSets 
    % the set was removed
    obj.view.handles.imView(prevSelectedSet) = [];
    delete(obj.view.handles.figureDocs{prevSelectedSet});
    obj.view.handles.figureDocs(prevSelectedSet) = [];
end

% update the button background, when buttons in the sets are different
if newSelectedDatasetIndex ~= prevSelectedDatasetIndex
    prevBufferStringId = sprintf('buffer%d', prevSelectedDatasetIndex);
    obj.handles.(prevBufferStringId).BackgroundColor = obj.view.handles.panels.dirContents.handles.updateFileList.BackgroundColor;

    % update description of the set tab
    obj.view.handles.figureDocs{obj.mibModel.Sets.selectedSet}.Description = sprintf('Buffer %d', newSelectedDatasetIndex);
end

% check for renamed set, rename the figure-document tan
if ~strcmp(obj.mibModel.Sets.names{obj.mibModel.Sets.selectedSet}, obj.view.handles.figureDocs{obj.mibModel.Sets.selectedSet}.Title)
    obj.view.handles.figureDocs{obj.mibModel.Sets.selectedSet}.Title = obj.mibModel.Sets.names{obj.mibModel.Sets.selectedSet};
end

%% Select the Figure-Document
% select the figure-document if the set was changed
if ~isempty(obj.view.handles.imageViewDocGroup.LastSelected) && ...
        ~strcmp(obj.view.handles.imageViewDocGroup.LastSelected.title, obj.mibModel.Sets.names{obj.mibModel.Sets.selectedSet})
    % get titles for the documents
    titles = cellfun(@(x) char(x.Title), obj.view.handles.figureDocs, 'UniformOutput', false);
    documentIndex = ismember(titles, obj.mibModel.Sets.names{obj.mibModel.Sets.selectedSet});
    obj.view.handles.figureDocs{documentIndex}.Selected = true;
end

% callback for the buffer button press
newBufferStringId = sprintf('buffer%d', newSelectedDatasetIndex);
obj.buffers_Callback(obj.handles.(newBufferStringId));

end