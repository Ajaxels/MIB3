function fileList_ContextMenu(obj, menuEntry, selectedData)
% function fileList_ContextMenu(obj, menuEntry, selectedData)
% callbacks for the context menu of the file list widget 
% (obj.handles.panels.activeDataset.handles.fileList)
%
% Parameters:
% menuEntry: handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
% selectedData: handle to the pressed
% 'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
% button that has the context menu (selectedData.ContextObject)
%
% Available menu options available from 'menuEntry.Tag':
% fileListContextCombine - combine selected files and open them all as a dataset in MIB
% fileListContextLoadPart - load part of the dataset from the selected file
% fileListContextLoadNth - load each N-th file and combine in a MIB dataset
% fileListContextInsert - insert selected files into the current dataset
% fileListContextColorCombine - combine selected files as color channels and open as a new MIB dataset
% fileListContextColorAdd - add selected file(s) as a new color channel to the current MIB dataset
% fileListContextColorAddNth - add each N-th selected file as a new color channel to the current MIB dataset
% fileListContextRename - rename the selected file
% fileListContextDelete - delete the selected file
% fileListContextProps - get file properties

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
            dlgOpts.Header = 'Please select a single file!';
            dlgOpts.MsgBoxOnly = true;
            dlgOpts.WindowStyle = 'normal';
            dlgOpts.WindowHeight = 150';
            dlgOpts.Icon = 'puffin_warning';
            utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, {}, {}, 'Rename file', dlgOpts);
            return;
        end
        [filePath, filename, ext] = fileparts(fullfile(obj.mibModel.currentDirectory, obj.mibModel.selectedFiles{1}));
        dlgOpts.mibPath = obj.mibModel.mibPath;
        answer = utils.dlgs.inputSingleDlg(obj.mibModel.mibGUI, 'Please enter new file name', [filename, ext], 'Rename file', dlgOpts);
        if isempty(answer); return; end
        movefile(fullfile(filePath, [filename, ext]), fullfile(filePath, answer));
        obj.updateFileList_Callback(answer);

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
        dlgOpts.Header = sprintf('Filename: %s\nDate: %s\nSize: %.3f KB', fileInfo.name, fileInfo.date, fileInfo.bytes/1000);
        dlgOpts.HeaderLines = 4;
        dlgOpts.MsgBoxOnly = true;
        dlgOpts.WindowHeight = 150';
        dlgOpts.WindowWidth = 400';
        dlgOpts.WindowStyle = 'normal';
        dlgOpts.Icon = 'puffin_measure';
        dlgOpts.IconWidth = 96;
        utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, {}, {}, 'File info', dlgOpts);

end

end