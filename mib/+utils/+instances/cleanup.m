function [labelVol, stats, cancelled] = cleanup(labelVol, options, wb)
% CLEANUP - Remove noise objects from a 3D instance label volume.
%
% Syntax:
%   .. code-block:: matlab
%
%       labelVol = utils.instances.cleanup(labelVol)
%       [labelVol, stats] = utils.instances.cleanup(labelVol, options)
%       [labelVol, stats, cancelled] = utils.instances.cleanup(labelVol, options, wb)
%
% The three post-processing filters of ``utils.instances.stitch2Dto3D``, applied
% to a finished instance volume. They are here rather than inside the stitcher
% because the same cleanup is wanted **after** manual editing, and because the
% thresholds are dataset-specific enough that the user normally wants to try a
% few values without re-running the linking pass, which is far more expensive.
%
% The order is fixed and matters:
%
% 1. **Absorb fragments** - dust is given back to the object around it, so that a
%    speck inside a real object fills a hole rather than punching one.
% 2. **Remove by voxel count** and **by occupied slices** - what is left of the
%    dust, plus large-in-plane false detections that do not propagate.
% 3. **Renumber** the survivors, optionally.
%
% Fragment absorption runs first precisely so that a speck lying inside a real
% object is returned to it, while a speck floating in the background - which has
% no neighbour to join - is still there for the size filters to delete.
%
% Input Arguments:
%   - **labelVol** - ``[height, width, depth]`` instance label volume
%     (0 = background). Label values need not be contiguous.
%   - **options** - *(optional)* structure of parameters:
%
%     - ``.absorbFragmentVoxels`` - give the voxels of objects this size or
%       smaller to the object surrounding them in-plane (default: ``5``,
%       ``0`` = off). The only filter that is on by default, because unlike the
%       two below it cannot remove anything - it moves voxels between objects.
%       The default is deliberately equal to the stitcher's ``minOverlapPixels``:
%       an object of fewer voxels than that can never produce a large enough
%       intersection to be linked on any slice pair, so it reaches exactly the
%       objects the linker is structurally unable to reach and nothing else
%     - ``.minObjectVoxels`` - delete objects smaller than this (default: ``0``)
%     - ``.minObjectSlices`` - delete objects occupying this many z-slices or
%       fewer (default: ``0``; ``1`` drops single-slice objects). Complements
%       ``minObjectVoxels``: a 2D false positive can be large in-plane yet absent
%       from the neighbouring slices, which an area threshold cannot see
%     - ``.compact`` - renumber the surviving objects to a contiguous ``1..K``
%       (default: ``true``). ``false`` keeps every survivor's label value, which
%       is what interactive editing needs - a user who has been working with
%       object 1299 should still find it under that number afterwards
%     - ``.objectVoxelCounts`` - precomputed voxel count per label value, to skip
%       one pass over the volume (default: ``[]`` = compute here)
%
%   - **wb** - *(optional)* handle of a caller-owned ``uiprogressdlg`` created
%     with ``'Cancelable', 'on'``. ``Message`` is written and ``CancelRequested``
%     polled; ``Value`` is left to the caller. Pass ``[]`` for none.
%
% Output Arguments:
%   - **labelVol** - the cleaned volume, demoted back to ``uint16`` when the
%     highest surviving label fits. Empty when cancelled.
%   - **stats** - structure:
%
%     - ``.objectVoxelCounts`` - voxels per object. Length ``K`` and aligned with
%       the new labels when ``compact`` is true, otherwise full length and
%       index-aligned with the original label values, zero where an object was
%       removed
%     - ``.objectSliceCounts`` - same alignment; **empty** unless
%       ``minObjectSlices`` was used, since it is not otherwise computed
%     - ``.numAbsorbedFragments`` / ``.numAbsorbedVoxels`` - what absorption moved
%     - ``.numObjects`` - surviving object count
%     - ``.numRemoved`` - objects deleted by the two size filters
%     - ``.remap`` - ``[maxIndex x 1]`` old label value to new label value, ``0``
%       for a removed object. Empty when nothing was removed or renumbered
%
%   - **cancelled** - logical. On cancel no partial volume is returned: a
%     half-cleaned stack looks like a valid result and would be written over the
%     user's model.
%
% Usage:
%   **Example 1** - the recommended post-stitch cleanup
%
%   .. code-block:: matlab
%
%      options.minObjectSlices = 1;      % drop single-slice detections
%      [labelVol, stats] = utils.instances.cleanup(labelVol, options);
%
%   **Example 2** - cleanup of a hand-edited model, keeping the label values
%
%   .. code-block:: matlab
%
%      options.compact = false;
%      options.minObjectVoxels = 50;
%      [labelVol, stats] = utils.instances.cleanup(labelVol, options, wb);
%
% See also: utils.instances.stitch2Dto3D, utils.instances.objectIndex

