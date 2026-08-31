function [labelVol, stats] = stitch2Dto3D(inputVol, options, wb)
% STITCH2DTO3D - Stitch per-slice 2D instance labels into a 3D instance volume.
%
% Syntax:
%   .. code-block:: matlab
%
%       labelVol = utils.instances.stitch2Dto3D(inputVol)
%       [labelVol, stats] = utils.instances.stitch2Dto3D(inputVol, options)
%       [labelVol, stats] = utils.instances.stitch2Dto3D(inputVol, options, wb)
%
% Given a stack of independently generated 2D instance segmentations (one
% label map per z-slice, object IDs **not** consistent across slices), link
% objects that overlap between neighbouring slices into single 3D instances
% with one consistent ID through the whole stack. The input ID *values* are
% ignored - every slice is internally relabelled to globally-unique nodes, so
% the routine is safe on genuinely independent per-slice segmentations.
%
% Two linking strategies are provided:
%   - ``'graph'`` *(default)* - build an undirected overlap graph over all
%     slices (an edge whenever a pair of objects on adjacent slices passes the
%     IoU **or** IoA test) and take connected components (union-find) as 3D
%     instances. Splits and merges are handled natively; no separate reverse
%     pass is needed because the graph is undirected.
%   - ``'hungarian'`` - the empanada-style pipeline: 1-to-1 IoU matching per
%     slice pair via ``matchpairs``, then IoA merge-in of the unmatched
%     objects, optionally run forward and backward and reconciled.
%
% Input Arguments:
%   - **inputVol** - ``[height, width, depth]`` numeric array of per-slice
%     instance labels (0 = background). Any integer class.
%   - **options** - *(optional)* structure of parameters:
%
%     - ``.method`` - ``'graph'`` (default) or ``'hungarian'``
%     - ``.splitDisconnected2D`` - treat each **connected component** of a
%       per-slice label as its own 2D object, rather than the whole label index
%       (default: ``true``). 2D instance predictors regularly emit a single
%       instance index covering several spatially separate blobs (a SOLOv2 mask
%       head firing at more than one location, or a tile-merge that fused two
%       detections). Such a label welds all of those blobs' 3D chains into one
%       object, and because the welds chain transitively across slices, a
%       handful of them can fuse most of the stack into a single giant instance.
%       Set to ``false`` only when the input indices are trusted and a genuinely
%       disconnected 2D mask must stay one object
%     - ``.iouThreshold`` - link objects whose IoU exceeds this (default: ``0.25``)
%     - ``.ioaThreshold`` - link when intersection-over-smaller-area exceeds
%       this, catching splits/thin bridges (default: ``0.50``)
%     - ``.minOverlapPixels`` - absolute minimum intersection to consider a
%       link, guards against 1-2 px spurious overlaps (default: ``5``)
%     - ``.absOverlapPixels`` - link a pair whose intersection reaches this many
%       pixels, whatever its IoU and IoA (default: ``0`` = disabled). Both ratio
%       tests are relative to object *area*, so a large cross-section meeting a
%       much smaller one scores low on each even when the shared area is
%       substantial in absolute terms: 3795 px against 1689 px sharing 716 px is
%       IoU 0.15 and IoA 0.42, below both defaults. This is a **sufficient**
%       condition added to the IoU/IoA tests, unlike ``minOverlapPixels`` which
%       is a necessary guard applied to all of them. It is an in-plane pixel
%       count, so a sensible value depends on the objects' size in this dataset
%       - inspect a few genuine links before setting it, and keep the
%       ``maxCentroidShift`` gate in mind, which still applies
%     - ``.zLookback`` - also test slices up to this many planes apart, to
%       bridge single-slice dropouts (default: ``1`` = adjacent only)
%     - ``.minObjectVoxels`` - remove 3D objects smaller than this after
%       stitching (default: ``0`` = keep all)
%     - ``.minObjectSlices`` - remove 3D objects that appear on this many
%       Z-slices or fewer (default: ``0`` = keep all; ``1`` drops single-slice
%       objects, ``2`` also drops those seen on two slices). Complements
%       ``minObjectVoxels``: a false detection can be large in-plane yet not
%       propagate through the stack, so an area threshold cannot see it while a
%       depth threshold can. Counts the slices an object actually occupies, not
%       its first-to-last span, so a ``zLookback`` bridge over a gap does not
%       inflate the count
%     - ``.absorbFragmentVoxels`` - after stitching, hand the voxels of any object
%       of this size or smaller to the object that surrounds it in-plane, rather
%       than leaving it as a separate speck (default: ``5``; ``0`` = off, and the
%       default matches ``minOverlapPixels`` because that is exactly the size
%       below which an object can never be linked at all). 2D instance
%       predictors emit stray pixels - a couple of pixels of one index sitting
%       inside another index's mask, or shaved off its rim - and
%       ``splitDisconnected2D`` correctly gives each its own object. Being
%       smaller than ``minOverlapPixels`` they can never satisfy the link guard,
%       so they survive stitching as unlinkable dust, typically a hole punched in
%       an otherwise solid object. Lowering ``minOverlapPixels`` is not the cure:
%       a speck lying over object A on one slice and under object B on the next
%       then links both and welds two unrelated objects together. Reassigning
%       voxels here runs after the linking is finished, so it cannot weld
%       anything. A fragment with no labelled neighbour is left alone - use
%       ``minObjectVoxels`` to delete those
%     - ``.anisotropyZ`` - voxel aspect ratio ``pixSize.z / pixSize.x`` (>= 1).
%       For anisotropic stacks (thick sections) a true continuation is displaced
%       more between slices, so its IoU legitimately drops; the effective IoU
%       threshold is lowered to ``max(iouThreshold / anisotropyZ, iouFloor)``.
%       IoA (containment) is left unchanged - it is scale-robust - and the
%       ``maxCentroidShift`` gate below guards against the relaxed IoU fusing
%       distant objects (default: ``1`` = isotropic, no relaxation)
%     - ``.iouFloor`` - lower clamp for the anisotropy-relaxed IoU threshold, so
%       it never falls below a meaningful value (default: ``0.05``)
%     - ``.maxCentroidShift`` - reject a link when the two objects' centroids are
%       more than this many pixels apart (scaled by the slice gap for
%       ``zLookback`` > 1). Lets IoU be relaxed for anisotropy without letting
%       far-apart objects merge (default: ``Inf`` = gate disabled)
%     - ``.centroidLinkRadius`` - enable centroid-nearest-neighbour gap bridging
%       (``'graph'`` only). For objects that have **no** overlap partner on a
%       slice pair, add a link to the mutually-nearest such orphan on the other
%       slice when their centroids are within this many pixels (scaled by the
%       slice gap). Reconnects a continuation that is laterally displaced or
%       briefly absent - the residual split the overlap graph cannot see
%       (default: ``0`` = disabled)
%     - ``.centroidSizeRatio`` - a centroid-NN link additionally requires
%       ``min(areaA,areaB)/max(areaA,areaB)`` to be at least this, so only
%       comparably-sized objects are bridged (default: ``0.5``)
%     - ``.bidirectional`` - for ``'hungarian'``, also run a reverse pass and
%       reconcile (default: ``true``; ignored by ``'graph'``)
%     - ``.verbose`` - logical, print a short summary (default: ``false``)
%
%   - **wb** - *(optional)* handle of a caller-owned ``uiprogressdlg``, created
%     with ``'Cancelable', 'on'``. Its ``Message`` is updated with the current
%     phase and slice counter, and ``CancelRequested`` is polled in every loop,
%     so a stitch over a large stack can be interrupted. Pass ``[]`` for none.
%     ``Value`` is left alone - the caller owns it, because it may be stitching
%     several volumes and scaling the bar over all of them. This replaces the
%     former ``options.showWaitbar``, which could never work: it built a
%     :class:`core.PoolWaitbar` with an empty parent, which that class rejects
%
% Output Arguments:
%   - **labelVol** - ``[height, width, depth]`` relabelled 3D instance volume,
%     IDs 1..K compacted, class ``uint16`` (or ``uint32`` if K > 65535). Empty
%     when the user cancelled
%   - **stats** - structure with ``.numInput2DObjects``, ``.numOutput3DObjects``,
%     ``.objectVoxelCounts`` (K×1), ``.objectSliceCounts`` (K×1, empty unless
%     ``minObjectSlices`` was used), ``.numAbsorbedFragments`` and
%     ``.numAbsorbedVoxels`` (both 0 unless ``absorbFragmentVoxels`` was used),
%     ``.cancelled`` (logical; when ``true`` nothing else in the structure is
%     meaningful and ``labelVol`` is empty), ``.method``, ``.options``
%
% Notes:
%   - Over-merging (one output object swallowing most of the stack) is almost
%     always caused by per-slice labels whose pixels form several separate
%     blobs - check with ``bwconncomp`` on a slice and compare the component
%     count against ``numel(unique(slice(slice>0)))``. ``splitDisconnected2D``
%     (on by default) removes that failure mode.
%   - Memory: the output volume is materialised in RAM (same footprint order
%     as the input). The graph itself needs only a union-find array over the
%     total 2D-object count plus two slices at a time.
%   - ``matchpairs`` (used by ``'hungarian'``) is a core MATLAB function and
%     needs no toolbox.
%
% **Example 1** - stitch a folder of 2D label tiffs read into a volume:
%
%   .. code-block:: matlab
%
%      files = dir(fullfile(folder, '*.tif'));
%      V = zeros(h, w, numel(files), 'uint16');
%      for z = 1:numel(files); V(:,:,z) = imread(fullfile(folder, files(z).name)); end
%      opt.iouThreshold = 0.25;
%      L = utils.instances.stitch2Dto3D(V, opt);
%
% **Example 2** - default one-liner on an in-memory stack, then inspect stats:
%
%   .. code-block:: matlab
%
%      [L, stats] = utils.instances.stitch2Dto3D(V);
%      fprintf('%d 2D objects -> %d 3D instances\n', ...
%          stats.numInput2DObjects, stats.numOutput3DObjects);
%      histogram(stats.objectVoxelCounts);   % 3D object size distribution
%
% **Example 3** - drop noise fragments (typical for a large, noisy stack such as
% an EM mitochondria volume):
%
%   .. code-block:: matlab
%
%      opt = struct('minObjectVoxels', 200, 'verbose', true);
%      L = utils.instances.stitch2Dto3D(V, opt);   % objects < 200 voxels removed
%
%   A false detection can be large in-plane yet live on one slice only, which no
%   voxel count will catch. Add a depth threshold for those:
%
%   .. code-block:: matlab
%
%      opt.minObjectSlices = 2;   % also drop anything seen on 1 or 2 slices
%      L = utils.instances.stitch2Dto3D(V, opt);
%
%   Specks that sit *inside* a real object should be given back to it rather than
%   deleted, which would leave a hole:
%
%   .. code-block:: matlab
%
%      opt.absorbFragmentVoxels = 4;   % <=4-voxel objects join their neighbour
%      [L, stats] = utils.instances.stitch2Dto3D(V, opt);
%      fprintf('%d fragments absorbed (%d voxels)\n', ...
%          stats.numAbsorbedFragments, stats.numAbsorbedVoxels);
%
% **Example 4** - bridge single-slice dropouts (an object that vanishes for one
% plane and reappears) by matching across a 2-slice gap:
%
%   .. code-block:: matlab
%
%      opt.zLookback = 2;          % test slices z-1 and z-2 against z
%      opt.ioaThreshold = 0.4;     % looser containment test for thin bridges
%      L = utils.instances.stitch2Dto3D(V, opt);
%
% **Example 5** - faithful empanada-style pipeline (1-to-1 Hungarian matching
% + IoA merge-in, forward and reverse passes) for comparison against ``'graph'``:
%
%   .. code-block:: matlab
%
%      opt = struct('method', 'hungarian', 'bidirectional', true, ...
%                   'iouThreshold', 0.25, 'ioaThreshold', 0.5);
%      Lh = utils.instances.stitch2Dto3D(V, opt);
%
% **Example 6** - apply to the active MIB dataset's labels layer (once wired
% into MIB, this is the intended call site):
%
%   .. code-block:: matlab
%
%      id = obj.mibModel.getActiveId();
%      V  = obj.mibModel.getData3D('labels', [], 3, NaN, struct('id', id));
%      L  = utils.instances.stitch2Dto3D(V{1});
%      obj.mibModel.setData3D({L}, 'labels', [], 3, NaN, struct('id', id));
%      notify(obj.mibModel, 'ShowImage');
%
% **Example 7** - conservative linking (require a strong IoU, ignore weak
% containment) to keep touching-but-distinct objects separate:
%
%   .. code-block:: matlab
%
%      opt = struct('iouThreshold', 0.5, 'ioaThreshold', 1.01, ...
%                   'minOverlapPixels', 20);   % ioaThreshold>1 disables IoA links
%      L = utils.instances.stitch2Dto3D(V, opt);
%
% **Example 8** - report progress and let the user stop a long stitch:
%
%   .. code-block:: matlab
%
%      wb = uiprogressdlg(parentFigure, 'Title', 'Stitch 2D instances to 3D', ...
%          'Indeterminate', 'on', 'Cancelable', 'on');
%      [L, stats] = utils.instances.stitch2Dto3D(V, opt, wb);
%      delete(wb);
%      if stats.cancelled; return; end   % L is empty, nothing was produced

