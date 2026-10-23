function fileList_ContextMenu(obj, menuEntry, selectedData)
% FILELIST_CONTEXTMENU - Callback for context menu operations on the file list.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.fileList_ContextMenu(menuEntry, selectedData)
%
% Handles context menu operations on files in the file list (``obj.handles.fileList``).
% Supports file loading, insertion, color channel operations, and file management (rename, delete, properties).
%
% Input Arguments:
%   - **menuEntry** - [matlab.ui.container.Menu] handle to the pressed context menu entry; menu operations are identified via ``menuEntry.Tag``
%   - **selectedData** - [matlab.ui.eventdata.MenuSelectedData] event data containing the source file list object (``selectedData.ContextObject``)
%
% Output Arguments:
%   None
%
% **Supported menu operations (menuEntry.Tag):**
%   - ``'fileListContextCombine'`` - combine selected files and open as a single dataset
%   - ``'fileListContextLoadPart'`` - load a portion (slice range) of a file
%   - ``'fileListContextLoadNth'`` - load every N-th file and combine into one dataset
%   - ``'fileListContextInsert'`` - insert selected files into the current dataset
%   - ``'fileListContextColorCombine'`` - combine selected files as separate color channels
%   - ``'fileListContextColorAdd'`` - add selected file(s) as a new color channel to current dataset
%   - ``'fileListContextColorAddNth'`` - add every N-th file as a new color channel
%   - ``'fileListContextRename'`` - rename the selected file
%   - ``'fileListContextDelete'`` - delete the selected file
%   - ``'fileListContextProps'`` - display file properties dialog
%

arguments (Input)
    obj controllers.MibDirContents
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('Pressed: controllers.MibDirContents.fileList_ContextMenu -> %s\n', menuEntry.Tag);
end

% override selected files since Ctrl+A is not detected
obj.mibModel.selectedFiles = obj.mibController.cDirContents.handles.fileList.Value;
obj.mibModel.selectedFiles(ismember(obj.mibModel.selectedFiles, {'[.]','[..]'})) = []; % remove [.] and [..]

switch menuEntry.Tag
    case 'fileListContextCombine'
        obj.mibModel.loadImages('Combine datasets');
    case 'fileListContextLoadPart'
        obj.mibModel.loadImages('Load part of dataset');
    case 'fileListContextLoadNth'
        obj.mibModel.loadImages('Load each N-th dataset');
    case 'fileListContextInsert'
        obj.mibModel.loadImages('Insert into open dataset');
    case 'fileListContextColorCombine'
        obj.mibModel.loadImages('Combine files as color channels');
    case 'fileListContextColorAdd'
        obj.mibModel.loadImages('Add as new color channel');
    case 'fileListContextColorAddNth'
        obj.mibModel.loadImages('Add each N-th dataset as new color channel');
    case 'fileListContextRename'
        if numel(obj.mibModel.selectedFiles) ~= 1
            header = 'Please select a single file!';
            dlgOpts.MsgBoxOnly = true;
            dlgOpts.WindowStyle = 'normal';
            dlgOpts.WindowHeight = 150';
            dlgOpts.Icon = 'puffin_warning';
            utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), header, {}, {}, 'Rename file', dlgOpts);
            return;
        end
        % folders are listed as [name] (see updateFileList_Callback); the
        % brackets belong to the list, not to the folder
        selectedName = obj.mibModel.selectedFiles{1};
        isFolder = numel(selectedName) > 2 && selectedName(1) == '[' && selectedName(end) == ']';
        if isFolder; selectedName = selectedName(2:end-1); end
        dlgOpts.mibPath = obj.mibModel.mibPath;
        answer = utils.dlgs.inputSingleDlg(obj.mibModel.getProgressBarParent(), 'Please enter new name', selectedName, 'Rename', dlgOpts);
        if isempty(answer); return; end
        answer = strtrim(answer);
        if isFolder && numel(answer) > 2 && answer(1) == '[' && answer(end) == ']'; answer = answer(2:end-1); end
        if isempty(answer) || strcmp(answer, selectedName); return; end
        sourcePath = fullfile(obj.mibModel.currentDirectory, selectedName);
        targetPath = fullfile(obj.mibModel.currentDirectory, answer);
        inUseBy = localDatasetReadingFrom(obj.mibModel, sourcePath);
        if ~isempty(inUseBy)
            % a Virtual or BigData dataset reads its image, or its model store,
            % from here on demand; after a rename every read and write would go
            % to a path that no longer exists
            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                sprintf(['"%s" is in use by dataset %d, which reads %s from it.\n\n' ...
                'Close that dataset, or open another one in its place, and rename then.'], ...
                selectedName, inUseBy.id, inUseBy.what), 'Rename');
            return;
        end
        if isfile(targetPath) || isfolder(targetPath)
            % movefile would replace a file, and move a folder INTO an existing one
            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                sprintf('"%s" already exists in this folder. Choose another name.', answer), 'Rename');
            return;
        end
        % A BigData model store keeps side files next to its folder, found by the
        % store's name: without its level map a reopened store treats every level
        % as up to date and shows stale detail where edits were made zoomed out
        sideFiles = {};
        if isFolder
            sideFiles = {core.MibBigDataLabels.levelMapPathFor(sourcePath), core.MibBigDataLabels.levelMapPathFor(targetPath); ...
                core.MibBigDataLabels.instanceIndexPathFor(sourcePath), core.MibBigDataLabels.instanceIndexPathFor(targetPath)};
            sideFiles = sideFiles(isfile(sideFiles(:, 1)), :);
            if any(isfile(sideFiles(:, 2)))
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                    sprintf('The model store side file "%s" already exists. Choose another name.', sideFiles{find(isfile(sideFiles(:, 2)), 1), 2}), 'Rename');
                return;
            end
        end
        try
            movefile(sourcePath, targetPath);
            for k = 1:size(sideFiles, 1)
                movefile(sideFiles{k, 1}, sideFiles{k, 2});
            end
        catch err
            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                sprintf('%s\n\nThe file or folder is probably open in another application, or MATLAB lacks permission.', err.message), ...
                'Rename failed');
            return;
        end
        if isFolder
            obj.updateFileList_Callback(['[' answer ']']);
        else
            obj.updateFileList_Callback(answer);
        end

    case 'fileListContextDelete'
        filenames = cellfun(@(f) fullfile(obj.mibModel.currentDirectory, f), obj.mibModel.selectedFiles, 'UniformOutput', false);
        if numel(filenames) == 1 %#ok<ISCL>
            msg = sprintf('You are going to delete\n%s', filenames{1});
        else
            msg = sprintf('You are going to delete\n%d files', numel(filenames));
        end
        selection = uiconfirm(obj.mibModel.mibGUI, msg, 'Delete file(s)?', ...
            'Options', {'Delete', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
        if strcmp(selection, 'Cancel'); return; end
        
        % convert warning into an error
        s = warning('error', 'MATLAB:DELETE:Permission');
        cleanupObj = onCleanup(@() warning(s));

        try
            for i = 1:numel(filenames)
                delete(filenames{i});
            end
        catch err
            utils.dlgs.showErrorDialog(obj.view.gui, sprintf('%s:\n%s\n\nThe file is probably open in another application, or MATLAB lacks permission', err.message, filenames{i}), ...
                'Delete failed', 'Cannot delete file!', '');
        end
        obj.updateFileList_Callback();

    case 'fileListContextProps'
        if isempty(obj.mibModel.selectedFiles); return; end
        fileInfo = dir(fullfile(obj.mibModel.currentDirectory, obj.mibModel.selectedFiles{1}));
        header = sprintf('Filename: %s\nDate: %s\nSize: %.3f KB', fileInfo.name, fileInfo.date, fileInfo.bytes/1000);
        dlgOpts.HeaderLines = 4;
        dlgOpts.MsgBoxOnly = true;
        dlgOpts.WindowHeight = 150';
        dlgOpts.WindowWidth = 400';
        dlgOpts.WindowStyle = 'normal';
        dlgOpts.Icon = 'puffin_info';
        dlgOpts.IconWidth = 96;
        utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), header, {}, {}, 'File info', dlgOpts);

