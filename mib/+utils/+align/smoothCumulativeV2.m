function [cumT, cumR, cumS] = smoothCumulativeV2(cumT, cumR, cumS, Depth, ...
    transformType, BatchOpt)
% SMOOTHCUMULATIVEV2 - Running-average smoothing of cumulative v2 parameters (batch).
%
% Syntax:
%   .. code-block:: matlab
%
%      [cumT, cumR, cumS] = utils.align.smoothCumulativeV2(cumT, cumR, cumS, ...
%          Depth, transformType, BatchOpt)
%
% BatchOpt-driven smoothing (no dialogs): each subtract flag enables smoothing
% of the corresponding parameter set; ``SubtractRunningAverageStep`` drives the
% half-width; per-parameter exclude-jump thresholds come from the legacy
% stretch/shear BatchOpt fields (mapped onto the v2 translation/rotation/scale
% components). Shared by the in-memory and BigData v2 alignment paths.
%
% See also: utils.align.runningAverageSmoothPoints, utils.align.interactiveSmoothingV2

halfwidth = BatchOpt.SubtractRunningAverageStep{1};
if halfwidth > floor(Depth/2 - 1)
    halfwidth = max(1, floor(Depth/2 - 1));
end
% v1-vs-v2 BatchOpt name mapping (v2 fields fall back to v1 stretch/shear)
excludeTranslation = BatchOpt.SubtractRunningAverageExcludeStretchPeaks{1};
excludeRotation    = BatchOpt.SubtractRunningAverageExcludeShearPeaks{1};
excludeScale       = BatchOpt.SubtractRunningAverageExcludeStretchPeaks{1};

if BatchOpt.SubtractRunningAverageFixStretch
    cumT(:, 1) = utils.align.runningAverageSmoothPoints(cumT(:, 1), halfwidth, excludeTranslation);
    cumT(:, 2) = utils.align.runningAverageSmoothPoints(cumT(:, 2), halfwidth, excludeTranslation);
end
if BatchOpt.SubtractRunningAverageFixShear && ismember(transformType, {'rigid', 'similarity', 'affine'})
    cumR = utils.align.runningAverageSmoothPoints(cumR, halfwidth, excludeRotation);
end
if BatchOpt.SubtractRunningAverageFixStretch && ismember(transformType, {'similarity', 'affine'})
    cumS = utils.align.runningAverageSmoothPoints(cumS, halfwidth, excludeScale) + 1;
end
end
