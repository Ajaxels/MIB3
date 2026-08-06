function options = normalizeTimeSeries(obj, colorChannel, options)
% NORMALIZETIMESERIES - Normalize contrast across time frames.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.normalizeTimeSeries(colorChannel, options)
%
% For each color channel, computes mean and standard deviation per time
% frame (either from the currently shown 2D slice or from the full 3D
% stack), then shifts and scales each frame so that its statistics match
% the dataset-wide (or manually specified) target values.
%
% Input Arguments:
%   - **obj** - :class:`controllers.ContrastNormalization` instance.
%   - **colorChannel** - ``[1 x N]`` vector of color-channel indices to process.
%   - **options** - struct with fields:
%
%     - ``.id`` - dataset index.
%     - ``.t1`` - first time-frame index.
%     - ``.t2`` - last time-frame index.
%     - ``.currentZ`` - Z-slice index for ``'Based on current 2D slice'`` mode.
%     - ``.waitbar`` - handle to the ``uiprogressdlg``; may be ``[]``.
%     - ``.waitbarOffset`` - base progress value before this target starts.
%     - ``.totalSteps`` - total steps for the waitbar denominator.

id         = options.id;
maxZ       = obj.mibModel.I{id}.image.depth;
t1         = options.t1;
t2         = options.t2;
numFrames  = t2 - t1 + 1;

meanValsStr = '';
stdValsStr  = '';

for chIdx = 1:numel(colorChannel)
    colorCh = colorChannel(chIdx);

    % --- Collect per-frame statistics
    mean_val = zeros(t2, 1);
    std_val  = zeros(t2, 1);
    getOpt   = options;

    for t = t1:t2
        getOpt.t = [t t];
        if strcmp(obj.BatchOpt.TimeSeriesNormalization{1}, 'Based on current 2D slice')
            frameData = double(cell2mat(obj.mibModel.getData2D('image', options.currentZ, [], colorCh, getOpt)));
        else
            frameData = double(cell2mat(obj.mibModel.getData3D('image', t, [], colorCh, getOpt)));
        end
        mean_val(t) = mean(frameData(:));
        std_val(t)  = std(frameData(:));

        if ~isempty(options.waitbar)
            options.waitbar.Value = min(1, ...
                (options.waitbarOffset + (chIdx-1)*numFrames*2 + (t-t1+1)) / options.totalSteps);
        end
    end

    % --- Resolve target mean / std
    switch obj.BatchOpt.Mode{1}
        case {'Automatic', 'BasedOnSlice'}
            targetMean = mean(mean_val(t1:t2));
            targetStd  = mean(std_val(t1:t2));
        case 'Manual'
            targetMean = obj.BatchOpt.Mean{1};
            targetStd  = obj.BatchOpt.Std{1};
    end

    meanValsStr = appendStatStr(meanValsStr, targetMean);
    stdValsStr  = appendStatStr(stdValsStr,  targetStd);
    fprintf('ContrastNormalization: ColCh %d, Time series, Mean: %f, Std: %f\n', colorCh, targetMean, targetStd);

    % --- Apply normalization to each frame
    for t = t1:t2
        getOpt.t = [t t];
        ratio    = targetStd / std_val(t);
        for z = 1:maxZ
            currentImage = cell2mat(obj.mibModel.getData2D('image', z, [], colorCh, getOpt));
            shifted = (double(currentImage) - mean_val(t)) * ratio + targetMean;
            obj.mibModel.setData2D(shifted, 'image', z, [], colorCh, getOpt);
        end

        if ~isempty(options.waitbar)
            options.waitbar.Value = min(1, ...
                (options.waitbarOffset + (chIdx-1)*numFrames*2 + numFrames + (t-t1+1)) / options.totalSteps);
        end
    end
end

options.meanValsStr = meanValsStr;
options.stdValsStr  = stdValsStr;
end

function str = appendStatStr(str, value)
if isempty(str)
    str = sprintf('%.0f', value);
else
    str = sprintf('%s, %.0f', str, value);
end
end
