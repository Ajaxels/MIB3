function listener_newDataset(obj, src, evtData)
% LISTENER_NEWDATASET - Update obj.I (MibDataset) by resizing it to fit on the screen.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listener_newDataset(src, evtData)
%
% executed upon catch of MibModel->"NewDataset" event
%
% Input Arguments:
%   - **src** — handle to MibModel
%   - **evtData** — event data, an instance of ``core.ToggleEventData``; ``evtData.Parameters``
%     is a structure with the following fields:
%
%     - ``.index`` — *(optional)* index of obj.I to update; ``[]`` updates the currently selected dataset
%
% Output Arguments:
%   (none)
%
% **Example 1** — update the current dataset (resize to fit screen):
%
%   .. code-block:: matlab
%
%      notify(obj.mibModel, 'NewDataset');
%
% **Example 2** — update dataset 8 specifically:
%
%   .. code-block:: matlab
%
%      Options.index = 8;
%      eventdata = core.ToggleEventData(Options);
%      notify(obj.mibModel, 'NewDataset', eventdata);
%

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
    % Fit the destination buffer to screen so the user sees it correctly when
    % switching to it. The no-index branch already uses fitToScreen; mirror that.
    Parameters.mode = 'fitToScreen';
    eventdata = core.ToggleEventData(Parameters);
    notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
    % Refresh the Datasets-panel button colors (e.g. turn the destination
    % buffer button green). update_fromModel is safe to call here because
    % the active buffer (mibModel.id) is unchanged — it just repaints buttons.
    notify(obj.mibModel, 'DatasetsPanelUpdate');
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
