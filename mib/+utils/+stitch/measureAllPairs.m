function edges = measureAllPairs(layout, pairs, options)
% MEASUREALLPAIRS - Measure the residual shift of every neighbour pair.
%
% Syntax:
%   .. code-block:: matlab
%
%      edges = utils.stitch.measureAllPairs(layout, pairs)
%      edges = utils.stitch.measureAllPairs(layout, pairs, options)
%
% For each candidate neighbour pair, extracts the nominal overlap crops from both
% tiles (:func:`utils.stitch.computeOverlapRegion` + a cached tile reader), runs
% :func:`utils.stitch.pairwiseShift`, and returns an ``edges`` struct array that
% carries the original pair fields plus the measured offset, its quality and a
% ``valid`` flag. The measured global offset obeys the ``pairwiseShift`` sign
% convention:
%
%   .. code-block:: matlab
%
%      edge.measured = edge.nominal + shiftYXZ
%
% Multi-channel tiles are registered on a single channel (``options.colorChannel``)
% or their max-projection (``options.colorChannel = 'max'``).
%
% Input Arguments:
%   - **layout** — [struct array] tile layout (see :func:`utils.stitch.makeTileReader`).
%   - **pairs** — [struct array] neighbour pairs; each has ``.i``, ``.j``,
%     ``.direction`` (``'x'``/``'y'``/``'z'``) and ``.nominal`` (``[dy dx dz]``).
%   - **options** *(optional)* — struct with fields:
%
%     - ``.expandPx`` — [double] jitter expansion for the overlap (default: ``64``)
%     - ``.qualityThreshold`` — [double] ``valid = quality >= threshold`` (default: ``0.30``)
%     - ``.colorChannel`` — [double|char] channel index to register on, or
%       ``'max'`` for a max-projection over channels (default: ``1``)
%     - ``.subpixel`` — [logical] subpixel refinement in ``pairwiseShift`` (default: ``true``)
%     - ``.registrationMethod`` — [char] ``'Phase correlation'`` (default) or
%       ``'Feature-based'``; selects :func:`utils.stitch.pairwiseShift` or
%       :func:`utils.stitch.featureShift` as the per-pair estimator (both share
%       the same sign convention, so the displacement composition is identical).
%     - ``.featureOptions`` — [struct] detector settings forwarded to
%       :func:`utils.stitch.featureShift` when ``registrationMethod`` is
%       ``'Feature-based'`` (detector type, per-detector params, downsampling,
%       RANSAC; the ``automaticOptions`` shape). Ignored for phase correlation.
%     - ``.cacheSizeBytes`` — [double] LRU tile-cache budget (default: ``2*1024^3``)
%     - ``.useParallel`` — [logical] measure pairs with ``parfor`` (default: ``false``)
%     - ``.showWaitbar`` — [logical] show a progress dialog (default: ``false``)
%     - ``.parentFigure`` — [handle] parent for the progress dialog (default: ``[]``)
%
% Output Arguments:
%   - **edges** — [struct array] one per pair with fields ``.i .j .direction
%     .nominal`` (copied) plus ``.measured`` (``[dy dx dz]``), ``.quality``
%     (``[0,1]``) and ``.valid`` (logical).
%
% **Example** — measure all pairs sequentially:
%
%   .. code-block:: matlab
%
%      opts.qualityThreshold = 0.3;
%      edges = utils.stitch.measureAllPairs(layout, pairs, opts);
%      solvable = edges([edges.valid]);

if nargin < 3; options = struct(); end
if ~isfield(options, 'expandPx');         options.expandPx = 64; end
if ~isfield(options, 'qualityThreshold'); options.qualityThreshold = 0.30; end
if ~isfield(options, 'colorChannel');     options.colorChannel = 1; end
if ~isfield(options, 'subpixel');         options.subpixel = true; end
if ~isfield(options, 'cacheSizeBytes');   options.cacheSizeBytes = 2 * 1024^3; end
if ~isfield(options, 'useParallel');      options.useParallel = false; end
if ~isfield(options, 'showWaitbar');      options.showWaitbar = false; end
if ~isfield(options, 'parentFigure');     options.parentFigure = []; end
if ~isfield(options, 'zSearchRadius');    options.zSearchRadius = 8; end
if ~isfield(options, 'registrationMethod'); options.registrationMethod = 'Phase correlation'; end
if ~isfield(options, 'featureOptions');     options.featureOptions = struct(); end

