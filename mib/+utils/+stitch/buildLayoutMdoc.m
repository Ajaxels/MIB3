function [layout, edges, positions, mdocInfo] = buildLayoutMdoc(mdocPath, options)
% BUILDLAYOUTMDOC - Build a tile layout (and optionally the stitch) from a SerialEM montage.
%
% Syntax:
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutMdoc(mdocPath)
%      [layout, edges, positions, mdocInfo] = utils.stitch.buildLayoutMdoc(mdocPath, options)
%
% Reads the plain-text ``.mdoc`` SerialEM writes beside a montage's MRC stack.
% Unlike every other layout source, the tiles are not separate files: each is a
% SLICE of the one container, addressed through the ``.sliceIndex`` field this
% builder adds to the layout contract and honoured by
% :func:`utils.stitch.makeTileReader`.
%
% The ``.mdoc`` records three successive stages of the same stitch, exactly as
% Fibics Atlas splits them across its three XML files, and this function can take
% any prefix of that chain:
%
%   ``PieceCoordinates``     *(always read)* - the NOMINAL montage position of
%                            each tile, in pixels. Becomes ``nomOrigin``.
%   ``XedgeDxy`` / ``YedgeDxy``  *(options.importEdges)* - SerialEM's own pairwise
%                            seam measurements. Becomes ``edges``, so MIB can
%                            solve without re-registering a pixel.
%   ``AlignedPieceCoords``   *(options.importPositions)* - SerialEM's FINAL solved
%                            tile positions. Becomes ``positions``, so the mosaic
%                            is ready to fuse with nothing recomputed.
%
% **Why the nominal placement is only a starting guess.** On the reference data
% the recorded grid is out by up to 5 px - MIB's own phase correlation and
% SerialEM's ``AlignedPieceCoords`` agree with each other to ~1 px and both
% disagree with ``PieceCoordinates`` by the same amount. Treat the nominal grid
% exactly like any other layout source: a rough placement that ``Measure
% overlaps`` refines. Import the edges (or the edges + positions) to keep
% SerialEM's own answer instead.
%
% .. important::
%    **The Y axis is mirrored.** MRC stores rows bottom-up and
%    :class:`io.loaders.ImodLoader` flips them on load, so a tile's ``row`` runs
%    OPPOSITE to its ``PieceCoordinates`` Y. Every Y quantity here - nominal
%    origins, solved positions and the edge shifts - is negated together, and the
%    result is normalised to a minimum of 1, which is why the montage's overall
%    height never enters the arithmetic.
%
% .. important::
%    **Edge sign convention (load-bearing).** ``XedgeDxy``/``YedgeDxy`` are
%    ``[dx dy]`` in the montage frame and are stated as the displacement of the
%    LOWER piece, so the offset to add to the nominal step is their negation. In
%    MIB's ``[row col]`` frame the row component picks up a SECOND negation from
%    the Y mirror, which cancels back to a plus:
%    ``measured = nominal + [edgeDxy(2), -edgeDxy(1), 0]``.
%    Verified against phase correlation on real data - both directions agree to
%    ~1.5 px, while the nominal grid is out by 5 px.
%
% .. note::
%    A piece stores the edge to its neighbour at HIGHER X/Y, so ``XedgeDxy`` is
%    absent on the last column and ``YedgeDxy`` on the last row.
%
% Input Arguments:
%   - **mdocPath** - [char] full path to the ``.mdoc`` file.
%   - **options** *(optional)* - struct with fields:
%
%     - ``.importEdges`` - [logical] read ``XedgeDxy``/``YedgeDxy`` into ``edges``
%       (default: ``false``)
%     - ``.importPositions`` - [logical] read ``AlignedPieceCoords`` into
%       ``positions`` (default: ``false``). With no edges imported the matching
%       ``edges`` are SYNTHESISED from the solved positions by
%       :func:`utils.stitch.synthesizeEdgesFromPositions`.
%     - ``.imagePath`` - [char] explicit path to the MRC container; by default it
%       is found from the ``.mdoc`` name by :func:`utils.stitch.findMdocSidecar`.
%
% Output Arguments:
%   - **layout** - struct array per the layout contract (see
%     :func:`utils.stitch.buildLayoutGrid`) plus ``.sliceIndex`` - the 1-based
%     slice of ``.filename`` holding this tile. Ordered by row then column.
%   - **edges** - struct array of imported/synthesised seams, empty when neither
%     stage was imported. SerialEM records no per-seam confidence, so every
%     imported edge carries ``.quality = 1`` and ``.valid = true``; it is the
%     caller's :func:`utils.stitch.scoreSeams` pass that checks them against the
%     pixels.
%   - **positions** - [N x 3 double] solved origins ``[y x z]``, or ``[]``.
%   - **mdocInfo** - struct describing the montage: ``.file``, ``.imagePath``,
%     ``.pixelSizeUm``, ``.tileHeight`` / ``.tileWidth``, ``.mrcMode``,
%     ``.fullMontSize``, ``.numSections`` and the per-tile ``.tiles`` records.
%
% **Example** - fuse a SerialEM montage exactly as SerialEM stitched it:
%
%   .. code-block:: matlab
%
%      opts = struct('importEdges', true, 'importPositions', true);
%      [layout, edges, positions] = utils.stitch.buildLayoutMdoc( ...
%          'D:\Cell1.mrc.mdoc', opts);
%      canvas = utils.stitch.planCanvas(layout, positions);
%      mosaic = utils.stitch.fuseInMemory(layout, canvas);
%
% See also utils.stitch.findMdocSidecar, utils.stitch.buildLayoutAtlas,
% utils.stitch.mrcTargetClass

