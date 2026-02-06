function update_fromModel(obj, src, evtData)
% function update_fromModel(obj, src, evtData)
% update widgets of the Datasets panel from obj.mibModel
% 
% This function is triggered either as a controllers.MibActiveDataset.listener to
% MibModel->DatasetsPanelUpdate event or as a method of
% controllers.MibActiveDataset.datasetsPanelUpdate() to update widgets of the Datasets
% panel (obj.view.handles.panels.activeDataset / obj.handles)
%
% Parameters:
% src: handle to MibModel when called as a listener, from controllers.MibActiveDataset it is not provided
% evtData: event data information, when called as a listener, from controllers.MibActiveDataset it is not provided
%
%|
% @b Examples:
% @code
% obj.update_fromModel(); // call from controllers.MibActiveDataset, update widgets of the Datasets panel using MibModel values
% @endcode
% @code
% notify(obj, 'DatasetsPanelUpdate'); // call from MibModel, update widgets of the Datasets panel using MibModel values
% @endcode

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
if numel(obj.view.handles.figureDocs) < noSets 
    % Add a new figure-based document
    figOptions.Title = sprintf('%s', Sets.names{end});
    figOptions.DocumentGroupTag = obj.view.handles.imageViewDocGroup.Tag;
    obj.view.handles.figureDocs{noSets} = matlab.ui.internal.FigureDocument(figOptions);
    obj.view.handles.figureDocs{noSets}.EnableDockControls = true;
    obj.view.handles.figureDocs{noSets}.Closable = false;
    % obj.view.handles.figureDocs{noSets}.CanCloseFcn

    obj.view.handles.figureDocs{noSets}.Figure.AutoResizeChildren = 'off';
    obj.view.handles.imView{noSets} = views.components.ImageView('Parent', obj.view.handles.figureDocs{noSets}.Figure, ...
        'Units', 'normalized', 'Position', [0 0 1 1]);
    
    % get aliases
    c = obj.mibController;
    imViewHandles = obj.view.handles.imView{noSets}.handles;
    
    % hold axes once here
    % Note! requires YDir = 'reverse', defined in ImageView.mlapp
    hold(imViewHandles.imViewAxes, 'on');
    
    % add callbacks
    imViewHandles.lastSlice.ButtonPushedFcn = @c.imViewPanel_Callbacks;
    imViewHandles.prevSlice.ButtonPushedFcn = @c.imViewPanel_Callbacks;
    imViewHandles.sliceNumberSlider.ValueChangingFcn = @c.imViewPanel_Callbacks;
    imViewHandles.nextSlice.ButtonPushedFcn = @c.imViewPanel_Callbacks;
    imViewHandles.firstSlice.ButtonPushedFcn = @c.imViewPanel_Callbacks;
    imViewHandles.sliceNumber.ValueChangedFcn = @c.imViewPanel_Callbacks;
    imViewHandles.frameNumber.ValueChangedFcn = @c.imViewPanel_Callbacks;
    imViewHandles.firstFrame.ButtonPushedFcn = @c.imViewPanel_Callbacks;
    imViewHandles.prevFrame.ButtonPushedFcn = @c.imViewPanel_Callbacks;
    imViewHandles.frameNumberSlider.ValueChangingFcn = @c.imViewPanel_Callbacks;
    imViewHandles.nextFrame.ButtonPushedFcn = @c.imViewPanel_Callbacks;
    imViewHandles.lastFrame.ButtonPushedFcn = @c.imViewPanel_Callbacks;

    % add mouse movement callbacks
    % add mouse movement callback
    % UIFigure identified in inside ImageView.mlapp as 
    % parentFigure = ancestor(obj.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes, 'figure');
    % obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.imViewFigure.WindowButtonMotionFcn = @(hObject, eventdata, handles)obj.mibGUI_WinMouseMotionFcn();
    
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.imViewFigure.WindowButtonMotionFcn = @(hObject, eventdata, handles)obj.view.mibGUI_WinMouseMotionFcn();

    % add component to the figure-document
    obj.view.gui.add(obj.view.handles.figureDocs{noSets});
    
    %% Configure axes properties
    imViewHandles.imViewAxes.Box = 'on';
    imViewHandles.imViewAxes.XTick = [];
    imViewHandles.imViewAxes.YTick = [];
    imViewHandles.imViewAxes.Interruptible = 'off';
    imViewHandles.imViewAxes.BusyAction = 'queue';
    imViewHandles.imViewAxes.HandleVisibility = 'callback';

    % update description of the set tab
    drawnow;
    obj.view.handles.figureDocs{selectedSet}.Description = sprintf('Buffer %d:\n%s', ...
        Sets.selectedDataset(selectedSet), ...
        obj.mibModel.I{newBufferGlobalIndex}.image.filename); 

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
    obj.view.handles.figureDocs{selectedSet}.Description = sprintf('Buffer %d:\n%s', newSelectedDatasetIndex, obj.mibModel.I{newBufferGlobalIndex}.image.filename);
end

if selectedSet ~= prevSelectedSet
    % update colors for the dataset buttons
    defaultBackgroundColor = obj.view.handles.panels.dirContents.handles.updateFileList.BackgroundColor; % default color for buttons

    for datasetId = 1:Sets.datasetsInSet
        bufferId = sprintf('buffer%d', datasetId);
        buttonHandle = obj.handles.(bufferId);

        globalIndex = datasetId + ((selectedSet-1) * Sets.datasetsInSet);
        if strcmp(obj.mibModel.I{globalIndex}.image.filename, 'none.tif')  % no dataset loaded
            buttonHandle.BackgroundColor = defaultBackgroundColor;
            buttonHandle.Tooltip = 'use RMB for a context menu with additional options';
        else
            buttonHandle.BackgroundColor = [0.6 1 0.6];
            buttonHandle.Tooltip = obj.mibModel.I{globalIndex}.image.filename;
        end
        
        % add DeveloperMode tag
        if obj.mibModel.preferences.System.DeveloperMode
            buttonHandle.Tooltip = sprintf('obj.view.handles.panels.activeDataset.handles.%s:\n%s', ...
                bufferId, buttonHandle.Tooltip);
        end
    end
end

% check for renamed set, rename the figure-document tan
if ~strcmp(Sets.names{selectedSet}, obj.view.handles.figureDocs{selectedSet}.Title)
    for setId=1:numel(obj.view.handles.figureDocs)
        obj.view.handles.figureDocs{setId}.Title = Sets.names{setId};
    end
    %obj.view.handles.figureDocs{selectedSet}.Title = Sets.names{selectedSet};
end

%% Select the Figure-Document
% select the figure-document if the set was changed
if ~isempty(obj.view.handles.imageViewDocGroup.LastSelected) && ...
        ~strcmp(obj.view.handles.imageViewDocGroup.LastSelected.title, Sets.names{selectedSet})
    % get titles for the documents
    titles = cellfun(@(x) char(x.Title), obj.view.handles.figureDocs, 'UniformOutput', false);
    documentIndex = ismember(titles, Sets.names{selectedSet});
    obj.view.handles.figureDocs{documentIndex}.Selected = true;
end

% callback for the buffer button press
obj.buffers_Callback(obj.handles.(newBufferStringId));

end