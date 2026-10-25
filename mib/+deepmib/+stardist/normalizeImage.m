function [normalized, lowValues, highValues] = normalizeImage(img, percentiles)
% NORMALIZEIMAGE - Percentile normalisation of an image for StarDist, per channel, in single precision.
%
% Syntax:
%   .. code-block:: matlab
%
%      normalized = deepmib.stardist.normalizeImage(img)
%      [normalized, lowValues, highValues] = deepmib.stardist.normalizeImage(img, percentiles)
%
% Computes, for every channel separately, ``(img - pLow) / (pHigh - pLow + 1e-20)`` without
% clipping, as csbdeep ``normalize(img, pLow, pHigh, axis=(0,1))``, which is how StarDist
% models expect their input. Values below the low percentile become negative and values above
% the high percentile exceed 1.
%
% The percentiles follow numpy's default definition (linear interpolation between the order
% statistics at 0-based position ``(n-1) * p/100``). MATLAB ``prctile`` uses a different
% definition and would shift the normalisation slightly against the pretrained models.
% For 8- and 16-bit integer images the order statistics are read from a histogram, which is
% exact and avoids sorting the whole image; other types are sorted.
%
% Input Arguments:
%   - **img** - [numeric] image ``[height, width]`` or ``[height, width, colors]``
%   - **percentiles** *(optional)* - [1x2 numeric] lower and upper percentile
%     (default: ``[1 99.8]``)
%
% Output Arguments:
%   - **normalized** - [single] normalised image, same size as **img**
%   - **lowValues** - [1xC single] low percentile of each channel
%   - **highValues** - [1xC single] high percentile of each channel

if nargin < 2; percentiles = [1 99.8]; end

nChannels = size(img, 3);
normalized = zeros(size(img), 'single');
lowValues = zeros(1, nChannels, 'single');
highValues = zeros(1, nChannels, 'single');
for channelId = 1:nChannels
    channel = img(:, :, channelId);
    values = single(numpyPercentiles(channel(:), percentiles));
    lowValues(channelId) = values(1);
    highValues(channelId) = values(2);
    normalized(:, :, channelId) = (single(channel) - values(1)) / (values(2) - values(1) + single(1e-20));
end
end

function values = numpyPercentiles(data, percentiles)
% numpy 'linear' method: position (n-1)*p/100 in the 0-based sorted data
n = numel(data);
position = (n - 1) * percentiles(:) / 100;
lowerRank = floor(position) + 1;                   % 1-based order statistics
upperRank = min(lowerRank + 1, n);
fraction = position - floor(position);
lowerValue = orderStatistics(data, lowerRank);
upperValue = orderStatistics(data, upperRank);
values = lowerValue + fraction .* (upperValue - lowerValue);
end

function values = orderStatistics(data, ranks)
% k-th smallest values; histogram for 8/16-bit integers, sorting otherwise
switch class(data)
    case {'uint8', 'uint16', 'int8', 'int16'}
        offset = double(intmin(class(data)));
        nBins = double(intmax(class(data))) - offset + 1;
        counts = accumarray(double(data) - offset + 1, 1, [nBins 1]);
        cumulative = cumsum(counts);
        values = zeros(size(ranks));
        for rankId = 1:numel(ranks)
            values(rankId) = find(cumulative >= ranks(rankId), 1) - 1 + offset;
        end
    otherwise
        sorted = sort(double(data));
        values = sorted(ranks);
end
end
