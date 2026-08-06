function coreLabel = segmentBlockedImageInstances(block, net, threshold, executionEnvironment)
% SEGMENTBLOCKEDIMAGEINSTANCES - Segment one tile of a blocked image with SOLOv2 (centroid-in-core).
%
% Syntax:
%   .. code-block:: matlab
%
%      coreLabel = deepmib.segmentBlockedImageInstances(block, net, threshold, executionEnvironment)
%
% Per-block function for ``blockedImage/apply`` used to tile large / whole-slide images for
% 2D instance segmentation. Each tile is read with a surrounding border of context
% (``BorderSize`` = overlap). ``segmentObjects`` is run on the bordered tile, and only the
% instances whose **centroid falls inside the tile core** (the non-border region that
% ``apply`` writes back) are kept - so each object is emitted by exactly the tile that owns
% its centroid, with no duplicates and no seam-splitting.
%
% Globally unique instance IDs are assigned via the global counter ``mibInstanceIdCounter``,
% which the caller must reset to 0 before ``apply`` (``apply`` runs blocks sequentially with
% ``UseParallel=false``). The final label map is relabelled to a contiguous range by the caller.
%
% Limitation: an object larger than the overlap band is truncated (never fully contained in
% one tile's field of view). Set the overlap ≥ the largest expected object, or switch the
% stitching mode (BatchOpt.P_OverlapInstancesMode) to 'IoU merge'
% (deepmib.segmentImageInstancesIoUMerge), which lifts this restriction.
%
% Input Arguments:
%   - **block** - struct from ``blockedImage/apply`` with ``.Data`` (bordered tile),
%     ``.BlockSize`` (core size), ``.BorderSize`` (overlap)
%   - **net** - trained ``solov2`` detector
%   - **threshold** - confidence threshold for ``segmentObjects``
%   - **executionEnvironment** - ``'auto'`` | ``'gpu'`` | ``'cpu'``
%
% Output Arguments:
%   - **coreLabel** - ``[BlockSize(1) × BlockSize(2)] uint32`` label map of the tile core
%     (each kept instance a unique index, background 0)

global mibInstanceIdCounter

data = squeeze(block.Data);
if size(data, 3) == 1               % grayscale -> RGB
    data = repmat(data, [1, 1, 3]);
elseif size(data, 3) > 3            % drop any trailing singleton batch dim
    data = data(:, :, 1:3);
end

bh = block.BlockSize(1);
bw = block.BlockSize(2);
border = block.BorderSize(1:2);     % [y x] overlap
coreLabel = zeros([bh, bw], 'uint32');

[masks, ~, scores] = segmentObjects(net, data, ...
    'Threshold', threshold, ...
    'SelectStrongest', true, ...
    'ExecutionEnvironment', executionEnvironment);

if isempty(scores); return; end

% paint low scores first so higher-scored instances win on overlap
[~, order] = sort(scores, 'ascend');
for k = order(:)'
    m = masks(:, :, k);
    st = regionprops(m, 'Centroid');
    if isempty(st); continue; end
    centroid = st(1).Centroid;      % [x y] in bordered-tile coordinates
    cy = centroid(2) - border(1);   % into core coordinates
    cx = centroid(1) - border(2);
    if cy > 0 && cy <= bh && cx > 0 && cx <= bw
        mibInstanceIdCounter = mibInstanceIdCounter + 1;
        coreMask = m(border(1)+1:border(1)+bh, border(2)+1:border(2)+bw);
        coreLabel(coreMask) = mibInstanceIdCounter;
    end
end
end
