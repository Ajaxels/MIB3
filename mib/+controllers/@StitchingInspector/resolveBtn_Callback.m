function resolveBtn_Callback(obj)
% RESOLVEBTN_CALLBACK - Re-run the global solve with the edited edge set.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.resolveBtn_Callback()
%
% Delegates to the parent's ``optimizePositions_Callback`` (same solver
% dispatch, canvas re-plan and quality-chip update as the Stitching window),
% then re-scores every seam at the NEW positions and re-ranks the review.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.resolveBtn_Callback: triggered\n');
end
if ~obj.dataValid(); return; end

obj.resolvePending = false;
obj.stitching.optimizePositions_Callback();

obj.scoreAndRank();
obj.updateWidgets();
if ~isempty(obj.currentEdgeIdx)
    obj.renderPairView();
else
    visibleRanking = obj.visibleRanking();
    if ~isempty(visibleRanking)
        obj.selectSeam(visibleRanking(1));
    end
end
notify(obj, 'SeamsUpdated');
end