arguments
    mdocPath (1,:) char
    options  struct = struct()
end

if ~isfield(options, 'importEdges');     options.importEdges = false; end
if ~isfield(options, 'importPositions'); options.importPositions = false; end
if ~isfield(options, 'imagePath');       options.imagePath = ''; end

if ~isfile(mdocPath)
    error('utils:stitch:buildLayoutMdoc:fileNotFound', ...
        'SerialEM montage description not found: %s', mdocPath);
end

sidecar = utils.stitch.findMdocSidecar(mdocPath);
if isempty(options.imagePath); options.imagePath = sidecar.imagePath; end
if isempty(options.imagePath) || ~isfile(options.imagePath)
    error('utils:stitch:buildLayoutMdoc:imageNotFound', ...
        ['The MRC stack holding the tiles was not found next to %s\n' ...
         'A SerialEM montage is two files: the image (e.g. Cell1.mrc) and the ' ...
         '.mdoc naming it.'], mdocPath);
end

% ---- Parse the montage description ----
mdocInfo = readMdoc(mdocPath);
mdocInfo.imagePath = options.imagePath;

if isempty(mdocInfo.tiles)
    error('utils:stitch:buildLayoutMdoc:notAMontage', ...
        ['%s carries no PieceCoordinates, so it does not describe a mosaic.\n' ...
         'SerialEM writes the same format for tilt series and single acquisitions, ' ...
         'which have no tiles to stitch.'], mdocPath);
end

% ---- Tile geometry and pixel class from the MRC header ----
mdocInfo = readContainerGeometry(mdocInfo);

layout = layoutFromMdoc(mdocInfo);

edges     = emptyEdges();
positions = [];

% ---- SerialEM's pairwise seam measurements ----
if options.importEdges
    edges = edgesFromMdoc(mdocInfo, layout);
    if isempty(edges)
        error('utils:stitch:buildLayoutMdoc:noEdges', ...
            'No XedgeDxy / YedgeDxy measurements found in %s', mdocPath);
    end
end

% ---- SerialEM's final solved positions ----
if options.importPositions
    positions = positionsFromMdoc(mdocInfo, layout);
    if isempty(edges)
        % Solved positions with no measurements would send Stitch straight back
        % into a full measure pass, throwing away the very import that was asked
        % for. Derive the edges the positions imply instead.
        edges = utils.stitch.synthesizeEdgesFromPositions(layout, positions);
    end
end

end