nPairs = numel(pairs);
edges = repmat(struct('i', [], 'j', [], 'direction', '', 'nominal', [0 0 0], ...
    'measured', [0 0 0], 'quality', 0, 'valid', false), 1, nPairs);

if nPairs == 0; return; end

shiftOptions = struct('subpixel', options.subpixel, 'window', true);
expandPx     = options.expandPx;
colorChannel = options.colorChannel;
zSearchRadius = options.zSearchRadius;

% Per-pair estimator: phase correlation (default) or feature-based. Both return
% [dy dx dz] in the same sign convention (cropB(r,c) ≈ cropA(r-dy,c-dx)), so the
% displacement composition in measureOne is method-agnostic. The handle is passed
% into the parfor body (a plain function handle broadcasts cleanly to workers).
isFeatureBased = strcmpi(options.registrationMethod, 'Feature-based');
if isFeatureBased
    shiftFcn = @(a, b, o) utils.stitch.featureShift(a, b, o);
    % Merge the feature-detector settings (detector type, per-detector params,
    % downsampling, RANSAC) into shiftOptions so featureShift reads them; the
    % fields are ignored by pairwiseShift-only callers.
    featureFields = fieldnames(options.featureOptions);
    for fieldIdx = 1:numel(featureFields)
        shiftOptions.(featureFields{fieldIdx}) = options.featureOptions.(featureFields{fieldIdx});
    end
else
    shiftFcn = @(a, b, o) utils.stitch.pairwiseShift(a, b, o);
end

if options.useParallel
    % Each worker builds its own cache (documented behaviour).
    readerOptions = struct('cacheSizeBytes', options.cacheSizeBytes);
    measured = zeros(nPairs, 3);
    qualities = zeros(nPairs, 1);
    parfor k = 1:nPairs
        localReader = utils.stitch.makeTileReader(layout, readerOptions);
        [measured(k, :), qualities(k)] = measureOne(layout, pairs(k), ...
            localReader, expandPx, colorChannel, shiftOptions, zSearchRadius, shiftFcn, isFeatureBased);
    end
    for k = 1:nPairs
        edges(k) = fillEdge(pairs(k), measured(k, :), qualities(k), options.qualityThreshold);
    end
else
    readerFcn = utils.stitch.makeTileReader(layout, ...
        struct('cacheSizeBytes', options.cacheSizeBytes));
    progressDialog = [];
    if options.showWaitbar && ~isempty(options.parentFigure)
        progressDialog = uiprogressdlg(options.parentFigure, 'Value', 0, ...
            'Message', 'Measuring tile overlaps...', 'Title', 'Stitching');
    end
    for k = 1:nPairs
        [measuredShift, quality] = measureOne(layout, pairs(k), readerFcn, ...
            expandPx, colorChannel, shiftOptions, zSearchRadius, shiftFcn, isFeatureBased);
        edges(k) = fillEdge(pairs(k), measuredShift, quality, options.qualityThreshold);
        if ~isempty(progressDialog) && isvalid(progressDialog)
            progressDialog.Value = k / nPairs;
        end
    end
    if ~isempty(progressDialog) && isvalid(progressDialog)
        close(progressDialog);
    end
end
end

% =====================================================================
function [measuredShift, quality] = measureOne(layout, pair, readerFcn, expandPx, colorChannel, shiftOptions, zSearchRadius, shiftFcn, isFeatureBased)
% MEASUREONE - Read overlap crops for one pair and estimate the residual shift.
% Adapt the expansion to the nominal overlap extent along the pair direction:
% expanding far beyond the overlap fills the crops with unshared content, which
% starves the correlation peak and creates genuine competing peaks.
% shiftFcn(a,b,o) is the per-pair estimator (pairwiseShift or featureShift).
if nargin < 7; zSearchRadius = 8; end
if nargin < 8 || isempty(shiftFcn); shiftFcn = @(a, b, o) utils.stitch.pairwiseShift(a, b, o); end
if nargin < 9; isFeatureBased = false; end
if strcmp(pair.direction, 'x')
    overlapExtent = layout(pair.i).tileSize(2) - abs(pair.nominal(2));
