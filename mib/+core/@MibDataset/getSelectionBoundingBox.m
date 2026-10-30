function [box, boxFraction] = getSelectionBoundingBox(obj, timeRange)
% GETSELECTIONBOUNDINGBOX - Bounding box of the Selection layer of a Standard dataset.
%
% Returns the smallest box ``[y1 y2 x1 x2 z1 z2 t1 t2]`` (in voxels, YX
% orientation) that holds every selected voxel of the requested time points.
% Operations whose effect is limited to selected voxels (add or remove the
% selection to a material or the mask, clear the selection) can then read,
% back up and write only that box instead of the whole volume.
%
% The box is measured on demand rather than tracked as edits happen: every
% write path to the selection would otherwise have to report its extent, and a
% missed one would silently leave part of the selection out. Measuring takes
% two max-reductions over the whole layer array, along ``[1 2]`` for the
% slices and along ``[1 3]`` for the X extent, and one more for the Y extent.
% The order matters: a reduction that includes the first dimension runs at
% ~16 ms per GiB, one that does not (``[2 3]``, or ``3`` alone) at ~90-115 ms
% per GiB. So the Y extent is taken from the slab of the selected columns,
% slices and time points when that slab is under a quarter of the array, and
% from the whole array in place otherwise - copying a large slab out costs
% more (~0.75 s per GiB for a full one) than the slow reduction. The selection
% bit of a packed ``MibLabels63`` layer is its top bit, so ``max >=
% selectionValue`` reads as "selected" in both the uint8 (63 materials) and
% the uint16 (16383 instances) layouts; a separate selection layer is a 0/1
% array, so ``max > 0``.
%
% The X extent is taken over all slices of the requested time points; slices
% without selection add nothing to it, so the box is exact.
%
% **When the box is worth using.** Processing a box costs a copy out and a
% write back, and a backup limited to x/y/z ranges is a real copy, whereas a
% whole-volume backup shares memory with the layer. So a large box is slower
% than the whole-volume pass (measured 2.3-2.5x slower for a box of the whole
% volume); callers use the box only when ``boxFraction`` is small and fall back
% to the whole volume otherwise.
%
% Syntax:
%   .. code-block:: matlab
%
%      [box, boxFraction] = obj.getSelectionBoundingBox(timeRange)
%
% Input Arguments:
%   - **timeRange** - [numeric] ``[t1 t2]`` time points to examine; default:
%     the current time point
%
% Output Arguments:
%   - **box** - [1x8 double] ``[y1 y2 x1 x2 z1 z2 t1 t2]`` of the selection,
%     with ``t1/t2`` the first and last time point that hold it; ``[]`` when
%     nothing is selected. For a Virtual or BigData dataset, whose layers are
%     not held in memory, the full extent of ``timeRange`` is returned, so a
%     caller that limits its work to the box stays correct.
%   - **boxFraction** - [double] volume of the box divided by the volume of the
%     requested time points: ``0`` when nothing is selected, ``1`` for a
%     Virtual or BigData dataset.
%
% Usage:
%   .. code-block:: matlab
%
%      % limit an operation on the current time point to the selected voxels
%      [box, boxFraction] = obj.mibModel.I{id}.getSelectionBoundingBox();
%      if isempty(box); return; end       % nothing selected
%      if boxFraction > 0.25; box = []; end   % the whole volume is faster
%

% Updates
%

if nargin < 2 || isempty(timeRange)
    timeRange = [obj.slices{5}(1), obj.slices{5}(1)];
end
timeRange = timeRange(1):timeRange(end);

if ~strcmp(obj.datasetType, 'Standard')
    box = [1, obj.image.height, 1, obj.image.width, 1, obj.image.depth, timeRange(1), timeRange(end)];
    boxFraction = 1;
    return;
end

if isa(obj.labels, 'core.MibLabels63')
    selectionThreshold = obj.labels.selectionValue;
    layerData = obj.labels.data;
else
    selectionThreshold = 1;
    layerData = obj.selection.data;
end
box = [];
boxFraction = 0;
if isempty(layerData); return; end

% the layers are [height width depth 1 time]
% selected slices and time points: [1 1 depth 1 time] -> [depth time]
sliceMax = max(layerData, [], [1 2]);
sliceHasSelection = reshape(sliceMax >= selectionThreshold, size(sliceMax, 3), size(sliceMax, 5));
sliceHasSelection = sliceHasSelection(:, timeRange);
if ~any(sliceHasSelection, 'all'); return; end
zIndices = find(any(sliceHasSelection, 2));
tIndices = timeRange(any(sliceHasSelection, 1));

% X extent over the selected time points: [1 width 1 1 time] -> [width time]
columnMax = max(layerData, [], [1 3]);
columnHasSelection = reshape(columnMax >= selectionThreshold, size(columnMax, 2), size(columnMax, 5));
xIndices = find(any(columnHasSelection(:, tIndices), 2));

% Y extent: a reduction that does not run along the first dimension is several
% times slower per voxel, so a small slab of the selected columns, slices and
% time points is copied out and reduced; a large one would cost more to copy
% than reducing the whole array in place
slabFraction = (xIndices(end) - xIndices(1) + 1) * (zIndices(end) - zIndices(1) + 1) * ...
    (tIndices(end) - tIndices(1) + 1) / (size(layerData, 2) * size(layerData, 3) * size(layerData, 5));
if slabFraction < 0.25
    slab = layerData(:, xIndices(1):xIndices(end), zIndices(1):zIndices(end), :, tIndices(1):tIndices(end));
    rowMax = max(slab, [], [2 3 4 5]);
else
    rowMax = max(layerData, [], [2 3 4]);
    rowMax = max(rowMax(:, :, :, :, tIndices), [], 5);
end
yIndices = find(rowMax >= selectionThreshold);

box = [yIndices(1), yIndices(end), xIndices(1), xIndices(end), ...
    zIndices(1), zIndices(end), tIndices(1), tIndices(end)];
boxFraction = prod(box(2:2:end) - box(1:2:end) + 1) / ...
    (size(layerData, 1) * size(layerData, 2) * size(layerData, 3) * numel(timeRange));
end
