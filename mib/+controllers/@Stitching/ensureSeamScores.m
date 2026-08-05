function cancelled = ensureSeamScores(obj, options)
% ENSURESEAMSCORES - Seam scores for the CURRENT placement, computed at most once.
%
% Syntax:
%   .. code-block:: matlab
%
%      cancelled = obj.ensureSeamScores()
%      cancelled = obj.ensureSeamScores(options)
%
% Fills ``obj.edges(k).seamScore`` / ``.dzHint`` with
% :func:`utils.stitch.scoreSeams`, and returns immediately when they already
% describe the current state. Same lazy-cache shape as
% :meth:`controllers.Stitching.ensureIntensityCorrection`, and for the same
% reason: scoring re-reads every overlap from disk, which on a large mosaic is
% the slowest thing the tool does short of fusing.
%
% **What it stops.** Two stages score the seams as part of their own job -
% :meth:`optimizePositions_Callback` after a solve and
% :meth:`buildLayoutFromBatchOpt` after importing a vendor placement - and the
% seam inspector scores them again on the way in
% (:meth:`controllers.StitchingInspector.scoreAndRank`). Importing an Atlas or
% SerialEM stitch and then pressing *Inspect and fix...* therefore read every
% overlap twice, as did every inspector re-solve
% (:meth:`controllers.StitchingInspector.resolveBtn_Callback` calls
% ``optimizePositions_Callback`` and then ``scoreAndRank``). The ranking itself
% is free to recompute - :func:`utils.stitch.rankSeams` touches no pixels.
%
% **What counts as "still current"** (``obj.seamScoresStamp``):
%
%   - the solved ``positions`` are unchanged - the scores ARE a function of the
%     placement, since the strips are cut at the solved origins;
%   - the edge count is unchanged - a re-measure produces a different set;
%   - ``BatchOpt.IntensityCorrection`` is unchanged - the scores are correlations
%     of CORRECTED pixels, so changing the method changes them;
%   - and every edge actually carries a score, so a partially-scored set (a
%     cancelled pass, or a project saved before scoring existed) is redone.
%
% Deliberately NOT invalidated by an edge edit that leaves the positions alone:
% excluding a seam, or a manual fix awaiting its re-solve, cannot change any
% seam's pixels. The re-solve that follows moves the positions, and that is what
% triggers the rescore.
%
% Input Arguments:
%   - **options** *(optional)* — struct with fields:
%
%     - ``.parentFigure`` — [handle] progress-dialog parent (default:
%       :meth:`guiFigure`; the inspector passes its own window)
%     - ``.readerFcn`` — [function_handle] reuse an existing tile reader (optional)
%
% Output Arguments:
%   - **cancelled** — [logical] ``true`` when the user cancelled the *Scoring
%     seams...* dialog; the scores are then cleared, the stamp is NOT set, and
%     the next request scores again. ``false`` when scoring ran or was skipped.
%
% See also utils.stitch.scoreSeams, utils.stitch.rankSeams,
% controllers.Stitching.ensureIntensityCorrection

if nargin < 2; options = struct(); end
cancelled = false;

if isempty(obj.layout) || isempty(obj.edges) || isempty(obj.positions); return; end
if obj.seamScoresAreCurrent(); return; end

if isfield(options, 'parentFigure')
    parentFigure = options.parentFigure;
else
    parentFigure = obj.guiFigure();
end

scoreOptions = struct( ...
    'showWaitbar',  obj.BatchOpt.showWaitbar && ~isempty(parentFigure), ...
    'parentFigure', parentFigure, ...
    'correction',   obj.ensureIntensityCorrection());
if isfield(options, 'readerFcn') && ~isempty(options.readerFcn)
    scoreOptions.readerFcn = options.readerFcn;
end

try
    [obj.edges, ~, cancelled] = utils.stitch.scoreSeams( ...
        obj.layout, obj.edges, obj.positions, scoreOptions);
catch
    % Pixel verification is advisory - never block a solve or an import on it.
    % The stamp stays unset, so the next consumer retries rather than trusting
    % whatever partial state the failure left behind.
    return;
end

if ~cancelled
    obj.seamScoresStamp = obj.currentSeamScoreStamp();
end

end
