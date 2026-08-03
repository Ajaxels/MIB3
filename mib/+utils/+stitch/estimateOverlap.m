function [result, cancelled] = estimateOverlap(layout, options)
% ESTIMATEOVERLAP - Estimate the true grid overlap from the tile images themselves.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = utils.stitch.estimateOverlap(layout)
%      result = utils.stitch.estimateOverlap(layout, options)
%
% The user-supplied overlap percentage is often only a guess; the pairwise
% measurement stage tolerates jitter around the nominal positions but not a
% systematically wrong overlap. This function recovers the actual overlap
% MIST-style, exploiting grid redundancy:
%
%   1. Neighbour pairs are taken from the grid structure (``.gridRC``), NOT from
%      the (possibly wrong) nominal origins.
%   2. Each sampled pair is registered by UNRESTRICTED full-tile phase
%      correlation (zero-padded to twice the tile size, so no shift aliases).
%      The top-K correlation peaks are each verified by normalised
%      cross-correlation of the overlap they imply; the best verified candidate
%      wins (BigStitcher-style peak verification).
%   3. In a regular grid every x-pair shares the same true step (up to jitter),
%      so the MEDIAN over pairs is a robust step estimate even when individual
%      pairs mismeasure.
%
% Large tiles are downsampled to ``options.maxDim`` for speed; the resulting
% step estimate is coarse (a few px), which is fine — it only repositions the
% nominal layout for the subsequent tight measurement pass.
%
% Input Arguments:
%   - **layout** — [struct array] tile layout with valid ``.gridRC`` fields
%     (grid layout source); see :func:`utils.stitch.buildLayoutGrid`.
%   - **options** *(optional)* — struct with fields:
%
%     - ``.maxPairsPerDirection`` — [double] pairs to sample per direction (default: ``6``)
%     - ``.topK`` — [double] correlation peaks to verify per pair (default: ``5``)
%     - ``.maxDim`` — [double] downsample tiles above this size (default: ``1024``)
%     - ``.minNcc`` — [double] minimum verification NCC to accept a pair (default: ``0.20``)
%     - ``.minOverlapPx`` — [double] minimum implied overlap extent (default: ``16``)
%     - ``.colorChannel`` — [double|'max'] channel used for registration (default: ``1``)
%     - ``.showWaitbar`` — [logical] show a Cancelable progress dialog (default: ``false``);
%       reading full-resolution tiles for the sampled pairs can take a noticeable time
%     - ``.parentFigure`` — [handle] parent for the progress dialog (default: ``[]``)
%
% Output Arguments:
%   - **result** — [struct] with fields:
%
%     - ``.overlapX`` / ``.overlapY`` — [double] estimated overlap in percent, NaN when
%       the direction could not be estimated (no pairs / no verified measurement)
%     - ``.stepX`` / ``.stepY`` — [1x2 double] median measured step ``[dy dx]`` per direction
%     - ``.madX`` / ``.madY`` — [double] median absolute deviation of the step estimates (px)
%     - ``.numMeasuredX`` / ``.numMeasuredY`` — [double] verified pairs per direction
%   - **cancelled** — [logical] ``true`` when the user pressed Cancel on the progress
%     dialog before every sampled pair was measured; ``result`` is then returned at its
%     all-NaN/zero defaults (a cancelled estimate is discarded, not a partial one).
%
% **Example** — recover the overlap for a grid built with a wrong guess:
%
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutGrid(files, wrongGridOpts);
%      est = utils.stitch.estimateOverlap(layout);
%      gridOpts.overlapX = est.overlapX;  % rebuild layout with the real overlap

if nargin < 2; options = struct(); end
if ~isfield(options, 'maxPairsPerDirection'); options.maxPairsPerDirection = 6; end
if ~isfield(options, 'topK');         options.topK = 5; end
if ~isfield(options, 'maxDim');       options.maxDim = 1024; end
if ~isfield(options, 'minNcc');       options.minNcc = 0.20; end
if ~isfield(options, 'minOverlapPx'); options.minOverlapPx = 16; end
if ~isfield(options, 'colorChannel'); options.colorChannel = 1; end
if ~isfield(options, 'showWaitbar');  options.showWaitbar = false; end
if ~isfield(options, 'parentFigure'); options.parentFigure = []; end

result = struct('overlapX', NaN, 'overlapY', NaN, ...
    'stepX', [NaN NaN], 'stepY', [NaN NaN], 'madX', NaN, 'madY', NaN, ...
    'numMeasuredX', 0, 'numMeasuredY', 0);
cancelled = false;

if numel(layout) < 2 || ~isfield(layout, 'gridRC'); return; end

