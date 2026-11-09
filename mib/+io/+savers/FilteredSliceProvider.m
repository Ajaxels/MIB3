classdef FilteredSliceProvider < io.savers.SliceProvider
% FILTEREDSLICEPROVIDER - SliceProvider that streams a processed pyramid level of a BigData image.
%
% Reads a band of rows of one pyramid level of an image, widened by a halo,
% passes it to a block function (a filter, an arithmetic expression...), and
% returns the band with the halo cropped. Fed to
% ``io.savers.Zarr3Saver.saveStreamResumable`` with ``BandHeight``, it writes
% the processed level as a new pyramid while holding only one band of rows in
% memory, so a whole-slide image is processed at full resolution.
%
% **The halo.** A neighbourhood filter computed on a band differs from the
% same filter on the whole slice near the band's top and bottom edges, because
% it pads there instead of seeing the next rows. Reading ``HaloYX`` extra rows
% on each side and dropping them makes the band equal the whole-slice result
% when the halo covers the filter support (``ceil(3*sigma)`` for a Gaussian,
% the strel radius for a morphological operation). Rows are read across the
% full width of the level, so no halo is needed in X. At the image border the
% band is not widened and the filter pads as it would on the whole slice.
% ``HaloZ`` does the same for 3D block functions: slice ``z`` is computed from
% slices ``z-HaloZ .. z+HaloZ`` (clamped to the stack) and only slice ``z`` is
% kept, so every slice is read ``2*HaloZ+1`` times.
%
% **Block function contract.** ``out = BlockFunction(block)``:
%
%   - ``HaloZ == 0`` (2D): ``block`` is ``[rows width colors]``, ``out`` must
%     be ``[rows width outColors]``
%   - ``HaloZ > 0`` (3D): ``block`` is ``[rows width depth colors]``, ``out``
%     must be ``[rows width depth outColors]``
%
% A block function with exactly **two** inputs is called as
% ``out = BlockFunction(block, z)``, with ``z`` the level slice the band belongs
% to (the centre slice for a 3D function). Tools whose parameters differ per
% slice use it, e.g. a threshold or a normalization computed for each slice by
% ``utils.bigdata.sampleStripes``. A block function with exactly **three** inputs
% is called as ``out = BlockFunction(block, z, firstRow)``, with ``firstRow``
% the level row of the first row of ``block`` (its halo included), for tools
% whose result depends on the position: a map computed on a coarser level and
% interpolated to the band, a pyramid aligned to the whole slice, a random field
% generated per row. Any other number of inputs gets ``block`` only, so pass a
% function of more inputs through an anonymous wrapper.
%
% ``out`` may change the class and the number of colour channels; both are
% found by running the function once on the first rows of slice 1 in the
% constructor, so it must accept a block of any height. Whole slices are never
% read by the constructor (``io.savers.MibImageSliceProvider`` probes a whole
% slice, which at level 1 of a whole-slide image does not fit in memory).
%
% **Coordinates.** ``getData`` takes ``options.y/x/z`` in full-resolution
% coordinates and maps them to level ``L`` with ``ceil(v / scale)``. Level rows
% ``a..b`` are therefore requested as full-resolution ``(a-1)*scale+1 ..
% b*scale``, which maps back to exactly ``a..b`` for any scale >= 1, integer or
% not.
%
% **Region.** ``Region = [yFirst yLast xFirst xLast]`` (level pixels) makes
% the provider stream that box only: ``SliceSize`` is the box, and rows and
% slices are counted from its top. The halo is then read in X as well, up to
% ``HaloYX`` columns on either side of the box (clamped to the level), and
% dropped with the Y halo, so a neighbourhood filter gives inside the box what
% it gives on the whole level. A block function of three inputs depends on
% the position and gets the full width of the level (``firstRow`` stays a
% level row), and the box columns are cut from its result. ``RegionMask``,
% a logical ``[boxHeight boxWidth]``, keeps the source values where it is
% false (a non-rectangular ROI): the result must then have the class and the
% channels of the source read, or the constructor errors
% (``io:FilteredSliceProvider:regionMaskResult``).
%
% **Parallel writing.** The provider can be sent to the workers of a process
% pool (``saveStreamResumable`` with a pool, ``parallel.pool.Constant``). The
% image handle with its open readers is ``Transient`` and is not serialised:
% the provider keeps the store path, and its first read on a worker opens the
% store again (``io.loaders.Zarr3VirtualSetupLoader``, as
% ``controllers.BigDataOptions.openStoreInBuffer`` does), so every worker
% reads with its own readers and chunk cache. The block function is
% serialised with what it captured; it must not capture a handle that cannot
% be (a controller, a figure). A provider captured by a block function (a
% coarser level read for a guide) is reopened the same way. The constructor's
% probe is not repeated on the worker.
%
% See also: io.savers.SliceProvider, io.savers.MibImageSliceProvider,
% io.savers.Zarr3Saver.saveStreamResumable, utils.bigdata.processImageToStore
%
% **Example** - Gaussian of level 1 of a BigData image, written in bands:
%
%   .. code-block:: matlab
%
%      img = mibModel.I{mibModel.getActiveId()}.image;   % core.MibBigDataImage
%      gaussian = @(block) imgaussfilt(block, 2);
%      provider = io.savers.FilteredSliceProvider(img, 1, [], gaussian, HaloYX = 6);
%      rows = provider.getSliceRows(1, 1, 512);           % first 512 rows of slice 1

    properties
        SupportsRowReads = true   % getSliceRows returns rows identical to getSlice
    end

    properties (SetAccess = private)
        Level        (1,1) double = 1     % 1-based pyramid level that is read
        HaloYX       (1,1) double = 0     % rows read above and below each band
        HaloZ        (1,1) double = 0     % slices read before and after each slice (3D)
    end

    properties (Access = private, Transient)
        Source                            % core.MibVirtualImage subclass with a pyramid; [] on a pool worker until the first read
    end

    properties (Access = private)
        SourcePath   char = ''            % store of Source, opened again on a pool worker
        ColChannel = []                   % colour channels to read, [] = all
        BlockFunction                     % function handle, see the class help
        BlockInputs (1,1) double = 1          % 1: BlockFunction(block), 2: (block, z), 3: (block, z, firstRow)
        ScaleYXZ     (1,3) double = [1 1 1]   % full-resolution pixels per level pixel
        FullWidth    (1,1) double = 1     % width of level 1, the x range of a full-width read
        LevelSize    (1,2) double = [1 1] % [height width] of the level
        Region       (1,4) double = [1 1 1 1]   % [yFirst yLast xFirst xLast] of the streamed box, level pixels
        RegionMask   = []                 % logical box mask, [] = the whole box; false keeps the source
    end

    methods
        function obj = FilteredSliceProvider(source, level, colChannel, blockFunction, options)
            % FILTEREDSLICEPROVIDER - Build a processed reader for one pyramid level.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       provider = io.savers.FilteredSliceProvider(source, level, colChannel, blockFunction)
            %       provider = io.savers.FilteredSliceProvider(..., HaloYX = 6, HaloZ = 0)
            %
            % Input Arguments:
            %   - **source** - image with a ``pyramid`` (``core.MibBigDataImage``,
            %     ``core.MibVirtualImage`` of a zarr store); read with
            %     ``getData('image', 3, colChannel, options)``
            %   - **level** - [double] 1-based pyramid level (1 = full resolution)
            %   - **colChannel** - colour channels to read, ``[]`` = all
            %   - **blockFunction** - function handle ``out = f(block)``, see the class help
            %   - **options.HaloYX** - [double] rows of halo above and below each band, default 0
            %   - **options.HaloZ** - [double] slices of halo for a 3D function, default 0 (2D)
            %   - **options.Region** - ``[yFirst yLast xFirst xLast]`` box of the level to
            %     stream, default ``[]`` (the whole level); see the class help
            %   - **options.RegionMask** - logical ``[boxHeight boxWidth]``, default ``[]``
            %     (the whole box); false pixels keep the source values
            arguments
                source
                level (1,1) double {mustBeInteger, mustBePositive}
                colChannel
                blockFunction (1,1) function_handle
                options.HaloYX (1,1) double {mustBeInteger, mustBeNonnegative} = 0
                options.HaloZ (1,1) double {mustBeInteger, mustBeNonnegative} = 0
                options.Region double = []
                options.RegionMask = []
            end
            levelSizes = source.pyramid.levelImageSizes;   % [N x 3] Y X Z
            if level > size(levelSizes, 1)
                error('io:FilteredSliceProvider:wrongLevel', ...
                    'Level %d requested, the image has %d pyramid levels.', level, size(levelSizes, 1));
            end
            obj.Source        = source;
            obj.SourcePath    = char(source.filename);
            obj.Level         = level;
            obj.ColChannel    = colChannel;
            obj.BlockFunction = blockFunction;
            obj.BlockInputs = 1;
            if any(nargin(blockFunction) == [2 3]); obj.BlockInputs = nargin(blockFunction); end
            obj.HaloYX        = options.HaloYX;
            obj.HaloZ         = options.HaloZ;
            obj.ScaleYXZ      = source.pyramid.levelScaleFactors(level, :);
            obj.FullWidth     = levelSizes(1, 2);

            obj.LevelSize = levelSizes(level, 1:2);
            region = options.Region;
            if isempty(region); region = [1 obj.LevelSize(1) 1 obj.LevelSize(2)]; end
            if numel(region) ~= 4 || any(region ~= round(region)) || region(1) < 1 || region(3) < 1 || ...
                    region(2) > obj.LevelSize(1) || region(4) > obj.LevelSize(2) || region(2) < region(1) || region(4) < region(3)
                error('io:FilteredSliceProvider:wrongRegion', ...
                    'The region [%s] is not a box inside level %d of %d x %d px (Y x X).', ...
                    num2str(region(:)'), level, obj.LevelSize(1), obj.LevelSize(2));
            end
            obj.Region = region(:)';
            height = region(2) - region(1) + 1;
            width  = region(4) - region(3) + 1;
            depth  = levelSizes(level, 3);
            if ~isempty(options.RegionMask) && ~isequal(size(options.RegionMask), [height width])
                error('io:FilteredSliceProvider:wrongRegion', 'The region mask is %d x %d, the region %d x %d.', ...
                    size(options.RegionMask, 1), size(options.RegionMask, 2), height, width);
            end
            if ~isempty(options.RegionMask) && ~all(options.RegionMask(:))
                obj.RegionMask = logical(options.RegionMask);
            end
            obj.SliceSize = [height width];
            obj.NumSlices = depth;
            obj.NumFrames = 1;

            % the class and channels of the result: run the function on a few rows
            if ~isempty(obj.RegionMask)
                mask = obj.RegionMask;
                obj.RegionMask = [];      % the probe returns the result unblended
                probe = obj.processRows(1, 1, min(height, 8));
                obj.RegionMask = mask;
                sourceChannels = numel(colChannel);
                if isempty(colChannel); sourceChannels = source.colors; end
                if size(probe, 3) ~= sourceChannels || ~strcmp(class(probe), source.dataClass)
                    error('io:FilteredSliceProvider:regionMaskResult', ...
                        ['The result has %d channel(s) of %s, the image %d of %s; a ROI that is not a rectangle ' ...
                         'needs the channels and class of the image, as its pixels outside the ROI keep the image.'], ...
                        size(probe, 3), class(probe), sourceChannels, source.dataClass);
                end
            else
                probe = obj.processRows(1, 1, min(height, 8));
            end
            obj.DataClass   = class(probe);
            obj.NumChannels = size(probe, 3);
            obj.OutputSize  = [height, width, depth, obj.NumChannels, 1];
        end

        function slice = getSlice(obj, z, ~)
            % GETSLICE - Return processed slice z ``[height width colors]``.
            slice = obj.getSliceRows(z, 1, obj.SliceSize(1));
        end

        function rows = getSliceRows(obj, z, rowFirst, rowLast)
            % GETSLICEROWS - Return processed rows rowFirst..rowLast of slice z ``[rows width colors]``.
            rows = obj.processRows(z, rowFirst, rowLast);
            if ~isa(rows, obj.DataClass)
                error('io:FilteredSliceProvider:classChanged', ...
                    'The block function returned %s for slice %d, rows %d-%d, but %s for the first rows.', ...
                    class(rows), z, rowFirst, rowLast, obj.DataClass);
            end
        end
    end

    methods (Access = private)
        function rows = processRows(obj, z, rowFirst, rowLast)
            % PROCESSROWS - Read the band with its halo, apply the function, crop the halo.
            %
            % ``rowFirst``, ``rowLast`` count from the top of the region; the
            % reads are in level rows and columns.
            levelFirst = obj.Region(1) + rowFirst - 1;
            levelLast = obj.Region(1) + rowLast - 1;
            readFirst = max(1, levelFirst - obj.HaloYX);
            readLast  = min(obj.LevelSize(1), levelLast + obj.HaloYX);
            if obj.BlockInputs == 3 || isequal(obj.Region([3 4]), [1 obj.LevelSize(2)])
                % full width: a position-dependent function, or no column box
                columnFirst = 1;
                columnLast = obj.LevelSize(2);
            else
                columnFirst = max(1, obj.Region(3) - obj.HaloYX);
                columnLast = min(obj.LevelSize(2), obj.Region(4) + obj.HaloYX);
            end
            zFirst = max(1, z - obj.HaloZ);
            zLast  = min(obj.NumSlices, z + obj.HaloZ);

            if isempty(obj.Source)
                % deserialised on a pool worker: the image handle is Transient, open the store again
                loaderOptions = struct('datasetMode', 'BigData');
                loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
                [imageInfo, files] = loader.loadMetadata({obj.SourcePath}, loaderOptions);
                [imageData, imageInfo] = loader.loadImages(files, imageInfo, loaderOptions);
                obj.Source = core.MibBigDataImage(imageData, imageInfo);
            end
            readOptions.pyramidLevel = obj.Level;
            readOptions.y = [(readFirst - 1) * obj.ScaleYXZ(1) + 1, readLast * obj.ScaleYXZ(1)];
            if columnFirst == 1 && columnLast == obj.LevelSize(2)
                readOptions.x = [1, obj.FullWidth];
            else
                readOptions.x = [(columnFirst - 1) * obj.ScaleYXZ(2) + 1, columnLast * obj.ScaleYXZ(2)];
            end
            readOptions.z = [(zFirst - 1) * obj.ScaleYXZ(3) + 1, zLast * obj.ScaleYXZ(3)];
            block = obj.Source.getData('image', 3, obj.ColChannel, readOptions);   % [y x z c]

            keepRows = (levelFirst - readFirst + 1):(levelLast - readFirst + 1);
            keepColumns = (obj.Region(3) - columnFirst + 1):(obj.Region(4) - columnFirst + 1);
            readWidth = size(block, 2);
            if obj.HaloZ == 0
                % 2D: [rows width colors]
                block = reshape(block, size(block, 1), size(block, 2), size(block, 4));
                processed = obj.applyBlockFunction(block, z, readFirst);
                if size(processed, 2) == readWidth; rows = processed(keepRows, keepColumns, :); end
                sourceRows = block(keepRows, keepColumns, :);
            else
                processed = obj.applyBlockFunction(block, z, readFirst);
                if size(processed, 2) == readWidth
                    rows = processed(keepRows, keepColumns, z - zFirst + 1, :);
                    rows = reshape(rows, numel(keepRows), size(rows, 2), size(rows, 4));
                end
                sourceRows = block(keepRows, keepColumns, z - zFirst + 1, :);
                sourceRows = reshape(sourceRows, numel(keepRows), size(sourceRows, 2), size(sourceRows, 4));
            end
            if size(processed, 2) ~= readWidth
                error('io:FilteredSliceProvider:wrongSize', ...
                    'The block function changed the width of the block from %d to %d.', ...
                    readWidth, size(processed, 2));
            end
            if ~isempty(obj.RegionMask)
                % outside a non-rectangular ROI the source stays
                outside = repmat(~obj.RegionMask(rowFirst:rowLast, :), 1, 1, size(rows, 3));
                rows(outside) = sourceRows(outside);
            end
        end

        function processed = applyBlockFunction(obj, block, z, firstRow)
            % APPLYBLOCKFUNCTION - Call the block function with as many of (block, z, firstRow) as it takes.
            switch obj.BlockInputs
                case 3
                    processed = obj.BlockFunction(block, z, firstRow);
                case 2
                    processed = obj.BlockFunction(block, z);
                otherwise
                    processed = obj.BlockFunction(block);
            end
        end
    end
end
