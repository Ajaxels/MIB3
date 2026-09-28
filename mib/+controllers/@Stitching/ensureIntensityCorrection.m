function correction = ensureIntensityCorrection(obj)
% ENSURETILECORRECTION - The intensity correction every tile read is made with.
%
% Syntax:
%   .. code-block:: matlab
%
%      correction = obj.ensureIntensityCorrection()
%
% Returns the correction implied by ``BatchOpt.IntensityCorrection``, estimating it on
% first use and caching it in ``obj.intensityCorrection``. Every stage that builds a
% tile reader - overlap estimation, measurement, seam scoring, the seam inspector
% and both fusers - passes the result through as ``options.correction``, which is
% what makes them all see the SAME pixels. A stage that skipped it would measure
% or score one set of intensities and fuse another.
%
% **Why it is lazy.** Estimating reads every tile once, which is worth avoiding
% until something actually needs pixels: opening a dialog, picking an input or
% flipping the dropdown must stay instant. The cache is dropped by
% :meth:`controllers.Stitching.buildLayoutFromBatchOpt` (new tiles) and by
% :meth:`controllers.Stitching.updateBatchOptFromGUI` (new method), so it can
% never describe a job other than the current one.
%
% ``'None'`` still produces a struct (neutral gains, no field) rather than ``[]``.
% Distinguishing "estimated, and the answer is no correction" from "not estimated
% yet" is what stops the estimate being retried on every stage of a run.
%
% **``'Re-exposure damage'`` also depends on the PLACEMENT**, which none of the
% other methods do closely enough to matter: it corrects a sharp-edged patch where
% an earlier tile's footprint fell, so its footprints are only as right as the
% positions they were placed with. Two consequences:
%
% - **Before the first solve it is neutral.** Nominal positions can be off by
%   many pixels (117 px vertically on the reference pair), and a correction placed
%   there would paint a sharp false edge into the pixels the registration then
%   measures. Measure overlaps and overlap estimation therefore run on uncorrected
%   pixels - phase correlation is insensitive to a flat offset band anyway - and
%   the damage is estimated as soon as solved positions exist, i.e. before the
%   seams are scored and before anything is fused.
% - **A changed placement re-places it.** The cached correction records the
%   positions it was placed with; when they no longer match ``obj.positions`` it
%   is re-estimated with the old one passed as ``previous``, which for a move of
%   a few pixels (a re-solve, an inspector fix) only re-places the footprints and
%   reads no pixel.
%
% Output Arguments:
%   - **correction** - struct per :func:`utils.stitch.estimateIntensityCorrection`;
%     ``[]`` only when there is no layout to estimate from.
%
% See also utils.stitch.estimateIntensityCorrection, utils.stitch.makeTileReader

correction = [];
if isempty(obj.layout); return; end

method = obj.BatchOpt.IntensityCorrection{1};
correctsDamage = strcmp(method, 'Re-exposure damage');
cached = obj.intensityCorrection;
if ~isempty(cached) && isstruct(cached) && strcmp(cached.method, method)
    if ~correctsDamage || ...
            (isempty(obj.positions) && isempty(cached.damage)) || ...
            (~isempty(obj.positions) && damagePlacedAt(cached, obj.positions))
        correction = cached;
        return;
    end
end

if correctsDamage && isempty(obj.positions)
    % Neutral until a solve exists; recorded under the method's own name so the
    % stages before the solve reuse it instead of retrying.
    obj.intensityCorrection = utils.stitch.estimateIntensityCorrection(obj.layout, struct('method', 'None'));
    obj.intensityCorrection.method = method;
    correction = obj.intensityCorrection;
    return;
end

estimateOptions = struct( ...
    'method',       method, ...
    'showWaitbar',  obj.BatchOpt.showWaitbar, ...
    'parentFigure', obj.guiFigure());
if correctsDamage && ~isempty(cached) && isstruct(cached) && strcmp(cached.method, method)
    estimateOptions.previous = cached;
end

% The overlap-solved method needs to know which pixels of two tiles show the same
% specimen. Solved positions are the best answer, but nominal origins are ample
% when nothing is solved yet (samples are block-averaged, so a few pixels of
% placement error do not move a low-order field) - which is what lets the method
% be chosen before Measure overlaps has ever run. The edges come along so that a
% seam excluded in the inspector cannot steer the fit either.
estimateOptions.positions = obj.positions;
estimateOptions.edges     = obj.edges;

try
    obj.intensityCorrection = utils.stitch.estimateIntensityCorrection(obj.layout, estimateOptions);
catch estimateError
    % Advisory, never fatal: a mosaic that cannot be intensity-corrected is still
    % perfectly stitchable, and failing here would block the whole run.
    warning('Stitching:intensityCorrectionFailed', ...
        'Could not estimate the tile intensity correction (%s); continuing without one.', ...
        estimateError.message);
    obj.intensityCorrection = utils.stitch.estimateIntensityCorrection(obj.layout, struct('method', 'None'));
end

correction = obj.intensityCorrection;

end

% =========================================================================
function tf = damagePlacedAt(correction, positions)
% DAMAGEPLACEDAT - Were this correction's footprints placed at these positions?
% A placeholder (no damage model yet) never matches, so it is replaced as soon as
% positions exist.
tf = isfield(correction, 'damage') && isstruct(correction.damage) && ...
    isfield(correction.damage, 'positions') && ...
    isequal(size(correction.damage.positions), [size(positions, 1), 2]) && ...
    isequal(correction.damage.positions, double(positions(:, 1:2)));
end
