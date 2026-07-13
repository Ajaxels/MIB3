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

% Display RMSE in status label
if isfield(solverInfo, 'rmseTotal')
    obj.view.handles.rmseLabel.Text = sprintf('RMSE: %.2f px (%d edges pruned)', ...
        solverInfo.rmseTotal, solverInfo.nPruned);
end

obj.updateWidgets();

end
