function [labelVol, stats] = splitDisconnected(labelVol, options)
% SPLITDISCONNECTED - give every connected component of an instance label its own index.
%
% Syntax:
%   .. code-block:: matlab
%
%       labelVol = utils.instances.splitDisconnected(labelVol)
%       [labelVol, stats] = utils.instances.splitDisconnected(labelVol, options)
%
% An instance index must name exactly one object. Tiled prediction can break that:
% ``segmentObjects`` occasionally returns a single detection whose mask covers two
% neighbouring objects, and cross-tile stitching can group detections that do not belong
% together, so one index ends up painted over two spatially separate blobs. Splitting each
% label into its connected components repairs the count without touching anything else -
% the pixels keep their object, only the numbering changes.
%
% The tiny leftovers this exposes (a few pixels shed by mask thresholding) are speckle
% rather than objects, so ``minObjectPixels`` discards them. This is the only step that
% removes pixels; with the default ``0`` nothing is lost.
%
% Input Arguments:
%   - **labelVol** - ``[height, width]`` or ``[height, width, depth]`` instance label array
%     (0 = background). Label values need not be contiguous.
%   - **options** - *(optional)* structure of parameters:
%
%     - ``.connectivity`` - ``8`` *(default)* splits within each z-slice, which is what a
%       stack of per-slice 2D predictions needs; ``26`` treats the volume as one 3D object
%       space, for a model whose indices are already consistent across slices. Splitting a
%       per-slice-numbered stack in 3D would wrongly fuse the unrelated objects that happen
%       to share an index on neighbouring slices
%     - ``.minObjectPixels`` - drop components smaller than this many pixels
%       (default: ``0``, keep everything)
%     - ``.perSliceNumbering`` - restart the numbering at 1 on every z-slice
%       (default: ``false`` = one contiguous ``1..N`` for the whole array). Only meaningful
%       with ``connectivity`` 8; matching the convention of
%       ``MibDeep.startPredictionInstances``, which keeps instance indices per slice so the
%       model type stays 65535 on deep stacks
%
% Output Arguments:
%   - **labelVol** - the relabelled array, ``uint16`` when the highest index fits and
%     ``uint32`` otherwise. Indices are contiguous from 1 (per slice with
%     ``perSliceNumbering``)
%   - **stats** - structure:
%
%     - ``.numObjectsBefore`` / ``.numObjectsAfter`` - distinct indices in and out. With
%       ``perSliceNumbering`` these are summed over the slices, so they count objects
%       rather than index values
%     - ``.numSplitLabels`` - indices that covered more than one component
%     - ``.numExtraObjects`` - objects recovered, i.e. components beyond the first of a
%       split index (before ``minObjectPixels`` is applied)
%     - ``.numDroppedComponents`` / ``.numDroppedPixels`` - what ``minObjectPixels`` removed
%
% Usage:
%   **Example 1** - repair a stack of per-slice instance predictions
%
%   .. code-block:: matlab
%
%      options.minObjectPixels = 100;
%      options.perSliceNumbering = true;
%      [labelVol, stats] = utils.instances.splitDisconnected(labelVol, options);
%
%   **Example 2** - split a 3D instance model whose indices span the volume
%
%   .. code-block:: matlab
%
%      [labelVol, stats] = utils.instances.splitDisconnected(labelVol, struct('connectivity', 26));
%
% See also: utils.instances.cleanup, utils.instances.stitch2Dto3D,
% deepmib.segmentImageInstancesIoUMerge

% Updates
%

if nargin < 2 || isempty(options); options = struct(); end
if ~isfield(options, 'connectivity');      options.connectivity = 8; end
if ~isfield(options, 'minObjectPixels');   options.minObjectPixels = 0; end
if ~isfield(options, 'perSliceNumbering'); options.perSliceNumbering = false; end

stats = struct('numObjectsBefore', 0, 'numObjectsAfter', 0, 'numSplitLabels', 0, ...
    'numExtraObjects', 0, 'numDroppedComponents', 0, 'numDroppedPixels', 0);

