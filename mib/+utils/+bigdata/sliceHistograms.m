function [counts, info] = sliceHistograms(image, level, options)
% SLICEHISTOGRAMS - Histogram of every intensity value, per slice and channel, of a pyramid level of a BigData image.
%
% Syntax:
%   .. code-block:: matlab
%
%       [counts, info] = utils.bigdata.sliceHistograms(image, level)
%       [counts, info] = utils.bigdata.sliceHistograms(image, level, ColChannel = 2, SampleBytes = 64e6)
%
% The statistics of the global-statistics Image tools on BigData: a threshold
% (Otsu, the HistThresh algorithms, a percentile), a mean and standard
% deviation, a minimum and maximum all follow from the histogram of intensity
% values. One bin per value of the class (256 for ``uint8``, 65536 for
% ``uint16``), so nothing is lost to binning and each tool bins further as its
% Standard version does. The rows are sampled by
% ``utils.bigdata.sampleStripes`` (see there for which rows are read and when
% the result is exact); a statistic from a sample is an estimate of the
% statistic of the whole slice.
%
% Input Arguments:
%   - **image** - ``core.MibBigDataImage`` of class ``uint8`` or ``uint16``
%   - **level** - [double] 1-based pyramid level
%   - **options.ColChannel** - colour channels, default ``[]`` (all)
%   - **options.SampleBytes** - [double] budget of image data read, default 256e6
%   - **options.ParentFigure** - figure for a cancelable progress dialog, default ``[]``
%   - **options.Slices** - [double] level slices to sample, default ``[]`` (all)
%
% Output Arguments:
%   - **counts** - ``[bins channels depth]`` double, ``counts(v+1, c, z)`` is the
%     number of sampled pixels of value ``v`` in channel ``c`` of level slice
%     ``z``, zeros for a slice not in ``Slices``; ``[]`` when cancelled
%   - **info** - struct of ``utils.bigdata.sampleStripes``; ``[]`` when cancelled
%
% **Example** - mean of channel 1 in every slice of level 1:
%
%   .. code-block:: matlab
%
%      counts = utils.bigdata.sliceHistograms(image, 1, ColChannel = 1);
%      values = (0:size(counts, 1) - 1)';
%      sliceMeans = squeeze(sum(counts .* values, 1) ./ sum(counts, 1));
%
% See also: utils.bigdata.sampleStripes

arguments
    image
    level (1,1) double {mustBeInteger, mustBePositive}
    options.ColChannel = []
    options.SampleBytes (1,1) double {mustBePositive} = 256e6
    options.ParentFigure = []
    options.Slices double {mustBeInteger, mustBePositive} = []
end
switch image.dataClass
    case 'uint8';  binCount = 256;
    case 'uint16'; binCount = 65536;
    otherwise
        error('utils:bigdata:histogramClass', ...
            'A histogram of every value needs a uint8 or uint16 image; this image is %s.', image.dataClass);
end
[sums, info] = utils.bigdata.sampleStripes(image, level, @(rows) localCounts(rows, binCount), ...
    ColChannel = options.ColChannel, SampleBytes = options.SampleBytes, ...
    ParentFigure = options.ParentFigure, Title = 'Collecting the statistics', Slices = options.Slices);
if isempty(sums); counts = []; return; end
sampled = find(~cellfun(@isempty, sums), 1);
[sums{cellfun(@isempty, sums)}] = deal(zeros(size(sums{sampled})));   % slices not in Slices
counts = cat(3, sums{:});
end

% ---------------------------------------------------------------------------
function counts = localCounts(rows, binCount)
% LOCALCOUNTS - [bins channels] counts of every value in each channel of the rows.
channelCount = size(rows, 3);
counts = zeros(binCount, channelCount);
for channel = 1:channelCount
    values = rows(:, :, channel);
    counts(:, channel) = accumarray(double(values(:)) + 1, 1, [binCount 1]);
end
end