% =========================================================================
function mdocInfo = readMdoc(mdocPath)
% READMDOC - Parse the .mdoc into globals, per-tile records and section blocks.
%
% The format is flat ``Key = value`` lines partitioned by bracketed block headers:
% ``[T = ...]`` (free-text titles, ignored), ``[ZValue = n]`` (one per slice, and
% for a montage one per TILE) and ``[MontSection = n]`` (one per section). Lines
% before the first block are montage-wide settings.

mdocInfo = struct();
mdocInfo.file         = mdocPath;
mdocInfo.pixelSizeUm  = NaN;
mdocInfo.fullMontSize = [];
mdocInfo.numSections  = 0;
mdocInfo.declaredSize = [];

rawText  = fileread(mdocPath);
rawLines = strsplit(rawText, {'\n', '\r\n', '\r'});

tileTemplate = struct('zValue', 0, 'pieceXYZ', [NaN NaN NaN], ...
    'alignedXYZ', [NaN NaN NaN], 'xEdge', [NaN NaN], 'yEdge', [NaN NaN]);
tiles = tileTemplate;
tiles(1) = [];

currentTile = 0;      % index into tiles(), 0 while outside a [ZValue] block

for lineIdx = 1:numel(rawLines)
    trimmedLine = strtrim(rawLines{lineIdx});
    if isempty(trimmedLine); continue; end

    % ---- Block header ----
    if trimmedLine(1) == '['
        blockTokens = regexp(trimmedLine, '^\[\s*(\w+)\s*=\s*(.*?)\s*\]$', 'tokens', 'once');
        currentTile = 0;
        if isempty(blockTokens); continue; end
        switch blockTokens{1}
            case 'ZValue'
                tiles(end + 1) = tileTemplate; %#ok<AGROW>
                tiles(end).zValue = str2double(blockTokens{2});
                currentTile = numel(tiles);
            case 'MontSection'
                mdocInfo.numSections = mdocInfo.numSections + 1;
        end
        continue;
    end

    keyValue = regexp(trimmedLine, '^(\w+)\s*=\s*(.*)$', 'tokens', 'once');
    if isempty(keyValue); continue; end
    keyName    = keyValue{1};
    numericValue = str2double(strsplit(strtrim(keyValue{2})));

    if currentTile > 0
        switch keyName
            case 'PieceCoordinates';   tiles(currentTile).pieceXYZ   = padTo3(numericValue);
            case 'AlignedPieceCoords'; tiles(currentTile).alignedXYZ = padTo3(numericValue);
            case 'XedgeDxy';           tiles(currentTile).xEdge      = padTo2(numericValue);
            case 'YedgeDxy';           tiles(currentTile).yEdge      = padTo2(numericValue);
        end
        continue;
    end

    % Montage-wide keys. PixelSpacing is repeated inside every [ZValue] block;
    % only the montage-wide one is taken (the per-tile copies are identical, but
    % reading them would make the value depend on parse order).
    switch keyName
        case 'PixelSpacing'
            % SerialEM writes Angstroms.
            if isscalar(numericValue) && isfinite(numericValue)
                mdocInfo.pixelSizeUm = numericValue / 10000;
            end
        case 'ImageSize'
            if numel(numericValue) >= 2; mdocInfo.declaredSize = numericValue(1:2); end
        case 'FullMontSize'
            if numel(numericValue) >= 2; mdocInfo.fullMontSize = numericValue(1:2); end
    end
end

% FullMontSize lives inside the [MontSection] block, past the point where
% currentTile has been reset, so pick it up wherever it appeared.
if isempty(mdocInfo.fullMontSize)
    montSize = regexp(rawText, '(?m)^\s*FullMontSize\s*=\s*(.+?)\s*$', 'tokens', 'once');
    if ~isempty(montSize)
        parsed = str2double(strsplit(strtrim(montSize{1})));
        if numel(parsed) >= 2; mdocInfo.fullMontSize = parsed(1:2); end
    end
end

% A [ZValue] block without PieceCoordinates is not a tile (tilt-series entry).
placedTiles = arrayfun(@(t) all(isfinite(t.pieceXYZ(1:2))), tiles);
mdocInfo.tiles = tiles(placedTiles);