% Updates
%

if nargin < 3; wb = []; end
if nargin < 2; options = struct(); end
if ~isfield(options, 'method');           options.method = 'graph'; end
if ~isfield(options, 'splitDisconnected2D'); options.splitDisconnected2D = true; end
if ~isfield(options, 'iouThreshold');     options.iouThreshold = 0.25; end
if ~isfield(options, 'ioaThreshold');     options.ioaThreshold = 0.50; end
if ~isfield(options, 'minOverlapPixels'); options.minOverlapPixels = 5; end
if ~isfield(options, 'absOverlapPixels'); options.absOverlapPixels = 0; end
if ~isfield(options, 'zLookback');        options.zLookback = 1; end
if ~isfield(options, 'minObjectVoxels');  options.minObjectVoxels = 0; end
if ~isfield(options, 'minObjectSlices');  options.minObjectSlices = 0; end
if ~isfield(options, 'absorbFragmentVoxels'); options.absorbFragmentVoxels = 5; end
if ~isfield(options, 'anisotropyZ');      options.anisotropyZ = 1; end
if ~isfield(options, 'iouFloor');         options.iouFloor = 0.05; end
if ~isfield(options, 'maxCentroidShift'); options.maxCentroidShift = inf; end
if ~isfield(options, 'centroidLinkRadius'); options.centroidLinkRadius = 0; end
if ~isfield(options, 'centroidSizeRatio');  options.centroidSizeRatio = 0.5; end
if ~isfield(options, 'bidirectional');    options.bidirectional = true; end
if ~isfield(options, 'verbose');          options.verbose = false; end