elseif strcmp(pair.direction, 'y')
    overlapExtent = layout(pair.i).tileSize(1) - abs(pair.nominal(1));
else
    overlapExtent = inf;
end
pairExpandPx = min(expandPx, max(round(0.75 * overlapExtent), 8));

% Feature-based within-layer matching reads the FULL tiles rather than the thin
% nominal-overlap strip: RANSAC discards features in the non-shared 90% while the
% overlap features (too few in a ~40 px strip for scale-space blob detectors)
% still fit the translation. This also lets it recover offsets far from nominal
% (unknown/arbitrary layouts) that the restricted phase-correlation search misses.
% Cross-layer ('z') pairs already sit at ~same XY, so their overlap crop is most
% of the tile — no full-tile override needed there.
if isFeatureBased && (strcmp(pair.direction, 'x') || strcmp(pair.direction, 'y'))
    bboxA = [1, layout(pair.i).tileSize(1); 1, layout(pair.i).tileSize(2)];
    bboxB = [1, layout(pair.j).tileSize(1); 1, layout(pair.j).tileSize(2)];
else
    [bboxA, bboxB] = utils.stitch.computeOverlapRegion(layout, pair.i, pair.j, pairExpandPx);
end
cropA = readerFcn(pair.i, bboxA);   % [H W D C]
cropB = readerFcn(pair.j, bboxB);

cropA = selectChannel(cropA, colorChannel);
cropB = selectChannel(cropB, colorChannel);

% Expected shift when tiles sit exactly at nominal (raw crop-start offset minus
% the nominal displacement); restrict the peak search to the jitter budget
% around it and zero-pad so shifts near -expandPx cannot alias.
shiftOptions.expectedShift = [bboxA(1, 1) - bboxB(1, 1) - pair.nominal(1), ...
                              bboxA(2, 1) - bboxB(2, 1) - pair.nominal(2)];
shiftOptions.searchRadius  = pairExpandPx + 8;
shiftOptions.padPx         = pairExpandPx + 8;

if strcmp(pair.direction, 'z')
    [shiftYXZ, quality, measuredDz] = measureZShift(cropA, cropB, ...
        pair.nominal(3), zSearchRadius, shiftOptions, shiftFcn);
else
    cropA = flattenDepth(cropA);
    cropB = flattenDepth(cropB);
    [shiftYXZ, quality] = shiftFcn(cropA, cropB, shiftOptions);
    measuredDz = pair.nominal(3);   % within-layer: dz constrained to nominal (0)
end

% Compose the measured displacement from the actual crop start offsets.
% With cropB(r,c) ~= cropA(r - dy, c - dx) (pairwiseShift convention) and crops
% starting at local positions bboxA(:,1)/bboxB(:,1):
%   P_j - P_i = (bboxA(:,1) - bboxB(:,1)) - [dy dx]
% This is exact even when border clamping makes the two crops cover different
% nominal windows. dz needs no crop-start compensation: both crops carry the
% FULL depth of their tiles, so slice indices are already tile-local.
measuredShift = [bboxA(1, 1) - bboxB(1, 1) - shiftYXZ(1), ...
                 bboxA(2, 1) - bboxB(2, 1) - shiftYXZ(2), ...
                 measuredDz];
end

% =====================================================================
function [shiftYXZ, quality, measuredDz] = measureZShift(cropA, cropB, nominalDz, zSearchRadius, shiftOptions, shiftFcn)
% MEASUREZSHIFT - Joint [dy dx dz] measurement for a cross-layer stack pair.
%
% XY and Z are decoupled: a mean projection over depth cancels the z-specific
% content (so it aligns XY well but says NOTHING about dz — a thick-slab
% correlation scores high for every dz with decent overlap and even prefers the
% smaller-dz / larger-overlap side). So:
%   1. dy, dx come from the mean-projection correlation (calibrated pairwiseShift).
%   2. dz is then chosen by scanning integer offsets and scoring each with the
%      normalised cross-correlation of the ACTUAL overlapping voxel block after
%      applying the recovered dy, dx. Real slice content makes the NCC-vs-dz
%      curve peak sharply at the true offset.
%
% When no candidate yields any Z-overlap (serial stacks that merely abut), falls
% back to the facing-slice correlation for [dy dx] and keeps dz at nominal.
%
% dz convention matches the solver: dz = P_j(3) - P_i(3) in slices; A-local
% slice ``a`` corresponds to B-local slice ``a - dz``. XY convention matches
% pairwiseShift: ``cropB(r,c) ≈ cropA(r-dy, c-dx)`` ⇒ A(r,c) sits at B(r+dy, c+dx).
if nargin < 6 || isempty(shiftFcn); shiftFcn = @(a, b, o) utils.stitch.pairwiseShift(a, b, o); end
Da = size(cropA, 3);
Db = size(cropB, 3);

