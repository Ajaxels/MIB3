classdef Zarr3Saver < io.savers.BaseSaver
% ZARR3SAVER - write an image as an OME-Zarr v3 multi-resolution (multiscales) pyramid.
%
% Produces a chunked OME-Zarr v3 group with one downsampled level per
% pyramid step, written through the native zarr-matlab engine
% (``ZarrArray``/``ZarrGroup``). The result is readable by MIB's
% ``io.loaders.Zarr3VirtualSetupLoader`` (and thus openable as a **BigData**
% dataset) and by other OME-Zarr tools.
%
% **Primary use - ingest/convert:** turn an in-memory (Standard) dataset into
% a zarr3 BigData pyramid on disk, so large datasets can be moved into the
% BigData segmentation workflow. (A non-zarr Virtual/BioFormats source must
% first be gathered to memory or streamed level-by-level - future.)
%
% **Axis order.** Arrays are created with the zarr-matlab transpose codec, so
% they store/return in native MATLAB ``[y, x, z, c, t]`` order. The
% ``multiscales.axes`` are declared to match (``y, x, z`` plus ``c`` and/or
% ``t`` only when those dimensions are > 1). ``Zarr3VirtualSetupLoader`` reads
% ``axes.name`` to recover this order, and ``Zarr3VirtualLoader`` applies the
% (identity) permutation - so the round-trip is exact.
%
% **Pyramid.** Level 0 = full resolution; each further level halves Y and X
% (Z is kept - XY-only downsampling). The per-level ``scale`` coordinate
% transformation encodes the physical voxel size (``pixSize`` × 2^level in XY),
% which the loader turns into the magnification→level mapping.
%
% **Examples**
%
% **Example 1** - convert the active dataset to a BigData pyramid:
%
%   .. code-block:: matlab
%
%      ds   = mibModel.I{mibModel.getActiveId()};
%      data = ds.getData4D('image', 3, NaN);          % returns a cell; {1} = [y x z c t]
%      data = data{1};
%      meta = struct('pixSize', ds.image.pixSize);
%      io.savers.Zarr3Saver().save(data, meta, 'C:\data\out.zarr3');
%      % then open 'C:\data\out.zarr3' in BigData mode
%
% **Example 2** - minimal call (no metadata, default options ⇒ voxel size 1):
%
%   .. code-block:: matlab
%
%      vol = uint16(rand(800, 600, 20) * 1000);       % [y x z]
%      io.savers.Zarr3Saver().save(vol, struct(), 'C:\data\vol.zarr3');
%
% **Example 3** - force a fixed number of pyramid levels:
%
%   .. code-block:: matlab
%
%      opt = struct('Levels', 4);                     % level 0..3 (full, /2, /4, /8 in XY)
%      io.savers.Zarr3Saver().save(vol, meta, 'C:\data\vol.zarr3', opt);
%
% **Example 4** - control where the auto-pyramid stops and its chunking:
%
%   .. code-block:: matlab
%
%      opt = struct('MinLevelSize', 512, ...          % stop once min(Y,X) < 512
%                   'MaxLevels',   6, ...             % never exceed 6 levels
%                   'ChunkSize',   [512 512 8]);      % [y x z] zarr chunk
%      io.savers.Zarr3Saver().save(vol, meta, 'C:\data\vol.zarr3', opt);
%
% **Example 5** - mode downsampling for label/model pyramids (majority-vote per output pixel):
%
%   .. code-block:: matlab
%
%      opt = struct('DownsampleMethod', 'mode');      % dominant label in each source block
%      io.savers.Zarr3Saver().save(labelVol, meta, 'C:\data\labels.zarr3', opt);
%
% **Example 6** - multichannel image (axes become ``yxzc``, colours preserved):
%
%   .. code-block:: matlab
%
%      rgb = uint8(rand(512, 512, 10, 3) * 255);      % [y x z c]
%      io.savers.Zarr3Saver().save(rgb, struct('pixSize', struct('x',.1,'y',.1,'z',.5)), ...
%                                  'C:\data\rgb.zarr3');
%
% **Example 7** - export ONE pyramid level of a BigData dataset back to zarr3
% (gather the level you want, then write it as a fresh single/low pyramid):
%
%   .. code-block:: matlab
%
%      ds    = mibModel.I{mibModel.getActiveId()};                 % BigData
%      level = ds.getData4D('image', 3, NaN, struct('pyramidLevel', 3));   % coarse level
%      level = level{1};
%      io.savers.Zarr3Saver().save(level, struct('pixSize', ds.image.pixSize), ...
%                                  'C:\data\level3.zarr3', struct('Levels', 1));
%
% **Example 8** - round-trip check (write, reopen via the BigData loader):
%
%   .. code-block:: matlab
%
%      io.savers.Zarr3Saver().save(vol, meta, 'C:\data\vol.zarr3');
%      lo = struct('datasetMode', 'BigData');
%      L  = io.loaders.Zarr3VirtualSetupLoader(lo);
%      [info, files] = L.loadMetadata({'C:\data\vol.zarr3'}, lo);
%      % files.levelImageSizes / files.levelScaleFactors describe the pyramid

    methods
        function obj = Zarr3Saver(options)
            % ZARR3SAVER - Constructor (accepts the optional saver options struct).
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            % GETSUPPORTEDFORMATS - format strings handled by Zarr3Saver.
            formats = {'OME-Zarr v3 (*.zarr3)', 'OME-Zarr v2 (*.zarr2)'};
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % SAVE - write ``data`` as an OME-Zarr multiscales pyramid.
            %
            % Writes zarr v3 by default and zarr v2 when the output path ends in
            % ``.zarr2``; the pyramid, chunking and metadata are otherwise
            % identical. Sharding is v3-only and is refused for a v2 output.
            %
            % Input Arguments:
            %   - **data** - [y x z c t] numeric image array (full resolution).
            %   - **metadata** - struct; uses ``.pixSize`` (``.x .y .z``) when present.
            %   - **filename** - [char] output ``.zarr3``/``.zarr2`` group path
            %     (overwritten if it exists).
            %   - **options** - *(optional)* struct:
            %
            %     - ``.ZarrFormat`` - 2 or 3; overrides the format implied by the extension
            %     - ``.Levels`` - explicit number of pyramid levels (default: auto)
            %     - ``.MinLevelSize`` - stop auto-pyramid when min(Y,X) < this (default 256)
            %     - ``.MaxLevels`` - cap on auto levels (default 8)
            %     - ``.ChunkSize`` - [y x z] chunk shape (default [256 256 16], clamped)
            %     - ``.ShardSize`` - [y x z] chunk multipliers; ``[]`` = no sharding. Each
            %       value says how many chunks to bundle per axis (e.g. [4 4 1])
            %     - ``.Compressors`` - codec spec for ZarrArray.create (default 'zstd')
            %     - ``.DownsampleMethod`` - 'bilinear', 'nearest', 'bicubic', 'median', or 'mode' (default 'bilinear').
            %       ``'median'`` picks the median value per block (noise-robust, image data).
            %       ``'mode'`` picks the dominant value per block (categorical label data).
            %
            % Output Arguments:
            %   - **fnOut** - [char] the written group path.

            if nargin < 5; options = struct(); end
            if nargin < 4 || isempty(filename); error('io:Zarr3Saver:noFilename', 'Output filename is required'); end

            % Interactive GUI save → collect pyramid/chunk/compression settings (same
            % dialog as the "Export to Zarr3" ribbon action); cancel aborts the save.
            [options, cancelled] = obj.resolveExportOptions(options, metadata, size(data, 1:3));
            if cancelled; fnOut = []; return; end

            if ~isfield(options, 'Levels');             options.Levels = []; end
            if ~isfield(options, 'MinLevelSize');       options.MinLevelSize = 256; end
            if ~isfield(options, 'MaxLevels');          options.MaxLevels = 8; end
            if ~isfield(options, 'ChunkSize');          options.ChunkSize = [256 256 16]; end
            if ~isfield(options, 'ShardSize');          options.ShardSize = []; end
            if ~isfield(options, 'Compressors');        options.Compressors = 'zstd'; end
            if ~isfield(options, 'DownsampleMethod');   options.DownsampleMethod = 'bilinear'; end
            if ~isfield(options, 'DownsampleStrategy'); options.DownsampleStrategy = 'XY only'; end

            % Label layers are categorical - prevent interpolating methods; allow 'mode'
            % (majority vote) as the accurate alternative to 'nearest'.
            isLabelLayer = (isfield(options,'layerType') && strcmp(options.layerType,'labels')) || ...
                (isstruct(metadata) && isfield(metadata,'materialNames') && ~isempty(metadata.materialNames));
            if isLabelLayer && ~ismember(options.DownsampleMethod, {'nearest', 'mode'})
                options.DownsampleMethod = 'nearest';
            end

            % physical voxel size (default 1)
            pixSize = struct('x', 1, 'y', 1, 'z', 1);
            if isstruct(metadata) && isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                ps = metadata.pixSize;
                if isfield(ps, 'x'); pixSize.x = ps.x; end
                if isfield(ps, 'y'); pixSize.y = ps.y; end
                if isfield(ps, 'z'); pixSize.z = ps.z; end
            end

            sz = size(data, 1:5);
            Y = sz(1); X = sz(2); Z = sz(3); C = sz(4); T = sz(5);
            imgClass = class(data);

            % axes declared to match the kept (non-trailing-singleton) dims
            axesNames = {'y', 'x', 'z'};
            axesTypes = {'space', 'space', 'space'};
            if C > 1; axesNames{end+1} = 'c'; axesTypes{end+1} = 'channel'; end
            if T > 1; axesNames{end+1} = 't'; axesTypes{end+1} = 'time'; end
            nKeep = numel(axesNames);

            % build per-level size/scale plan (honours DownsampleStrategy)
            plan    = io.savers.Zarr3Saver.computeLevelPlan(Y, X, Z, pixSize, options);
            nLevels = numel(plan);

            % fresh group
            filename = char(filename);
            zarrFormat = io.savers.Zarr3Saver.resolveZarrFormat(filename, options);
            if isfolder(filename); rmdir(filename, 's'); end
            % bulk writes follow io.zarr.Config backend; levels inherit the format
            grp = io.zarr.Group.create(filename, 'zarrFormat', zarrFormat);

            datasets = cell(1, nLevels);
            for L = 1:nLevels
                Yl = plan(L).Yl;
                Xl = plan(L).Xl;
                Zl = plan(L).Zl;

                if L == 1
                    lvl = data;
                else
                    lvl = zeros(Yl, Xl, Zl, C, T, imgClass);
                    for t = 1:T
                        for c = 1:C
                            blockMethods = {'mode', 'median'};
                            if Zl == Z
                                % XY-only: slice-by-slice resize
                                if ismember(options.DownsampleMethod, blockMethods)
                                    reduceFcn = str2func(options.DownsampleMethod);
                                    for z = 1:Z
                                        lvl(:,:,z,c,t) = io.savers.Zarr3Saver.blockReduce2D( ...
                                            data(:,:,z,c,t), Yl, Xl, reduceFcn);
                                    end
                                else
                                    for z = 1:Z
                                        lvl(:,:,z,c,t) = imresize(data(:,:,z,c,t), [Yl Xl], ...
                                            options.DownsampleMethod);
                                    end
                                end
                            else
                                % XY + Z: volumetric resize
                                if ismember(options.DownsampleMethod, blockMethods)
                                    reduceFcn = str2func(options.DownsampleMethod);
                                    lvl(:,:,:,c,t) = io.savers.Zarr3Saver.blockReduce3D( ...
                                        data(:,:,:,c,t), Yl, Xl, Zl, reduceFcn);
                                else
                                    method3d = options.DownsampleMethod;
                                    if strcmp(method3d, 'bilinear'); method3d = 'linear'; end
                                    if strcmp(method3d, 'bicubic');  method3d = 'cubic';  end
                                    lvl(:,:,:,c,t) = cast(imresize3(data(:,:,:,c,t), [Yl Xl Zl], method3d), imgClass);
                                end
                            end
                        end
                    end
                end

                % drop trailing singleton c/t to match the declared axes
                keepShape = [Yl, Xl, Zl];
                if C > 1; keepShape(end+1) = C; end %#ok<AGROW>
                if T > 1; keepShape(end+1) = T; end %#ok<AGROW>
                lvl = reshape(lvl, keepShape);

                % chunk: clamp [y x z] to level size; full extent for c/t
                chunk = min(options.ChunkSize(1:3), keepShape(1:3));
                chunk = max(chunk, [1 1 1]);
                if numel(keepShape) > 3; chunk = [chunk, keepShape(4:end)]; end %#ok<AGROW>

                name = num2str(L - 1);
                createArgs = {'chunkShape', chunk, 'compressors', options.Compressors};
                if ~isempty(options.ShardSize)
                    createArgs = [createArgs, {'shardShape', io.savers.Zarr3Saver.computeShard(chunk, options.ShardSize)}]; %#ok<AGROW>
                end
                arr = grp.createArray(name, keepShape, imgClass, createArgs{:});
                arr.write(lvl);

                % per-level physical scale (actual values from the plan, not 2^(L-1))
                scaleVec = [plan(L).physScaleY, plan(L).physScaleX, plan(L).physScaleZ];
                if C > 1; scaleVec(end+1) = 1; end %#ok<AGROW>
                if T > 1; scaleVec(end+1) = 1; end %#ok<AGROW>
                datasets{L} = struct('path', name, ...
                    'coordinateTransformations', {{struct('type', 'scale', 'scale', scaleVec)}});
            end

            % OME-NGFF multiscales attribute
            axesCells = cell(1, nKeep);
            for a = 1:nKeep
                axesCells{a} = struct('name', axesNames{a}, 'type', axesTypes{a});
            end
            ms = struct('version', '0.4', 'axes', {axesCells}, 'datasets', {datasets});
            attrStruct = struct('multiscales', {{ms}});
            % persist material names/colours for label layers (model round-trip)
            if isLabelLayer && isstruct(metadata) && isfield(metadata,'materialNames') && ~isempty(metadata.materialNames)
                mm = struct('materialNames', {metadata.materialNames});
                if isfield(metadata,'materialColors') && ~isempty(metadata.materialColors)
                    mm.materialColors = metadata.materialColors;
                end
                attrStruct.mibMaterials = mm;
            end
            grp.setAttributes(attrStruct);

            fnOut = filename;
        end

        function fnOut = saveStream(obj, provider, metadata, filename, options)
            % SAVESTREAM - write an OME-Zarr pyramid streaming one Z-slice at a time.
            %
            % Memory-bounded twin of ``save``: instead of a full ``[y x z c t]`` array
            % it pulls each Z-slice from ``provider`` (an ``io.savers.SliceProvider``),
            % writes it to level 0, and writes its XY-downsampled copies to the coarser
            % levels - all via region (``bbox``) writes - so the whole volume is never
            % resident. This is the out-of-core ingest path (e.g. a large source → zarr).
            %
            % Chooses the zarr format exactly as ``save`` does: from the output
            % extension, or from ``options.ZarrFormat`` when given.
            %
            % See ``io.savers.BaseSaver.saveStream``.
            %
            % **Example** - stream a volume into a fresh OME-Zarr v3 pyramid:
            %
            %   .. code-block:: matlab
            %
            %      vol      = uint16(rand(900, 800, 6) * 1000);            % [y x z]
            %      provider = io.savers.InMemorySliceProvider(reshape(vol, 900, 800, 6, 1, 1));
            %      meta     = struct('pixSize', struct('x',0.02,'y',0.02,'z',0.1));
            %      io.savers.Zarr3Saver(struct()).saveStream(provider, meta, 'C:\out\vol.zarr3', ...
            %          struct('showWaitbar', false));
            %      % reopen via io.loaders.Zarr3VirtualSetupLoader (datasetMode = 'BigData')
            if nargin < 5; options = struct(); end
            if nargin < 4 || isempty(filename); error('io:Zarr3Saver:noFilename', 'Output filename is required'); end

            % Interactive GUI save → show the export-settings dialog (cancel aborts).
            [options, cancelled] = obj.resolveExportOptions(options, metadata, provider.OutputSize(1:3));
            if cancelled; fnOut = []; return; end

            if ~isfield(options, 'Levels');             options.Levels = []; end
            if ~isfield(options, 'MinLevelSize');       options.MinLevelSize = 256; end
            if ~isfield(options, 'MaxLevels');          options.MaxLevels = 8; end
            if ~isfield(options, 'ChunkSize');          options.ChunkSize = [256 256 16]; end
            if ~isfield(options, 'ShardSize');          options.ShardSize = []; end
            if ~isfield(options, 'Compressors');        options.Compressors = 'zstd'; end
            if ~isfield(options, 'DownsampleMethod');   options.DownsampleMethod = 'bilinear'; end
            if ~isfield(options, 'DownsampleStrategy'); options.DownsampleStrategy = 'XY only'; end

            isLabelLayer = (isfield(options,'layerType') && strcmp(options.layerType,'labels')) || ...
                (isstruct(metadata) && isfield(metadata,'materialNames') && ~isempty(metadata.materialNames));
            if isLabelLayer && ~ismember(options.DownsampleMethod, {'nearest', 'mode'})
                options.DownsampleMethod = 'nearest';
            end

            pixSize = struct('x', 1, 'y', 1, 'z', 1);
            if isstruct(metadata) && isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                ps = metadata.pixSize;
                if isfield(ps,'x'); pixSize.x = ps.x; end
                if isfield(ps,'y'); pixSize.y = ps.y; end
                if isfield(ps,'z'); pixSize.z = ps.z; end
            end

            sz = provider.OutputSize;
            Y = sz(1); X = sz(2); Z = sz(3); C = sz(4); T = sz(5);
            imgClass = provider.DataClass;

            axesNames = {'y','x','z'}; axesTypes = {'space','space','space'};
            if C > 1; axesNames{end+1} = 'c'; axesTypes{end+1} = 'channel'; end
            if T > 1; axesNames{end+1} = 't'; axesTypes{end+1} = 'time'; end
            nKeep = numel(axesNames);

            % build per-level size/scale plan (honours DownsampleStrategy)
            plan    = io.savers.Zarr3Saver.computeLevelPlan(Y, X, Z, pixSize, options);
            nLevels = numel(plan);

            filename = char(filename);
            zarrFormat = io.savers.Zarr3Saver.resolveZarrFormat(filename, options);
            if isfolder(filename); rmdir(filename, 's'); end
            grp = io.zarr.Group.create(filename, 'zarrFormat', zarrFormat);

            % --- create every level array up front ---
            levelInfo = repmat(struct('Yl', Y, 'Xl', X, 'Zl', Z, 'arr', [], 'name', '', 'chunkZ', 1), 1, nLevels);
            datasets  = cell(1, nLevels);
            for L = 1:nLevels
                Yl = plan(L).Yl; Xl = plan(L).Xl; Zl = plan(L).Zl;
                keepShape = [Yl, Xl, Zl];
                if C > 1; keepShape(end+1) = C; end %#ok<AGROW>
                if T > 1; keepShape(end+1) = T; end %#ok<AGROW>
                chunk = min(options.ChunkSize(1:3), keepShape(1:3));
                chunk = max(chunk, [1 1 1]);
                if numel(keepShape) > 3; chunk = [chunk, keepShape(4:end)]; end %#ok<AGROW>
                name = num2str(L - 1);
                levelInfo(L).Yl = Yl; levelInfo(L).Xl = Xl; levelInfo(L).Zl = Zl; levelInfo(L).name = name;
                levelInfo(L).chunkZ = chunk(3);
                createArgs = {'chunkShape', chunk, 'compressors', options.Compressors};
                if ~isempty(options.ShardSize)
                    createArgs = [createArgs, {'shardShape', io.savers.Zarr3Saver.computeShard(chunk, options.ShardSize)}]; %#ok<AGROW>
                end
                levelInfo(L).arr = grp.createArray(name, keepShape, imgClass, createArgs{:});
                scaleVec = [plan(L).physScaleY, plan(L).physScaleX, plan(L).physScaleZ];
                if C > 1; scaleVec(end+1) = 1; end %#ok<AGROW>
                if T > 1; scaleVec(end+1) = 1; end %#ok<AGROW>
                datasets{L} = struct('path', name, ...
                    'coordinateTransformations', {{struct('type', 'scale', 'scale', scaleVec)}});
            end

            % --- stream slices: write each (z,t) to every level ---
            % Levels with cumZFactor > 1 require Z accumulation: buffer groupSize
            % source slices, average them, to produce one output Z-slice.
            %
            % Output slices are NOT written to disk one at a time: a zarr chunk is
            % compressed as a unit, so a 1-slice-thick region write forces a full
            % decompress + splice + recompress of the ENTIRE chunk it lands in -
            % repeated once per Z-slice inside that chunk (chunkZ-fold redundant
            % work). Instead, output slices are buffered per level up to that
            % level's chunk Z-thickness (``levelInfo(L).chunkZ``) and flushed as one
            % region write per full chunk, mirroring how the legacy Python pipeline
            % (ImageConverter.processZChunk) always writes whole Z-chunks.
            zGroupSizes = arrayfun(@(p) p.cumZFactor, plan);
            zBuffers    = cell(1, nLevels);   % {Yl×Xl×C} source slices pending Z-downsampling, per level
            writeBatch  = cell(1, nLevels);   % {Yl×Xl×C} output slices pending a chunk-aligned write, per level
            writeStart  = ones(1, nLevels);   % 1-based Z index where the pending writeBatch{L} begins

            wb = obj.createProgressDialog('Saving Zarr3...', sprintf('Writing %s', filename), true);
            total = Z * T; done = 0;
            for t = 1:T
                for L = 1:nLevels; zBuffers{L} = {}; writeBatch{L} = {}; end
                writeStart(:) = 1;

                for z = 1:Z
                    if ~isempty(wb) && wb.CancelRequested; delete(wb); fnOut = []; return; end
                    slice = provider.getSlice(z, t);   % [Y X C]

                    for L = 1:nLevels
                        Yl = levelInfo(L).Yl; Xl = levelInfo(L).Xl;
                        groupSize = zGroupSizes(L);

                        if L == 1
                            xySlice = slice;
                        elseif ismember(options.DownsampleMethod, {'mode', 'median'})
                            xySlice = io.savers.Zarr3Saver.blockReduce2D( ...
                                slice, Yl, Xl, str2func(options.DownsampleMethod));
                        else
                            xySlice = imresize(slice, [Yl Xl], options.DownsampleMethod);
                        end

                        if groupSize == 1
                            outputSlice = xySlice;
                            haveOutputSlice = true;
                        else
                            zBuffers{L}{end+1} = xySlice;
                            haveOutputSlice = numel(zBuffers{L}) == groupSize;
                            if haveOutputSlice
                                outputSlice = io.savers.Zarr3Saver.reduceZBuffer( ...
                                    zBuffers{L}, options.DownsampleMethod, imgClass, Yl, Xl, C);
                                zBuffers{L} = {};
                            end
                        end

                        if haveOutputSlice
                            writeBatch{L}{end+1} = outputSlice;
                            if numel(writeBatch{L}) == levelInfo(L).chunkZ
                                io.savers.Zarr3Saver.writeStreamBatch( ...
                                    levelInfo(L).arr, writeBatch{L}, writeStart(L), t, C, T, Yl, Xl, imgClass);
                                writeStart(L) = writeStart(L) + numel(writeBatch{L});
                                writeBatch{L} = {};
                            end
                        end
                    end

                    done = done + 1;
                    if ~isempty(wb); wb.Value = done/total; end
                end

                % fold in the trailing partial Z-downsampling group (edge case: Z not
                % divisible by groupSize), then flush any remaining partial write batch
                % (edge case: number of output slices not divisible by chunkZ).
                for L = 1:nLevels
                    if ~isempty(zBuffers{L})
                        outputSlice = io.savers.Zarr3Saver.reduceZBuffer( ...
                            zBuffers{L}, options.DownsampleMethod, imgClass, ...
                            levelInfo(L).Yl, levelInfo(L).Xl, C);
                        writeBatch{L}{end+1} = outputSlice;
                    end
                    if ~isempty(writeBatch{L})
                        io.savers.Zarr3Saver.writeStreamBatch( ...
                            levelInfo(L).arr, writeBatch{L}, writeStart(L), t, C, T, ...
                            levelInfo(L).Yl, levelInfo(L).Xl, imgClass);
                    end
                end
            end
            if ~isempty(wb); delete(wb); end

            % --- OME-NGFF multiscales (+ materials for labels) ---
            axesCells = cell(1, nKeep);
            for a = 1:nKeep; axesCells{a} = struct('name', axesNames{a}, 'type', axesTypes{a}); end
            ms = struct('version', '0.4', 'axes', {axesCells}, 'datasets', {datasets});
            attrStruct = struct('multiscales', {{ms}});
            if isLabelLayer && isstruct(metadata) && isfield(metadata,'materialNames') && ~isempty(metadata.materialNames)
                mm = struct('materialNames', {metadata.materialNames});
                if isfield(metadata,'materialColors') && ~isempty(metadata.materialColors)
                    mm.materialColors = metadata.materialColors;
                end
                attrStruct.mibMaterials = mm;
            end
            grp.setAttributes(attrStruct);

            fnOut = filename;
            fprintf('Zarr3Saver: streamed → %s\n', filename);
        end
    end

    methods (Access = private)
        function [options, cancelled] = resolveExportOptions(obj, options, metadata, sizeYXZ)
            % RESOLVEEXPORTOPTIONS - show the zarr3 export-settings dialog when interactive.
            %
            % Brings the generic "Save image/model as… → OME-Zarr v3" path in line with
            % the "Export to Zarr3" ribbon action: when called from a GUI save (a valid
            % ``ParentFigure``, not ``silent``) and the caller has not already supplied
            % pyramid/chunk/compression settings, it shows ``Zarr3Saver.optionsDialog``
            % and merges the result into ``options``. Returns ``cancelled = true`` if the
            % user cancels. Headless/scripted use (no ``ParentFigure``), batch/``silent``
            % calls, and pre-configured option structs all skip the dialog.
            %
            % ``sizeYXZ`` - [Y X Z] of the data being saved; forwarded (with
            % ``metadata.pixSize``) as ``optionsDialog``'s ``datasetInfo`` so the smart
            % chunk/shard/strategy defaults (WSI / isotropic / anisotropic 3-D) match
            % what the ribbon "Export to Zarr3" / "Export model to Zarr3" actions show
            % for the same dataset - omitting it silently falls back to the isotropic
            % preset regardless of the data's actual shape or voxel size.
            cancelled = false;
            if isfield(options,'silent') && options.silent; return; end
            if isempty(obj.ParentFigure); return; end   % headless/scripted → use defaults
            % settings already provided (e.g. by the Export-ribbon optionsDialog)?
            if isfield(options,'ChunkSize') || isfield(options,'Compressors') || isfield(options,'Levels')
                return;
            end
            isModel = (isfield(options,'layerType') && strcmp(options.layerType,'labels')) || ...
                (isstruct(metadata) && isfield(metadata,'materialNames') && ~isempty(metadata.materialNames));
            datasetInfo = [];
            if nargin >= 4 && numel(sizeYXZ) == 3 && isstruct(metadata) && isfield(metadata,'pixSize')
                datasetInfo = struct('Y', sizeYXZ(1), 'X', sizeYXZ(2), 'Z', sizeYXZ(3), ...
                    'pixSize', metadata.pixSize);
            end
            dlgOptions = io.savers.Zarr3Saver.optionsDialog(obj.ParentFigure, obj.mibPath, isModel, datasetInfo);
            if isempty(dlgOptions); cancelled = true; return; end
            fn = fieldnames(dlgOptions);
            for k = 1:numel(fn); options.(fn{k}) = dlgOptions.(fn{k}); end
        end
    end

    methods (Static)
        function fnOut = exportDataset(mibModel, datasetId, filename, options)
            % EXPORTDATASET - write an open dataset's image to a zarr3 pyramid.
            %
            % Convenience wrapper used by the UI entry points (the dataset-type
            % dropdown "Convert to BigData" and the Export ribbon menu). Gathers
            % the dataset's full image volume into memory and writes it with
            % ``save``. Voxel size is taken from the image's ``pixSize``.
            %
            % Input Arguments:
            %   - **mibModel** - the ``models.MibModel`` instance.
            %   - **datasetId** - *(optional)* dataset index; default = active id.
            %   - **filename** - [char] output ``.zarr3`` path.
            %   - **options** - *(optional)* struct forwarded to ``save`` (Levels,
            %     ChunkSize, Compressors, …).
            %
            % Output Arguments:
            %   - **fnOut** - [char] the written group path.
            %
            % NOTE: gathers the whole volume into memory - fine for Standard
            % datasets; out-of-core streaming for huge sources is future work.
            if nargin < 4; options = struct(); end
            if nargin < 3 || isempty(filename); error('io:Zarr3Saver:noFilename', 'Output filename is required'); end
            if nargin < 2 || isempty(datasetId); datasetId = mibModel.getActiveId(); end

            ds = mibModel.I{datasetId};
            data = ds.getData4D('image', 3, NaN);   % full [y x z c t]; returns a cell
            if iscell(data); data = data{1}; end
            meta = struct('pixSize', ds.image.pixSize);
            fnOut = io.savers.Zarr3Saver().save(data, meta, filename, options);
        end

        function fnOut = exportModel(mibModel, datasetId, filename, options)
            % EXPORTMODEL - write an open dataset's MODEL (labels) to a zarr3 pyramid.
            %
            % Gathers the material-index label volume and writes it as an
            % OME-Zarr v3 multiscales pyramid with **nearest-neighbour**
            % downsampling (labels are categorical), then stores material names
            % and colours in a ``mibMaterials`` attribute (same convention as
            % ``core.MibBigDataLabels``).
            %
            % Input/Output mirror ``exportDataset``; ``DownsampleMethod`` is
            % forced to ``'nearest'``.
            if nargin < 4; options = struct(); end
            if nargin < 3 || isempty(filename); error('io:Zarr3Saver:noFilename', 'Output filename is required'); end
            if nargin < 2 || isempty(datasetId); datasetId = mibModel.getActiveId(); end

            ds = mibModel.I{datasetId};
            if ~ds.modelExist
                error('io:Zarr3Saver:noModel', 'There is no model to export.');
            end
            data = ds.getData4D('labels', 3, NaN);   % material indices, [y x z 1 t]; returns a cell
            if iscell(data); data = data{1}; end
            if ~isfield(options, 'DownsampleMethod') || ~ismember(options.DownsampleMethod, {'nearest', 'mode'})
                options.DownsampleMethod = 'nearest';   % default for categorical data
            end
            meta = struct('pixSize', ds.image.pixSize);
            fnOut = io.savers.Zarr3Saver().save(data, meta, filename, options);

            % persist material names/colours alongside the pyramid (best-effort)
            try
                grp = io.zarr.Group(char(fnOut));
                attrs = grp.getAttributes();      % preserve multiscales
                names = ds.labels.materialNames;
                if isempty(names); names = {}; end
                mm = struct('materialNames', {names});
                if ~isempty(ds.labels.materialColors); mm.materialColors = ds.labels.materialColors; end
                attrs.mibMaterials = mm;
                grp.setAttributes(attrs);
            catch
            end
        end

        function options = optionsDialog(parentFig, mibPath, isModel, datasetInfo, presetDefaults)
            % OPTIONSDIALOG - collect zarr3 export settings; returns [] if cancelled.
            %
            % Shared by the image/model export menus, the "Convert to BigData"
            % dropdown, and BigData alignment. When ``isModel`` is true, the method
            % is restricted to
            % 'nearest' or 'mode' (labels are categorical). The downsampling
            % *strategy* (XY only vs. Anisotropy-preserving) is offered for both -
            % model reads use their own per-axis ``modelScaleFactors`` (see
            % ``MibBigDataLabels.getData63``), so a model pyramid can shrink Z the
            % same way an image pyramid does. Pick the same strategy as the paired
            % image export (default filename ``Labels_<image>.zarr3``) so the two
            % pyramids' level shapes line up.
            %
            % **datasetInfo** (optional struct, fields ``Y``, ``X``, ``Z``, ``pixSize``)
            % drives smart defaults for chunk size, sharding, and downsampling strategy:
            %   - WSI  (Z <= 2 or max(Y,X) >= 8000): chunk 512×512×1, shard factors 4×4×1
            %   - 3-D anisotropic (vxZ >= 2× vxXY):  chunk 256×256×16, strategy 'Anisotropy-preserving'
            %   - 3-D isotropic   (vxZ <  2× vxXY):  chunk 128×128×64, strategy 'XY only'
            %
            % **Downsampling strategy:**
            %   - ``XY only`` - halves X & Y at every level, Z stays constant.
            %   - ``Anisotropy-preserving`` - halves XY until voxels are near-isotropic,
            %     then also halves Z to keep the aspect ratio ~1 at coarser levels.
            %     Recommended for 3-D datasets where vxZ >> vxXY.
            %
            % **Pyramid levels - auto rule (when "Pyramid levels" = 0):** level 0 is
            % full resolution; levels are added while the next halving keeps
            % ``min(Y, X) >= 256 px``, capped at 8 levels. A fixed count (1..12) overrides.
            %
            % **Sharding:** a shard is a single file holding a grid of chunks (zarr v3
            % sharding codec). Shard size 0 = no sharding; otherwise each axis is rounded
            % up to a whole multiple of the chunk size.
            %
            % **presetDefaults** (optional struct) pre-fills the dialog fields with an
            % existing dataset's actual settings (used by BigData alignment to seed the
            % dialog from the open dataset instead of the dimension heuristics). Any of
            % ``Levels``, ``ChunkSize`` [y x z], ``ShardSize`` [y x z] (empty/absent = off),
            % ``Compressors``, ``DownsampleMethod``, ``DownsampleStrategy`` overrides the
            % corresponding heuristic default.
            %
            % Output Arguments:
            %   - **options** - struct with fields ``Levels`` (omitted when auto),
            %     ``ChunkSize`` [y x z], ``ShardSize`` [y x z] (omitted when no sharding),
            %     ``Compressors``, ``DownsampleMethod``, ``DownsampleStrategy``;
            %     ``[]`` when cancelled.
            if nargin < 5; presetDefaults = []; end
            if nargin < 4; datasetInfo = []; end
            if nargin < 3; isModel = false; end
            if nargin < 2; mibPath = ''; end

            % --- smart defaults from dataset info ---
            if ~isempty(datasetInfo) && isstruct(datasetInfo) && ...
                    isfield(datasetInfo, 'Y') && isfield(datasetInfo, 'Z') && isfield(datasetInfo, 'pixSize')
                isWSI = datasetInfo.Z <= 2 || max(datasetInfo.Y, datasetInfo.X) >= 8000;
                ps = datasetInfo.pixSize;
                vxXY = max(ps.x, ps.y);
                if vxXY <= 0; vxXY = 1; end
                vxRatio = ps.z / vxXY;
            else
                isWSI = false;
                vxRatio = 1;
            end

            if isWSI
                defaultChunk    = '512, 512, 1';
                defaultShard    = '4, 4, 1';
                defaultStrategy = 'XY only';
            elseif vxRatio < 2
                defaultChunk    = '128, 128, 64';
                defaultShard    = '4, 4, 1';
                defaultStrategy = 'XY only';
            else
                defaultChunk    = '256, 256, 16';
                defaultShard    = '4, 4, 1';
                if vxRatio >= 1.5
                    defaultStrategy = 'Anisotropy-preserving';
                else
                    defaultStrategy = 'XY only';
                end
            end

            % Conditional header + method items depending on whether this is a model export
            % (the downsampling *strategy* explanation/prompt is shared by both - see
            % the function header comment on why models are not restricted to XY-only)
            if isModel
                methodLines = { ...
                    '"nearest" (fast): picks the nearest source pixel - preserves exact'; ...
                    'label integers, recommended for most models.'; ...
                    '"mode" (slow, precise): dominant label value per block (majority vote)'; ...
                    '- best semantic accuracy for fine structures or thin boundaries.'};
                methodItems = {'nearest (fast)', 'mode (precise, very slow)'};
            else
                methodLines = { ...
                    '"median": median value per block - noise-robust, preserves edges'; ...
                    'better than bilinear; does not produce new pixel values.'; ...
                    '"mode": dominant value per block (majority vote) - for categorical'; ...
                    'labels exported as images; slower than "nearest".'};
                methodItems = {'bilinear (fast, smooth)', 'nearest (fast)', ...
                               'bicubic (slower, sharp)', 'median (very slow, noise-robust)', ...
                               'mode (precise, very slow)'};
            end
            headerLines = [{ ...
                    'Pyramid levels = 0 (auto): adds levels while min(Y,X)/2 >= 256 px'; ...
                    '(up to 8); a fixed count (1-12) overrides.'; ...
                    ''}; ...
                    methodLines; ...
                    { ''; ...
                    'Strategy "XY only": halves X & Y at every level, Z constant.'; ...
                    '"Anisotropy-preserving": halves XY until voxels near-isotropic,'; ...
                    'then also halves Z - keeps aspect ratio ~1 at coarser levels. Use the'; ...
                    'same strategy as the paired image export so the level shapes match.'; ...
                    ''; ...
                    'Shard X-factors [Y,X,Z]: how many chunks to bundle per axis into'; ...
                    'one shard file (e.g. 4,4,1 = 16 chunks/file in XY). 0 = off.'}];
            header = strjoin(headerLines, newline);

            prompts = {'Pyramid levels (0 = auto):'; 'Chunk size [Y, X, Z]:'; ...
                       'Shard X-factors [Y, X, Z] (0 = off):'; 'Compression:'; ...
                       'Downsampling method:'; 'Downsampling strategy:'};
            strategyItems   = {'XY only', 'Anisotropy-preserving'};
            compressorItems = {'zstd', 'gzip', 'none'};

            % --- override the heuristic defaults with an existing dataset's settings ---
            levelDefault      = 0;   % 0 = auto
            compressorDefault = 1;
            methodDefault     = 1;
            if ~isempty(presetDefaults) && isstruct(presetDefaults)
                if isfield(presetDefaults, 'Levels') && ~isempty(presetDefaults.Levels)
                    levelDefault = presetDefaults.Levels;
                end
                if isfield(presetDefaults, 'ChunkSize') && numel(presetDefaults.ChunkSize) == 3
                    defaultChunk = sprintf('%d, %d, %d', round(presetDefaults.ChunkSize));
                end
                if isfield(presetDefaults, 'DownsampleStrategy') && ~isempty(presetDefaults.DownsampleStrategy)
                    defaultStrategy = presetDefaults.DownsampleStrategy;
                end
                if isfield(presetDefaults, 'DownsampleMethod') && ~isempty(presetDefaults.DownsampleMethod)
                    mi = find(startsWith(methodItems, presetDefaults.DownsampleMethod), 1);
                    if ~isempty(mi); methodDefault = mi; end
                end
                if isfield(presetDefaults, 'Compressors') && ~isempty(presetDefaults.Compressors)
                    ci = find(strcmp(compressorItems, presetDefaults.Compressors), 1);
                    if ~isempty(ci); compressorDefault = ci; end
                end
                % shard is entered as per-axis chunk multipliers; convert from absolute
                if isfield(presetDefaults, 'ShardSize')
                    if numel(presetDefaults.ShardSize) == 3 && numel(presetDefaults.ChunkSize) == 3
                        mult = max(1, round(presetDefaults.ShardSize(:)' ./ max(1, presetDefaults.ChunkSize(:)')));
                        defaultShard = sprintf('%d, %d, %d', mult);
                    else
                        defaultShard = '0, 0, 0';   % explicitly no sharding
                    end
                end
            end

            defaultStrategyIdx = find(strcmp(strategyItems, defaultStrategy), 1);
            if isempty(defaultStrategyIdx); defaultStrategyIdx = 1; end
            defAns  = {struct('Spinner', true, 'Value', levelDefault, 'Limits', [0 12], 'Step', 1, 'Round', true); ...
                       defaultChunk; ...
                       defaultShard; ...
                       [compressorItems, {compressorDefault}]; ...
                       [methodItems, {methodDefault}]; ...
                       [strategyItems, {defaultStrategyIdx}]};

            dlgOpts = struct('LabelPosition', 'left', 'WindowWidth', 560, ...
                'HeaderLines', numel(headerLines));
            if ~isempty(mibPath); dlgOpts.mibPath = mibPath; end
            answer = utils.dlgs.inputUniversalDlg(parentFig, header, ...
                prompts, defAns, 'Export to Zarr3', dlgOpts);
            if isempty(answer); options = []; return; end

            options = struct();
            if answer{1} > 0; options.Levels = answer{1}; end       % 0 -> auto
            chunk = str2num(answer{2}); %#ok<ST2NM>
            if numel(chunk) == 3; options.ChunkSize = chunk; end
            shard = str2num(answer{3}); %#ok<ST2NM>
            if numel(shard) == 3 && all(shard > 0); options.ShardSize = shard; end   % 0 = no sharding
            options.Compressors = answer{4};
            % strip the parenthetical note from method items (e.g. 'nearest (fast)' → 'nearest')
            options.DownsampleMethod = strtok(answer{5}, ' ');
            options.DownsampleStrategy = answer{6};
        end

        function zarrFormat = resolveZarrFormat(filename, options)
            % RESOLVEZARRFORMAT - which zarr format to write, and is it consistent?
            %
            % The output extension chooses the format - ``.zarr2`` writes zarr
            % v2, anything else v3 - matching the rule
            % ``core.MibBigDataLabels.zarrFormatFromPath`` applies to model
            % stores. ``options.ZarrFormat`` overrides it when a caller needs to
            % be explicit.
            %
            % Sharding is rejected here rather than deep inside ``ZarrArray``,
            % so the message can name the extension that selected v2. Zarr v2
            % has no sharding codec at all; silently dropping the setting would
            % write a store with a different chunk layout than was asked for.
            %
            % Input Arguments:
            %   - **filename** - [char] output group path.
            %   - **options** - [struct] saver options; ``.ZarrFormat`` and
            %     ``.ShardSize`` are consulted.
            %
            % Output Arguments:
            %   - **zarrFormat** - [numeric] 2 or 3.

            if isstruct(options) && isfield(options, 'ZarrFormat') && ~isempty(options.ZarrFormat)
                zarrFormat = double(options.ZarrFormat);
                if ~ismember(zarrFormat, [2, 3])
                    error('io:Zarr3Saver:zarrFormat', ...
                        'options.ZarrFormat must be 2 or 3, got %g.', zarrFormat);
                end
            else
                zarrFormat = core.MibBigDataLabels.zarrFormatFromPath(filename);
            end

            if zarrFormat == 2 && isstruct(options) && isfield(options, 'ShardSize') ...
                    && ~isempty(options.ShardSize) && any(options.ShardSize > 0)
                error('io:Zarr3Saver:shardingUnsupportedV2', ...
                    ['Sharding was requested, but the output is Zarr v2, which has no sharding\n' ...
                     'codec:\n  %s\n\n' ...
                     'Either write Zarr v3 instead, or turn sharding off in the export settings.'], ...
                    filename);
            end
        end

        function shard = computeShard(chunk, shardMultiplier)
            % COMPUTESHARD - compute per-axis shard shape from chunk multipliers.
            %
            % ``shardMultiplier`` is a [y x z] integer vector where each value says how
            % many chunks to bundle per axis (e.g. [4 4 1] → 4 chunks in Y, 4 in X,
            % 1 in Z per shard file). Colour/time axes keep the chunk extent.
            % ``shard`` has the same length as ``chunk``.
            shard = chunk;
            n = min(3, numel(shardMultiplier));
            for i = 1:n
                if shardMultiplier(i) > 0
                    shard(i) = chunk(i) * max(1, round(shardMultiplier(i)));
                end
            end
        end

        function plan = computeLevelPlan(Y, X, Z, pixSize, options)
            % COMPUTELEVELPLAN - build per-level size/scale table for the pyramid.
            %
            % Returns a struct array ``plan`` with one entry per pyramid level.
            % Each entry has fields:
            %   - ``Yl``, ``Xl``, ``Zl``       - pixel dimensions at this level
            %   - ``cumXYFactor``, ``cumZFactor`` - cumulative scale vs level 0
            %   - ``physScaleY``, ``physScaleX``, ``physScaleZ`` - physical voxel size
            %
            % Options fields consumed:
            %   - ``DownsampleStrategy`` - 'XY only' (default) | 'Anisotropy-preserving'
            %   - ``Levels``             - explicit level count (overrides auto when > 0)
            %   - ``MinLevelSize``       - auto stop when min(Y,X) would drop below this (default 256)
            %   - ``MaxLevels``          - hard cap on level count (default 8)
            if ~isfield(options, 'DownsampleStrategy'); options.DownsampleStrategy = 'XY only'; end
            if ~isfield(options, 'MinLevelSize');       options.MinLevelSize = 256; end
            if ~isfield(options, 'MaxLevels');          options.MaxLevels = 8; end

            vxXY = max(pixSize.x, pixSize.y);
            if vxXY <= 0; vxXY = 1; end
            vxZ  = pixSize.z;
            if vxZ  <= 0; vxZ  = 1; end

            curY  = Y;    curX  = X;    curZ  = Z;
            curVxXY = vxXY;  curVxZ = vxZ;
            cumXYFactor = 1;  cumZFactor = 1;

            plan = struct('Yl', Y, 'Xl', X, 'Zl', Z, ...
                'cumXYFactor', 1, 'cumZFactor', 1, ...
                'physScaleY', pixSize.y, 'physScaleX', pixSize.x, 'physScaleZ', pixSize.z);

            useExplicit = isfield(options, 'Levels') && ~isempty(options.Levels) && options.Levels > 0;

            while true
                % stop conditions
                if useExplicit
                    if numel(plan) >= options.Levels; break; end
                else
                    if min(floor(curY/2), floor(curX/2)) < options.MinLevelSize; break; end
                    if numel(plan) >= options.MaxLevels; break; end
                end

                nextVxXY = curVxXY * 2;
                doZ = strcmp(options.DownsampleStrategy, 'Anisotropy-preserving') && ...
                    curZ > 1 && nextVxXY > curVxZ;

                cumXYFactor = cumXYFactor * 2;
                curY = max(1, round(curY / 2));
                curX = max(1, round(curX / 2));
                curVxXY = nextVxXY;

                if doZ
                    cumZFactor = cumZFactor * 2;
                    % ceil, not floor: saveStream buffers cumZFactor source slices per
                    % output slice and always flushes a trailing partial group, so the
                    % level's Zl must match that count exactly (floor would allocate one
                    % slice short of what the streamed flush writes, an out-of-bounds
                    % write when Z is not a multiple of cumZFactor).
                    curZ = max(1, ceil(Z / cumZFactor));
                    curVxZ = curVxZ * 2;
                end

                plan(end+1) = struct('Yl', curY, 'Xl', curX, 'Zl', curZ, ...  %#ok<AGROW>
                    'cumXYFactor', cumXYFactor, 'cumZFactor', cumZFactor, ...
                    'physScaleY', pixSize.y * cumXYFactor, ...
                    'physScaleX', pixSize.x * cumXYFactor, ...
                    'physScaleZ', pixSize.z * cumZFactor);
            end
        end

        function patchMetadata(zarrPath, pixSize, boundingBox)
            % PATCHMETADATA - Update bounding box and pixel sizes in a zarr3 file on disk.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      io.savers.Zarr3Saver.patchMetadata(zarrPath, pixSize, boundingBox)
            %
            % Writes to the zarr.json attributes:
            %   - ``mibBoundingBox`` [xmin xmax ymin ymax zmin zmax] (MIB-specific round-trip)
            %   - ``translation`` coordinateTransformation per pyramid level (OME-NGFF 0.5)
            %   - Updated ``scale`` per pyramid level from new ``pixSize``
            %
            % Input Arguments:
            %   - **zarrPath** - [char] local path to the zarr3 root folder
            %   - **pixSize** - [struct] with fields ``.x``, ``.y``, ``.z``
            %   - **boundingBox** - [1x6 double] ``[xmin xmax ymin ymax zmin zmax]``
            %
            % Output Arguments:
            %   (none)
            %

            if isempty(zarrPath) || ~isfolder(zarrPath); return; end
            if startsWith(zarrPath, 'http://') || startsWith(zarrPath, 'https://'); return; end
            jsonPath = fullfile(zarrPath, 'zarr.json');
            if ~isfile(jsonPath); return; end

            try
                rawMeta = jsondecode(fileread(jsonPath));
                if isfield(rawMeta, 'attributes') && isstruct(rawMeta.attributes)
                    attrs = rawMeta.attributes;
                else
                    attrs = struct();
                end

                % ---- locate multiscales -----------------------------------------
                ms = [];
                msLocation = '';  % 'direct' or 'ome'
                if isfield(attrs, 'multiscales') && ~isempty(attrs.multiscales)
                    ms = attrs.multiscales(1);
                    msLocation = 'direct';
                elseif isfield(attrs, 'ome') && isstruct(attrs.ome) && ...
                        isfield(attrs.ome, 'multiscales') && ~isempty(attrs.ome.multiscales)
                    ms = attrs.ome.multiscales(1);
                    msLocation = 'ome';
                end

                if isempty(ms) || ~isfield(ms, 'datasets')
                    warning('io:Zarr3Saver:patchMetadata:noMultiscales', ...
                        'patchMetadata: no multiscales in %s - skipped.', zarrPath);
                    return;
                end

                % ---- parse axis order ------------------------------------------
                axisLabels = {};
                if isfield(ms, 'axes') && ~isempty(ms.axes)
                    axesDef = ms.axes;
                    if isstruct(axesDef)
                        names = {axesDef.name};
                    else
                        names = cellfun(@(a) a.name, axesDef, 'UniformOutput', false);
                    end
                    axisLabels = num2cell(lower(char(strjoin(names, ''))));
                end
                if isempty(axisLabels)
                    axisLabels = {'y', 'x', 'z'};
                end
                nAxes = numel(axisLabels);
                yIdx = find(strcmp(axisLabels, 'y'), 1);
                xIdx = find(strcmp(axisLabels, 'x'), 1);
                zIdx = find(strcmp(axisLabels, 'z'), 1);

                % ---- translation vector (same for all levels) ------------------
                translationVec = zeros(1, nAxes);
                if ~isempty(yIdx); translationVec(yIdx) = boundingBox(3); end
                if ~isempty(xIdx); translationVec(xIdx) = boundingBox(1); end
                if ~isempty(zIdx); translationVec(zIdx) = boundingBox(5); end

                % ---- read level-0 scale (used to compute per-level ratios) -----
                nLevels = numel(ms.datasets);
                ct0 = ms.datasets(1).coordinateTransformations;
                level0Scales = io.savers.Zarr3Saver.extractScaleVec(ct0, nAxes);

                % ---- update each level -----------------------------------------
                for levelIdx = 1:nLevels
                    ct = ms.datasets(levelIdx).coordinateTransformations;
                    oldScale = io.savers.Zarr3Saver.extractScaleVec(ct, nAxes);

                    % scale ratio relative to level 0 (preserves pyramid structure)
                    scaleRatio = max(oldScale ./ max(level0Scales, eps(1)), eps(1));

                    newScaleVec = ones(1, nAxes);
                    if ~isempty(yIdx); newScaleVec(yIdx) = pixSize.y * scaleRatio(yIdx); end
                    if ~isempty(xIdx); newScaleVec(xIdx) = pixSize.x * scaleRatio(xIdx); end
                    if ~isempty(zIdx); newScaleVec(zIdx) = pixSize.z * scaleRatio(zIdx); end

                    scaleSt       = struct('type', 'scale',       'scale',       newScaleVec);
                    translationSt = struct('type', 'translation', 'translation', translationVec);
                    % use cell array so jsonencode produces [{...},{...}] without
                    % null fields from mixed-field struct arrays
                    ms.datasets(levelIdx).coordinateTransformations = {scaleSt, translationSt};
                end

                % ---- write back ------------------------------------------------
                if strcmp(msLocation, 'direct')
                    attrs.multiscales(1) = ms;
                else
                    attrs.ome.multiscales(1) = ms;
                end
                attrs.mibBoundingBox = reshape(double(boundingBox), 1, 6);

                grp = ZarrGroup(zarrPath);
                grp.setAttributes(attrs);

            catch ME
                warning('io:Zarr3Saver:patchMetadata:failed', ...
                    'patchMetadata failed for %s: %s', zarrPath, ME.message);
            end
        end
    end

    methods (Static, Access = private)
        function writeStreamBatch(arr, batchCell, zStart, tPos, C, T, Yl, Xl, imgClass)
            % WRITESTREAMBATCH - write a run of consecutive Z-slices to a zarr array in one region write.
            %
            % ``batchCell`` holds 1..chunkZ XY slices (each ``[Yl Xl]`` or ``[Yl Xl C]``),
            % starting at 1-based Z index ``zStart``. Writing them together (rather than
            % one ``arr.write`` call per slice) keeps each touched chunk to a single
            % decompress/recompress cycle instead of one per Z-slice it contains.
            nZ = numel(batchCell);
            batchData = zeros(Yl, Xl, nZ, C, imgClass);
            for i = 1:nZ
                batchData(:,:,i,:) = reshape(cast(batchCell{i}, imgClass), Yl, Xl, 1, C);
            end
            if C == 1; batchData = reshape(batchData, Yl, Xl, nZ); end
            if T > 1
                batchData = reshape(batchData, [size(batchData, 1:max(3, ndims(batchData))), 1]);
            end
            bbox = [1 Yl+1; 1 Xl+1; zStart zStart+nZ];
            if C > 1; bbox = [bbox; 1 C+1]; end
            if T > 1; bbox = [bbox; tPos tPos+1]; end
            arr.write(batchData, bbox);
        end

        function out = blockReduce2D(inputSlice, Yl, Xl, reduceFcn)
            % BLOCKREDDUCE2D - downsample a 2-D (or [H W C]) slice using a per-block reduction.
            %
            % ``reduceFcn`` is a function handle compatible with ``f(matrix, dim)``,
            % e.g. ``@mode`` (majority vote, for labels) or ``@median`` (noise-robust, for images).
            % Fast vectorised reshape for integer scale factors; block-boundary loop otherwise.
            [H, W, C] = size(inputSlice, 1, 2, 3);
            fy = H / Yl;  fx = W / Xl;
            out = zeros(Yl, Xl, C, class(inputSlice));
            if abs(fy - round(fy)) < 1e-9 && abs(fx - round(fx)) < 1e-9
                % Integer factors: fast vectorised path
                fy = round(fy);  fx = round(fx);
                for c = 1:C
                    blk = reshape(inputSlice(:,:,c), fy, Yl, fx, Xl);
                    blk = permute(blk, [1 3 2 4]);          % [fy fx Yl Xl]
                    blk = reshape(blk, fy*fx, Yl*Xl);
                    out(:,:,c) = reshape(reduceFcn(blk, 1), Yl, Xl);
                end
            else
                % Non-integer factors: block-boundary loop
                yBounds = round(linspace(0, H, Yl+1));
                xBounds = round(linspace(0, W, Xl+1));
                for c = 1:C
                    plane = inputSlice(:,:,c);
                    for yi = 1:Yl
                        rows = yBounds(yi)+1 : yBounds(yi+1);
                        for xi = 1:Xl
                            cols = xBounds(xi)+1 : xBounds(xi+1);
                            block = plane(rows, cols);
                            out(yi, xi, c) = reduceFcn(block(:));
                        end
                    end
                end
            end
            if C == 1; out = reshape(out, Yl, Xl); end
        end

        function out = blockReduce3D(inputVol, Yl, Xl, Zl, reduceFcn)
            % BLOCKREDUCE3D - downsample a [H W D] volume by a 3-D per-block reduction.
            %
            % Used for the anisotropy-preserving path where Z is also halved.
            % Fast vectorised reshape for integer scale factors; loop fallback otherwise.
            [H, W, D] = size(inputVol);
            fy = H / Yl;  fx = W / Xl;  fz = D / Zl;
            if abs(fy-round(fy))<1e-9 && abs(fx-round(fx))<1e-9 && abs(fz-round(fz))<1e-9
                fy = round(fy);  fx = round(fx);  fz = round(fz);
                vol = reshape(inputVol, fy, Yl, fx, Xl, fz, Zl);
                vol = permute(vol, [1 3 5 2 4 6]);          % [fy fx fz Yl Xl Zl]
                vol = reshape(vol, fy*fx*fz, Yl*Xl*Zl);
                out = cast(reshape(reduceFcn(vol, 1), Yl, Xl, Zl), class(inputVol));
            else
                yBounds = round(linspace(0, H, Yl+1));
                xBounds = round(linspace(0, W, Xl+1));
                zBounds = round(linspace(0, D, Zl+1));
                out = zeros(Yl, Xl, Zl, class(inputVol));
                for zi = 1:Zl
                    zIdx = zBounds(zi)+1 : zBounds(zi+1);
                    for yi = 1:Yl
                        rows = yBounds(yi)+1 : yBounds(yi+1);
                        for xi = 1:Xl
                            cols = xBounds(xi)+1 : xBounds(xi+1);
                            block = inputVol(rows, cols, zIdx);
                            out(yi, xi, zi) = reduceFcn(block(:));
                        end
                    end
                end
            end
        end

        function result = reduceZBuffer(bufferCell, method, imgClass, Yl, Xl, C)
            % REDUCEZBUFFER - collapse a cell array of Z-slices into one output slice.
            %
            % 'mode'   - majority vote per spatial position (for categorical labels).
            % 'median' - median per spatial position (noise-robust, for images).
            % All other methods - arithmetic mean cast to imgClass.
            if ismember(method, {'mode', 'median'})
                stacked   = cat(4, bufferCell{:});          % [Yl Xl C nAccum]
                flat      = reshape(stacked, [], numel(bufferCell));
                reduceFcn = str2func(method);
                result    = cast(reshape(reduceFcn(flat, 2), Yl, Xl, C), imgClass);
            else
                accumulated = double(bufferCell{1});
                for k = 2:numel(bufferCell)
                    accumulated = accumulated + double(bufferCell{k});
                end
                result = cast(accumulated / numel(bufferCell), imgClass);
            end
        end

        function sc = extractScaleVec(ct, nAxes)
            % EXTRACTSCALEVEC - Extract scale vector from a coordinateTransformations value.
            % ct may be a struct, struct array, or cell array.
            % Returns a right-aligned [1 x nAxes] row vector; defaults to ones.
            sc = [];
            try
                if isstruct(ct) && ~isempty(ct)
                    for k = 1:numel(ct)
                        if isfield(ct(k), 'scale') && strcmp(ct(k).type, 'scale')
                            sc = ct(k).scale; break;
                        end
                    end
                elseif iscell(ct)
                    for k = 1:numel(ct)
                        entry = ct{k};
                        if isfield(entry, 'type') && strcmp(entry.type, 'scale')
                            sc = entry.scale; break;
                        end
                    end
                end
                if isempty(sc); sc = ones(1, nAxes); return; end
                if iscell(sc); sc = cell2mat(sc(:)'); else; sc = double(sc(:)'); end
                nSc = numel(sc);
                if nSc == nAxes
                    % already aligned
                elseif nSc < nAxes
                    padded = ones(1, nAxes);
                    padded(end - nSc + 1 : end) = sc;
                    sc = padded;
                else
                    sc = sc(end - nAxes + 1 : end);
                end
            catch
                sc = ones(1, nAxes);
            end
        end
    end
end
