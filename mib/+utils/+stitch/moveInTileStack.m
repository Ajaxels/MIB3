function stack = moveInTileStack(stack, tileIdx, action, positions, tileSizes)
% MOVEINTILESTACK - Move one tile in the Overwrite drawing order.
%
% Syntax:
%   .. code-block:: matlab
%
%      stack = utils.stitch.moveInTileStack(stack, tileIdx, action, positions, tileSizes)
%
% ``stack`` lists the tiles bottom first (see :func:`utils.stitch.tileDrawOrder`):
% the last one wins every overlap it takes part in. The four actions the seam
% inspector offers:
%
% - ``'top'`` / ``'bottom'`` - to the very end / start of the stack.
% - ``'up'`` / ``'down'`` - one step past the nearest tile above / below it
%   **that it actually overlaps**. Stepping past a tile it does not touch changes
%   no pixel of the mosaic, so it would be an action with no visible effect;
%   skipping those makes every press count.
%
% An action that changes nothing (``'top'`` on the top tile, ``'up'`` with no
% overlapping tile above) returns the stack unchanged, which is how the caller
% tells which actions are worth offering.
%
% Input Arguments:
%   - **stack** - [1 x N double] tile indices, bottom first.
%   - **tileIdx** - [double] the tile to move.
%   - **action** - [char] ``'top'`` | ``'up'`` | ``'down'`` | ``'bottom'``.
%   - **positions** - [N x 3 double] tile origins ``[y x z]`` (solved or nominal).
%   - **tileSizes** - [N x 3+ double] ``[H W D ...]`` per tile, as in
%     ``layout.tileSize``.
%
% Output Arguments:
%   - **stack** - [1 x N double] the new order, bottom first.
%
% **Example** - put tile 4 below tile 2:
%
%   .. code-block:: matlab
%
%      stack = utils.stitch.moveInTileStack(stack, 4, 'down', positions, ...
%          reshape([layout.tileSize], 4, []).');
%
% See also utils.stitch.tileDrawOrder

stack = stack(:)';
from = find(stack == tileIdx, 1);
if isempty(from); return; end
rest = stack([1:from - 1, from + 1:end]);

switch action
    case 'top'
        stack = [rest, tileIdx];
    case 'bottom'
        stack = [tileIdx, rest];
    case {'up', 'down'}
        if strcmp(action, 'up')
            candidates = from + 1:numel(stack);
        else
            candidates = from - 1:-1:1;
        end
        neighbour = [];
        for position = candidates
            if tilesOverlap(tileIdx, stack(position), positions, tileSizes)
                neighbour = stack(position);
                break;
            end
        end
        if isempty(neighbour); return; end
        at = find(rest == neighbour, 1);
        if strcmp(action, 'up')
            stack = [rest(1:at), tileIdx, rest(at + 1:end)];
        else
            stack = [rest(1:at - 1), tileIdx, rest(at:end)];
        end
    otherwise
        error('utils:stitch:moveInTileStack:unknownAction', ...
            'Unknown tile-stack action "%s".', action);
end
end

% =========================================================================
function tf = tilesOverlap(tileA, tileB, positions, tileSizes)
% TILESOVERLAP - Do the two tiles' boxes share at least one voxel?
depths = ones(size(tileSizes, 1), 1);
if size(tileSizes, 2) >= 3; depths = tileSizes(:, 3); end
extents = [tileSizes(:, 1:2), depths];
tf = true;
for axisIdx = 1:3
    lowA = positions(tileA, axisIdx); highA = lowA + extents(tileA, axisIdx);
    lowB = positions(tileB, axisIdx); highB = lowB + extents(tileB, axisIdx);
    if min(highA, highB) - max(lowA, lowB) <= 0
        tf = false;
        return;
    end
end
end