end

% =========================================================================
function mdocInfo = readContainerGeometry(mdocInfo)
% READCONTAINERGEOMETRY - Tile dimensions and pixel class, from the MRC header.
%
% The header is authoritative over the .mdoc's ``ImageSize``: it describes the
% pixels that will actually be read. A disagreement means the .mdoc no longer
% matches its image, which is worth a warning but not a refusal.

try
    mrcFile = MRCImage(mdocInfo.imagePath, 0);   % header only, no pixels
    header  = getHeader(mrcFile);
    close(mrcFile);
catch readError
    error('utils:stitch:buildLayoutMdoc:badContainer', ...
        'Could not read the MRC header of %s\n%s', mdocInfo.imagePath, readError.message);
end

% ImodLoader permutes [nX nY nZ] -> [nY nX nZ], so rows come from nY.
mdocInfo.tileHeight = header.nY;
mdocInfo.tileWidth  = header.nX;
mdocInfo.numSlices  = header.nZ;
mdocInfo.mrcMode    = header.mode;

if numel(mdocInfo.tiles) > header.nZ
    error('utils:stitch:buildLayoutMdoc:tileCountMismatch', ...
        '%s places %d tiles but %s holds only %d slices.', ...
        mdocInfo.file, numel(mdocInfo.tiles), mdocInfo.imagePath, header.nZ);
end

