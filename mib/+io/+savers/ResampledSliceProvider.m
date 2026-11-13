classdef ResampledSliceProvider < io.savers.SliceProvider
% RESAMPLEDSLICEPROVIDER - SliceProvider that streams one pyramid level of a BigData image resampled to another size.
%
% The Resample tool on a BigData dataset (``controllers.ResampleDataset``):
% level ``Level`` of an image is resampled to ``[height width depth]`` and
% returned in bands of output rows, so a whole-slide image is resampled while
% only the source rows of one band are held in memory. Fed to
% ``io.savers.Zarr3Saver.saveStreamResumable`` with ``BandHeight`` (through
% ``utils.bigdata.processImageToStore``) it writes the result as a new
% pyramid; ``controllers.BigDataOptions`` also reads it into memory.
%
% **The same result as Standard.** Standard Resample with the ``imresize``
% function calls ``imresize3`` (or ``imresize`` for one slice), which is
% separable: the volume is resized along one axis at a time, the axis with the
% smallest scale (the strongest shrink) first, each pass rounded to the class
% of the image. Each output pixel of a pass is a weighted sum of the input
% pixels under its kernel, at positions fixed by the whole axis (``u = x /
% scale + 0.5 * (1 - 1 / scale)``, the kernel widened by ``1 / scale`` when
% shrinking, the edges mirrored). This class builds those weights for the
% whole axis once (``imresize``'s contributions, sparse) and applies the rows
% of them that a band needs, in the same order and with the same rounding, so
% a band equals the matching rows of the whole result. Measured 2026-11-13
% against ``imresize3`` / ``imresize`` on uint8 volumes: nearest is equal,
% the other kernels differ by at most 1 grey level on under 0.1 % of the
% voxels (a value on a rounding tie, summed in another order than the
% ``imresize`` MEX sums it); without the rounding after each pass cubic was
% up to 29 off.
%
% **Pooling** (``'max pooling'``, ``'min pooling'``) follows
% ``utils.resizeImage3d``: output voxel ``j`` of an axis covers the input
% interval ``[(j-1)*N/n, j*N/n]`` (an enlarged axis takes its nearest
% voxel), and max / min is taken over the voxels it overlaps. It is exact in
% bands, keeps the class and creates no new value.
%
% Methods: ``'nearest'``, ``'linear'`` (``'bilinear'``, ``'triangle'``: the
% same kernel), ``'cubic'`` (``'bicubic'``), ``'box'``, ``'lanczos2'``,
% ``'lanczos3'``, ``'max pooling'``, ``'min pooling'``. Not offered: the
% ``interpn`` and ``tformarray`` functions and ``'spline'``, whose value at
% a point depends on the whole axis, and ``'osc'``.
%
% **Cost.** A band of output rows reads the source rows under the kernel of
% those rows across the full width of the level (``bandRows`` sizes it).
% An output slice reads the source slices under its Z kernel, so with a
% resampled Z each source slice is read by several output slices (about 4
% for cubic, 2 for linear, whatever the factor); the chunk cache serves the
% repeats.
%
% **Parallel writing.** As ``io.savers.FilteredSliceProvider``: the image
% handle is ``Transient``, and the first read on a pool worker opens the store
% again from its path.
%
% See also: io.savers.FilteredSliceProvider, utils.bigdata.processImageToStore,
% utils.resizeImage3d, controllers.BigDataOptions
%
% **Example** - level s1 of a BigData image at half its size, first 100 rows of slice 1:
%
%   .. code-block:: matlab
%
%      img = mibModel.I{mibModel.getActiveId()}.image;   % core.MibBigDataImage
%      levelSize = img.pyramid.levelImageSizes(2, :);
%      provider = io.savers.ResampledSliceProvider(img, 2, [], ...
%          [round(levelSize(1:2) / 2), levelSize(3)], 'cubic');
%      rows = provider.getSliceRows(1, 1, 100);

    properties
        SupportsRowReads = true   % getSliceRows returns rows identical to getSlice
    end

    properties (SetAccess = private)
        Level  (1,1) double = 1           % 1-based pyramid level that is read
        Method (1,:) char = 'cubic'       % resampling method, see the class help
        LevelSize (1,3) double = [1 1 1]  % [height width depth] of the level that is read
        VoxelScaleYXZ (1,3) double = [1 1 1]   % level voxels per output voxel, [y x z]: the output voxel size is the level's times this
    end

    properties (Access = private, Transient)
        Source                            % core.MibVirtualImage subclass with a pyramid; [] on a pool worker until the first read
    end

    properties (Access = private)
        SourcePath char = ''              % store of Source, opened again on a pool worker
        ColChannel = []                   % colour channels to read, [] = all
        ScaleYXZ (1,3) double = [1 1 1]   % full-resolution pixels per level pixel
        FullWidth (1,1) double = 1        % width of level 1, the x range of a full-width read
        Axes                              % 1 x 3 struct, one per axis [y x z], see buildAxis
        PassOrder (1,:) double = []       % axes resampled, in the order of the passes
    end

    properties (Constant)
        Methods = {'nearest', 'linear', 'bilinear', 'triangle', 'cubic', 'bicubic', 'box', ...
            'lanczos2', 'lanczos3', 'max pooling', 'min pooling'}
        % resampling methods this class takes
    end

    methods
        function obj = ResampledSliceProvider(source, level, colChannel, outputSize, method)
            % RESAMPLEDSLICEPROVIDER - Build a resampling reader for one pyramid level.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       provider = io.savers.ResampledSliceProvider(source, level, colChannel, outputSize, method)
            %
            % Input Arguments:
            %   - **source** - image with a ``pyramid`` (``core.MibBigDataImage``);
            %     read with ``getData('image', 3, colChannel, options)``
            %   - **level** - [double] 1-based pyramid level (1 = full resolution)
            %   - **colChannel** - colour channels to read, ``[]`` = all
            %   - **outputSize** - [double] ``[height width depth]`` of the result
            %   - **method** - [char] one of ``Methods``, see the class help
            %
            % Nothing is read here: the result has the class of the image and
            % the channels read.
            arguments
                source
                level (1,1) double {mustBeInteger, mustBePositive}
                colChannel
                outputSize (1,3) double {mustBeInteger, mustBePositive}
                method (1,:) char
            end
            levelSizes = source.pyramid.levelImageSizes;   % [N x 3] Y X Z
            if level > size(levelSizes, 1)
                error('io:ResampledSliceProvider:wrongLevel', ...
                    'Level %d requested, the image has %d pyramid levels.', level, size(levelSizes, 1));
            end
            if ~ismember(method, obj.Methods)
                error('io:ResampledSliceProvider:wrongMethod', ...
                    'Resampling method "%s" is not available on BigData; use one of: %s.', method, strjoin(obj.Methods, ', '));
            end
            obj.Source     = source;
            obj.SourcePath = char(source.filename);
            obj.Level      = level;
            obj.ColChannel = colChannel;
            obj.Method     = method;
            obj.ScaleYXZ   = source.pyramid.levelScaleFactors(level, :);
            obj.FullWidth  = levelSizes(1, 2);
            obj.LevelSize  = levelSizes(level, :);
            obj.VoxelScaleYXZ = obj.LevelSize ./ outputSize;

            obj.Axes = [obj.buildAxis(obj.LevelSize(1), outputSize(1)), ...
                obj.buildAxis(obj.LevelSize(2), outputSize(2)), obj.buildAxis(obj.LevelSize(3), outputSize(3))];
            % imresize / imresize3 resize the axis of the smallest scale first
            [~, order] = sort(outputSize ./ obj.LevelSize);
            obj.PassOrder = order(outputSize(order) ~= obj.LevelSize(order));

            channels = numel(colChannel);
            if isempty(colChannel); channels = source.colors; end
            obj.SliceSize   = outputSize(1:2);
            obj.NumSlices   = outputSize(3);
            obj.NumFrames   = 1;
            obj.NumChannels = channels;
            obj.DataClass   = source.dataClass;
            obj.OutputSize  = [outputSize, channels, 1];
        end

        function slice = getSlice(obj, z, ~)
            % GETSLICE - Return resampled slice z ``[height width colors]``.
            slice = obj.getSliceRows(z, 1, obj.SliceSize(1));
        end

        function rows = getSliceRows(obj, z, rowFirst, rowLast)
            % GETSLICEROWS - Return rows rowFirst..rowLast of resampled slice z ``[rows width colors]``.
            %
            % Reads the level rows and slices under the kernels of these
            % output rows and of slice ``z``, across the full width, and
            % resamples them axis by axis in ``PassOrder``.
            if isempty(obj.Source)
                % deserialised on a pool worker: the image handle is Transient, open the store again
                loaderOptions = struct('datasetMode', 'BigData');
                loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
                [imageInfo, files] = loader.loadMetadata({obj.SourcePath}, loaderOptions);
                [imageData, imageInfo] = loader.loadImages(files, imageInfo, loaderOptions);
                obj.Source = core.MibBigDataImage(imageData, imageInfo);
            end
            outputRanges = [rowFirst rowLast; 1 obj.SliceSize(2); z z];
            inputRanges = zeros(3, 2);
            for axisIndex = [1 3]
                inputRanges(axisIndex, :) = obj.inputRange(axisIndex, outputRanges(axisIndex, :));
            end
            % every column is read, also those no output column uses (nearest may skip the last)
            inputRanges(2, :) = [1 obj.LevelSize(2)];
            readOptions.pyramidLevel = obj.Level;
            readOptions.y = [(inputRanges(1, 1) - 1) * obj.ScaleYXZ(1) + 1, inputRanges(1, 2) * obj.ScaleYXZ(1)];
            readOptions.x = [1, obj.FullWidth];
            readOptions.z = [(inputRanges(3, 1) - 1) * obj.ScaleYXZ(3) + 1, inputRanges(3, 2) * obj.ScaleYXZ(3)];
            block = obj.Source.getData('image', 3, obj.ColChannel, readOptions);   % [y x z c]
            block = reshape(block, size(block, 1), size(block, 2), size(block, 3), size(block, 4));

            dataClass = class(block);
            isPooling = endsWith(obj.Method, 'pooling');
            if ~isPooling; block = double(block); end
            for axisIndex = obj.PassOrder
                if isPooling
                    block = obj.poolAxis(block, axisIndex, outputRanges(axisIndex, :), inputRanges(axisIndex, 1));
                else
                    block = obj.weightAxis(block, axisIndex, outputRanges(axisIndex, :), inputRanges(axisIndex, :));
                    block = double(cast(block, dataClass));   % rounded and clipped after every pass, as imresize3
                end
            end
            % an axis that is not resampled was read at the output range already
            rows = reshape(cast(block, dataClass), size(block, 1), size(block, 2), size(block, 4));
        end

        function bandRows = bandRows(obj, bandBytes)
            % BANDROWS - Output rows per band that keep one band within ``bandBytes``.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       bandRows = provider.bandRows(bandBytes)
            %
            % A band is resampled in double (8 bytes per element, twice for the
            % copy a pass makes). Its largest array has the more of the source
            % rows under its kernel (``rows * VoxelScaleYXZ(1) + support``) and
            % the output rows, at the more of the level and output widths, times
            % the source slices under the Z kernel and the channels. Returns the
            % output height when the whole slice fits, at least 1.
            perElement = 16 * obj.supportLength(3) * obj.NumChannels;
            budgetRows = bandBytes / (max(obj.SliceSize(2), obj.LevelSize(2)) * perElement);
            % rows <= budgetRows and rows * scale + support <= budgetRows
            rows = min(budgetRows, (budgetRows - obj.supportLength(1)) / obj.VoxelScaleYXZ(1));
            bandRows = max(1, min(obj.SliceSize(1), floor(rows)));
        end
    end

    methods (Access = private)
        function axisPlan = buildAxis(obj, inputLength, outputLength)
            % BUILDAXIS - Weights (transposed, input x output, sparse) or pooling intervals of one axis.
            axisPlan = struct('weights', [], 'firstIndex', [], 'lastIndex', []);
            if inputLength == outputLength; return; end
            if endsWith(obj.Method, 'pooling')
                outputIndex = (1:outputLength)';
                if outputLength > inputLength
                    axisPlan.firstIndex = min(inputLength, floor((outputIndex - 0.5) * inputLength / outputLength) + 1);
                    axisPlan.lastIndex = axisPlan.firstIndex;
                else
                    % the 1e-9 guard stops a rounding error from adding a neighbour to an exact block
                    axisPlan.firstIndex = floor((outputIndex - 1) * inputLength / outputLength + 1e-9) + 1;
                    axisPlan.lastIndex = min(inputLength, ceil(outputIndex * inputLength / outputLength - 1e-9));
                end
                return;
            end
            axisPlan.weights = io.savers.ResampledSliceProvider.contributions(inputLength, outputLength, obj.Method);
        end

        function range = inputRange(obj, axisIndex, outputRange)
            % INPUTRANGE - First and last level index read for the output indices outputRange(1)..outputRange(2) of an axis.
            axisPlan = obj.Axes(axisIndex);
            if ~isempty(axisPlan.weights)
                inputIndices = find(any(axisPlan.weights(:, outputRange(1):outputRange(2)), 2));
                range = [inputIndices(1), inputIndices(end)];
            elseif ~isempty(axisPlan.firstIndex)
                range = [min(axisPlan.firstIndex(outputRange(1):outputRange(2))), max(axisPlan.lastIndex(outputRange(1):outputRange(2)))];
            else
                range = outputRange;    % not resampled
            end
        end

        function support = supportLength(obj, axisIndex)
            % SUPPORTLENGTH - The most level indices of an axis that one output index reads.
            axisPlan = obj.Axes(axisIndex);
            if ~isempty(axisPlan.weights)
                [inputIndices, outputIndices] = find(axisPlan.weights);
                support = max(accumarray(outputIndices, inputIndices, [], @max) - accumarray(outputIndices, inputIndices, [], @min)) + 1;
            elseif ~isempty(axisPlan.firstIndex)
                support = max(axisPlan.lastIndex - axisPlan.firstIndex) + 1;
            else
                support = 1;
            end
        end

        function block = weightAxis(obj, block, axisIndex, outputRange, inputRange)
            % WEIGHTAXIS - Resample one axis of a double block with the weights of the output range.
            weights = obj.Axes(axisIndex).weights(inputRange(1):inputRange(2), outputRange(1):outputRange(2));
            blockSize = size(block, 1:4);
            permutation = [axisIndex, setdiff(1:4, axisIndex)];
            block = reshape(permute(block, permutation), blockSize(axisIndex), []);
            block = full(weights' * block);
            blockSize(axisIndex) = size(weights, 2);
            block = ipermute(reshape(block, blockSize(permutation)), permutation);
        end

        function pooled = poolAxis(obj, block, axisIndex, outputRange, inputFirst)
            % POOLAXIS - Max or min of one axis of a block over the input interval of each output index.
            axisPlan = obj.Axes(axisIndex);
            firstIndex = axisPlan.firstIndex(outputRange(1):outputRange(2)) - inputFirst + 1;
            lastIndex = axisPlan.lastIndex(outputRange(1):outputRange(2)) - inputFirst + 1;
            poolFunction = @max;
            if strcmp(obj.Method, 'min pooling'); poolFunction = @min; end
            subscripts = repmat({':'}, 1, 4);
            subscripts{axisIndex} = firstIndex;
            pooled = block(subscripts{:});
            for offset = 1:max(lastIndex - firstIndex)
                % a block shorter than the longest one repeats its last voxel, which max/min ignore
                subscripts{axisIndex} = min(firstIndex + offset, lastIndex);
                pooled = poolFunction(pooled, block(subscripts{:}));
            end
        end
    end

    methods (Static, Access = private)
        function weights = contributions(inputLength, outputLength, method)
            % CONTRIBUTIONS - Sparse ``[inputLength x outputLength]`` weights of imresize for one axis.
            %
            % The contributions of ``imresize`` (and ``imresize3``): kernel
            % centres ``u = x / scale + 0.5 * (1 - 1 / scale)``, the kernel
            % widened by ``1 / scale`` with antialiasing when shrinking (not
            % for nearest), the weights of each output normalised to 1, indices
            % beyond the edges mirrored.
            scale = outputLength / inputLength;
            antialiasing = true;
            switch method
                case 'nearest'
                    kernel = @io.savers.ResampledSliceProvider.boxKernel; kernelWidth = 1; antialiasing = false;
                case {'linear', 'bilinear', 'triangle'}
                    kernel = @io.savers.ResampledSliceProvider.triangleKernel; kernelWidth = 2;
                case {'cubic', 'bicubic'}
                    kernel = @io.savers.ResampledSliceProvider.cubicKernel; kernelWidth = 4;
                case 'box'
                    kernel = @io.savers.ResampledSliceProvider.boxKernel; kernelWidth = 1;
                case 'lanczos2'
                    kernel = @(x) io.savers.ResampledSliceProvider.lanczosKernel(x, 2); kernelWidth = 4;
                case 'lanczos3'
                    kernel = @(x) io.savers.ResampledSliceProvider.lanczosKernel(x, 3); kernelWidth = 6;
            end
            if scale < 1 && antialiasing
                weightFunction = @(x) scale * kernel(scale * x);
                kernelWidth = kernelWidth / scale;
            else
                weightFunction = kernel;
            end
            outputIndex = (1:outputLength)';
            centres = outputIndex / scale + 0.5 * (1 - 1 / scale);
            leftmost = floor(centres - kernelWidth / 2);
            taps = ceil(kernelWidth) + 2;
            indices = leftmost + (0:taps - 1);
            tapWeights = weightFunction(centres - indices);
            tapWeights = tapWeights ./ sum(tapWeights, 2);
            mirrored = [1:inputLength, inputLength:-1:1];
            indices = mirrored(mod(indices - 1, numel(mirrored)) + 1);
            outputIndices = repmat(outputIndex, 1, taps);
            % sparse() sums the weights of a mirrored index that appears twice, as imresize does
            weights = sparse(indices(:), outputIndices(:), tapWeights(:), inputLength, outputLength);
        end

        function f = cubicKernel(x)
            % CUBICKERNEL - Keys cubic, a = -0.5, as imresize.
            absx = abs(x);
            absx2 = absx.^2;
            absx3 = absx.^3;
            f = (1.5 * absx3 - 2.5 * absx2 + 1) .* (absx <= 1) + ...
                (-0.5 * absx3 + 2.5 * absx2 - 4 * absx + 2) .* ((1 < absx) & (absx <= 2));
        end

        function f = boxKernel(x)
            % BOXKERNEL - Box of width 1, as imresize.
            f = double((-0.5 <= x) & (x < 0.5));
        end

        function f = triangleKernel(x)
            % TRIANGLEKERNEL - Triangle of width 2 (linear), as imresize.
            f = (x + 1) .* ((-1 <= x) & (x < 0)) + (1 - x) .* ((0 <= x) & (x <= 1));
        end

        function f = lanczosKernel(x, lobes)
            % LANCZOSKERNEL - Lanczos of 2 or 3 lobes, as imresize (with its eps guard at 0).
            f = (sin(pi * x) .* sin(pi * x / lobes) + eps) ./ ((pi^2 * x.^2 / lobes) + eps);
            f = f .* (abs(x) < lobes);
        end
    end
end
