function weightMap = blendWeights(tileHW, marginPx)
% BLENDWEIGHTS - Linear feather (distance-ramp) blend weights for one tile.
%
% Syntax:
%   .. code-block:: matlab
%
%      weightMap = utils.stitch.blendWeights(tileHW)
%      weightMap = utils.stitch.blendWeights(tileHW, marginPx)
%
% Builds a single-precision ``[H W]`` weight map that is ``1`` across the tile
% interior and ramps linearly down toward the edges, reaching a small positive
% value at the outermost pixel. The weight at any pixel is the minimum of its
% four separable edge ramps (distance to the nearest edge, normalised by
% ``marginPx``), so overlapping tiles cross-fade smoothly and no pixel receives
% exactly zero weight (which keeps ``sum(w*I)/sum(w)`` well defined everywhere).
% The construction is separable (outer product of 1-D ramps) — no ``bwdist``.
%
% Input Arguments:
%   - **tileHW** — [1x2 double] tile size ``[H W]``.
%   - **marginPx** *(optional)* — [double] feather width in pixels from each edge
%     (default: ``round(min(H, W) / 8)``, at least 1).
%
% Output Arguments:
%   - **weightMap** — [H x W single] blend weights in ``(0, 1]``.
%
% **Example** — feather weights with a 32-pixel ramp:
%
%   .. code-block:: matlab
%
%      w = utils.stitch.blendWeights([512 512], 32);
%      imagesc(w); axis image; colorbar;

H = tileHW(1);
W = tileHW(2);
if nargin < 2 || isempty(marginPx)
    marginPx = max(1, round(min(H, W) / 8));
end
marginPx = max(1, marginPx);

% 1-D ramp along each dimension: distance to the nearest end (1-based, so the
% first and last pixel are distance 1), normalised by marginPx, clamped to
% (minWeight, 1]. rampY is a column, rampX a row → min() broadcasts to [H W].
rampY = edgeRamp(H, marginPx);          % H x 1
rampX = edgeRamp(W, marginPx)';         % 1 x W

% Minimum over the two separable ramps = distance-to-nearest-edge feather.
weightMap = single(min(rampY, rampX));  % implicit expansion → H x W
end

% =====================================================================
function ramp = edgeRamp(n, marginPx)
% EDGERAMP - 1-D linear ramp column: rises from the edges to 1 over marginPx pixels.
if n == 1
    ramp = single(1);
    return;
end
minWeight = single(1) / single(marginPx + 1);   % smallest weight (outermost pixel)
idx = (1:n)';
distFromStart = idx;                 % 1..n (pixel 1 is distance 1 from the start edge)
distFromEnd   = n - idx + 1;         % n..1
dist = min(distFromStart, distFromEnd);
ramp = single(dist) / single(marginPx);
ramp = min(ramp, 1);
ramp = max(ramp, minWeight);
end
