function jumpToTile(obj, tileIdx)
% JUMPTOTILE - Open the worst incident seam of a tile (mini-map click).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.jumpToTile(tileIdx)
%
% Input Arguments:
%   - **tileIdx** — [double] tile index clicked in the mini-map
%

if ~obj.dataValid(); return; end
edges = obj.stitching.edges;

% First edge of this tile in the visible (worst-first) ranking is its worst
% seam of the current fix mode; a tile with no seam in this mode does nothing.
visibleRanking = obj.visibleRanking();
for rankPos = 1:numel(visibleRanking)
    k = visibleRanking(rankPos);
    if edges(k).i == tileIdx || edges(k).j == tileIdx
        obj.selectSeam(k);
        return;
    end
end
end
