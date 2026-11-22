function [index, cancelled] = buildInstanceIndex(obj, options, wb)
% BUILDINSTANCEINDEX - Build or refresh the cached per-object index of the instance model.
%
% Syntax:
%   .. code-block:: matlab
%
%       index = obj.buildInstanceIndex()
%       index = obj.buildInstanceIndex(options)
%       [index, cancelled] = obj.buildInstanceIndex(options, wb)
%
% Reads the labels layer of one time point and hands it to
% ``utils.instances.objectIndex``, storing the result in ``obj.instanceIndex``.
% The index is what lets ``controllers.InstanceEditor`` answer "where is object
% N" without a volume scan, and what confines every edit to one bounding box.
%
% The whole volume is read with the fast path of ``getData3D`` (Standard
% dataset, XY orientation, all materials, no block mode), which returns a
% copy-on-write alias of the labels array rather than a copy. Nothing here
% writes to it.
%
% **BigData.** A disk-backed model (``core.MibBigDataLabels``) is never read
% whole. The labels object keeps the index it was last synced with
% (``syncedInstanceIndex``) and the full-resolution box of every labels change
% made since (``indexDirtyBox``, grown by ``setData63``), and saves both next to
% the store on Save model and close, so a reopened store needs no scan. A build
% then does the least work that gives an exact index:
%
%   - nothing changed since the sync - the synced index is returned
%   - a full build with a dirty box - only the objects on the box now, or whose
%     box reached into it before, are re-measured, over the union of the box and
%     their previous boxes
%   - a refresh (``.objectIds``) - the named objects are re-measured the same
%     way over ``.bbox``. The caller vouches for every change inside ``.bbox``,
%     so a dirty box inside it is cleared and one reaching outside it is kept
%   - no synced index yet - a full scan at full resolution
%
% Every read is done in strips of whole rows of about 32 M voxels, so memory is
% bounded whatever the size of the store; time is proportional to the region
% read. Reading at level 1 materializes tiles last edited zoomed out
% (``core.MibBigDataLabels.materializeForRead``). ``.previousCrop`` is ignored:
% the union rule is exact without it, and the whole-slice difference it enables
% would read whole full-resolution slices. A read-only BigData overlay
% (``core.MibBigDataLabelsIndex``, ``core.MibBigDataLabelsZarr2``) is refused.
%
% Input Arguments:
%   - **options** - *(optional)* structure:
%
%     - ``.timePoint`` - time point to index (default: the currently shown one).
%       The index describes one time point at a time; the field is recorded in
%       the returned struct so a caller can tell when it no longer applies
%     - ``.objectIds`` - refresh only these objects in the existing
%       ``obj.instanceIndex`` instead of rebuilding (default: ``[]`` = full
%       build). Ignored when there is no index yet, or when it belongs to a
%       different time point, in which case a full build is done instead
%     - ``.bbox`` - ``[yMin yMax xMin xMax zMin zMax]`` region the edit changed,
%       passed through to ``utils.instances.objectIndex``
%     - ``.previousCrop`` - labels of ``.bbox`` as they were **before** the edit
%       (default: ``[]``). Makes the refresh a difference over the whole slices
%       ``bbox(5):bbox(6)``, which never reads the rest of the volume - see
%       ``previousSlices`` of ``utils.instances.objectIndex``, built here by
%       putting this crop back into the current slices. The edit must not have
%       changed anything outside ``.bbox``. This is how a 2-D edit stays at the
%       cost of one slice when its objects span the stack, as they do on an
%       unstitched model; such a refresh never narrows a bounding box
%     - ``.computeSliceCount`` - fill ``.sliceCount`` (default: ``true``)
%
%   - **wb** - *(optional)* handle of a caller-owned cancelable ``uiprogressdlg``,
%     or ``[]``.
%
% Output Arguments:
%   - **index** - the index structure, also stored in ``obj.instanceIndex``. It
%     carries two fields this method owns on top of the utility's:
%
%     - ``.timePoint`` - the time point it describes
%     - ``.stale`` - always ``false`` on return. Set it to ``true`` from outside
%       when the model is edited by anything other than the editor
%
%     Empty when the model is missing, read-only BigData, or the run was
%     cancelled.
%   - **cancelled** - logical, true when the user pressed Cancel. ``obj.instanceIndex``
%     is then left as it was rather than replaced by a partial index.
%
% Usage:
%   **Example 1** - build the index for the shown time point
%
%   .. code-block:: matlab
%
%      index = obj.mibModel.I{id}.buildInstanceIndex();
%
%   **Example 2** - refresh two objects after an edit
%
%   .. code-block:: matlab
%
%      refreshOptions.objectIds = [7, 12];
%      refreshOptions.bbox = [120 180 300 420 4 19];
%      obj.mibModel.I{id}.buildInstanceIndex(refreshOptions);
%
% See also: utils.instances.objectIndex, models.MibModel.editInstanceObjects

