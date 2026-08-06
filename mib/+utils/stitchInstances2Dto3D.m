function [labelVol, stats] = stitchInstances2Dto3D(inputVol, options)
% STITCHINSTANCES2DTO3D - Stitch per-slice 2D instance labels into a 3D instance volume.
%
% Syntax:
%   .. code-block:: matlab
%
%       labelVol = utils.stitchInstances2Dto3D(inputVol)
%       [labelVol, stats] = utils.stitchInstances2Dto3D(inputVol, options)
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
%     - ``.iouThreshold`` - link objects whose IoU exceeds this (default: ``0.25``)
%     - ``.ioaThreshold`` - link when intersection-over-smaller-area exceeds
%       this, catching splits/thin bridges (default: ``0.50``)
%     - ``.minOverlapPixels`` - absolute minimum intersection to consider a
%       link, guards against 1-2 px spurious overlaps (default: ``5``)
%     - ``.zLookback`` - also test slices up to this many planes apart, to
%       bridge single-slice dropouts (default: ``1`` = adjacent only)
%     - ``.minObjectVoxels`` - remove 3D objects smaller than this after
%       stitching (default: ``0`` = keep all)
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
%     - ``.showWaitbar`` - logical, show progress (default: ``false``)
%     - ``.verbose`` - logical, print a short summary (default: ``false``)
%
% Output Arguments:
%   - **labelVol** - ``[height, width, depth]`` relabelled 3D instance volume,
%     IDs 1..K compacted, class ``uint16`` (or ``uint32`` if K > 65535)
%   - **stats** - structure with ``.numInput2DObjects``, ``.numOutput3DObjects``,
%     ``.objectVoxelCounts`` (K×1), ``.method``, ``.options``
%
% Notes:
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
%      L = utils.stitchInstances2Dto3D(V, opt);
%
% **Example 2** - default one-liner on an in-memory stack, then inspect stats:
%
%   .. code-block:: matlab
%
%      [L, stats] = utils.stitchInstances2Dto3D(V);
%      fprintf('%d 2D objects -> %d 3D instances\n', ...
%          stats.numInput2DObjects, stats.numOutput3DObjects);
%      histogram(stats.objectVoxelCounts);   % 3D object size distribution
%
% **Example 3** - drop noise fragments and show a progress bar (typical for a
% large, noisy stack such as an EM mitochondria volume):
%
%   .. code-block:: matlab
%
%      opt = struct('minObjectVoxels', 200, 'showWaitbar', true, 'verbose', true);
%      L = utils.stitchInstances2Dto3D(V, opt);   % objects < 200 voxels removed
%
% **Example 4** - bridge single-slice dropouts (an object that vanishes for one
% plane and reappears) by matching across a 2-slice gap:
%
%   .. code-block:: matlab
%
%      opt.zLookback = 2;          % test slices z-1 and z-2 against z
%      opt.ioaThreshold = 0.4;     % looser containment test for thin bridges
%      L = utils.stitchInstances2Dto3D(V, opt);
%
% **Example 5** - faithful empanada-style pipeline (1-to-1 Hungarian matching
% + IoA merge-in, forward and reverse passes) for comparison against ``'graph'``:
%
%   .. code-block:: matlab
%
%      opt = struct('method', 'hungarian', 'bidirectional', true, ...
%                   'iouThreshold', 0.25, 'ioaThreshold', 0.5);
%      Lh = utils.stitchInstances2Dto3D(V, opt);
%
% **Example 6** - apply to the active MIB dataset's labels layer (once wired
% into MIB, this is the intended call site):
%
%   .. code-block:: matlab
%
%      id = obj.mibModel.getActiveId();
%      V  = obj.mibModel.getData3D('labels', [], 3, NaN, struct('id', id));
%      L  = utils.stitchInstances2Dto3D(V{1});
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
%      L = utils.stitchInstances2Dto3D(V, opt);

% Updates
%

if nargin < 2; options = struct(); end
if ~isfield(options, 'method');           options.method = 'graph'; end
if ~isfield(options, 'iouThreshold');     options.iouThreshold = 0.25; end
if ~isfield(options, 'ioaThreshold');     options.ioaThreshold = 0.50; end
if ~isfield(options, 'minOverlapPixels'); options.minOverlapPixels = 5; end
if ~isfield(options, 'zLookback');        options.zLookback = 1; end
if ~isfield(options, 'minObjectVoxels');  options.minObjectVoxels = 0; end
if ~isfield(options, 'anisotropyZ');      options.anisotropyZ = 1; end
if ~isfield(options, 'iouFloor');         options.iouFloor = 0.05; end
if ~isfield(options, 'maxCentroidShift'); options.maxCentroidShift = inf; end
if ~isfield(options, 'centroidLinkRadius'); options.centroidLinkRadius = 0; end
if ~isfield(options, 'centroidSizeRatio');  options.centroidSizeRatio = 0.5; end
if ~isfield(options, 'bidirectional');    options.bidirectional = true; end
if ~isfield(options, 'showWaitbar');      options.showWaitbar = false; end
if ~isfield(options, 'verbose');          options.verbose = false; end