% ---- collect grid-adjacent pairs from gridRC (nominal-independent) --------
gridRows = reshape([layout.gridRC], 2, [])';
xPairs = zeros(0, 2);   % [i j]: same row, col+1
yPairs = zeros(0, 2);   % [i j]: same col, row+1
for i = 1:numel(layout)
    jx = find(gridRows(:, 1) == gridRows(i, 1) & gridRows(:, 2) == gridRows(i, 2) + 1, 1);
    if ~isempty(jx); xPairs(end+1, :) = [i, jx]; end %#ok<AGROW>
    jy = find(gridRows(:, 1) == gridRows(i, 1) + 1 & gridRows(:, 2) == gridRows(i, 2), 1);
    if ~isempty(jy); yPairs(end+1, :) = [i, jy]; end %#ok<AGROW>
end
xPairs = samplePairs(xPairs, options.maxPairsPerDirection);
yPairs = samplePairs(yPairs, options.maxPairsPerDirection);

readerFcn = utils.stitch.makeTileReader(layout);
tileH = layout(1).tileSize(1);
tileW = layout(1).tileSize(2);
downFactor = max(1, ceil(max(tileH, tileW) / options.maxDim));

% ---- measure both directions ----------------------------------------------
% Reading full-resolution tiles for each sampled pair can take a noticeable
% time for large files — show progress (one step per pair, across both
% directions) so the app does not look frozen, and let the user cancel out.
totalPairs = size(xPairs, 1) + size(yPairs, 1);
progressDialog = [];
if options.showWaitbar && ~isempty(options.parentFigure) && totalPairs > 0
    progressDialog = uiprogressdlg(options.parentFigure, 'Value', 0, 'Cancelable', 'on', ...
        'Message', 'Estimating tile overlap...', 'Title', 'Stitching');
end

doneSoFar = 0;
stepsY = zeros(0, 2);
[stepsX, result.numMeasuredX, doneSoFar, cancelled] = ...
    measureDirection(xPairs, readerFcn, downFactor, options, progressDialog, doneSoFar, totalPairs);
if ~cancelled
    [stepsY, result.numMeasuredY, doneSoFar, cancelled] = ...
        measureDirection(yPairs, readerFcn, downFactor, options, progressDialog, doneSoFar, totalPairs); %#ok<ASGLU>
end

if ~isempty(progressDialog) && isvalid(progressDialog)
    close(progressDialog);
end

if cancelled
    % A cancelled estimate is discarded outright, not applied partially — the
    % caller (runOverlapEstimation) checks this flag and leaves BatchOpt
    % untouched, exactly as if Estimate overlap had never run.
    result.numMeasuredX = 0;
    result.numMeasuredY = 0;
    return;
end

if result.numMeasuredX > 0
    result.stepX = median(stepsX, 1);
    result.madX  = max(median(abs(stepsX - result.stepX), 1));
    result.overlapX = (tileW - result.stepX(2)) / tileW * 100;
end
if result.numMeasuredY > 0
    result.stepY = median(stepsY, 1);
    result.madY  = max(median(abs(stepsY - result.stepY), 1));
    result.overlapY = (tileH - result.stepY(1)) / tileH * 100;
end
end

% =========================================================================
function pairs = samplePairs(pairs, maxPairs)
% SAMPLEPAIRS - Evenly sample at most maxPairs rows.
if size(pairs, 1) > maxPairs
    pickIdx = round(linspace(1, size(pairs, 1), maxPairs));
    pairs = pairs(pickIdx, :);
end
end

% =========================================================================
function [steps, numMeasured, doneSoFar, cancelled] = measureDirection(pairs, readerFcn, downFactor, options, progressDialog, doneSoFar, totalPairs)
% MEASUREDIRECTION - Full-tile registration of each pair; returns verified steps [dy dx].
%
% progressDialog is [] when no dialog is shown; doneSoFar/totalPairs track
% progress across BOTH directions (X then Y), since the caller shares one
% dialog for the whole estimate. Cancel is checked before each pair (one
% blocking tile-read + correlation), so a click takes effect at the next pair
% boundary, not mid-pair; remaining pairs in this direction are then skipped.
steps = zeros(0, 2);
cancelled = false;
for k = 1:size(pairs, 1)
    if ~isempty(progressDialog) && isvalid(progressDialog) && progressDialog.CancelRequested
        cancelled = true;
        numMeasured = size(steps, 1);
        return;
    end
    tileA = prepareTile(readerFcn(pairs(k, 1)), downFactor, options.colorChannel);
    tileB = prepareTile(readerFcn(pairs(k, 2)), downFactor, options.colorChannel);
    offset = registerFullTiles(tileA, tileB, options);
    if ~any(isnan(offset))
        steps(end+1, :) = offset * downFactor; %#ok<AGROW>
    end
    doneSoFar = doneSoFar + 1;
    if ~isempty(progressDialog) && isvalid(progressDialog)
        progressDialog.Value = doneSoFar / totalPairs;
    end
