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
%   - **Position file** — file picker for either kind of file that states where the
%     tiles go: MIB's position text file (whose filename column may point at images
%     or, with SubfolderMode, at folders), or a **Fibics Atlas** mosaic
%     (``MosaicInfo_*.ve-mif``). Only the ``.ve-mif`` is offered for Atlas — its
%     ``.ve-tie`` / ``.ve-updates`` results are detected from it automatically, and
%     when Atlas already stitched the mosaic the user is asked how much of that
%     stitch to reuse before the layout is built.
%   - **Grid / Filename pattern**, SubfolderMode OFF — multi-select file picker;
%     the selected image files are the tiles (stored newline-joined in
%     InputPath; the layout builder natural-sorts them, so selection order does
%     not matter). A plain folder path typed/pasted into InputPath still works —
%     its image files become the tiles (batch back-compat).
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
    % Pick a position text file OR a Fibics Atlas mosaic — both state where every
    % tile goes, so they share this source and are told apart by extension.
    startFolder = firstExistingPath(obj.BatchOpt.InputPath);
    if isempty(startFolder); startFolder = obj.mibModel.currentDirectory; end
    % Only the .ve-mif is offered for Atlas: it is the one file that names the
    % tiles, and its .ve-tie / .ve-updates results are found automatically from
    % it. Listing all three would ask the user to make a choice the tool makes
    % better itself.
    [selectedFile, selectedFolder] = uigetfile( ...
        {'*.txt;*.csv;*.tsv;*.ve-mif', 'Position files and Atlas mosaics'; ...
         '*.txt;*.csv;*.tsv', 'Position files (*.txt, *.csv, *.tsv)'; ...
         '*.ve-mif', 'Fibics Atlas mosaic (MosaicInfo_*.ve-mif)'; ...
         '*.*', 'All files'}, ...
        'Select position file or Atlas mosaic', startFolder);
    if isequal(selectedFile, 0)
        return;
    end
    inputPath = fullfile(selectedFolder, selectedFile);

    % A .ve-tie / .ve-updates still resolves back to its .ve-mif — the picker no
    % longer offers them, but "All files" and typed/pasted paths can still reach
    % them, and they name the same mosaic either way.
    sidecars = utils.stitch.findAtlasSidecars(inputPath);
    if ~isempty(sidecars.mifPath)
        inputPath = sidecars.mifPath;
        % Ask BEFORE building: the answer lands in BatchOpt.AtlasImport, which is
        % what buildLayoutFromBatchOpt reads to decide what to import.
        if ~obj.askAtlasImportMode(inputPath)
            return;   % cancelled — leave the previous input untouched
        end
    elseif ismember(lower(extensionOf(inputPath)), {'.ve-tie', '.ve-updates'})
        utils.dlgs.showErrorDialog(obj.view.gui, sprintf([ ...
            'This is one of an Atlas mosaic''s result files, but its ' ...
            'MosaicInfo_*.ve-mif is missing from the same folder.\n\n' ...
            'The .ve-mif lists the tiles, so it has to be there too.']), ...
            'Atlas mosaic incomplete');
        return;
    end

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
    % Grid / Filename pattern with single-image tiles — multi-select the tile
    % files (the layout builder natural-sorts them, so selection order is free).
    startFolder = firstExistingPath(obj.BatchOpt.InputPath);
    if isempty(startFolder); startFolder = obj.mibModel.currentDirectory; end
    [selectedFiles, selectedFolder] = uigetfile( ...
        {'*.tif;*.tiff;*.png;*.jpg;*.jpeg;*.bmp', 'Image files'; '*.*', 'All files'}, ...
        'Select tile image files', startFolder, 'MultiSelect', 'on');
    if isequal(selectedFiles, 0)
        return;
    end
    if ischar(selectedFiles); selectedFiles = {selectedFiles}; end
    fullPaths = fullfile(selectedFolder, selectedFiles);
    obj.BatchOpt.InputPath = strjoin(fullPaths, newline);
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

% Draw the arrangement that was just built. For an Atlas mosaic this is the whole
% point of the import step — the preview shows the SOLVED positions when a
% placement came with the mosaic, so the user sees what pressing Stitch would
% fuse before pressing it. Other inputs only refresh a preview already on screen.
selectedSidecars = utils.stitch.findAtlasSidecars(obj.BatchOpt.InputPath);
if ~isempty(obj.layout) && (~isempty(selectedSidecars.mifPath) || ...
        ~isempty(obj.view.handles.previewAxes.Children))
    obj.previewLayoutBtn_Callback();
end

end

% =========================================================================
function extension = extensionOf(filePath)
% EXTENSIONOF - File extension of a path, '' when it has none.
[~, ~, extension] = fileparts(filePath);
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
