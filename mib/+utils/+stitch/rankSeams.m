function ranking = rankSeams(edges)
% RANKSEAMS - Worst-first review order for an already-scored edge set.
%
% Syntax:
%   .. code-block:: matlab
%
%      ranking = utils.stitch.rankSeams(edges)
%
% Orders edges the way the seam inspector reviews them: pruned (``valid =
% false``) edges first, then by ``seamScore`` ascending with unscored / ``NaN``
% scores leading (no overlap at the solved placement is the worst thing an edge
% can be).
%
% Split out of :func:`utils.stitch.scoreSeams` because it reads NO PIXELS - it
% is a pure function of the edge fields. That is what lets a consumer re-derive
% the order after an edge is excluded, or adopt an edge set that was already
% scored, without paying for a second pass over the overlaps (which on a large
% mosaic is measured in minutes). :func:`utils.stitch.scoreSeams` calls this at
% the end, so the two orders cannot drift.
%
% Input Arguments:
%   - **edges** - [struct array] with ``.valid`` and ``.seamScore``. Either field
%     may be missing or empty; missing ``valid`` counts as valid, an empty or
%     ``NaN`` score sorts worst.
%
% Output Arguments:
%   - **ranking** - [1 x M double] edge indices, worst first.
%
% See also utils.stitch.scoreSeams

numEdges = numel(edges);
ranking = 1:numEdges;
if numEdges == 0; return; end

hasValid = isfield(edges, 'valid');
hasScore = isfield(edges, 'seamScore');

validFlags = false(numEdges, 1);
scores = zeros(numEdges, 1);
for k = 1:numEdges
    validFlags(k) = ~hasValid || isempty(edges(k).valid) || edges(k).valid;
    if hasScore && ~isempty(edges(k).seamScore)
        scores(k) = edges(k).seamScore;
    else
        scores(k) = NaN;   % never scored - same standing as "no overlap"
    end
end
scores(isnan(scores)) = -Inf;

[~, ranking] = sortrows([validFlags, scores], [1 2]);
ranking = ranking(:)';
end
