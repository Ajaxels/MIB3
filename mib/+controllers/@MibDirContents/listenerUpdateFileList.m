function listenerUpdateFileList(obj, src, evtData)
% LISTENERUPDATEFILELIST - Listener callback to refresh the file list in the Directory Contents panel.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listenerUpdateFileList(src, evtData)
%
% Updates the file list widget (``obj.handles.fileList``) when the MibModel ``UpdateFileList`` event
% is triggered. Optionally highlights a specific filename in the list.
%
% Input Arguments:
%   - **src** — [models.MibModel] model object that triggered the event
%   - **evtData** — [core.ToggleEventData] event data with optional parameters:
%
%     - ``.Parameters.filename`` — *(optional)* [char] filename to highlight in the file list; when omitted, highlights the current dataset filename
%
% Output Arguments:
%   None
%
% **Example 1** — update file list and highlight specific file:
%
%   .. code-block:: matlab
%
%      Options.filename = 'sample_001.tif';
%      eventdata = core.ToggleEventData(Options);
%      notify(obj.mibModel, 'UpdateFileList', eventdata)
%
% **Example 2** — update file list with current dataset filename:
%
%   .. code-block:: matlab
%
%      notify(obj.mibModel, 'UpdateFileList')
%

% update the missing fields
if ~isprop(evtData, 'Parameters')
    filename = obj.mibModel.I{obj.mibModel.id}.image.filename;
    [parentDir, fname, ext] = fileparts(filename);

    % Navigate to the file's parent directory when it differs from the current one
    if ~isempty(parentDir) && isfolder(parentDir) && ...
            ~strcmp(filename, 'none.tif') && ...
            ~strcmp(obj.mibModel.currentDirectory, parentDir)
        obj.mibModel.currentDirectory = parentDir;
    end

    % Folder-based formats (zarr3, zarr, HDF5 group, …) are listed with
    % square brackets in the directory panel — match that convention.
    if isfolder(filename)
        selectedFilename = ['[' fname ext ']'];
    else
        selectedFilename = [fname ext];
    end
else
    selectedFilename = evtData.Parameters.filename;
end

obj.updateFileList_Callback(selectedFilename);
end
