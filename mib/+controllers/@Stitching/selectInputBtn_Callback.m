function selectInputBtn_Callback(obj)
% SELECTINPUTBTN_CALLBACK - Open a file/folder picker and build the tile layout.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.selectInputBtn_Callback()
%
% Behaviour depends on ``BatchOpt.LayoutSource`` and ``BatchOpt.SubfolderMode``
% (SubfolderMode = each tile is a FOLDER Z-stack rather than a single file):
%   - **Bio-Formats metadata** — multi-select file picker; one multi-series file
%     (series = tiles) or several single-tile files carrying stage coordinates.
%   - **Position file** — file picker for the position text file (the file's
%     filename column may point at images or, with SubfolderMode, at folders).
%   - **Grid / Filename pattern**, SubfolderMode OFF — folder picker; the folder's
%     image files are the tiles.
%   - **Grid / Filename pattern**, SubfolderMode ON — multi-select the tile
%     folders (each a Z-stack); stored newline-joined in InputPath.
%
% After building the layout, ``obj.layout`` is populated and
% ``updateWidgets`` is called to refresh the status display.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.selectInputBtn_Callback: triggered\n');
end
layoutSource = obj.BatchOpt.LayoutSource{1};

if strcmp(layoutSource, 'Bio-Formats metadata')
    % Pick one or more Bio-Formats files (stage coordinates are read from metadata)
    startFolder = firstExistingPath(obj.BatchOpt.InputPath);
    if isempty(startFolder); startFolder = obj.mibModel.currentDirectory; end
    [selectedFiles, selectedFolder] = uigetfile( ...
        {'*.czi;*.nd2;*.lif;*.oib;*.oif;*.vsi;*.lsm;*.ome.tif;*.ome.tiff;*.tif;*.tiff', ...
         'Bio-Formats files'; '*.*', 'All files'}, ...
        'Select Bio-Formats tile file(s)', startFolder, 'MultiSelect', 'on');
    if isequal(selectedFiles, 0)
        return;
    end
    if ischar(selectedFiles); selectedFiles = {selectedFiles}; end
    fullPaths = fullfile(selectedFolder, selectedFiles);
    obj.BatchOpt.InputPath = strjoin(fullPaths, newline);
    obj.refreshInputPathWidget();
elseif strcmp(layoutSource, 'Position file')
    % Pick a position text file
    startFolder = firstExistingPath(obj.BatchOpt.InputPath);
    if isempty(startFolder); startFolder = obj.mibModel.currentDirectory; end
    [selectedFile, selectedFolder] = uigetfile( ...
        {'*.txt;*.csv;*.tsv', 'Position files (*.txt, *.csv, *.tsv)'; '*.*', 'All files'}, ...
        'Select position file', startFolder);
    if isequal(selectedFile, 0)
        return;
    end
    inputPath = fullfile(selectedFolder, selectedFile);
    obj.BatchOpt.InputPath = inputPath;
    obj.refreshInputPathWidget();
elseif obj.BatchOpt.SubfolderMode
    % Grid / Filename pattern with folder Z-stack tiles — multi-select folders.
    startFolder = firstExistingPath(obj.BatchOpt.InputPath);
    if isempty(startFolder); startFolder = obj.mibModel.currentDirectory; end
    selectedFolders = uigetfile_n_dir(startFolder, 'Select tile folders (each = one Z-stack tile)');
    if isempty(selectedFolders)
        return;
    end
    selectedFolders = selectedFolders(cellfun(@isfolder, selectedFolders));
    if isempty(selectedFolders)
        utils.dlgs.showErrorDialog(obj.view.gui, 'No valid folders selected.', 'Folder selection');
        return;
    end
    obj.BatchOpt.InputPath = strjoin(selectedFolders, newline);
    obj.refreshInputPathWidget();
else
    % Grid / Filename pattern with single-image tiles — pick their folder.
    startFolder = obj.BatchOpt.InputPath;
    if isempty(startFolder) || ~isfolder(startFolder)
        startFolder = obj.mibModel.currentDirectory;
    end
    selectedFolder = uigetdir(startFolder, 'Select tile folder');
    if isequal(selectedFolder, 0)
        return;
    end
    obj.BatchOpt.InputPath = selectedFolder;
    obj.refreshInputPathWidget();
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

% =========================================================================
function startFolder = firstExistingPath(inputPath)
% FIRSTEXISTINGPATH - Parent of the first existing entry in a (possibly
% newline-joined) InputPath, for seeding a picker's start folder. '' if none.
startFolder = '';
if isempty(inputPath); return; end
entries = strtrim(strsplit(inputPath, newline));
entries = entries(~cellfun(@isempty, entries));
for k = 1:numel(entries)
    if isfolder(entries{k})
        startFolder = fileparts(entries{k}); return;
    elseif isfile(entries{k})
        startFolder = fileparts(entries{k}); return;
    end
end
end
