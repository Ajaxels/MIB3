function crops = buildZMosaicCrops(obj, zBoundary, viewCanvas)
% BUILDZMOSAICCROPS - Fuse the Fix Z view: mosaic slices z-1 and z around a point.
%
% Syntax:
%   .. code-block:: matlab
%
%      crops = obj.buildZMosaicCrops(zBoundary)
%      crops = obj.buildZMosaicCrops(zBoundary, viewCanvas)
%
% Fix Z treats the tiles as correctly stitched: a correction is ONE rigid
% shift of mosaic slice z (and everything above) against slice z-1, so it is
% judged and measured on the stitched MOSAIC, at any place the user picks -
% not on one tile. This composes the same rectangle of both slices with
% :func:`utils.stitch.fuseSliceRegion`: the Stitching window's blend mode, the
% inspector's drawing order and the intensity-corrected tiles of its reader,
% i.e. what Stitch would write there. Only the tiles under the rectangle are
% read.
%
% The rectangle is centred on ``obj.zMosaicCenter`` (a mini-map click,
% :func:`fixZSelectPoint`) - by default the centre of the current seam's
% tile *i* - and is that tile's size, at most 1024 x 1024 px, shifted (not
% shrunk) to stay inside the canvas. Both slices come from ``viewCanvas``
% (:meth:`zViewCanvas`, no per-slice corrections), so slice z appears at the
% boundary's current correction only once renderPairView offsets it by
% :meth:`boundaryDelta` - the frame drag and click-correlate always used.
%
% Input Arguments:
%   - **zBoundary** - [double] boundary z (2 .. mosaic depth): slices z-1 and z
%   - **viewCanvas** - [struct] *(optional)* :meth:`zViewCanvas`, to avoid
%     planning twice
%
% Output Arguments:
%   - **crops** - [struct] also stored in ``obj.zMosaicCrops``:
%
%     - ``.zBoundary`` - [double] the boundary
%     - ``.region`` - [2x2] ``[r0 r1; c0 c1]`` canvas pixels
%     - ``.regionPositions`` - [2x2] the same rectangle in the solved-position
%       frame the mini-map draws in
%     - ``.sliceA`` / ``.sliceB`` - [h x w single] slices z-1 / z, channel 1
%

if nargin < 3; viewCanvas = obj.zViewCanvas(); end
layout = obj.stitching.layout;
positions = obj.stitching.positions;
edge = obj.stitching.edges(obj.currentEdgeIdx);

% Solved-position frame -> canvas pixels. Translation plans place the minimum
% origin at pixel 1; warped plans shift by their own corner, read off tile 1.
if isfield(viewCanvas, 'tforms') && ~isempty(viewCanvas.tforms)
    frameOffset = viewCanvas.tilePlacement(1, 1:2) - positions(1, 1:2);
else
    frameOffset = 1 - min(positions(:, 1:2), [], 1);
end

centre = obj.zMosaicCenter;
if isempty(centre)
    centre = positions(edge.i, 1:2) + layout(edge.i).tileSize(1:2) / 2;
end
centreCanvas = centre + frameOffset;
cropSize = min(min([1024, 1024], layout(edge.i).tileSize(1:2)), viewCanvas.size(1:2));
startRC = round(centreCanvas - cropSize / 2);
startRC = min(max(startRC, 1), viewCanvas.size(1:2) - cropSize + 1);
region = [startRC(1), startRC(1) + cropSize(1) - 1; startRC(2), startRC(2) + cropSize(2) - 1];

crops = struct('zBoundary', zBoundary, 'region', region, ...
    'regionPositions', region - [frameOffset(1), frameOffset(1); frameOffset(2), frameOffset(2)], ...
    'sliceA', obj.fuseZMosaicSlice(zBoundary - 1, region, viewCanvas), ...
    'sliceB', obj.fuseZMosaicSlice(zBoundary, region, viewCanvas));
obj.zMosaicCrops = crops;
end
