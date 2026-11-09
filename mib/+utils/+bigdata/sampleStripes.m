function [sums, info] = sampleStripes(image, level, reduceFunction, options)
% SAMPLESTRIPES - Sum a statistic over evenly spaced stripes of rows of every slice of a pyramid level.
%
% Syntax:
%   .. code-block:: matlab
%
%       [sums, info] = utils.bigdata.sampleStripes(image, level, reduceFunction)
%       [sums, info] = utils.bigdata.sampleStripes(..., SampleBytes = 64e6, ColChannel = 1, ...)
%
% The statistics pass of the BigData Image tools whose parameters depend on the
% whole image (a threshold, a normalization). Reading the whole level for them
% would cost as much as the processing itself, which on a whole-slide image is
% many gigabytes, so only a sample of it is read: **stripes** of rows across
% the full width, spread evenly over the height of every slice. The rows of
% each stripe are passed to ``reduceFunction``, and its outputs are summed per
% slice. A sum of counts, values or squares gives histograms, means and
% variances; the caller derives its parameters from them.
%
% **Which rows.** A stripe is one **chunk row**: the chunk height of the level
% in the store (256 rows when the reader does not report one, as for vendor
% files) across the full width. A store decodes whole chunks, so a lower
% stripe would cost the same reading time for less sample; the cost of a pass
% is what matters on a dataset of many gigabytes. The budget ``SampleBytes``
% (of image data read, before any ``BlockFunction``) is shared equally by the
% slices and buys whole chunk rows, evenly spaced over the height:
%
% - when it covers the whole level, every row is read and the statistics are
%   exact (``info.exact``);
% - at least ``MinimumStripes`` stripes are read in total, shared by the
%   slices and at least one per slice, so the sample of a slice spreads over
%   its height: 16 stripes of a whole-slide image, one stripe of each slice
%   of a deep stack. This can exceed the budget; ``info.fractionRead``
%   reports the share of the level actually read.
%
% The stripes are at the same rows in every slice and the slices are read in
% order, so a chunk spanning several slices is decoded once and then served by
% ``io.zarr.ChunkCache``. The positions do not depend on the data, so a run
% on the same dataset and budget reads the same rows.
%
% **Halo.** With ``BlockFunction`` (e.g. a gradient) each stripe is read with
% ``HaloYX`` rows above and below through ``io.savers.FilteredSliceProvider``,
% processed, and cropped back to the stripe, so the function sees the same
% neighbourhood as on the whole slice. ``reduceFunction`` then receives the
% processed rows.
%
% Input Arguments:
%   - **image** - ``core.MibBigDataImage`` (an image with a ``pyramid`` that
%     honours ``getData`` ``pyramidLevel``)
%   - **level** - [double] 1-based pyramid level (1 = full resolution)
%   - **reduceFunction** - function handle ``value = f(rows)``: ``rows`` is
%     ``[stripeRows width channels]`` of the image class (or the output of
%     ``BlockFunction``); ``value`` is a numeric array of the same size for
%     every call, summed per slice. Sum in double to avoid integer saturation
%   - **options.ColChannel** - colour channels to read, default ``[]`` (all)
%   - **options.BlockFunction** - function handle applied to each stripe with
%     its halo before ``reduceFunction``, contract as in
%     ``io.savers.FilteredSliceProvider``; default ``[]`` (the rows as read)
%   - **options.HaloYX** - [double] rows of halo for ``BlockFunction``, default 0
%   - **options.SampleBytes** - [double] budget of image data read, default 256e6
%   - **options.MinimumStripes** - [double] stripes read in total at least, default 16
%   - **options.Slices** - [double] level slices to sample, default ``[]`` (all);
%     the budget is shared by these slices only, and the other entries of
%     ``sums`` stay ``[]`` (a 2D tool samples the shown slice alone)
%   - **options.ParentFigure** - figure for a cancelable progress dialog,
%     default ``[]`` (no dialog)
%   - **options.Title** - [char] title of the progress dialog
%
% Output Arguments:
%   - **sums** - {1 x depth} cell, the sum of ``reduceFunction`` over the
%     stripes of each slice of the level, ``[]`` for a slice not in
%     ``Slices``; ``[]`` when cancelled
%   - **info** - struct: ``level``, ``exact`` [logical], ``stripeHeight``,
%     ``stripesPerSlice``, ``rowsRead`` and ``rowsTotal`` (over the sampled slices),
%     ``fractionRead``; ``[]`` when cancelled
%
% **Example** - mean intensity of every slice of level 2 from a 64 MB sample:
%
%   .. code-block:: matlab
%
%      image = mibModel.I{mibModel.getActiveId()}.image;
%      sums = utils.bigdata.sampleStripes(image, 2, @(rows) [sum(rows(:), 'double'); numel(rows)], ...
%          SampleBytes = 64e6);
%      sliceMeans = cellfun(@(s) s(1) / s(2), sums);
%
% See also: utils.bigdata.sliceHistograms, io.savers.FilteredSliceProvider,
% io.zarr.ChunkCache

