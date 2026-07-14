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

if isempty(obj.edges)
    warnOptions.MsgBoxOnly  = true;
    warnOptions.Icon        = 'puffin_warning';
    warnOptions.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        'No edge measurements available. Please run Measure first.', {}, {}, ...
        'No measurements', warnOptions);
    return;
end

% Solve positions
solverOptions.springWeight = obj.BatchOpt.NominalPositionWeight{1};

try
    [obj.positions, solverInfo] = utils.stitch.solveGlobalLeastSquares( ...
        obj.layout, obj.edges, solverOptions);
catch solverError
    utils.dlgs.showErrorDialog(obj.view.gui, solverError.message, 'Solver failed');
    return;
end

% Plan canvas
try
    obj.canvas = utils.stitch.planCanvas(obj.layout, obj.positions);
catch canvasError
    utils.dlgs.showErrorDialog(obj.view.gui, canvasError.message, 'Canvas planning failed');
    return;
end

obj.updateWidgets();

% Colour-coded alignment quality: translate the raw RMSE (in pixels — the mean
% disagreement between the pairwise measurements at the solved positions) into a
% plain-language rating on a green→red scale that a non-specialist can read at a
% glance. The exact px value stays in the text and the tooltip for those who want it.
if isfield(solverInfo, 'rmseTotal')
    [ratingText, ratingColor] = qualityRating(solverInfo.rmseTotal);
    rmseLabel = obj.view.handles.rmseLabel;
    if solverInfo.nPruned > 0
        rmseLabel.Text = sprintf('  %s  (%.2f px, %d weak edge(s) dropped)  ', ...
            ratingText, solverInfo.rmseTotal, solverInfo.nPruned);
    else
        rmseLabel.Text = sprintf('  %s  (%.2f px)  ', ratingText, solverInfo.rmseTotal);
    end
    rmseLabel.BackgroundColor = ratingColor;
    rmseLabel.FontColor = [1 1 1];
    rmseLabel.Tooltip = sprintf(['Alignment residual: %.2f px root-mean-square.\n' ...
        'How much the pairwise overlap measurements disagree at the solved positions.\n' ...
        '< 1 px excellent · 1–3 good · 3–10 fair · > 10 poor.'], solverInfo.rmseTotal);
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