% Updates
%

if nargin < 3; wb = []; end
if nargin < 2 || isempty(options); options = struct(); end

if ~isfield(options, 'timePoint');         options.timePoint = obj.getCurrentTimePoint(); end
if ~isfield(options, 'objectIds');         options.objectIds = []; end
if ~isfield(options, 'bbox');              options.bbox = []; end
if ~isfield(options, 'previousCrop');      options.previousCrop = []; end
if ~isfield(options, 'computeSliceCount'); options.computeSliceCount = true; end

cancelled = false;
index = [];

if ~obj.modelExist || ~obj.labels.exists
    obj.instanceIndex = [];
    return;
end

% A read-only label overlay is served slice by slice from a remote pyramid; the
% getData3D below would pull the whole registered volume across the network to
% index objects that cannot be edited anyway. jrc_mus-liver-6's er segmentation is
% 510 GiB, so this is a refusal rather than a slow path. A foreign zarr v2 store
% (core.MibBigDataLabelsZarr2) is read-only too, and the side-file would be
% written into a folder MIB does not own.
if isa(obj.labels, 'core.MibBigDataLabelsIndex') || isa(obj.labels, 'core.MibBigDataLabelsZarr2')
    obj.instanceIndex = [];
    return;
end

% An editable BigData model is never read whole; see localBigDataIndex.
if isa(obj.labels, 'core.MibBigDataLabels')
    [index, cancelled, remainingDirtyBox, fullScan] = localBigDataIndex(obj, options, wb);
    if cancelled; index = []; return; end
    index.timePoint = options.timePoint;
    index.stale = false;
    obj.labels.syncInstanceIndex(index, remainingDirtyBox);
    if fullScan; obj.labels.saveInstanceIndex(); end
    obj.instanceIndex = index;
    return;
end

% Whole labels volume of this time point. NaN as the colour channel asks for the
% raw index map rather than one material as a binary mask, which is what makes
% the zero-copy fast path apply.
readOptions = struct('blockModeSwitch', 0);
volume = cell2mat(obj.getData3D('labels', options.timePoint, 3, NaN, readOptions));

indexOptions = struct('bbox', options.bbox, 'computeSliceCount', options.computeSliceCount);

% A refresh is only valid against an index of the same time point; anything else
% silently describes a different volume, so fall back to a full build.
canRefresh = ~isempty(options.objectIds) && ~isempty(obj.instanceIndex) && ...
    isfield(obj.instanceIndex, 'timePoint') && ...
    isequal(obj.instanceIndex.timePoint, options.timePoint);
if canRefresh
    indexOptions.index = obj.instanceIndex;
    indexOptions.objectIds = options.objectIds;

    if ~isempty(options.previousCrop)
        box = double(options.bbox);
        if ~isequal(size(options.previousCrop, 1, 2, 3), box([2 4 6]) - box([1 3 5]) + 1)
            error('MibDataset:buildInstanceIndex:previousCropSize', ...
                'previousCrop is [%s] but bbox [%s] describes a different region', ...
                num2str(size(options.previousCrop)), num2str(box));
        end
        previousSlices = volume(:, :, box(5):box(6));
        previousSlices(box(1):box(2), box(3):box(4), :) = options.previousCrop;
        indexOptions.previousSlices = previousSlices;
    end
end

[index, cancelled] = utils.instances.objectIndex(volume, indexOptions, wb);
if cancelled
    % Leave the previous index in place; a partial one would carry stale boxes
    % that the next edit would write through.
    index = [];
    return;
end

