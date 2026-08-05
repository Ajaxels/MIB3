function [edges, ranking] = scoreSeams(layout, edges, positions, options)
% SCORESEAMS - Pixel-based seam quality of every edge at the SOLVED positions.
%
% Syntax:
%   .. code-block:: matlab
%
%      [edges, ranking] = utils.stitch.scoreSeams(layout, edges, positions)
%      [edges, ranking] = utils.stitch.scoreSeams(layout, edges, positions, options)
%
% For every edge, reads the two tiles' overlap strips AT THE SOLVED POSITIONS
% and stores their zero-mean normalised cross-correlation in
% ``edges(k).seamScore`` (range ``[-1, 1]``; higher = better seam). This is the
% inspector's primary ranking metric (see
% ``development/stitching/plan_inspector.md``): a confidently WRONG pairwise
% measurement — RANSAC or phase correlation locked one period off on repetitive
% content — satisfies the solver perfectly on a chain-like graph (zero
% residual), but its pixels do not agree at the solved placement, so only
% re-checking actual pixels catches it. Edges whose tiles do not overlap at all
% at the solved positions get ``seamScore = NaN`` (worst possible).
%
% **3D (z-stack tiles):** the strips are aligned in depth by the solved ``dz``
% and scored as the MEAN of per-slice 2D NCCs over the overlapping slab (the
% same metric ``measureAllPairs`` uses to choose ``dz`` — a volumetric NCC
% would inherit the thick-slab bias and stay high at wrong offsets). No slab
% overlap at the solved ``dz`` scores ``NaN``. Cross-layer (``direction ==
% 'z'``) edges are additionally re-scored at ``dz ± dzScanRadius``: when a
% neighbouring offset beats the solved one by ``dzHintMargin`` the difference
% is stored in ``edges(k).dzHint`` (e.g. ``+2`` = the pixels prefer ``dz + 2``);
% ``dzHint = 0`` means the solved ``dz`` is the local optimum.
%
% The returned ``ranking`` orders edges for worst-first review: pruned
% (``valid = false``) edges first, then by seam score ascending with ``NaN``
% scores leading.
%
% Non-translation solves: the strips are cut by the TRANSLATION between the
% solved origins; the residual rotation/scale of an otherwise good seam lowers
% its absolute score slightly, but the ranking (relative scores) remains
% meaningful. Transform-aware strip warping is a later refinement.
%
% Input Arguments:
%   - **layout** — [struct array] tile layout (``.tileSize``, reader fields).
%   - **edges** — [struct array] from :func:`utils.stitch.measureAllPairs`.
%   - **positions** — [N x 3 double] solved ``[y x z]`` origins.
%   - **options** *(optional)* — struct with fields:
%
%     - ``.colorChannel`` — [double|char] channel to score on, or ``'max'``
%       (default: ``1``; same semantics as ``measureAllPairs``)
%     - ``.maxStripPx`` — [double] strips longer than this are downsampled
%       before correlation (default: ``1024``)
%     - ``.maxScoreSlices`` — [double] at most this many z-slices of the
%       overlap slab are correlated, evenly sampled (default: ``16``)
%     - ``.dzScanRadius`` — [double] cross-layer edges are re-scored at
%       ``dz ± radius`` to fill ``dzHint``; ``0`` disables (default: ``2``)
%     - ``.dzHintMargin`` — [double] a neighbouring dz must beat the solved
%       one by this much before it is hinted (default: ``0.05``)
%     - ``.cacheSizeBytes`` — [double] LRU tile-cache budget (default: ``2*1024^3``)
%     - ``.readerFcn`` — [function_handle] reuse an existing tile reader (optional)
%     - ``.showWaitbar`` / ``.parentFigure`` — progress dialog (default: off)
%
% Output Arguments:
%   - **edges** — the input edges with ``.seamScore`` and ``.dzHint`` filled in.
%   - **ranking** — [1 x M double] edge indices in worst-first review order.
%
% **Example** — score and list the three worst seams:
%
%   .. code-block:: matlab
%
%      [edges, ranking] = utils.stitch.scoreSeams(layout, edges, positions);
%      worst = edges(ranking(1:3));

