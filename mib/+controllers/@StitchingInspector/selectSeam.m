function selectSeam(obj, edgeIdx)
% SELECTSEAM - Make one seam current: render its pair view + sync selection.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.selectSeam(edgeIdx)
%
% Input Arguments:
%   - **edgeIdx** — [double] index into ``obj.stitching.edges``
%

if ~obj.dataValid(); return; end
if edgeIdx < 1 || edgeIdx > numel(obj.stitching.edges); return; end

obj.currentEdgeIdx = edgeIdx;

% Sync the table selection to the chosen seam (guarded: selection API may
% differ across releases; selection is a convenience, not state). rankPos is
% empty when the seam is filtered out of the current fix mode's table, which
% clears the selection — the pair view still shows the seam.
if obj.hasWidget('seamTable')
    rankPos = find(obj.visibleRanking() == edgeIdx, 1);
    try %#ok<TRYNC>
        obj.view.handles.seamTable.Selection = rankPos;
        % Selection alone does not bring an out-of-view row into the visible
        % viewport (uitable has no auto-scroll-to-selection).
        if ~isempty(rankPos)
            scroll(obj.view.handles.seamTable, 'row', rankPos);
        end
    end
end

obj.renderPairView();
obj.renderMiniMap();   % refresh the current-pair highlight
obj.refreshExcludeButton();   % the button reflects THIS seam's exclusion state

end
