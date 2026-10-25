function [points, scores, rayDist, cancelled] = nms(prob, dist, grid, probThresh, nmsThresh, options)
% NMS - Non-maximum suppression of StarDist polygon candidates; returns one polygon per object.
%
% Syntax:
%   .. code-block:: matlab
%
%      [points, scores, rayDist] = deepmib.stardist.nms(prob, dist, grid, probThresh, nmsThresh)
%      [points, scores, rayDist, cancelled] = deepmib.stardist.nms(prob, dist, grid, probThresh, nmsThresh, options)
%
% Follows the dense path of StarDist 0.9.2 (``stardist.nms.non_maximum_suppression`` and
% ``c_non_max_suppression_inds`` in ``stardist2d.cpp``):
%
% 1. **Candidates**: grid cells with ``prob > probThresh``, excluding a border of 2 grid cells on
%    every side, sorted by probability, highest first. The centre of the cell at 1-based index
%    ``(i, j)`` is the pixel ``((i-1)*gRow, (j-1)*gCol)`` in 0-based coordinates (no offset).
% 2. **Greedy suppression**: each candidate, in that order, is kept unless it overlaps an
%    already kept polygon by more than ``nmsThresh``, where
%    ``overlap = intersection / min(areaCandidate, areaKept)`` - the intersection over the
%    **smaller** area, not the IoU. Kept polygons may overlap one another up to the threshold.
%
% Two implementations of step 2, chosen with ``options.method``:
%
% - ``'mex'`` - ``stardistMex`` (``mib/external/stardist``), StarDist's own C++
%   (``stardist2d.cpp`` with Clipper polygon clipping and a nanoflann kd-tree), built by
%   ``deployment/mib3_compile_c_files.m``.
%   Polygon vertices are truncated to integer coordinates before clipping, as in StarDist, so the
%   decisions equal StarDist's. Cancel is checked once before the call; the call itself can only be
%   interrupted with Ctrl+C.
% - ``'raster'`` - MATLAB fallback when the MEX file is missing (e.g. a platform it was not built
%   for). Polygon areas are the exact (shoelace) areas of the float polygons; the intersection is
%   counted on pixel centres: each candidate is rasterised once on its bounding box
%   (deepmib.stardist.starPolygonMask), every kept polygon's mask is cached, and only kept
%   polygons whose bounding box intersects the candidate's are tested, nearest centre first. On
%   the StarDist test set it disagrees with the C++ on 0-2 of up to 48 000 candidates, without a
%   visible change in the labels, but it is 7-16x slower than StarDist's multi-threaded C++.
%
% Candidates with equal probability are ordered by their position (column-major), which may
% differ from the order numpy's unstable ``argsort`` gives them.
%
% Input Arguments:
%   - **prob** - [single] probability map ``[h, w]`` at grid resolution, see
%     deepmib.stardist.predictMaps
%   - **dist** - [single] ray distances ``[h, w, nRays]`` in full-resolution pixels
%   - **grid** - [1x2 numeric] grid of the model, ``config.grid``
%   - **probThresh** - [numeric] probability threshold
%   - **nmsThresh** - [numeric] overlap threshold
%   - **options** *(optional)* - struct with fields:
%
%     - ``.progressDlg`` - [uiprogressdlg] dialog whose ``CancelRequested`` is checked before
%       the MEX call, or every 1000 candidates by the raster version; ``[]`` for none
%       (default: ``[]``)
%     - ``.method`` - [char] ``'auto'`` (the MEX when it exists, otherwise raster), ``'mex'`` or
%       ``'raster'`` (default: ``'auto'``)
%
% Output Arguments:
%   - **points** - [double] ``[n, 2]`` kept polygon centres ``[row col]``, 0-based pixels, by
%     decreasing score
%   - **scores** - [single] ``[n, 1]`` probabilities of the kept polygons
%   - **rayDist** - [double] ``[n, nRays]`` ray lengths of the kept polygons
%   - **cancelled** - [logical] ``true`` when the user pressed Cancel; the other outputs are
%     then empty
%
% **Example** - objects of one image, drawn into a label map:
%
%   .. code-block:: matlab
%
%      [prob, dist] = deepmib.stardist.predictMaps(net, x, config);
%      [points, scores, rayDist] = deepmib.stardist.nms(prob, dist, config.grid, config.probThresh, config.nmsThresh);
%      labels = deepmib.stardist.polygonsToLabel(points, rayDist, scores, size(x, [1 2]));

if nargin < 6; options = struct(); end
if ~isfield(options, 'progressDlg'); options.progressDlg = []; end
if ~isfield(options, 'method'); options.method = 'auto'; end
cancelled = false;
border = 2;
grid = reshape(grid, 1, 2);

