function [bboxA, bboxB] = computeOverlapRegion(layout, i, j, expandPx)
% COMPUTEOVERLAPREGION - Nominal overlap rectangle of two tiles in local pixel coords.
%
% Syntax:
%   .. code-block:: matlab
%
%      [bboxA, bboxB] = utils.stitch.computeOverlapRegion(layout, i, j)
%      [bboxA, bboxB] = utils.stitch.computeOverlapRegion(layout, i, j, expandPx)
%
% Given the nominal origins and sizes of tiles ``i`` and ``j`` (from ``layout``),
% computes the rectangle where the two tiles are expected to overlap and returns
% it in EACH tile's own local pixel coordinate system. The rectangle is grown by
% ``expandPx`` on every side to give the phase-correlation search room for the
% expected positioning jitter, then clamped to the respective tile bounds. Both
% returned boxes have identical width and height (the intersection extent) so the
% two crops can be correlated directly.
%
% Coordinate convention: origins are 1-based ``[y x z]`` pixel positions of the
% top-left tile corner in the shared global frame. A tile of size ``[H W]`` spans
% global rows ``[oy, oy+H-1]`` and columns ``[ox, ox+W-1]``.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout with ``.nomOrigin`` (``[y x z]``)
%     and ``.tileSize`` (``[H W D C]``) fields.
%   - **i** - [double] index of the first tile.
%   - **j** - [double] index of the second tile.
%   - **expandPx** *(optional)* - [double] pixels to expand the overlap on each
%     side to absorb jitter (default: ``64``).
%
% Output Arguments:
%   - **bboxA** - [2x2] overlap rectangle in tile ``i`` local coords,
%     ``[yMin yMax; xMin xMax]`` (1-based, inclusive).
%   - **bboxB** - [2x2] overlap rectangle in tile ``j`` local coords, same shape;
%     both boxes have equal height and width.
%
% .. note::
%    When the nominal boxes do not overlap at all (even after expansion), the
%    returned rectangles fall back to the full extent of the smaller shared
%    region clamped to both tiles, guaranteeing a non-empty, equal-sized crop.
%
% **Example** - overlap crop of a horizontal neighbour pair:
%
%   .. code-block:: matlab
%
%      [bboxA, bboxB] = utils.stitch.computeOverlapRegion(layout, 1, 2, 32);
%      readerFcn = utils.stitch.makeTileReader(layout);
%      cropA = readerFcn(1, bboxA);
%      cropB = readerFcn(2, bboxB);

if nargin < 4 || isempty(expandPx); expandPx = 64; end

originA = layout(i).nomOrigin;      % [y x z]
originB = layout(j).nomOrigin;
sizeA   = layout(i).tileSize;       % [H W D C]
sizeB   = layout(j).tileSize;

Ha = sizeA(1); Wa = sizeA(2);
Hb = sizeB(1); Wb = sizeB(2);

% Global spans (1-based inclusive) of each tile.
ayGlobal = [originA(1), originA(1) + Ha - 1];
axGlobal = [originA(2), originA(2) + Wa - 1];
byGlobal = [originB(1), originB(1) + Hb - 1];
bxGlobal = [originB(2), originB(2) + Wb - 1];

% Nominal overlap in global coords (intersection).
yLo = max(ayGlobal(1), byGlobal(1));
yHi = min(ayGlobal(2), byGlobal(2));
xLo = max(axGlobal(1), bxGlobal(1));
xHi = min(axGlobal(2), bxGlobal(2));

% Expand by jitter budget.
yLo = yLo - expandPx;   yHi = yHi + expandPx;
xLo = xLo - expandPx;   xHi = xHi + expandPx;

% Fallback when there is no genuine overlap: force at least a 1-pixel box.
if yHi < yLo; yHi = yLo; end
if xHi < xLo; xHi = xLo; end

% Convert the expanded global span into each tile's local (1-based) coordinates
% and clamp each crop to its OWN tile bounds only. The expansion therefore
% survives INTO each tile even at tile borders where the nominal overlap sits at
% the tile edge - this is what gives phase correlation room to detect offsets up
% to expandPx. The two crops then generally cover DIFFERENT nominal windows;
% measureAllPairs compensates exactly using the crop start offsets:
%   P_j - P_i = (bboxA(:,1) - bboxB(:,1)) - shift
bboxA = [yLo - originA(1) + 1, yHi - originA(1) + 1; ...
         xLo - originA(2) + 1, xHi - originA(2) + 1];
bboxB = [yLo - originB(1) + 1, yHi - originB(1) + 1; ...
         xLo - originB(2) + 1, xHi - originB(2) + 1];

% Nominal origins may be fractional (percentage-derived grid steps, estimated
% overlaps); pixel reads need integer bounds. Rounding here is safe because the
% offset compensation in measureAllPairs uses the ACTUAL (rounded) crop starts.
bboxA = round(bboxA);
bboxB = round(bboxB);

bboxA(1, :) = min(max(bboxA(1, :), 1), Ha);
bboxA(2, :) = min(max(bboxA(2, :), 1), Wa);
bboxB(1, :) = min(max(bboxB(1, :), 1), Hb);
bboxB(2, :) = min(max(bboxB(2, :), 1), Wb);

% Ensure equal extents on both sides (trim the larger crop at its far edge; the
% crop STARTS are preserved because the offset compensation above uses them).
hExtent = min(bboxA(1, 2) - bboxA(1, 1), bboxB(1, 2) - bboxB(1, 1));
wExtent = min(bboxA(2, 2) - bboxA(2, 1), bboxB(2, 2) - bboxB(2, 1));
bboxA(1, 2) = bboxA(1, 1) + hExtent;
bboxA(2, 2) = bboxA(2, 1) + wExtent;
bboxB(1, 2) = bboxB(1, 1) + hExtent;
bboxB(2, 2) = bboxB(2, 1) + wExtent;
end
