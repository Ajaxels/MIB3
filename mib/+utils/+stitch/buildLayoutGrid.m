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
%   - **filenames** — [cell] cell array of full-path character vectors for tile files
%   - **gridOptions** — struct with fields:
%
%     - ``.rows`` — [double] number of grid rows (0 = auto)
%     - ``.cols`` — [double] number of grid columns (0 = auto)
%     - ``.tileOrder`` — [char] one of ``'Horizontal'``, ``'Horizontal snake'``,
%       ``'Vertical'``, ``'Vertical snake'``
%     - ``.overlapX`` — [double] horizontal overlap in percent (0–90)
%     - ``.overlapY`` — [double] vertical overlap in percent (0–90)
%
% Output Arguments:
%   - **layout** — struct array with fields per contract:
%
%     - ``.index`` — [double] 1-based tile index
%     - ``.filename`` — [char] full path
%     - ``.sliceFiles`` — [cell] ``{}`` for single-file tiles
%     - ``.zLayer`` — [double] always ``1`` (single layer)
%     - ``.gridRC`` — [double] ``[row col]``
%     - ``.nomOrigin`` — [double] ``[y x z]`` 1-based pixel origins
%     - ``.tileSize`` — [double] ``[H W D C]``
%     - ``.dataClass`` — [char] MATLAB class string
%
% **Example** — 2x3 grid of TIF tiles with 10% overlap:
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

% Resolve rows/cols
numRows = gridOptions.rows;
numCols = gridOptions.cols;
if numRows == 0 && numCols == 0
    numRows = ceil(sqrt(numTiles));
    numCols = ceil(numTiles / numRows);
elseif numRows == 0
    numRows = ceil(numTiles / numCols);
elseif numCols == 0
    numCols = ceil(numTiles / numRows);
end

overlapX = gridOptions.overlapX;
overlapY = gridOptions.overlapY;
tileOrder = gridOptions.tileOrder;

% Read first tile dimensions
[tileHeight, tileWidth, tileDepth, tileColors, tileClass] = readTileSize(sortedFilenames{1});

% Step sizes (sub-pixel exact; origins are 1-based)
stepX = tileWidth  * (1 - overlapX / 100);
stepY = tileHeight * (1 - overlapY / 100);

% Assign (row, col) per tile index according to tileOrder
[rowAssign, colAssign] = assignGridPositions(numTiles, numRows, numCols, tileOrder);

% Build layout struct array
tileSize = [tileHeight, tileWidth, tileDepth, tileColors];
layout(numTiles) = struct('index', 0, 'filename', '', 'sliceFiles', {{}}, 'zLayer', 1, ...
    'gridRC', [0 0], 'nomOrigin', [0 0 0], 'tileSize', [0 0 0 0], 'dataClass', '');

for tileIdx = 1:numTiles
    row = rowAssign(tileIdx);
    col = colAssign(tileIdx);
    originY = (row - 1) * stepY + 1;
    originX = (col - 1) * stepX + 1;

    layout(tileIdx).index      = tileIdx;
    layout(tileIdx).filename   = sortedFilenames{tileIdx};
    layout(tileIdx).sliceFiles = {};
    layout(tileIdx).zLayer     = 1;
    layout(tileIdx).gridRC     = [row, col];
    layout(tileIdx).nomOrigin  = [originY, originX, 1];
    layout(tileIdx).tileSize   = tileSize;
    layout(tileIdx).dataClass  = tileClass;
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

% =========================================================================
function [tileHeight, tileWidth, tileDepth, tileColors, tileClass] = readTileSize(filename)
% Read tile dimensions from the first file using imfinfo fast path where possible.

[~, ~, extension] = fileparts(filename);
extension = lower(extension);

tileDepth  = 1;
tileColors = 1;
tileClass  = 'uint8';
tileHeight = 0;
tileWidth  = 0;

if ismember(extension, {'.tif', '.tiff', '.png', '.jpg', '.jpeg', '.bmp'})
    try
        info = imfinfo(filename);
        tileHeight = info(1).Height;
        tileWidth  = info(1).Width;
        tileDepth  = numel(info);
        if isfield(info(1), 'SamplesPerPixel')
            tileColors = info(1).SamplesPerPixel;
        end
        if isfield(info(1), 'BitDepth')
            bitDepth = info(1).BitDepth;
            if tileColors > 1
                bitDepth = bitDepth / tileColors;
            end
            if bitDepth <= 8
                tileClass = 'uint8';
            elseif bitDepth <= 16
                tileClass = 'uint16';
            else
                tileClass = 'single';
            end
        end
        return;
    catch
        % Fall through to loadImagesWrapper
    end
end

% General path via io.loadImagesWrapper
try
    loadOpts.silent = true;
    tileData = io.loadImagesWrapper(filename, loadOpts);
    if ~isempty(tileData)
        tileHeight = size(tileData, 1);
        tileWidth  = size(tileData, 2);
        tileDepth  = size(tileData, 3);
        tileColors = size(tileData, 4);
        tileClass  = class(tileData);
    end
catch
    warning('utils:stitch:buildLayoutGrid:cannotReadTile', ...
        'Cannot read tile size from %s; using defaults 256x256.', filename);
    tileHeight = 256;
    tileWidth  = 256;
end

end
