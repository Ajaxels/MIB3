function listenerUpdateFileList(obj, src, evtData)
% function listenerUpdateFileList(obj, src, evtData)
% Update list of files in "obj.view.handles.panels.dirContents.handles.fileList" 
% executed upon catch of MibModel->"UpdateFileList" event
%
% Parameters:
% src: handle to MibModel
% evtData: event data, an instance of core.ToggleEventData class with the following fields:
% .Parameters field containing a structure with the
%    .evtData.Parameters.filename - update mode,
%         @li 'filename' -> [@em optional] provide a filename that should be highlighted in the filelist widget
% .Source -> handle to MibModel
% .EventName -> string with the event name that triggered the callback
% see example in MibModel.datasetsSetsOps-> 'Add set'
%
% Return values:
% 

%| 
% @b Examples:
% @code 
% // call from MibModel; update the list of files and highlight "filename.tif"
% Options.filename = 'filename.tif';
% eventdata = core.ToggleEventData(Options);
% notify(obj.mibModel, 'UpdateFileList', eventdata);
% @endcode 
% // call from MibModel; update the list of files
% @code
% // update the current dataset using the "resize" mode
% notify(obj.mibModel, 'UpdateFileList');
% @endcode 

% update the missing fields
if ~isprop(evtData, 'Parameters')
    selectedFilename = '';
else
    selectedFilename = evtData.Parameters.filename;
end

obj.updateFileList_Callback(selectedFilename);
end