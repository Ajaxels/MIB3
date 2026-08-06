function jumpToTile(obj, tileIdx)
% JUMPTOTILE - Open the worst incident seam of a tile.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.jumpToTile(tileIdx)
%
% Programmatic/headless entry point (e.g. tests). The mini-map itself does
% NOT call this - a click there goes through
% :func:`miniMapButtonDown`/:meth:`edgeAtMiniMapPoint`, which resolves to
% whichever SEAM is nearest the click point, since a tile usually touches
% more than one seam and "its worst one" is not always the one a click was
% aimed at.
%
% Input Arguments:
%   - **tileIdx** - [double] tile index
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
