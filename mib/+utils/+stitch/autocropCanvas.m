function canvas = autocropCanvas(layout, canvas)
% AUTOCROPCANVAS - Shrink a planned canvas to the region every slice fully covers.
%
% Syntax:
%   .. code-block:: matlab
%
%      canvas = utils.stitch.autocropCanvas(layout, canvas)
%
% Solved tile positions are never a perfect rectangle: the outer tiles end up a
% few pixels apart, so the mosaic carries a ragged background frame along all
% four sides. This trims it away by replacing the canvas with the LARGEST
% axis-aligned rectangle that is covered by tiles on EVERY output slice, and
% re-expressing the placement plan in the cropped frame. Both fusers then produce
% the cropped mosaic directly - nothing is fused and thrown away, so the
% streaming path benefits identically to the in-memory one.
%
% The crop is in-plane only. Z is left alone: an output slice is either produced
% or it is not, and dropping end slices would silently change the depth of a
% stack the user asked for. Slices no tile reaches at all are SKIPPED rather than
% intersected in - an empty slice would otherwise veto every crop.
%
% **How the rectangle is found.** Every tile footprint is a rectangle in canvas
% coordinates, so coverage is piecewise-constant on the grid formed by the
% footprint edges: at most ``2N+2`` distinct rows and columns for ``N`` tiles,
% whatever the mosaic's pixel size. Coverage is evaluated on that compressed grid
% (once per distinct Z-segment - the contributing tile set and the ``zShifts``
% correction only change at tile-band boundaries), intersected across segments,
% and the maximum-area all-covered rectangle is read off with the
% largest-rectangle-in-histogram stack algorithm weighted by the cell sizes. The
% result is exact in pixels; no coverage mask the size of the mosaic is ever
% allocated.
%
% **Warped (affine) plans** use a CONSERVATIVE footprint: the affine image of a
% tile is a parallelogram, and the axis-aligned rectangle spanned by its middle
% two corner x-coordinates and middle two y-coordinates is inscribed in it. One
% further pixel is trimmed off each side because ``imwarp`` blends the outermost
% resampled row against the zero fill. Under-claiming coverage can only leave a
% slightly smaller mosaic; over-claiming would put back the black edge this
% exists to remove. Tiles whose transform is an integer translation take the
% exact rectangle, so a translation plan crops identically with or without
% ``canvas.tforms``.
%
% Input Arguments:
%   - **layout** — [struct array] tile layout (``.tileSize``).
%   - **canvas** — [struct] from :func:`utils.stitch.planCanvas`.
%
% Output Arguments:
%   - **canvas** — [struct] same fields, with ``.size(1:2)``, ``.tilePlacement``,
%     ``.boundingBox`` and (when present) ``.tforms`` / ``.tileBounds`` moved into
%     the cropped frame, plus:
%
%     - ``.cropRect`` — [1x4] ``[y0 y1 x0 x1]`` of the kept region in the
%       ORIGINAL canvas frame. Absent when no fully covered region exists (the
%       canvas is then returned untouched and a warning is issued).
%
% **Example** — plan and crop:
%
%   .. code-block:: matlab
%
%      canvas = utils.stitch.planCanvas(layout, positions);
%      canvas = utils.stitch.autocropCanvas(layout, canvas);
%      fprintf('kept %d x %d\n', canvas.size(1), canvas.size(2));

nTiles = numel(layout);
if nTiles == 0; return; end

H = canvas.size(1);
W = canvas.size(2);
Z = canvas.size(3);
placement = canvas.tilePlacement;

tileSizes = reshape([layout.tileSize], 4, nTiles)';   % N x 4 [H W D C]
tileH = tileSizes(:, 1);
tileW = tileSizes(:, 2);
tileD = tileSizes(:, 3);

hasTforms = isfield(canvas, 'tforms') && ~isempty(canvas.tforms);

% ---- per-tile footprint in canvas coordinates, before any per-slice shift ----
baseRect = zeros(nTiles, 4);        % [row0 row1 col0 col1]
for tileIdx = 1:nTiles
    if hasTforms && ~isIntegerTranslation(canvas.tforms{tileIdx})
        baseRect(tileIdx, :) = inscribedRect(double(canvas.tforms{tileIdx}), ...
            tileH(tileIdx), tileW(tileIdx));
    else
        baseRect(tileIdx, :) = [placement(tileIdx, 1), placement(tileIdx, 1) + tileH(tileIdx) - 1, ...
                                placement(tileIdx, 2), placement(tileIdx, 2) + tileW(tileIdx) - 1];
    end
end

