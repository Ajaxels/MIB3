function layout = buildLayoutGrid(filenames, gridOptions)
% BUILDLAYOUTGRID - Build a tile layout struct from a rectangular grid specification.
%
% Syntax:
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutGrid(filenames, gridOptions)
%
% Tiles are natural-sorted before placement.  The first tile's pixel
% dimensions are read to compute nominal origins; all tiles are assumed
% to have the same size.
%
% Nominal origin formula (1-based pixels):
%   x = (col-1) * width  * (1 - overlapX/100) + 1
%   y = (row-1) * height * (1 - overlapY/100) + 1
%
% Input Arguments:
%   - **filenames** - [cell] cell array of full-path character vectors for tile files
%   - **gridOptions** - struct with fields:
%
%     - ``.rows`` - [double] number of grid rows (0 = auto)
%     - ``.cols`` - [double] number of grid columns (0 = auto)
%     - ``.tileOrder`` - [char] one of ``'Horizontal'``, ``'Horizontal snake'``,
%       ``'Vertical'``, ``'Vertical snake'``
%     - ``.overlapX`` - [double] horizontal overlap in percent (0-90)
%     - ``.overlapY`` - [double] vertical overlap in percent (0-90)
%
% Output Arguments:
%   - **layout** - struct array with fields per contract:
%
%     - ``.index`` - [double] 1-based tile index
%     - ``.filename`` - [char] full path
%     - ``.sliceFiles`` - [cell] ``{}`` for single-file tiles
%     - ``.zLayer`` - [double] always ``1`` (single layer)
%     - ``.gridRC`` - [double] ``[row col]``
%     - ``.nomOrigin`` - [double] ``[y x z]`` 1-based pixel origins
%     - ``.tileSize`` - [double] ``[H W D C]``
%     - ``.dataClass`` - [char] MATLAB class string
%
% **Example** - 2x3 grid of TIF tiles with 10% overlap:
%
%   .. code-block:: matlab
%
%      opts.rows = 2; opts.cols = 3;
%      opts.tileOrder = 'Horizontal'; opts.overlapX = 10; opts.overlapY = 10;
%      layout = utils.stitch.buildLayoutGrid(myFiles, opts);
%

arguments
    filenames   cell
    gridOptions struct
end

if isempty(filenames)
    layout = struct('index', {}, 'filename', {}, 'sliceFiles', {}, 'zLayer', {}, ...
        'gridRC', {}, 'nomOrigin', {}, 'tileSize', {}, 'dataClass', {});
    return;
end

% Natural sort first
sortedFilenames = utils.stitch.naturalSortFiles(filenames);
numTiles = numel(sortedFilenames);

% Each grid entry is either a single image file or a FOLDER holding the tile's
% Z-stack. Resolve every entry up front (utils.stitch.resolveTileEntry auto-
% detects which) so folder tiles carry their images in ``sliceFiles`` and their
% depth in tileSize(3).
tileSliceFiles = cell(numTiles, 1);
tileSizes      = cell(numTiles, 1);
tileClasses    = cell(numTiles, 1);
for tileIdx = 1:numTiles
    [tileSliceFiles{tileIdx}, tileSizes{tileIdx}, tileClasses{tileIdx}] = ...
        utils.stitch.resolveTileEntry(sortedFilenames{tileIdx});
end

% Resolve rows/cols
numRows = gridOptions.rows;
numCols = gridOptions.cols;
if numRows == 0 && numCols == 0
    % Auto grid: the divisor pair closest to square that tiles numTiles
    % EXACTLY. A ceil(sqrt(N)) grid leaves holes for non-rectangular counts
    % (3 tiles -> 2x2 with a gap), which breaks the neighbour graph: phantom
    % pairs across the hole measure garbage while the real neighbours are
    % never paired. The tile order states the preferred orientation: a
    % Vertical order gets the tall arrangement (3 tiles -> 3x1), Horizontal
    % the wide one (1x3).
    smallDim = floor(sqrt(numTiles));
    while mod(numTiles, smallDim) ~= 0
        smallDim = smallDim - 1;
    end
    if startsWith(gridOptions.tileOrder, 'Vertical')
        numRows = numTiles / smallDim;
        numCols = smallDim;
    else
        numRows = smallDim;
        numCols = numTiles / smallDim;
    end
