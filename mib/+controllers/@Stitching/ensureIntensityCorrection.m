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
% Output Arguments:
%   - **correction** - struct per :func:`utils.stitch.estimateIntensityCorrection`;
%     ``[]`` only when there is no layout to estimate from.
%
% See also utils.stitch.estimateIntensityCorrection, utils.stitch.makeTileReader

correction = [];
if isempty(obj.layout); return; end

if ~isempty(obj.intensityCorrection) && isstruct(obj.intensityCorrection) && ...
        strcmp(obj.intensityCorrection.method, obj.BatchOpt.IntensityCorrection{1})
    correction = obj.intensityCorrection;
    return;
end

estimateOptions = struct( ...
    'method',       obj.BatchOpt.IntensityCorrection{1}, ...
    'showWaitbar',  obj.BatchOpt.showWaitbar, ...
    'parentFigure', obj.guiFigure());

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
