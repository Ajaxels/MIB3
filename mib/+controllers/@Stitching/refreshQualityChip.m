function refreshQualityChip(obj)
% REFRESHQUALITYCHIP - Render the alignment-quality chip from the cached state.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.refreshQualityChip()
%
% Colour-coded alignment quality (``rmseLabel``), translating the raw solver
% RMSE — in pixels, the mean disagreement between the pairwise measurements at
% the solved positions — into a plain-language rating on a green→red scale that
% a non-specialist can read at a glance, DOWNGRADED whenever the pixel seam
% check disagrees with the residual. The exact numbers stay in the text and the
% tooltip for those who want them.
%
% Reads ``obj.solverInfo`` (cached by
% :func:`controllers.Stitching.optimizePositions_Callback`, restored by
% :func:`controllers.Stitching.loadProjectBtn_Callback`) and the seam scores
% currently on ``obj.edges``. Nothing here re-reads pixels or re-solves, so it
% is cheap enough to run from ``updateWidgets`` — which is what keeps the chip
% honest when the seam inspector excludes or re-includes an edge: the worst
% score is a minimum over the VALID edges, so that set changing changes the
% verdict even though no position moved.
%
% While the inspector owes a global re-solve (``resolvePending`` — a fix made
% with *Auto re-solve* off), the cached RMSE no longer describes the current
% edge set, so the chip says so instead of quoting a stale number.

if isempty(obj.view) || ~isfield(obj.view.handles, 'rmseLabel'); return; end
rmseLabel = obj.view.handles.rmseLabel;

% Neutral until there is something to report. obj.solverInfo is always a struct
% (empty until the first solve), so one isfield covers every case.
if isempty(obj.positions) || ~isfield(obj.solverInfo, 'rmseTotal')
    rmseLabel.Text = 'Alignment: —';
    rmseLabel.BackgroundColor = 'none';
    rmseLabel.FontColor = [0 0 0];
    rmseLabel.Tooltip = '';
    return;
end

% Pixel seam check over the edges that are CURRENTLY in the solve.
worstSeamScore  = NaN;
dzMismatchCount = 0;
if ~isempty(obj.edges) && isfield(obj.edges, 'seamScore')
    validEdges = obj.edges(logical([obj.edges.valid]));
    validScores = [validEdges.seamScore];
    if ~isempty(validScores)
        validScores(isnan(validScores)) = -1;   % no overlap at solved placement = broken
        worstSeamScore = min(validScores);
    end
    if isfield(obj.edges, 'dzHint') && ~isempty(validEdges)
        dzMismatchCount = nnz([validEdges.dzHint]);
    end
end

[ratingText, ratingColor] = qualityRating(obj.solverInfo.rmseTotal);

nDisconnected = 0;
if isfield(obj.solverInfo, 'disconnectedTiles')
    nDisconnected = numel(obj.solverInfo.disconnectedTiles);
end
nPruned = 0;
if isfield(obj.solverInfo, 'nPruned'); nPruned = obj.solverInfo.nPruned; end

if resolveIsPending(obj)
    % An edge was edited but the solve has not been re-run: the seam scores
    % still describe the current placement, the RMSE does not.
    rmseLabel.Text = '  Seams edited — press Re-solve to update the alignment  ';
    rmseLabel.BackgroundColor = [0.85 0.50 0.05];   % orange
elseif nDisconnected > 0
    % A tile with no valid measurement is parked at its nominal position —
    % the RMSE over the remaining edges says NOTHING about it, so a green
    % chip would be a lie (a 3-tile row misread as 2x2 solves to 0.1 px
    % while a tile sits wherever the grid guess put it).
    rmseLabel.Text = sprintf('  Alignment incomplete  (%d tile(s) held at nominal, %.2f px on the rest)  ', ...
        nDisconnected, obj.solverInfo.rmseTotal);
    rmseLabel.BackgroundColor = [0.85 0.50 0.05];   % orange
