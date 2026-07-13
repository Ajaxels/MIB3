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

nPairs = numel(pairs);
edges = repmat(struct('i', [], 'j', [], 'direction', '', 'nominal', [0 0 0], ...
    'measured', [0 0 0], 'quality', 0, 'valid', false), 1, nPairs);

if nPairs == 0; return; end

shiftOptions = struct('subpixel', options.subpixel, 'window', true);
expandPx     = options.expandPx;
colorChannel = options.colorChannel;

if options.useParallel
    % Each worker builds its own cache (documented behaviour).
    readerOptions = struct('cacheSizeBytes', options.cacheSizeBytes);
    measured = zeros(nPairs, 3);
    qualities = zeros(nPairs, 1);
    parfor k = 1:nPairs
        localReader = utils.stitch.makeTileReader(layout, readerOptions);
        [measured(k, :), qualities(k)] = measureOne(layout, pairs(k), ...
            localReader, expandPx, colorChannel, shiftOptions);
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
            expandPx, colorChannel, shiftOptions);
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
function [measuredShift, quality] = measureOne(layout, pair, readerFcn, expandPx, colorChannel, shiftOptions)
% MEASUREONE - Read overlap crops for one pair and estimate the residual shift.
% Adapt the expansion to the nominal overlap extent along the pair direction:
% expanding far beyond the overlap fills the crops with unshared content, which
% starves the correlation peak and creates genuine competing peaks.
if strcmp(pair.direction, 'x')
    overlapExtent = layout(pair.i).tileSize(2) - abs(pair.nominal(2));
elseif strcmp(pair.direction, 'y')
    overlapExtent = layout(pair.i).tileSize(1) - abs(pair.nominal(1));
else
    overlapExtent = inf;
end
pairExpandPx = min(expandPx, max(round(0.75 * overlapExtent), 8));

[bboxA, bboxB] = utils.stitch.computeOverlapRegion(layout, pair.i, pair.j, pairExpandPx);
cropA = readerFcn(pair.i, bboxA);   % [H W D C]
cropB = readerFcn(pair.j, bboxB);

cropA = selectChannel(cropA, colorChannel);
cropB = selectChannel(cropB, colorChannel);

% For a z-direction pair of Z-stacks correlate the facing (mean-projected)
% slices; for within-layer pairs the crops are already 2D (D == 1).
cropA = flattenDepth(cropA);
cropB = flattenDepth(cropB);

% Expected shift when tiles sit exactly at nominal (raw crop-start offset minus
% the nominal displacement); restrict the peak search to the jitter budget
% around it and zero-pad so shifts near -expandPx cannot alias.
shiftOptions.expectedShift = [bboxA(1, 1) - bboxB(1, 1) - pair.nominal(1), ...
                              bboxA(2, 1) - bboxB(2, 1) - pair.nominal(2)];
shiftOptions.searchRadius  = pairExpandPx + 8;
shiftOptions.padPx         = pairExpandPx + 8;

[shiftYXZ, quality] = utils.stitch.pairwiseShift(cropA, cropB, shiftOptions);

% Compose the measured displacement from the actual crop start offsets.
% With cropB(r,c) ~= cropA(r - dy, c - dx) (pairwiseShift convention) and crops
% starting at local positions bboxA(:,1)/bboxB(:,1):
%   P_j - P_i = (bboxA(:,1) - bboxB(:,1)) - [dy dx]
% This is exact even when border clamping makes the two crops cover different
% nominal windows. dz keeps the nominal value in Phase 1 (pairwiseShift dz = 0).
measuredShift = [bboxA(1, 1) - bboxB(1, 1) - shiftYXZ(1), ...
                 bboxA(2, 1) - bboxB(2, 1) - shiftYXZ(2), ...
                 pair.nominal(3)];
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
