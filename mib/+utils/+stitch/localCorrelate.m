function [newOffsetYX, score, confident, debugInfo] = localCorrelate(tileA, tileB, clickXY, currentOffsetYX, options)
% LOCALCORRELATE - Click-seeded local registration of a tile pair (ROI NCC).
%
% Syntax:
%   .. code-block:: matlab
%
%      [newOffsetYX, score, confident] = utils.stitch.localCorrelate(tileA, tileB, clickXY, currentOffsetYX)
%      [newOffsetYX, score, confident, debugInfo] = utils.stitch.localCorrelate(..., options)
%
% The seam inspector's "human picks WHERE, machine finds EXACTLY" tool (see
% ``development/stitching/plan_inspector.md``): the user clicks a distinctive
% spot in the overlap; a small ROI around the click is cut from tile A and
% matched by ``normxcorr2`` against tile B's neighbourhood of the corresponding
% location (within a search radius of the current offset). The NCC peak gives a
% corrected pair offset with subpixel (parabolic) refinement; the peak height
% and its prominence over the second-best peak gate a ``confident`` flag so a
% weak/ambiguous match never silently moves a tile.
%
% **Offset convention.** ``currentOffsetYX``/``newOffsetYX`` are the pair
% displacement ``positions(j,1:2) - positions(i,1:2)`` - tile-A pixel ``(r, c)``
% corresponds to tile-B pixel ``(r - dy, c - dx)`` (the solver/edge.measured
% convention).
%
% Input Arguments:
%   - **tileA** - [numeric] full tile ``i``, 2D or ``[H W D C]`` (depth is
%     mean-projected, channel selected per ``options.colorChannel``).
%   - **tileB** - [numeric] full tile ``j``, same conventions.
%   - **clickXY** - [1x2 double] ``[x y]`` click location in tile-A local pixels.
%   - **currentOffsetYX** - [1x2 double] current solved ``[dy dx]``.
%   - **options** *(optional)* - struct with fields:
%
%     - ``.roiSize`` - [double] ROI edge length around the click (default: ``128``)
%     - ``.searchRadius`` - [double] search extent around the corresponding
%       location in B, per side (default: ``64``)
%     - ``.colorChannel`` - [double|char] channel / ``'max'`` (default: ``1``)
%     - ``.subpixel`` - [logical] parabolic peak refinement (default: ``true``)
%     - ``.minPeak`` - [double] minimum peak NCC for confidence (default: ``0.5``)
%     - ``.minProminence`` - [double] minimum peak − second-peak separation
%       (second peak sampled outside a 5-px exclusion zone; default: ``0.05``)
%     - ``.smoothSigma`` - [double] sigma of the Gaussian blur of the fallback
%       match; ``0`` disables the fallback (default: ``1``). The raw template
%       and search crop are matched first; only when that match is not
%       confident is it repeated on both crops blurred with this sigma (the
%       tiles themselves are never blurred). Pixel noise caps the NCC of
%       correctly aligned raw tiles: on a noisy uint8 EM pair the true offset
%       peaked at 0.27-0.41, under ``minPeak``, and never snapped; with sigma 1
%       the same spots gave 0.84-0.89 and the same offset. The
%       ``'flat-template'`` test runs on the raw template.
%
% Output Arguments:
%   - **newOffsetYX** - [1x2 double] corrected ``[dy dx]``; equals
%     ``currentOffsetYX`` when not confident (never a silent bad move).
%   - **score** - [double] peak NCC in ``[-1, 1]`` (``0`` when no match ran).
%   - **confident** - [logical] peak and prominence above the thresholds.
%   - **debugInfo** - [struct] ``.secondPeak``, ``.templateBBox`` /
%     ``.searchBBox`` (``[rowStart rowEnd; colStart colEnd]``), ``.reason``
%     (why not confident: ``''`` | ``'roi-too-small'`` | ``'flat-template'`` |
%     ``'search-too-small'`` | ``'weak-peak'``), ``.smoothSigma`` (sigma of the
%     reported match: ``0`` = raw crops, ``options.smoothSigma`` = the blurred
%     fallback, ``NaN`` = no match ran). When neither match is confident, the
%     reported ``score``/``.secondPeak`` are those of the last attempt.
%
% **Example** - snap a seam from a click at a landmark:
%
%   .. code-block:: matlab
%
%      [offset, score, ok] = utils.stitch.localCorrelate(tileI, tileJ, [412 88], [2 -158]);
%      if ok; edge.measured(1:2) = offset; edge.source = 'user'; end

if nargin < 5; options = struct(); end
if ~isfield(options, 'roiSize');       options.roiSize = 128; end
if ~isfield(options, 'searchRadius');  options.searchRadius = 64; end
if ~isfield(options, 'colorChannel');  options.colorChannel = 1; end
if ~isfield(options, 'subpixel');      options.subpixel = true; end
if ~isfield(options, 'minPeak');       options.minPeak = 0.5; end
if ~isfield(options, 'minProminence'); options.minProminence = 0.05; end
if ~isfield(options, 'smoothSigma');   options.smoothSigma = 1; end

newOffsetYX = currentOffsetYX(1:2);
score = 0;
confident = false;
debugInfo = struct('secondPeak', NaN, 'templateBBox', [], 'searchBBox', [], 'reason', '', 'smoothSigma', NaN);

imageA = flattenTile(tileA, options.colorChannel);
imageB = flattenTile(tileB, options.colorChannel);
[heightA, widthA] = size(imageA);
[heightB, widthB] = size(imageB);

