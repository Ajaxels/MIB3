function clearSelectionTiles(obj, fullZ)
% CLEARSELECTIONTILES - Clear the selection over a range of slices of a
% disk-backed model, touching only the tiles that may hold selection
% (``selectionTiles``). Used by c / Shift+C.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.clearSelectionTiles([1, obj.depth])   % the whole stack
%      obj.clearSelectionTiles([z, z])           % one slice
%
% When the slices cover the selection tiles whole in z (always for the whole
% stack, and for one slice when the pyramid does not downsample z), the selection
% bits are zeroed at the COARSEST level only and the selection layer of those
% tiles is marked authoritative there (``matLevel(..., 3)``): every finer level
% then reads as no selection, rebuilt on demand from the coarsest one. That costs
% one read and write of a tiny block, whatever the size of the selection, and
% leaves the labels and the mask alone. A clear written at the display level
% instead (as ``clearLayer`` does) would miss a stroke drawn finer than the
% display, which a nearest downsample can drop.
%
% Otherwise (part of a tile plane of a z-downsampled pyramid) the selection is
% cleared with ``setData63`` at the finest level the selection lives at in those
% tiles, so nothing finer is left behind.
%
% Input Arguments:
%   - **fullZ** - [1x2 double] full-resolution slices to clear

[box, selectionLevel, tileMask] = obj.selectionFootprint(fullZ, 3);
if isempty(box)
    if ~any(obj.selectionTiles, 'all'); obj.selectionBBoxFull = []; end
    return;
end

tileSize = obj.modelScaleFactors(end, :);
planes = find(any(tileMask, [1 2]));
wholePlanes = (planes(1)-1)*tileSize(3)+1 >= fullZ(1) && ...
    min(planes(end)*tileSize(3), max(1, obj.depth)) <= fullZ(2);

if wholePlanes
    coarsest = size(obj.modelLevelSizes, 1);
    fullZTiles = [(planes(1)-1)*tileSize(3)+1, min(planes(end)*tileSize(3), max(1, obj.depth))];
    [Yl, Xl, Zl] = obj.regionForLevel(coarsest, box(1:2), box(3:4), fullZTiles);
    block = obj.readPackedLevel(coarsest, Yl, Xl, Zl);
    [tileY, tileX, tileZ] = obj.tilesForFullRegion(box(1:2), box(3:4), fullZTiles);
    windowTiles = tileMask(tileY(1):tileY(2), tileX(1):tileX(2), tileZ(1):tileZ(2));
    rowTiles   = obj.tileIndexOfLevelPixels(coarsest, 1, Yl) - tileY(1) + 1;
    colTiles   = obj.tileIndexOfLevelPixels(coarsest, 2, Xl) - tileX(1) + 1;
    sliceTiles = obj.tileIndexOfLevelPixels(coarsest, 3, Zl) - tileZ(1) + 1;
    inTiles = windowTiles(rowTiles, colTiles, sliceTiles);
    block(inTiles) = bitand(block(inTiles), bitcmp(cast(obj.selectionValue, obj.containerClass)));
    obj.writePackedLevel(coarsest, block, Yl, Xl, Zl);
    obj.markTileHits(tileY, tileX, tileZ, windowTiles, coarsest, 3);
    obj.selectionTiles(tileMask) = false;
else
    options = struct('pyramidLevel', selectionLevel, 'y', box(1:2), 'x', box(3:4), 'z', box(5:6));
    [Yl, Xl, Zl] = obj.orientPhysRanges(selectionLevel, 3, options);
    obj.setData63(zeros(Yl(2)-Yl(1)+1, Xl(2)-Xl(1)+1, Zl(2)-Zl(1)+1, 'uint8'), 'selection', 3, [], options);
end
if ~any(obj.selectionTiles, 'all'); obj.selectionBBoxFull = []; end
end
