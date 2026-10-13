function sectionLayout = splitLayoutIntoSections(layout)
% SPLITLAYOUTINTOSECTIONS - Expand folder Z-stack tiles into one single-slice piece per section.
%
% Syntax:
%   .. code-block:: matlab
%
%      sectionLayout = utils.stitch.splitLayoutIntoSections(layout)
%
% For a serial-section montage written as **one folder per tile** - every
% folder holding that stage position's image of every section, slice ``s`` of
% every folder being section ``s`` - the stitcher must place every slice on its
% own: the stage lands slightly off on each section (backlash), so a folder is
% NOT a rigid, already-registered Z-stack. This turns each folder tile into one
% layout entry per slice, so the existing pipeline measures, solves and fuses
% the slices individually:
%
% - in-plane seams between the tiles of every section (``zLayer`` = section),
% - section-to-section seams between consecutive slices of the same folder
%   (cross-layer ``'z'`` pairs of two single-slice pieces, dz kept at 1 - see
%   :func:`utils.stitch.measureAllPairs`),
% - one joint solve, and a canvas one slice per section deep.
%
% Every piece keeps the folder in ``.filename`` - the tile's source entry, which
% is what the stitched dataset is named after and what a reloaded project
% restores ``InputPath`` from - and reads its single image through a
% one-element ``.sliceFiles``. Pieces are ordered SECTION-MAJOR: all tiles of
% section 1, then all of section 2, ...; within a section the folders keep
% their input order. ``.stageTile`` records the folder (input index) a piece
% came from, which :func:`utils.stitch.findNeighborPairs` uses to build the
% pairs directly instead of testing every pair of pieces.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout from any ``buildLayout*`` source.
%     Every entry must be a FOLDER tile (non-empty ``.sliceFiles``), all on ONE
%     ``zLayer``, all with the SAME number of slices.
%
% Output Arguments:
%   - **sectionLayout** - [struct array] ``numel(layout) x numSlices`` pieces,
%     each a copy of its folder's entry (optional fields such as ``.pixSize``
%     included) with:
%
%     - ``.index`` - [double] position in ``sectionLayout``
%     - ``.sliceFiles`` - [cell] the one image of that section
%     - ``.zLayer`` - [double] section number ``s``
%     - ``.nomOrigin`` - [double] the folder's ``[y x]``, z = folder z + ``s`` - 1
%     - ``.tileSize`` - [double] the folder's ``[H W 1 C]``
%     - ``.stageTile`` - [double] index of the folder in ``layout``
%
% Errors (identifiers ``utils:stitch:splitLayoutIntoSections:<id>``):
%   - ``notFolders`` - some tile is a single file (an image, or a multi-page
%     stack, which has no per-page reader yet)
%   - ``severalLayers`` - the folders sit on more than one ``zLayer``
%   - ``unequalSliceCounts`` - the folders hold different numbers of images;
%     the message lists every folder's count. Never truncated silently:
%     slice ``s`` would stop meaning section ``s``.
%
% **Example** - split a 2x2 grid of folder tiles:
%
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutGrid(tileFolders, gridOptions);
%      sectionLayout = utils.stitch.splitLayoutIntoSections(layout);
%      pairs = utils.stitch.findNeighborPairs(sectionLayout);
%

arguments
    layout struct
end

numTiles = numel(layout);
if numTiles == 0
    sectionLayout = layout;
    return;
end

isFolderTile = arrayfun(@(tile) ~isempty(tile.sliceFiles), layout);
if ~all(isFolderTile)
    firstFile = layout(find(~isFolderTile, 1)).filename;
    error('utils:stitch:splitLayoutIntoSections:notFolders', ...
        ['Registering slices needs every tile to be a folder of slice images, ' ...
         'but %s is a single file.'], firstFile);
end

if numel(unique([layout.zLayer])) > 1
    error('utils:stitch:splitLayoutIntoSections:severalLayers', ...
        ['Registering slices needs all tile folders on one Z-layer, ' ...
         'each folder holding every section.']);
end

sliceCounts = arrayfun(@(tile) numel(tile.sliceFiles), layout);
if any(sliceCounts ~= sliceCounts(1))
    countLines = arrayfun(@(tile, count) sprintf('  %s: %d', tile.filename, count), ...
        layout(:), sliceCounts(:), 'UniformOutput', false);
    error('utils:stitch:splitLayoutIntoSections:unequalSliceCounts', ...
        ['Registering slices needs the same number of images in every tile folder ' ...
         '(slice s of every folder is section s), but the counts differ:\n%s'], ...
        strjoin(countLines, newline));
end
numSlices = sliceCounts(1);

% The field must exist on the template before pieces carrying it are assigned in.
if ~isfield(layout, 'stageTile'); [layout.stageTile] = deal([]); end
sectionLayout = repmat(layout(1), 1, numTiles * numSlices);
pieceIdx = 0;
for slice = 1:numSlices
    for tileIdx = 1:numTiles
        pieceIdx = pieceIdx + 1;
        piece = layout(tileIdx);
        piece.index = pieceIdx;
        piece.sliceFiles = piece.sliceFiles(slice);
        piece.zLayer = slice;
        piece.nomOrigin(3) = piece.nomOrigin(3) + slice - 1;
        piece.tileSize(3) = 1;
        piece.stageTile = tileIdx;
        sectionLayout(pieceIdx) = piece;
    end
end
end
