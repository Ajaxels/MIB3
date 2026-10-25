function [probThresh, nmsThresh, accuracy, cancelled] = optimizeThresholds(net, images, labels, config, options)
% OPTIMIZETHRESHOLDS - Tune the probability and NMS thresholds of a StarDist model on validation images.
%
% Syntax:
%   .. code-block:: matlab
%
%      [probThresh, nmsThresh] = deepmib.stardist.optimizeThresholds(net, images, labels, config)
%      [probThresh, nmsThresh, accuracy, cancelled] = deepmib.stardist.optimizeThresholds(net, images, labels, config, options)
%
% Follows StarDist 0.9.2 ``optimize_thresholds`` / ``utils.optimize_threshold``: the maps of
% every validation image are predicted once; then, for each NMS threshold in
% ``options.nmsThreshs``, the probability threshold is optimised within
% ``[maxProb/2, maxProb]`` (``maxProb`` = the highest probability over all images), and the
% pair with the best score is returned (the first one on ties, as StarDist).
%
% The score of a threshold pair is the matching **accuracy** ``TP / (TP + FP + FN)``, with
% ``TP``, ``FP`` and ``FN`` summed over all validation images, averaged over the IoU thresholds
% ``options.iouThreshs``, with the one-to-one matching of deepmib.stardist.matchInstances.
%
% The search is a line-by-line port of what StarDist calls, scipy
% ``minimize_scalar(method='golden', bracket=(maxProb/2, maxProb), tol, options={'maxiter'})``:
% ``scipy.optimize.bracket`` first expands the two points into a three-point bracket with
% golden and parabolic steps (probes outside ``[maxProb/2, maxProb]`` are evaluated at the
% nearest bound, as StarDist clips them), then the golden-section loop runs for at most
% ``options.maxIterations`` iterations or until the bracket is narrower than
% ``options.tolerance * (|x1| + |x2|)``. Accuracy is a step function of the threshold, so a
% different search would stop on a different plateau; the port makes MIB find the same
% thresholds as StarDist for the same maps (checked against StarDist 0.9.2 / scipy 1.15).
% When scipy's bracket is invalid (flat objective), the best of its three points is used, as in
% scipy's ``_recover_from_bracket_error``.
%
% One deliberate difference: StarDist returns scipy's raw ``x``, which can lie outside the bracket
% although the objective was evaluated at the clipped value; this function returns the clipped
% value, i.e. the threshold whose accuracy is reported.
%
% Every evaluation runs deepmib.stardist.nms on all validation images, which dominates the run
% time.
%
% Input Arguments:
%   - **net** - [dlnetwork] StarDist network
%   - **images** - [cell] normalised validation images, see deepmib.stardist.normalizeImage
%   - **labels** - [cell] ground-truth instance label maps of the same sizes
%   - **config** - [struct] configuration, see deepmib.stardist.defaultConfig
%   - **options** *(optional)* - struct with fields:
%
%     - ``.nmsThreshs`` - [numeric] NMS thresholds to try (default: ``[0.3 0.4 0.5]``)
%     - ``.iouThreshs`` - [numeric] IoU thresholds of the score (default: ``[0.3 0.5 0.7]``)
%     - ``.maxIterations`` - [numeric] golden-section iterations per NMS threshold, scipy
%       ``maxiter`` (default: ``20``)
%     - ``.tolerance`` - [numeric] relative width of the final bracket, scipy ``xtol``
%       (default: ``1e-2``)
%     - ``.executionEnvironment`` - [char] ``'auto'``, ``'gpu'`` or ``'cpu'`` (default: ``'auto'``)
%     - ``.tileSize`` - [1x2 numeric] tile core size of the prediction (default: ``[1024 1024]``)
%     - ``.progressDlg`` - [uiprogressdlg] dialog whose ``Value`` follows the search and whose
%       ``CancelRequested`` is checked before every evaluation and inside the NMS; ``[]`` for none
%       (default: ``[]``)
%
% Output Arguments:
%   - **probThresh** - [double] optimised probability threshold
%   - **nmsThresh** - [double] the NMS threshold of the best pair
%   - **accuracy** - [double] score of the returned pair
%   - **cancelled** - [logical] ``true`` when the user pressed Cancel; the other outputs are then
%     empty and the caller must keep its previous thresholds