% ---- template: ROI around the click in tile A, clipped to the tile ------------
half = floor(options.roiSize / 2);
clickRow = round(clickXY(2));
clickCol = round(clickXY(1));
templateRows = max(1, clickRow - half):min(heightA, clickRow + half - 1);
templateCols = max(1, clickCol - half):min(widthA, clickCol + half - 1);
if numel(templateRows) < 16 || numel(templateCols) < 16
    debugInfo.reason = 'roi-too-small';
    return;
end
template = imageA(templateRows, templateCols);
debugInfo.templateBBox = [templateRows(1), templateRows(end); templateCols(1), templateCols(end)];
if std(template(:)) < eps('single')
    debugInfo.reason = 'flat-template';
    return;
end

% ---- search region: the corresponding B location +- searchRadius --------------
correspondingRows = templateRows - round(currentOffsetYX(1));
correspondingCols = templateCols - round(currentOffsetYX(2));
searchRows = max(1, correspondingRows(1) - options.searchRadius): ...
             min(heightB, correspondingRows(end) + options.searchRadius);
searchCols = max(1, correspondingCols(1) - options.searchRadius): ...
             min(widthB, correspondingCols(end) + options.searchRadius);
templateH = numel(templateRows);
templateW = numel(templateCols);
% normxcorr2 needs the template strictly inside the search image; a clipped
% search that cannot contain it means the click is outside B's reach.
if numel(searchRows) < templateH + 2 || numel(searchCols) < templateW + 2
    debugInfo.reason = 'search-too-small';
    return;
end
searchImage = imageB(searchRows, searchCols);
debugInfo.searchBBox = [searchRows(1), searchRows(end); searchCols(1), searchCols(end)];

% ---- NCC: peak restricted to full-overlap placements ---------------------------
% The raw crops are matched first; when that is not confident the match is
% repeated on blurred crops (never the tiles): pixel noise can cap the NCC of
% correctly aligned raw EM tiles below minPeak, and a light blur restores it
sigmaList = 0;
if options.smoothSigma > 0; sigmaList = [0, options.smoothSigma]; end
for sigma = sigmaList
    if sigma > 0
        crossCorr = normxcorr2(imgaussfilt(template, sigma), imgaussfilt(searchImage, sigma));
    else
        crossCorr = normxcorr2(template, searchImage);
    end
    validMap = crossCorr(templateH:numel(searchRows), templateW:numel(searchCols));
    [peak, peakIdx] = max(validMap(:));
    [peakRow, peakCol] = ind2sub(size(validMap), peakIdx);
    score = double(peak);

    % Second peak outside a 5-px exclusion zone - ambiguity guard against
    % repetitive content (the very failure mode the inspector exists to fix).
    exclusion = 5;
    maskedMap = validMap;
    maskedRows = max(1, peakRow - exclusion):min(size(validMap, 1), peakRow + exclusion);
    maskedCols = max(1, peakCol - exclusion):min(size(validMap, 2), peakCol + exclusion);
    maskedMap(maskedRows, maskedCols) = -Inf;
    secondPeak = max(maskedMap(:));
    if ~isfinite(secondPeak); secondPeak = -1; end
    debugInfo.secondPeak = double(secondPeak);
    debugInfo.smoothSigma = sigma;

    if score >= options.minPeak && (score - secondPeak) >= options.minProminence; break; end
end

if score < options.minPeak || (score - secondPeak) < options.minProminence
    debugInfo.reason = 'weak-peak';
    return;
end

% ---- subpixel refinement + offset composition ----------------------------------
% validMap(pr, pc) places template(1,1) at searchImage(pr, pc); parabolic
% interpolation sharpens the peak location.
refinedRow = double(peakRow);
refinedCol = double(peakCol);
if options.subpixel
    refinedRow = refinedRow + parabolicOffset(validMap, peakRow, peakCol, 1);
    refinedCol = refinedCol + parabolicOffset(validMap, peakRow, peakCol, 2);
end
templateTopLeftInB = [searchRows(1) + refinedRow - 1, searchCols(1) + refinedCol - 1];
% A(r, c) == B(r - dy, c - dx)  =>  [dy dx] = A top-left - B top-left.
newOffsetYX = [templateRows(1), templateCols(1)] - templateTopLeftInB;
confident = true;
end

% =====================================================================
function img = flattenTile(img, colorChannel)
% FLATTENTILE - [H W D C] -> single 2D (channel select/max-proj, mean depth).
if size(img, 4) > 1
    if ischar(colorChannel) || isstring(colorChannel)
        img = max(img, [], 4);
    else
        channel = min(max(round(colorChannel), 1), size(img, 4));
        img = img(:, :, :, channel);
    end
else
    img = img(:, :, :, 1);
end
if size(img, 3) > 1
    img = mean(single(img), 3);
end
img = single(img(:, :, 1));
end

% =====================================================================
function offset = parabolicOffset(map, peakRow, peakCol, dim)
% PARABOLICOFFSET - 3-point parabola through the peak along one dimension;
% returns the fractional correction in [-0.5, 0.5] (0 at the map border).
if dim == 1
    if peakRow <= 1 || peakRow >= size(map, 1); offset = 0; return; end
    left = double(map(peakRow - 1, peakCol));
    centre = double(map(peakRow, peakCol));
    right = double(map(peakRow + 1, peakCol));
else
    if peakCol <= 1 || peakCol >= size(map, 2); offset = 0; return; end
    left = double(map(peakRow, peakCol - 1));
    centre = double(map(peakRow, peakCol));
    right = double(map(peakRow, peakCol + 1));
end
denominator = left - 2 * centre + right;
if abs(denominator) < eps
    offset = 0;
else
    offset = 0.5 * (left - right) / denominator;
    offset = max(min(offset, 0.5), -0.5);
end
end
