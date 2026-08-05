function scoreAndRank(obj)
% SCOREANDRANK - Score every seam at the current solved positions and rank.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.scoreAndRank()
%
% Runs :func:`utils.stitch.scoreSeams` over the parent's edge set (writing
% ``seamScore`` back into ``obj.stitching.edges``) and stores the worst-first
% review order in ``obj.ranking``. The LRU tile reader is created once and
% shared with the pair-view rendering.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.scoreAndRank: triggered\n');
end

if isempty(obj.readerFcn)
    obj.readerFcn = utils.stitch.makeTileReader(obj.stitching.layout);
end

% During construction obj.view.gui is still invisible and uiprogressdlg
% refuses it — progressParent falls back to the parent Stitching window then,
% and to [] (no progress bar) when there is no window at all.
scoreOptions.readerFcn    = obj.readerFcn;
scoreOptions.parentFigure = obj.progressParent();
scoreOptions.showWaitbar  = ~isempty(scoreOptions.parentFigure);
scoreOptions.correction   = obj.stitching.ensureIntensityCorrection();

[obj.stitching.edges, obj.ranking] = utils.stitch.scoreSeams( ...
    obj.stitching.layout, obj.stitching.edges, obj.stitching.positions, scoreOptions);

end