if nargin < 4; options = struct(); end
if ~isfield(options, 'colorChannel');   options.colorChannel = 1; end
if ~isfield(options, 'maxStripPx');     options.maxStripPx = 1024; end
if ~isfield(options, 'maxScoreSlices'); options.maxScoreSlices = 16; end
if ~isfield(options, 'dzScanRadius');   options.dzScanRadius = 2; end
if ~isfield(options, 'dzHintMargin');   options.dzHintMargin = 0.05; end
if ~isfield(options, 'cacheSizeBytes'); options.cacheSizeBytes = 2 * 1024^3; end
if ~isfield(options, 'correction');      options.correction = []; end
if ~isfield(options, 'showWaitbar');    options.showWaitbar = false; end
if ~isfield(options, 'parentFigure');   options.parentFigure = []; end

numEdges = numel(edges);
ranking = 1:numEdges;
if numEdges == 0; return; end

if isfield(options, 'readerFcn') && ~isempty(options.readerFcn)
    readerFcn = options.readerFcn;
else
    readerFcn = utils.stitch.makeTileReader(layout, ...
        struct('cacheSizeBytes', options.cacheSizeBytes, 'correction', options.correction));
end

% uiprogressdlg errors on an invisible parent (e.g. a GUI scored during its
% own startup, before the figure is shown) — skip the dialog in that case.
progressDialog = [];
if options.showWaitbar && ~isempty(options.parentFigure) && ...
        isvalid(options.parentFigure) && strcmp(options.parentFigure.Visible, 'on')
    progressDialog = uiprogressdlg(options.parentFigure, 'Value', 0, ...
        'Message', 'Scoring seams...', 'Title', 'Stitching');
end

for k = 1:numEdges
    [edges(k).seamScore, edges(k).dzHint] = scoreOne(layout, edges(k), ...
        positions, readerFcn, options);
    if ~isempty(progressDialog) && isvalid(progressDialog)
        progressDialog.Value = k / numEdges;
    end
end
if ~isempty(progressDialog) && isvalid(progressDialog)
    close(progressDialog);
end

% Worst-first review order: pruned edges lead, then seam score ascending with
% NaN (no overlap at solved positions — definitely broken) before everything.
validFlags = false(numEdges, 1);
scores = zeros(numEdges, 1);
for k = 1:numEdges
    validFlags(k) = isfield(edges, 'valid') && edges(k).valid;
    scores(k) = edges(k).seamScore;
end
scores(isnan(scores)) = -Inf;
[~, ranking] = sortrows([validFlags, scores], [1 2]);
ranking = ranking(:)';
end

% =====================================================================
function [seamScore, dzHint] = scoreOne(layout, edge, positions, readerFcn, options)
% SCOREONE - Slab NCC of one edge at the solved positions + dz preference hint.
dzHint = 0;
sizeI = layout(edge.i).tileSize;
sizeJ = layout(edge.j).tileSize;
deltaYXZ = round(positions(edge.j, :) - positions(edge.i, :));
deltaYX = deltaYXZ(1:2);
solvedDz = 0;
if numel(deltaYXZ) >= 3; solvedDz = deltaYXZ(3); end

% Overlap in tile-i local coordinates: pixel (r, c) of tile i is pixel
% (r - dy, c - dx) of tile j.
rowRange = [max(1, 1 + deltaYX(1)), min(sizeI(1), sizeJ(1) + deltaYX(1))];
colRange = [max(1, 1 + deltaYX(2)), min(sizeI(2), sizeJ(2) + deltaYX(2))];
if rowRange(2) - rowRange(1) < 3 || colRange(2) - colRange(1) < 3
    seamScore = NaN;   % (nearly) no overlap at the solved placement
    return;
end

