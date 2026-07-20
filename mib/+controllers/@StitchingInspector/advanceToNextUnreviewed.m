function advanceToNextUnreviewed(obj)
% ADVANCETONEXTUNREVIEWED - Select the worst seam not yet reviewed.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.advanceToNextUnreviewed()
%
% "Reviewed" = source 'confirmed' or 'user', or excluded (valid = false).
% When everything is reviewed, stays on the current seam.
%

if ~obj.dataValid(); return; end
edges = obj.stitching.edges;
% Stay within the seams the current fix mode shows, so "confirm + advance"
% never jumps to a row absent from the table.
visibleRanking = obj.visibleRanking();
for rankPos = 1:numel(visibleRanking)
    k = visibleRanking(rankPos);
    if k == obj.currentEdgeIdx; continue; end
    if edges(k).valid && strcmp(edges(k).source, 'auto')
        obj.selectSeam(k);
        return;
    end
end
end