% ---- Z-segments: where the contributing tile set or the slice shift changes ---
zStart = placement(:, 3);
zEnd   = zStart + tileD - 1;
hasZShifts = isfield(canvas, 'zShifts') && ~isempty(canvas.zShifts);

segmentStarts = [1; zStart(:); zEnd(:) + 1];
if hasZShifts
    shiftChanges = find(any(diff(canvas.zShifts, 1, 1) ~= 0, 2)) + 1;
    segmentStarts = [segmentStarts; shiftChanges(:)];
end
segmentStarts = unique(segmentStarts);
segmentStarts = segmentStarts(segmentStarts >= 1 & segmentStarts <= Z);

segmentRects = cell(numel(segmentStarts), 1);
keptSegments = 0;
for segmentIdx = 1:numel(segmentStarts)
    zGlobal = segmentStarts(segmentIdx);
    contributing = find(zGlobal >= zStart & zGlobal <= zEnd);
    if isempty(contributing); continue; end   % empty slice: cropping cannot help it

    sliceShift = [0, 0];
    if hasZShifts && zGlobal <= size(canvas.zShifts, 1)
        sliceShift = canvas.zShifts(zGlobal, :);
    end

    rects = baseRect(contributing, :) + ...
        [sliceShift(1), sliceShift(1), sliceShift(2), sliceShift(2)];
    % Clip to the canvas: the fusers do the same, so coverage outside is not real.
    rects(:, 1) = max(rects(:, 1), 1);
    rects(:, 2) = min(rects(:, 2), H);
    rects(:, 3) = max(rects(:, 3), 1);
    rects(:, 4) = min(rects(:, 4), W);
    rects = rects(rects(:, 1) <= rects(:, 2) & rects(:, 3) <= rects(:, 4), :);
    if isempty(rects); continue; end

    keptSegments = keptSegments + 1;
    segmentRects{keptSegments} = rects;
end
segmentRects = segmentRects(1:keptSegments);

if keptSegments == 0
    warning('utils:stitch:autocropCanvas:noCoverage', ...
        'Autocrop: no output slice is covered by any tile - the canvas is left uncropped.');
    return;
end

% ---- compressed coordinate grid: coverage is constant inside each cell --------
allRects = vertcat(segmentRects{:});
rowEdges = unique([1; allRects(:, 1); allRects(:, 2) + 1; H + 1]);
colEdges = unique([1; allRects(:, 3); allRects(:, 4) + 1; W + 1]);
nRowCells = numel(rowEdges) - 1;
nColCells = numel(colEdges) - 1;

covered = true(nRowCells, nColCells);
for segmentIdx = 1:keptSegments
    rects = segmentRects{segmentIdx};
    segmentCoverage = false(nRowCells, nColCells);
    for rectIdx = 1:size(rects, 1)
        rowRange = cellRange(rowEdges, rects(rectIdx, 1), rects(rectIdx, 2));
        colRange = cellRange(colEdges, rects(rectIdx, 3), rects(rectIdx, 4));
        segmentCoverage(rowRange, colRange) = true;
    end
    covered = covered & segmentCoverage;
    if ~any(covered, 'all'); break; end
end

if ~any(covered, 'all')
    warning('utils:stitch:autocropCanvas:noCommonRegion', ...
        ['Autocrop: no rectangle is covered by tiles on every output slice ' ...
         '(check for a gap in the layout) - the canvas is left uncropped.']);
    return;
end

% ---- largest all-covered rectangle, weighted by the compressed cell sizes -----
rowWeights = diff(rowEdges);
colWeights = diff(colEdges);
colPrefix  = [0; cumsum(colWeights)];

bestArea = 0;
bestRect = [];
columnHeights = zeros(nColCells, 1);
for rowIdx = 1:nRowCells
    columnHeights = (columnHeights + rowWeights(rowIdx)) .* covered(rowIdx, :)';
    [area, colFirst, colLast, height] = maxHistogramRect(columnHeights, colPrefix);
    if area > bestArea
        bestArea = area;
        bottomRow = rowEdges(rowIdx + 1) - 1;
        bestRect = [bottomRow - height + 1, bottomRow, ...
                    colEdges(colFirst), colEdges(colLast + 1) - 1];
    end
end

% ---- apply the crop ----------------------------------------------------------
cropY0 = bestRect(1); cropY1 = bestRect(2);
cropX0 = bestRect(3); cropX1 = bestRect(4);
canvas.cropRect = bestRect;
if cropY0 == 1 && cropY1 == H && cropX0 == 1 && cropX1 == W
    return;                      % already tight - nothing to move
end

newH = cropY1 - cropY0 + 1;
newW = cropX1 - cropX0 + 1;
canvas.size(1) = newH;
canvas.size(2) = newW;
canvas.tilePlacement(:, 1) = placement(:, 1) - (cropY0 - 1);
canvas.tilePlacement(:, 2) = placement(:, 2) - (cropX0 - 1);

