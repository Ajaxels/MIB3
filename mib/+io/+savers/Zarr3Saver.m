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
% **Axis order.** Arrays are declared with the shape of the native MATLAB
% ``[y, x, z, c, t]`` array, and read/write return that order. The
% ``multiscales.axes`` are declared to match (``y, x, z`` plus ``c`` and/or
% ``t`` only when those dimensions are > 1). ``Zarr3VirtualSetupLoader`` reads
% ``axes.name`` to recover this order, and ``Zarr3VirtualLoader`` applies the
% (identity) permutation - so the round-trip is exact.
%
% **Chunk byte order.** Arrays are created with ``'filters', 'none'``: chunks
% hold their bytes in C order (v3 codecs ``bytes`` + compressor, v2
% ``order: C``), without the zarr-matlab default transpose codec. The logical
% array is the same either way - only the byte layout inside a chunk differs -
% and every zarr reader decodes both. C order is chosen for speed: zarrMex
% writes it ~2.5x faster than through the transpose codec (measured,
% development/bigdata/plan_imageconverter_zarr.md), and it is the layout other
% tools expect. Stores written earlier with the transpose codec stay readable.
%
% **Pyramid.** Level 0 = full resolution; each further level halves Y and X
% by resizing the level above by exactly 0.5, and halves Z too (mean of each
% pair of slices) when ``DownsampleStrategy`` is ``'Anisotropy-preserving'`` and
% the voxels have become coarser in XY than in Z (``computeLevelPlan``). All
% writers - ``save``, ``saveStream``, ``saveStreamResumable`` - produce the same
% pyramid from the same data (interpolating methods). The per-level
% ``scale`` coordinate transformation encodes the physical voxel size
% (``pixSize`` × 2^level in XY), which the loader turns into the
% magnification→level mapping.
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
            % **Pyramid.** For the interpolating methods each level is computed
            % from the level above: XY by exactly 0.5 (``imresize(..., 0.5)``, the
            % ``2^k`` scale written in the metadata; resizing to ``[Yl Xl]`` would
            % stretch an odd size by ``size/Yl``), and where the level halves Z,
            % the mean of each pair of slices (``reduceZBuffer``; a trailing
            % single slice is kept). This is the pyramid ``saveStreamResumable``
            % writes, so the same data gives the same store from memory and by
            % streaming. ``'mode'``/``'median'`` reduce blocks of the
            % full-resolution data (``blockReduce2D``/``blockReduce3D``).
            %
            % Input Arguments:
            %   - **data** - [y x z c t] numeric image array (full resolution).
            %   - **metadata** - struct; uses ``.pixSize`` (``.x .y .z``) when present, and
            %     ``.boundingBox`` (``[xmin xmax ymin ymax zmin zmax]``) when it has 6 values,
            %     stored as ``mibBoundingBox`` plus a per-level ``translation``. Without
            %     it the store opens with its origin at 0.
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
                elseif ismember(options.DownsampleMethod, {'mode', 'median'})
                    % block reduction from the full-resolution data
                    reduceFcn = str2func(options.DownsampleMethod);
                    lvl = zeros(Yl, Xl, Zl, C, T, imgClass);
                    for t = 1:T
                        for c = 1:C
                            if Zl == Z
                                for z = 1:Z
                                    lvl(:,:,z,c,t) = io.savers.Zarr3Saver.blockReduce2D( ...
                                        data(:,:,z,c,t), Yl, Xl, reduceFcn);
                                end
                            else
                                lvl(:,:,:,c,t) = io.savers.Zarr3Saver.blockReduce3D( ...
                                    data(:,:,:,c,t), Yl, Xl, Zl, reduceFcn);
                            end
                        end
                    end
                else
                    % From the level above: XY by exactly 0.5 - the 2x scale of the
                    % metadata - and, where the level halves Z, the mean of each
                    % pair of slices (reduceZBuffer, a trailing single slice kept).
                    % The same pyramid as saveStreamResumable (buildLevelBand), so
                    % a dataset saved from memory equals one converted by streaming.
                    zFactor = round(plan(L).cumZFactor / plan(L-1).cumZFactor);
                    previousDepth = size(previousLevel, 3);
                    lvl = zeros(Yl, Xl, Zl, C, T, imgClass);
                    for t = 1:T
                        for c = 1:C
                            resized = zeros(Yl, Xl, previousDepth, imgClass);
                            for z = 1:previousDepth
                                resized(:,:,z) = imresize(previousLevel(:,:,z,c,t), 0.5, options.DownsampleMethod);
                            end
                            if zFactor == 1
                                lvl(:,:,:,c,t) = resized;
                            else
                                for outputIndex = 1:Zl
                                    groupSlices = (outputIndex-1)*zFactor+1 : min(outputIndex*zFactor, previousDepth);
                                    group = arrayfun(@(z) resized(:,:,z), groupSlices, 'UniformOutput', false);
                                    lvl(:,:,outputIndex,c,t) = io.savers.Zarr3Saver.reduceZBuffer( ...
                                        group, options.DownsampleMethod, imgClass, Yl, Xl, 1);
                                end
                            end
                        end
                    end
                end
                previousLevel = lvl;   % [y x z c t], before the singleton c/t are dropped

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
                % C byte order, no transpose codec - see "Chunk byte order" in the class help
                createArgs = {'chunkShape', chunk, 'compressors', options.Compressors, 'filters', 'none'};
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
            attrStruct = io.savers.Zarr3Saver.addBoundingBox(attrStruct, metadata);
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
            % extension, or from ``options.ZarrFormat`` when given. Takes the options
            % of ``save``, plus:
            %
            %   - ``.MaterialNamesFromData`` - *(label layers only, default false)*
            %     when ``metadata`` carries no ``materialNames``, name materials
            %     ``Material 1..N`` from the largest label value met while
            %     streaming, so the source is read only once. Opt-in: a stream of
            %     instance ids would otherwise get one material per instance.
            %
            % **Memory.** Output slices are buffered per level up to the depth of
            % one write: the chunk Z-thickness, or the shard Z-thickness when
            % sharded (a partial-shard write re-reads and rewrites the whole shard,
            % measured 3.4x slower). Peak memory is therefore about
            % ``3 x writeDepth`` full-resolution slices (the buffer, the
            % concatenated write array and the copy zarrMex makes while encoding)
            % plus the coarser levels' smaller buffers -
            % callers converting very large slices should check it first (see
            % ``ImageConverter.confirmZarrMemory``).
            %
            % **Interrupted writes.** The group attributes are written before the
            % first slice with ``mibIncomplete = true`` and rewritten without it after
            % the last one, so a store left by a cancel, an error or a crash opens
            % with the full pyramid declared and the Zarr loaders warn that it is
            % incomplete. A cancel returns ``[]`` and leaves that partial store.
            %
            % Each level is computed from the output slices of the level above
            % (cascaded, ~2.6x cheaper than resizing the full slice for every
            % level): XY by exactly 0.5 for the interpolating methods, and where
            % the level halves Z, the mean of each pair of those slices.
            % ``'mode'``/``'median'`` reduce blocks of the full slice while the
            % level keeps the full Z, and of the level above after (see
            % ``reduceSliceXY``). This is the pyramid of ``save`` and
            % ``saveStreamResumable``, so the three writers produce the same store.
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

            [options, isLabelLayer, pixSize] = io.savers.Zarr3Saver.streamDefaults(options, metadata);

            sz = provider.OutputSize;
            Y = sz(1); X = sz(2); Z = sz(3); C = sz(4); T = sz(5);
            imgClass = provider.DataClass;

            % build per-level size/scale plan (honours DownsampleStrategy)
            plan    = io.savers.Zarr3Saver.computeLevelPlan(Y, X, Z, pixSize, options);
            nLevels = numel(plan);

            % every level array created up front, attributes flagged mibIncomplete
            filename = char(filename);
            [grp, levelInfo, attrStruct] = io.savers.Zarr3Saver.createStreamStore( ...
                filename, plan, C, T, imgClass, options, metadata, isLabelLayer);

            % label stores without names: track the largest label while streaming
            trackMaxLabel = isLabelLayer && ~isfield(attrStruct, 'mibMaterials') && ...
                isfield(options, 'MaterialNamesFromData') && options.MaterialNamesFromData;
            maxLabel = 0;

            % --- stream slices: write each (z,t) to every level ---
            % The levels form a cascade: level L takes the output slices of level
            % L-1, reduces each in XY and averages every group of zFactor(L) of
            % them in Z (zFactor = cumZFactor(L) / cumZFactor(L-1), 1 or 2) into
            % one output slice - the pyramid of save and saveStreamResumable
            % (buildLevelBand). A level that produced no output for this source
            % slice (its Z group is still filling) leaves the deeper levels idle.
            %
            % Output slices are NOT written to disk one at a time: a zarr chunk is
            % compressed as a unit, so a 1-slice-thick region write forces a full
            % decompress + splice + recompress of the ENTIRE chunk it lands in -
            % repeated once per Z-slice inside that chunk (chunkZ-fold redundant
            % work). Instead, output slices are buffered per level up to that
            % level's chunk Z-thickness (``levelInfo(L).chunkZ``) and flushed as one
            % region write per full chunk, mirroring how the legacy Python pipeline
            % (ImageConverter.processZChunk) always writes whole Z-chunks.
            cumZFactors = [plan.cumZFactor];
            zFactors    = [1, round(cumZFactors(2:end) ./ cumZFactors(1:end-1))];   % per level, from the level above
            zBuffers    = cell(1, nLevels);   % {Yl×Xl×C} XY-reduced slices of level L-1 pending Z-averaging, per level
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
                    if trackMaxLabel; maxLabel = max(maxLabel, double(max(slice, [], 'all'))); end

                    levelOutput = [];   % output slice of the level above, [] when it produced none
                    for L = 1:nLevels
                        Yl = levelInfo(L).Yl; Xl = levelInfo(L).Xl;
                        if L == 1
                            outputSlice = slice;
                        else
                            if isempty(levelOutput); break; end   % level L-1 is still filling a Z group
                            xySlice = io.savers.Zarr3Saver.reduceSliceXY(levelOutput, slice, Yl, Xl, ...
                                cumZFactors(L), options.DownsampleMethod);
                            if zFactors(L) == 1
                                outputSlice = xySlice;
                            else
                                zBuffers{L}{end+1} = xySlice;
                                outputSlice = [];
                                if numel(zBuffers{L}) == zFactors(L)
                                    outputSlice = io.savers.Zarr3Saver.reduceZBuffer( ...
                                        zBuffers{L}, options.DownsampleMethod, imgClass, Yl, Xl, C);
                                    zBuffers{L} = {};
                                end
                            end
                        end

                        if ~isempty(outputSlice)
                            writeBatch{L}{end+1} = outputSlice;
                            if numel(writeBatch{L}) == levelInfo(L).chunkZ
                                io.savers.Zarr3Saver.writeStreamBatch( ...
                                    levelInfo(L).arr, writeBatch{L}, writeStart(L), t, C, T, Yl, Xl, imgClass);
                                writeStart(L) = writeStart(L) + numel(writeBatch{L});
                                writeBatch{L} = {};
                            end
                        end
                        levelOutput = outputSlice;
                    end

                    done = done + 1;
                    if ~isempty(wb); wb.Value = done/total; end
                end

                % Trailing partial Z groups, level by level down the cascade: the
                % last output of level L-1 (if its group was partial) joins the
                % buffer of level L before that buffer is averaged in turn; then
                % flush the remaining partial write batch (number of output slices
                % not divisible by chunkZ).
                levelOutput = [];
                for L = 1:nLevels
                    Yl = levelInfo(L).Yl; Xl = levelInfo(L).Xl;
                    outputSlice = [];
                    if L > 1
                        if ~isempty(levelOutput)
                            xySlice = io.savers.Zarr3Saver.reduceSliceXY(levelOutput, [], Yl, Xl, ...
                                cumZFactors(L), options.DownsampleMethod);
                            if zFactors(L) == 1
                                outputSlice = xySlice;
                            else
                                zBuffers{L}{end+1} = xySlice;
                            end
                        end
                        if ~isempty(zBuffers{L})
                            outputSlice = io.savers.Zarr3Saver.reduceZBuffer( ...
                                zBuffers{L}, options.DownsampleMethod, imgClass, Yl, Xl, C);
                            zBuffers{L} = {};
                        end
                        if ~isempty(outputSlice); writeBatch{L}{end+1} = outputSlice; end
                    end
                    if ~isempty(writeBatch{L})
                        io.savers.Zarr3Saver.writeStreamBatch( ...
                            levelInfo(L).arr, writeBatch{L}, writeStart(L), t, C, T, Yl, Xl, imgClass);
                    end
                    levelOutput = outputSlice;
                end
            end
            if ~isempty(wb); delete(wb); end

            if trackMaxLabel && maxLabel > 0
                attrStruct.mibMaterials = struct('materialNames', ...
                    {arrayfun(@(k) sprintf('Material %d', k), (1:maxLabel)', 'UniformOutput', false)});
            end
            grp.setAttributes(attrStruct);   % replaces the attributes: drops mibIncomplete

            fnOut = filename;
            fprintf('Zarr3Saver: streamed → %s\n', filename);
        end

        function fnOut = saveStreamResumable(obj, provider, metadata, filename, options, pool)
            % SAVESTREAMRESUMABLE - write an OME-Zarr pyramid in independent slab tasks that can be resumed.
            %
            % Twin of ``saveStream`` with the same options and the same store
            % (``createStreamStore``), but the work is split into tasks, run on the
            % workers of ``pool`` or, without a pool, one after the other on the
            % client. Every finished task is recorded in the store, so a
            % conversion that was cancelled, failed or crashed continues where it
            % stopped (``options.Resume``):
            %
            %   1. **Level-0 slabs.** Each task reads its Z-slab of source slices
            %      (on a worker the provider arrives once, through
            %      ``parallel.pool.Constant``), writes it to level 0 and to every
            %      further level that keeps the full Z (``cumZFactor == 1``),
            %      downsampling XY per slice. The slab depth is the level-0 write
            %      depth (chunk Z, or shard Z when sharded), so every task writes
            %      whole chunks/shards and no two tasks touch the same one.
            %   2. **Z-downsampled levels**, one after the other: each task reads a
            %      chunk-aligned block of the level above back from the store,
            %      downsamples it in XY and Z, and writes one write depth of the
            %      level. Level ``L`` needs level ``L-1`` complete, hence the order.
            %
            % No pixel crosses a process boundary with a pool.
            %
            % **Bands of rows** (``options.BandHeight > 0``, smaller than the slice
            % height). For slices whose slab does not fit in memory: level 0 is
            % written in tasks of one Z-slab x one band of ``BandHeight`` rows
            % (rounded down to whole chunk - or shard - rows of level 0, at least
            % one), read with ``provider.getSliceRows``; then every coarser level
            % is built band by band from the level above (``buildLevelBand``),
            % each band reading about as much as a level-0 band. Memory per task
            % no longer depends on the slice height. Bands need a provider that
            % reads rows (``getSliceRows``, and ``SupportsRowReads`` when it has
            % that property) and an interpolating downsampling method; otherwise
            % ``io:Zarr3Saver:bandsUnsupported``. A banded store equals an
            % unbanded one: every resize is by exactly 0.5 and a band reads enough
            % rows around it to resize exactly like the whole slice.
            %
            % **XY downsampling** is by exactly 0.5 per level (``imresize(...,
            % 0.5)``), matching the ``2^k`` scale in the metadata; for an odd size
            % this differs from resizing to ``[Yl Xl]``, which stretches by
            % ``size/Yl``.
            %
            % **Resume.** Two files in the store root drive it, both removed when
            % the conversion completes:
            %
            %   - ``.mib_resume.json`` - written once at the start: what the store
            %     is (source and pyramid sizes, level plan, chunk, shard, codec,
            %     zarr format, downsampling method) plus
            %     ``options.SourceFingerprint``, which the caller sets to identify
            %     its source (e.g. names, sizes and dates of the source files), and
            %     the band height. A resume compares the first part and takes the
            %     band height from the record, whatever ``BandHeight`` it is given:
            %     the task keys depend on it, and a caller that sizes bands from the
            %     free memory would otherwise refuse its own resume
            %   - ``.mib_progress.log`` - one line ``<task key> <largest value>``
            %     appended on the client after each finished task
            %
            % With ``options.Resume = true`` the existing store is reopened
            % instead of replaced; the recorded tasks are skipped, the others run
            % (a task interrupted while writing rewrites its whole chunks, so a
            % half-written slab is harmless). The store must carry both files and
            % a ``.mib_resume.json`` equal to the one this call would write -
            % otherwise ``io:Zarr3Saver:cannotResume`` is raised with the reason,
            % and nothing is changed. Tasks are recorded in submission order, so
            % with a pool a few finished tasks may be redone after a crash.
            %
            % The store equals the one ``saveStream`` writes: both build each
            % level from the level above. Only one time point (``T == 1``) is
            % supported. With a pool
            % ``provider`` is serialised, so it must not hold a pool or open file
            % handles (e.g. ``ImageDatastoreSliceProvider``). Progress and Cancel
            % act between tasks, i.e. per slab.
            %
            % **Memory.** Per worker (or on the client without a pool), phase 1
            % holds the slab of every full-Z level (~1.33 x writeDepth full slices)
            % plus the copy zarrMex makes while writing; phase 2 a block of
            % ``writeDepth x factor`` slices of the level above.
            %
            % Cancel and errors as in ``saveStream``: the store keeps
            % ``mibIncomplete`` and the resume files; cancel returns ``[]``, a
            % failed task cancels the remaining ones and raises
            % ``io:Zarr3Saver:taskFailed`` naming the level and Z range.
            %
            % Input Arguments:
            %   - **provider** - ``io.savers.SliceProvider``
            %   - **metadata**, **filename** - as for ``saveStream``
            %   - **options** - as for ``saveStream``, plus:
            %
            %     - ``.Resume`` - [logical] continue an interrupted conversion, default false
            %     - ``.SourceFingerprint`` - struct or char identifying the source,
            %       compared on resume; default empty
            %     - ``.BandHeight`` - rows of a level-0 band, ``0`` (default) or at
            %       least the slice height for whole slices
            %
            %   - **pool** - *(optional)* process-based ``parallel.Pool``; ``[]`` runs
            %     the tasks on the client
            %
            % Output Arguments:
            %   - **fnOut** - [char] the written group path, ``[]`` if cancelled
            %
            % **Example** - a folder of TIFFs, written by 4 workers, then resumed:
            %
            %   .. code-block:: matlab
            %
            %      provider = io.savers.ImageDatastoreSliceProvider(imageDatastore('C:\slices'));
            %      meta = struct('pixSize', struct('x',0.01,'y',0.01,'z',0.03));
            %      saver = io.savers.Zarr3Saver(struct());
            %      saver.saveStreamResumable(provider, meta, 'C:\out\stack.zarr3', struct('silent', true), parpool(4));
            %      % ... interrupted; later, with the same settings:
            %      saver.saveStreamResumable(provider, meta, 'C:\out\stack.zarr3', ...
            %          struct('silent', true, 'Resume', true), gcp);
            if nargin < 5 || isempty(options); options = struct(); end
            if nargin < 6; pool = []; end
            if nargin < 4 || isempty(filename); error('io:Zarr3Saver:noFilename', 'Output filename is required'); end
            resumeConversion = isfield(options, 'Resume') && options.Resume;
            sourceFingerprint = '';
            if isfield(options, 'SourceFingerprint'); sourceFingerprint = options.SourceFingerprint; end

            [options, cancelled] = obj.resolveExportOptions(options, metadata, provider.OutputSize(1:3));
            if cancelled; fnOut = []; return; end
            [options, isLabelLayer, pixSize] = io.savers.Zarr3Saver.streamDefaults(options, metadata);

            sz = provider.OutputSize;
            Y = sz(1); X = sz(2); Z = sz(3); C = sz(4); T = sz(5);
            if T > 1
                error('io:Zarr3Saver:resumableTimeSeries', ...
                    'saveStreamResumable writes a single time point; use saveStream for time series.');
            end
            imgClass = provider.DataClass;

            plan = io.savers.Zarr3Saver.computeLevelPlan(Y, X, Z, pixSize, options);
            nLevels = numel(plan);
            filename = char(filename);
            resumeFile = fullfile(filename, '.mib_resume.json');
            progressFile = fullfile(filename, '.mib_progress.log');

            % what the store is: a resume must find exactly this
            resumeInfo = struct('sizeYXZC', [Y X Z C], 'dataClass', imgClass, ...
                'levelsYXZ', [[plan.Yl]', [plan.Xl]', [plan.Zl]'], 'cumZFactor', [plan.cumZFactor], ...
                'chunkSize', options.ChunkSize, 'shardSize', options.ShardSize, ...
                'compressors', options.Compressors, 'downsampleMethod', options.DownsampleMethod, ...
                'zarrFormat', io.savers.Zarr3Saver.resolveZarrFormat(filename, options), ...
                'source', sourceFingerprint);
            resumeText = jsonencode(resumeInfo);

            bandHeight = 0;
            if isfield(options, 'BandHeight') && ~isempty(options.BandHeight); bandHeight = options.BandHeight; end
            finishedTasks = dictionary(string.empty, double.empty);   % task key -> largest value of the task
            if resumeConversion
                if ~isfile(resumeFile) || ~isfile(progressFile)
                    error('io:Zarr3Saver:cannotResume', ...
                        'Cannot resume %s: it holds no record of an interrupted conversion.', filename);
                end
                recorded = jsondecode(fileread(resumeFile));
                if ~isfield(recorded, 'conversion') || ~isequal(recorded.conversion, jsondecode(resumeText))
                    error('io:Zarr3Saver:cannotResume', ['Cannot resume %s: the source or the settings ' ...
                        'differ from those of the interrupted conversion.'], filename);
                end
                % the recorded bands, whatever this call asks for: the task keys depend on them
                bandHeight = recorded.bandHeight;
                progressLines = splitlines(strtrim(fileread(progressFile)));
                for lineIndex = 1:numel(progressLines)
                    parts = split(strtrim(progressLines{lineIndex}));
                    if numel(parts) == 2; finishedTasks(parts(1)) = str2double(parts(2)); end
                end
                [grp, levelInfo, attrStruct] = io.savers.Zarr3Saver.createStreamStore( ...
                    filename, plan, C, T, imgClass, options, metadata, isLabelLayer, false);
            else
                [grp, levelInfo, attrStruct] = io.savers.Zarr3Saver.createStreamStore( ...
                    filename, plan, C, T, imgClass, options, metadata, isLabelLayer);
            end

            % --- bands of rows: level-0 band height in whole chunk (shard) rows ---
            useBands = bandHeight > 0 && bandHeight < Y;
            if useBands
                if ~ismethod(provider, 'getSliceRows') || ...
                        (isprop(provider, 'SupportsRowReads') && ~provider.SupportsRowReads)
                    error('io:Zarr3Saver:bandsUnsupported', ...
                        'The source cannot be read in bands of rows; use BandHeight = 0.');
                end
                if ismember(options.DownsampleMethod, {'mode', 'median'})
                    error('io:Zarr3Saver:bandsUnsupported', ...
                        'Bands of rows support the interpolating downsampling methods only, not ''%s''.', options.DownsampleMethod);
                end
                bandHeight = max(1, floor(bandHeight / levelInfo(1).rowAlign)) * levelInfo(1).rowAlign;
                useBands = bandHeight < Y;
            end
            if ~useBands; bandHeight = 0; end
            if ~resumeConversion
                resumeRecord = struct('conversion', resumeInfo, 'bandHeight', bandHeight);
                fileId = fopen(resumeFile, 'w'); fwrite(fileId, jsonencode(resumeRecord), 'char'); fclose(fileId);
                fileId = fopen(progressFile, 'w'); fclose(fileId);
            end
            trackMaxLabel = isLabelLayer && ~isfield(attrStruct, 'mibMaterials') && ...
                isfield(options, 'MaterialNamesFromData') && options.MaterialNamesFromData;

            levelNames = {levelInfo.name};
            levelSizes = [[levelInfo.Yl]', [levelInfo.Xl]'];
            if isempty(pool)
                providerArgument = struct('Value', provider);   % same .Value access as a pool Constant
            else
                providerArgument = parallel.pool.Constant(provider);
            end
            slabDepth = levelInfo(1).chunkZ;
            zFirsts = 1:slabDepth:Z;
            zLasts = min(zFirsts + slabDepth - 1, Z);

            % --- task list: level 0, then one group per level built from the level above ---
            if useBands
                % level 0 slab by slab and band by band; every coarser level is
                % then built from the level above, in bands as well
                numberOfDirectLevels = 1;
                yFirsts = 1:bandHeight:Y;
                yLasts = min(yFirsts + bandHeight - 1, Y);
                [slabIndex, bandIndex] = ndgrid(1:numel(zFirsts), 1:numel(yFirsts));
                slabIndex = slabIndex(:)'; bandIndex = bandIndex(:)';
                taskGroups = {struct( ...
                    'key', arrayfun(@(s, b) sprintf('L0_Z%d_Y%d', zFirsts(s), yFirsts(b)), slabIndex, bandIndex, 'UniformOutput', false), ...
                    'label', arrayfun(@(s, b) sprintf('level 0, Z %d-%d, Y %d-%d', zFirsts(s), zLasts(s), yFirsts(b), yLasts(b)), ...
                        slabIndex, bandIndex, 'UniformOutput', false), ...
                    'function', @io.savers.Zarr3Saver.writeLevel0Band, 'numberOfOutputs', 1, ...
                    'arguments', arrayfun(@(s, b) {filename, levelNames{1}, providerArgument, ...
                        zFirsts(s), zLasts(s), yFirsts(b), yLasts(b), trackMaxLabel}, slabIndex, bandIndex, 'UniformOutput', false))};
            else
                % levels keeping the full Z are written with level 0; the others are
                % built from the level above (cumZFactor never decreases with L)
                numberOfDirectLevels = find([plan.cumZFactor] > 1, 1) - 1;
                if isempty(numberOfDirectLevels); numberOfDirectLevels = nLevels; end
                taskGroups = {struct('key', arrayfun(@(first) sprintf('L0_Z%d', first), zFirsts, 'UniformOutput', false), ...
                    'label', arrayfun(@(first, last) sprintf('level 0, Z %d-%d', first, last), zFirsts, zLasts, 'UniformOutput', false), ...
                    'function', @io.savers.Zarr3Saver.writeDirectSlab, 'numberOfOutputs', 1, ...
                    'arguments', arrayfun(@(first, last) {filename, levelNames(1:numberOfDirectLevels), ...
                        levelSizes(1:numberOfDirectLevels, :), providerArgument, first, last, C, imgClass, ...
                        options.DownsampleMethod, trackMaxLabel}, zFirsts, zLasts, 'UniformOutput', false))};
            end
            for L = numberOfDirectLevels+1:nLevels
                zFactor = round(plan(L).cumZFactor / plan(L-1).cumZFactor);
                if useBands
                    % the source block of a band (2 rows per output row at the width
                    % of the level above, writeDepth x zFactor deep) stays about the
                    % size of a level-0 band
                    rowsPerBand = floor(bandHeight * X * slabDepth / ...
                        (2 * levelSizes(L-1, 2) * levelInfo(L).chunkZ * zFactor));
                    rowsPerBand = max(1, floor(rowsPerBand / levelInfo(L).rowAlign)) * levelInfo(L).rowAlign;
                    rowsPerBand = min(rowsPerBand, levelInfo(L).Yl);
                else
                    rowsPerBand = levelInfo(L).Yl;
                end
                outFirsts = 1:levelInfo(L).chunkZ:levelInfo(L).Zl;
                outLasts = min(outFirsts + levelInfo(L).chunkZ - 1, levelInfo(L).Zl);
                rowFirsts = 1:rowsPerBand:levelInfo(L).Yl;
                rowLasts = min(rowFirsts + rowsPerBand - 1, levelInfo(L).Yl);
                [slabIndex, bandIndex] = ndgrid(1:numel(outFirsts), 1:numel(rowFirsts));
                slabIndex = slabIndex(:)'; bandIndex = bandIndex(:)';
                if useBands
                    keys = arrayfun(@(s, b) sprintf('L%d_Z%d_Y%d', L - 1, outFirsts(s), rowFirsts(b)), slabIndex, bandIndex, 'UniformOutput', false);
                    labels = arrayfun(@(s, b) sprintf('level %d, Z %d-%d, Y %d-%d', L - 1, outFirsts(s), outLasts(s), ...
                        rowFirsts(b), rowLasts(b)), slabIndex, bandIndex, 'UniformOutput', false);
                else
                    keys = arrayfun(@(s) sprintf('L%d_Z%d', L - 1, outFirsts(s)), slabIndex, 'UniformOutput', false);
                    labels = arrayfun(@(s) sprintf('level %d, Z %d-%d', L - 1, outFirsts(s), outLasts(s)), slabIndex, 'UniformOutput', false);
                end
                taskGroups{end+1} = struct('key', keys, 'label', labels, ...
                    'function', @io.savers.Zarr3Saver.buildLevelBand, 'numberOfOutputs', 0, ...
                    'arguments', arrayfun(@(s, b) {filename, levelNames{L-1}, levelNames{L}, ...
                        levelSizes(L-1, :), levelSizes(L, :), outFirsts(s), outLasts(s), rowFirsts(b), rowLasts(b), ...
                        zFactor, levelInfo(L-1).Zl, C, imgClass, options.DownsampleMethod}, ...
                        slabIndex, bandIndex, 'UniformOutput', false)); %#ok<AGROW>
            end
            numberOfTasks = sum(cellfun(@numel, taskGroups));
            doneTasks = numEntries(finishedTasks);

            if isempty(pool); workerText = 'on this computer'; else; workerText = sprintf('on %d workers', pool.NumWorkers); end
            wb = obj.createProgressDialog('Saving Zarr...', sprintf('Writing %s\n%s', filename, workerText), true);
            if ~isempty(wb); wb.Value = doneTasks / numberOfTasks; end

            for groupIndex = 1:numel(taskGroups)
                tasks = taskGroups{groupIndex};
                tasks = tasks(~isKey(finishedTasks, string({tasks.key})));
                [finishedTasks, doneTasks, cancelled] = io.savers.Zarr3Saver.runTasks( ...
                    tasks, pool, wb, doneTasks, numberOfTasks, finishedTasks, progressFile);
                if cancelled; if ~isempty(wb); delete(wb); end; fnOut = []; return; end
            end
            if ~isempty(wb); delete(wb); end

            maxLabel = max([0; values(finishedTasks)]);
            if trackMaxLabel && maxLabel > 0
                attrStruct.mibMaterials = struct('materialNames', ...
                    {arrayfun(@(k) sprintf('Material %d', k), (1:maxLabel)', 'UniformOutput', false)});
            end
            grp.setAttributes(attrStruct);   % replaces the attributes: drops mibIncomplete
            delete(resumeFile);
            delete(progressFile);

            fnOut = filename;
            fprintf('Zarr3Saver: written %s → %s\n', workerText, filename);
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
            meta = struct('pixSize', ds.image.pixSize, 'boundingBox', ds.image.boundingBox);
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
            meta = struct('pixSize', ds.image.pixSize, 'boundingBox', ds.image.boundingBox);
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
            %   - 3-D anisotropic (vxZ >= 2× vxXY):  chunk 256×256×4, strategy 'Anisotropy-preserving'
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
            % **Compression level:** 0 keeps the codec default of the zarr engine
            % (zstd 3, gzip 5; ``ZarrArray.getDefaultCodecConfig``), so a dialog
            % accepted unchanged writes exactly what ``Compressors = 'zstd'`` always
            % wrote. zstd takes 1..22, gzip 1..9; a gzip level above 9 is written as 9
            % (the header says so). The level is ignored for ``'none'``.
            %
            % **presetDefaults** (optional struct) pre-fills the dialog fields with an
            % existing dataset's actual settings (used by BigData alignment to seed the
            % dialog from the open dataset instead of the dimension heuristics). Any of
            % ``Levels``, ``ChunkSize`` [y x z], ``ShardSize`` [y x z] (empty/absent = off),
            % ``Compressors``, ``DownsampleMethod``, ``DownsampleStrategy`` overrides the
            % corresponding heuristic default. ``Compressors`` takes the same forms the
            % dialog returns: a codec name, or a struct whose ``configuration.level``
            % pre-fills the compression level.
            %
            % Output Arguments:
            %   - **options** - struct with fields ``Levels`` (omitted when auto),
            %     ``ChunkSize`` [y x z], ``ShardSize`` [y x z] (omitted when no sharding),
            %     ``Compressors``, ``DownsampleMethod``, ``DownsampleStrategy``;
            %     ``[]`` when cancelled. ``Compressors`` is the codec name
            %     (``'zstd'``, ``'gzip'``, ``'none'``) when the level is the codec
            %     default, otherwise ``struct('name', codec, 'configuration',
            %     struct('level', level))``; both forms go straight to
            %     ``ZarrArray.create``.
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
                defaultChunk    = '256, 256, 4';
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
                    'one shard file (e.g. 4,4,1 = 16 chunks/file in XY). 0 = off.'; ...
                    ''; ...
                    'Compression level: zstd 1-22, gzip 1-9 (higher is written as 9);'; ...
                    'higher = smaller files, slower writes. 0 = default (zstd 3, gzip 5).'}];
            header = strjoin(headerLines, newline);

            prompts = {'Pyramid levels (0 = auto):'; 'Chunk size [Y, X, Z]:'; ...
                       'Shard X-factors [Y, X, Z] (0 = off):'; 'Compression:'; ...
                       'Compression level (0 = default):'; ...
                       'Downsampling method:'; 'Downsampling strategy:'};
            strategyItems   = {'XY only', 'Anisotropy-preserving'};
            compressorItems = {'zstd', 'gzip', 'none'};

            % --- override the heuristic defaults with an existing dataset's settings ---
            levelDefault      = 0;   % 0 = auto
            compressorDefault = 1;
            compressionLevelDefault = 0;   % 0 = codec default
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
                    presetCodec = presetDefaults.Compressors;
                    if isstruct(presetCodec)
                        if isfield(presetCodec, 'configuration') && isfield(presetCodec.configuration, 'level')
                            compressionLevelDefault = presetCodec.configuration.level;
                        end
                        presetCodec = presetCodec.name;
                    end
                    ci = find(strcmp(compressorItems, presetCodec), 1);
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
                       struct('Spinner', true, 'Value', compressionLevelDefault, 'Limits', [0 22], 'Step', 1, 'Round', true); ...
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
            compressionLevel = answer{5};
            if strcmp(options.Compressors, 'gzip'); compressionLevel = min(compressionLevel, 9); end
            if compressionLevel > 0 && ~strcmp(options.Compressors, 'none')
                options.Compressors = struct('name', options.Compressors, ...
                    'configuration', struct('level', compressionLevel));
            end
            % strip the parenthetical note from method items (e.g. 'nearest (fast)' → 'nearest')
            options.DownsampleMethod = strtok(answer{6}, ' ');
            options.DownsampleStrategy = answer{7};
        end

        function saverOptions = optionsFromPyramid(pyramid)
            % OPTIONSFROMPYRAMID - Saver options that rebuild a store the way an existing pyramid was built.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       saverOptions = io.savers.Zarr3Saver.optionsFromPyramid(pyramid)
            %
            % A store derived from a BigData dataset (aligned, cropped) keeps the
            % chunking, level count, downsampling strategy and sharding of its
            % source, so level ``sN`` of the result has the scale of level ``sN``
            % of the source. Used by ``Alignment.applyAlignmentBigData`` and
            % ``MibDataset.cropToBigData``; ``reviewOptionsDialog`` lets the user
            % change the result before writing.
            %
            % - **Chunk** - level 0 chunk of the source, ``[256 256 16]`` when the
            %   pyramid records none.
            % - **Levels** - the source level count, explicit, so the automatic
            %   ``MinLevelSize`` stop does not shorten a small crop.
            % - **Strategy** - ``'Anisotropy-preserving'`` when any source level
            %   halves Z, otherwise ``'XY only'``.
            % - **Shard** - only when the source shard spans more than one chunk,
            %   and as chunks per shard (``ShardSize`` is a multiplier everywhere in
            %   this saver; the source records it in voxels).
            % - **Method** - ``'bilinear'``; the source does not record it.
            %
            % Input Arguments:
            %   - **pyramid** - ``MibVirtualImage.pyramid`` struct of the source;
            %     reads ``axisOrder``, ``chunkSizes``, ``shardSizes``,
            %     ``levelImageSizes``, ``levelScaleFactors`` when present
            %
            % Output Arguments:
            %   - **saverOptions** - struct with ``silent`` (true), ``ChunkSize``
            %     ``[y x z]``, ``Levels``, ``DownsampleStrategy``,
            %     ``DownsampleMethod`` and, when the source is sharded,
            %     ``ShardSize`` ``[y x z]`` in chunks

            axisOrder = 'yxz';
            if isfield(pyramid, 'axisOrder') && ~isempty(pyramid.axisOrder)
                axisOrder = char(pyramid.axisOrder);
            end

            chunkYXZ = [256 256 16];
            if isfield(pyramid, 'chunkSizes') && ~isempty(pyramid.chunkSizes) && ~isempty(pyramid.chunkSizes{1})
                chunkYXZ = io.savers.Zarr3Saver.mapAxisVector(double(pyramid.chunkSizes{1}), axisOrder, chunkYXZ);
            end

            sourceLevels = 1;
            if isfield(pyramid, 'levelImageSizes') && ~isempty(pyramid.levelImageSizes)
                sourceLevels = size(pyramid.levelImageSizes, 1);
            end

            downsampleStrategy = 'XY only';
            if isfield(pyramid, 'levelScaleFactors') && size(pyramid.levelScaleFactors, 1) >= 2 ...
                    && any(diff(pyramid.levelScaleFactors(:, 3)) > 0)
                downsampleStrategy = 'Anisotropy-preserving';
            end

            saverOptions = struct();
            saverOptions.silent             = true;   % skip the dialog inside save/saveStream
            saverOptions.ChunkSize          = chunkYXZ;
            saverOptions.DownsampleStrategy = downsampleStrategy;
            saverOptions.DownsampleMethod   = 'bilinear';
            saverOptions.Levels             = sourceLevels;

            if isfield(pyramid, 'shardSizes') && ~isempty(pyramid.shardSizes) && ~isempty(pyramid.shardSizes{1})
                shardYXZ = io.savers.Zarr3Saver.mapAxisVector(double(pyramid.shardSizes{1}), axisOrder, chunkYXZ);
                if any(shardYXZ > chunkYXZ)
                    saverOptions.ShardSize = max(1, round(shardYXZ ./ chunkYXZ));
                end
            end
        end

        function saverOptions = reviewOptionsDialog(saverOptions, parentFig, mibPath, datasetInfo)
            % REVIEWOPTIONSDIALOG - Show the Zarr settings dialog pre-filled with ``saverOptions`` and merge the answer.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       saverOptions = io.savers.Zarr3Saver.reviewOptionsDialog(saverOptions, parentFig, mibPath, datasetInfo)
            %
            % Opens ``optionsDialog`` with ``saverOptions`` as its preset (typically
            % from ``optionsFromPyramid``) and returns the options to write with.
            % The dialog omits ``Levels`` for auto and ``ShardSize`` for no
            % sharding, so those two are dropped from the base before the merge;
            % ``MinLevelSize`` 256 and ``MaxLevels`` 8 are set for the auto case.
            % Fields the dialog does not set (``silent``) are kept.
            %
            % Input Arguments:
            %   - **saverOptions** - struct with ``ChunkSize``, ``Levels``,
            %     ``DownsampleStrategy``, ``DownsampleMethod`` and optional
            %     ``ShardSize`` (chunks per shard) and ``Compressors``
            %   - **parentFig** - figure the dialog is placed over
            %   - **mibPath** - MIB installation path, for the dialog icons
            %   - **datasetInfo** - struct with ``Y``, ``X``, ``Z``, ``pixSize`` of
            %     the store to write, see ``optionsDialog``
            %
            % Output Arguments:
            %   - **saverOptions** - merged options, ``[]`` when the dialog was cancelled

            preset = struct('ChunkSize', saverOptions.ChunkSize, ...
                'DownsampleStrategy', saverOptions.DownsampleStrategy, ...
                'DownsampleMethod', saverOptions.DownsampleMethod);
            if isfield(saverOptions, 'Levels'); preset.Levels = saverOptions.Levels; end
            if isfield(saverOptions, 'Compressors'); preset.Compressors = saverOptions.Compressors; end
            preset.ShardSize = [];   % optionsDialog takes the shard in voxels, empty = off
            if isfield(saverOptions, 'ShardSize') && ~isempty(saverOptions.ShardSize)
                preset.ShardSize = saverOptions.ShardSize(:)' .* saverOptions.ChunkSize(:)';
            end

            dialogOptions = io.savers.Zarr3Saver.optionsDialog(parentFig, mibPath, false, datasetInfo, preset);
            if isempty(dialogOptions); saverOptions = []; return; end

            saverOptions = rmfield(saverOptions, intersect(fieldnames(saverOptions), {'Levels', 'ShardSize'}));
            saverOptions.MinLevelSize = 256;   % used only when the dialog left Levels on auto
            saverOptions.MaxLevels    = 8;
            dialogFields = fieldnames(dialogOptions);
            for fieldId = 1:numel(dialogFields)
                saverOptions.(dialogFields{fieldId}) = dialogOptions.(dialogFields{fieldId});
            end
        end

        function pyramid = pyramidFromPlan(plan, chunkYXZ, axisOrder)
            % PYRAMIDFROMPLAN - Pyramid struct for ``MibBigDataLabels.createStore`` that mirrors an image level plan.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       pyramid = io.savers.Zarr3Saver.pyramidFromPlan(plan, chunkYXZ, axisOrder)
            %
            % A model store written next to an image store must have the image's
            % level sizes and scale factors, or the overlay and the level matching
            % (``ChunkingImport``, ``ChunkingExport``) disagree between the two.
            % Building both from one ``computeLevelPlan`` result guarantees it.
            %
            % Input Arguments:
            %   - **plan** - struct array from ``computeLevelPlan``
            %   - **chunkYXZ** - ``[y x z]`` chunk of the image; ``createStore``
            %     clamps it to each level's size
            %   - **axisOrder** - axis order of the store, e.g. ``'yxz'``
            %
            % Output Arguments:
            %   - **pyramid** - struct with ``levelImageSizes`` ``[nLevels x 3]``,
            %     ``levelScaleFactors`` ``[nLevels x 3]`` (``[y x z]``), ``axisOrder``
            %     and ``chunkSizes`` (one chunk per level, in ``axisOrder``)

            nLevels = numel(plan);
            levelSizes   = zeros(nLevels, 3);
            scaleFactors = zeros(nLevels, 3);
            for levelId = 1:nLevels
                levelSizes(levelId, :)   = [plan(levelId).Yl, plan(levelId).Xl, plan(levelId).Zl];
                scaleFactors(levelId, :) = [plan(levelId).cumXYFactor, plan(levelId).cumXYFactor, plan(levelId).cumZFactor];
            end

            chunkAxis = zeros(1, numel(axisOrder));
            yIndex = strfind(axisOrder, 'y');  xIndex = strfind(axisOrder, 'x');  zIndex = strfind(axisOrder, 'z');
            if ~isempty(yIndex); chunkAxis(yIndex) = chunkYXZ(1); end
            if ~isempty(xIndex); chunkAxis(xIndex) = chunkYXZ(2); end
            if ~isempty(zIndex); chunkAxis(zIndex) = chunkYXZ(3); end

            pyramid = struct();
            pyramid.levelImageSizes   = levelSizes;
            pyramid.levelScaleFactors = scaleFactors;
            pyramid.axisOrder         = axisOrder;
            pyramid.chunkSizes        = repmat({chunkAxis}, nLevels, 1);
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
            % PATCHMETADATA - Update bounding box and pixel sizes in a zarr v2/v3 group on disk.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      io.savers.Zarr3Saver.patchMetadata(zarrPath, pixSize, boundingBox)
            %
            % Writes to the group attributes (``zarr.json`` for v3, ``.zattrs`` for v2):
            %   - ``mibBoundingBox`` [xmin xmax ymin ymax zmin zmax] (MIB-specific round-trip)
            %   - ``translation`` coordinateTransformation per pyramid level (OME-NGFF 0.5)
            %   - Updated ``scale`` per pyramid level from new ``pixSize``
            %
            % Input Arguments:
            %   - **zarrPath** - [char] local path to the zarr v2/v3 group folder; a
            %     remote URL or a folder that is not a zarr group is skipped silently
            %   - **pixSize** - [struct] with fields ``.x``, ``.y``, ``.z``
            %   - **boundingBox** - [1x6 double] ``[xmin xmax ymin ymax zmin zmax]``
            %
            % Output Arguments:
            %   (none)
            %

            if isempty(zarrPath) || ~isfolder(zarrPath); return; end
            if startsWith(zarrPath, 'http://') || startsWith(zarrPath, 'https://'); return; end
            % a v3 group keeps its attributes in zarr.json, a v2 group in .zattrs
            % next to .zgroup; ZarrGroup reads and writes either
            if ~isfile(fullfile(zarrPath, 'zarr.json')) && ~isfile(fullfile(zarrPath, '.zgroup')); return; end

            try
                grp = ZarrGroup(zarrPath);
                attrs = grp.getAttributes();
                if ~isstruct(attrs); attrs = struct(); end

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

                grp.setAttributes(attrs);

            catch ME
                warning('io:Zarr3Saver:patchMetadata:failed', ...
                    'patchMetadata failed for %s: %s', zarrPath, ME.message);
            end
        end
    end

    methods (Static, Hidden)
        % Tasks of saveStreamResumable. Public only so that parfeval can
        % call them on a pool worker; not meant to be called directly.

        function maxLabel = writeDirectSlab(storePath, levelNames, levelSizes, providerConstant, ...
                zFirst, zLast, C, imgClass, downsampleMethod, trackMaxLabel)
            % WRITEDIRECTSLAB - Read source slices zFirst..zLast and write them to every full-Z level.
            %
            % Runs on a pool worker. Reads each slice from the provider in
            % ``providerConstant.Value``, downsamples it in XY for the coarser
            % levels (cascaded from the previous level by exactly 0.5 for the
            % interpolating methods, see ``buildLevelBand``; from the full slice
            % for ``'mode'``/``'median'``), collects the slab per level and writes
            % each level with one region write.
            %
            % Input Arguments:
            %   - **storePath** - [char] zarr group path
            %   - **levelNames** - cellstr, array names of the full-Z levels
            %   - **levelSizes** - ``[nLevels x 2]`` ``[Y X]`` of those levels
            %   - **providerConstant** - ``parallel.pool.Constant`` of the slice provider
            %   - **zFirst**, **zLast** - 1-based source slice range of the slab
            %   - **C** - number of channels
            %   - **imgClass** - [char] data class
            %   - **downsampleMethod** - [char] ``imresize`` method, ``'mode'`` or ``'median'``
            %   - **trackMaxLabel** - [logical] return the largest value of the slab
            %
            % Output Arguments:
            %   - **maxLabel** - [double] the largest value read, ``0`` unless tracked
            provider = providerConstant.Value;
            numberOfLevels = numel(levelNames);
            depth = zLast - zFirst + 1;
            cascadeDownsampling = ~ismember(downsampleMethod, {'mode', 'median'});
            slabs = cell(1, numberOfLevels);
            for L = 1:numberOfLevels
                slabs{L} = zeros(levelSizes(L, 1), levelSizes(L, 2), depth, C, imgClass);
            end

            maxLabel = 0;
            for z = zFirst:zLast
                slice = provider.getSlice(z, 1);   % [Y X C]
                if trackMaxLabel; maxLabel = max(maxLabel, double(max(slice, [], 'all'))); end
                xySlice = slice;
                for L = 1:numberOfLevels
                    Yl = levelSizes(L, 1); Xl = levelSizes(L, 2);
                    if L > 1
                        if cascadeDownsampling
                            xySlice = imresize(xySlice, 0.5, downsampleMethod);   % from level L-1, [Yl Xl]
                        else
                            xySlice = io.savers.Zarr3Saver.blockReduce2D(slice, Yl, Xl, str2func(downsampleMethod));
                        end
                    end
                    slabs{L}(:, :, z - zFirst + 1, :) = reshape(cast(xySlice, imgClass), Yl, Xl, 1, C);
                end
            end

            for L = 1:numberOfLevels
                io.savers.Zarr3Saver.writeRegion(fullfile(storePath, levelNames{L}), slabs{L}, 1, zFirst, C);
                slabs{L} = [];
            end
        end

        function maxLabel = writeLevel0Band(storePath, levelName, providerConstant, zFirst, zLast, yFirst, yLast, trackMaxLabel)
            % WRITELEVEL0BAND - Read rows yFirst..yLast of source slices zFirst..zLast and write them to level 0.
            %
            % Runs on a pool worker. Memory is one band - ``(yLast-yFirst+1) x
            % width x slab depth`` - however large the slices are; the provider
            % must read rows (``getSliceRows``, e.g. a TIFF through ``imread``
            % with ``PixelRegion``). The coarser levels are built afterwards from
            % level 0 by ``buildLevelBand``.
            %
            % Input Arguments:
            %   - **storePath** - [char] zarr group path
            %   - **levelName** - [char] array name of level 0
            %   - **providerConstant** - ``parallel.pool.Constant`` (or struct with ``.Value``) of the provider
            %   - **zFirst**, **zLast** - 1-based source slice range
            %   - **yFirst**, **yLast** - 1-based row range, whole chunks (shards) of level 0
            %   - **trackMaxLabel** - [logical] return the largest value of the band
            %
            % Output Arguments:
            %   - **maxLabel** - [double] the largest value read, ``0`` unless tracked
            provider = providerConstant.Value;
            C = provider.NumChannels;
            band = zeros(yLast - yFirst + 1, provider.SliceSize(2), zLast - zFirst + 1, C, provider.DataClass);
            maxLabel = 0;
            for z = zFirst:zLast
                rows = provider.getSliceRows(z, yFirst, yLast);   % [rows X C]
                if trackMaxLabel; maxLabel = max(maxLabel, double(max(rows, [], 'all'))); end
                band(:, :, z - zFirst + 1, :) = reshape(rows, size(band, 1), size(band, 2), 1, C);
            end
            io.savers.Zarr3Saver.writeRegion(fullfile(storePath, levelName), band, yFirst, zFirst, C);
        end

        function buildLevelBand(storePath, sourceName, targetName, sourceSize, targetSize, ...
                zOutFirst, zOutLast, yOutFirst, yOutLast, zFactor, sourceDepth, C, imgClass, downsampleMethod)
            % BUILDLEVELBAND - Build rows yOutFirst..yOutLast of slices zOutFirst..zOutLast of a level from the level above.
            %
            % Runs on a pool worker. Every level halves XY (``computeLevelPlan``),
            % so the interpolating methods resize by exactly 0.5 (``imresize(...,
            % 0.5, method)``): output row ``u`` is centred on source row
            % ``2u - 0.5``, the same mapping as the ``2^k`` scale written in the
            % metadata, and ``ceil(rows/2)`` rows come out - the level size. A band
            % reads the source rows it needs plus ``halo`` rows on either side
            % (the bicubic antialiasing kernel reaches 4 source rows at 0.5) and
            % starts on an odd source row, so its resize equals the whole-slice
            % resize exactly (measured, bilinear/bicubic/nearest, odd and even
            % sizes) and bands join without seams. ``'mode'``/``'median'`` reduce
            % blocks with ``blockReduce2D`` and need the whole slice
            % (``yOutFirst = 1``, ``yOutLast = targetSize(1)``).
            %
            % The source block is ``zFactor``-times deeper than the output; each
            % group of ``zFactor`` resized slices is reduced in Z with
            % ``reduceZBuffer`` (a trailing group may be shorter) and the result
            % written with one region write.
            %
            % Input Arguments:
            %   - **storePath** - [char] zarr group path
            %   - **sourceName**, **targetName** - array names of the level above and of this level
            %   - **sourceSize**, **targetSize** - ``[Y X]`` of the two levels
            %   - **zOutFirst**, **zOutLast** - 1-based output slice range
            %   - **yOutFirst**, **yOutLast** - 1-based output row range, whole chunks (shards)
            %   - **zFactor** - Z downsampling factor from the source level (1 or 2)
            %   - **sourceDepth** - Z size of the source level
            %   - **C** - number of channels
            %   - **imgClass** - [char] data class
            %   - **downsampleMethod** - [char] as for ``writeDirectSlab``
            halo = 8;   % even, so the band starts on an odd source row
            cascadeDownsampling = ~ismember(downsampleMethod, {'mode', 'median'});
            if cascadeDownsampling
                rowFirst = max(1, 2 * yOutFirst - 1 - halo);
                rowLast = min(sourceSize(1), 2 * yOutLast + halo);
            else
                rowFirst = 1;
                rowLast = sourceSize(1);
            end
            rowOffset = (rowFirst - 1) / 2;   % output rows before the block's first one

            source = io.zarr.Array(fullfile(storePath, sourceName));
            zInFirst = (zOutFirst - 1) * zFactor + 1;
            zInLast = min(zOutLast * zFactor, sourceDepth);
            bbox = [rowFirst rowLast+1; 1 sourceSize(2)+1; zInFirst zInLast+1];
            if C > 1; bbox = [bbox; 1 C+1]; end
            inputRows = rowLast - rowFirst + 1;
            inputDepth = zInLast - zInFirst + 1;
            block = reshape(source.read(bbox), inputRows, sourceSize(2), inputDepth, C);

            outputRows = yOutLast - yOutFirst + 1;
            Xl = targetSize(2);
            outputDepth = zOutLast - zOutFirst + 1;
            output = zeros(outputRows, Xl, outputDepth, C, imgClass);
            for outputIndex = 1:outputDepth
                firstInput = (outputIndex - 1) * zFactor + 1;
                lastInput = min(outputIndex * zFactor, inputDepth);
                group = cell(1, lastInput - firstInput + 1);
                for inputIndex = firstInput:lastInput
                    sourceSlice = reshape(block(:, :, inputIndex, :), inputRows, sourceSize(2), C);
                    if cascadeDownsampling
                        resized = imresize(sourceSlice, 0.5, downsampleMethod);
                        group{inputIndex - firstInput + 1} = resized(yOutFirst - rowOffset : yOutLast - rowOffset, :, :);
                    else
                        group{inputIndex - firstInput + 1} = io.savers.Zarr3Saver.blockReduce2D( ...
                            sourceSlice, targetSize(1), Xl, str2func(downsampleMethod));
                    end
                end
                output(:, :, outputIndex, :) = reshape(io.savers.Zarr3Saver.reduceZBuffer( ...
                    group, downsampleMethod, imgClass, outputRows, Xl, C), outputRows, Xl, 1, C);
            end
            io.savers.Zarr3Saver.writeRegion(fullfile(storePath, targetName), output, yOutFirst, zOutFirst, C);
        end
    end

    methods (Static, Access = private)
        function outYXZ = mapAxisVector(vector, axisOrder, defaultYXZ)
            % MAPAXISVECTOR - Reorder a per-axis vector given in ``axisOrder`` (e.g. ``'tczyx'``) to ``[y x z]``.
            %
            % An axis missing from ``axisOrder`` or beyond the end of ``vector``
            % keeps its value from ``defaultYXZ``.
            outYXZ = defaultYXZ;
            yIndex = strfind(axisOrder, 'y');
            xIndex = strfind(axisOrder, 'x');
            zIndex = strfind(axisOrder, 'z');
            if ~isempty(yIndex) && yIndex <= numel(vector); outYXZ(1) = vector(yIndex); end
            if ~isempty(xIndex) && xIndex <= numel(vector); outYXZ(2) = vector(xIndex); end
            if ~isempty(zIndex) && zIndex <= numel(vector); outYXZ(3) = vector(zIndex); end
        end

        function [options, isLabelLayer, pixSize] = streamDefaults(options, metadata)
            % STREAMDEFAULTS - Fill the saveStream / saveStreamResumable option defaults.
            %
            % Also decides whether this is a label layer (``options.layerType`` is
            % ``'labels'`` or ``metadata.materialNames`` is set) and then forces a
            % categorical downsampling method (``'nearest'`` unless ``'mode'``), and
            % takes the voxel size from ``metadata.pixSize`` (default 1).
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
        end

        function [grp, levelInfo, attrStruct] = createStreamStore(filename, plan, C, T, imgClass, options, metadata, isLabelLayer, createNew)
            % CREATESTREAMSTORE - Create the zarr group and every level array of a streamed pyramid.
            %
            % Replaces an existing folder at ``filename``. Each level gets its
            % chunk (clamped to the level) and shard shape, C byte order (no
            % transpose codec). The group attributes - OME-NGFF multiscales,
            % materials of a label layer, bounding box - are written at once with
            % ``mibIncomplete = true``; the caller rewrites them with ``attrStruct``
            % (which has no flag) after the last write.
            %
            % With ``createNew = false`` (resume, default true) the existing store
            % is opened instead: nothing is deleted or written, the level arrays
            % are opened, and ``levelInfo``/``attrStruct`` are computed as for a
            % new store.
            %
            % Output Arguments:
            %   - **grp** - ``io.zarr.Group``
            %   - **levelInfo** - struct array per level: ``Yl Xl Zl arr name chunkZ
            %     rowAlign``, where ``chunkZ`` is the Z depth of one write and
            %     ``rowAlign`` the Y step of a band write (chunk Z / Y, or shard Z / Y
            %     when sharded)
            %   - **attrStruct** - the final group attributes
            nLevels = numel(plan);
            axesNames = {'y','x','z'}; axesTypes = {'space','space','space'};
            if C > 1; axesNames{end+1} = 'c'; axesTypes{end+1} = 'channel'; end
            if T > 1; axesNames{end+1} = 't'; axesTypes{end+1} = 'time'; end

            if nargin < 9; createNew = true; end
            filename = char(filename);
            if createNew
                zarrFormat = io.savers.Zarr3Saver.resolveZarrFormat(filename, options);
                if isfolder(filename); rmdir(filename, 's'); end
                grp = io.zarr.Group.create(filename, 'zarrFormat', zarrFormat);
            else
                grp = io.zarr.Group(filename);
            end

            levelInfo = repmat(struct('Yl', 1, 'Xl', 1, 'Zl', 1, 'arr', [], 'name', '', 'chunkZ', 1, 'rowAlign', 1), 1, nLevels);
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
                levelInfo(L).chunkZ = chunk(3);     % Z depth of one write
                levelInfo(L).rowAlign = chunk(1);   % Y step of a band write
                % C byte order, no transpose codec - see "Chunk byte order" in the class help
                createArgs = {'chunkShape', chunk, 'compressors', options.Compressors, 'filters', 'none'};
                if ~isempty(options.ShardSize)
                    shard = io.savers.Zarr3Saver.computeShard(chunk, options.ShardSize);
                    createArgs = [createArgs, {'shardShape', shard}]; %#ok<AGROW>
                    % a write must cover whole shards, or each partial write
                    % re-reads and rewrites the shard (see Memory in saveStream)
                    levelInfo(L).chunkZ = shard(3);
                    levelInfo(L).rowAlign = shard(1);
                end
                if createNew
                    levelInfo(L).arr = grp.createArray(name, keepShape, imgClass, createArgs{:});
                else
                    levelInfo(L).arr = grp.openArray(name);
                end
                scaleVec = [plan(L).physScaleY, plan(L).physScaleX, plan(L).physScaleZ];
                if C > 1; scaleVec(end+1) = 1; end %#ok<AGROW>
                if T > 1; scaleVec(end+1) = 1; end %#ok<AGROW>
                datasets{L} = struct('path', name, ...
                    'coordinateTransformations', {{struct('type', 'scale', 'scale', scaleVec)}});
            end

            % --- OME-NGFF multiscales (+ materials for labels) ---
            axesCells = cell(1, numel(axesNames));
            for a = 1:numel(axesNames); axesCells{a} = struct('name', axesNames{a}, 'type', axesTypes{a}); end
            ms = struct('version', '0.4', 'axes', {axesCells}, 'datasets', {datasets});
            attrStruct = struct('multiscales', {{ms}});
            if isLabelLayer && isstruct(metadata) && isfield(metadata,'materialNames') && ~isempty(metadata.materialNames)
                mm = struct('materialNames', {metadata.materialNames});
                if isfield(metadata,'materialColors') && ~isempty(metadata.materialColors)
                    mm.materialColors = metadata.materialColors;
                end
                attrStruct.mibMaterials = mm;
            end
            attrStruct = io.savers.Zarr3Saver.addBoundingBox(attrStruct, metadata);
            if createNew
                % declared up front and flagged, so an interrupted store is recognisable
                incompleteAttrs = attrStruct;
                incompleteAttrs.mibIncomplete = true;
                grp.setAttributes(incompleteAttrs);
            end
        end

        function [finishedTasks, doneTasks, cancelled] = runTasks(tasks, pool, wb, doneTasks, totalTasks, finishedTasks, progressFile)
            % RUNTASKS - Run saveStreamResumable's tasks, record each finished one, show progress, honour Cancel.
            %
            % ``tasks`` is a struct array with ``key``, ``label``, ``function``,
            % ``numberOfOutputs`` and ``arguments``. With a pool all tasks are
            % submitted at once and collected in order, each future polled so
            % Cancel stays responsive; without a pool they run one by one on the
            % client, Cancel checked between them. A finished task goes into
            % ``finishedTasks`` (key -> largest value returned, 0 when the task
            % returns nothing) and is appended to ``progressFile`` as
            % ``<key> <value>`` - recorded only after it finished, so a resume
            % never skips unwritten data. On Cancel the remaining futures are
            % cancelled and ``cancelled`` is true. A failed task cancels the rest,
            % closes ``wb`` and raises ``io:Zarr3Saver:taskFailed`` with its label
            % (level, Z range).
            cancelled = false;
            if isempty(tasks); return; end
            futures = parallel.FevalFuture.empty;
            if ~isempty(pool)
                for taskIndex = 1:numel(tasks)
                    futures(taskIndex) = parfeval(pool, tasks(taskIndex).function, ...
                        tasks(taskIndex).numberOfOutputs, tasks(taskIndex).arguments{:});
                end
            end

            for taskIndex = 1:numel(tasks)
                task = tasks(taskIndex);
                largestValue = 0;
                if isempty(pool)
                    drawnow limitrate;
                    if ~isempty(wb) && wb.CancelRequested; cancelled = true; return; end
                    try
                        if task.numberOfOutputs > 0
                            largestValue = task.function(task.arguments{:});
                        else
                            task.function(task.arguments{:});
                        end
                    catch err
                        if ~isempty(wb); delete(wb); end
                        error('io:Zarr3Saver:taskFailed', 'Writing %s failed: %s', task.label, err.message);
                    end
                else
                    while ~wait(futures(taskIndex), 'finished', 0.5)
                        drawnow limitrate;
                        if ~isempty(wb) && wb.CancelRequested; break; end
                    end
                    if ~isempty(wb) && wb.CancelRequested
                        cancel(futures);
                        cancelled = true;
                        return;
                    end
                    if ~isempty(futures(taskIndex).Error)
                        cancel(futures);
                        if ~isempty(wb); delete(wb); end
                        error('io:Zarr3Saver:taskFailed', 'Writing %s failed: %s', ...
                            task.label, futures(taskIndex).Error.message);
                    end
                    if task.numberOfOutputs > 0; largestValue = fetchOutputs(futures(taskIndex)); end
                end

                finishedTasks(string(task.key)) = largestValue;
                fileId = fopen(progressFile, 'a');
                fprintf(fileId, '%s %.17g\n', task.key, largestValue);
                fclose(fileId);
                doneTasks = doneTasks + 1;
                if ~isempty(wb); wb.Value = doneTasks / totalTasks; end
            end
        end

        function xySlice = reduceSliceXY(previousOutput, sourceSlice, Yl, Xl, cumZFactor, downsampleMethod)
            % REDUCESLICEXY - XY step of saveStream's level cascade: one output slice of level L-1 to level L.
            %
            % The interpolating methods resize ``previousOutput`` (an output slice
            % of the level above) by exactly 0.5 - the ``2^k`` scale of the
            % metadata, see ``buildLevelBand``. ``'mode'``/``'median'`` reduce
            % blocks of ``sourceSlice`` (the full-resolution slice) while the
            % level keeps the full Z (``cumZFactor == 1``, as ``writeDirectSlab``)
            % and of ``previousOutput`` once Z was halved (as ``buildLevelBand``).
            if ~ismember(downsampleMethod, {'mode', 'median'})
                xySlice = imresize(previousOutput, 0.5, downsampleMethod);
            elseif cumZFactor == 1
                xySlice = io.savers.Zarr3Saver.blockReduce2D(sourceSlice, Yl, Xl, str2func(downsampleMethod));
            else
                xySlice = io.savers.Zarr3Saver.blockReduce2D(previousOutput, Yl, Xl, str2func(downsampleMethod));
            end
        end

        function writeRegion(arrayPath, region, yFirst, zFirst, C)
            % WRITEREGION - Write a ``[rows X depth C]`` region at row ``yFirst``, Z ``zFirst`` with one region write.
            %
            % The region spans the full width; ``yFirst = 1`` and all rows write a
            % whole slab.
            [rows, columns, depth, ~] = size(region);
            bbox = [yFirst yFirst+rows; 1 columns+1; zFirst zFirst+depth];
            if C > 1
                bbox = [bbox; 1 C+1];
            else
                region = reshape(region, rows, columns, depth);
            end
            io.zarr.Array(arrayPath).write(region, bbox);
        end

        function attrStruct = addBoundingBox(attrStruct, metadata)
            % ADDBOUNDINGBOX - add the dataset bounding box to freshly built group attributes.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      attrStruct = io.savers.Zarr3Saver.addBoundingBox(attrStruct, metadata)
            %
            % Shared by ``save`` and ``saveStream`` so every store MIB writes keeps
            % the source bounding box, whatever the caller and zarr format.
            % ``patchMetadata`` does the same for an existing store, but reads
            % ``zarr.json`` directly and so cannot reach a v2 store.
            % Writes the same two entries as ``patchMetadata``:
            %
            %   - ``mibBoundingBox`` - ``[xmin xmax ymin ymax zmin zmax]``, the MIB
            %     round-trip value the zarr loaders apply over anything derived
            %     from the transforms
            %   - a ``translation`` transform appended to every pyramid level, with
            %     the bounding-box origin on the y/x/z axes and 0 on c/t, for
            %     other OME-Zarr readers. As in ``patchMetadata`` the translation
            %     is the same for all levels.
            %
            % Input Arguments:
            %   - **attrStruct** - struct with ``.multiscales = {ms}``, ``ms.axes``
            %     starting ``y, x, z`` and ``ms.datasets`` a cell of structs whose
            %     ``coordinateTransformations`` is a cell holding the scale
            %   - **metadata** - saver metadata; nothing is added unless
            %     ``metadata.boundingBox`` has 6 finite values
            %
            % Output Arguments:
            %   - **attrStruct** - the input with the translations and
            %     ``mibBoundingBox`` added
            if ~isstruct(metadata) || ~isfield(metadata, 'boundingBox') || ...
                    numel(metadata.boundingBox) ~= 6 || ~all(isfinite(metadata.boundingBox))
                return;
            end
            boundingBox = reshape(double(metadata.boundingBox), 1, 6);
            ms = attrStruct.multiscales{1};
            translationVec = zeros(1, numel(ms.axes));
            translationVec(1:3) = [boundingBox(3), boundingBox(1), boundingBox(5)];   % axes y, x, z (, c, t)
            translationSt = struct('type', 'translation', 'translation', translationVec);
            for levelIdx = 1:numel(ms.datasets)
                ms.datasets{levelIdx}.coordinateTransformations{end+1} = translationSt;
            end
            attrStruct.multiscales = {ms};
            attrStruct.mibBoundingBox = boundingBox;
        end

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
