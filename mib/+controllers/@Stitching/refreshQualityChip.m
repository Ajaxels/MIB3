function refreshQualityChip(obj)
% REFRESHQUALITYCHIP - Render the alignment-quality chip from the cached state.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.refreshQualityChip()
%
% Colour-coded alignment quality (``rmseLabel``), translating the raw solver
% RMSE - in pixels, the mean disagreement between the pairwise measurements at
% the solved positions - into a plain-language rating on a green→red scale that
% a non-specialist can read at a glance, DOWNGRADED whenever the pixel seam
% check disagrees with the residual. The exact numbers stay in the text and the
% tooltip for those who want them.
%
% Reads ``obj.solverInfo`` (cached by
% :func:`controllers.Stitching.optimizePositions_Callback`, restored by
% :func:`controllers.Stitching.loadProjectBtn_Callback`) and the seam scores
% currently on ``obj.edges``. Nothing here re-reads pixels or re-solves, so it
% is cheap enough to run from ``updateWidgets`` - which is what keeps the chip
% honest when the seam inspector excludes or re-includes an edge: the worst
% score is a minimum over the VALID edges, so that set changing changes the
% verdict even though no position moved.
%
% While a global re-solve is owed (``obj.resolvePending`` - a fix made with
% *Auto re-solve* off), the cached RMSE no longer describes the current edge set,
% so the chip says so instead of quoting a stale number. The flag lives on the
% CONTROLLER, not on the inspector, so the warning survives the inspector being
% closed - which is exactly when a stale rating would otherwise go unmentioned.

if isempty(obj.view) || ~isfield(obj.view.handles, 'rmseLabel'); return; end
rmseLabel = obj.view.handles.rmseLabel;

% Neutral until there is something to report. obj.solverInfo is always a struct
% (empty until the first solve), so one isfield covers every case.
if isempty(obj.positions) || ~isfield(obj.solverInfo, 'rmseTotal')
    rmseLabel.Text = 'Alignment: -';
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

pendingResolve = obj.resolvePending;
if pendingResolve
    % An edge was edited but the solve has not been re-run: the seam scores
    % still describe the current placement, the RMSE does not. The third line
    % answers the question the second one provokes - pressing Re-solve is
    % OPTIONAL, because stitchBtn_Callback settles the debt before it fuses.
    % Telling the user to press it (the old wording did) would send them to a
    % button they do not need.
    rmseLabel.Text = sprintf(['Seams edited\nRating stale until re-solved\n' ...
        'Re-solve now, or just Stitch']);
    rmseLabel.BackgroundColor = [0.85 0.50 0.05];   % orange
elseif nDisconnected > 0
    % A tile with no valid measurement is parked at its nominal position -
    % the RMSE over the remaining edges says NOTHING about it, so a green
    % chip would be a lie (a 3-tile row misread as 2x2 solves to 0.1 px
    % while a tile sits wherever the grid guess put it).
    rmseLabel.Text = sprintf('Alignment incomplete\nSolver error: %.2f px\n%d tile(s) unmeasured', ...
        obj.solverInfo.rmseTotal, nDisconnected);
    rmseLabel.BackgroundColor = [0.85 0.50 0.05];   % orange
elseif worstSeamScore < 0.4   % NaN compares false: no scores -> RMSE rating
    % The pixels at the solved seams do not match: wrong layout
    % orientation or a confidently-wrong measurement. The residual alone
    % would read "Excellent" here (chain graphs have nothing to
    % contradict) - that is the lie this branch exists to stop.
    rmseLabel.Text = sprintf('Seams disagree, fix needed\nSolver error: %.2f px\nSeam match: %.2f', ...
        obj.solverInfo.rmseTotal, worstSeamScore);
    rmseLabel.BackgroundColor = [0.75 0.20 0.20];   % red
elseif worstSeamScore < 0.7
    rmseLabel.Text = sprintf('Check seams\nSolver error: %.2f px\nSeam match: %.2f', ...
        obj.solverInfo.rmseTotal, worstSeamScore);
    rmseLabel.BackgroundColor = [0.85 0.50 0.05];   % orange
elseif dzMismatchCount > 0
    % The XY seams look fine but the pixels prefer a DIFFERENT Z offset on
    % at least one cross-layer seam (edges(k).dzHint from the dz-scan in
    % scoreSeams) - a Z misalignment barely dents the XY scores, so it
    % needs its own branch to be visible.
    rmseLabel.Text = sprintf('Check Z alignment\nSolver error: %.2f px\n%d seam(s) off', ...
        obj.solverInfo.rmseTotal, dzMismatchCount);
    rmseLabel.BackgroundColor = [0.85 0.50 0.05];   % orange
elseif nPruned > 0
    rmseLabel.Text = sprintf('%s\nSolver error: %.2f px\n%d weak edge(s) dropped', ...
        ratingText, obj.solverInfo.rmseTotal, nPruned);
    rmseLabel.BackgroundColor = ratingColor;
else
    rmseLabel.Text = sprintf('%s\nSolver error: %.2f px\nSeam match: %s', ...
        ratingText, obj.solverInfo.rmseTotal, seamMatchText(worstSeamScore));
    rmseLabel.BackgroundColor = ratingColor;
end
rmseLabel.FontColor = [1 1 1];
if pendingResolve
    % Quoting the cached numbers here would contradict the chip, which has just
    % said they are stale.
    rmseLabel.Tooltip = sprintf([ ...
        'A seam was edited with Auto re-solve off, so the tile positions no\n' ...
        'longer follow from the measurements and the rating is out of date.\n\n' ...
        'Press Re-solve in the seam inspector to refresh it now - or simply\n' ...
        'press Stitch, which re-solves first and never fuses stale positions.']);
else
    rmseLabel.Tooltip = sprintf(['Two checks, combined:\n' ...
        '- Solver error: %.2f px (avg. mismatch between tiles; <1 great, >10 poor)\n' ...
        '- Seam match: %s (pixel overlap at seams; 0.7+ good, <0.4 bad)\n' ...
        'Tiles with no measurement stay at their nominal spot, unchecked.\n' ...
        'Use Inspect & fix to correct problem seams.'], ...
        obj.solverInfo.rmseTotal, seamMatchText(worstSeamScore));
end

end

% =========================================================================
function text = seamMatchText(worstSeamScore)
% SEAMMATCHTEXT - The seam figure, or why there is none. NaN here means no VALID
% edge carries a score: either nothing has been scored yet, or the user
% cancelled the Scoring seams pass (which clears the partial result rather than
% rate the mosaic on the half of the seams it managed to read). Saying so beats
% printing "NaN" - and the rating shown beside it is then the solver residual
% alone, which on a chain-like graph is exactly the number that cannot be
% trusted on its own.
if isnan(worstSeamScore)
    text = 'not checked';
else
    text = sprintf('%.2f', worstSeamScore);
end
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