if ~isempty(mdocInfo.declaredSize) && ...
        ~isequal(mdocInfo.declaredSize(:)', [header.nX, header.nY])
    warning('utils:stitch:buildLayoutMdoc:sizeMismatch', ...
        ['%s declares ImageSize %d %d but %s is %d x %d; ' ...
         'the MRC header is used.'], mdocInfo.file, mdocInfo.declaredSize(1), ...
        mdocInfo.declaredSize(2), mdocInfo.imagePath, header.nX, header.nY);
end

% Pixel size: the .mdoc's PixelSpacing (Angstroms) is preferred; the MRC cell
% dimensions carry the same number and stand in when the key is absent.
if ~isfinite(mdocInfo.pixelSizeUm) || mdocInfo.pixelSizeUm <= 0
    mdocInfo.pixelSizeUm = header.cellDimensionX / header.nX / 10000;
end

[mdocInfo.dataClass, mdocInfo.needsScaling] = utils.stitch.mrcTargetClass(header.mode);

end

% =========================================================================
function layout = layoutFromMdoc(mdocInfo)
% LAYOUTFROMMDOC - Turn the parsed tile records into the layout contract.

tiles = mdocInfo.tiles;
pieceX = arrayfun(@(t) t.pieceXYZ(1), tiles)';
pieceY = arrayfun(@(t) t.pieceXYZ(2), tiles)';
pieceZ = arrayfun(@(t) t.pieceXYZ(3), tiles)';
pieceZ(~isfinite(pieceZ)) = 0;

% MRC rows run bottom-up and ImodLoader flips them, so the row axis is the
% NEGATED piece Y. Normalising to a minimum of 1 afterwards is what makes the
% montage's overall height irrelevant - only relative placement matters.
[originRow, originCol] = montageToImageFrame(pieceY, pieceX);

% Distinct section coordinates become zLayer 1..K, matching the position-file
% source. One [MontSection] montage yields a single layer for every tile.
uniqueZ = sort(unique(pieceZ));
zLayerMap = dictionary(uniqueZ, (1:numel(uniqueZ))');

% Row/column indices from the placement itself: the piece coordinates are a
% regular grid, and the mirror has already reversed the row order.
gridRow = rankOf(originRow);
gridCol = rankOf(originCol);

% Order by grid position so tile numbering in the preview reads row by row.
[~, sortOrder] = sortrows([gridRow, gridCol]);

numTiles = numel(tiles);
layout(numTiles) = struct('index', 0, 'filename', '', 'sliceFiles', {{}}, ...
    'sliceIndex', 0, 'zLayer', 1, 'gridRC', [0 0], 'nomOrigin', [0 0 0], ...
    'tileSize', [0 0 0 0], 'dataClass', '', 'pixSize', []);

% The montage's own scale, so the stitched dataset inherits it instead of
% defaulting to 1 um. Z is the in-plane size: a montage is one section and the
% .mdoc records no section thickness, so an isotropic guess is the honest one -
% it at least keeps XY correct, which is what measurements on a montage use.
tilePixSize = struct('x', mdocInfo.pixelSizeUm, 'y', mdocInfo.pixelSizeUm, ...
    'z', mdocInfo.pixelSizeUm, 'units', 'um');

for outIdx = 1:numTiles
    tileIdx = sortOrder(outIdx);
    layout(outIdx).index      = outIdx;
    layout(outIdx).filename   = mdocInfo.imagePath;
    layout(outIdx).sliceFiles = {};
    % Every tile is a slice of the one container; ZValue is 0-based.
    layout(outIdx).sliceIndex = tiles(tileIdx).zValue + 1;
    layout(outIdx).zLayer     = zLayerMap(pieceZ(tileIdx));
    layout(outIdx).gridRC     = [gridRow(tileIdx), gridCol(tileIdx)];
    layout(outIdx).nomOrigin  = [originRow(tileIdx), originCol(tileIdx), ...
                                 zLayerMap(pieceZ(tileIdx))];
    layout(outIdx).tileSize   = [mdocInfo.tileHeight, mdocInfo.tileWidth, 1, 1];
    layout(outIdx).dataClass  = mdocInfo.dataClass;
    layout(outIdx).pixSize    = tilePixSize;
end

end

% =========================================================================
function edges = edgesFromMdoc(mdocInfo, layout)
% EDGESFROMMDOC - Convert SerialEM's per-piece edge shifts into the edge contract.
%
% Each piece records the seam to its neighbour at the next higher X
% (``XedgeDxy``) and next higher Y (``YedgeDxy``), so the last column and last row
% carry none. See the sign convention in the function help.

tiles = mdocInfo.tiles;
pieceX = arrayfun(@(t) t.pieceXYZ(1), tiles)';
pieceY = arrayfun(@(t) t.pieceXYZ(2), tiles)';
pieceZ = arrayfun(@(t) t.pieceXYZ(3), tiles)';
pieceZ(~isfinite(pieceZ)) = 0;

% tiles() order -> layout() order (layoutFromMdoc sorted by grid position).
layoutIndexOf = zeros(numel(tiles), 1);
sliceIndices  = [layout.sliceIndex];
for tileIdx = 1:numel(tiles)
    layoutIndexOf(tileIdx) = find(sliceIndices == tiles(tileIdx).zValue + 1, 1);
end

edges = emptyEdges();

for tileIdx = 1:numel(tiles)
    for directionIdx = 1:2
        if directionIdx == 1
            edgeShift = tiles(tileIdx).xEdge;
            directionName = 'x';
            sameLine  = pieceY == pieceY(tileIdx) & pieceZ == pieceZ(tileIdx);
            advancing = pieceX;
        else
            edgeShift = tiles(tileIdx).yEdge;
            directionName = 'y';
            sameLine  = pieceX == pieceX(tileIdx) & pieceZ == pieceZ(tileIdx);
            advancing = pieceY;
        end
        if any(~isfinite(edgeShift)); continue; end

        % The neighbour is the nearest piece further along this axis.
        candidates = find(sameLine & advancing > advancing(tileIdx));
        if isempty(candidates); continue; end
        [~, nearest] = min(advancing(candidates));
        neighbourTile = candidates(nearest);

        tileI = layoutIndexOf(tileIdx);
        tileJ = layoutIndexOf(neighbourTile);
        if tileI == tileJ; continue; end

        nominal = layout(tileJ).nomOrigin - layout(tileI).nomOrigin;
        % [dx dy] of the LOWER piece in the montage frame -> [row col] offset to
        % add to the nominal step. The row sign flips twice (edge convention,
        % then the Y mirror) and comes back positive.
        measured = nominal + [edgeShift(2), -edgeShift(1), 0];

        % Every other producer of edges emits i < j; keep that invariant so the
        % solver, the seam scorer and the inspector see the familiar orientation.
        if tileI > tileJ
            [tileI, tileJ] = deal(tileJ, tileI);
            nominal  = -nominal;
            measured = -measured;
        end

        newEdge = emptyEdges();
        newEdge(1).i         = tileI;
        newEdge(1).j         = tileJ;
        newEdge(1).direction = directionName;
        newEdge(1).nominal   = nominal;
        newEdge(1).measured  = measured;
        % SerialEM records no per-seam confidence, so nothing here can be graded.
        % scoreSeams checks the placement against the pixels afterwards.
        newEdge(1).quality   = 1;
        newEdge(1).valid     = true;
        newEdge(1).tform     = [];
        newEdge(1).source    = 'auto';
        newEdge(1).seamScore = [];
        newEdge(1).dzHint    = 0;

        edges(end + 1) = newEdge; %#ok<AGROW>
    end
end

end

% =========================================================================
function positions = positionsFromMdoc(mdocInfo, layout)
% POSITIONSFROMMDOC - Read SerialEM's final solved tile positions.

tiles = mdocInfo.tiles;
numTiles = numel(layout);
sliceIndices = [layout.sliceIndex];

alignedX = nan(numTiles, 1);
alignedY = nan(numTiles, 1);
for tileIdx = 1:numel(tiles)
    layoutIndex = find(sliceIndices == tiles(tileIdx).zValue + 1, 1);
    if isempty(layoutIndex); continue; end
    alignedX(layoutIndex) = tiles(tileIdx).alignedXYZ(1);
    alignedY(layoutIndex) = tiles(tileIdx).alignedXYZ(2);
end

if all(isnan(alignedX))
    error('utils:stitch:buildLayoutMdoc:noSolvedPositions', ...
        'No AlignedPieceCoords found in %s', mdocInfo.file);
end

% Same mirror as the nominal origins, so the two frames stay comparable.
[positionRow, positionCol] = montageToImageFrame(alignedY, alignedX);

% A tile SerialEM did not place stays where the nominal grid put it - the same
% treatment the global solver gives a tile with no valid measurement.
nominalOrigins = reshape([layout.nomOrigin], 3, []).';
unplaced = isnan(positionRow) | isnan(positionCol);
positionRow(unplaced) = nominalOrigins(unplaced, 1);
positionCol(unplaced) = nominalOrigins(unplaced, 2);

positions = [positionRow, positionCol, nominalOrigins(:, 3)];

end

% =========================================================================
function [originRow, originCol] = montageToImageFrame(montageY, montageX)
% MONTAGETOIMAGEFRAME - Montage (X right, Y up) -> image (col right, row down).
% Rows are the NEGATED montage Y because ImodLoader flips the MRC vertically on
% load. Both axes are then normalised to a minimum of 1, which is why the
% montage's overall size never enters the arithmetic.
originRow = -montageY(:);
originCol =  montageX(:);
originRow = originRow - min(originRow, [], 'omitnan') + 1;
originCol = originCol - min(originCol, [], 'omitnan') + 1;
end

% =========================================================================
function ranks = rankOf(values)
% RANKOF - 1-based index of each value among the sorted distinct values.
[~, ~, ranks] = unique(round(values(:)));
end

% =========================================================================
function padded = padTo3(values)
% PADTO3 - First three elements of a parsed value list, NaN-padded.
padded = [NaN NaN NaN];
count = min(3, numel(values));
padded(1:count) = values(1:count);
end

% =========================================================================
function padded = padTo2(values)
% PADTO2 - First two elements of a parsed value list, NaN-padded.
padded = [NaN NaN];
count = min(2, numel(values));
padded(1:count) = values(1:count);
end

% =========================================================================
function edges = emptyEdges()
% EMPTYEDGES - One-element template carrying every field the pipeline expects.
edges = struct('i', 0, 'j', 0, 'direction', 'x', 'nominal', [0 0 0], ...
    'measured', [0 0 0], 'quality', 0, 'valid', false, 'tform', [], ...
    'source', 'auto', 'seamScore', [], 'dzHint', 0);
edges(1) = [];
end
