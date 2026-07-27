function runOverlapEstimation(obj)
% RUNOVERLAPESTIMATION - Estimate the true grid overlap and rebuild the nominal layout.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.runOverlapEstimation()
%
% Grid-style layout sources only (Grid, Filename pattern — both carry ``.gridRC``).
% Calls :func:`utils.stitch.estimateOverlap` (full-tile phase correlation with
% peak verification, median over the grid), writes the recovered percentages into
% ``BatchOpt.OverlapX/OverlapY`` and rebuilds the layout so the subsequent tight
% measurement pass starts from honest nominal positions. Directions that could not
% be estimated keep the user's value.
%
% Does nothing for a layout restored from a project file: the rebuild would
% re-derive it from ``BatchOpt``, which still describes whatever job was set up
% before the load (a project carries no layout source or grid before schema v3),
% silently replacing the project's tiles. Its nominal origins come from the file
% and need no overlap guess.
%

if ~ismember(obj.BatchOpt.LayoutSource{1}, {'Grid', 'Filename pattern'}); return; end
if obj.layoutFromProject; return; end
if isempty(obj.layout); obj.buildLayoutFromBatchOpt(); end

estimate = utils.stitch.estimateOverlap(obj.layout);

overlapChanged = false;
if isfinite(estimate.overlapX) && estimate.numMeasuredX > 0
    limits = obj.BatchOpt.OverlapX{2};
    obj.BatchOpt.OverlapX{1} = min(max(round(estimate.overlapX, 1), limits(1)), limits(2));
    overlapChanged = true;
end
if isfinite(estimate.overlapY) && estimate.numMeasuredY > 0
    limits = obj.BatchOpt.OverlapY{2};
    obj.BatchOpt.OverlapY{1} = min(max(round(estimate.overlapY, 1), limits(1)), limits(2));
    overlapChanged = true;
end

if overlapChanged
    obj.buildLayoutFromBatchOpt();
    if ~isempty(obj.view)
        obj.updateWidgets();
    end
end

end
