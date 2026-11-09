function normalizeBigData(obj, colorChannel, parentFig)
% NORMALIZEBIGDATA - Normalize the slices of a BigData dataset into a new OME-Zarr store.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.normalizeBigData(colorChannel, parentFig)
%
% The *Z stack* normalization of ``normalizeZStack`` for a BigData dataset,
% whose image is read-only and does not fit in memory. Two passes over the
% level ``BatchOpt.BigData_PyramidLevel``:
%
% 1. **Statistics** - the histogram of each selected channel in every slice
%    from evenly spaced stripes of rows (``utils.bigdata.sliceHistograms``,
%    256 MB of image data by default; exact when the level fits). The mean and
%    standard deviation of each slice follow from it, with the black (0) or
%    white (``maxInt``) pixels left out as ``Exculude`` says. A slice with no
%    pixel left takes the values of the next slice that has some, else of the
%    previous one, as in ``normalizeZStack``.
% 2. **Normalization** - every band of rows is shifted and scaled
%    (``(value - sliceMean) * targetStd / sliceStd + targetMean``, the excluded
%    pixels unchanged) and written to a new store, opened as ``BigData_OpenIn``
%    says (``controllers.BigDataOptions.run``). The other channels are copied.
%
% The targets follow ``Mode``: *Automatic* - the mean of the slice means and of
% the slice standard deviations; *BasedOnSlice* - the values of
% ``ReferenceSliceNo``, a full-resolution slice number mapped to the level;
% *Manual* - ``Mean`` and ``Std``.
%
% Only *Z stack*: *Masked area* and *Background* need the mask band by band,
% and a BigData dataset has one time point. Errors are shown in a dialog, or
% raised as ``controllers:ContrastNormalization:bigData`` when headless.
%
% Input Arguments:
%   - **obj** - :class:`controllers.ContrastNormalization` instance; ``BatchOpt.id``
%     is the dataset
%   - **colorChannel** - ``[1 x N]`` channels to normalize
%   - **parentFig** - window for the dialogs, ``[]`` when headless

errorId = 'controllers:ContrastNormalization:bigData';
title = 'Contrast normalization';
BatchOpt = obj.BatchOpt;
dataset = obj.mibModel.I{BatchOpt.id};
if ~strcmp(BatchOpt.Target{1}, 'Z stack')
    controllers.BigDataOptions.reportError(obj.mibModel, parentFig, errorId, sprintf( ...
        'On a BigData dataset only the "Z stack" normalization is available; "%s" is not.', BatchOpt.Target{1}), title);
    return;
end
if ~ismember(dataset.image.dataClass, {'uint8', 'uint16'})
    controllers.BigDataOptions.reportError(obj.mibModel, parentFig, errorId, sprintf( ...
        'Normalization of a BigData dataset needs a uint8 or uint16 image; this one is %s.', ...
        dataset.image.dataClass), title);
    return;
end
try
    level = obj.bigDataOptions.resolveLevel(BatchOpt);
catch err
    controllers.BigDataOptions.reportError(obj.mibModel, parentFig, errorId, err.message, title);
    return;
end

% asked before the histogram pass; the probe of the time copies the band, as
% cheap as the linear mapping of the run
if ~obj.bigDataOptions.confirmRun(BatchOpt, @(block) block, Note = ['A pass over a sample of rows of ' ...
        'every slice comes first, for the histograms; it is not in the estimate.'])
    notify(obj.mibModel, 'StopProtocol');
    return;
end
progressParent = [];
if ~isempty(obj.view) && isvalid(obj.view.gui); progressParent = obj.view.gui; end
[counts, info] = utils.bigdata.sliceHistograms(dataset.image, level, ColChannel = colorChannel, ...
    ParentFigure = progressParent);
if isempty(counts)      % cancelled while collecting; nothing written
    notify(obj.mibModel, 'StopProtocol');
    return;
end

maxInt = double(dataset.image.maxInt);
values = (0:size(counts, 1) - 1)';
switch BatchOpt.Exculude{1}
    case 'Excude blacks'; counts(1, :, :) = 0;
    case 'Excude whites'; counts(maxInt + 1, :, :) = 0;
