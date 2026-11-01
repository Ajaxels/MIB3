function options = normalizeBackground(obj, colorChannel, options)
% NORMALIZEBACKGROUND - Shift each slice based on masked background intensity.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.normalizeBackground(colorChannel, options)
%
% For each color channel, computes the per-slice mean intensity restricted to
% pixels in the mask layer (representing background regions), fills gaps where
% the mask is empty, and then shifts each slice so that its background mean
% matches a common target value.  Standard deviation is not used; only a
% shift is applied.
%
% Input Arguments:
%   - **obj** - :class:`controllers.ContrastNormalization` instance.
%   - **colorChannel** - ``[1 x N]`` vector of color-channel indices to process.
%   - **options** - struct with fields:
%
%     - ``.id`` - dataset index.
%     - ``.t`` - ``[tVal tVal]`` time-point pair.
%     - ``.waitbar`` - handle to the ``uiprogressdlg``; may be ``[]``.
%     - ``.waitbarOffset`` - base progress value before this target starts.
%     - ``.totalSteps`` - total steps for the waitbar denominator.
%     - ``.parentFig`` - parent figure for error dialogs.
%
% Output Arguments:
%   - **options** - the input struct with the action-log string
%     ``.meanValsStr`` filled in, and with:
%
%     - ``.cancelled`` - set to ``true`` when the user pressed Cancel; the
%       waitbar is polled before every slice, while collecting statistics
%       and while applying them
%     - ``.failed`` - set to ``true`` when the mask layer is empty; the error
%       has already been shown, the waitbar is left for the caller to close
%     - ``.modified`` - set to ``true`` once the first slice has been written

id        = options.id;
maxZ      = obj.mibModel.I{id}.image.depth;
parentFig = options.parentFig;

meanValsStr = '';

for chIdx = 1:numel(colorChannel)
    colorCh = colorChannel(chIdx);

    [mean_val, ~, options.cancelled] = obj.collectSliceStats(1, maxZ, options.t(1), colorCh, true, options);
    if options.cancelled; return; end

    % Fill NaN entries
    nanIds = find(isnan(mean_val));
    valIds = find(~isnan(mean_val));
    if isempty(valIds)
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf('The "%s" layer appears to be empty!\nPlease draw the mask or select the correct Mask layer.', ...
            obj.BatchOpt.MaskLayer{1}), ...
            'ContrastNormalization: empty mask');
        options.failed = true;
        return;
    end
    for i = 1:numel(nanIds)
        nextValid = find(valIds > nanIds(i), 1);
        if isempty(nextValid)
            nextValid = find(valIds < nanIds(i), 1, 'last');
        end
        mean_val(nanIds(i)) = mean_val(valIds(nextValid));
    end

    % Resolve target background mean
    switch obj.BatchOpt.Mode{1}
        case 'Automatic'
            targetMean = mean(mean_val);
        case 'BasedOnSlice'
            referenceSlice = obj.BatchOpt.ReferenceSliceNo{1};
            targetMean     = mean_val(referenceSlice);
        case 'Manual'
            targetMean = obj.BatchOpt.Mean{1};
    end

    meanValsStr = appendStatStr(meanValsStr, targetMean);
    fprintf('ContrastNormalization: ColCh %d, Background, Target mean: %f\n', colorCh, targetMean);

    getOpt   = options;
    getOpt.t = options.t;

    for z = 1:maxZ
        if ~isempty(options.waitbar) && options.waitbar.CancelRequested
            options.cancelled = true;
            return;
        end
        currentImage = cell2mat(obj.mibModel.getData2D('image', z, [], colorCh, getOpt));
        shifted = double(currentImage) - mean_val(z) + targetMean;
        obj.mibModel.setData2D(shifted, 'image', z, [], colorCh, getOpt);
        options.modified = true;

        if ~isempty(options.waitbar)
            options.waitbar.Value = min(1, ...
                (options.waitbarOffset + (chIdx-1)*maxZ + z) / options.totalSteps);
        end
    end
end

options.meanValsStr = meanValsStr;
options.stdValsStr  = '';
end

function str = appendStatStr(str, value)
if isempty(str)
    str = sprintf('%.0f', value);
else
    str = sprintf('%s, %.0f', str, value);
end
end