bboxA = [rowRange; colRange];
bboxB = [rowRange - deltaYX(1); colRange - deltaYX(2)];
stripA = reduceChannels(readerFcn(edge.i, bboxA), options.colorChannel);
stripB = reduceChannels(readerFcn(edge.j, bboxB), options.colorChannel);

% Downsample long strips (XY only) for speed — both by the same factor.
longestSide = max([size(stripA, 1), size(stripA, 2)]);
if longestSide > options.maxStripPx
    ratio = options.maxStripPx / longestSide;
    stripA = imresize(stripA, ratio, 'bilinear');
    stripB = imresize(stripB, ratio, 'bilinear');
end

seamScore = slabScore(stripA, stripB, solvedDz, options.maxScoreSlices);

% Cross-layer edges: scan dz ± radius so a Z misalignment becomes an
% actionable hint ("the pixels prefer dz+2"), not just a low score.
isZEdge = isfield(edge, 'direction') && strcmp(edge.direction, 'z');
if isZEdge && options.dzScanRadius > 0 && max(size(stripA, 3), size(stripB, 3)) > 1
    bestScore = seamScore;
    if isnan(bestScore); bestScore = -Inf; end
    bestDz = solvedDz;
    radius = round(options.dzScanRadius);
    for candidateDz = [solvedDz - (1:radius), solvedDz + (1:radius)]
        candidateScore = slabScore(stripA, stripB, candidateDz, options.maxScoreSlices);
        if ~isnan(candidateScore) && candidateScore > bestScore
            bestScore = candidateScore;
            bestDz = candidateDz;
        end
    end
    referenceScore = seamScore;
    if isnan(referenceScore); referenceScore = -Inf; end
    if bestDz ~= solvedDz && bestScore > referenceScore + options.dzHintMargin
        dzHint = bestDz - solvedDz;
    end
end
end

% =====================================================================
function score = slabScore(stripA, stripB, dz, maxScoreSlices)
% SLABSCORE - Mean per-slice NCC over the depth-overlapping slab at offset dz.
% Depth convention matches the solver / measureAllPairs: tile-i local slice
% ``a`` corresponds to tile-j local slice ``a - dz``. Per-slice (not
% volumetric) correlation: a 3D NCC is dominated by the z-intensity profile
% and stays high at wrong offsets (the thick-slab bias measureAllPairs works
% around the same way).
depthA = size(stripA, 3);
depthB = size(stripB, 3);
aSlices = max(1, 1 + dz):min(depthA, depthB + dz);
if isempty(aSlices)
    score = NaN;   % no depth overlap at this dz
    return;
end
if numel(aSlices) > maxScoreSlices
    aSlices = aSlices(round(linspace(1, numel(aSlices), maxScoreSlices)));
end
sliceScores = zeros(1, numel(aSlices));
for idx = 1:numel(aSlices)
    sliceScores(idx) = zeroMeanNcc(stripA(:, :, aSlices(idx)), ...
        stripB(:, :, aSlices(idx) - dz));
end
score = mean(sliceScores);
end

% =====================================================================
function strip = reduceChannels(strip, colorChannel)
% REDUCECHANNELS - [H W D C] -> single [H W D]: channel select or max-proj
% (same semantics as measureAllPairs); the DEPTH is kept for slab scoring.
if size(strip, 4) > 1
    if ischar(colorChannel) || isstring(colorChannel)
        strip = max(strip, [], 4);
    else
        channel = min(max(round(colorChannel), 1), size(strip, 4));
        strip = strip(:, :, :, channel);
    end
else
    strip = strip(:, :, :, 1);
end
strip = single(strip);
end

% =====================================================================
function ncc = zeroMeanNcc(a, b)
% ZEROMEANNCC - Zero-mean normalised cross-correlation of two equal-size strips.
a = double(a(:)) - mean(a(:));
b = double(b(:)) - mean(b(:));
denom = norm(a) * norm(b);
if denom < eps
    ncc = 0;   % flat strips: no evidence either way
else
    ncc = (a' * b) / denom;
end
end
