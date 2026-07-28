function measureOverlaps_Callback(obj)
% MEASUREOVERLAPS_CALLBACK - Measure pairwise shifts for all neighbour tile pairs.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.measureOverlaps_Callback()
%
% Calls ``utils.stitch.findNeighborPairs`` to identify all overlapping tile
% pairs, then calls ``utils.stitch.measureAllPairs`` to compute phase-
% correlation shifts and quality scores for each pair.  Results are cached
% in ``obj.edges`` and the status label is updated.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.measureOverlaps_Callback: triggered\n');
end
if isempty(obj.layout)
    obj.warnUser('No layout loaded. Please select input tiles first.', 'No layout');
    return;
end

% Estimate the actual overlap from the images first (grid layouts): the
% user-entered overlap is often only a guess, and a wrong nominal defeats the
% restricted-search pairwise measurement.
if obj.BatchOpt.EstimateOverlap
    try
        obj.runOverlapEstimation();
    catch estimateError
        obj.reportError(estimateError, 'Overlap estimation failed');
        return;
    end
end

% Find neighbour pairs from nominal layout
pairOptions.minOverlapPx = 16;
nominalPairs = utils.stitch.findNeighborPairs(obj.layout, pairOptions);

if isempty(nominalPairs)
    obj.warnUser('No overlapping tile pairs found. Check overlap settings.', 'No pairs');
    return;
end

% Measure all pairs
measureOptions.qualityThreshold   = obj.BatchOpt.QualityThreshold{1};
measureOptions.subpixel           = obj.BatchOpt.SubpixelPlacement;
measureOptions.registrationMethod = obj.BatchOpt.RegistrationMethod{1};
measureOptions.transformType      = obj.BatchOpt.TransformType{1};
measureOptions.allowRotation      = obj.BatchOpt.AllowRotation;
% A non-translation transform implies the feature-based estimator (phase
% correlation can only measure translation), so its options are needed too.
if strcmp(obj.BatchOpt.RegistrationMethod{1}, 'Feature-based') || ...
        ~strcmp(obj.BatchOpt.TransformType{1}, 'Translation')
    measureOptions.featureOptions = obj.buildFeatureOptions();
end
measureOptions.parentFigure       = obj.guiFigure();
measureOptions.showWaitbar        = obj.BatchOpt.showWaitbar && ~isempty(measureOptions.parentFigure);

try
    obj.edges = utils.stitch.measureAllPairs(obj.layout, nominalPairs, measureOptions);
catch measureError
    obj.reportError(measureError, 'Measurement failed');
    return;
end

obj.updateWidgets();

end