% candidates
mask = prob > probThresh;
mask([1:min(border, end), max(end-border+1, 1):end], :) = false;
mask(:, [1:min(border, end), max(end-border+1, 1):end]) = false;
[rowIndex, colIndex] = find(mask);
nRays = size(dist, 3);
distFlat = reshape(dist, [], nRays);
[scores, order] = sort(prob(mask), 'descend');
rayDist = double(distFlat(mask(:), :));
rayDist = rayDist(order, :);
points = [rowIndex(order) - 1, colIndex(order) - 1] .* grid;

method = options.method;
if strcmp(method, 'auto')
    if exist('stardistMex', 'file') == 3; method = 'mex'; else; method = 'raster'; end
end
switch method
    case 'mex'
        if ~isempty(options.progressDlg) && options.progressDlg.CancelRequested
            points = []; scores = []; rayDist = []; cancelled = true;
            return;
        end
        keep = stardistMex('nms', single(rayDist), single(points), nmsThresh, true, true);
    case 'raster'
        [keep, cancelled] = suppressRaster(points, rayDist, nmsThresh, options.progressDlg);
        if cancelled
            points = []; scores = []; rayDist = [];
            return;
        end
    otherwise
        error('stardist:nms:method', 'Unknown method "%s"; use ''auto'', ''mex'' or ''raster''', method);
end
points = points(keep, :);
scores = scores(keep);
rayDist = rayDist(keep, :);
end

function [keep, cancelled] = suppressRaster(points, rayDist, nmsThresh, progressDlg)
% greedy suppression on pixel centres; candidates sorted by descending score
cancelled = false;
nCandidates = size(points, 1);
nRays = size(rayDist, 2);

% vertices, bounding boxes and areas of all candidates at once
phi = (0:nRays-1) * 2*pi / nRays;
vertexRow = points(:, 1) + rayDist .* sin(phi);
vertexCol = points(:, 2) + rayDist .* cos(phi);
bbox = [min(vertexRow, [], 2), max(vertexRow, [], 2), min(vertexCol, [], 2), max(vertexCol, [], 2)];
pixelBox = [ceil(bbox(:, 1)), floor(bbox(:, 2)), ceil(bbox(:, 3)), floor(bbox(:, 4))];
nextRow = circshift(vertexRow, -1, 2);
nextCol = circshift(vertexCol, -1, 2);
areas = 0.5 * abs(sum(vertexCol .* nextRow - nextCol .* vertexRow, 2)) + 1e-10;

keep = false(nCandidates, 1);
keptIds = zeros(nCandidates, 1);
keptMask = cell(nCandidates, 1);
nKept = 0;
for candId = 1:nCandidates
    if ~isempty(progressDlg) && mod(candId, 1000) == 0 && progressDlg.CancelRequested
        keep = []; cancelled = true;
        return;
    end
    keptSoFar = keptIds(1:nKept);
    hits = keptSoFar(bbox(keptSoFar, 1) <= bbox(candId, 2) & bbox(candId, 1) <= bbox(keptSoFar, 2) & ...
        bbox(keptSoFar, 3) <= bbox(candId, 4) & bbox(candId, 3) <= bbox(keptSoFar, 4));
    suppressed = false;
    candMask = [];
    if ~isempty(hits)
        [~, order] = sort(sum((points(hits, :) - points(candId, :)).^2, 2));
        for hitId = hits(order)'
            rowFrom = max(pixelBox(candId, 1), pixelBox(hitId, 1));
            rowTo = min(pixelBox(candId, 2), pixelBox(hitId, 2));
            colFrom = max(pixelBox(candId, 3), pixelBox(hitId, 3));
            colTo = min(pixelBox(candId, 4), pixelBox(hitId, 4));
            if rowFrom > rowTo || colFrom > colTo; continue; end
            if isempty(candMask)
                candMask = deepmib.stardist.starPolygonMask(points(candId, :), rayDist(candId, :), ...
                    pixelBox(candId, 1):pixelBox(candId, 2), pixelBox(candId, 3):pixelBox(candId, 4));
            end
            candWindow = candMask(rowFrom-pixelBox(candId, 1)+1 : rowTo-pixelBox(candId, 1)+1, ...
                colFrom-pixelBox(candId, 3)+1 : colTo-pixelBox(candId, 3)+1);
            keptWindow = keptMask{hitId}(rowFrom-pixelBox(hitId, 1)+1 : rowTo-pixelBox(hitId, 1)+1, ...
                colFrom-pixelBox(hitId, 3)+1 : colTo-pixelBox(hitId, 3)+1);
            if nnz(candWindow & keptWindow) / min(areas(candId), areas(hitId)) > nmsThresh
                suppressed = true;
                break;
            end
        end
    end
    if ~suppressed
        keep(candId) = true;
        nKept = nKept + 1;
        keptIds(nKept) = candId;
        if isempty(candMask)
            candMask = deepmib.stardist.starPolygonMask(points(candId, :), rayDist(candId, :), ...
                pixelBox(candId, 1):pixelBox(candId, 2), pixelBox(candId, 3):pixelBox(candId, 4));
        end
        keptMask{candId} = candMask;
    end
end
end
