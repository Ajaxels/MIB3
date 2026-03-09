function listenerNewDataset(obj, src, evtData)
% function listenerNewDataset(obj, src, evtData)
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
    % valid InnerPosition before listenerUpdateDatasetAxes reads axSize
    drawnow limitrate;
    fitOpt = Parameters;
    fitOpt.mode = 'fitToScreen';
    eventdata = core.ToggleEventData(fitOpt);
    notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
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
if strcmp(evtData.EventName, 'NewDataset'); obj.mibModel.Undo.clearContents(); end

% show the new image
obj.showImage();

end