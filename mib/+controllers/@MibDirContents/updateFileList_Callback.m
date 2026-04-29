function updateFileList_Callback(obj, selectedFilename)
% UPDATEFILELIST_CALLBACK - callback for click on the "obj.view.handles.panels.dirContents.handles.updateFileList" button to update.
%
% Syntax:
%   function updateFileList_Callback(obj, selectedFilename)
%
% the list of files shown in "obj.view.handles.panels.dirContents.handles.fileList"
% using filters specified in "obj.view.handles.panels.dirContents.handles.fileFilters"
%
% Input Arguments:
%   - **selectedFilename** — *(optional)* char with the selected filename to highlight
%

% arguments (Input)
%     obj controllers.MibDirContents
%     hWidget matlab.ui.control.Button = obj.view.handles.panels.dirContents.handles.updateFileList
%     hData matlab.ui.eventdata.ButtonPushedData = []
%     selectedFilename char = ''
% end

if nargin < 2; selectedFilename = ''; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDirContents.updateFileList_Callback: clicked on: "obj.view.handles.panels.dirContents.handles.updateFileList"\n');
end

selectedExtention = obj.view.handles.panels.dirContents.handles.fileFilters.Value;
currPath = obj.mibModel.currentDirectory;

if currPath(end) == ':'   % change from c: to c:\, because somehow dir('c:') gives wrong result
    currPath = [currPath '\'];
end

fileList = dir(currPath); % get list of files and folders
fnames = {fileList.name};

if isempty(fnames)
    % fix of a rare case, when dir returns an empty structure
    fnames = {'[.]', '[..]'};
else
    dirs = fnames([fileList.isdir]);  % generate list of directories
    fileList = fnames(~[fileList.isdir]);     % generate structure with files
    [~, ~, fileList_ext] = cellfun(@fileparts, fileList, 'UniformOutput', false);   % get extensions

    if strcmp(selectedExtention, 'all known')
        % get the list of available extensions
        extensions = strjoin(obj.view.handles.panels.dirContents.handles.fileFilters.Items(2:end)','|');
        % filter the list of files to keep only those files that have
        % extensions listed in "extensions"
        files = fileList(~cellfun(@isempty, regexpi(fileList_ext, extensions)))';
    else
        files = fileList(~cellfun(@isempty, regexpi(fileList_ext, selectedExtention)))';
    end
    fnames = files;
    %fnames = sort(files);

    if ~isempty(dirs)
        % add square brackets to indicate directory
        dirs = strcat(repmat({'['}, 1, length(dirs)), dirs, repmat({']'}, 1, length(dirs)));
        % combine directories and file names into a single list
        fnames = {dirs{:}, fnames{:}}; %#ok<CCAT>
    end
end

% update the list of files
obj.view.handles.panels.dirContents.handles.fileList.Items = fnames;
if isempty(selectedFilename)
    % highlight the first entry
    obj.view.handles.panels.dirContents.handles.fileList.Value = fnames{1};
else
    % highlight selected file if it is present
    if ismember(selectedFilename, fnames)
        obj.view.handles.panels.dirContents.handles.fileList.Value = selectedFilename;
        % Scroll listbox so that this item is visible
        scroll(obj.view.handles.panels.dirContents.handles.fileList, selectedFilename);
    else
        obj.view.handles.panels.dirContents.handles.fileList.Value = fnames{1};
    end
end

%obj.mibView.handles.mibPathEdit.String = mypath;
%focus(obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.figureDoc.Figure); % remove focus from hObject
end