end
% [1 channels depth] while the counts are summed, then [channels depth]
pixelCount = sum(counts, 1);
sliceMean = sum(counts .* values, 1) ./ pixelCount;
sliceStd = sqrt(sum(counts .* (values - sliceMean).^2, 1) ./ (pixelCount - 1));   % normalized by n-1, as std
depth = size(counts, 3);
pixelCount = reshape(pixelCount, numel(colorChannel), depth);
sliceMean = reshape(sliceMean, numel(colorChannel), depth);
sliceStd = reshape(sliceStd, numel(colorChannel), depth);
sliceMean(pixelCount == 0) = NaN;
sliceStd(pixelCount == 0) = NaN;
if all(isnan(sliceMean), 'all')
    controllers.BigDataOptions.reportError(obj.mibModel, parentFig, errorId, ...
        'No pixels are left for the statistics after excluding the blacks or whites.', title);
    return;
end
% an empty slice takes the values of the next slice with pixels, else of the previous one
sliceMean = fillmissing(fillmissing(sliceMean, 'next', 2), 'previous', 2);
sliceStd = fillmissing(fillmissing(sliceStd, 'next', 2), 'previous', 2);

switch BatchOpt.Mode{1}
    case 'Automatic'
        targetMean = mean(sliceMean, 2);
        targetStd = mean(sliceStd, 2);
    case 'BasedOnSlice'
        scaleZ = dataset.image.pyramid.levelScaleFactors(level, 3);
        referenceSlice = min(size(sliceMean, 2), ceil(BatchOpt.ReferenceSliceNo{1} / scaleZ));
        targetMean = sliceMean(:, referenceSlice);
        targetStd = sliceStd(:, referenceSlice);
    case 'Manual'
        targetMean = repmat(BatchOpt.Mean{1}, numel(colorChannel), 1);
        targetStd = repmat(BatchOpt.Std{1}, numel(colorChannel), 1);
end

normalization = struct('channels', colorChannel, 'sliceMean', sliceMean, 'sliceStd', sliceStd, ...
    'targetMean', targetMean, 'targetStd', targetStd, 'exclude', BatchOpt.Exculude{1}, 'maxInt', maxInt);
blockFunction = @(block, z) localNormalizeBand(block, z, normalization);
try
    result = obj.bigDataOptions.run(BatchOpt, blockFunction, Fingerprint = jsonencode(normalization), Confirmed = true);
catch err
    controllers.BigDataOptions.reportError(obj.mibModel, parentFig, errorId, ...
        sprintf('Normalization of the BigData dataset failed:\n%s', err.message), title);
    return;
end
if isempty(result)      % cancelled; nothing is left on disk
    notify(obj.mibModel, 'StopProtocol');
    return;
end

obj.bigDataOptions.reportStoreResult(result, sprintf( ...
    'ContrastNorm: Z stack, Mode: %s, Ch: %s, Mean: %s, Std: %s; level %s, statistics from %.1f%% of the level -> %s', ...
    BatchOpt.Mode{1}, num2str(colorChannel), num2str(targetMean', '%.0f '), num2str(targetStd', '%.0f '), ...
    BatchOpt.BigData_PyramidLevel{1}, 100 * info.fractionRead, result.outputPath));
obj.mibModel.preferences.Users.Tiers.numberOfContrastAdjustments = obj.mibModel.preferences.Users.Tiers.numberOfContrastAdjustments + 1;
notify(obj.mibModel, 'UpdateUserScore', core.ToggleEventData(2));
obj.returnBatchOpt(BatchOpt);
end

% ---------------------------------------------------------------------------
function out = localNormalizeBand(block, z, normalization)
% LOCALNORMALIZEBAND - Normalize the channels of one band ``[rows width colors]`` of level slice ``z``.
% The arithmetic of normalizeZStack: in double, the excluded pixels unchanged,
% then rounded and saturated to the class of the image.
out = block;
for channelIndex = 1:numel(normalization.channels)
    channel = normalization.channels(channelIndex);
    values = double(block(:, :, channel));
    shifted = (values - normalization.sliceMean(channelIndex, z)) * ...
        (normalization.targetStd(channelIndex) / normalization.sliceStd(channelIndex, z)) + ...
        normalization.targetMean(channelIndex);
    switch normalization.exclude
        case 'Excude blacks'
            keep = values > 0;
            shifted(~keep) = values(~keep);
        case 'Excude whites'
            keep = values < normalization.maxInt;
            shifted(~keep) = values(~keep);
    end
    out(:, :, channel) = cast(shifted, class(block));
end
end