arguments
    image
    level (1,1) double {mustBeInteger, mustBePositive}
    reduceFunction (1,1) function_handle
    options.ColChannel = []
    options.BlockFunction = []
    options.HaloYX (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    options.SampleBytes (1,1) double {mustBePositive} = 256e6
    options.MinimumStripes (1,1) double {mustBeInteger, mustBePositive} = 16
    options.Slices double {mustBeInteger, mustBePositive} = []
    options.ParentFigure = []
    options.Title (1,:) char = 'Sampling the image'
end
sums = [];
pyramid = image.pyramid;
if level > size(pyramid.levelImageSizes, 1)
    error('utils:bigdata:wrongLevel', 'Level %d requested, the image has %d pyramid levels.', ...
        level, size(pyramid.levelImageSizes, 1));
end
levelSize = pyramid.levelImageSizes(level, :);    % [Y X Z]
height = levelSize(1);
width = levelSize(2);
depth = levelSize(3);
slices = options.Slices(:)';
if isempty(slices); slices = 1:depth; end
if any(slices > depth)
    error('utils:bigdata:wrongSlice', 'Slice %d requested, level %d has %d slices.', max(slices), level, depth);
end
sampledCount = numel(slices);
channelCount = numel(options.ColChannel);
if channelCount == 0; channelCount = image.colors; end
bytesPerRow = width * channelCount * numel(typecast(zeros(1, image.dataClass), 'uint8'));

% stripe layout, the same for every slice
chunkRows = 256;
if isfield(pyramid, 'chunkSizes') && numel(pyramid.chunkSizes) >= level && ~isempty(pyramid.chunkSizes{level})
    % the chunk vector is in the store's axis order ('tczyx'...)
    axisOrder = 'yxz';
    if isfield(pyramid, 'axisOrder') && ~isempty(pyramid.axisOrder); axisOrder = char(pyramid.axisOrder); end
    yIndex = strfind(axisOrder, 'y');
    if ~isempty(yIndex) && yIndex <= numel(pyramid.chunkSizes{level})
        chunkRows = double(pyramid.chunkSizes{level}(yIndex));
    end
end
stripeHeight = min(chunkRows, height);
chunkRowCount = ceil(height / stripeHeight);
chunkRowsInBudget = floor(options.SampleBytes / (bytesPerRow * stripeHeight * sampledCount));
minimumPerSlice = min(chunkRowCount, max(1, ceil(options.MinimumStripes / sampledCount)));
stripeCount = min(chunkRowCount, max(minimumPerSlice, chunkRowsInBudget));
chunkIndices = unique(floor(((0:stripeCount - 1) + 0.5) * chunkRowCount / stripeCount));   % 0-based
stripeFirst = chunkIndices * stripeHeight + 1;
stripeLast = min(stripeFirst + stripeHeight - 1, height);
stripeCount = numel(stripeFirst);

% a stripe is read in pieces of at most this many rows, so a wide level with
% tall chunks does not need a stripe-sized copy in double
pieceRows = max(1, floor(64e6 / (8 * width * channelCount)));

blockFunction = options.BlockFunction;
if isempty(blockFunction); blockFunction = @(block) block; end
provider = io.savers.FilteredSliceProvider(image, level, options.ColChannel, blockFunction, ...
    HaloYX = options.HaloYX);

progressDialog = [];
if ~isempty(options.ParentFigure) && isvalid(options.ParentFigure)
    progressDialog = uiprogressdlg(options.ParentFigure, 'Title', options.Title, 'Cancelable', 'on', ...
        'Message', sprintf('Level s%d: %d stripes of %d rows in each of %d slices', ...
        level - 1, stripeCount, stripeHeight, sampledCount));
    cleanupDialog = onCleanup(@() delete(progressDialog));
end

sliceSums = cell(1, depth);
for sliceIndex = 1:sampledCount
    z = slices(sliceIndex);
    for stripeIndex = 1:stripeCount
        if ~isempty(progressDialog)
            if progressDialog.CancelRequested; info = []; return; end
            progressDialog.Value = ((sliceIndex - 1) * stripeCount + stripeIndex - 1) / (sampledCount * stripeCount);
        end
        for pieceFirst = stripeFirst(stripeIndex):pieceRows:stripeLast(stripeIndex)
            pieceLast = min(pieceFirst + pieceRows - 1, stripeLast(stripeIndex));
            value = reduceFunction(provider.getSliceRows(z, pieceFirst, pieceLast));
            if isempty(sliceSums{z})
                sliceSums{z} = value;
            else
                sliceSums{z} = sliceSums{z} + value;
            end
        end
    end
end
sums = sliceSums;

rowsRead = sum(stripeLast - stripeFirst + 1) * sampledCount;
info = struct('level', level, 'exact', rowsRead == height * sampledCount, 'stripeHeight', stripeHeight, ...
    'stripesPerSlice', stripeCount, 'rowsRead', rowsRead, 'rowsTotal', height * sampledCount, ...
    'fractionRead', rowsRead / (height * sampledCount));
end
