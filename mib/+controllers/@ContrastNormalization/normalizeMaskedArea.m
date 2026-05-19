function options = normalizeMaskedArea(obj, colorChannel, options)
% NORMALIZEMASKEDAREA - Normalize contrast using per-slice masked-area statistics.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.normalizeMaskedArea(colorChannel, options)
%
% For each color channel, computes the per-slice mean and standard deviation
% restricted to pixels in the mask layer, fills any gaps where the mask is
% empty, then shifts and scales each slice to match a common target mean and std.
%
% Input Arguments:
%   - **obj** — :class:`controllers.ContrastNormalization` instance.
%   - **colorChannel** — ``[1 x N]`` vector of color-channel indices to process.
%   - **options** — struct with fields:
%
%     - ``.id`` — dataset index.
%     - ``.t`` — ``[tVal tVal]`` time-point pair.
%     - ``.waitbar`` — handle to the ``uiprogressdlg``; may be ``[]``.
%     - ``.waitbarOffset`` — base progress value before this target starts.
%     - ``.totalSteps`` — total steps for the waitbar denominator.
%     - ``.parentFig`` — parent figure for error dialogs.

id       = options.id;
maxZ     = obj.mibModel.I{id}.image.depth;
parentFig = options.parentFig;

meanValsStr = '';
stdValsStr  = '';

for chIdx = 1:numel(colorChannel)
    colorCh = colorChannel(chIdx);

    [mean_val, std_val] = obj.collectSliceStats(1, maxZ, options.t(1), colorCh, true, options);

    % Fill NaN entries
    nanIds = find(isnan(mean_val));
    valIds = find(~isnan(mean_val));
    if isempty(valIds)
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf('The "%s" layer appears to be empty!\nPlease draw the mask or select the correct Mask layer.', ...
            obj.BatchOpt.MaskLayer{1}), ...
            'ContrastNormalization: empty mask');
        if ~isempty(options.waitbar); close(options.waitbar); end
        return;
    end
    for i = 1:numel(nanIds)
        nextValid = find(valIds > nanIds(i), 1);
        if isempty(nextValid)
            nextValid = find(valIds < nanIds(i), 1, 'last');
        end
        mean_val(nanIds(i)) = mean_val(valIds(nextValid));
        std_val(nanIds(i))  = std_val(valIds(nextValid));
    end

    % Resolve target mean / std
    switch obj.BatchOpt.Mode{1}
        case 'Automatic'
            targetMean = mean(mean_val);
            targetStd  = mean(std_val);
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
    fprintf('ContrastNormalization: ColCh %d, Masked area, Mean: %f, Std: %f\n', colorCh, targetMean, targetStd);

    getOpt   = options;
    getOpt.t = options.t;

    for z = 1:maxZ
        ratio = targetStd / std_val(z);
        currentImage = cell2mat(obj.mibModel.getData2D('image', z, [], colorCh, getOpt));
        shifted = (double(currentImage) - mean_val(z)) * ratio + targetMean;
        obj.mibModel.setData2D(shifted, 'image', z, [], colorCh, getOpt);

        if ~isempty(options.waitbar)
            options.waitbar.Value = min(1, ...
                (options.waitbarOffset + (chIdx-1)*maxZ + z) / options.totalSteps);
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
