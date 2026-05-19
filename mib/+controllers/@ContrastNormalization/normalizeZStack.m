function options = normalizeZStack(obj, colorChannel, options)
% NORMALIZEZSTACK - Normalize contrast across Z-slices of a single time point.
%
% Syntax:
%   .. code-block:: matlab
%
%      options = obj.normalizeZStack(colorChannel, options)
%
% For each color channel, computes the per-slice mean and standard deviation
% over the full image frame and adjusts each slice so that its mean matches
% the dataset-wide (or manually specified) mean and its spread matches the
% dataset-wide std.
%
% Input Arguments:
%   - **obj** — :class:`controllers.ContrastNormalization` instance.
%   - **colorChannel** — ``[1 x N]`` vector of color-channel indices to process.
%   - **options** — struct with fields:
%
%     - ``.id`` — dataset index.
%     - ``.t`` — ``[tVal tVal]`` time-point pair for the single frame.
%     - ``.waitbar`` — handle to the ``uiprogressdlg``; may be ``[]``.
%     - ``.waitbarOffset`` — base progress value before this target starts.
%     - ``.totalSteps`` — total number of (channel × slice) steps for the waitbar.

id   = options.id;
maxZ = obj.mibModel.I{id}.image.depth;

% Collect running strings for the action log
meanValsStr = '';
stdValsStr  = '';

for chIdx = 1:numel(colorChannel)
    colorCh = colorChannel(chIdx);

    [mean_val, std_val] = obj.collectSliceStats(1, maxZ, options.t(1), colorCh, false, options);

    % Fill NaN entries by nearest-neighbour interpolation
    [mean_val, std_val] = fillStatGaps(mean_val, std_val);
    if isempty(mean_val); continue; end  % all slices were empty

    % Resolve target mean / std
    switch obj.BatchOpt.Mode{1}
        case 'Automatic'
            validIds = ~isnan(mean_val);
            targetMean = mean(mean_val(validIds));
            targetStd  = mean(std_val(validIds));
        case 'BasedOnSlice'
            referenceSlice = obj.BatchOpt.ReferenceSliceNo{1};
            targetMean = mean_val(referenceSlice);
            targetStd  = std_val(referenceSlice);
        case 'Manual'
            targetMean = obj.BatchOpt.Mean{1};
            targetStd  = obj.BatchOpt.Std{1};
    end

    meanValsStr = appendStatStr(meanValsStr, targetMean);
    stdValsStr  = appendStatStr(stdValsStr,  targetStd);
    fprintf('ContrastNormalization: ColCh %d, Z stack, Mean: %f, Std: %f\n', colorCh, targetMean, targetStd);

    % Determine the exclusion mask for applying normalization
    switch obj.BatchOpt.Exculude{1}
        case 'Whole range';   outliers = [];
        case 'Excude blacks'; outliers = 0;
        case 'Excude whites'; outliers = obj.mibModel.I{id}.image.maxInt;
    end

    getOpt   = options;
    getOpt.t = options.t;

    for z = 1:maxZ
        currentImage = cell2mat(obj.mibModel.getData2D('image', z, [], colorCh, getOpt));
        ratio  = targetStd / std_val(z);
        shifted = double(currentImage) - mean_val(z);
        shifted = shifted * ratio;

        if isempty(outliers)
            currentImage = shifted + targetMean;
        elseif outliers == 0
            mask = double(currentImage) > 0;
            currentImage = double(currentImage);
            currentImage(mask) = shifted(mask) + targetMean;
        else
            mask = double(currentImage) < outliers;
            currentImage = double(currentImage);
            currentImage(mask) = shifted(mask) + targetMean;
        end

        obj.mibModel.setData2D(currentImage, 'image', z, [], colorCh, getOpt);

        if ~isempty(options.waitbar)
            options.waitbar.Value = min(1, ...
                (options.waitbarOffset + (chIdx-1)*maxZ + z) / options.totalSteps);
        end
    end
end

options.meanValsStr = meanValsStr;
options.stdValsStr  = stdValsStr;
end

% ---- Local helpers --------------------------------------------------------

function [meanOut, stdOut] = fillStatGaps(meanIn, stdIn)
% Fill NaN entries using nearest non-NaN neighbours.
meanOut = meanIn;
stdOut  = stdIn;
nanIds  = find(isnan(meanIn));
valIds  = find(~isnan(meanIn));
if isempty(valIds)
    meanOut = [];
    stdOut  = [];
    return;
end
for i = 1:numel(nanIds)
    nextValid = find(valIds > nanIds(i), 1);
    if isempty(nextValid)
        nextValid = find(valIds < nanIds(i), 1, 'last');
    end
    meanOut(nanIds(i)) = meanIn(valIds(nextValid));
    stdOut(nanIds(i))  = stdIn(valIds(nextValid));
end
end

function str = appendStatStr(str, value)
if isempty(str)
    str = sprintf('%.0f', value);
else
    str = sprintf('%s, %.0f', str, value);
end
end
