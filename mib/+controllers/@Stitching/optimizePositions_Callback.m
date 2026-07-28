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
    obj.warnUser('No edge measurements available. Please run Measure first.', 'No measurements');
    return;
end

% Solve positions: translation -> per-axis scalar solve; anything richer -> the
% affine block solve, which returns per-tile transforms for the warp fuser.
solverOptions.springWeight = obj.BatchOpt.NominalPositionWeight{1};

try
    if strcmp(obj.BatchOpt.TransformType{1}, 'Translation')
        [obj.positions, obj.solverInfo] = utils.stitch.solveGlobalLeastSquares( ...
            obj.layout, obj.edges, solverOptions);
        obj.tforms = {};
    else
        solverOptions.transformType = obj.BatchOpt.TransformType{1};
        solverOptions.allowRotation = obj.BatchOpt.AllowRotation;
        [obj.tforms, obj.positions, obj.solverInfo] = utils.stitch.solveGlobalAffine( ...
            obj.layout, obj.edges, solverOptions);
    end
catch solverError
    obj.reportError(solverError, 'Solver failed');
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
    obj.reportError(canvasError, 'Canvas planning failed');
    return;
end

% Verify the solve by the PIXELS: seam NCC of every valid edge at the solved
% positions. The solver residual is blind on chain-like graphs (no loops →
% residual ~0 whatever the measurements claim), so a confidently-wrong or
% orientation-mismatched measurement solves to "0.1 px" while the seams are
% garbage — only re-reading the actual overlap pixels catches that. Scores are
% stored on the edges (persisted with the project, reused by the inspector and
% by refreshQualityChip, which turns them into the rating without re-reading).
parentFigure = obj.guiFigure();
try
    obj.edges = utils.stitch.scoreSeams(obj.layout, obj.edges, obj.positions, ...
        struct('showWaitbar', ~isempty(parentFigure), 'parentFigure', parentFigure));
catch
    % pixel verification is advisory — never block the solve on it
end

% Refreshes the widgets AND the alignment-quality chip (updateWidgets calls
% refreshQualityChip, which reads the solverInfo just cached above).
obj.updateWidgets();

% Refresh the layout preview so it reflects the freshly SOLVED positions.
if ~isempty(obj.layout)
    obj.previewLayoutBtn_Callback();
end

end