depth = size(inputVol, 3);

% Progress and cancellation, both through the caller's wb. The message is
% refreshed only every messageStep slices - a uifigure property write forces a
% redraw, which on a thousand-slice stack costs more than the work it reports
% on. The cancel poll runs on every slice, though - one slice is enough work to
% be worth interrupting, and a Cancel button that only answers once a percent is
% not one the user can rely on.
messageStep = max(1, floor(depth/100));

% -- Pass 1: relabel every slice to compact 1..n and count objects per slice
% Store the compacted slices as int32 planes so the ID values never collide
% between slices once the per-slice offset is added.
compactSlices = cell(depth, 1);
countPerSlice = zeros(depth, 1);
for z = 1:depth
    if localCancelled(wb); [labelVol, stats] = localCancelledResult(options); return; end
    if mod(z, messageStep) == 0
        localReport(wb, sprintf('Splitting 2D objects: slice %d of %d...', z, depth));
    end
    [compactSlices{z}, countPerSlice(z)] = localCompact(inputVol(:,:,z), options.splitDisconnected2D);
end
offset = [0; cumsum(countPerSlice)];   % global node = offset(z) + localLabel
totalNodes = offset(end);

if totalNodes == 0    % empty input
    labelVol = zeros(size(inputVol), 'uint16');
    stats = struct('numInput2DObjects', 0, 'numOutput3DObjects', 0, ...
        'objectVoxelCounts', [], 'objectSliceCounts', [], ...
        'numAbsorbedFragments', 0, 'numAbsorbedVoxels', 0, 'cancelled', false, ...
        'method', options.method, 'options', options);
    return;