elseif worstSeamScore < 0.4   % NaN compares false: no scores -> RMSE rating
    % The pixels at the solved seams do not match: wrong layout
    % orientation or a confidently-wrong measurement. The residual alone
    % would read "Excellent" here (chain graphs have nothing to
    % contradict) — that is the lie this branch exists to stop.
    rmseLabel.Text = sprintf('  Seams disagree  (worst pixel match %.2f, solver %.2f px) — Inspect & fix  ', ...
        worstSeamScore, obj.solverInfo.rmseTotal);
    rmseLabel.BackgroundColor = [0.75 0.20 0.20];   % red
elseif worstSeamScore < 0.7
    rmseLabel.Text = sprintf('  Check seams  (worst pixel match %.2f, solver %.2f px)  ', ...
        worstSeamScore, obj.solverInfo.rmseTotal);
    rmseLabel.BackgroundColor = [0.85 0.50 0.05];   % orange
elseif dzMismatchCount > 0
    % The XY seams look fine but the pixels prefer a DIFFERENT Z offset on
    % at least one cross-layer seam (edges(k).dzHint from the dz-scan in
    % scoreSeams) — a Z misalignment barely dents the XY scores, so it
    % needs its own branch to be visible.
    rmseLabel.Text = sprintf('  Check Z alignment  (%d seam(s) prefer a different Z offset, %.2f px)  ', ...
        dzMismatchCount, obj.solverInfo.rmseTotal);
    rmseLabel.BackgroundColor = [0.85 0.50 0.05];   % orange
elseif nPruned > 0
    rmseLabel.Text = sprintf('  %s  (%.2f px, %d weak edge(s) dropped)  ', ...
        ratingText, obj.solverInfo.rmseTotal, nPruned);
    rmseLabel.BackgroundColor = ratingColor;
else
    rmseLabel.Text = sprintf('  %s  (%.2f px)  ', ratingText, obj.solverInfo.rmseTotal);
    rmseLabel.BackgroundColor = ratingColor;
end
rmseLabel.FontColor = [1 1 1];
rmseLabel.Tooltip = sprintf(['Alignment quality, from two independent checks:\n' ...
    '1) Solver residual: %.2f px RMS — how much the pairwise measurements\n' ...
    '   disagree at the solved positions (< 1 px excellent · 1–3 good ·\n' ...
    '   3–10 fair · > 10 poor). Blind on chain-like layouts (no loops).\n' ...
    '2) Pixel seam check: worst overlap NCC %.2f — the actual pixels\n' ...
    '   re-read at the solved seams (>= 0.7 good · 0.4–0.7 check · < 0.4 bad).\n' ...
    '   Z-stacks are scored slice-by-slice at the solved Z offset, and\n' ...
    '   cross-layer seams are re-scored at nearby Z offsets — a seam whose\n' ...
    '   pixels prefer a different Z downgrades the rating.\n' ...
    'Tiles without any valid measurement are held at nominal positions and\n' ...
    'are covered by neither check. Fix problem seams via Inspect & fix.'], ...
    obj.solverInfo.rmseTotal, worstSeamScore);

end

% =========================================================================
function tf = resolveIsPending(obj)
% RESOLVEISPENDING - True when an open inspector has edited the edges without
% re-running the global solve.
tf = ~isempty(obj.inspector) && isvalid(obj.inspector) && obj.inspector.resolvePending;
end

% =========================================================================
function [ratingText, ratingColor] = qualityRating(rmse)
% QUALITYRATING - Map an RMSE (px) to a plain-language rating + green→red colour.
if rmse <= 1
    ratingText  = 'Excellent alignment';
    ratingColor = [0.20 0.60 0.30];   % green
elseif rmse <= 3
    ratingText  = 'Good alignment';
    ratingColor = [0.45 0.60 0.15];   % olive-green
elseif rmse <= 10
    ratingText  = 'Fair alignment';
    ratingColor = [0.85 0.50 0.05];   % orange
else
    ratingText  = 'Poor alignment';
    ratingColor = [0.75 0.20 0.20];   % red
end
end