if options.connectivity == 26
    [labelVol, stats] = localSplitBlock(labelVol, 26, options.minObjectPixels, 0, stats);
else
    depth = size(labelVol, 3);
    splitVol = zeros(size(labelVol), 'uint32');
    nextId = 0;
    for z = 1:depth
        if options.perSliceNumbering; nextId = 0; end
        [splitVol(:, :, z), stats, nextId] = ...
            localSplitBlock(labelVol(:, :, z), 8, options.minObjectPixels, nextId, stats);
    end
    labelVol = splitVol;
end

% keep the storage class as small as the indices allow - MIB model types are driven by it
maxIndex = double(max(labelVol, [], 'all'));
if isempty(maxIndex) || maxIndex <= 65535
    labelVol = uint16(labelVol);
else
    labelVol = uint32(labelVol);
end
end

% =====================================================================
function [splitBlock, stats, nextId] = localSplitBlock(block, connectivity, minObjectPixels, nextId, stats)
% split every label of one 2D slice or of a whole volume, continuing the numbering
%
% Each label is searched inside its own bounding box rather than over the whole array: on a
% 1714x2606 slice with ~220 labels that is 0.06 s instead of 1.2 s, i.e. minutes rather than
% an hour over a whole-slide stack, for an identical result.
blockSize = size(block);
splitBlock = zeros(blockSize, 'uint32');
if ~any(block, 'all'); return; end

labelStats = regionprops(block, 'BoundingBox', 'PixelIdxList');
for labelIndex = 1:numel(labelStats)
    pixelIds = labelStats(labelIndex).PixelIdxList;
    if isempty(pixelIds); continue; end        % index not present in this block
    stats.numObjectsBefore = stats.numObjectsBefore + 1;

    [boxMask, boxOrigin, boxSize] = localCropToBoundingBox(labelStats(labelIndex), blockSize, pixelIds);
    components = bwconncomp(boxMask, connectivity);
    if components.NumObjects > 1
        stats.numSplitLabels = stats.numSplitLabels + 1;
        stats.numExtraObjects = stats.numExtraObjects + components.NumObjects - 1;
    end

    for componentId = 1:components.NumObjects
        boxPixelIds = components.PixelIdxList{componentId};
        if numel(boxPixelIds) < minObjectPixels
            stats.numDroppedComponents = stats.numDroppedComponents + 1;
            stats.numDroppedPixels = stats.numDroppedPixels + numel(boxPixelIds);
            continue;
        end
        nextId = nextId + 1;
        stats.numObjectsAfter = stats.numObjectsAfter + 1;
        splitBlock(localBoxToBlockIndices(boxPixelIds, boxSize, boxOrigin, blockSize)) = nextId;
    end
end
end

% =====================================================================
function [boxMask, boxOrigin, boxSize] = localCropToBoundingBox(labelStat, blockSize, pixelIds)
% logical mask of one label inside its own bounding box
% regionprops gives [xMin yMin (zMin) width height (depth)] with corners at .5
box = labelStat.BoundingBox;
numDims = numel(box)/2;
boxOrigin = ceil(box(1:numDims));
boxOrigin([1 2]) = boxOrigin([2 1]);            % x,y order to row,column order
boxSize = box(numDims+1:end);
boxSize([1 2]) = boxSize([2 1]);

subscripts = cell(1, numDims);
[subscripts{:}] = ind2sub(blockSize, pixelIds);
for dim = 1:numDims
    subscripts{dim} = subscripts{dim} - boxOrigin(dim) + 1;
end
boxMask = false(boxSize);
boxMask(sub2ind(boxSize, subscripts{:})) = true;
end

% =====================================================================
function blockIds = localBoxToBlockIndices(boxPixelIds, boxSize, boxOrigin, blockSize)
% map linear indices of the bounding-box crop back to the full block
numDims = numel(boxOrigin);
subscripts = cell(1, numDims);
[subscripts{:}] = ind2sub(boxSize, boxPixelIds);
for dim = 1:numDims
    subscripts{dim} = subscripts{dim} + boxOrigin(dim) - 1;
end
blockIds = sub2ind(blockSize, subscripts{:});
end
