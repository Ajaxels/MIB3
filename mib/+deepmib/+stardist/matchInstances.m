function stats = matchInstances(labelsTrue, labelsPred, iouThreshs)
% MATCHINSTANCES - One-to-one matching of predicted and true instances at IoU thresholds, as StarDist.
%
% Syntax:
%   .. code-block:: matlab
%
%      stats = deepmib.stardist.matchInstances(labelsTrue, labelsPred, iouThreshs)
%
% Reproduces ``stardist.matching.matching`` (StarDist 0.9.2) for one image. Label ids are
% arbitrary positive integers, 0 is background. The IoU of every true/predicted pair is
% computed from the pixel overlap; at each threshold a pair can match when its IoU is **at
% least** the threshold. Below an IoU of 0.5 one object can overlap several others by that
% much, so the one-to-one assignment is solved with ``matchpairs``, maximising first the
% number of matches and second the sum of their IoUs (StarDist uses
% ``linear_sum_assignment`` with the same objective).
%
% Dataset scores are built by summing ``truePositives``, ``nTrue`` and ``nPred`` over the
% images, as ``matching_dataset`` does: accuracy ``TP / (TP + FP + FN)`` with
% ``FP = nPred - TP`` and ``FN = nTrue - TP``, and ``mean_true_score = sumMatchedIoU / nTrue``.
%
% Input Arguments:
%   - **labelsTrue** - [integer] ground-truth label image
%   - **labelsPred** - [integer] predicted label image of the same size
%   - **iouThreshs** - [numeric] IoU thresholds, e.g. ``[0.3 0.5 0.7]``
%
% Output Arguments:
%   - **stats** - [struct] with fields:
%
%     - ``.truePositives`` - [1xK double] matched pairs per threshold
%     - ``.sumMatchedIoU`` - [1xK double] sum of the IoUs of the matched pairs per threshold
%     - ``.nTrue`` - [double] number of true objects
%     - ``.nPred`` - [double] number of predicted objects

nThreshs = numel(iouThreshs);
stats = struct('truePositives', zeros(1, nThreshs), 'sumMatchedIoU', zeros(1, nThreshs), 'nTrue', 0, 'nPred', 0);

[trueIds, ~, trueIndex] = unique(labelsTrue(:));
[predIds, ~, predIndex] = unique(labelsPred(:));
overlap = accumarray([trueIndex, predIndex], 1, [numel(trueIds), numel(predIds)]);
areaTrue = sum(overlap, 2);
areaPred = sum(overlap, 1);
if trueIds(1) == 0; overlap(1, :) = []; areaTrue(1) = []; end
if predIds(1) == 0; overlap(:, 1) = []; areaPred(1) = []; end
stats.nTrue = size(overlap, 1);
stats.nPred = size(overlap, 2);
if stats.nTrue == 0 || stats.nPred == 0; return; end

iou = overlap ./ (areaTrue + areaPred - overlap);
nMatchable = min(stats.nTrue, stats.nPred);
for threshId = 1:nThreshs
    passes = iou >= iouThreshs(threshId);
    if ~any(passes(:)); continue; end
    benefit = double(passes) + iou / (2 * nMatchable);
    benefit(~passes) = 0;
    pairs = matchpairs(benefit, 0, 'max');
    pairIndex = sub2ind(size(iou), pairs(:, 1), pairs(:, 2));
    matched = passes(pairIndex);
    stats.truePositives(threshId) = nnz(matched);
    stats.sumMatchedIoU(threshId) = sum(iou(pairIndex(matched)));
end
end