index.timePoint = options.timePoint;
index.stale = false;
obj.instanceIndex = index;
end

% =====================================================================
function [index, cancelled, remainingDirtyBox, fullScan] = localBigDataIndex(obj, options, wb)
% Index of a disk-backed BigData model, built without ever holding the volume.
%
% The store is a zarr pyramid far larger than memory, so the Standard route - one
% getData3D of the whole volume handed to utils.instances.objectIndex - becomes
% three cheaper ones, tried in this order:
%
% - **nothing to do** - the labels object holds the index it was last synced
%   with (core.MibBigDataLabels.syncedInstanceIndex, restored from the side-file
%   when the store is reopened) and no labels changed since: it is returned as is
% - **a re-measure** of what changed: the dirty box that setData63 keeps, or for
%   a refresh of named objects the caller's box, see localRefreshObjects
% - **a full scan**, strip by strip at full resolution (localScanRegion), when
%   there is no index to start from
%
% options.previousCrop is not used: on a disk-backed store the difference over
% whole slices it enables would read whole full-resolution slices, the very cost
% it exists to avoid there. The union rule of localRefreshObjects is exact
% without it.
%
% Output Arguments:
%   - **remainingDirtyBox** - changes the returned index does not yet account
%     for, ``[]`` when it describes the store exactly
%   - **fullScan** - logical, true when the index was built from scratch
labels = obj.labels;
remainingDirtyBox = [];
fullScan = false;
volumeBox = [1, labels.height, 1, labels.width, 1, labels.depth];

base = labels.syncedInstanceIndex;
dirtyBox = labels.indexDirtyBox;
if isempty(base) || ~isfield(base, 'timePoint') || ~isequal(base.timePoint, options.timePoint)
    index = [];
    [measured, cancelled] = localScanRegion(obj, volumeBox, options.timePoint, wb);
    if cancelled; return; end
    index = localMeasuredToIndex(measured);
    fullScan = true;
    return;
end

if ~isempty(options.objectIds)
    % A refresh of named objects. The caller vouches for every change inside its
    % box (see utils.instances.objectIndex, .objectIds), so a dirty box lying
    % inside it is accounted for; one reaching outside it stays pending.
    [index, cancelled] = localRefreshObjects(obj, base, options.objectIds, options.bbox, ...
        options.timePoint, wb, []);
    if ~isempty(dirtyBox) && ~localBoxInside(dirtyBox, options.bbox)
        remainingDirtyBox = dirtyBox;
    end
    return;
end

cancelled = false;
index = base;
if isempty(dirtyBox); return; end

% Which objects the change can have touched: everything on the dirty box now,
% and everything whose box reached into it before - which covers an object
% erased from it completely.
index = [];
[inDirtyBox, cancelled] = localScanRegion(obj, dirtyBox, options.timePoint, wb);
if cancelled; return; end
presentNow = inDirtyBox.ids;
presentBefore = base.ids(localBoxesOverlap(double(base.bbox), dirtyBox));
objectIds = unique([presentNow(:); presentBefore(:)]);
[index, cancelled] = localRefreshObjects(obj, base, objectIds, dirtyBox, ...
    options.timePoint, wb, inDirtyBox);
end

% =====================================================================
function [index, cancelled] = localRefreshObjects(obj, base, objectIds, seedBox, timePoint, wb, seedMeasured)
% Re-measure the named objects of base over the union of seedBox and their
% previous boxes.
%
% The rule of the refresh in utils.instances.objectIndex, and exact for the same
% reason: whatever an object had before lay inside its previous box, and whatever
% it gained lies where the store changed, inside seedBox. The union is read in
% strips, so its size costs time but never memory.
%
% Input Arguments:
%   - **seedBox** - ``[y1 y2 x1 x2 z1 z2]`` where the store changed, or ``[]``
%   - **seedMeasured** - localScanRegion result for seedBox when the caller
%     already has it, or ``[]``. Used when the union turns out to be seedBox
%     itself, which saves reading it twice
index = base;
cancelled = false;
objectIds = double(objectIds(:));
objectIds = unique(objectIds(objectIds > 0));
if isempty(objectIds); return; end

labels = obj.labels;
region = seedBox;
[isKnown, knownRows] = ismember(objectIds, base.ids);
for row = knownRows(isKnown)'
    region = core.MibBigDataLabels.bboxUnion(region, double(base.bbox(row, :)));