end
numMeasured = size(steps, 1);
end

% =========================================================================
function img = prepareTile(img, downFactor, colorChannel)
% PREPARETILE - Single-channel 2D single-precision tile, optionally downsampled.
if size(img, 4) > 1
    if ischar(colorChannel) || isstring(colorChannel)
        img = max(img, [], 4);
    else
        img = img(:, :, :, min(max(round(colorChannel), 1), size(img, 4)));
    end
end
if size(img, 3) > 1
    img = mean(single(img), 3);
end
img = single(img(:, :, 1));
if downFactor > 1
    img = imresize(img, 1 / downFactor, 'bilinear');
end
end

% =========================================================================
function offset = registerFullTiles(tileA, tileB, options)
% REGISTERFULLTILES - Unrestricted phase correlation with top-K NCC verification.
%
% Returns offset = P_j - P_i (= position of tile B minus tile A) as [dy dx],
% or [NaN NaN] when no candidate passes verification.
% NO Hann window here — deliberate. For small overlaps the shared content sits
% at the tile EDGES, exactly where a window crushes the signal to zero (found
% empirically: windowed full-tile correlation has no peak at the true shift at
% all). Zero-padding already prevents circular aliasing; the boundary-step
% artifacts this leaves land mostly on the axes and are rejected by the NCC
% verification below (BigStitcher takes the same approach).
[H, W] = size(tileA);
paddedA = zeros(2 * H, 2 * W, 'single');
paddedB = zeros(2 * H, 2 * W, 'single');
paddedA(1:H, 1:W) = tileA - mean(tileA(:));
paddedB(1:H, 1:W) = tileB - mean(tileB(:));

crossPower = fft2(paddedA) .* conj(fft2(paddedB));
magnitude  = abs(crossPower);
magnitude(magnitude < eps('single')) = 1;
surface = real(ifft2(crossPower ./ magnitude));

% Top-K peaks with an exclusion window around each accepted peak
exclusionRadius = 9;
bestNcc = -Inf;
offset = [NaN, NaN];
searchSurface = surface;
minOverlapPx = max(8, round(options.minOverlapPx / 2));   % relative to (possibly downsampled) tiles
for peakIdx = 1:options.topK
    [~, linearIdx] = max(searchSurface(:));
    [peakRow, peakCol] = ind2sub(size(surface), linearIdx);
    % suppress this peak's neighbourhood for the next iteration
    rowRange = mod((peakRow - exclusionRadius:peakRow + exclusionRadius) - 1, size(surface, 1)) + 1;
    colRange = mod((peakCol - exclusionRadius:peakCol + exclusionRadius) - 1, size(surface, 2)) + 1;
    searchSurface(rowRange, colRange) = -Inf;

    % wrapped index -> signed raw shift. With B(r,c) = A(r+dy, c+dx) for
    % d = P_j - P_i, the raw peak of Fa.*conj(Fb) sits at d directly
    % (verified against ground truth; note this is the OPPOSITE composition
    % to the crop-based path in measureAllPairs, where crop starts differ).
    rawShift = [wrapIndex(peakRow, size(surface, 1)), wrapIndex(peakCol, size(surface, 2))];
    candidate = rawShift;

    ncc = overlapNcc(tileA, tileB, candidate, minOverlapPx);
    if ncc > bestNcc && ncc >= options.minNcc
        bestNcc = ncc;
        offset = candidate;
    end
end
end

% =========================================================================
function ncc = overlapNcc(tileA, tileB, offset, minOverlapPx)
% OVERLAPNCC - Normalised cross-correlation of the overlap implied by offset.
%
% Tile A sits at (0,0), tile B at offset [dy dx]. Shared region in A coordinates:
% rows max(1, 1+dy) : min(H, H+dy), cols likewise.
[H, W] = size(tileA);
dy = offset(1); dx = offset(2);
rowStartA = max(1, 1 + dy);  rowEndA = min(H, H + dy);
colStartA = max(1, 1 + dx);  colEndA = min(W, W + dx);
if (rowEndA - rowStartA + 1) < minOverlapPx || (colEndA - colStartA + 1) < minOverlapPx
    ncc = -Inf;
    return;
end
regionA = tileA(rowStartA:rowEndA, colStartA:colEndA);
regionB = tileB(rowStartA - dy:rowEndA - dy, colStartA - dx:colEndA - dx);
regionA = regionA(:) - mean(regionA(:));
regionB = regionB(:) - mean(regionB(:));
denominator = norm(regionA) * norm(regionB);
if denominator < eps
    ncc = -Inf;
else
    ncc = (regionA' * regionB) / denominator;
end
end

% =========================================================================
function shift = wrapIndex(idx, n)
shift = idx - 1;
if shift > floor(n / 2); shift = shift - n; end
end
