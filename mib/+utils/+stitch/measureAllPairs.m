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
%     - ``.transformType`` — [char] ``'Translation'`` (default) | ``'Rigid'`` |
%       ``'Similarity'`` | ``'Affine'``. Phase correlation can only measure
%       translation, so any non-translation model implies the feature-based
%       estimator regardless of ``registrationMethod``. Non-translation edges
%       additionally carry the full fitted transform in ``.tform``.
%     - ``.allowRotation`` — [logical] ``true`` (default). ``false`` constrains
%       every pairwise fit to carry no rotation (forwarded to
%       :func:`utils.stitch.featureShift`); pair it with the same option on
%       :func:`utils.stitch.solveGlobalAffine` so measurement and solve agree.
%     - ``.preserveEdges`` — [struct array] previously measured edges whose
%       USER-made fixes (``.source = 'user'``, from the seam inspector) must
%       survive this re-measure: after measuring, any output edge whose
%       ``(i, j)`` pair matches a preserved user edge is replaced by it.
%       Without this, one re-measure silently discards a QC session. Preserved
%       user edges whose pair no longer exists in ``pairs`` are dropped.
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
%     (``[0,1]``), ``.valid`` (logical), ``.tform`` — the tile-local A→B
%     transform as a 3x3 double in xy pixel coordinates
%     (``[x_j; y_j; 1] = tform * [x_i; y_i; 1]``), filled only when a
%     non-translation ``transformType`` was fitted (``[]`` otherwise; the
%     translation solver reads ``.measured`` alone) — and the seam-inspector
%     bookkeeping fields ``.source`` (``'auto'`` here; ``'user'``/
%     ``'confirmed'`` are set by the inspector) and ``.seamScore``
%     (``[]`` here; filled by :func:`utils.stitch.scoreSeams`).
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
if ~isfield(options, 'transformType') || isempty(options.transformType)
    options.transformType = 'Translation';
end
if ~isfield(options, 'allowRotation'); options.allowRotation = true; end
if ~isfield(options, 'preserveEdges'); options.preserveEdges = []; end

nPairs = numel(pairs);
edges = repmat(struct('i', [], 'j', [], 'direction', '', 'nominal', [0 0 0], ...
    'measured', [0 0 0], 'quality', 0, 'valid', false, 'tform', [], ...
    'source', 'auto', 'seamScore', []), 1, nPairs);

if nPairs == 0; return; end

shiftOptions = struct('subpixel', options.subpixel, 'window', true);
expandPx     = options.expandPx;
colorChannel = options.colorChannel;
zSearchRadius = options.zSearchRadius;

% Per-pair estimator: phase correlation (default) or feature-based. Both return
% [dy dx dz] in the same sign convention (cropB(r,c) ≈ cropA(r-dy,c-dx)), so the
% displacement composition in measureOne is method-agnostic. The handle is passed
% into the parfor body (a plain function handle broadcasts cleanly to workers).
% Phase correlation can only measure translation — any richer transform model
% forces the feature-based estimator.
fitsFullTransform = ~strcmpi(options.transformType, 'Translation');
isFeatureBased = strcmpi(options.registrationMethod, 'Feature-based') || fitsFullTransform;
if isFeatureBased
    shiftFcn = @(a, b, o) utils.stitch.featureShift(a, b, o);
    % Merge the feature-detector settings (detector type, per-detector params,
    % downsampling, RANSAC) into shiftOptions so featureShift reads them; the
    % fields are ignored by pairwiseShift-only callers.
    featureFields = fieldnames(options.featureOptions);
    for fieldIdx = 1:numel(featureFields)
        shiftOptions.(featureFields{fieldIdx}) = options.featureOptions.(featureFields{fieldIdx});
    end
    shiftOptions.transformType = lower(options.transformType);   % estgeotform2d spelling
    shiftOptions.allowRotation = options.allowRotation;
else
    shiftFcn = @(a, b, o) utils.stitch.pairwiseShift(a, b, o);
end

if options.useParallel
    % Each worker builds its own cache (documented behaviour).
    readerOptions = struct('cacheSizeBytes', options.cacheSizeBytes);
    measured = zeros(nPairs, 3);
    qualities = zeros(nPairs, 1);
    tforms = cell(nPairs, 1);
    parfor k = 1:nPairs
        localReader = utils.stitch.makeTileReader(layout, readerOptions);
        [measured(k, :), qualities(k), tforms{k}] = measureOne(layout, pairs(k), ...
            localReader, expandPx, colorChannel, shiftOptions, zSearchRadius, shiftFcn, isFeatureBased);
    end
    for k = 1:nPairs
        edges(k) = fillEdge(pairs(k), measured(k, :), qualities(k), options.qualityThreshold, tforms{k});
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
        [measuredShift, quality, tformTile] = measureOne(layout, pairs(k), readerFcn, ...
            expandPx, colorChannel, shiftOptions, zSearchRadius, shiftFcn, isFeatureBased);
        edges(k) = fillEdge(pairs(k), measuredShift, quality, options.qualityThreshold, tformTile);
        if ~isempty(progressDialog) && isvalid(progressDialog)
            progressDialog.Value = k / nPairs;
        end
    end
    if ~isempty(progressDialog) && isvalid(progressDialog)
        close(progressDialog);
    end