if nargin < 5; options = struct(); end
defaults = struct('nmsThreshs', [0.3 0.4 0.5], 'iouThreshs', [0.3 0.5 0.7], 'maxIterations', 20, ...
    'tolerance', 1e-2, 'executionEnvironment', 'auto', 'tileSize', [1024 1024], 'progressDlg', []);
fieldNames = fieldnames(defaults);
for fieldId = 1:numel(fieldNames)
    if ~isfield(options, fieldNames{fieldId}); options.(fieldNames{fieldId}) = defaults.(fieldNames{fieldId}); end
end
config = deepmib.stardist.defaultConfig(config);
probThresh = []; nmsThresh = []; accuracy = []; cancelled = false;
dlg = options.progressDlg;
nImages = numel(images);

% 1. maps, once per image
probMaps = cell(nImages, 1);
distMaps = cell(nImages, 1);
mapOptions = struct('tileSize', options.tileSize, 'executionEnvironment', options.executionEnvironment);
for imageId = 1:nImages
    if ~isempty(dlg)
        if dlg.CancelRequested; cancelled = true; return; end
        dlg.Value = 0.2 * (imageId - 1) / nImages;
    end
    [probMaps{imageId}, distMaps{imageId}] = deepmib.stardist.predictMaps(net, images{imageId}, config, mapOptions);
end
maxProb = max(cellfun(@(p) max(p, [], 'all'), probMaps));

% 2. for each nmsThresh, scipy golden search of probThresh on the negated accuracy; a cancel
% inside the objective is raised as an error and caught here
bracketLow = maxProb / 2;
bracketHigh = maxProb;
nmsOptions = struct('progressDlg', dlg);
nEvaluationsExpected = numel(options.nmsThreshs) * (options.maxIterations + 5);
nEvaluationsDone = 0;
bestScore = -Inf;
try
    for nmsCandidate = options.nmsThreshs(:)'
        cache = dictionary(double.empty, double.empty);   % objective by clipped threshold
        objective = @(threshold) negatedAccuracy(threshold, nmsCandidate);
        [xa, xb, xc, fa, fb, fc, isValid] = scipyBracket(objective, bracketLow, bracketHigh);
        if isValid
            [xMin, fMin] = scipyGolden(objective, xa, xb, xc, options.tolerance, options.maxIterations);
        else
            [fMin, minId] = min([fa fb fc]);
            candidates = [xa xb xc];
            xMin = candidates(minId);
        end
        if -fMin > bestScore
            bestScore = -fMin;
            probThresh = min(max(xMin, bracketLow), bracketHigh);
            nmsThresh = nmsCandidate;
        end
    end
catch err
    if ~strcmp(err.identifier, 'stardist:optimizeThresholds:cancelled'); rethrow(err); end
    probThresh = []; nmsThresh = []; accuracy = []; cancelled = true;
    return;
end
accuracy = bestScore;
if ~isempty(dlg); dlg.Value = 1; end

    function value = negatedAccuracy(threshold, nmsCandidate)
        % -(mean accuracy over the IoU thresholds), TP/FP/FN summed over the images; probes
        % outside the bracket are evaluated at the nearest bound, as StarDist does
        threshold = min(max(threshold, bracketLow), bracketHigh);
        if isKey(cache, threshold); value = cache(threshold); return; end
        if ~isempty(dlg)
            if dlg.CancelRequested; error('stardist:optimizeThresholds:cancelled', 'Cancelled'); end
            dlg.Value = 0.2 + 0.8 * min(1, nEvaluationsDone / nEvaluationsExpected);
        end
        nEvaluationsDone = nEvaluationsDone + 1;
        truePositives = zeros(1, numel(options.iouThreshs));
        nTrue = 0;
        nPred = 0;
        for evalImageId = 1:nImages
            [points, scores, rayDist, wasCancelled] = deepmib.stardist.nms(probMaps{evalImageId}, ...
                distMaps{evalImageId}, config.grid, threshold, nmsCandidate, nmsOptions);
            if wasCancelled; error('stardist:optimizeThresholds:cancelled', 'Cancelled'); end
            predicted = deepmib.stardist.polygonsToLabel(points, rayDist, scores, size(labels{evalImageId}, [1 2]));
            imageStats = deepmib.stardist.matchInstances(labels{evalImageId}, predicted, options.iouThreshs);
            truePositives = truePositives + imageStats.truePositives;
            nTrue = nTrue + imageStats.nTrue;
            nPred = nPred + imageStats.nPred;
        end
        falsePositives = nPred - truePositives;
        falseNegatives = nTrue - truePositives;
        value = -mean(truePositives ./ max(truePositives + falsePositives + falseNegatives, 1));
        cache(threshold) = value;
    end
