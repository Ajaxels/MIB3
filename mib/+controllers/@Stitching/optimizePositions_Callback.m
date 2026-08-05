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

% Whoever asked for it, a completed solve settles any debt an inspector edit
% left behind: the positions now follow from the current edge set again.
obj.resolvePending = false;

% Plan canvas (warped footprints when per-tile transforms exist; per-slice
% mosaic corrections from the inspector's Fix Z ride along)
try
    canvasOptions = struct('zSliceFixes', obj.zSliceFixes, ...
        'autocrop', obj.BatchOpt.Autocrop);
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
% ensureSeamScores does the reading (and swallows any failure - pixel
% verification is advisory and must never block the solve). It is a no-op when
% the scores already describe this placement, which is what stops the seam
% inspector paying for a second full pass over the overlaps right after a
% re-solve.
scoringCancelled = obj.ensureSeamScores();

% Refreshes the widgets AND the alignment-quality chip (updateWidgets calls
% refreshQualityChip, which reads the solverInfo just cached above).
obj.updateWidgets();

% The SOLVE stands - only its pixel verification was skipped, so this is a note
% on the status line rather than an error or a StopProtocol. Set after
% updateWidgets, which rewrites the label. The chip already says "not checked"
% (scoreSeams cleared the partial scores), so this only names the reason.
if scoringCancelled && ~isempty(obj.view)
    obj.view.handles.statusLabel.Text = sprintf( ...
        '%s - seam check cancelled', obj.view.handles.statusLabel.Text);
end

% Refresh the layout preview so it reflects the freshly SOLVED positions.
if ~isempty(obj.layout)
    obj.previewLayoutBtn_Callback();
end

end
