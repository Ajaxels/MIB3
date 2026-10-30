function status = moveSelection(obj, destination, action, options)
% MOVESELECTION - Move the selection to the labels or the mask over a range of
% slices of a disk-backed model (Shift+A / Shift+S / Shift+R, and their 2D forms).
%
% Syntax:
%   .. code-block:: matlab
%
%      status = obj.moveSelection(destination, action, options)
%
% Only the tiles that may hold selection (``selectionTiles``, see
% ``selectionFootprint``) are read and written, so the cost follows the selection,
% not the volume: a selection made with SAM2 in 3D through a large stack is moved
% in one call instead of visiting every slice.
%
% Each group of consecutive tile planes (a chunk, kept under about 1.5e8 voxels)
% is processed at the finest level any layer holds data at in its selection tiles
% (``matLevel``, all three layers). The labels drawn at full resolution under a
% selection drawn zoomed out are then rewritten at full resolution, so the move
% does not replace them with the coarse version. A chunk whose layers all live at
% a coarse level is processed there, which is what makes a selection drawn zoomed
% out cheap to move. The chunk is read with ``materializeForRead`` +
% ``readPackedLevel`` and written back with ``setData63(..., 'everything')``, which
% propagates it to the coarser levels, marks only the tiles it changed, keeps the
% instance index and ``selectionTiles`` up to date.
%
% The selection is cleared over the processed slices, as in the Standard mode.
%
% Input Arguments:
%   - **destination** - [char] ``'labels'`` or ``'mask'``
%   - **action** - [char]
%
%     - ``'add'`` - selected voxels get ``options.materialIndex`` (labels) or the mask
%     - ``'remove'`` - selected voxels lose their material (labels) or the mask
%     - ``'replace'`` - local replace: on each slice, the material
%       ``options.materialIndex`` (or the mask) is first removed from the blocks of
%       one coarsest-grid tile in y/x (``modelScaleFactors(end, 1:2)`` pixels) that
%       hold a moved voxel ON THAT SLICE, then the selection is added as ``'add'``.
%       Decided per slice, not per tile: a tile of a pyramid that also downsamples
%       z spans several slices, and the neighbouring slices of a selection must
%       keep their material. The tile map only says where selection may be; the
%       blocks are taken from the selection read, so a tile map that is unknown
%       everywhere (an old side-file) still clears only around the selection. The
%       rest of the volume is left as it is; for a replace over the whole volume
%       call ``eraseEverywhere`` first and then ``'add'``.
%
%   - **options** *(optional)* - [struct] with fields
%
%     - ``.z`` - [1x2 double] full-resolution slices, default the whole depth
%     - ``.materialIndex`` - [double] destination material of a labels move
%       (MIB's "Add to" material). Required for labels ``'add'``/``'replace'``.
%     - ``.restrictMaterial`` - [double | empty] only selected voxels of this
%       material are moved ("Fix selection to material"); default ``[]``
%     - ``.restrictMask`` - [logical] only selected voxels inside the mask are moved
%       ("Masked area"); default false
%     - ``.progressFcn`` - [function handle | empty] called before each chunk as
%       ``cancel = progressFcn(fractionDone)``; returning true stops the move before
%       the next write. Default ``[]``.
%
% Output Arguments:
%   - **status** - [struct]
%
%     - ``.changed`` - [logical] at least one chunk was written
%     - ``.cancelled`` - [logical] the move stopped on a cancel request; the chunks
%       written before it stay written (the caller restores its undo copy)
%     - ``.zDone`` - [1x2 double | empty] slices processed before stopping
%     - ``.levels`` - [double] the pyramid level of each processed chunk
%
% Usage:
%   .. code-block:: matlab
%
%      % Shift+A: add the selection of the whole stack to material 3
%      labels = obj.mibModel.I{id}.labels;
%      status = labels.moveSelection('labels', 'add', struct('materialIndex', 3));

if nargin < 4; options = struct(); end
if ~isfield(options, 'z') || isempty(options.z); options.z = [1, max(1, obj.depth)]; end
if ~isfield(options, 'materialIndex'); options.materialIndex = []; end
if ~isfield(options, 'restrictMaterial'); options.restrictMaterial = []; end
if ~isfield(options, 'restrictMask'); options.restrictMask = false; end
if ~isfield(options, 'progressFcn'); options.progressFcn = []; end
if strcmp(destination, 'labels') && ~strcmp(action, 'remove') && isempty(options.materialIndex)
    error('MibBigDataLabels:moveSelection', 'options.materialIndex is required to add the selection to a material');
end

status = struct('changed', false, 'cancelled', false, 'zDone', [], 'levels', []);
[~, ~, tileMask] = obj.selectionFootprint(options.z, 1:3);
if isempty(tileMask); return; end

voxelBudget = 1.5e8;     % per chunk: the packed block plus a few logical copies of it
tileSize = obj.modelScaleFactors(end, :);
selectionValue = cast(obj.selectionValue, obj.containerClass);
maskValue = cast(obj.maskValue, obj.containerClass);
materialMask = cast(obj.materialMask, obj.containerClass);

planes = find(any(tileMask, [1 2]));
planes = planes(:)';
chunkStart = 1;
while chunkStart <= numel(planes)
    % grow the chunk over consecutive planes while it stays under the budget
    chunkEnd = chunkStart;
    while chunkEnd < numel(planes) && planes(chunkEnd + 1) == planes(chunkEnd) + 1
        [~, ~, ~, voxels] = chunkPlan(obj, tileMask, planes(chunkStart):planes(chunkEnd + 1), options.z);
        if voxels > voxelBudget; break; end
        chunkEnd = chunkEnd + 1;
    end
    tilePlanes = planes(chunkStart):planes(chunkEnd);

    if ~isempty(options.progressFcn) && options.progressFcn((chunkStart - 1) / numel(planes))
        status.cancelled = true;
        return;
    end

    [box, levelIdx] = chunkPlan(obj, tileMask, tilePlanes, options.z);
    readOptions = struct('pyramidLevel', levelIdx, 'y', box(1:2), 'x', box(3:4), 'z', box(5:6));
    [Yl, Xl, Zl] = obj.orientPhysRanges(levelIdx, 3, readOptions);
    obj.materializeForRead(levelIdx, Yl, Xl, Zl);
    packed = obj.readPackedLevel(levelIdx, Yl, Xl, Zl);

    moved = bitand(packed, selectionValue) > 0;
    if ~isempty(options.restrictMaterial)
        moved = moved & bitand(packed, materialMask) == options.restrictMaterial;
    end
    if options.restrictMask
        moved = moved & bitand(packed, maskValue) > 0;
    end

    if strcmp(action, 'replace')
        % the y/x blocks of each slice holding a moved voxel of that slice, where
        % the destination is cleared first
        rowTiles = obj.tileIndexOfLevelPixels(levelIdx, 1, Yl) - (box(1) - 1) / tileSize(1);
        colTiles = obj.tileIndexOfLevelPixels(levelIdx, 2, Xl) - (box(3) - 1) / tileSize(2);
        [movedRows, movedCols, movedSlices] = ind2sub(size(moved), find(moved));
        blocksHit = false(rowTiles(end), colTiles(end), size(moved, 3));
        blocksHit(sub2ind(size(blocksHit), reshape(rowTiles(movedRows), [], 1), reshape(colTiles(movedCols), [], 1), movedSlices)) = true;
        inTiles = blocksHit(rowTiles, colTiles, :);
    end

    switch destination
        case 'labels'
            materials = bitand(packed, materialMask);
            switch action
                case 'add'
                    materials(moved) = options.materialIndex;
                case 'remove'
                    materials(moved) = 0;
                case 'replace'
                    materials(inTiles & materials == options.materialIndex) = 0;
                    materials(moved) = options.materialIndex;
            end
            packed = bitor(bitand(packed, bitcmp(materialMask)), materials);
        case 'mask'
            switch action
                case 'add'
                    packed(moved) = bitor(packed(moved), maskValue);
                case 'remove'
                    packed(moved) = bitand(packed(moved), bitcmp(maskValue));
                case 'replace'
                    packed(inTiles) = bitand(packed(inTiles), bitcmp(maskValue));
                    packed(moved) = bitor(packed(moved), maskValue);
            end
    end
    packed = bitand(packed, bitcmp(selectionValue));     % the selection is consumed

    if obj.setData63(packed, 'everything', 3, [], readOptions)
        status.changed = true;
    end
    status.levels(end + 1) = levelIdx;
    status.zDone = [options.z(1), box(6)];
    chunkStart = chunkEnd + 1;
end
if ~any(obj.selectionTiles, 'all'); obj.selectionBBoxFull = []; end
end

% ------------------------------------------------------------------------
function [box, levelIdx, chunkTiles, voxels] = chunkPlan(obj, tileMask, tilePlanes, fullZ)
% Box, level and tile mask of the selection tiles of the tile planes
% ``tilePlanes``. ``box`` - full-resolution [y1 y2 x1 x2 z1 z2], whole tiles in
% y/x, z clipped to ``fullZ``; ``levelIdx`` - finest level of any layer in those
% tiles; ``chunkTiles`` - the tile mask over the box; ``voxels`` - the size of
% the box at that level.
planeTiles = tileMask(:, :, tilePlanes);
rows = find(any(planeTiles, [2 3]));
cols = find(any(planeTiles, [1 3]));
chunkTiles = planeTiles(rows(1):rows(end), cols(1):cols(end), :);
levels = obj.matLevel(rows(1):rows(end), cols(1):cols(end), tilePlanes, :);
levels = levels(repmat(chunkTiles, [1 1 1 3]));
levels = levels(levels > 0);
if isempty(levels)
    levelIdx = size(obj.modelLevelSizes, 1);
else
    levelIdx = double(min(levels));
end
tileSize = obj.modelScaleFactors(end, :);
box = [(rows(1)-1)*tileSize(1)+1, min(rows(end)*tileSize(1), obj.height), ...
       (cols(1)-1)*tileSize(2)+1, min(cols(end)*tileSize(2), obj.width), ...
       max(fullZ(1), (tilePlanes(1)-1)*tileSize(3)+1), min(fullZ(2), tilePlanes(end)*tileSize(3))];
voxels = prod((box(2:2:end) - box(1:2:end) + 1) ./ obj.modelScaleFactors(levelIdx, :));
end