end

% union-find parent array over all 2D objects in the stack
parent = (1:totalNodes)';

switch lower(options.method)
    case 'graph'
        for z = 2:depth
            if localCancelled(wb); [labelVol, stats] = localCancelledResult(options); return; end
            if mod(z, messageStep) == 0
                localReport(wb, sprintf('Linking objects across Z: slice %d of %d...', z, depth));
            end
            for g = 1:min(options.zLookback, z-1)
                parent = localLinkPair(parent, ...
                    compactSlices{z-g}, offset(z-g), countPerSlice(z-g), ...
                    compactSlices{z},   offset(z),   countPerSlice(z), options, false, g);
            end
        end
    case 'hungarian'
        % forward pass
        for z = 2:depth
            if localCancelled(wb); [labelVol, stats] = localCancelledResult(options); return; end
            if mod(z, messageStep) == 0
                localReport(wb, sprintf('Linking objects across Z: slice %d of %d...', z, depth));
            end
            parent = localLinkPair(parent, ...
                compactSlices{z-1}, offset(z-1), countPerSlice(z-1), ...
                compactSlices{z},   offset(z),   countPerSlice(z), options, true, 1);
        end
        % reverse pass (reconciled via the shared union-find)
        if options.bidirectional
            for z = depth:-1:2
                if localCancelled(wb); [labelVol, stats] = localCancelledResult(options); return; end
                if mod(z, messageStep) == 0
                    localReport(wb, sprintf('Linking objects across Z (reverse pass): slice %d of %d...', z, depth));
                end
                parent = localLinkPair(parent, ...
                    compactSlices{z},   offset(z),   countPerSlice(z), ...
                    compactSlices{z-1}, offset(z-1), countPerSlice(z-1), options, true, 1);
            end
        end
    otherwise
        error('utils:instances:stitch2Dto3D:badMethod', ...
            'Unknown method "%s" (use "graph" or "hungarian")', options.method);
