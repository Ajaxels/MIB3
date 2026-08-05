function scoreAndRank(obj)
% SCOREANDRANK - Score every seam at the current solved positions and rank.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.scoreAndRank()
%
% Makes sure the parent's edge set carries ``seamScore`` for the CURRENT
% placement, then stores the worst-first review order in ``obj.ranking``. The
% LRU tile reader is created once and shared with the pair-view rendering.
%
% Scoring goes through :meth:`controllers.Stitching.ensureSeamScores`, so the
% overlaps are read only if nothing already scored them at these positions.
% Both routes into the inspector arrive pre-scored in the normal case - opening
% it after *Optimize positions* or after importing a vendor stitch, and
% :meth:`resolveBtn_Callback`, which re-solves through the parent before calling
% here - and re-reading every overlap is the slowest thing in the tool short of
% fusing. The RANKING is recomputed unconditionally: it is a pure function of
% the edge fields (:func:`utils.stitch.rankSeams`) and costs nothing, so it
% still follows an edge excluded since the last pass.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.scoreAndRank: triggered\n');
end

obj.tileReader();   % one shared reader for the whole inspector session

% During construction obj.view.gui is still invisible and uiprogressdlg
% refuses it — progressParent falls back to the parent Stitching window then,
% and to [] (no progress bar) when there is no window at all.
obj.stitching.ensureSeamScores(struct( ...
    'parentFigure', obj.progressParent(), ...
    'readerFcn',    obj.readerFcn));

obj.ranking = utils.stitch.rankSeams(obj.stitching.edges);

end
