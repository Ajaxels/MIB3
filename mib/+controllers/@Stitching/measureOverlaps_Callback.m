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
    warnOptions.MsgBoxOnly  = true;
    warnOptions.Icon        = 'puffin_warning';
    warnOptions.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        'No layout loaded. Please select input tiles first.', {}, {}, ...
        'No layout', warnOptions);
    return;
end

% Estimate the actual overlap from the images first (grid layouts): the
% user-entered overlap is often only a guess, and a wrong nominal defeats the
% restricted-search pairwise measurement.
if obj.BatchOpt.EstimateOverlap
    try
        obj.runOverlapEstimation();
    catch estimateError
        utils.dlgs.showErrorDialog(obj.view.gui, estimateError.message, 'Overlap estimation failed');
        return;
    end
end

% Find neighbour pairs from nominal layout
pairOptions.minOverlapPx = 16;
nominalPairs = utils.stitch.findNeighborPairs(obj.layout, pairOptions);

if isempty(nominalPairs)
    warnOptions.MsgBoxOnly  = true;
    warnOptions.Icon        = 'puffin_warning';
    warnOptions.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        'No overlapping tile pairs found. Check overlap settings.', {}, {}, ...
        'No pairs', warnOptions);
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
measureOptions.showWaitbar        = obj.BatchOpt.showWaitbar;
measureOptions.parentFigure       = obj.view.gui;

try
    obj.edges = utils.stitch.measureAllPairs(obj.layout, nominalPairs, measureOptions);
catch measureError
    utils.dlgs.showErrorDialog(obj.view.gui, measureError.message, 'Measurement failed');
    return;
end

obj.updateWidgets();

end
