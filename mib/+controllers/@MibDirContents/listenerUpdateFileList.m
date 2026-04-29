function listenerUpdateFileList(obj, src, evtData)
% LISTENERUPDATEFILELIST - Update list of files in "obj.view.handles.panels.dirContents.handles.fileList".
%
% Syntax:
%   function listenerUpdateFileList(obj, src, evtData)
%
% executed upon catch of MibModel->"UpdateFileList" event
%
% Input Arguments:
%   - **src** — handle to MibModel
%   - **evtData** — event data, an instance of core.ToggleEventData class with the following fields:
%     .Parameters field containing a structure with the
%     .evtData.Parameters.filename - update mode,
%     - 'filename' *(optional)* provide a filename that should be highlighted in the filelist widget
%   .Source handle to MibModel
%   .EventName string with the event name that triggered the callback
%   see example in MibModel.datasetsSetsOps-> 'Add set'
%
% Output Arguments:
%
% Usage:
%   Example 1::
%
%     // call from MibModel; update the list of files and highlight "filename.tif"
%     Options.filename = 'filename.tif';
%     eventdata = core.ToggleEventData(Options);
%     notify(obj.mibModel, 'UpdateFileList', eventdata);
%
%   // call from MibModel; update the list of files
%   Example 2::
%
%     // update the list of files highlighting the current dataset
%     notify(obj.mibModel, 'UpdateFileList');
%

% update the missing fields
if ~isprop(evtData, 'Parameters')
    [~, fname, ext] = fileparts(obj.mibModel.I{obj.mibModel.id}.image.filename);
    selectedFilename = [fname, ext];
else
    selectedFilename = evtData.Parameters.filename;
end

obj.updateFileList_Callback(selectedFilename);
end
