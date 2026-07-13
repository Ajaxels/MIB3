function selectInputBtn_Callback(obj)
% SELECTINPUTBTN_CALLBACK - Open a file/folder picker and build the tile layout.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.selectInputBtn_Callback()
%
% Behaviour depends on ``BatchOpt.LayoutSource``:
%   - **Grid** or **Filename pattern** — opens a folder picker; collects all
%     image files in the folder and calls the appropriate layout builder.
%   - **Position file** — opens a file picker for the position text file.
%
% After building the layout, ``obj.layout`` is populated and
% ``updateWidgets`` is called to refresh the status display.
%

layoutSource = obj.BatchOpt.LayoutSource{1};

if strcmp(layoutSource, 'Position file')
    % Pick a position text file
    startFolder = obj.BatchOpt.InputPath;
    if isempty(startFolder) || ~isfolder(startFolder)
        startFolder = obj.mibModel.currentDirectory;
    end
    [selectedFile, selectedFolder] = uigetfile( ...
        {'*.txt;*.csv;*.tsv', 'Position files (*.txt, *.csv, *.tsv)'; '*.*', 'All files'}, ...
        'Select position file', startFolder);
    if isequal(selectedFile, 0)
        return;
    end
    inputPath = fullfile(selectedFolder, selectedFile);
    obj.BatchOpt.InputPath = inputPath;
    obj.view.handles.InputPath.Value = inputPath;
else
    % Grid or Filename pattern — pick a folder
    startFolder = obj.BatchOpt.InputPath;
    if isempty(startFolder) || ~isfolder(startFolder)
        startFolder = obj.mibModel.currentDirectory;
    end
    selectedFolder = uigetdir(startFolder, 'Select tile folder');
    if isequal(selectedFolder, 0)
        return;
    end
    obj.BatchOpt.InputPath = selectedFolder;
    obj.view.handles.InputPath.Value = selectedFolder;
end

% Build the layout headlessly from the updated BatchOpt
try
    obj.buildLayoutFromBatchOpt();
catch buildError
    utils.dlgs.showErrorDialog(obj.view.gui, buildError.message, 'Layout build failed');
    return;
end

obj.updateWidgets();

end