end

end

% =====================================================================
function inUseBy = localDatasetReadingFrom(mibModel, sourcePath)
% The first open dataset that reads from sourcePath on demand, or [] when none.
%
% Only on-demand readers count: a Standard dataset holds its image in memory, so
% renaming the file it came from changes nothing for it. What is checked:
%   - the image files of a Virtual or BigData dataset (image.Virtual.filenames,
%     plus image.filename)
%   - the model store of a disk-backed model (labels.modelStorePath)
% sourcePath matches when it is one of those paths, or a folder holding one -
% renaming the folder a store sits in breaks it just the same.
%
% Output Arguments:
%   - **inUseBy** - struct with ``.id`` (dataset index) and ``.what`` (text for the
%     message), or ``[]``
inUseBy = [];
normalise = @(p) lower(regexprep(strrep(char(p), '/', '\'), '\\+$', ''));
source = normalise(sourcePath);
for id = 1:numel(mibModel.I)
    dataset = mibModel.I{id};
    if isempty(dataset) || ~isvalid(dataset); continue; end

    usedPaths = {};
    usedFor = {};
    if any(dataset.datasetType(1) == ['V' 'B'])
        imagePaths = {dataset.image.filename};
        if isprop(dataset.image, 'Virtual') && isstruct(dataset.image.Virtual) && ...
                isfield(dataset.image.Virtual, 'filenames')
            readerFiles = dataset.image.Virtual.filenames;
            if isstring(readerFiles); readerFiles = cellstr(readerFiles); end
            if iscell(readerFiles)
                imagePaths = [imagePaths, reshape(readerFiles, 1, [])]; %#ok<AGROW>
            end
        end
        usedPaths = [usedPaths, imagePaths]; %#ok<AGROW>
        usedFor = [usedFor, repmat({'its image'}, 1, numel(imagePaths))]; %#ok<AGROW>
    end
    if isprop(dataset.labels, 'modelStorePath') && strlength(dataset.labels.modelStorePath) > 0
        usedPaths{end+1} = char(dataset.labels.modelStorePath); %#ok<AGROW>
        usedFor{end+1} = 'its model'; %#ok<AGROW>
    end

    for k = 1:numel(usedPaths)
        if isempty(usedPaths{k}) || ~ischar(usedPaths{k}); continue; end
        used = normalise(usedPaths{k});
        if strcmp(used, source) || startsWith(used, [source '\'])
            inUseBy = struct('id', id, 'what', usedFor{k});
            return;
        end
    end
end
end
