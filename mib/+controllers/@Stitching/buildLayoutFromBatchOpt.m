function buildLayoutFromBatchOpt(obj)
% BUILDLAYOUTFROMBATCHOPT - Build the tile layout from current BatchOpt settings (headless).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.buildLayoutFromBatchOpt()
%
% Builds ``obj.layout`` from ``BatchOpt.LayoutSource`` and ``BatchOpt.InputPath``
% without opening any dialogs, so it works both in batch mode and from the GUI
% after the input path was chosen. Errors when the path is missing or contains
% no tiles. Downstream state (``edges``, ``positions``, ``canvas``) is reset.
%

layoutSource = obj.BatchOpt.LayoutSource{1};
inputPath = obj.BatchOpt.InputPath;

if isempty(inputPath)
    error('Stitching:noInputPath', 'InputPath is empty — select a tile folder or position file first');
end

if strcmp(layoutSource, 'Bio-Formats metadata')
    % One multi-series file (series = tiles) or several single-tile files, each
    % carrying its own OME stage coordinates. buildLayoutBioFormats resolves a
    % newline-joined list / single file / folder and reads the positions.
    obj.layout = utils.stitch.buildLayoutBioFormats(inputPath);
elseif strcmp(layoutSource, 'Position file')
    % The position file's filename column may point at images or (when the
    % tiles are folders) at folder Z-stacks — buildLayoutPositionFile auto-
    % detects each entry, so SubfolderMode needs no special handling here.
    if ~isfile(inputPath)
        error('Stitching:badInputPath', 'Position file not found: %s', inputPath);
    end
    obj.layout = utils.stitch.buildLayoutPositionFile(inputPath);
else
    % Grid or Filename pattern. Collect the tile ENTRIES — image files, or
    % folder Z-stacks when SubfolderMode is on (buildLayout* auto-detect folders).
    tileEntries = collectTileEntries(inputPath, obj.BatchOpt.SubfolderMode);

    if strcmp(layoutSource, 'Grid')
        gridOpts.rows       = obj.BatchOpt.GridRows{1};
        gridOpts.cols       = obj.BatchOpt.GridCols{1};
        gridOpts.tileOrder  = obj.BatchOpt.TileOrder{1};
        gridOpts.overlapX   = obj.BatchOpt.OverlapX{1};
        gridOpts.overlapY   = obj.BatchOpt.OverlapY{1};
        obj.layout = utils.stitch.buildLayoutGrid(tileEntries, gridOpts);
    else
        % Filename pattern — grid indices from the _Z##-X##-Y## tokens, with the
        % same Overlap X/Y as the Grid source (0 = abutting reassembly).
        patternOpts.overlapX = obj.BatchOpt.OverlapX{1};
        patternOpts.overlapY = obj.BatchOpt.OverlapY{1};
        obj.layout = utils.stitch.buildLayoutFilenamePattern(tileEntries, patternOpts);
    end
end

% Reset downstream state
obj.edges     = [];
obj.positions = [];
obj.tforms    = {};
obj.canvas    = [];
obj.zSliceFixes = [];
obj.solverInfo  = struct();
% The layout now describes BatchOpt again, so re-deriving it is safe once more.
obj.layoutFromProject = false;

end

% =========================================================================
function tileEntries = collectTileEntries(inputPath, tilesAreFolders)
% COLLECTTILEENTRIES - List the tile source paths for a Grid / Filename-pattern
% layout. tilesAreFolders (SubfolderMode) selects folder Z-stacks over images:
%   folders ON  — InputPath is a newline-joined folder list (GUI multi-select),
%                 or a single parent folder whose subfolders are the tiles (batch).
%   folders OFF — InputPath is a newline-joined image-file list (GUI
%                 multi-select), or one folder whose image files are the tiles
%                 (typed path / batch back-compat).
if tilesAreFolders
    tileEntries = strtrim(strsplit(inputPath, newline));
    tileEntries = tileEntries(~cellfun(@isempty, tileEntries));
    if isscalar(tileEntries) && isfolder(tileEntries{1})
        parentFolder = tileEntries{1};
        subDirs = dir(parentFolder);
        subDirs = subDirs([subDirs.isdir] & ~ismember({subDirs.name}, {'.', '..'}));
        if isempty(subDirs)
            error('Stitching:noTileFolders', 'No tile subfolders found in %s', parentFolder);
        end
        tileEntries = fullfile(parentFolder, {subDirs.name});
    else
        missing = tileEntries(~cellfun(@isfolder, tileEntries));
        if ~isempty(missing)
            error('Stitching:badTileFolder', 'Tile folder not found: %s', missing{1});
        end
    end
    return;
end

tileEntries = strtrim(strsplit(inputPath, newline));
tileEntries = tileEntries(~cellfun(@isempty, tileEntries));
if isscalar(tileEntries) && isfolder(tileEntries{1})
    % Single folder: its image files are the tiles.
    tileFolder = tileEntries{1};
    imageExtensions = {'*.tif', '*.tiff', '*.png', '*.jpg', '*.jpeg', '*.bmp'};
    tileEntries = {};
    for extIdx = 1:numel(imageExtensions)
        foundFiles = dir(fullfile(tileFolder, imageExtensions{extIdx}));
        if ~isempty(foundFiles)
            tileEntries = [tileEntries, fullfile(tileFolder, {foundFiles.name})]; %#ok<AGROW>
        end
    end
    if isempty(tileEntries)
        error('Stitching:noTiles', 'No image files found in %s', tileFolder);
    end
else
    % Explicit file list from the multi-select picker (or typed/pasted).
    missing = tileEntries(~cellfun(@isfile, tileEntries));
    if ~isempty(missing)
        error('Stitching:badInputPath', 'Tile file not found: %s', missing{1});
    end
end
end
