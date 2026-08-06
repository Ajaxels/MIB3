function [layout, edges, positions, atlasInfo] = buildLayoutAtlas(veMifPath, options)
% BUILDLAYOUTATLAS - Build a tile layout (and optionally the stitch) from a Fibics Atlas mosaic.
%
% Syntax:
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutAtlas(veMifPath)
%      [layout, edges, positions, atlasInfo] = utils.stitch.buildLayoutAtlas(veMifPath, options)
%
% Reads the XML files a Fibics Atlas acquisition writes next to its tiles. Atlas
% records three successive stages of the same stitch in three files sharing one
% base name, and this function can take any prefix of that chain:
%
%   ``.ve-mif``      *(always read)* - the acquisition record: per-tile ``row``/``col``
%                    and NOMINAL stage position, tile size, FOV and pixel size.
%                    Becomes the layout's ``gridRC`` / ``nomOrigin``.
%   ``.ve-tie``      *(options.importTies)* - Atlas's pairwise seam measurements.
%                    Becomes the ``edges`` array, so MIB can solve without
%                    re-registering a single pixel.
%   ``.ve-updates``  *(options.importPositions)* - Atlas's FINAL solved tile
%                    positions. Becomes ``positions``, so the mosaic is ready to
%                    fuse with nothing recomputed.
%
% **Why the nominal placement is only a starting guess.** Under some imaging
% conditions the stage positions Atlas records do not describe where the tiles
% actually overlap (the sample data this was written against is off by ~32 px in
% Y - Atlas's own ties agree). The nominal grid is therefore treated exactly like
% any other layout source: a rough placement that ``Measure overlaps`` refines.
% Import the ties (or the ties + positions) to keep Atlas's own answer instead.
%
% **Coordinate conversion.** Atlas works in micrometres on a stage frame whose Y
% axis points UP and whose X axis may run either way. Rather than hard-coding a
% vendor convention, the axis directions are DERIVED per mosaic by correlating
% each tile's ``row``/``col`` attribute with its stage coordinate, so a mosaic
% acquired with a mirrored stage maps correctly without a flag. The same signs
% are then applied to the tie shifts and the solved positions, which share the
% stage frame's orientation.
%
% **Tile files are resolved locally.** The paths inside the XML are absolute
% paths on the acquisition machine (``E:\...``), which almost never exist where
% the data is analysed. Every tile is therefore looked up by its FILE NAME in the
% folder holding the ``.ve-mif``, falling back to the recorded path only when the
% local file is missing.
%
% Input Arguments:
%   - **veMifPath** - [char] full path to the ``MosaicInfo_*.ve-mif`` file.
%   - **options** *(optional)* - struct with fields:
%
%     - ``.importTies`` - [logical] read the ``.ve-tie`` seam measurements into
%       ``edges`` (default: ``false``)
%     - ``.importPositions`` - [logical] read the ``.ve-updates`` solved tile
%       positions into ``positions`` (default: ``false``). With no ties imported
%       the matching ``edges`` are SYNTHESISED from the solved positions, so the
%       state is self-consistent (a re-solve reproduces the same placement) and
%       the seam inspector has something to review.
%     - ``.tiePath`` / ``.updatesPath`` - [char] explicit sidecar paths; by
%       default they are found next to the ``.ve-mif`` by
%       :func:`utils.stitch.findAtlasSidecars`.
%     - ``.layout`` - [struct array] a layout already built from this very
%       ``.ve-mif``; supplied to skip re-reading every tile's dimensions when only
%       the sidecars are wanted (default: ``[]`` - build it).
%
% Output Arguments:
%   - **layout** - struct array per the layout contract (see
%     :func:`utils.stitch.buildLayoutGrid`), one entry per tile, ordered by
%     ``row`` then ``col``. Single Z layer - one ``.ve-mif`` is one section.
%   - **edges** - struct array of imported/synthesised seams (empty when neither
%     sidecar was imported). Ties Atlas marked ``<User>true</User>`` (placed by
%     hand in Atlas) carry ``.source = 'user'``, so MIB weights them like its own
%     manual fixes and a re-measure preserves them; the rest are ``'auto'``.
%   - **positions** - [N x 3 double] solved origins ``[y x z]``, or ``[]``.
%   - **atlasInfo** - struct describing the mosaic: ``.mosaicName``, ``.folder``,
%     ``.pixelSizeUm``, ``.signX`` / ``.signY`` (derived axis directions),
%     ``.fovUm``, ``.overlapXpercent`` / ``.overlapYpercent``, ``.numTilesX`` /
%     ``.numTilesY`` and the per-tile ``.tiles`` records.
%
% **Example** - fuse an Atlas mosaic exactly as Atlas stitched it:
%
%   .. code-block:: matlab
%
%      opts = struct('importTies', true, 'importPositions', true);
%      [layout, edges, positions] = utils.stitch.buildLayoutAtlas( ...
%          'D:\S_001\MosaicInfo_S_001.ve-mif', opts);
%      canvas = utils.stitch.planCanvas(layout, positions);
%      mosaic = utils.stitch.fuseInMemory(layout, canvas);
%
% See also utils.stitch.findAtlasSidecars, utils.stitch.buildLayoutGrid

arguments
    veMifPath (1,:) char
    options   struct = struct()
end

if ~isfield(options, 'importTies');      options.importTies = false; end
if ~isfield(options, 'importPositions'); options.importPositions = false; end
if ~isfield(options, 'tiePath');         options.tiePath = ''; end
if ~isfield(options, 'updatesPath');     options.updatesPath = ''; end
if ~isfield(options, 'layout');          options.layout = []; end

if ~isfile(veMifPath)
    error('utils:stitch:buildLayoutAtlas:fileNotFound', ...
        'Atlas mosaic file not found: %s', veMifPath);
end

sidecars = utils.stitch.findAtlasSidecars(veMifPath);
if isempty(options.tiePath);     options.tiePath     = sidecars.tiePath; end
if isempty(options.updatesPath); options.updatesPath = sidecars.updatesPath; end

% ---- Nominal layout from the acquisition record ----
atlasInfo = readMosaicInfo(veMifPath);
if isempty(options.layout)
    layout = layoutFromMosaicInfo(atlasInfo);
else
    layout = options.layout;
    if numel(layout) ~= numel(atlasInfo.tiles)
        error('utils:stitch:buildLayoutAtlas:layoutMismatch', ...
            'The supplied layout has %d tiles but %s lists %d.', ...
            numel(layout), veMifPath, numel(atlasInfo.tiles));
    end
end

edges     = emptyEdges();
positions = [];

% ---- Atlas's pairwise seam measurements ----
if options.importTies
    if isempty(options.tiePath)
        error('utils:stitch:buildLayoutAtlas:noTieFile', ...
            'No .ve-tie file found next to %s', veMifPath);
    end
    edges = readTies(options.tiePath, layout, atlasInfo);
end

% ---- Atlas's final solved positions ----
if options.importPositions
    if isempty(options.updatesPath)
        error('utils:stitch:buildLayoutAtlas:noUpdatesFile', ...
            'No .ve-updates file found next to %s', veMifPath);
    end
    positions = readUpdates(options.updatesPath, layout, atlasInfo);
    if isempty(edges)
        % Solved positions with no measurements would send Stitch straight back
        % into a full measure pass (it fills an empty edge set before it looks at
        % the positions), throwing away the very import that was just asked for.
        % Derive the edges the positions imply instead: self-consistent, and the
        % seam inspector needs an edge set to review.
        edges = utils.stitch.synthesizeEdgesFromPositions(layout, positions);
    end
end

end

% =========================================================================
function atlasInfo = readMosaicInfo(veMifPath)
% READMOSAICINFO - Parse the .ve-mif acquisition record.

documentNode = xmlread(veMifPath);
rootNode = documentNode.getDocumentElement();

[mosaicFolder, mosaicBaseName] = fileparts(veMifPath);

atlasInfo = struct();
atlasInfo.file   = veMifPath;
atlasInfo.folder = mosaicFolder;

referenceInfoNode = directChild(rootNode, 'ReferenceInfo');
atlasInfo.mosaicName = directChildText(referenceInfoNode, 'Name', mosaicBaseName);

% Pixel size: honour the unit attribute (Atlas writes nm). TileInfo holds a
% SECOND, unrelated PixelSize deep inside the autofocus block - direct-child
% lookups keep the two apart.
[pixelSizeText, pixelSizeUnit] = directChildTextAndUnit(rootNode, 'PixelSize');
pixelSizeUm = str2double(pixelSizeText);
if strcmpi(pixelSizeUnit, 'nm'); pixelSizeUm = pixelSizeUm / 1000; end

tileInfoNode = directChild(rootNode, 'TileInfo');
atlasInfo.fovUm        = directChildNumber(tileInfoNode, 'FOV', NaN);
atlasInfo.tileWidthPx  = directChildNumber(tileInfoNode, 'TileWidth', NaN);
atlasInfo.tileHeightPx = directChildNumber(tileInfoNode, 'TileHeight', NaN);
atlasInfo.overlapXum   = directChildNumber(tileInfoNode, 'TileOverlapXum', NaN);
atlasInfo.overlapYum   = directChildNumber(tileInfoNode, 'TileOverlapYum', NaN);
atlasInfo.numTilesX    = directChildNumber(tileInfoNode, 'NumTilesX', NaN);
atlasInfo.numTilesY    = directChildNumber(tileInfoNode, 'NumTilesY', NaN);

% Fall back to FOV / tile width when PixelSize is absent or nonsensical - the
% two are redundant in the file and either alone determines the scale.
if ~isfinite(pixelSizeUm) || pixelSizeUm <= 0
    pixelSizeUm = atlasInfo.fovUm / atlasInfo.tileWidthPx;
end
if ~isfinite(pixelSizeUm) || pixelSizeUm <= 0
    error('utils:stitch:buildLayoutAtlas:noPixelSize', ...
        'Could not determine the pixel size from %s', veMifPath);
end
atlasInfo.pixelSizeUm = pixelSizeUm;

atlasInfo.overlapXpercent = 100 * atlasInfo.overlapXum / atlasInfo.fovUm;
atlasInfo.overlapYpercent = 100 * atlasInfo.overlapYum / atlasInfo.fovUm;

% ---- Per-tile records ----
tilesNode = directChild(rootNode, 'Tiles');
tileNodes = directChildren(tilesNode, 'Tile');
if isempty(tileNodes)
    error('utils:stitch:buildLayoutAtlas:noTiles', ...
        'No <Tile> entries found in %s', veMifPath);
end

numTiles = numel(tileNodes);
tiles = repmat(struct('row', 0, 'col', 0, 'mifIndex', 0, 'filename', '', ...
    'stageXum', NaN, 'stageYum', NaN), 1, numTiles);
for tileIdx = 1:numTiles
    tileNode = tileNodes{tileIdx};
    tiles(tileIdx).mifIndex = tileIdx - 1;      % 0-based, as the tie file counts
    tiles(tileIdx).row = attributeNumber(tileNode, 'row', tileIdx);
    tiles(tileIdx).col = attributeNumber(tileNode, 'col', 1);

    % TargetStage* is the intended grid position, Stage* the position the stage
    % actually reported. The target is the cleaner rough placement (an exactly
    % regular grid); the readback only differs by the stage's own settling error.
    stageX = directChildNumber(tileNode, 'TargetStageX', NaN);
    stageY = directChildNumber(tileNode, 'TargetStageY', NaN);
    if ~isfinite(stageX); stageX = directChildNumber(tileNode, 'StageX', NaN); end
    if ~isfinite(stageY); stageY = directChildNumber(tileNode, 'StageY', NaN); end
    tiles(tileIdx).stageXum = stageX;
    tiles(tileIdx).stageYum = stageY;

    tiles(tileIdx).filename = resolveTileFile( ...
        directChildText(tileNode, 'Filename', ''), mosaicFolder);
end

% Order by grid position so tile numbering in the preview reads row by row;
% mifIndex keeps the tie file's own numbering usable as a fallback.
[~, sortOrder] = sortrows([[tiles.row]', [tiles.col]']);
atlasInfo.tiles = tiles(sortOrder);

% ---- Stage axis directions, derived from this mosaic ----
[atlasInfo.signX, atlasInfo.signY] = deriveAxisSigns(atlasInfo.tiles);

end

% =========================================================================
function [signX, signY] = deriveAxisSigns(tiles)
% DERIVEAXISSIGNS - Which way each stage axis runs relative to the pixel axes.
%
% ``x_px`` must grow with the column index and ``y_px`` with the row index. Both
% signs are read off the mosaic itself by correlating the grid index with the
% stage coordinate, so no vendor/stage convention is assumed. Defaults (X as
% recorded, Y inverted - the usual Y-up stage) cover degenerate 1xN / Nx1 grids
% where one axis carries no information.

signX = 1;
signY = -1;

columnIndices = [tiles.col]';
rowIndices    = [tiles.row]';
stageX        = [tiles.stageXum]';
stageY        = [tiles.stageYum]';

usableX = isfinite(stageX);
if numel(unique(columnIndices(usableX))) > 1
    covarianceX = cov(columnIndices(usableX), stageX(usableX));
    if covarianceX(1, 2) ~= 0; signX = sign(covarianceX(1, 2)); end
end

usableY = isfinite(stageY);
if numel(unique(rowIndices(usableY))) > 1
    covarianceY = cov(rowIndices(usableY), stageY(usableY));
    if covarianceY(1, 2) ~= 0; signY = sign(covarianceY(1, 2)); end
end

end

% =========================================================================
function layout = layoutFromMosaicInfo(atlasInfo)
% LAYOUTFROMMOSAICINFO - Turn the parsed tile records into the layout contract.

tiles = atlasInfo.tiles;
numTiles = numel(tiles);

missingFiles = find(~cellfun(@isfile, {tiles.filename}), 1);
if ~isempty(missingFiles)
    error('utils:stitch:buildLayoutAtlas:tileNotFound', ...
        ['Tile file not found: %s\n' ...
         'The .ve-mif records the acquisition machine''s paths; the tiles are ' ...
         'looked up by name in %s'], tiles(missingFiles).filename, atlasInfo.folder);
end

originXpx = atlasInfo.signX * [tiles.stageXum]' / atlasInfo.pixelSizeUm;
originYpx = atlasInfo.signY * [tiles.stageYum]' / atlasInfo.pixelSizeUm;
originXpx = originXpx - min(originXpx) + 1;   % 1-based, fractions kept for the solver
originYpx = originYpx - min(originYpx) + 1;

layout(numTiles) = struct('index', 0, 'filename', '', 'sliceFiles', {{}}, 'zLayer', 1, ...
    'gridRC', [0 0], 'nomOrigin', [0 0 0], 'tileSize', [0 0 0 0], 'dataClass', '', ...
    'pixSize', []);

% The mosaic's own scale, so the stitched dataset inherits it. One .ve-mif is one
% section and carries no thickness, so Z is the in-plane size.
tilePixSize = struct('x', atlasInfo.pixelSizeUm, 'y', atlasInfo.pixelSizeUm, ...
    'z', atlasInfo.pixelSizeUm, 'units', 'um');

for tileIdx = 1:numTiles
    [sliceFiles, tileSize, dataClass] = utils.stitch.resolveTileEntry(tiles(tileIdx).filename);
    layout(tileIdx).index      = tileIdx;
    layout(tileIdx).filename   = tiles(tileIdx).filename;
    layout(tileIdx).sliceFiles = sliceFiles;
    layout(tileIdx).zLayer     = 1;            % one .ve-mif is one section
    layout(tileIdx).gridRC     = [tiles(tileIdx).row, tiles(tileIdx).col];
    layout(tileIdx).nomOrigin  = [originYpx(tileIdx), originXpx(tileIdx), 1];
    layout(tileIdx).tileSize   = tileSize;
    layout(tileIdx).dataClass  = dataClass;
    layout(tileIdx).pixSize    = tilePixSize;
end

end

% =========================================================================
function edges = readTies(tiePath, layout, atlasInfo)
% READTIES - Convert Atlas's pairwise seam measurements into the edge contract.
%
% Each ``<Tie>`` states where the shared strip sits inside both tiles
% (``Image1Position`` / ``Image2Position``, µm from each tile's centre) and the
% correction Atlas measured for it (``Shift``). The offset from tile i to tile j
% is therefore ``(Image2Position - Image1Position) + Shift`` in the stage frame -
% the position terms alone reproduce the nominal step exactly.

documentNode = xmlread(tiePath);
rootNode = documentNode.getDocumentElement();

% Atlas rejects its own ties below this confidence; honouring it keeps a tie it
% would not have used from silently steering MIB's solve.
confidenceThreshold = directChildNumber(rootNode, 'ConfidenceThreshold', 0);

tieNodes = directChildren(directChild(rootNode, 'Ties'), 'Tie');
edges = emptyEdges();
if isempty(tieNodes); return; end

[nameToIndex, mifIndexToLayout] = buildTileLookup(layout, atlasInfo);
pixelSizeUm = atlasInfo.pixelSizeUm;

seenPairs = false(numel(layout), numel(layout));
for tieIdx = 1:numel(tieNodes)
    tieNode = tieNodes{tieIdx};

    tileI = resolveTileReference(tieNode, 'Image1FileName', 'Image1Index', nameToIndex, mifIndexToLayout);
    tileJ = resolveTileReference(tieNode, 'Image2FileName', 'Image2Index', nameToIndex, mifIndexToLayout);
    if isempty(tileI) || isempty(tileJ) || tileI == tileJ; continue; end

    position1 = readXY(directChild(tieNode, 'Image1Position'));
    position2 = readXY(directChild(tieNode, 'Image2Position'));
    shiftUm   = readXY(directChild(tieNode, 'Shift'));
    if any(~isfinite([position1, position2, shiftUm])); continue; end

    % Both positions locate the SAME shared strip, each in its own tile's frame:
    % strip = centre1 + position1 = centre2 + position2, so the tile-to-tile
    % offset is position1 - position2 (+329 - -329 = the nominal step, exactly),
    % and Shift is the correction Atlas measured on top of it.
    offsetUm = (position1 - position2) + shiftUm;   % tile i -> tile j, stage frame
    measured = [atlasInfo.signY * offsetUm(2) / pixelSizeUm, ...
                atlasInfo.signX * offsetUm(1) / pixelSizeUm, 0];

    % Every other producer of edges emits i < j; keep that invariant so the
    % solver, the seam scorer and the inspector all see the familiar orientation.
    if tileI > tileJ
        [tileI, tileJ] = deal(tileJ, tileI);
        measured = -measured;
    end
    if seenPairs(tileI, tileJ); continue; end
    seenPairs(tileI, tileJ) = true;

    confidence   = directChildNumber(tieNode, 'Confidence', 0);
    isOverlap    = directChildFlag(tieNode, 'Overlap', true);
    isUserPlaced = directChildFlag(tieNode, 'User', false);

    nominal = layout(tileJ).nomOrigin - layout(tileI).nomOrigin;

    newEdge = emptyEdges();
    newEdge(1).i         = tileI;
    newEdge(1).j         = tileJ;
    newEdge(1).direction = directionOf(nominal, measured);
    newEdge(1).nominal   = nominal;
    newEdge(1).measured  = measured;
    % Atlas confidence is an unbounded ratio that runs slightly above 1 on strong
    % matches; MIB's quality is a [0 1] score, so it is clamped rather than rescaled.
    newEdge(1).quality   = min(1, max(0, confidence));
    newEdge(1).valid     = isOverlap && confidence >= confidenceThreshold;
    newEdge(1).tform     = [];
    % A tie Atlas marks <User>true</User> was placed by hand in Atlas - exactly
    % what 'user' means here, so it gets the same solver weight and the same
    % protection from being overwritten by a re-measure.
    newEdge(1).source    = ternaryChar(isUserPlaced, 'user', 'auto');
    newEdge(1).seamScore = [];
    newEdge(1).dzHint    = 0;

    edges(end + 1) = newEdge; %#ok<AGROW>
end

end

% =========================================================================
function positions = readUpdates(updatesPath, layout, atlasInfo)
% READUPDATES - Read Atlas's final solved tile positions.
%
% Each ``<Tile>`` carries a 4x4 ``<ParentTransform>`` that maps the unit square
% onto the mosaic: ``M11``/``M22`` are the tile's FOV in µm and ``M41``/``M42``
% its solved offset, in the same stage-frame orientation as the ``.ve-mif``.
% Only the translation is used - the linear part is the fixed tile scale, and
% Atlas wrote ``PerTileRotation``/``PerTileScale`` = false.
%
% ``<DefaultAlignment>`` holds a second, unrelated ``<ParentTransform>``; taking
% only DIRECT children of ``<Tile>`` is what keeps them apart.

documentNode = xmlread(updatesPath);
rootNode = documentNode.getDocumentElement();
tileNodes = directChildren(rootNode, 'Tile');

numTiles = numel(layout);
solvedXum = nan(numTiles, 1);
solvedYum = nan(numTiles, 1);

[nameToIndex, ~] = buildTileLookup(layout, atlasInfo);

for tileIdx = 1:numel(tileNodes)
    tileNode = tileNodes{tileIdx};

    layoutIndex = lookupByName(nameToIndex, directChildText(tileNode, 'Name', ''));
    if isempty(layoutIndex)
        layoutIndex = lookupByName(nameToIndex, directChildText(tileNode, 'FileName', ''));
    end
    if isempty(layoutIndex); continue; end

    transformNode = directChild(tileNode, 'ParentTransform');
    if isempty(transformNode); continue; end
    solvedXum(layoutIndex) = directChildNumber(transformNode, 'M41', NaN);
    solvedYum(layoutIndex) = directChildNumber(transformNode, 'M42', NaN);
end

if all(isnan(solvedXum))
    error('utils:stitch:buildLayoutAtlas:noSolvedPositions', ...
        'None of the tiles in %s could be matched to the mosaic''s tiles.', updatesPath);
end

positionXpx = atlasInfo.signX * solvedXum / atlasInfo.pixelSizeUm;
positionYpx = atlasInfo.signY * solvedYum / atlasInfo.pixelSizeUm;
positionXpx = positionXpx - min(positionXpx, [], 'omitnan') + 1;
positionYpx = positionYpx - min(positionYpx, [], 'omitnan') + 1;

% A tile Atlas did not place stays where the nominal grid put it - the same
% treatment the global solver gives a tile with no valid measurement.
nominalOrigins = reshape([layout.nomOrigin], 3, []).';
unplaced = isnan(positionXpx) | isnan(positionYpx);
positionXpx(unplaced) = nominalOrigins(unplaced, 2);
positionYpx(unplaced) = nominalOrigins(unplaced, 1);

positions = [positionYpx, positionXpx, nominalOrigins(:, 3)];

end

% =========================================================================
function [nameToIndex, mifIndexToLayout] = buildTileLookup(layout, atlasInfo)
% BUILDTILELOOKUP - Name -> layout index map, plus the .ve-mif's own numbering.
%
% The sidecars name their tiles by the acquisition machine's absolute path, so
% matching is done on the lower-cased base name (no extension), which survives
% the move to the analysis machine. Atlas also writes ``.ve-updates`` ``<Name>``
% without an extension, so both forms land on the same key.

numTiles = numel(layout);
tileKeys = strings(numTiles, 1);
for tileIdx = 1:numTiles
    [~, baseName] = fileparts(layout(tileIdx).filename);
    tileKeys(tileIdx) = lower(string(baseName));
end
[uniqueKeys, firstOccurrence] = unique(tileKeys, 'stable');
nameToIndex = dictionary(uniqueKeys, firstOccurrence);

mifIndexToLayout = zeros(numTiles, 1);
mifIndexToLayout([atlasInfo.tiles.mifIndex] + 1) = 1:numTiles;

end

% =========================================================================
function layoutIndex = resolveTileReference(tieNode, fileTag, indexTag, nameToIndex, mifIndexToLayout)
% RESOLVETILEREFERENCE - Map a tie's tile reference onto a layout index.
% The recorded file name is authoritative; the 0-based index into the .ve-mif's
% tile listing is the fallback for files renamed after acquisition.

layoutIndex = lookupByName(nameToIndex, directChildText(tieNode, fileTag, ''));
if ~isempty(layoutIndex); return; end

mifIndex = directChildNumber(tieNode, indexTag, NaN);
if isfinite(mifIndex) && mifIndex >= 0 && mifIndex < numel(mifIndexToLayout)
    layoutIndex = mifIndexToLayout(mifIndex + 1);
    if layoutIndex == 0; layoutIndex = []; end
end

end

% =========================================================================
function layoutIndex = lookupByName(nameToIndex, recordedPath)
% LOOKUPBYNAME - Layout index for a recorded path, [] when it is not a tile here.
layoutIndex = [];
if isempty(recordedPath); return; end
[~, baseName] = fileparts(strrep(recordedPath, '\', filesep));
tileKey = lower(string(baseName));
if isKey(nameToIndex, tileKey)
    layoutIndex = nameToIndex(tileKey);
end
end

% =========================================================================
function tileFile = resolveTileFile(recordedPath, mosaicFolder)
% RESOLVETILEFILE - Locate a tile recorded with the acquisition machine's path.
tileFile = recordedPath;
if isempty(recordedPath); return; end
[~, baseName, extension] = fileparts(strrep(recordedPath, '\', filesep));
localCandidate = fullfile(mosaicFolder, [baseName, extension]);
if isfile(localCandidate)
    tileFile = localCandidate;
end
end

% =========================================================================
function direction = directionOf(nominal, measured)
% DIRECTIONOF - Tag a seam 'x' or 'y' by its dominant offset, matching
% utils.stitch.findNeighborPairs. Falls back to the measured offset when the
% nominal one is degenerate (both tiles at the same nominal spot).
offset = nominal;
if all(abs(offset(1:2)) < eps); offset = measured; end
if abs(offset(2)) >= abs(offset(1))
    direction = 'x';
else
    direction = 'y';
end
end

% =========================================================================
function edges = emptyEdges()
% EMPTYEDGES - One-element template carrying every field the pipeline expects.
edges = struct('i', 0, 'j', 0, 'direction', 'x', 'nominal', [0 0 0], ...
    'measured', [0 0 0], 'quality', 0, 'valid', false, 'tform', [], ...
    'source', 'auto', 'seamScore', [], 'dzHint', 0);
edges(1) = [];
end

% =========================================================================
function value = ternaryChar(condition, trueValue, falseValue)
if condition; value = trueValue; else; value = falseValue; end
end

% ============================== XML helpers ==============================
% Atlas nests tags that repeat at different depths (<PixelSize> inside the
% autofocus block, <ParentTransform> inside <DefaultAlignment>), so every lookup
% here walks DIRECT children only - getElementsByTagName would cross those
% boundaries and pick up the wrong node.

function childNode = directChild(parentNode, tagName)
% DIRECTCHILD - First direct child element with this tag, [] when absent.
childNode = [];
if isempty(parentNode); return; end
childNodes = parentNode.getChildNodes();
for nodeIdx = 0:childNodes.getLength() - 1
    candidate = childNodes.item(nodeIdx);
    if candidate.getNodeType() == 1 && strcmp(char(candidate.getNodeName()), tagName)
        childNode = candidate;
        return;
    end
end
end

% =========================================================================
function childNodes = directChildren(parentNode, tagName)
% DIRECTCHILDREN - All direct child elements with this tag, as a cell array.
childNodes = {};
if isempty(parentNode); return; end
allChildren = parentNode.getChildNodes();
for nodeIdx = 0:allChildren.getLength() - 1
    candidate = allChildren.item(nodeIdx);
    if candidate.getNodeType() == 1 && strcmp(char(candidate.getNodeName()), tagName)
        childNodes{end + 1} = candidate; %#ok<AGROW>
    end
end
end

% =========================================================================
function text = directChildText(parentNode, tagName, defaultText)
% DIRECTCHILDTEXT - Text content of a direct child element.
text = defaultText;
childNode = directChild(parentNode, tagName);
if isempty(childNode); return; end
text = strtrim(char(childNode.getTextContent()));
end

% =========================================================================
function [text, unit] = directChildTextAndUnit(parentNode, tagName)
% DIRECTCHILDTEXTANDUNIT - Text content plus the element's `unit` attribute.
text = '';
unit = '';
childNode = directChild(parentNode, tagName);
if isempty(childNode); return; end
text = strtrim(char(childNode.getTextContent()));
unit = strtrim(char(childNode.getAttribute('unit')));
end

% =========================================================================
function value = directChildNumber(parentNode, tagName, defaultValue)
% DIRECTCHILDNUMBER - Numeric content of a direct child element.
value = defaultValue;
text = directChildText(parentNode, tagName, '');
if isempty(text); return; end
parsed = str2double(text);
if ~isnan(parsed); value = parsed; end
end

% =========================================================================
function flag = directChildFlag(parentNode, tagName, defaultValue)
% DIRECTCHILDFLAG - Boolean content ('true'/'false') of a direct child element.
flag = defaultValue;
text = directChildText(parentNode, tagName, '');
if isempty(text); return; end
flag = strcmpi(text, 'true') || strcmp(text, '1');
end

% =========================================================================
function value = attributeNumber(node, attributeName, defaultValue)
% ATTRIBUTENUMBER - Numeric value of an element attribute.
value = defaultValue;
text = strtrim(char(node.getAttribute(attributeName)));
if isempty(text); return; end
parsed = str2double(text);
if ~isnan(parsed); value = parsed; end
end

% =========================================================================
function xyValue = readXY(pointNode)
% READXY - [X Y] of an Atlas point element; NaNs when the element is missing.
xyValue = [NaN, NaN];
if isempty(pointNode); return; end
xyValue = [directChildNumber(pointNode, 'X', NaN), directChildNumber(pointNode, 'Y', NaN)];
end