% Updates
%

if nargin < 3; wb = []; end
if nargin < 2 || isempty(options); options = struct(); end

if ~isfield(options, 'absorbFragmentVoxels'); options.absorbFragmentVoxels = 5; end
if ~isfield(options, 'minObjectVoxels');      options.minObjectVoxels = 0; end
if ~isfield(options, 'minObjectSlices');      options.minObjectSlices = 0; end
if ~isfield(options, 'compact');              options.compact = true; end
if ~isfield(options, 'objectVoxelCounts');    options.objectVoxelCounts = []; end

cancelled = false;
depth = size(labelVol, 3);

maxIndex = double(max(labelVol, [], 'all'));
if isempty(maxIndex) || maxIndex == 0
    stats = localEmptyStats();
    return;
end

objectVoxelCounts = options.objectVoxelCounts;
if isempty(objectVoxelCounts)
    objectVoxelCounts = accumarray(double(labelVol(labelVol > 0)), 1, [maxIndex 1]);
end

%% Absorb dust into the objects around it
numAbsorbedFragments = 0;
numAbsorbedVoxels = 0;
if options.absorbFragmentVoxels > 0
    localReport(wb, 'Absorbing fragments into their neighbours...');
    [labelVol, objectVoxelCounts, numAbsorbedFragments, numAbsorbedVoxels, cancelled] = ...
        localAbsorbFragments(labelVol, objectVoxelCounts, options.absorbFragmentVoxels, wb);
    if cancelled; labelVol = []; stats = localEmptyStats(); return; end
end

%% Size filters
objectSliceCounts = [];
keep = objectVoxelCounts > 0;   % a fully absorbed fragment has no voxels left
existed = keep;
if options.minObjectVoxels > 0
    keep = keep & objectVoxelCounts >= options.minObjectVoxels;
end
if options.minObjectSlices > 0
    % Slices actually occupied, counted per object. A large in-plane false
    % detection that never propagates is invisible to the voxel threshold.
    localReport(wb, 'Removing objects that span too few slices...');
    objectSliceCounts = zeros(maxIndex, 1);
    messageStep = max(1, floor(depth/100));
    for z = 1:depth
        if localCancelled(wb); labelVol = []; stats = localEmptyStats(); cancelled = true; return; end
        if mod(z, messageStep) == 0
            localReport(wb, sprintf('Counting occupied slices: slice %d of %d...', z, depth));
        end
        plane = labelVol(:, :, z);
        present = unique(plane(plane > 0));
        objectSliceCounts(present) = objectSliceCounts(present) + 1;
    end
    keep = keep & objectSliceCounts > options.minObjectSlices;
end

%% Apply
remap = [];
numRemoved = nnz(existed & ~keep);
% Compaction rewrites a label whenever there is any gap below the maximum;
% without it only the removed objects have to be zeroed.
needsRemap = numRemoved > 0 || (options.compact && ~all(keep));
if needsRemap
    if options.compact
        remap = zeros(maxIndex, 1);
        remap(keep) = 1:nnz(keep);
    else
        remap = (1:maxIndex)';
        remap(~keep) = 0;
    end
    nonZero = labelVol > 0;
    labelVol(nonZero) = remap(labelVol(nonZero));

    if options.compact
        objectVoxelCounts = objectVoxelCounts(keep);
        if ~isempty(objectSliceCounts); objectSliceCounts = objectSliceCounts(keep); end
    else
        objectVoxelCounts(~keep) = 0;
        if ~isempty(objectSliceCounts); objectSliceCounts(~keep) = 0; end
    end
end

% Demote the storage class when the highest surviving label fits in uint16.
% Judged on the label value rather than on the object count, because without
% compaction the two are not the same number.
maxRemaining = double(max(labelVol, [], 'all'));
if ~isempty(maxRemaining) && maxRemaining <= 65535 && ~isa(labelVol, 'uint16')
    labelVol = uint16(labelVol);
