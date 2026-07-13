function measureBtn_Callback(obj)
% MEASUREBTN_CALLBACK - Measure pairwise shifts for all neighbour tile pairs.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.measureBtn_Callback()
%
% Calls ``utils.stitch.findNeighborPairs`` to identify all overlapping tile
% pairs, then calls ``utils.stitch.measureAllPairs`` to compute phase-
% correlation shifts and quality scores for each pair.  Results are cached
% in ``obj.edges`` and the status label is updated.
%

if isempty(obj.layout)
    warnOptions.MsgBoxOnly  = true;
    warnOptions.Icon        = 'puffin_warning';
    warnOptions.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        'No layout loaded. Please select input tiles first.', {}, {}, ...
        'No layout', warnOptions);
    return;
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
measureOptions.qualityThreshold = obj.BatchOpt.QualityThreshold{1};
measureOptions.subpixel         = obj.BatchOpt.SubpixelPlacement;
measureOptions.showWaitbar      = obj.BatchOpt.showWaitbar;
measureOptions.parentFigure     = obj.view.gui;

try
    obj.edges = utils.stitch.measureAllPairs(obj.layout, nominalPairs, measureOptions);
catch measureError
    utils.dlgs.showErrorDialog(obj.view.gui, measureError.message, 'Measurement failed');
    return;
end

obj.updateWidgets();

end
