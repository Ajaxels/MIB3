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
% The returned arrays are **index-aligned**: entry ``k`` describes the object
% whose label value is ``k``, so ``index.voxels(objId)`` is a direct lookup and
% no id-to-row mapping is needed. Entries for label values that are not present
% carry ``exists(k) == false`` and zeros elsewhere.
%
% ``PixelIdxList`` is deliberately **not** stored - it is the one per-object
% quantity whose size grows with the data, and it is cheap to derive from the
% bounding box when a single object is actually operated on::
%
%     bb  = index.bbox(objId, :);
%     sub = labelVol(bb(1):bb(2), bb(3):bb(4), bb(5):bb(6));
%     idx = dataset.convertPixelIdxListCrop2Full(find(sub == objId), ...
%             struct('y', bb(1:2), 'x', bb(3:4), 'z', bb(5:6)));
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
%       Only these entries are recomputed. The caller must list **every** object
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
%       object had on them before is taken out of its entry and what it has now
%       is put in, and nothing outside them is read. For an edit confined to a
%       few slices of objects that span the stack - every 2-D edit of an
%       unstitched model - the union rule above would otherwise rescan nearly the
%       whole volume. Voxel count, centroid and slice count stay exact; the
%       bounding box only grows, see the note below. Requires ``.bbox``
%     - ``.computeSliceCount`` - fill ``.sliceCount`` (default: ``true``). The
%       only part of a full build that needs its own pass over the volume; set
%       ``false`` when the count is not going to be read
%
%   - **wb** - *(optional)* handle of a caller-owned ``uiprogressdlg`` created
%     with ``'Cancelable', 'on'``. Its ``Message`` is updated and
%     ``CancelRequested`` polled; ``Value`` is left to the caller, which may be
%     scaling one bar over several volumes. Pass ``[]`` for no progress dialog.
%
% Output Arguments:
%   - **index** - structure with index-aligned arrays of length ``maxIndex``:
%
%     - ``.exists`` - ``[maxIndex x 1]`` logical, object k has at least one voxel
%     - ``.voxels`` - ``[maxIndex x 1]`` uint32, voxel count of object k
%     - ``.bbox`` - ``[maxIndex x 6]`` int32 ``[yMin yMax xMin xMax zMin zMax]``,
%       inclusive and 1-based, ready to be used as ``options.y/.x/.z`` of
%       ``getData3D`` / ``backup``. All zero for an absent object
%     - ``.centroid`` - ``[maxIndex x 3]`` single ``[x y z]`` - the ``regionprops``
%       ordering, so it can be passed straight to ``MibDataset.moveView(x, y)``
%     - ``.sliceCount`` - ``[maxIndex x 1]`` uint32, number of z-slices the object
%       actually occupies (not its first-to-last span, so an object with a gap in
%       the middle is judged on the slices it is really on). All zero when
%       ``computeSliceCount`` was false
%     - ``.maxIndex`` - highest label value the arrays are sized for
%     - ``.numObjects`` - ``nnz(exists)``
%
%     Empty (``[]``) when the run was cancelled.
%   - **cancelled** - logical, true when the user pressed Cancel. No partial
%     index is returned: a half-filled index looks valid and its stale boxes
%     would silently corrupt the next edit.
%
% .. note::
%    The next free label value is ``find(~index.exists, 1)``, falling back to
%    ``index.maxIndex + 1`` when every value below the maximum is in use.
%
% .. note::
%    **A refresh never shrinks the index space.** If an edit removes the highest
%    label value, ``maxIndex`` stays where it was and the vacated entry becomes a
%    free index; a full rebuild of the same volume would size its arrays to the
%    new maximum instead and has no way of knowing the higher value ever existed.
%    So a refreshed index equals a rebuilt one *over the range they share*, with
%    the refreshed tail marked absent - not element for element.
%
% .. note::
%    **A refresh from** ``previousSlices`` **never shrinks a bounding box** of an
%    object that still has voxels outside those slices. That part of the object
%    is known only by the box it already had, so when the edit removes the voxels
%    that set a box edge, the box stays larger than the object until the next
%    full build. This is safe - every reader uses the box as the bound of a
%    search - but such an entry is not equal to a rebuilt one. An object that has
%    nothing left outside the slices gets its exact box.
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
%      bb = double(index.bbox(objId, :));
%      getDataOptions.y = bb(1:2);  getDataOptions.x = bb(3:4);  getDataOptions.z = bb(5:6);

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
depth = size(labelVol, 3);

maxIndex = double(max(labelVol, [], 'all'));
if isempty(maxIndex) || maxIndex == 0
    index = localEmptyIndex(0);
    return;
end

localReport(wb, 'Indexing objects: measuring bounding boxes...');
if localCancelled(wb); index = []; cancelled = true; return; end

% One regionprops call rather than a hand-written accumulation: it is a single
% C pass that allocates only per object, where find/ind2sub over every labelled
% voxel of a multi-GB volume would need several arrays the size of the
% segmentation. The label matrix must be a non-sparse numeric array with
% positive integer values, which an instance model always is.
stats = regionprops(labelVol, {'Area', 'BoundingBox', 'Centroid'});

index = localEmptyIndex(maxIndex);
% regionprops returns one entry per label value from 1 to max, so the struct
% array is already index-aligned and absent labels come back with Area 0.
areas = [stats.Area]';
index.voxels = uint32(areas);
index.exists = areas > 0;