end
localReport(wb, 'Building the 3D instance volume...');

% -- Flatten union-find to root ids, then compact roots to 1..K
root = localFindAll(parent);
[uRoots, ~, rootCompact] = unique(root);   % rootCompact maps node->1..K
numObjects = numel(uRoots);

% node -> final id lookup
node2id = rootCompact;   % totalNodes x 1

% -- Build output volume
outClass = 'uint16';
if numObjects > 65535; outClass = 'uint32'; end
labelVol = zeros(size(inputVol), outClass);
for z = 1:depth
    cs = compactSlices{z};
    nz = cs > 0;
    if any(nz(:))
        globalNodes = double(cs(nz)) + offset(z);
        plane = zeros(size(cs), outClass);
        plane(nz) = node2id(globalNodes);
        labelVol(:,:,z) = plane;
    end
end

objectVoxelCounts = accumarray(labelVol(labelVol>0), 1, [numObjects 1]);

% -- Fragment absorption plus the two size filters, then a relabel to a
% contiguous 1..K. Shared with the instance editor, which offers the same
% cleanup on an already-stitched model, so the thresholds behave identically
% whether they are applied during stitching or afterwards.
cleanupOptions.absorbFragmentVoxels = options.absorbFragmentVoxels;
cleanupOptions.minObjectVoxels = options.minObjectVoxels;
cleanupOptions.minObjectSlices = options.minObjectSlices;
cleanupOptions.compact = true;
cleanupOptions.objectVoxelCounts = objectVoxelCounts;
[labelVol, cleanupStats, cancelled] = utils.instances.cleanup(labelVol, cleanupOptions, wb);
if cancelled; [labelVol, stats] = localCancelledResult(options); return; end
numObjects = cleanupStats.numObjects;