end

function [xa, xb, xc, fa, fb, fc, isValid] = scipyBracket(func, xa, xb)
% scipy.optimize.bracket (scipy 1.15), grow_limit = 110, maxiter = 1000
gold = 1.618034;
verySmall = 1e-21;
growLimit = 110;
maxIterations = 1000;
fa = func(xa);
fb = func(xb);
if fa < fb
    [xa, xb] = deal(xb, xa);
    [fa, fb] = deal(fb, fa);
end
xc = xb + gold * (xb - xa);
fc = func(xc);
iteration = 0;
while fc < fb
    tmp1 = (xb - xa) * (fb - fc);
    tmp2 = (xb - xc) * (fb - fa);
    val = tmp2 - tmp1;
    if abs(val) < verySmall
        denominator = 2 * verySmall;
    else
        denominator = 2 * val;
    end
    w = xb - ((xb - xc) * tmp2 - (xb - xa) * tmp1) / denominator;
    wLimit = xb + growLimit * (xc - xb);
    if iteration > maxIterations; break; end   % scipy raises; treated as an invalid bracket
    iteration = iteration + 1;
    if (w - xc) * (xb - w) > 0
        fw = func(w);
        if fw < fc
            xa = xb; xb = w; fa = fb; fb = fw;
            break;
        elseif fw > fb
            xc = w; fc = fw;
            break;
        end
        w = xc + gold * (xc - xb);
        fw = func(w);
    elseif (w - wLimit) * (wLimit - xc) >= 0
        w = wLimit;
        fw = func(w);
    elseif (w - wLimit) * (xc - w) > 0
        fw = func(w);
        if fw < fc
            xb = xc; xc = w;
            w = xc + gold * (xc - xb);
            fb = fc; fc = fw;
            fw = func(w);
        end
    else
        w = xc + gold * (xc - xb);
        fw = func(w);
    end
    xa = xb; xb = xc; xc = w;
    fa = fb; fb = fc; fc = fw;
end
condition1 = (fb < fc && fb <= fa) || (fb < fa && fb <= fc);
condition2 = (xa < xb && xb < xc) || (xc < xb && xb < xa);
condition3 = all(isfinite([xa xb xc]));
isValid = condition1 && condition2 && condition3;
end

function [xMin, fMin] = scipyGolden(func, xa, xb, xc, tolerance, maxIterations)
% scipy.optimize._optimize._minimize_scalar_golden (scipy 1.15) from a valid bracket
goldenRatio = 0.61803399;
goldenComplement = 1 - goldenRatio;
x3 = xc;
x0 = xa;
if abs(xc - xb) > abs(xb - xa)
    x1 = xb;
    x2 = xb + goldenComplement * (xc - xb);
else
    x2 = xb;
    x1 = xb - goldenComplement * (xb - xa);
end
f1 = func(x1);
f2 = func(x2);
for iteration = 1:maxIterations
    if abs(x3 - x0) <= tolerance * (abs(x1) + abs(x2)); break; end
    if f2 < f1
        x0 = x1; x1 = x2;
        x2 = goldenRatio * x1 + goldenComplement * x3;
        f1 = f2;
        f2 = func(x2);
    else
        x3 = x2; x2 = x1;
        x1 = goldenRatio * x2 + goldenComplement * x0;
        f2 = f1;
        f1 = func(x1);
    end
end
if f1 < f2
    xMin = x1; fMin = f1;
else
    xMin = x2; fMin = f2;
end
end