end
if isempty(region)
    region = [1, labels.height, 1, labels.width, 1, labels.depth];
end
region = [max(1, region(1)), min(labels.height, region(2)), ...
          max(1, region(3)), min(labels.width,  region(4)), ...
          max(1, region(5)), min(labels.depth,  region(6))];

if ~isempty(seedMeasured) && isequal(region, seedBox)
    measured = seedMeasured;
else
    [measured, cancelled] = localScanRegion(obj, region, timePoint, wb);
    if cancelled; index = []; return; end
end

% The named objects get the rows measured now, and an object that lost all of
% its voxels gets none, so it comes back absent.
[found, measuredRows] = ismember(objectIds, measured.ids);
measuredRows = measuredRows(found);
% explicit columns: an empty selection keeps the 0x0 or 1x0 shape of what it
% indexes, and the division below would then not broadcast
voxels = reshape(measured.voxels(measuredRows), [], 1);
rows = struct('ids', objectIds(found), 'voxels', voxels, ...
    'bbox', reshape(measured.bbox(measuredRows, :), [], 6), ...
    'centroid', reshape(measured.sums(measuredRows, :), [], 3) ./ voxels, ...
    'sliceCount', measured.slices(measuredRows));
index = utils.instances.replaceIndexRows(index, objectIds, rows);
end

% =====================================================================
function [measured, cancelled] = localScanRegion(obj, region, timePoint, wb)
% Voxel count, box, coordinate sums and slice count of every object in region,
% read at full resolution one strip at a time.
%
% A strip is a run of whole rows of the region on one slice, about 32 M voxels
% (64 MB of a uint16 store), measured by utils.instances.objectIndex and merged
% into running totals. Reading at level 1 materializes any tile last edited at a
% coarser zoom (core.MibBigDataLabels.materializeForRead), so a model painted
% zoomed out is written out at full resolution here - the same work Save does.
%
% The totals are sparse, one row per object found, like the index itself: a
% model of type 1073741823 can use indices near 1e9. Each strip gives one row
% per object on it; the strips of one slice are combined into one row per
% object with a slice count of 1, and the rows of the slices pile up until
% there are about 4 M of them, when they are combined per object. Memory
% therefore follows the number of objects, not the highest index or the
% number of slices.
%
% Output Arguments:
%   - **measured** - struct with one row per object found, sorted by index:
%     ``.ids``, ``.voxels`` and ``.slices`` [n x 1], ``.bbox`` [n x 6]
%     ``[yMin yMax xMin xMax zMin zMax]``, ``.sums`` [n x 3] of ``[x y z]``,
%     the centroid order; all double
%   - **cancelled** - logical, the user pressed Cancel; measured is then partial
cancelled = false;
% rows of [id voxels yMin yMax xMin xMax zMin zMax sumX sumY sumZ slices]
pending = zeros(0, 12);
measured = localRowsToMeasured(pending);

stripVoxels = 2^25;
regionWidth = region(4) - region(3) + 1;
rowsPerStrip = max(256, floor(stripVoxels / regionWidth / 256) * 256);
rowStarts = region(1):rowsPerStrip:region(2);
stepCount = numel(rowStarts) * (region(6) - region(5) + 1);
messageStep = max(1, floor(stepCount / 100));
step = 0;

