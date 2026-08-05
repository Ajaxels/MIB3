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
% The **Position file** source covers three file kinds, told apart by extension:
% MIB's own ``filename X Y [Z]`` text file, a **Fibics Atlas** mosaic
% (``MosaicInfo_*.ve-mif``), and a **SerialEM** montage (``*.mdoc``, or the
% ``.mrc`` it describes). All three answer the same question — where does each
% tile go — so they share one layout source rather than three dropdown entries.
%
% The two vendor formats can bring more than a layout: alongside the acquisition
% record they may carry the vendor's own finished stitch, and
% ``BatchOpt.LayoutImport`` decides how much of it to take (nothing / the seam
% measurements / the measurements and the solved placement). Importing here
% rather than in the GUI callback keeps batch runs and the dialog on one path.
%

layoutSource = obj.BatchOpt.LayoutSource{1};
inputPath = obj.BatchOpt.InputPath;

if isempty(inputPath)
    error('Stitching:noInputPath', 'InputPath is empty — select a tile folder or position file first');
end

% Filled by the Atlas branch below; assigned after the downstream reset so the
% reset cannot wipe what was just imported.
importedEdges     = [];
importedPositions = [];

if strcmp(layoutSource, 'Bio-Formats metadata')
    % One multi-series file (series = tiles) or several single-tile files, each
    % carrying its own OME stage coordinates. buildLayoutBioFormats resolves a
    % newline-joined list / single file / folder and reads the positions.
    obj.layout = utils.stitch.buildLayoutBioFormats(inputPath);
elseif strcmp(layoutSource, 'Position file')
    if ~isfile(inputPath)
        error('Stitching:badInputPath', 'Position file not found: %s', inputPath);
    end
    % Each find*Sidecar* helper returns an all-empty struct for a path that is not
    % its own format, so the returned path doubles as the "is this one of mine?"
    % test — and resolves whichever member of the format's file set was picked
    % back to the one that has to be parsed.
    sidecars     = utils.stitch.findAtlasSidecars(inputPath);
    mdocSidecar  = utils.stitch.findMdocSidecar(inputPath);
    if ~isempty(mdocSidecar.mdocPath)
        % A SerialEM montage: one MRC stack whose slices are the tiles, plus the
        % .mdoc placing them. Same three import stages as Atlas, so the same
        % downgrade rule applies — asking for a stage the file does not carry
        % falls back rather than raising, since the montage is still perfectly
        % stitchable from scratch.
        mdocOptions.importEdges = ~strcmp(obj.BatchOpt.LayoutImport{1}, 'Nominal grid only') && ...
            mdocSidecar.numEdges > 0;
        mdocOptions.importPositions = strcmp(obj.BatchOpt.LayoutImport{1}, 'Vendor seams + solved positions') && ...
            mdocSidecar.numAligned > 0;
        mdocOptions.imagePath = mdocSidecar.imagePath;
        [obj.layout, importedEdges, importedPositions] = ...
            utils.stitch.buildLayoutMdoc(mdocSidecar.mdocPath, mdocOptions);
    elseif ~isempty(sidecars.mifPath)
        % One .ve-mif describes one mosaic (one section): tile files, grid indices
        % and nominal stage positions. An import mode asking for a sidecar that is
        % not there is downgraded rather than raising — the mosaic is still
        % perfectly stitchable from scratch, which is what the nominal layout is for.
        atlasOptions.importTies = ~strcmp(obj.BatchOpt.LayoutImport{1}, 'Nominal grid only') && ...
            ~isempty(sidecars.tiePath);
        atlasOptions.importPositions = strcmp(obj.BatchOpt.LayoutImport{1}, 'Vendor seams + solved positions') && ...
            ~isempty(sidecars.updatesPath);
        [obj.layout, importedEdges, importedPositions] = ...
            utils.stitch.buildLayoutAtlas(sidecars.mifPath, atlasOptions);
    else
        % MIB's text position file. Its filename column may point at images or
        % (when the tiles are folders) at folder Z-stacks — buildLayoutPositionFile
        % auto-detects each entry, so SubfolderMode needs no handling here.
        obj.layout = utils.stitch.buildLayoutPositionFile(inputPath);
    end
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
% Estimated from the OLD tiles, so it cannot describe these ones.
obj.intensityCorrection = [];
% The layout now describes BatchOpt again, so re-deriving it is safe once more.
obj.layoutFromProject = false;

% ---- Adopt anything the layout source brought with it (Fibics Atlas) ----
if ~isempty(importedEdges)
    obj.edges = importedEdges;
end
if ~isempty(importedPositions)
    obj.positions = importedPositions;
    % A placement that arrives without a solve still needs a residual for the
    % alignment chip, otherwise an imported stitch reads "Alignment: —" and the
    % user has no way to tell a good Atlas result from a bad one. Derive it from
    % the imported edges at the imported positions — the same quantity
    % solveGlobalLeastSquares reports, just measured rather than minimised.
    obj.solverInfo = residualsAtPositions(obj.layout, obj.edges, obj.positions);
    % Verify by the PIXELS as well: an Atlas mosaic stitched under difficult
    % imaging conditions can carry confident-but-wrong seams, and re-reading the
    % overlaps is the only check that catches it (same rationale as the seam
    % scoring after every solve in optimizePositions_Callback).
    parentFigure = obj.guiFigure();
    try
        obj.edges = utils.stitch.scoreSeams(obj.layout, obj.edges, obj.positions, ...
            struct('showWaitbar', obj.BatchOpt.showWaitbar && ~isempty(parentFigure), ...
                   'parentFigure', parentFigure, ...
                   'correction', obj.ensureIntensityCorrection()));
    catch
        % pixel verification is advisory — never block the import on it
    end
end

end

% =========================================================================
function solverInfo = residualsAtPositions(layout, edges, positions)
% RESIDUALSATPOSITIONS - solverInfo for a placement that was imported, not solved.
% Same fields utils.stitch.solveGlobalLeastSquares reports, so every consumer
% (the alignment chip, the project sidecar) reads an imported stitch exactly as
% it reads a computed one.

numEdges = numel(edges);
residuals = zeros(numEdges, 3);
for edgeIdx = 1:numEdges
    residuals(edgeIdx, :) = edges(edgeIdx).measured - ...
        (positions(edges(edgeIdx).j, :) - positions(edges(edgeIdx).i, :));
end

validMask = false(numEdges, 1);
if numEdges > 0; validMask = logical([edges.valid])'; end
scored = residuals(validMask, :);
if isempty(scored); scored = zeros(0, 3); end

solverInfo = struct();
solverInfo.residuals  = residuals;
solverInfo.rmse       = sqrt(mean(scored.^2, 1));
solverInfo.rmseTotal  = sqrt(mean(scored(:).^2));
if isempty(scored); solverInfo.rmse = [0 0 0]; solverInfo.rmseTotal = 0; end
solverInfo.nPruned    = 0;
solverInfo.nComponents = 1;
solverInfo.anchorComponent = 1;

% A tile no valid edge touches was never checked by the import — the chip must
% say so rather than rate the mosaic on the tiles that were.
touched = false(numel(layout), 1);
for edgeIdx = find(validMask)'
    touched(edges(edgeIdx).i) = true;
    touched(edges(edgeIdx).j) = true;
end
solverInfo.disconnectedTiles = find(~touched)';

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
