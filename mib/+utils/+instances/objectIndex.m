function [index, cancelled] = objectIndex(labelVol, options, wb)
% OBJECTINDEX - Build a per-object index (bounding box, size, centroid) of an instance label volume.
%
% Syntax:
%   .. code-block:: matlab
%
%       index = utils.instances.objectIndex(labelVol)
%       index = utils.instances.objectIndex(labelVol, options)
%       [index, cancelled] = utils.instances.objectIndex(labelVol, options, wb)
%
% Instance models produced by ``utils.instances.stitch2Dto3D`` hold thousands of
% objects in a volume of several GB. Every question an interactive editor asks
% about a single object - where is it, how big is it, how many slices does it
% span, which index is free next - is a full-volume scan unless the answers are
% cached. This function builds that cache, and can refresh a part of it after an
% edit without rescanning the volume.
%
% The index is **sparse**: it has one row per object that has voxels, sorted by
% index, and ``.ids`` names the object of each row. Its size therefore follows
% the number of objects, not the highest index: a BigData model of type
% 1073741823 can use indices near 1e9, and an index with one row per possible
% value (about 45 bytes each) would need 45 GB there. Look an object up with
% ``ismember``::
%
%     [found, row] = ismember(objectId, index.ids);
%     if found; box = double(index.bbox(row, :)); end
%
% ``PixelIdxList`` is deliberately **not** stored - it is the one per-object
% quantity whose size grows with the data, and it is cheap to derive from the
% bounding box when a single object is actually operated on::
%
%     bb  = double(index.bbox(row, :));
%     sub = labelVol(bb(1):bb(2), bb(3):bb(4), bb(5):bb(6));
%     idx = dataset.convertPixelIdxListCrop2Full(find(sub == objectId), ...
%             struct('y', bb(1:2), 'x', bb(3:4), 'z', bb(5:6)));
%
% **Full build.** Up to a highest index of 2^20 the volume is measured by one
% ``regionprops`` call, a single C pass that allocates only per label value;
% its result has one entry per value from 1 to the maximum, which is what makes
% it unusable above that. A volume with a higher index is measured slice by
% slice instead (``unique`` and ``accumarray`` over the labelled pixels of one
% plane), so memory follows one slice and the number of objects. Both routes
% give the same index.
%
% Input Arguments:
%   - **labelVol** - ``[height, width, depth]`` numeric array of instance labels
%     (0 = background). Any integer class; ``depth`` may be 1.
%   - **options** - *(optional)* structure of parameters:
%
%     - ``.index`` - an index returned by an earlier call, to be **refreshed in
%       place** rather than rebuilt (default: ``[]`` = full build). Requires
%       ``.objectIds``. Fields of the passed struct that this function does not
%       own (for example the caller's ``.timePoint``) are carried over untouched
%     - ``.objectIds`` - vector of label values whose extent may have changed.
%       Only their rows are recomputed. The caller must list **every** object
%       the edit could have touched, before and after: an object left out keeps
%       its stale bounding box, and acting on a stale box writes the wrong voxels
%     - ``.bbox`` - ``[yMin yMax xMin xMax zMin zMax]`` region in which voxels
%       changed (default: ``[]`` = the objects' own previous boxes only). The
%       rescan covers the union of this box and the previous boxes of
%       ``objectIds``, which is exactly where those objects can now have voxels:
%       their old voxels were inside their old boxes, and new voxels can only be
%       where the volume changed
%     - ``.previousSlices`` - ``[height, width, zMax-zMin+1]`` labels of the whole
%       slices ``bbox(5):bbox(6)`` as they were **before** the edit (default:
%       ``[]``). Turns the refresh into a difference over those slices: what each
%       object had on them before is taken out of its row and what it has now
%       is put in, and nothing outside them is read. For an edit confined to a
%       few slices of objects that span the stack - every 2-D edit of an
%       unstitched model - the union rule above would otherwise rescan nearly the
%       whole volume. Voxel count, centroid and slice count stay exact; the
%       bounding box only grows, see the note below. Requires ``.bbox``
%     - ``.computeSliceCount`` - fill ``.sliceCount`` of a full build (default:
%       ``true``). The only part of a ``regionprops`` build that needs its own
%       pass over the volume; set ``false`` when the count is not going to be
%       read. A refresh always fills it
%
%   - **wb** - *(optional)* handle of a caller-owned ``uiprogressdlg`` created
%     with ``'Cancelable', 'on'``. Its ``Message`` is updated and
%     ``CancelRequested`` polled; ``Value`` is left to the caller, which may be
%     scaling one bar over several volumes. Pass ``[]`` for no progress dialog.
%
% Output Arguments:
%   - **index** - structure with one row per present object, ``n = numObjects``:
%
%     - ``.ids`` - ``[n x 1]`` double, the index of the object of each row, sorted
%       ascending, without 0
%     - ``.voxels`` - ``[n x 1]`` uint32, voxel count
%     - ``.bbox`` - ``[n x 6]`` int32 ``[yMin yMax xMin xMax zMin zMax]``,
%       inclusive and 1-based, ready to be used as ``options.y/.x/.z`` of
%       ``getData3D`` / ``backup``
%     - ``.centroid`` - ``[n x 3]`` single ``[x y z]`` - the ``regionprops``
%       ordering, so it can be passed straight to ``MibDataset.moveView(x, y)``
%     - ``.sliceCount`` - ``[n x 1]`` uint32, number of z-slices the object
%       actually occupies (not its first-to-last span, so an object with a gap in
%       the middle is judged on the slices it is really on). All zero when
%       ``computeSliceCount`` was false
%     - ``.maxIndex`` - highest index in use, ``max(ids)``, 0 for an empty model
%     - ``.numObjects`` - ``numel(ids)``
%
%     Empty (``[]``) when the run was cancelled.
%   - **cancelled** - logical, true when the user pressed Cancel. No partial
%     index is returned: a half-filled index looks valid and its stale boxes
%     would silently corrupt the next edit.
%
% .. note::
%    The next free label value is the lowest positive integer not in ``.ids``:
%    the first gap of the sorted ids, or ``maxIndex + 1`` when there is none.
%
% .. note::
%    **A refresh from** ``previousSlices`` **never shrinks a bounding box** of an
%    object that still has voxels outside those slices. That part of the object
%    is known only by the box it already had, so when the edit removes the voxels
%    that set a box edge, the box stays larger than the object until the next
%    full build. This is safe - every reader uses the box as the bound of a
%    search - but such a row is not equal to a rebuilt one. An object that has
%    nothing left outside the slices gets its exact box. Every other refresh
%    gives exactly the index a full build of the edited volume gives.
%
% Usage:
%   **Example 1** - full build with a cancelable progress dialog
%
%   .. code-block:: matlab
%
%      wb = uiprogressdlg(parentFigure, 'Title', 'Indexing objects', ...
%          'Indeterminate', 'on', 'Cancelable', 'on');
%      [index, cancelled] = utils.instances.objectIndex(labelVol, struct(), wb);
%      delete(wb);
%      if cancelled; return; end
%
%   **Example 2** - refresh after merging object 12 into object 7
%
%   .. code-block:: matlab
%
%      refresh.index = index;
%      refresh.objectIds = [7, 12];
%      index = utils.instances.objectIndex(labelVol, refresh);
%
%   **Example 3** - bounding box of one object, as getData3D options
%
%   .. code-block:: matlab
%
%      [~, row] = ismember(objectId, index.ids);
%      bb = double(index.bbox(row, :));
%      getDataOptions.y = bb(1:2);  getDataOptions.x = bb(3:4);  getDataOptions.z = bb(5:6);
%
% See also: utils.instances.replaceIndexRows, core.MibDataset.buildInstanceIndex

% Updates
%

if nargin < 3; wb = []; end
if nargin < 2 || isempty(options); options = struct(); end

if ~isfield(options, 'index');             options.index = []; end
if ~isfield(options, 'objectIds');         options.objectIds = []; end
if ~isfield(options, 'bbox');              options.bbox = []; end
if ~isfield(options, 'previousSlices');    options.previousSlices = []; end
if ~isfield(options, 'computeSliceCount'); options.computeSliceCount = true; end

cancelled = false;

if ~isempty(options.index)
    index = localRefresh(labelVol, options);
    return;
end

%% Full build
maxIndex = double(max(labelVol, [], 'all'));
if isempty(maxIndex) || maxIndex == 0
    index = localEmptyIndex();
    return;
end

localReport(wb, 'Indexing objects: measuring bounding boxes...');
if localCancelled(wb); index = []; cancelled = true; return; end

% regionprops returns one struct per label value from 1 to the maximum, each
% field an array of its own: above about a million values that is more memory
% than the objects, near 1e9 it is out of reach.
if maxIndex > 2^20
    [index, cancelled] = localPlaneBuild(labelVol, wb);
    if cancelled; index = []; return; end
    if ~options.computeSliceCount; index.sliceCount(:) = 0; end
    return;
end

% One regionprops call rather than a hand-written accumulation: it is a single
% C pass that allocates only per object, where find/ind2sub over every labelled
% voxel of a multi-GB volume would need several arrays the size of the
% segmentation. The label matrix must be a non-sparse numeric array with
% positive integer values, which an instance model always is.
depth = size(labelVol, 3);
stats = regionprops(labelVol, {'Area', 'BoundingBox', 'Centroid'});
areas = [stats.Area]';
present = find(areas > 0);

index = localEmptyIndex();
index.ids = double(present(:));
index.voxels = uint32(areas(present));
if ~isempty(present)
    boxes = reshape([stats(present).BoundingBox], [], numel(present))';
    centroids = reshape([stats(present).Centroid], [], numel(present))';
    if depth == 1 && size(boxes, 2) == 4
        % regionprops drops the third dimension on a 2-D input: BoundingBox is
        % [x-0.5 y-0.5 w h] and Centroid is [x y]. Restore the single z plane so
        % that callers get the same 6-column box whatever the depth.
        boxes = [boxes(:, 1:2), 0.5 * ones(numel(present), 1), boxes(:, 3:4), ones(numel(present), 1)];
        centroids = [centroids, ones(numel(present), 1)];
    end
    xMin = ceil(boxes(:, 1));   yMin = ceil(boxes(:, 2));   zMin = ceil(boxes(:, 3));
    index.bbox = int32([yMin, yMin + boxes(:, 5) - 1, ...
                        xMin, xMin + boxes(:, 4) - 1, ...
                        zMin, zMin + boxes(:, 6) - 1]);
    index.centroid = single(centroids);
end
index.sliceCount = zeros(numel(present), 1, 'uint32');

if options.computeSliceCount
    [sliceCount, cancelled] = localSliceCounts(labelVol, maxIndex, wb);
    if cancelled; index = []; return; end
    index.sliceCount = sliceCount(present);
end

index.numObjects = numel(index.ids);
index.maxIndex = maxIndex;
end

% =====================================================================
function [index, cancelled] = localPlaneBuild(labelVol, wb)
% Full build one slice at a time, for a volume whose highest index is too large
% for regionprops.
%
% Each plane gives one row per object on it - voxel count, in-plane box and
% coordinate sums - from unique and accumarray over its labelled pixels. The
% rows of all planes are then combined per object; as every plane contributes
% at most one row per object, the number of rows of an object is the number
% of slices it is on.
cancelled = false;
index = localEmptyIndex();
depth = size(labelVol, 3);
planeIds = cell(depth, 1);
planeRows = cell(depth, 1);
messageStep = max(1, floor(depth/100));
for z = 1:depth
    if localCancelled(wb); cancelled = true; return; end
    if mod(z, messageStep) == 0
        localReport(wb, sprintf('Indexing objects: slice %d of %d...', z, depth));
    end
    plane = labelVol(:, :, z);
    linear = find(plane);
    if isempty(linear); continue; end
    [sliceIds, ~, slot] = unique(plane(linear));
    [y, x] = ind2sub(size(plane), linear);
    n = numel(sliceIds);
    % [voxels yMin yMax xMin xMax sumX sumY z]
    planeRows{z} = [accumarray(slot, 1, [n 1]), ...
        accumarray(slot, y, [n 1], @min), accumarray(slot, y, [n 1], @max), ...
        accumarray(slot, x, [n 1], @min), accumarray(slot, x, [n 1], @max), ...
        accumarray(slot, x, [n 1]), accumarray(slot, y, [n 1]), repmat(z, n, 1)];
    planeIds{z} = double(sliceIds(:));
end

allRows = vertcat(planeRows{:});
if isempty(allRows); return; end
[ids, ~, group] = unique(vertcat(planeIds{:}));
n = numel(ids);
voxels = accumarray(group, allRows(:, 1), [n 1]);
index.ids = ids;
index.voxels = uint32(voxels);
index.bbox = int32([accumarray(group, allRows(:, 2), [n 1], @min), accumarray(group, allRows(:, 3), [n 1], @max), ...
                    accumarray(group, allRows(:, 4), [n 1], @min), accumarray(group, allRows(:, 5), [n 1], @max), ...
                    accumarray(group, allRows(:, 8), [n 1], @min), accumarray(group, allRows(:, 8), [n 1], @max)]);
sums = [accumarray(group, allRows(:, 6), [n 1]), accumarray(group, allRows(:, 7), [n 1]), ...
        accumarray(group, allRows(:, 8) .* allRows(:, 1), [n 1])];
index.centroid = single(sums ./ voxels);
index.sliceCount = uint32(accumarray(group, 1, [n 1]));
index.numObjects = n;
index.maxIndex = ids(end);
end

% =====================================================================
function index = localRefresh(labelVol, options)
% Recompute a named subset of objects after a local edit.
%
% The rescan region is the union of the caller's changed box and the objects'
% *previous* boxes. That union is provably where those objects can have voxels
% now: anything they had before was inside their old boxes, and anything they
% gained can only be where the volume changed.

index = options.index;
objectIds = double(options.objectIds(:));
objectIds = unique(objectIds(objectIds > 0));
if isempty(objectIds); return; end

[height, width, depth] = size(labelVol, 1, 2, 3);

% Match against the volume's own class rather than casting the crop to double -
% the crop can be a large fraction of the volume when a big object is edited,
% and double() would quadruple it.
searchIds = cast(objectIds, 'like', labelVol);
if ~isequal(double(searchIds), objectIds)
    error('utils:instances:objectIndex:idOutOfRange', ...
        'objectIds do not fit the class of the label volume (%s); promote the model type first', ...
        class(labelVol));
end

if ~isempty(options.previousSlices)
    [index, done] = localRefreshFromSlices(labelVol, options, index, objectIds, searchIds);
    if done; return; end
end

region = options.bbox;
[isKnown, knownRows] = ismember(objectIds, index.ids);
if any(isKnown)
    previous = double(index.bbox(knownRows(isKnown), :));
    previousUnion = [min(previous(:, 1)), max(previous(:, 2)), ...
                     min(previous(:, 3)), max(previous(:, 4)), ...
                     min(previous(:, 5)), max(previous(:, 6))];
    if isempty(region)
        region = previousUnion;
    else
        region = [min(region(1), previousUnion(1)), max(region(2), previousUnion(2)), ...
                  min(region(3), previousUnion(3)), max(region(4), previousUnion(4)), ...
                  min(region(5), previousUnion(5)), max(region(6), previousUnion(6))];
    end
end
if isempty(region)
    region = [1, height, 1, width, 1, depth];
end
region = [max(1, region(1)), min(height, region(2)), ...
          max(1, region(3)), min(width,  region(4)), ...
          max(1, region(5)), min(depth,  region(6))];

sub = labelVol(region(1):region(2), region(3):region(4), region(5):region(6));
measured = localMeasure(sub, searchIds, region([1 3 5]), depth);

% Only objects that actually have voxels get a row; the rest lose theirs, so an
% object that lost all of its voxels in the edit comes back absent.
filled = measured.counts > 0;
rows = struct('ids', objectIds(filled), ...
    'voxels', measured.counts(filled), ...
    'bbox', measured.bbox(filled, :), ...
    'centroid', measured.sums(filled, :) ./ measured.counts(filled, 1), ...
    'sliceCount', measured.slices(filled));
index = utils.instances.replaceIndexRows(index, objectIds, rows);
end

% =====================================================================
function [index, done] = localRefreshFromSlices(labelVol, options, index, objectIds, searchIds)
% Refresh from whole slices only, as the difference between before and after.
%
% On an unstitched model the numbering restarts on every slice, so one index
% names an object on most slices and its box spans the stack. The union rule of
% localRefresh then rescans nearly the whole volume to account for an edit on
% one slice: 8.8 s per 2-D split on a 1636x2556x1250 uint16 model (2026-10-02).
%
% Everything a row holds except the box is a sum over voxels, so it can be
% corrected by what changed: the counts and coordinate sums of each object on
% these slices before the edit are taken out, the ones after are put in. Slices
% are taken whole so that "the object is on slice z" is known exactly from them.
%
% The box cannot be corrected that way - the rest of the object is known only by
% the box it already had - so it is widened to cover what the object now has
% here and never narrowed. An object with nothing left outside these slices is
% described by them completely and gets its exact box.
%
% done is false, with the index untouched, when a row cannot have described
% the volume: an object would have lost more voxels here than it had. The
% caller then falls back to the exact rescan rather than writing a wrong row.
done = false;
[height, width, depth] = size(labelVol, 1, 2, 3);
if numel(options.bbox) ~= 6
    error('utils:instances:objectIndex:previousSlicesWithoutBox', ...
        'previousSlices needs options.bbox to say which slices it holds');
end
zRange = double(options.bbox(5)):double(options.bbox(6));
before = options.previousSlices;
if ~isequal(size(before, 1, 2, 3), [height, width, numel(zRange)])
    error('utils:instances:objectIndex:previousSlicesSize', ...
        'previousSlices must be the whole slices %d to %d, [%d %d %d]; got [%s]', ...
        zRange(1), zRange(end), height, width, numel(zRange), num2str(size(before)));
end

origin = [1, 1, zRange(1)];
prior = localMeasure(before, searchIds, origin, depth);
current = localMeasure(labelVol(:, :, zRange), searchIds, origin, depth);

% the rows these objects had, zero for an object new to the index
count = numel(objectIds);
[isKnown, knownRows] = ismember(objectIds, index.ids);
previousVoxels = zeros(count, 1);
previousCentroids = zeros(count, 3);
previousSlices = zeros(count, 1);
boxes = zeros(count, 6);
previousVoxels(isKnown) = double(index.voxels(knownRows(isKnown)));
previousCentroids(isKnown, :) = double(index.centroid(knownRows(isKnown), :));
previousSlices(isKnown) = double(index.sliceCount(knownRows(isKnown)));
boxes(isKnown, :) = double(index.bbox(knownRows(isKnown), :));

elsewhere = previousVoxels - prior.counts;       % voxels on slices the edit did not touch
if any(elsewhere < 0); return; end

voxels = elsewhere + current.counts;
sums = previousCentroids .* previousVoxels - prior.sums + current.sums;
sliceCount = previousSlices - prior.slices + current.slices;

% Objects that live only on these slices are measured, not corrected.
onlyHere = elsewhere == 0;
sums(onlyHere, :) = current.sums(onlyHere, :);
sliceCount(onlyHere) = current.slices(onlyHere);
boxes(onlyHere, :) = current.bbox(onlyHere, :);

grown = ~onlyHere & current.counts > 0;
boxes(grown, [1 3 5]) = min(boxes(grown, [1 3 5]), current.bbox(grown, [1 3 5]));
boxes(grown, [2 4 6]) = max(boxes(grown, [2 4 6]), current.bbox(grown, [2 4 6]));

present = voxels > 0;
rows = struct('ids', objectIds(present), ...
    'voxels', voxels(present), ...
    'bbox', boxes(present, :), ...
    'centroid', sums(present, :) ./ voxels(present, 1), ...
    'sliceCount', max(sliceCount(present), 0));
index = utils.instances.replaceIndexRows(index, objectIds, rows);
done = true;
end

% =====================================================================
function measured = localMeasure(sub, searchIds, origin, depth)
% Voxel count, bounding box, coordinate sums and occupied slices of each of
% searchIds inside sub, a block of the label volume whose first voxel sits at
% origin = [y x z] of the volume. Rows follow searchIds; sums are [x y z], the
% centroid order. An object absent from the block has a zero row.
n = numel(searchIds);
measured = struct('counts', zeros(n, 1), 'bbox', zeros(n, 6), ...
    'sums', zeros(n, 3), 'slices', zeros(n, 1));

[member, slot] = ismember(sub, searchIds);
linear = find(member);
if isempty(linear); return; end

[subY, subX, subZ] = ind2sub(size(sub, 1, 2, 3), linear);
y = double(subY) + origin(1) - 1;
x = double(subX) + origin(2) - 1;
z = double(subZ) + origin(3) - 1;
hit = double(slot(linear));

measured.counts = accumarray(hit, 1, [n 1]);
measured.bbox = [accumarray(hit, y, [n 1], @min, 0), accumarray(hit, y, [n 1], @max, 0), ...
                 accumarray(hit, x, [n 1], @min, 0), accumarray(hit, x, [n 1], @max, 0), ...
                 accumarray(hit, z, [n 1], @min, 0), accumarray(hit, z, [n 1], @max, 0)];
measured.sums = [accumarray(hit, x, [n 1]), accumarray(hit, y, [n 1]), accumarray(hit, z, [n 1])];
% Occupied slices: one sparse hit per (object, slice) pair, so what is summed
% is distinct slices rather than voxels.
occupancy = sparse(hit, z, 1, n, depth);
measured.slices = full(sum(occupancy > 0, 2));
end

% =====================================================================
function [sliceCount, cancelled] = localSliceCounts(labelVol, maxIndex, wb)
% Number of z-slices each label value 1..maxIndex actually occupies.
%
% Counted with one pass of unique() per plane rather than from the bounding box,
% so an object with a hole in the middle of its z-range is judged on the slices
% it is really on. Same loop as the minObjectSlices filter of
% utils.instances.stitch2Dto3D. Indexed by value, which the regionprops route
% that calls it bounds to 2^20.

cancelled = false;
depth = size(labelVol, 3);
sliceCount = zeros(maxIndex, 1, 'uint32');

% The cancel poll runs on every slice - one slice is enough work to be worth
% interrupting - while the message is refreshed a hundred times at most, a
% uifigure property write forcing a redraw each time.
messageStep = max(1, floor(depth/100));
for z = 1:depth
    if localCancelled(wb); cancelled = true; return; end
    if mod(z, messageStep) == 0
        localReport(wb, sprintf('Indexing objects: slice %d of %d...', z, depth));
    end
    plane = labelVol(:, :, z);
    present = unique(plane(plane > 0));
    if ~isempty(present)
        sliceCount(present) = sliceCount(present) + 1;
    end
end
end

% =====================================================================
function index = localEmptyIndex()
% An index with no objects
index = struct();
index.ids = zeros(0, 1);
index.voxels = zeros(0, 1, 'uint32');
index.bbox = zeros(0, 6, 'int32');
index.centroid = zeros(0, 3, 'single');
index.sliceCount = zeros(0, 1, 'uint32');
index.maxIndex = 0;
index.numObjects = 0;
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
