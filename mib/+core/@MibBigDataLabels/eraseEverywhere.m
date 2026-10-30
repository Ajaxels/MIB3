function status = eraseEverywhere(obj, layerGroup, materialIndex, progressFcn)
% ERASEEVERYWHERE - Remove one material, or the mask, from the whole volume of a
% disk-backed model (the first half of a whole-volume Shift+R).
%
% Syntax:
%   .. code-block:: matlab
%
%      status = obj.eraseEverywhere(1, materialIndex, progressFcn)   % a material
%      status = obj.eraseEverywhere(2, [], progressFcn)              % the mask
%
% A material can sit in any tile, so every written tile is visited. Each tile is
% edited at the level its layer is authoritative at (``matLevel(..., layerGroup)``)
% and nowhere finer: those levels are recomputed from it on read anyway. A tile
% the layer was never written to (level 0) is skipped. The work is done in bands
% of whole tile rows, one tile plane and one level at a time; a band is read,
% the voxels of its tiles at that level are edited, and the band is written back
% (the voxels of the other tiles are written back unchanged). Only the runs of
% tiles that changed are propagated to the coarser levels, and only the bits of
% ``layerGroup``: a tile whose layer lives at a coarser level holds stale data at
% this level, which must not reach the level it is authoritative at.
%
% The level map does not change (each tile keeps its level). The instance index
% is told where labels changed. There is no undo: on a large volume a copy would
% be the size of the model.
%
% Input Arguments:
%   - **layerGroup** - [double] ``1`` labels (remove ``materialIndex``) or ``2`` mask
%   - **materialIndex** - [double] the material to remove; ignored for the mask
%   - **progressFcn** *(optional)* - [function handle | empty] called before each
%     band as ``cancel = progressFcn(fractionDone)``; returning true stops before
%     the next write
%
% Output Arguments:
%   - **status** - [struct] ``.changed`` (a voxel was removed), ``.cancelled``
%     (stopped on request; the bands before it stay edited), ``.planesDone``
%     (coarsest-grid planes finished)

if nargin < 4; progressFcn = []; end
status = struct('changed', false, 'cancelled', false, 'planesDone', 0);
if isempty(obj.matLevel); return; end

voxelBudget = 6e7;
tileSize = obj.modelScaleFactors(end, :);
if layerGroup == 1
    layerBits = cast(obj.materialMask, obj.containerClass);
else
    layerBits = cast(obj.maskValue, obj.containerClass);
end
levelMap = obj.matLevel(:, :, :, layerGroup);
planeCount = size(levelMap, 3);
changedBox = [];

for tilePlane = 1:planeCount
    planeLevels = levelMap(:, :, tilePlane);
    fullZ = [(tilePlane-1)*tileSize(3)+1, min(tilePlane*tileSize(3), max(1, obj.depth))];
    for levelIdx = reshape(unique(planeLevels(planeLevels > 0)), 1, [])
        levelTiles = planeLevels == levelIdx;
        tileRows = find(any(levelTiles, 2));
        sf = obj.modelScaleFactors(levelIdx, :);
        cols = find(any(levelTiles, 1));
        rowVoxels = (tileSize(1) / sf(1)) * ((cols(end) - cols(1) + 1) * tileSize(2) / sf(2)) * ...
            max(1, tileSize(3) / sf(3));
        rowsPerBand = max(1, floor(voxelBudget / rowVoxels));
        bandStart = 1;
        while bandStart <= numel(tileRows)
            if ~isempty(progressFcn) && progressFcn((tilePlane - 1) / planeCount)
                status.cancelled = true;
                break;
            end
            bandRows = [tileRows(bandStart), min(tileRows(end), tileRows(bandStart) + rowsPerBand - 1)];
            fullY = [(bandRows(1)-1)*tileSize(1)+1, min(bandRows(2)*tileSize(1), obj.height)];
            fullX = [(cols(1)-1)*tileSize(2)+1, min(cols(end)*tileSize(2), obj.width)];
            [Yl, Xl, Zl] = obj.regionForLevel(levelIdx, fullY, fullX, fullZ);
            block = obj.readPackedLevel(levelIdx, Yl, Xl, Zl);

            rowTiles = obj.tileIndexOfLevelPixels(levelIdx, 1, Yl);
            colTiles = obj.tileIndexOfLevelPixels(levelIdx, 2, Xl);
            target = levelTiles(rowTiles, colTiles);              % voxels of the tiles at this level
            if layerGroup == 1
                target = target & bitand(block, layerBits) == materialIndex;
            else
                target = target & bitand(block, layerBits) > 0;
            end
            if any(target, 'all')
                block(target) = bitand(block(target), bitcmp(layerBits));
                obj.writePackedLevel(levelIdx, block, Yl, Xl, Zl);
                status.changed = true;

                % propagate the runs of changed tiles, row by row of tiles
                [tileY, tileX, ~, changedTiles] = obj.tilesHit(levelIdx, target, Yl, Xl, Zl);
                changedTiles = any(changedTiles, 3);
                for row = 1:size(changedTiles, 1)
                    runs = diff([0, changedTiles(row, :), 0]);
                    runStarts = find(runs == 1);
                    runEnds = find(runs == -1) - 1;
                    for run = 1:numel(runStarts)
                        tileRow = tileY(1) + row - 1;
                        runTiles = tileX(1) + [runStarts(run), runEnds(run)] - 1;
                        runY = [(tileRow-1)*tileSize(1)+1, min(tileRow*tileSize(1), obj.height)];
                        runX = [(runTiles(1)-1)*tileSize(2)+1, min(runTiles(2)*tileSize(2), obj.width)];
                        [runYl, runXl] = obj.regionForLevel(levelIdx, runY, runX, fullZ);
                        runBlock = block(runYl(1)-Yl(1)+1:runYl(2)-Yl(1)+1, runXl(1)-Xl(1)+1:runXl(2)-Xl(1)+1, :);
                        obj.propagateRegion(runBlock, runY, runX, fullZ, levelIdx, 'coarser', layerGroup);
                        changedBox = core.MibBigDataLabels.bboxUnion(changedBox, [runY, runX, fullZ]);
                    end
                end
            end
            bandStart = find(tileRows > bandRows(2), 1);
            if isempty(bandStart); break; end
        end
        if status.cancelled; break; end
    end
    if status.cancelled; break; end
    status.planesDone = tilePlane;
end
if layerGroup == 1 && ~isempty(changedBox)
    obj.markLabelsChanged(changedBox);
end
end