if hasTforms
    for tileIdx = 1:nTiles
        shifted = double(canvas.tforms{tileIdx});
        shifted(1:2, 3) = shifted(1:2, 3) - [cropX0 - 1; cropY0 - 1];
        canvas.tforms{tileIdx} = shifted;
    end
    % tileBounds were already clipped to the OLD canvas; the crop is a subset of
    % it, so shifting and re-clipping gives the same answer as clipping the true
    % footprint to the cropped canvas. A tile left entirely outside comes out
    % with y1 < y0, which fuseSliceComposite skips.
    bounds = canvas.tileBounds - [cropY0 - 1, cropY0 - 1, cropX0 - 1, cropX0 - 1];
    bounds(:, 1) = max(bounds(:, 1), 1);
    bounds(:, 2) = min(bounds(:, 2), newH);
    bounds(:, 3) = max(bounds(:, 3), 1);
    bounds(:, 4) = min(bounds(:, 4), newW);
    canvas.tileBounds = bounds;
end

pixSize = canvas.pixSize;
canvas.boundingBox = [0, (newW - 1) * pixSize.x, ...
                      0, (newH - 1) * pixSize.y, ...
                      0, (Z - 1) * pixSize.z];
end

% =====================================================================
function rect = inscribedRect(tformMatrix, tileHeight, tileWidth)
% INSCRIBEDRECT - Conservative axis-aligned rectangle inside a warped tile.
%
% The affine image of a rectangle is a parallelogram; the box spanned by the
% middle two corner x-coordinates and the middle two corner y-coordinates lies
% inside it. One pixel is trimmed off each side on top of that, because imwarp
% blends the outermost resampled row/column against its zero fill value.
corners = tformMatrix(1:2, 1:2) * ...
    [1, tileWidth, 1, tileWidth; ...
     1, 1, tileHeight, tileHeight] + tformMatrix(1:2, 3);
sortedX = sort(corners(1, :));
sortedY = sort(corners(2, :));
rect = [ceil(sortedY(2)) + 1, floor(sortedY(3)) - 1, ...
        ceil(sortedX(2)) + 1, floor(sortedX(3)) - 1];
end

% =====================================================================
function tf = isIntegerTranslation(tformMatrix)
% ISINTEGERTRANSLATION - True for a whole-pixel pure translation, i.e. a tile
% that fuseSliceComposite places without resampling (same test it applies).
tformMatrix = double(tformMatrix);
tf = max(abs(tformMatrix(1:2, 1:2) - eye(2)), [], 'all') < 1e-9 && ...
     max(abs(tformMatrix(1:2, 3) - round(tformMatrix(1:2, 3)))) < 1e-3;
end

% =====================================================================
function cellIndices = cellRange(edges, firstPixel, lastPixel)
% CELLRANGE - Compressed-grid cell indices spanned by a pixel range. Both
% boundaries are members of `edges` by construction, so the range is exact.
firstCell = find(edges == firstPixel, 1);
lastCell  = find(edges == lastPixel + 1, 1) - 1;
cellIndices = firstCell:lastCell;
end

% =====================================================================
function [bestArea, bestFirst, bestLast, bestHeight] = maxHistogramRect(heights, colPrefix)
% MAXHISTOGRAMRECT - Largest-area rectangle under a histogram whose bars have
% unequal widths (stack algorithm; colPrefix is the cumulative width, so the
% total width of bars first..last is colPrefix(last+1) - colPrefix(first)).
nBars = numel(heights);
stack = zeros(nBars + 1, 1);
stackTop = 0;
bestArea = 0; bestFirst = 1; bestLast = 0; bestHeight = 0;

for barIdx = 1:(nBars + 1)
    if barIdx <= nBars
        currentHeight = heights(barIdx);
    else
        currentHeight = 0;               % sentinel: flush the stack
    end
    while stackTop > 0 && heights(stack(stackTop)) >= currentHeight
        poppedHeight = heights(stack(stackTop));
        stackTop = stackTop - 1;
        if stackTop > 0
            firstBar = stack(stackTop) + 1;
        else
            firstBar = 1;
        end
        lastBar = barIdx - 1;
        area = poppedHeight * (colPrefix(lastBar + 1) - colPrefix(firstBar));
        if poppedHeight > 0 && area > bestArea
            bestArea   = area;
            bestFirst  = firstBar;
            bestLast   = lastBar;
            bestHeight = poppedHeight;
        end
    end
    if barIdx <= nBars
        stackTop = stackTop + 1;
        stack(stackTop) = barIdx;
    end
end
end