end

edges = mergePreservedUserEdges(edges, options.preserveEdges);
end

% =====================================================================
function edges = mergePreservedUserEdges(edges, preserveEdges)
% MERGEPRESERVEDUSEREDGES - Re-apply user-fixed edges over fresh measurements.
% Only edges the inspector marked source='user' are carried over; everything
% else takes the new automatic measurement.
if isempty(preserveEdges) || ~isfield(preserveEdges, 'source'); return; end
for p = 1:numel(preserveEdges)
    preserved = preserveEdges(p);
    if ~strcmp(preserved.source, 'user'); continue; end
    for k = 1:numel(edges)
        if edges(k).i == preserved.i && edges(k).j == preserved.j
            edges(k).measured  = preserved.measured;
            edges(k).quality   = preserved.quality;
            edges(k).valid     = preserved.valid;
            edges(k).source    = preserved.source;
            if isfield(preserved, 'tform');     edges(k).tform = preserved.tform; end
            if isfield(preserved, 'seamScore'); edges(k).seamScore = preserved.seamScore; end
            break;
        end
    end
end
end

% =====================================================================
function [measuredShift, quality, tformTile] = measureOne(layout, pair, readerFcn, expandPx, colorChannel, shiftOptions, zSearchRadius, shiftFcn, isFeatureBased)
% MEASUREONE - Read overlap crops for one pair and estimate the residual shift.
% Adapt the expansion to the nominal overlap extent along the pair direction:
% expanding far beyond the overlap fills the crops with unshared content, which
% starves the correlation peak and creates genuine competing peaks.
% shiftFcn(a,b,o) is the per-pair estimator (pairwiseShift or featureShift).
% tformTile is the fitted tile-local A->B 3x3 (xy) when a non-translation model
% was requested; [] otherwise.
if nargin < 7; zSearchRadius = 8; end
if nargin < 8 || isempty(shiftFcn); shiftFcn = @(a, b, o) utils.stitch.pairwiseShift(a, b, o); end
if nargin < 9; isFeatureBased = false; end
tformTile = [];
% Full transforms are within-layer only: cross-layer ('z') pairs are measured as
% translations regardless of the requested model (the in-plane affine acts per
% slice; z composes additively, so z-edges carry no linear part).
fitsFullTransform = isfield(shiftOptions, 'transformType') && ...
    ~strcmp(shiftOptions.transformType, 'translation');
if fitsFullTransform && strcmp(pair.direction, 'z')
    shiftOptions.transformType = 'translation';
    fitsFullTransform = false;
end
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
    [shiftYXZ, quality, shiftDebugInfo] = shiftFcn(cropA, cropB, shiftOptions);
    measuredDz = pair.nominal(3);   % within-layer: dz constrained to nominal (0)
    if fitsFullTransform && isstruct(shiftDebugInfo) && ...
            isfield(shiftDebugInfo, 'tformA') && ~isempty(shiftDebugInfo.tformA)
        % Re-express the crop-local fit in tile-local coordinates. With crops
        % starting at tile pixels oA/oB (1-based, [y x] from the bboxes) and the
        % crop-frame map x_cropB = M*x_cropA + c:
        %   x_tileB = M*x_tileA + c + (oB-1) - M*(oA-1)
        % i.e. T_tile = Tr(oB-1) * T_crop * Tr(-(oA-1)) (xy order). For the
        % feature-based full-tile reads oA = oB = [1 1] and T_tile = T_crop.
        offsetA = [bboxA(2, 1) - 1; bboxA(1, 1) - 1];   % [x; y]
        offsetB = [bboxB(2, 1) - 1; bboxB(1, 1) - 1];
        tformTile = shiftDebugInfo.tformA;
        tformTile(1:2, 3) = tformTile(1:2, 3) + offsetB - tformTile(1:2, 1:2) * offsetA;
    end
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
function edge = fillEdge(pair, measuredShift, quality, qualityThreshold, tformTile)
% FILLEDGE - Assemble one output edge struct from a pair + measurement.
if nargin < 5; tformTile = []; end
edge.i         = pair.i;
edge.j         = pair.j;
edge.direction = pair.direction;
edge.nominal   = pair.nominal;
edge.measured  = measuredShift;
edge.quality   = quality;
edge.valid     = quality >= qualityThreshold;
edge.tform     = tformTile;
edge.source    = 'auto';
edge.seamScore = [];
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