stats = struct();
stats.numInput2DObjects = totalNodes;
stats.numOutput3DObjects = numObjects;
stats.objectVoxelCounts = cleanupStats.objectVoxelCounts;
stats.objectSliceCounts = cleanupStats.objectSliceCounts;   % empty unless minObjectSlices was used
stats.numAbsorbedFragments = cleanupStats.numAbsorbedFragments;
stats.numAbsorbedVoxels = cleanupStats.numAbsorbedVoxels;
stats.cancelled = false;
stats.method = options.method;
stats.options = options;

if options.verbose
    fprintf('stitch2Dto3D: %d 2D objects across %d slices -> %d 3D instances (method=%s)\n', ...
        totalNodes, depth, numObjects, options.method);
end
end

% =====================================================================
function cancelled = localCancelled(wb)
% true once the user has pressed Cancel on the caller's progress dialog
cancelled = ~isempty(wb) && isvalid(wb) && wb.CancelRequested;
end

% =====================================================================
function localReport(wb, message)
% show the current phase on the caller's progress dialog, if there is one
if ~isempty(wb) && isvalid(wb); wb.Message = message; end
end

% =====================================================================
function [labelVol, stats] = localCancelledResult(options)
% Common exit for a cancelled run: no partial volume is returned, because a
% half-linked stack looks like a valid result and would silently be written
% over the user's model. The caller checks stats.cancelled.
labelVol = [];
stats = struct('numInput2DObjects', 0, 'numOutput3DObjects', 0, ...
    'objectVoxelCounts', [], 'objectSliceCounts', [], ...
    'numAbsorbedFragments', 0, 'numAbsorbedVoxels', 0, 'cancelled', true, ...
    'method', options.method, 'options', options);
end

% =====================================================================
function [compact, n] = localCompact(slice, splitDisconnected)
% relabel a 2D slice's positive labels to a contiguous 1..n (int32), 0=bg
if nargin < 2; splitDisconnected = true; end
slice = double(slice);
pos = slice > 0;
if ~any(pos(:)); compact = zeros(size(slice), 'int32'); n = 0; return; end
vals = slice(pos);
u = unique(vals);
n = numel(u);
lut = zeros(max(u) + 1, 1);
lut(u + 1) = 1:n;
compact = zeros(size(slice), 'int32');
compact(pos) = int32(lut(vals + 1));

if ~splitDisconnected; return; end

% Give every connected component of a label its own node. A 2D predictor may
% hand the same index to several separate blobs; keeping them as one node
% welds their 3D chains together and the welds chain across slices, collapsing
% the stack into one giant object. Each label is cropped to its bounding box
% first, so the cost stays proportional to the objects' area, not n * slice.
boxes = regionprops(double(compact), 'BoundingBox');
split = zeros(size(compact), 'int32');
next = 0;
for k = 1:n
    box = boxes(k).BoundingBox;
    col1 = floor(box(1)) + 1;   col2 = col1 + box(3) - 1;
    row1 = floor(box(2)) + 1;   row2 = row1 + box(4) - 1;
    subMask = compact(row1:row2, col1:col2) == k;
    components = bwconncomp(subMask, 8);
    subSplit = split(row1:row2, col1:col2);
    for c = 1:components.NumObjects
        next = next + 1;
        subSplit(components.PixelIdxList{c}) = next;
    end
    split(row1:row2, col1:col2) = subSplit;
end
compact = split;
n = next;
end

% =====================================================================
function parent = localLinkPair(parent, csA, offA, nA, csB, offB, nB, options, useHungarian, gap)
% Score overlaps between two compacted slices and union linked object pairs.
if nA == 0 || nB == 0; return; end
if nargin < 10 || isempty(gap); gap = 1; end