elseif numRows == 0
    numRows = ceil(numTiles / numCols);
elseif numCols == 0
    numCols = ceil(numTiles / numRows);
end

overlapX = gridOptions.overlapX;
overlapY = gridOptions.overlapY;
tileOrder = gridOptions.tileOrder;

% Step sizes from the first tile's XY size (sub-pixel exact; origins 1-based).
tileHeight = tileSizes{1}(1);
tileWidth  = tileSizes{1}(2);
stepX = tileWidth  * (1 - overlapX / 100);
stepY = tileHeight * (1 - overlapY / 100);

% Assign (row, col) per tile index according to tileOrder
[rowAssign, colAssign] = assignGridPositions(numTiles, numRows, numCols, tileOrder);

% Build layout struct array
layout(numTiles) = struct('index', 0, 'filename', '', 'sliceFiles', {{}}, 'zLayer', 1, ...
    'gridRC', [0 0], 'nomOrigin', [0 0 0], 'tileSize', [0 0 0 0], 'dataClass', '');

for tileIdx = 1:numTiles
    row = rowAssign(tileIdx);
    col = colAssign(tileIdx);
    originY = (row - 1) * stepY + 1;
    originX = (col - 1) * stepX + 1;

    layout(tileIdx).index      = tileIdx;
    layout(tileIdx).filename   = sortedFilenames{tileIdx};
    layout(tileIdx).sliceFiles = tileSliceFiles{tileIdx};
    layout(tileIdx).zLayer     = 1;
    layout(tileIdx).gridRC     = [row, col];
    layout(tileIdx).nomOrigin  = [originY, originX, 1];
    layout(tileIdx).tileSize   = tileSizes{tileIdx};   % per-tile [H W D C]
    layout(tileIdx).dataClass  = tileClasses{tileIdx};
end

end

% =========================================================================
function [rowAssign, colAssign] = assignGridPositions(numTiles, numRows, numCols, tileOrder)
% Assign 1-based (row, col) to each tile in natural-sort order.

rowAssign = zeros(numTiles, 1);
colAssign = zeros(numTiles, 1);

switch tileOrder
    case 'Horizontal'
        % Left-to-right, top-to-bottom; row changes slowest
        for tileIdx = 1:numTiles
            linearIdx = tileIdx - 1;
            rowAssign(tileIdx) = floor(linearIdx / numCols) + 1;
            colAssign(tileIdx) = mod(linearIdx, numCols) + 1;
        end

    case 'Horizontal snake'
        % Left-to-right on even rows, right-to-left on odd rows
        for tileIdx = 1:numTiles
            linearIdx = tileIdx - 1;
            rowIdx = floor(linearIdx / numCols);
            colIdx = mod(linearIdx, numCols);
            if mod(rowIdx, 2) == 1
                % reverse direction on odd rows (0-indexed)
                colIdx = numCols - 1 - colIdx;
            end
            rowAssign(tileIdx) = rowIdx + 1;
            colAssign(tileIdx) = colIdx + 1;
        end

    case 'Vertical'
        % Top-to-bottom, left-to-right; col changes slowest
        for tileIdx = 1:numTiles
            linearIdx = tileIdx - 1;
            colAssign(tileIdx) = floor(linearIdx / numRows) + 1;
            rowAssign(tileIdx) = mod(linearIdx, numRows) + 1;
        end

    case 'Vertical snake'
        % Top-to-bottom on even cols, bottom-to-top on odd cols
        for tileIdx = 1:numTiles
            linearIdx = tileIdx - 1;
            colIdx = floor(linearIdx / numRows);
            rowIdx = mod(linearIdx, numRows);
            if mod(colIdx, 2) == 1
                rowIdx = numRows - 1 - rowIdx;
            end
            rowAssign(tileIdx) = rowIdx + 1;
            colAssign(tileIdx) = colIdx + 1;
        end

    otherwise
        error('utils:stitch:buildLayoutGrid:unknownTileOrder', ...
            'Unknown tileOrder: %s. Must be Horizontal, Horizontal snake, Vertical, or Vertical snake.', tileOrder);
end

end
