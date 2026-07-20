function optimizePositions_Callback(obj)
% OPTIMIZEPOSITIONS_CALLBACK - Run global least-squares solve and plan the output canvas.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.optimizePositions_Callback()
%
% Calls ``utils.stitch.solveGlobalLeastSquares`` to determine optimal tile
% positions from the measured edge set, then calls ``utils.stitch.planCanvas``
% to compute the output canvas size and integer tile placements.  Results are
% cached in ``obj.positions`` and ``obj.canvas``.
%
% RMSE and residual statistics are displayed in the status label.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.optimizePositions_Callback: triggered\n');
end
if isempty(obj.edges)
    warnOptions.MsgBoxOnly  = true;
    warnOptions.Icon        = 'puffin_warning';
    warnOptions.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        'No edge measurements available. Please run Measure first.', {}, {}, ...
        'No measurements', warnOptions);
    return;
end

% Solve positions: translation -> per-axis scalar solve; anything richer -> the
% affine block solve, which returns per-tile transforms for the warp fuser.
solverOptions.springWeight = obj.BatchOpt.NominalPositionWeight{1};

try
    if strcmp(obj.BatchOpt.TransformType{1}, 'Translation')
        [obj.positions, solverInfo] = utils.stitch.solveGlobalLeastSquares( ...
            obj.layout, obj.edges, solverOptions);
        obj.tforms = {};
    else
        solverOptions.transformType = obj.BatchOpt.TransformType{1};
        solverOptions.allowRotation = obj.BatchOpt.AllowRotation;
        [obj.tforms, obj.positions, solverInfo] = utils.stitch.solveGlobalAffine( ...
            obj.layout, obj.edges, solverOptions);
    end
catch solverError
    utils.dlgs.showErrorDialog(obj.view.gui, solverError.message, 'Solver failed');
    return;
end

% Plan canvas (warped footprints when per-tile transforms exist; per-slice
% mosaic corrections from the inspector's Fix Z ride along)
try
    canvasOptions = struct('zSliceFixes', obj.zSliceFixes);
    if ~isempty(obj.tforms)
        canvasOptions.tforms = obj.tforms;
    end
    obj.canvas = utils.stitch.planCanvas(obj.layout, obj.positions, canvasOptions);
catch canvasError
    utils.dlgs.showErrorDialog(obj.view.gui, canvasError.message, 'Canvas planning failed');
    return;
end

% Verify the solve by the PIXELS: seam NCC of every valid edge at the solved
% positions. The solver residual is blind on chain-like graphs (no loops →
% residual ~0 whatever the measurements claim), so a confidently-wrong or
% orientation-mismatched measurement solves to "0.1 px" while the seams are
% garbage — only re-reading the actual overlap pixels catches that. Scores are
% stored on the edges (persisted with the project, reused by the inspector).
worstSeamScore = NaN;
dzMismatchCount = 0;
try
    obj.edges = utils.stitch.scoreSeams(obj.layout, obj.edges, obj.positions, ...
        struct('showWaitbar', true, 'parentFigure', obj.view.gui));
    validScores = [obj.edges([obj.edges.valid]).seamScore];
    if ~isempty(validScores)
        validScores(isnan(validScores)) = -1;   % no overlap at solved placement = broken
        worstSeamScore = min(validScores);
    end
    if isfield(obj.edges, 'dzHint')
        dzMismatchCount = nnz([obj.edges([obj.edges.valid]).dzHint]);
    end
catch
    % pixel verification is advisory — never block the solve on it
end

obj.updateWidgets();

% Colour-coded alignment quality: translate the raw RMSE (in pixels — the mean
% disagreement between the pairwise measurements at the solved positions) into a
% plain-language rating on a green→red scale that a non-specialist can read at a
% glance, DOWNGRADED whenever the pixel seam check disagrees with the residual.
% The exact numbers stay in the text and the tooltip for those who want them.
if isfield(solverInfo, 'rmseTotal')
    [ratingText, ratingColor] = qualityRating(solverInfo.rmseTotal);
    rmseLabel = obj.view.handles.rmseLabel;
    nDisconnected = 0;
    if isfield(solverInfo, 'disconnectedTiles')
        nDisconnected = numel(solverInfo.disconnectedTiles);
    end
    if nDisconnected > 0
        % A tile with no valid measurement is parked at its nominal position —
        % the RMSE over the remaining edges says NOTHING about it, so a green
        % chip would be a lie (a 3-tile row misread as 2x2 solves to 0.1 px
        % while a tile sits wherever the grid guess put it).
        rmseLabel.Text = sprintf('  Alignment incomplete  (%d tile(s) held at nominal, %.2f px on the rest)  ', ...
            nDisconnected, solverInfo.rmseTotal);
        rmseLabel.BackgroundColor = [0.85 0.50 0.05];   % orange
    elseif worstSeamScore < 0.4   % NaN compares false: no scores -> RMSE rating
        % The pixels at the solved seams do not match: wrong layout
        % orientation or a confidently-wrong measurement. The residual alone
        % would read "Excellent" here (chain graphs have nothing to
        % contradict) — that is the lie this branch exists to stop.
        rmseLabel.Text = sprintf('  Seams disagree  (worst pixel match %.2f, solver %.2f px) — Inspect & fix  ', ...
            worstSeamScore, solverInfo.rmseTotal);
        rmseLabel.BackgroundColor = [0.75 0.20 0.20];   % red
    elseif worstSeamScore < 0.7
        rmseLabel.Text = sprintf('  Check seams  (worst pixel match %.2f, solver %.2f px)  ', ...
            worstSeamScore, solverInfo.rmseTotal);
        rmseLabel.BackgroundColor = [0.85 0.50 0.05];   % orange
    elseif dzMismatchCount > 0
        % The XY seams look fine but the pixels prefer a DIFFERENT Z offset on
        % at least one cross-layer seam (edges(k).dzHint from the dz-scan in
        % scoreSeams) — a Z misalignment barely dents the XY scores, so it
        % needs its own branch to be visible.
        rmseLabel.Text = sprintf('  Check Z alignment  (%d seam(s) prefer a different Z offset, %.2f px)  ', ...
            dzMismatchCount, solverInfo.rmseTotal);
        rmseLabel.BackgroundColor = [0.85 0.50 0.05];   % orange
    elseif solverInfo.nPruned > 0
        rmseLabel.Text = sprintf('  %s  (%.2f px, %d weak edge(s) dropped)  ', ...
            ratingText, solverInfo.rmseTotal, solverInfo.nPruned);
        rmseLabel.BackgroundColor = ratingColor;
    else
        rmseLabel.Text = sprintf('  %s  (%.2f px)  ', ratingText, solverInfo.rmseTotal);
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
        solverInfo.rmseTotal, worstSeamScore);
end

% Refresh the layout preview so it reflects the freshly SOLVED positions.
if ~isempty(obj.layout)
    obj.previewLayoutBtn_Callback();
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