depth = size(inputVol, 3);

% -- Pass 1: relabel every slice to compact 1..n and count objects per slice
% Store the compacted slices as int32 planes so the ID values never collide
% between slices once the per-slice offset is added.
compactSlices = cell(depth, 1);
countPerSlice = zeros(depth, 1);
for z = 1:depth
    [compactSlices{z}, countPerSlice(z)] = localCompact(inputVol(:,:,z));
end
offset = [0; cumsum(countPerSlice)];   % global node = offset(z) + localLabel
totalNodes = offset(end);

if totalNodes == 0    % empty input
    labelVol = zeros(size(inputVol), 'uint16');
    stats = struct('numInput2DObjects', 0, 'numOutput3DObjects', 0, ...
        'objectVoxelCounts', [], 'method', options.method, 'options', options);
    return;
end

% union-find parent array over all 2D objects in the stack
parent = (1:totalNodes)';

if options.showWaitbar
    pwb = core.PoolWaitbar(depth-1, sprintf('Stitching 2D instances into 3D\nPlease wait...'), [], '2D->3D stitching');
else
    pwb = [];
end

switch lower(options.method)
    case 'graph'
        for z = 2:depth
            for g = 1:min(options.zLookback, z-1)
                parent = localLinkPair(parent, ...
                    compactSlices{z-g}, offset(z-g), countPerSlice(z-g), ...
                    compactSlices{z},   offset(z),   countPerSlice(z), options, false, g);
            end
            if ~isempty(pwb); pwb.increment(); end
        end
    case 'hungarian'
        % forward pass
        for z = 2:depth
            parent = localLinkPair(parent, ...
                compactSlices{z-1}, offset(z-1), countPerSlice(z-1), ...
                compactSlices{z},   offset(z),   countPerSlice(z), options, true, 1);
            if ~isempty(pwb); pwb.increment(); end
        end
        % reverse pass (reconciled via the shared union-find)
        if options.bidirectional
            for z = depth:-1:2
                parent = localLinkPair(parent, ...
                    compactSlices{z},   offset(z),   countPerSlice(z), ...
                    compactSlices{z-1}, offset(z-1), countPerSlice(z-1), options, true, 1);
            end
        end
    otherwise
        if ~isempty(pwb); delete(pwb); end
        error('utils:stitchInstances2Dto3D:badMethod', ...
            'Unknown method "%s" (use "graph" or "hungarian")', options.method);
end
if ~isempty(pwb); delete(pwb); end

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

% -- Optional small-object removal + relabel
objectVoxelCounts = accumarray(labelVol(labelVol>0), 1, [numObjects 1]);
if options.minObjectVoxels > 0
    keep = objectVoxelCounts >= options.minObjectVoxels;
    remap = zeros(numObjects, 1);
    remap(keep) = 1:nnz(keep);
    nzAll = labelVol > 0;
    newVals = remap(labelVol(nzAll));
    labelVol(nzAll) = newVals;
    numObjects = nnz(keep);
    objectVoxelCounts = objectVoxelCounts(keep);
    if numObjects <= 65535 && ~isa(labelVol, 'uint16')
        labelVol = uint16(labelVol);
    end
end

stats = struct();
stats.numInput2DObjects = totalNodes;
stats.numOutput3DObjects = numObjects;
stats.objectVoxelCounts = objectVoxelCounts;
stats.method = options.method;
stats.options = options;

if options.verbose
    fprintf('stitchInstances2Dto3D: %d 2D objects across %d slices -> %d 3D instances (method=%s)\n', ...
        totalNodes, depth, numObjects, options.method);
end
end

% =====================================================================
function [compact, n] = localCompact(slice)
% relabel a 2D slice's positive labels to a contiguous 1..n (int32), 0=bg
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

if ~useHungarian
    % graph: link on IoU OR IoA above threshold
    sel = inter >= options.minOverlapPixels & centroidOK & ...
        (iou >= effIouThreshold | ioa >= options.ioaThreshold);
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
    % IoA merge-in: any B object not matched but strongly contained in an A object
    ioaValid = ioa >= options.ioaThreshold & inter >= options.minOverlapPixels;
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