readOptions = struct('blockModeSwitch', 0, 'x', region(3:4));
for z = region(5):region(6)
    sliceRows = cell(numel(rowStarts), 1);
    for stripNumber = 1:numel(rowStarts)
        firstRow = rowStarts(stripNumber);
        if localCancelled(wb); cancelled = true; return; end
        step = step + 1;
        if mod(step, messageStep) == 0 && ~isempty(wb) && isvalid(wb)
            wb.Message = sprintf('Indexing objects: %d%% of the region...', round(100 * step / stepCount));
        end

        readOptions.y = [firstRow, min(firstRow + rowsPerStrip - 1, region(2))];
        readOptions.z = [z, z];
        strip = cell2mat(obj.getData3D('labels', timePoint, 3, NaN, readOptions));
        stripIndex = utils.instances.objectIndex(strip, struct('computeSliceCount', false));
        if stripIndex.numObjects == 0; continue; end

        % strip coordinates -> volume coordinates
        voxels = double(stripIndex.voxels);
        boxes = double(stripIndex.bbox);
        boxes(:, 1:2) = boxes(:, 1:2) + firstRow - 1;
        boxes(:, 3:4) = boxes(:, 3:4) + region(3) - 1;
        boxes(:, 5:6) = z;
        centroids = double(stripIndex.centroid);
        centroids(:, 1) = centroids(:, 1) + region(3) - 1;
        centroids(:, 2) = centroids(:, 2) + firstRow - 1;
        centroids(:, 3) = z;
        sliceRows{stripNumber} = [stripIndex.ids, voxels, boxes, centroids .* voxels, ones(numel(voxels), 1)];
    end

    % every object of this slice is on it once, however many strips it spans
    sliceRows = localCombineRows(vertcat(sliceRows{:}));
    sliceRows(:, 12) = 1;
    pending = [pending; sliceRows]; %#ok<AGROW>
    if size(pending, 1) > 2^22
        pending = localCombineRows(pending);
    end
end
measured = localRowsToMeasured(localCombineRows(pending));
end

% =====================================================================
function rows = localCombineRows(rows)
% One row per object out of rows [id voxels yMin yMax xMin xMax zMin zMax sumX
% sumY sumZ slices]: voxels, coordinate sums and slice counts are summed, the
% boxes joined. The result is sorted by id.
if isempty(rows); return; end
[ids, ~, group] = unique(rows(:, 1));
n = numel(ids);
rows = [ids, accumarray(group, rows(:, 2), [n 1]), ...
    accumarray(group, rows(:, 3), [n 1], @min), accumarray(group, rows(:, 4), [n 1], @max), ...
    accumarray(group, rows(:, 5), [n 1], @min), accumarray(group, rows(:, 6), [n 1], @max), ...
    accumarray(group, rows(:, 7), [n 1], @min), accumarray(group, rows(:, 8), [n 1], @max), ...
    accumarray(group, rows(:, 9), [n 1]), accumarray(group, rows(:, 10), [n 1]), ...
    accumarray(group, rows(:, 11), [n 1]), accumarray(group, rows(:, 12), [n 1])];
end

% =====================================================================
function measured = localRowsToMeasured(rows)
% Combined rows [id voxels yMin yMax xMin xMax zMin zMax sumX sumY sumZ
% slices] -> the measured struct of localScanRegion
if isempty(rows); rows = zeros(0, 12); end
measured = struct('ids', rows(:, 1), 'voxels', rows(:, 2), 'bbox', rows(:, 3:8), ...
    'sums', rows(:, 9:11), 'slices', rows(:, 12));
end

% =====================================================================
function index = localMeasuredToIndex(measured)
% localScanRegion totals of the whole volume -> an index in the shape
% utils.instances.objectIndex returns
index = struct();
index.ids = measured.ids;
index.voxels = uint32(measured.voxels);
index.bbox = int32(measured.bbox);
index.centroid = single(measured.sums ./ measured.voxels);
index.sliceCount = uint32(measured.slices);
index.numObjects = numel(measured.ids);
index.maxIndex = 0;
if ~isempty(measured.ids); index.maxIndex = measured.ids(end); end
end

% =====================================================================
function tf = localBoxInside(inner, outer)
% true when box inner lies entirely inside box outer; an empty outer holds nothing
tf = numel(outer) == 6 && all(inner([1 3 5]) >= outer([1 3 5])) && all(inner([2 4 6]) <= outer([2 4 6]));
end

% =====================================================================
function overlap = localBoxesOverlap(boxes, box)
% [n x 1] logical, row k of boxes [n x 6] shares at least one voxel with box
overlap = boxes(:, 1) <= box(2) & boxes(:, 2) >= box(1) & ...
          boxes(:, 3) <= box(4) & boxes(:, 4) >= box(3) & ...
          boxes(:, 5) <= box(6) & boxes(:, 6) >= box(5);
end

% =====================================================================
function cancelled = localCancelled(wb)
% true once the user has pressed Cancel on the caller's progress dialog
cancelled = ~isempty(wb) && isvalid(wb) && wb.CancelRequested;
end