useCentroidLink = options.centroidLinkRadius > 0;

% Overlap of the two slices. With centroid-NN linking on we must not bail out
% when there is no overlap - that pure-gap case is exactly what NN bridges.
mask = csA > 0 & csB > 0;
hasOverlap = any(mask(:));
if ~hasOverlap && ~useCentroidLink; return; end

% Full areas (over the whole slice, not just the overlap region).
areaA = accumarray(double(csA(csA > 0)), 1, [nA 1]);
areaB = accumarray(double(csB(csB > 0)), 1, [nB 1]);

% Object centroids, needed by the centroid-shift gate and/or centroid-NN links.
needCentroids = isfinite(options.maxCentroidShift) || useCentroidLink;
if needCentroids
    [ryA, rxA] = find(csA > 0);  labA = double(csA(csA > 0));
    cxA = accumarray(labA, rxA, [nA 1]) ./ areaA;
    cyA = accumarray(labA, ryA, [nA 1]) ./ areaA;
    [ryB, rxB] = find(csB > 0);  labB = double(csB(csB > 0));
    cxB = accumarray(labB, rxB, [nB 1]) ./ areaB;
    cyB = accumarray(labB, ryB, [nB 1]) ./ areaB;
end

% Overlap-based candidate pairs (empty when the slices share no pixels).
if hasOverlap
    la = double(csA(mask));
    lb = double(csB(mask));
    key = la + (lb - 1) * nA;
    [uk, ~, ic] = unique(key);
    inter = accumarray(ic, 1);
    ia = mod(uk - 1, nA) + 1;
    ib = floor((uk - 1) / nA) + 1;
    au = areaA(ia);
    bu = areaB(ib);
    iou = inter ./ (au + bu - inter);
    ioa = inter ./ min(au, bu);
else
    inter = zeros(0, 1); ia = zeros(0, 1); ib = zeros(0, 1);
    iou = zeros(0, 1); ioa = zeros(0, 1);
end

% Anisotropy: relax the effective IoU threshold when sections are thick
% (true continuations are more displaced, so their IoU drops). IoA is left
% unchanged - containment is scale-robust.
effIouThreshold = options.iouThreshold;
if options.anisotropyZ > 1
    effIouThreshold = max(options.iouThreshold / options.anisotropyZ, options.iouFloor);
end

% Centroid-shift gate: an overlap pair whose object centroids are farther apart
% than maxCentroidShift (scaled by the slice gap) is rejected, so the relaxed
% IoU cannot fuse distant objects.
centroidOK = true(size(ia));
if isfinite(options.maxCentroidShift) && ~isempty(ia)
    centroidDist = hypot(cxA(ia) - cxB(ib), cyA(ia) - cyB(ib));
    centroidOK = centroidDist <= options.maxCentroidShift * gap;
end

% Absolute-overlap link: IoU and IoA are both ratios against object area, so a
% large cross-section meeting a much smaller one scores low on each even when
% the shared area is large in absolute terms. A sufficient condition on the raw
% intersection catches that; the centroid gate above still applies.
if options.absOverlapPixels > 0
    absOverlapOK = inter >= options.absOverlapPixels;
else
    absOverlapOK = false(size(inter));
end