end

stats = struct();
stats.objectVoxelCounts = objectVoxelCounts;
stats.objectSliceCounts = objectSliceCounts;
stats.numAbsorbedFragments = numAbsorbedFragments;
stats.numAbsorbedVoxels = numAbsorbedVoxels;
stats.numObjects = nnz(keep);
stats.numRemoved = numRemoved;
stats.remap = remap;
end

% =====================================================================
function stats = localEmptyStats()
stats = struct('objectVoxelCounts', [], 'objectSliceCounts', [], ...
    'numAbsorbedFragments', 0, 'numAbsorbedVoxels', 0, ...
    'numObjects', 0, 'numRemoved', 0, 'remap', []);
end

% =====================================================================
function [labelVol, voxelCounts, numFragments, numVoxels, cancelled] = localAbsorbFragments(labelVol, voxelCounts, maxFragmentVoxels, wb)
% Give the voxels of dust objects to the object surrounding them in-plane.
%
% Deliberately a *voxel* operation, run after the union-find is finished, not
% another link rule: a 2-voxel speck that lies over object A on one slice and
% under object B on the next would, as a graph link, weld A and B into one
% object. Reassigning its voxels instead cannot join anything - each group of
% voxels is decided on its own slice, by its own neighbours.
%
% A fragment is absorbed into the majority label among its 8-neighbours on that
% slice, counting only objects that are not themselves fragments, so absorption
% never chains from one speck to the next. A fragment with no such neighbour
% (floating in the background) keeps its voxels and stays an object.

numFragments = 0;
numVoxels = 0;
cancelled = false;
isFragment = voxelCounts > 0 & voxelCounts <= maxFragmentVoxels;
if ~any(isFragment); return; end

[height, width, ~] = size(labelVol);
sliceStride = height * width;

nonZeroIdx = find(labelVol > 0);
nonZeroLabels = double(labelVol(nonZeroIdx));
isSelected = isFragment(nonZeroLabels);
fragmentIdx = nonZeroIdx(isSelected);
fragmentLabels = nonZeroLabels(isSelected);
clear nonZeroIdx nonZeroLabels isSelected;

% one group per (fragment, slice): a fragment may occupy more than one slice and
% each slice has its own neighbourhood to decide against
fragmentSlices = ceil(fragmentIdx / sliceStride);
[groups, ~, groupIndex] = unique([fragmentLabels, fragmentSlices], 'rows');
[groupIndex, order] = sort(groupIndex);
fragmentIdx = fragmentIdx(order);
groupStart = [1; find(diff(groupIndex)) + 1];
groupEnd = [groupStart(2:end) - 1; numel(groupIndex)];

absorbedPerObject = zeros(numel(voxelCounts), 1);
% Unlike the per-slice loops, one iteration here is a few dozen pixels, so a
% cancel poll every iteration would cost more than the absorption itself.
numGroups = size(groups, 1);
cancelStep = max(1, floor(numGroups/100));
for g = 1:numGroups
    if mod(g, cancelStep) == 0 && localCancelled(wb); cancelled = true; return; end
    fragmentLabel = groups(g, 1);
    z = groups(g, 2);
    voxels = fragmentIdx(groupStart(g):groupEnd(g));
    [rows, cols] = ind2sub([height, width], voxels - (z - 1) * sliceStride);
    row1 = max(1, min(rows) - 1);   row2 = min(height, max(rows) + 1);
    col1 = max(1, min(cols) - 1);   col2 = min(width, max(cols) + 1);
    patch = labelVol(row1:row2, col1:col2, z);
    neighbours = double(patch(patch > 0 & patch ~= fragmentLabel));
    neighbours = neighbours(~isFragment(neighbours));
    if isempty(neighbours); continue; end
    target = mode(neighbours);
    labelVol(voxels) = target;
    absorbedPerObject(fragmentLabel) = absorbedPerObject(fragmentLabel) + numel(voxels);
    voxelCounts(target) = voxelCounts(target) + numel(voxels);
    numVoxels = numVoxels + numel(voxels);
end
voxelCounts = voxelCounts - absorbedPerObject;
numFragments = nnz(absorbedPerObject > 0 & voxelCounts == 0);
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
