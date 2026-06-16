function update_fromModel(obj, src, evtData)
% UPDATE_FROMMODEL - update widgets of the Datasets panel from obj.mibModel.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.update_fromModel(src, evtData)
%
% This function is triggered either as a controllers.MibActiveDataset.listener to
% MibModel->DatasetsPanelUpdate event or as a method of
% controllers.MibActiveDataset.datasetsPanelUpdate() to update widgets of the Datasets
% panel (obj.view.handles.panels.activeDataset / obj.handles)
%
% Input Arguments:
%   - **src** — handle to MibModel when called as a listener, from controllers.MibActiveDataset it is not provided
%   - **evtData** — event data information, when called as a listener, from controllers.MibActiveDataset it is not provided
%
% Usage:
%   Example 1::
%
%     obj.update_fromModel(); // call from controllers.MibActiveDataset, update widgets of the Datasets panel using MibModel values
%
%   Example 2::
%
%     notify(obj, 'DatasetsPanelUpdate'); // call from MibModel, update widgets of the Datasets panel using MibModel values
%

% arguments
%     obj controllers.MibActiveDataset
%     src models.MibModel
%     evtData event.EventData
% end

% make aliases
selectedSet = obj.mibModel.Sets.selectedSet;
Sets = obj.mibModel.Sets;

% find an index of the previously pressed button and the set
prevSelectedDatasetIndex = mod(obj.mibModel.id-1, Sets.datasetsInSet)+1; % without the correction mod(20, 10) == 0, while should be 10
% get currently selected index
newSelectedDatasetIndex = Sets.selectedDataset(selectedSet);
newBufferStringId = sprintf('buffer%d', newSelectedDatasetIndex);  % generate handle for the buffer button
newBufferGlobalIndex = newSelectedDatasetIndex + ((selectedSet-1) * Sets.datasetsInSet);

% get index of the previously selected set
prevSelectedSet = ceil(obj.mibModel.id/Sets.datasetsInSet);

% update set names and the currently selected set
obj.handles.sets.Items = Sets.names;
obj.handles.sets.Value = Sets.names(selectedSet);

%% Modify Figure-Documents

% add a new matlab.ui.internal.FigureDocument to match number of sets
noSets = numel(Sets.names); % get number of sets
% Check for addition of a new set
if numel(obj.mibController.cImageDoc) < noSets 
    % Add a new figure-based document
    obj.mibController.cImageDoc{noSets} = controllers.MibImageDocument(...
        obj.mibController, ...
        obj.view, ...
        sprintf('%s', Sets.names{end}), ...
        obj.view.handles.imageViewDocGroup.Tag, ...
        noSets, ...
        obj.mibModel);
   
    % add component to the figure-document
    obj.view.gui.add(obj.mibController.cImageDoc{noSets}.figureDoc);
    drawnow;
    % Small pause to ensure the layout engine has finished
    pause(0.5); % add small pause to allow rendering on axes
    
    % Explicitly trigger axes update for all datasets in this set with correct dimensions
    startIndex = (noSets-1)*obj.mibModel.Sets.datasetsInSet + 1;
    for i=startIndex:startIndex+obj.mibModel.Sets.datasetsInSet-1
        Options.mode = 'resize';
        Options.index = i;
        eventdata = core.ToggleEventData(Options);
        notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
    end

    % update description of the set tab
    obj.mibController.cImageDoc{noSets}.setDescription( ...
        sprintf('Buffer %d:\n%s', Sets.selectedDataset(selectedSet), obj.mibModel.I{newBufferGlobalIndex}.image.filename)); 

elseif numel(obj.mibController.cImageDoc) > noSets 
    % the set was removed
    obj.mibController.deleteImageDocument(prevSelectedSet);
end

% update the button background, when buttons in the sets are different
if newSelectedDatasetIndex ~= prevSelectedDatasetIndex
    prevBufferStringId = sprintf('buffer%d', prevSelectedDatasetIndex);
    obj.handles.(prevBufferStringId).BackgroundColor = obj.view.handles.panels.dirContents.handles.updateFileList.BackgroundColor;

    % update description of the set tab
    obj.mibController.cImageDoc{selectedSet}.setDescription( ...
        sprintf('Buffer %d:\n%s', newSelectedDatasetIndex, obj.mibModel.I{newBufferGlobalIndex}.image.filename));
end

% Always repaint all buffer buttons for the current set so that any buffer
% that just received data (e.g. crop-to a different buffer) turns green
% without requiring a set change.
defaultBackgroundColor = obj.view.handles.panels.activeDataset.handles.addSet.BackgroundColor;
for datasetId = 1:Sets.datasetsInSet
    bufferId = sprintf('buffer%d', datasetId);
    buttonHandle = obj.handles.(bufferId);

    globalIndex = datasetId + ((selectedSet-1) * Sets.datasetsInSet);
    img = obj.mibModel.I{globalIndex}.image;
    if strcmp(img.filename, 'none.tif') && img.height == 512 && img.width == 512 && img.depth == 1 && img.time == 1
        % Empty placeholder buffer — no data loaded
        buttonHandle.BackgroundColor = defaultBackgroundColor;
        buttonHandle.Tooltip = 'use RMB for a context menu with additional options';
    elseif strcmp(img.filename, 'none.tif')
        % In-memory dataset — data present but no file on disk (e.g. loaded from Examples)
        buttonHandle.BackgroundColor = [1 0.85 0.6];
        buttonHandle.Tooltip = sprintf('In-memory dataset (%dx%dx%d); use File -> Save to save', img.width, img.height, img.depth);
    else
        % File-backed dataset
        buttonHandle.BackgroundColor = [0.6 1 0.6];
        buttonHandle.Tooltip = img.filename;
    end

    % add DeveloperMode tag
    if obj.mibModel.preferences.System.DeveloperMode
        buttonHandle.Tooltip = sprintf('obj.view.handles.panels.activeDataset.handles.%s:\n%s', ...
            bufferId, buttonHandle.Tooltip);
    end
end

% check for renamed set, rename the figure-document tab
if ~strcmp(Sets.names{selectedSet}, obj.mibController.cImageDoc{selectedSet}.getTitle())
    for setId=1:numel(obj.mibController.cImageDoc)
        obj.mibController.cImageDoc{setId}.setTitle(Sets.names{setId});
    end
end

%% Select the Figure-Document
% Select the figure-document if the set was changed
if ~isempty(obj.view.handles.imageViewDocGroup.LastSelected) && ...
        ~strcmp(obj.view.handles.imageViewDocGroup.LastSelected.title, Sets.names{selectedSet})
    
    % Get titles for the documents
    titles = cellfun(@(x) x.getTitle(), obj.mibController.cImageDoc, 'UniformOutput', false);
    setOfDatasetsIndex = ismember(titles, Sets.names{selectedSet});
    obj.mibController.cImageDoc{setOfDatasetsIndex}.selectDocument();
end

% callback for the buffer button press
obj.buffers_Callback(obj.handles.(newBufferStringId));

end