if ~useHungarian
    % graph: link on IoU OR IoA above threshold, or on a large absolute overlap
    sel = inter >= options.minOverlapPixels & centroidOK & ...
        (iou >= effIouThreshold | ioa >= options.ioaThreshold | absOverlapOK);
    ea = ia(sel); eb = ib(sel);

    % Centroid-NN gap bridging: for objects left with no overlap link on this
    % slice pair (orphans), add a link to the mutually-nearest orphan on the
    % other slice when within centroidLinkRadius (scaled by gap) and of
    % comparable size. Reconnects a continuation that is displaced or briefly
    % absent - the residual failure the overlap graph cannot see.
    if useCentroidLink
        hasLinkA = false(nA, 1); hasLinkA(ea) = true;
        hasLinkB = false(nB, 1); hasLinkB(eb) = true;
        orphA = find(~hasLinkA);
        orphB = find(~hasLinkB);
        if ~isempty(orphA) && ~isempty(orphB)
            dist = hypot(cxA(orphA) - cxB(orphB)', cyA(orphA) - cyB(orphB)');
            sizeRatio = min(areaA(orphA), areaB(orphB)') ./ max(areaA(orphA), areaB(orphB)');
            dist(dist > options.centroidLinkRadius * gap | ...
                 sizeRatio < options.centroidSizeRatio) = inf;
            [nearestDist, nnB] = min(dist, [], 2);   % nearest orphB for each orphA
            [~, nnA] = min(dist, [], 1);             % nearest orphA for each orphB
            for ii = 1:numel(orphA)
                jj = nnB(ii);
                if isfinite(nearestDist(ii)) && nnA(jj) == ii   % mutual NN
                    ea(end+1, 1) = orphA(ii); eb(end+1, 1) = orphB(jj); %#ok<AGROW>
                end
            end
        end
    end
else
    % hungarian: 1-to-1 max-IoU assignment, then IoA merge for the rest
    valid = inter >= options.minOverlapPixels & centroidOK;
    ivA = ia(valid); ivB = ib(valid); ivIoU = iou(valid);
    ea = []; eb = [];
    matchedB = false(nB, 1);
    if ~isempty(ivIoU)
        % build cost matrix (dense over the objects that share any overlap)
        aList = unique(ivA); bList = unique(ivB);
        [~, ai] = ismember(ivA, aList);
        [~, bi] = ismember(ivB, bList);
        C = zeros(numel(aList), numel(bList));
        C(sub2ind(size(C), ai, bi)) = ivIoU;
        % matchpairs minimises cost; use -IoU, reject below-threshold matches
        M = matchpairs(-C, -effIouThreshold);
        for k = 1:size(M, 1)
            gA = aList(M(k, 1)); gB = bList(M(k, 2));
            if C(M(k, 1), M(k, 2)) >= effIouThreshold
                ea(end+1, 1) = gA; eb(end+1, 1) = gB; %#ok<AGROW>
                matchedB(gB) = true;
            end
        end
    end
    % IoA merge-in: any B object not matched but strongly contained in an A
    % object, or sharing a large absolute overlap with one
    ioaValid = (ioa >= options.ioaThreshold | absOverlapOK) & inter >= options.minOverlapPixels;
    ivmA = ia(ioaValid); ivmB = ib(ioaValid); ivmIoA = ioa(ioaValid);
    [ivmB, order] = sort(ivmB); ivmA = ivmA(order); ivmIoA = ivmIoA(order);
    prevB = -1; bestIoA = -1; bestA = -1;
    for k = 1:numel(ivmB)
        if ivmB(k) ~= prevB
            if prevB > 0 && ~matchedB(prevB)
                ea(end+1, 1) = bestA; eb(end+1, 1) = prevB; %#ok<AGROW>
            end
            prevB = ivmB(k); bestIoA = -1; bestA = -1;
        end
        if ivmIoA(k) > bestIoA; bestIoA = ivmIoA(k); bestA = ivmA(k); end
    end
    if prevB > 0 && ~matchedB(prevB)
        ea(end+1, 1) = bestA; eb(end+1, 1) = prevB;
    end
end

% union linked pairs (global node ids)
for k = 1:numel(ea)
    parent = localUnion(parent, offA + ea(k), offB + eb(k));
end
end

% =====================================================================
function parent = localUnion(parent, a, b)
ra = localFind(parent, a);
rb = localFind(parent, b);
if ra ~= rb
    if ra < rb; parent(rb) = ra; else; parent(ra) = rb; end
end
end

function r = localFind(parent, x)
r = x;
while parent(r) ~= r; r = parent(r); end
end

function root = localFindAll(parent)
% fully flatten every node to its root
root = parent;
changed = true;
while changed
    newRoot = root(root);
    changed = ~isequal(newRoot, root);
    root = newRoot;
end
end
