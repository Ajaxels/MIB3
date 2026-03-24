function listener_newDataset(obj, src, evtData)
% function listener_newDataset(obj, src, evtData)
% Update obj.I (MibDataset) by resizing it to fit on the screen
% executed upon catch of MibModel->"NewDataset" event
%
% Parameters:
% src: handle to MibModel
% evtData: event data, an instance of core.ToggleEventData class with the following fields:
% .Parameters field containing a structure with the
%    .evtData.Parameters.index -> [@b optional] index of obj.I to update, when @em [] updates the currently selected dataset
% .Source -> handle to MibModel
% .EventName -> string with the event name that triggered the callback
% see example in MibModel.datasetsSetsOps-> 'Add set'

%| 
% @b Examples:
% @code
% // update the current dataset using the "resize" mode
% notify(obj.mibModel, 'NewDataset');
% @endcode 
%
% @code
% Options.index = 8;
% eventdata = core.ToggleEventData(Options);
% // update dataset 8 using the "resize" mode
% notify(obj.mibModel, 'NewDataset', eventdata);
% @endcode 

% if Parameters was not initialized
if ~isprop(evtData, 'Parameters')
    Parameters = struct; 
else
    Parameters = evtData.Parameters;
end

% update the missing fields
if ~isfield(Parameters, 'index')
    Parameters.index = obj.mibModel.id;
    % fit the new dataset to screen — drawnow ensures the axes panel has a
    % valid InnerPosition before listener_updateDatasetAxes reads axSize
    drawnow limitrate;
    % In split-panel mode, drawnow processes queued AppContainer
    % PropertyChanged events, which can trigger listener_appStateChanged
    % → setsOps_Callbacks → datasetsSetsOps and corrupt Sets.selectedSet
    % and mibModel.id.  Restore them to the intended dataset if changed.
    % Do NOT fire DatasetsPanelUpdate here — it triggers ShowImage via
    % buffers_Callback before UpdateDatasetAxes has initialized the axes,
    % causing an Ishown index error.  Restore model state only; the
    % DatasetsPanelUpdate is deferred until after UpdateDatasetAxes below.
    intendedSet = ceil(Parameters.index / obj.mibModel.Sets.datasetsInSet);
    needsPanelUpdate = false;
    if obj.mibModel.Sets.selectedSet ~= intendedSet
        obj.mibModel.Sets.selectedSet = intendedSet;
        obj.mibModel.id = Parameters.index;
        needsPanelUpdate = true;
    elseif obj.mibModel.id ~= Parameters.index
        obj.mibModel.id = Parameters.index;
    end
    fitOpt = Parameters;
    fitOpt.mode = 'fitToScreen';
    eventdata = core.ToggleEventData(fitOpt);
    notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
    % Now that axes are initialized, sync the Datasets panel if needed
    if needsPanelUpdate
        notify(obj.mibModel, 'DatasetsPanelUpdate');
    end
else  % use provided index of the dataset
    % resize the dataset with the index to fit the screen
    eventdata = core.ToggleEventData(Parameters);
    notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
end

% update BioFormatsMemoizer directory
obj.mibModel.I{Parameters.index}.bioFormatsMemoizerMemoDir = obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir;

% uncheck the linked views state
currentButtonHandle = sprintf('buffer%i', mod(Parameters.index, obj.mibModel.Sets.datasetsInSet)); % handle of the current dataset button
if obj.cActiveDataset.handles.(currentButtonHandle).UIContextMenu.Children(3).Text(1) == '[' % check for "[Linked ..."
    % exampleStr = '[Linked: 12 <-> 15] press to unlink';
    % get ids of the linked buttons
    ids = sscanf(obj.cActiveDataset.handles.(currentButtonHandle).UIContextMenu.Children(3).Text, '[Linked: %d <-> %d]');
    secondButtonHandle = sprintf('buffer%i', ids(2));
    % unlink the buttons
    obj.cActiveDataset.handles.(currentButtonHandle).UIContextMenu.Children(3).Text = 'Link view with... [Unlinked]';
    obj.cActiveDataset.handles.(secondButtonHandle).UIContextMenu.Children(3).Text = 'Link view with... [Unlinked]';
end

% update widgets of the MIB view
obj.updateGuiWidgets();

% clear undo history
if strcmp(evtData.EventName, 'NewDataset'); obj.mibModel.Backup.clearContents(); end

% show the new image
obj.showImage();

end