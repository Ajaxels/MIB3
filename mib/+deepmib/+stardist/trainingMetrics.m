function metrics = trainingMetrics()
% TRAININGMETRICS - Metrics reported by trainnet while a StarDist network trains.
%
% Syntax:
%   .. code-block:: matlab
%
%      metrics = deepmib.stardist.trainingMetrics()
%      options = trainingOptions('adam', 'Metrics', deepmib.stardist.trainingMetrics())
%
% Returns ``{@coreIoU}``: the intersection over union, in percent, between the object **cores**
% of the prediction and of the target, i.e. the grid cells where the probability channel is
% ``> 0.5`` in the network output and in the probability target, pooled over the mini-batch.
% ``trainnet`` reports it per mini-batch and averages it over the mini-batches of the validation
% set, as ``TrainingcoreIoU`` / ``ValidationcoreIoU``; the MIB progress window shows it on its
% accuracy gauges (deepmib.customTrainingProgressDisplayTrainNet).
%
% Both sides are thresholded at the same level because the probability target is soft (the
% normalised distance to the object edge, see deepmib.stardist.computeTargets): it is 1 at the
% object centre and falls towards the edge. A first version compared the predicted cores with
% every pixel inside an object (target ``> 0``), which no network can match - the pretrained
% ``2D_versatile_fluo`` scored 29-35% on its own DSB2018 images. With cores on both sides a perfect
% network scores 100%, and ``2D_versatile_fluo`` scores 69-85% on those images (the targets near
% 0.5 cannot be matched exactly); measured in ``development/deepmib/plan_stardist.md``, phase 3.
%
% It is a cheap progress indicator where a classification accuracy does not exist: it measures
% how well the objects are found, not whether touching objects are separated, which only the
% object-level accuracy of deepmib.stardist.optimizeThresholds after training does.
%
% The metric is a local function returned by handle because ``trainnet`` names a metric after
% its function and requires a valid variable name: a package function handle
% (``@deepmib.stardist.coreIoU``) is rejected with "These are not valid variable names".
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   - **metrics** - [cell] function handles for the ``'Metrics'`` training option

metrics = {@coreIoU};
end

function value = coreIoU(Y, T)
% IoU in percent of predicted and true object cores (probability > 0.5); 100 when neither has one
predicted = extractdata(Y(:, :, 1, :)) > 0.5;
actual = T(:, :, 1, :) > 0.5;
if isa(actual, 'dlarray'); actual = extractdata(actual); end
union = nnz(predicted | actual);
if union == 0
    value = 100;
else
    value = 100 * double(gather(nnz(predicted & actual))) / double(gather(union));
end
end