projA = mean(single(cropA), 3);
projB = mean(single(cropB), 3);
[xyShift, xyQuality] = shiftFcn(projA, projB, shiftOptions);
dy = round(xyShift(1));
dx = round(xyShift(2));

[Ha, Wa, ~] = size(cropA);
Hb = size(cropB, 1);
Wb = size(cropB, 2);

% Overlapping XY block in A coords such that (r+dy, c+dx) is inside B.
rowA = max(1, 1 - dy):min(Ha, Hb - dy);
colA = max(1, 1 - dx):min(Wa, Wb - dx);

dzCandidates = round(nominalDz) + (-zSearchRadius:zSearchRadius);
bestNcc = -Inf;
bestDz = round(nominalDz);
anyOverlap = false;
if ~isempty(rowA) && ~isempty(colA)
    blockA = single(cropA(rowA, colA, :));
    blockB = single(cropB(rowA + dy, colA + dx, :));
    for candidateIdx = 1:numel(dzCandidates)
        dz = dzCandidates(candidateIdx);
        aLo = max(1, 1 + dz);
        aHi = min(Da, Db + dz);
        if aHi < aLo; continue; end
        anyOverlap = true;
        va = blockA(:, :, aLo:aHi);
        vb = blockB(:, :, (aLo:aHi) - dz);
        ncc = normXCorr(va(:), vb(:));
        if ncc > bestNcc
            bestNcc = ncc;
            bestDz = dz;
        end
    end
end

if anyOverlap
    shiftYXZ = [xyShift(1), xyShift(2), 0];
    quality = max(xyQuality, 0);
    measuredDz = bestDz;
    return;
end

% Facing-slice fallback: stacks meet without sharing slices.
if nominalDz >= 0
    faceA = single(cropA(:, :, Da));   % bottom of A faces ...
    faceB = single(cropB(:, :, 1));    % ... top of B
else
    faceA = single(cropA(:, :, 1));
    faceB = single(cropB(:, :, Db));
end
[shiftYXZ, quality] = shiftFcn(faceA, faceB, shiftOptions);
measuredDz = nominalDz;
end

% =====================================================================
function ncc = normXCorr(a, b)
% NORMXCORR - Normalised cross-correlation of two equal-length vectors.
a = a - mean(a);
b = b - mean(b);
denom = norm(a) * norm(b);
if denom < eps
    ncc = -Inf;
else
    ncc = (a' * b) / denom;
end
end

% =====================================================================
function edge = fillEdge(pair, measuredShift, quality, qualityThreshold)
% FILLEDGE - Assemble one output edge struct from a pair + measurement.
edge.i         = pair.i;
edge.j         = pair.j;
edge.direction = pair.direction;
edge.nominal   = pair.nominal;
edge.measured  = measuredShift;
edge.quality   = quality;
edge.valid     = quality >= qualityThreshold;
end

% =====================================================================
function img = selectChannel(img, colorChannel)
% SELECTCHANNEL - Reduce [H W D C] to [H W D] on the chosen channel or max-proj.
if size(img, 4) <= 1
    img = img(:, :, :, 1);
    return;
end
if ischar(colorChannel) || isstring(colorChannel)
    img = max(img, [], 4);
else
    channel = min(max(round(colorChannel), 1), size(img, 4));
    img = img(:, :, :, channel);
end
end

% =====================================================================
function img = flattenDepth(img)
% FLATTENDEPTH - Collapse the depth dimension to a 2D image for correlation.
%
% Within-layer pairs already have depth 1. For 'z' pairs (Phase 1, simple) use
% the mean projection over depth so the two facing stacks correlate their bulk
% content; dz itself is returned as 0 by pairwiseShift.
if size(img, 3) > 1
    img = mean(single(img), 3);
end
img = img(:, :, 1);
end
