function [mean_val, std_val] = collectSliceStats(obj, z1, z2, t, colorCh, useMask, options)
% COLLECTSLICESTATS - Compute per-slice mean and std for one color channel.
%
% Syntax:
%   .. code-block:: matlab
%
%      [mean_val, std_val] = obj.collectSliceStats(z1, z2, t, colorCh, useMask, options)
%
% Iterates over slices ``z1:z2`` at time point ``t`` and computes mean and
% standard deviation of pixel intensities.  When ``useMask`` is ``true``,
% statistics are restricted to the pixels flagged by ``obj.BatchOpt.MaskLayer``
% (``'selection'`` or ``'mask'``).  Slices where the mask is empty return
% ``NaN``; the caller is responsible for gap-filling.
%
% Input Arguments:
%   - **obj** - :class:`controllers.ContrastNormalization` instance.
%   - **z1** - first slice index (1-based).
%   - **z2** - last slice index (1-based).
%   - **t** - time-point index.
%   - **colorCh** - scalar color-channel index.
%   - **useMask** - logical; ``true`` to restrict stats to the mask layer.
%   - **options** - struct passed to ``getData2D``; must contain ``.id``.
%
% Output Arguments:
%   - **mean_val** - ``[maxZ x 1]`` double vector; ``NaN`` for empty-mask slices.
%   - **std_val** - ``[maxZ x 1]`` double vector; ``NaN`` for empty-mask slices.

maxZ    = obj.mibModel.I{options.id}.image.depth;
getOpt  = options;
getOpt.t = [t t];

mean_val = zeros(maxZ, 1);
std_val  = zeros(maxZ, 1);

% Determine the exclusion value (0 = black, maxInt = white, empty = none)
switch obj.BatchOpt.Exculude{1}
    case 'Whole range';   outliers = [];
    case 'Excude blacks'; outliers = 0;
    case 'Excude whites'; outliers = obj.mibModel.I{options.id}.image.maxInt;
end

for z = z1:z2
    currentImage = cell2mat(obj.mibModel.getData2D('image', z, [], colorCh, getOpt));

    if useMask
        maskSlice = cell2mat(obj.mibModel.getData2D(obj.BatchOpt.MaskLayer{1}, z, [], colorCh, getOpt));
        if max(maskSlice(:)) == 0
            mean_val(z) = NaN;
            std_val(z)  = NaN;
            continue;
        end
        pixelValues = double(currentImage(maskSlice == 1));
    else
        if isempty(outliers)
            pixelValues = double(currentImage(:));
        elseif outliers == 0
            pixelValues = double(currentImage(currentImage > 0));
        else
            pixelValues = double(currentImage(currentImage < outliers));
        end
    end

    if isempty(pixelValues)
        mean_val(z) = NaN;
        std_val(z)  = NaN;
    else
        mean_val(z) = mean(pixelValues);
        std_val(z)  = std(pixelValues);
    end
end
end