present = find(index.exists);
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
    index.bbox(present, :) = int32([yMin, yMin + boxes(:, 5) - 1, ...
                                    xMin, xMin + boxes(:, 4) - 1, ...
                                    zMin, zMin + boxes(:, 6) - 1]);
    index.centroid(present, :) = single(centroids);
end

if options.computeSliceCount
    [index.sliceCount, cancelled] = localSliceCounts(labelVol, maxIndex, wb);
    if cancelled; index = []; return; end
end

index.numObjects = nnz(index.exists);
index.maxIndex = maxIndex;
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

% Grow the arrays when the edit introduced label values above the old maximum.
newMax = max([index.maxIndex; objectIds]);
if newMax > index.maxIndex
    index = localGrowIndex(index, newMax);
end

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
    if done
        index.numObjects = nnz(index.exists);
        return;
    end
end

region = options.bbox;
known = objectIds(objectIds <= size(index.bbox, 1));
known = known(index.exists(known));
if ~isempty(known)
    previous = double(index.bbox(known, :));
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

% Clear the entries first: an object that lost all of its voxels in the edit
% must come back as absent, not keep its old numbers.
index.exists(objectIds) = false;
index.voxels(objectIds) = 0;
index.bbox(objectIds, :) = 0;
index.centroid(objectIds, :) = 0;
index.sliceCount(objectIds) = 0;

sub = labelVol(region(1):region(2), region(3):region(4), region(5):region(6));
measured = localMeasure(sub, searchIds, region([1 3 5]), depth);

% Only objects that actually have voxels are written back; the rest were
% cleared above and must stay cleared.
filled = measured.counts > 0;
ids = objectIds(filled);
index.exists(ids) = true;
index.voxels(ids) = uint32(measured.counts(filled));
index.bbox(ids, :) = int32(measured.bbox(filled, :));
index.centroid(ids, :) = single(measured.sums(filled, :) ./ measured.counts(filled, 1));
index.sliceCount(ids) = uint32(measured.slices(filled));

index.numObjects = nnz(index.exists);
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
% Everything an entry holds except the box is a sum over voxels, so it can be
% corrected by what changed: the counts and coordinate sums of each object on
% these slices before the edit are taken out, the ones after are put in. Slices
% are taken whole so that "the object is on slice z" is known exactly from them.
%
% The box cannot be corrected that way - the rest of the object is known only by
% the box it already had - so it is widened to cover what the object now has
% here and never narrowed. An object with nothing left outside these slices is
% described by them completely and gets its exact box.
%
% done is false, with the index untouched, when an entry cannot have described
% the volume: an object would have lost more voxels here than it had. The
% caller then falls back to the exact rescan rather than writing a wrong entry.
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

previousVoxels = double(index.voxels(objectIds));
elsewhere = previousVoxels - prior.counts;       % voxels on slices the edit did not touch
if any(elsewhere < 0); return; end

voxels = elsewhere + current.counts;
sums = double(index.centroid(objectIds, :)) .* previousVoxels - prior.sums + current.sums;
sliceCount = double(index.sliceCount(objectIds)) - prior.slices + current.slices;
boxes = double(index.bbox(objectIds, :));

% Objects that live only on these slices are measured, not corrected.
onlyHere = elsewhere == 0;
sums(onlyHere, :) = current.sums(onlyHere, :);
sliceCount(onlyHere) = current.slices(onlyHere);
boxes(onlyHere, :) = current.bbox(onlyHere, :);

grown = ~onlyHere & current.counts > 0;
boxes(grown, [1 3 5]) = min(boxes(grown, [1 3 5]), current.bbox(grown, [1 3 5]));
boxes(grown, [2 4 6]) = max(boxes(grown, [2 4 6]), current.bbox(grown, [2 4 6]));

present = voxels > 0;
centroid = zeros(numel(objectIds), 3);
centroid(present, :) = sums(present, :) ./ voxels(present, 1);
boxes(~present, :) = 0;
sliceCount(~present) = 0;

index.exists(objectIds) = present;
index.voxels(objectIds) = uint32(voxels);
index.bbox(objectIds, :) = int32(boxes);
index.centroid(objectIds, :) = single(centroid);
index.sliceCount(objectIds) = uint32(max(sliceCount, 0));
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
% Number of z-slices each object actually occupies.
%
% Counted with one pass of unique() per plane rather than from the bounding box,
% so an object with a hole in the middle of its z-range is judged on the slices
% it is really on. Same loop as the minObjectSlices filter of
% utils.instances.stitch2Dto3D.

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
function index = localEmptyIndex(maxIndex)
% An index sized for maxIndex label values with nothing in it yet
index = struct();
index.exists = false(maxIndex, 1);
index.voxels = zeros(maxIndex, 1, 'uint32');
index.bbox = zeros(maxIndex, 6, 'int32');
index.centroid = zeros(maxIndex, 3, 'single');
index.sliceCount = zeros(maxIndex, 1, 'uint32');
index.maxIndex = maxIndex;
index.numObjects = 0;
end

% =====================================================================
function index = localGrowIndex(index, newMax)
% Extend the arrays to cover label values up to newMax, keeping other fields
old = index.maxIndex;
index.exists(old+1:newMax, 1) = false;
index.voxels(old+1:newMax, 1) = 0;
index.bbox(old+1:newMax, 1:6) = 0;
index.centroid(old+1:newMax, 1:3) = 0;
index.sliceCount(old+1:newMax, 1) = 0;
index.maxIndex = newMax;
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
