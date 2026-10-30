classdef MibBigDataLabels < core.MibLabels63
% MIBBIGDATALABELS - disk-backed, packed 63-class segmentation labels for BigData datasets.
%
% Subclass of ``core.MibLabels63``. Keeps the identical bit-packing scheme
% (bits 1-6 = material 0-63, bit 7 = mask, bit 8 = selection) but stores the
% packed uint8 data in a writable **multi-resolution zarr pyramid** on disk
% (one level per image pyramid level), so models for datasets too large for
% memory can be segmented and persisted.
%
% **How it integrates.** ``MibImage.getData``/``setData`` route non-image
% layers of a ``MibLabels63`` to ``getData63``/``setData63``; this class
% overrides those to read/modify/write the on-disk pyramid. Because the seam
% is exactly ``getData63``/``setData63``, all of ``MibDataset.getData2D/3D/4D``,
% ``setData2D/...`` and every segmentation tool work unchanged.
%
% **Pyramid.** The model mirrors the image pyramid: same number of levels,
% same per-level sizes (``levelImageSizes``) and scale factors, chunk-aligned
% to the image. ``getData63`` reads the level matching ``options.magFactor``
% and resizes to the displayed resolution exactly like the image reader
% (``MibVirtualImage.getDataZarr``), so image and model always line up.
% ``setData63`` writes the edited region only at the working level and all
% COARSER levels (cheap downsample, preserving packed bytes), and records the
% working level in the per-tile level map (``matLevel``). Finer levels are left
% dirty and reconstructed on demand: ``getData63`` recomputes a finer tile from
% its ``matLevel`` source (no coarse-echo halo), writes it into the level
% (materialize) and caches it. ``saveLevelMap``/``loadLevelMap`` persist the map
% in a side-file; ``materializeAll`` (Save) finalizes every level. See
% development/bigdata/bigdata_logic.md.
%
% **Axis order.** Levels are created with ``ZarrArray`` → they round-trip in
% native MATLAB ``[y, x, z]`` order, no permutation. That holds in both zarr
% formats: v3 gets a transpose codec, v2 gets Fortran chunk order, which is the
% v2 spelling of the same thing. ``obj.data`` stays empty; dimensions come from
% level 0.
%
% **Zarr format.** The store is v3 by default and v2 when the path ends in
% ``.zarr2`` (``createStore`` / ``zarrFormatFromPath``); both are fully
% editable, and everything above applies unchanged to either. A store MIB
% created carries the ``mibModelStore`` marker - a v2 store WITHOUT it was
% written by another tool and is handled read-only by
% ``core.MibBigDataLabelsZarr2`` instead.

    properties
        modelStorePath (1,1) string = ""
        % [string] zarr group root path of the packed model pyramid.
        modelArrays = {}
        % {1 x nLevels} io.zarr.Array handles, one per resolution level (finest first).
        modelLevelNames = {}
        % {1 x nLevels} relative level paths within the group ('0','1',...).
        modelLevelSizes = []
        % [nLevels x 3] per-level [y, x, z] size.
        modelScaleFactors = []
        % [nLevels x 3] per-level [yScale, xScale, zScale] relative to level 0.
        Compressors = 'zstd'
        ShardFactors = []
        % [1x3 numeric] chunks per shard [y x z] used by createStore for zarr v3
        % stores, as ``io.savers.Zarr3Saver.computeShard`` takes them; [] or 0s =
        % no sharding (default). Ignored for zarr v2. Sharding cuts the file count
        % of a large store, but every edit then rewrites whole shards (a
        % partial-shard write re-reads and rewrites the shard, measured 3.4x
        % slower), so the interactively created models leave it off.
        maxIndexUsed = 0
        % [double] highest material/instance index ever written to the store. Raised
        % by setData63 from the max of each written block (cost scales with the
        % edit, never with the slide) and persisted in the ``mibMaterials``
        % attribute by writeMaterialMetadata. It is an upper bound: erasing an
        % object does not lower it. Lets "next empty material" on a uint16
        % instance model answer without scanning the store. A store closed
        % without writeMaterialMetadata (crash) falls back to the coarsest level's
        % max on open, which may miss objects too small to survive downsampling.
    end

    properties (Transient)
        % --- multi-resolution "level map" (see setData63 / getData63 / materializeAll) ---
        matLevel = []
        % [uint8 [coarseY x coarseX x coarseZ x 3]] per coarsest-grid tile and per
        % layer (4th index: 1 = labels, 2 = mask, 3 = selection, see layerGroupBits),
        % the FINEST pyramid level index holding materialized data of that layer
        % (0 = never written). Finer = smaller index; level 1 = full resolution;
        % level N = coarsest. An edit of a layer writes the working level + coarser
        % and sets that layer's entry to the working level; its finer levels are
        % implicitly dirty and recomputed on read (getData63) or at Save
        % (materializeAll). The layers are tracked separately so that, e.g., a
        % selection stroke drawn zoomed out does not make the full-resolution labels
        % under it stale. Side-files written before the split (mapVersion 1) hold one
        % map for all layers; loadLevelMap copies it to each layer.
        levelMapPath = ''
        % [char] side-file path ('<storePath>.levelmap') persisting matLevel.
        selectionBBoxFull = []
        % [1x6 double] full-resolution bounding box [y0 y1 x0 x1 z0 z1] of where the
        % SELECTION layer currently has data, or [] when there is no selection. Grown
        % by setData63 on every selection write (exact written bits → reliable even for
        % a 1-pixel stroke), reset/shrunk when the selection is cleared or consumed.
        % Clamps the instance editor's drawing; the moves and clears use the finer
        % selectionTiles instead. Transient: not persisted; recomputed lazily as
        % edits happen this session.
        selectionTiles = []
        % [logical [coarseY x coarseX x coarseZ]] per coarsest-grid tile, false when
        % the tile is known to hold no selection at any level, true when it may hold
        % some. Kept by setData63 (noteSelectionWrite) on every write that sets
        % selection bits: a tile the write covers whole gets the exact answer, a
        % tile it covers in part can only become true. Unlike selectionBBoxFull it
        % follows a selection made of many separate pieces through a 3D volume
        % (SAM2 in 3D), and it is saved in the level-map side-file, so whole-stack
        % moves (Shift+A/S/R) and clears (Shift+C) touch only these tiles
        % (selectionFootprint). A store opened without a saved map starts all true:
        % unknown, so every tile is a candidate until a write or a move settles it.

        % --- instance index bookkeeping (see core.MibDataset.buildInstanceIndex) ---
        syncedInstanceIndex = []
        % [struct] the instance index (``utils.instances.objectIndex`` fields plus
        % ``.timePoint``/``.stale``) that last described this store exactly, or []
        % when none was built. ``indexDirtyBox`` is relative to it: the index plus
        % a re-measure of the dirty box is the index of the store as it is now.
        % Set through syncInstanceIndex, restored from the side-file by openStore.
        indexDirtyBox = []
        % [1x6 double] full-resolution box [y0 y1 x0 x1 z0 z1] holding every
        % labels change made since syncedInstanceIndex was taken, or [] when
        % there is none. Grown by setData63 through markLabelsChanged, and only
        % while syncedInstanceIndex is set. A labels write at a coarser level is
        % widened to whole coarsest tiles: reading level 1 later re-materializes
        % the labels of those tiles from that level (materializeForRead).
        % Selection and mask writes never count - the level map is per layer.
        instanceIndexOnDisk = false
        % [logical] true while the side-file (instanceIndexPathFor) is a valid
        % description of the store as it is now. The first labels change after
        % that deletes the file, so a crash can never leave an index on disk that
        % describes a different store.
        instanceIndexUnsaved = false
        % [logical] syncedInstanceIndex or indexDirtyBox changed since the
        % side-file was written; saveInstanceIndex writes it then.
    end

    methods
        % declared external methods (override MibLabels63)
        dataset = getData63(obj, type, orient, materialIndex, options)
        result  = setData63(obj, dataset, type, orient, materialIndex, options)
        [levelIdx, levelSize] = findClosestLevelForImport(obj, sourceDims)
        status = moveSelection(obj, destination, action, options)       % Shift+A/S/R on the tiles holding selection
        clearSelectionTiles(obj, fullZ)                                  % c/Shift+C on the tiles holding selection
        status = eraseEverywhere(obj, layerGroup, materialIndex, progressFcn) % remove a material or the mask from the whole volume

        function obj = MibBigDataLabels(img, meta)
            % MIBBIGDATALABELS - Construct an empty disk-backed label container.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = core.MibBigDataLabels([], meta)
            %
            % Creates the in-memory object with no pyramid store attached.  The on-disk
            % store is allocated separately by ``createStore`` (new dataset) or
            % ``openStore`` (existing model).  Until one of those is called,
            % ``obj.exists == false`` and all reads/writes are no-ops.
            %
            % Input Arguments:
            %   - **img** *(optional)* - [empty] pass ``[]``; pixel data is never stored
            %     in memory for BigData labels.
            %   - **meta** *(optional)* - [dictionary] metadata dictionary used by the
            %     parent ``core.MibLabels63`` constructor to set dimensions.  Default:
            %     empty ``MibImage`` info.
            %
            % **Example** - create a fresh labels object and attach a pyramid store:
            %
            %   .. code-block:: matlab
            %
            %      meta = core.MibImage.initializeImgInfo();
            %      lb   = core.MibBigDataLabels([], meta);
            %      lb.createStore([4096 4096 100], 'C:\data\model.zarr3', pyramid);
            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; img = []; end
            obj = obj@core.MibLabels63(img, meta);
            obj.type = 'labels63';
        end

        function createStore(obj, dims, storePath, pyramid, zarrFormat)
            % CREATESTORE - Allocate a zero-filled packed label pyramid on disk.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.createStore(dims)
            %      obj.createStore(dims, storePath)
            %      obj.createStore(dims, storePath, pyramid)
            %      obj.createStore(dims, storePath, pyramid, zarrFormat)
            %
            % Creates a new zarr group at ``storePath`` with one packed array per
            % pyramid level, of class ``obj.containerClass``:
            %
            %   - ``'uint8'`` (default) - bits 1-6 = material 0-63, bit 7 = mask,
            %     bit 8 = selection;
            %   - ``'uint16'`` - bits 1-14 = instance index 0-16383, bit 15 = mask,
            %     bit 16 = selection. Select it with ``obj.setLayout('uint16')``
            %     **before** this call; the layout is a property rather than an
            %     argument so the method signature stays stable for live instances.
            %
            % The level count, sizes, scale factors, and chunk shapes are copied from
            % ``pyramid`` so the model mirrors the image pyramid exactly. The codec
            % comes from ``obj.Compressors`` and, for zarr v3, sharding from
            % ``obj.ShardFactors`` (off by default); set them before this call.  An empty level
            % map (``matLevel``) is initialised and persisted as a side-file.
            %
            % The store is written in zarr **v3** by default and in **v2** when the
            % path ends in ``.zarr2``; both are fully editable and behave
            % identically, since the packed bytes round-trip in ``[y, x, z]``
            % either way (a transpose codec in v3, Fortran chunk order in v2).
            % Either way the group is marked with the ``mibModelStore`` attribute,
            % which is how ``models.MibModel.loadModel`` later tells a MIB-written
            % store from a foreign one (see ``core.MibBigDataLabelsZarr2``).
            %
            % Input Arguments:
            %   - **dims** - [1x3 numeric] ``[height, width, depth]`` in pixels; used as the
            %     fallback level-0 size when ``pyramid`` is empty.
            %   - **storePath** *(optional)* - [char|string] zarr group root directory.
            %     Default: a temporary path (``[tempname '_bigdata_model.zarr3']``).
            %   - **pyramid** *(optional)* - [struct] image pyramid struct with fields:
            %
            %     - ``.levelImageSizes`` - [nLevels x 3] ``[height, width, depth]`` per level
            %     - ``.levelScaleFactors`` - [nLevels x 3] ``[yScale, xScale, zScale]``
            %     - ``.chunkSizes`` - {1 x nLevels} per-level chunk vectors in axis order
            %     - ``.axisOrder`` - [char] axis order string (default ``'tczyx'``)
            %
            %   When ``pyramid`` is empty, a single full-resolution level is created.
            %
            %   - **zarrFormat** *(optional)* - [numeric] ``2`` or ``3``; overrides the
            %     format implied by the extension. Default: derived from ``storePath``.
            %
            % **Example** - create a 3-level model matching a loaded BigData image:
            %
            %   .. code-block:: matlab
            %
            %      img = mib.mibModel.I{1};   % core.MibDataset handle
            %      lb  = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            %      storePath = fullfile(fileparts(img.image.Virtual.filenames{1}), ...
            %                           'Labels.zarr3');
            %      lb.createStore([img.image.height, img.image.width, img.image.depth], ...
            %                     storePath, img.image.pyramid);
            %
            % **Example** - the same model as a zarr v2 store:
            %
            %   .. code-block:: matlab
            %
            %      lb.createStore(dims, 'C:\data\Labels.zarr2', img.image.pyramid);
            if nargin < 4; pyramid = []; end
            if nargin < 3 || isempty(storePath); storePath = [tempname '_bigdata_model.zarr3']; end
            storePath = char(storePath);
            if nargin < 5 || isempty(zarrFormat)
                zarrFormat = core.MibBigDataLabels.zarrFormatFromPath(storePath);
            end
            if isfolder(storePath); rmdir(storePath, 's'); end

            % --- resolve levels from the image pyramid (or single fallback) ---
            chunkCell = {};
            % image chunk is stored in the dataset's axis order (default 'tczyx');
            % resolve y/x/z positions so a chunk of any rank maps correctly to [y x z].
            axisOrder = 'tczyx';
            if ~isempty(pyramid) && isfield(pyramid, 'axisOrder') && ~isempty(pyramid.axisOrder)
                axisOrder = char(pyramid.axisOrder);
            end
            yIdx = find(axisOrder == 'y', 1);
            xIdx = find(axisOrder == 'x', 1);
            zIdx = find(axisOrder == 'z', 1);
            if ~isempty(pyramid) && isfield(pyramid, 'levelImageSizes') && ...
                    ~isempty(pyramid.levelImageSizes) && size(pyramid.levelImageSizes, 2) >= 3
                levelSizes = double(pyramid.levelImageSizes(:, 1:3));     % [y x z]
                scaleFac   = double(pyramid.levelScaleFactors(:, 1:3));   % [yS xS zS]
                if isfield(pyramid, 'chunkSizes'); chunkCell = pyramid.chunkSizes; end
            else
                levelSizes = double(dims(1:3));
                scaleFac   = [1 1 1];
            end
            nLevels = size(levelSizes, 1);

            % --- build the group + one packed array per level ------------------
            % backend per io.zarr.Config; format per the path (or the override);
            % array class from the packed layout (obj.setLayout before this call)
            grp = io.zarr.Group.create(storePath, 'zarrFormat', zarrFormat);
            obj.modelArrays = cell(1, nLevels);
            obj.modelLevelNames = cell(1, nLevels);
            for L = 1:nLevels
                name = num2str(L - 1);
                sz = levelSizes(L, :);
                ch = [256 256 16];                    % default [y x z]
                if ~isempty(chunkCell) && numel(chunkCell) >= L && ~isempty(chunkCell{L})
                    c = chunkCell{L};                 % image chunk, in axisOrder order
                    if ~isempty(yIdx) && yIdx <= numel(c); ch(1) = c(yIdx); end
                    if ~isempty(xIdx) && xIdx <= numel(c); ch(2) = c(xIdx); end
                    if ~isempty(zIdx) && zIdx <= numel(c); ch(3) = c(zIdx); end
                end
                ch = max(min(double(ch), sz), [1 1 1]);
                createArgs = {'chunkShape', ch, 'compressors', obj.Compressors, 'fillValue', 0};
                if zarrFormat == 3 && any(obj.ShardFactors > 0)
                    % zarr v2 has no sharding codec
                    createArgs = [createArgs, {'shardShape', io.savers.Zarr3Saver.computeShard(ch, obj.ShardFactors)}]; %#ok<AGROW>
                end
                obj.modelArrays{L} = grp.createArray(name, sz, obj.containerClass, createArgs{:});
                obj.modelLevelNames{L} = name;
            end
            obj.writeMultiscales(grp, scaleFac);

            obj.modelStorePath    = string(storePath);
            obj.modelLevelSizes   = levelSizes;
            obj.modelScaleFactors = scaleFac;

            % --- state from level 0 (obj.data stays empty) --------------------
            obj.height    = levelSizes(1, 1);
            obj.width     = levelSizes(1, 2);
            obj.depth     = levelSizes(1, 3);
            obj.colors    = 1;
            obj.time      = 1;
            obj.dim_yxzct = [obj.height, obj.width, obj.depth, 1, 1];
            obj.dataClass = obj.containerClass;
            obj.maxInt    = double(intmax(obj.containerClass));
            obj.exists    = true;

            % fresh store → empty level map + side-file path
            obj.levelMapPath = core.MibBigDataLabels.levelMapPathFor(storePath);
            obj.initLevelMapEmpty();

            % a fresh store has no index yet; a side-file left by an earlier store
            % at the same path describes objects that are not there any more
            obj.resetInstanceIndexState();
            indexPath = core.MibBigDataLabels.instanceIndexPathFor(storePath);
            if isfile(indexPath); delete(indexPath); end
        end

        function closeStore(obj)
            % CLOSESTORE - release level handles (data remains on disk).
            % Marks the labels as non-existent so reads/writes become no-ops
            % until a store is (re)opened. Persists the level map first so a
            % reopened model knows which finer levels are still virtual, and the
            % material metadata (incl. maxIndexUsed).
            obj.saveLevelMap();
            obj.writeMaterialMetadata();
            obj.modelArrays = {};
            obj.exists = false;
        end

        function delete(~)
            % DELETE - destructor: nothing to release beyond the handles (data on
            % disk is left as-is; the level map is persisted by closeStore).
        end

        function openStore(obj, storePath)
            % OPENSTORE - attach to an EXISTING packed model pyramid on disk.
            %
            % Reattaches this labels object to a model store previously written
            % by createStore (or a compatible OME-NGFF multiscales group of
            % packed uint8 or uint16 levels). Level sizes and scale factors are
            % restored from the stored ``multiscales`` metadata and array shapes;
            % the packed layout (``setLayout``) follows the data type of level 0,
            % so stores written before the uint16 layout existed open as uint8.
            % No pixel data is read into memory. Use this to reopen a saved model
            % so segmentation can continue across sessions.
            %
            % Input Arguments:
            %   - **storePath** - [char|string] path to the model zarr group.
            storePath = char(storePath);
            grp = io.zarr.Group(storePath);
            attrs = grp.getAttributes();
            if ~isfield(attrs, 'multiscales')
                error('core:MibBigDataLabels:openStore', ...
                    'No multiscales metadata found at "%s"', storePath);
            end
            ms = attrs.multiscales;
            if iscell(ms); ms = ms{1}; elseif numel(ms) > 1; ms = ms(1); end
            dsList = ms.datasets;
            nL = numel(dsList);

            obj.modelArrays     = cell(1, nL);
            obj.modelLevelNames = cell(1, nL);
            levelSizes = zeros(nL, 3);
            scaleFac   = zeros(nL, 3);
            for L = 1:nL
                if iscell(dsList); d = dsList{L}; else; d = dsList(L); end
                name = char(d.path);
                arr  = grp.openArray(name);
                obj.modelArrays{L}     = arr;
                obj.modelLevelNames{L} = name;
                shpv = ones(1, 3);
                v = double(arr.shape());
                n = min(3, numel(v));
                shpv(1:n) = v(1:n);
                levelSizes(L, :) = shpv;
                ct = d.coordinateTransformations;
                if iscell(ct); ct = ct{1}; elseif numel(ct) > 1; ct = ct(1); end
                scv = ones(1, 3);
                v = double(ct.scale(:)');
                n = min(3, numel(v));
                scv(1:n) = v(1:n);
                scaleFac(L, :) = scv;
            end

            % packed layout from the level-0 data type: zarr v3 reports 'uint16',
            % zarr v2 a numpy typestring such as '<u2'
            levelDataType = char(obj.modelArrays{1}.dataType());
            if ~isempty(regexp(levelDataType, '^(uint16|[<>|]?u2)$', 'once'))
                obj.setLayout('uint16');
            else
                obj.setLayout('uint8');
            end

            obj.modelStorePath    = string(storePath);
            obj.modelLevelSizes   = levelSizes;
            % Normalise to level-0-relative scale factors. The stored multiscales
            % 'scale' may be a physical voxel size (Zarr3Saver export) or already a
            % relative factor (createStore); dividing by level 0 yields the relative
            % pyramid factors [1; 2; 4; ...] in both cases, matching what
            % Zarr3VirtualSetupLoader produces for the image and what pickLevel /
            % getData63 expect.
            base = scaleFac(1, :);
            base(base == 0) = 1;
            obj.modelScaleFactors = scaleFac ./ base;
            obj.height    = levelSizes(1, 1);
            obj.width     = levelSizes(1, 2);
            obj.depth     = levelSizes(1, 3);
            obj.colors    = 1;
            obj.time      = 1;
            obj.dim_yxzct = [obj.height, obj.width, obj.depth, 1, 1];
            obj.dataClass = obj.containerClass;
            obj.maxInt    = double(intmax(obj.containerClass));
            obj.exists    = true;

            % restore the level map from the side-file (or fall back for old stores)
            obj.levelMapPath = core.MibBigDataLabels.levelMapPathFor(storePath);
            if ~obj.loadLevelMap(); obj.initLevelMapFallback(); end

            % restore material names/colours if previously saved (see writeMaterialMetadata)
            if isfield(attrs, 'mibMaterials')
                mm = attrs.mibMaterials;
                if isfield(mm, 'materialNames') && ~isempty(mm.materialNames)
                    names = mm.materialNames;
                    if ischar(names); names = {names}; end
                    if iscell(names); obj.materialNames = names(:); end
                end
                if isfield(mm, 'materialColors') && ~isempty(mm.materialColors) && isnumeric(mm.materialColors)
                    mc = double(mm.materialColors);
                    % JSON/zarr attribute round-trip can flatten/transpose the
                    % [nMaterials x 3] matrix (e.g. a single 1x3 colour comes back as
                    % 3x1). Normalise back to N x 3 so it is a valid RGB list.
                    if size(mc, 2) ~= 3 && size(mc, 1) == 3
                        mc = mc.';
                    end
                    obj.materialColors = mc;
                end
                obj.materialsCount = numel(obj.materialNames);
            end
            obj.maxIndexUsed = 0;
            if isfield(attrs, 'mibMaterials') && isfield(attrs.mibMaterials, 'maxIndexUsed')
                obj.maxIndexUsed = double(attrs.mibMaterials.maxIndexUsed);
            elseif strcmp(obj.containerClass, 'uint16')
                % no persisted value (store closed by a crash): the coarsest level
                % is the only affordable scan; objects lost to its downsampling
                % are missed, so the next new index may collide with one of them
                cs = obj.modelLevelSizes(end, :);
                coarsest = obj.readPackedLevel(nL, [1 cs(1)], [1 cs(2)], [1 max(1, cs(3))]);
                obj.maxIndexUsed = double(max(bitand(coarsest, obj.materialMask), [], 'all'));
            end
            if obj.maxMaterials > 255
                % uint16 instance model: two name slots; the count is the highest index
                obj.materialsCount = obj.maxIndexUsed;
                obj.objects3D = true;
                if isfield(attrs, 'mibMaterials') && isfield(attrs.mibMaterials, 'objects3D')
                    obj.objects3D = logical(attrs.mibMaterials.objects3D);
                end
                if numel(obj.materialNames) < 2; obj.materialNames = {'1'; '2'}; end
                if size(obj.materialColors, 1) < 65535; obj.materialColors = rand(65535, 3); end
            end

            % restore the instance index saved with the store, if it still applies
            obj.resetInstanceIndexState();
            obj.loadInstanceIndex();
        end

        function result = countMaterials(obj)
            % COUNTMATERIALS - materialsCount without scanning the store.
            %
            % Overrides ``core.MibLabels63.countMaterials``, which scans
            % ``obj.data`` - empty for a disk-backed model. The uint16 instance
            % layout answers from ``maxIndexUsed`` (an upper bound kept by
            % ``setData63``); the uint8 layout counts ``materialNames`` as before.
            %
            % Output Arguments:
            %   - **result** - double, the updated ``materialsCount``.
            if obj.maxMaterials > 255
                obj.materialsCount = obj.maxIndexUsed;
                result = obj.materialsCount;
            else
                result = countMaterials@core.MibLabels63(obj);
            end
        end

        function writeMaterialMetadata(obj)
            % WRITEMATERIALMETADATA - persist material names/colours to the store.
            %
            % Writes a ``mibMaterials`` attribute (alongside ``multiscales``) so
            % material names and colours survive a close/reopen of the model.
            % Call after material names/colours change (creation, rename, etc.).
            % No-op when the store is not open; best-effort (never throws).
            if strlength(obj.modelStorePath) == 0; return; end
            try
                grp = io.zarr.Group(char(obj.modelStorePath));
                attrs = grp.getAttributes();   % preserve existing (multiscales)
                names = obj.materialNames;
                if isempty(names); names = {}; end
                mm = struct('materialNames', {names});
                % an instance model's 65535 generated colours would make a multi-MB
                % JSON attribute rewritten on every material change; openStore
                % generates them again instead
                if ~isempty(obj.materialColors) && obj.maxMaterials < 256
                    mm.materialColors = obj.materialColors;
                end
                mm.maxIndexUsed = obj.maxIndexUsed;
                mm.objects3D    = obj.objects3D;
                attrs.mibMaterials = mm;
                grp.setAttributes(attrs);
            catch
                % persistence is best-effort; never block segmentation on it
            end
        end

        function levelIdx = pickLevel(obj, options)
            % PICKLEVEL - Choose the pyramid level index for the given read/write options.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      levelIdx = obj.pickLevel(options)
            %
            % Returns ``options.pyramidLevel`` when it is present and non-empty (explicit
            % override), otherwise finds the level whose ``modelScaleFactors(:,1)`` is
            % closest to ``options.magFactor`` (nearest-neighbour on the scale axis).
            % The result is clamped to ``[1, nLevels]``.
            %
            % Input Arguments:
            %   - **options** - [struct] with fields:
            %
            %     - ``.pyramidLevel`` *(optional)* - [numeric] explicit level (1 = finest).
            %     - ``.magFactor``    *(optional)* - [numeric] current display magnification
            %       factor (``dataset.magFactor``).  Default: ``1`` (full resolution).
            %
            % Output Arguments:
            %   - **levelIdx** - [numeric scalar] 1-based pyramid level index (1 = finest /
            %     full-resolution; ``nLevels`` = coarsest).
            if isfield(options, 'pyramidLevel') && ~isempty(options.pyramidLevel)
                levelIdx = options.pyramidLevel;
            else
                mf = 1;
                if isfield(options, 'magFactor') && ~isempty(options.magFactor); mf = options.magFactor; end
                [~, levelIdx] = min(abs(obj.modelScaleFactors(:, 1) - mf));
            end
            levelIdx = max(1, min(levelIdx, size(obj.modelLevelSizes, 1)));
        end

        function block = readPackedLevel(obj, levelIdx, Ylim, Xlim, Zlim)
            % READPACKEDLEVEL - read a packed [ny x nx x nz] block from one level.
            bbox = [Ylim(1), Ylim(2)+1; Xlim(1), Xlim(2)+1; Zlim(1), Zlim(2)+1];
            block = obj.modelArrays{levelIdx}.read(bbox);
            block = reshape(block, Ylim(2)-Ylim(1)+1, Xlim(2)-Xlim(1)+1, Zlim(2)-Zlim(1)+1);
        end

        function writePackedLevel(obj, levelIdx, block, Ylim, Xlim, Zlim)
            % WRITEPACKEDLEVEL - write a packed [ny x nx x nz] block to one level.
            bbox = [Ylim(1), Ylim(2)+1; Xlim(1), Xlim(2)+1; Zlim(1), Zlim(2)+1];
            obj.modelArrays{levelIdx}.write(cast(block, obj.containerClass), bbox);
        end

        function initLevelMapEmpty(obj)
            % INITLEVELMAPEMPTY - allocate an empty level map over the coarsest grid,
            % one plane per layer (labels, mask, selection).
            cs = obj.modelLevelSizes(end, :);            % coarsest [y x z]
            obj.matLevel = zeros([cs(1), cs(2), max(1, cs(3)), 3], 'uint8');
            obj.selectionTiles = false([cs(1), cs(2), max(1, cs(3))]);
        end

        function bits = layerGroupBits(obj)
            % LAYERGROUPBITS - packed bits of each layer of the level map, in the
            % order of its 4th dimension: [labels, mask, selection], of class
            % ``obj.containerClass``.
            bits = [cast(obj.materialMask, obj.containerClass), ...
                cast(obj.maskValue, obj.containerClass), cast(obj.selectionValue, obj.containerClass)];
        end

        function [ty, tx, tz] = tilesForFullRegion(obj, fullY, fullX, fullZ)
            % TILESFORFULLREGION - full-res region -> inclusive coarsest-grid tile ranges.
            sfN = obj.modelScaleFactors(end, :);         % coarsest [yScale xScale zScale]
            cs  = obj.modelLevelSizes(end, :);
            ty = [max(1, ceil(fullY(1)/sfN(1))), min(cs(1),          ceil(fullY(2)/sfN(1)))];
            tx = [max(1, ceil(fullX(1)/sfN(2))), min(cs(2),          ceil(fullX(2)/sfN(2)))];
            tz = [max(1, ceil(fullZ(1)/sfN(3))), min(max(1, cs(3)),  ceil(fullZ(2)/sfN(3)))];
        end

        function markTiles(obj, fullY, fullX, fullZ, levelIdx, layerGroups)
            % MARKTILES - set matLevel = levelIdx for every coarsest tile covering the
            % full-res region (latest-edit-wins: invalidates any finer materialization).
            % ``layerGroups`` *(optional)* - layers whose entries are set, as indices
            % into the 4th dimension of matLevel (1 labels, 2 mask, 3 selection);
            % default all three, for a write of the whole packed value.
            if nargin < 6 || isempty(layerGroups); layerGroups = 1:3; end
            if isempty(obj.matLevel); obj.initLevelMapEmpty(); end
            [ty, tx, tz] = obj.tilesForFullRegion(fullY, fullX, fullZ);
            obj.matLevel(ty(1):ty(2), tx(1):tx(2), tz(1):tz(2), layerGroups) = uint8(levelIdx);
        end

        function markTileHits(obj, tileY, tileX, tileZ, hits, levelIdx, layerGroups)
            % MARKTILEHITS - markTiles for the tiles of a tile window where ``hits``
            % is true only. ``tileY/tileX/tileZ`` - inclusive tile ranges of the
            % window, ``hits`` - logical of the window's size (from tilesHit).
            % A write marks only the tiles it changed: an unchanged tile keeps
            % its finer data, which is still exact.
            if isempty(obj.matLevel); obj.initLevelMapEmpty(); end
            window = obj.matLevel(tileY(1):tileY(2), tileX(1):tileX(2), tileZ(1):tileZ(2), :);
            for layer = layerGroups
                plane = window(:, :, :, layer);
                plane(hits) = uint8(levelIdx);
                window(:, :, :, layer) = plane;
            end
            obj.matLevel(tileY(1):tileY(2), tileX(1):tileX(2), tileZ(1):tileZ(2), :) = window;
        end

        function [tileY, tileX, tileZ, hits] = tilesHit(obj, levelIdx, voxelMask, Yl, Xl, Zl)
            % TILESHIT - which coarsest-grid tiles hold a true voxel of ``voxelMask``.
            % ``voxelMask`` - logical [y x z] block at level ``levelIdx`` over the
            % level index ranges ``Yl/Xl/Zl``. Returns the inclusive tile ranges
            % the block spans and ``hits``, a logical over that tile window. One
            % pass over the block, reducing rows, then columns, then slices of
            % each tile in turn.
            rowTiles   = obj.tileIndexOfLevelPixels(levelIdx, 1, Yl);
            colTiles   = obj.tileIndexOfLevelPixels(levelIdx, 2, Xl);
            sliceTiles = obj.tileIndexOfLevelPixels(levelIdx, 3, Zl);
            tileY = rowTiles([1 end]);  tileX = colTiles([1 end]);  tileZ = sliceTiles([1 end]);
            hits = anyPerTile(voxelMask, rowTiles - tileY(1) + 1, 1);
            hits = anyPerTile(hits, colTiles - tileX(1) + 1, 2);
            hits = anyPerTile(hits, sliceTiles - tileZ(1) + 1, 3);
        end

        function covered = tilesCovered(obj, levelIdx, Yl, Xl, Zl)
            % TILESCOVERED - logical over the tile window of a level-``levelIdx``
            % block (same window as tilesHit): true for a tile the block covers
            % whole, so the block holds everything there is of it at that level.
            % An edge tile of the volume counts as covered when the block reaches
            % the edge.
            sf = obj.modelScaleFactors(levelIdx, :);
            tileSize = obj.modelScaleFactors(end, :);
            volumeSize = [obj.height, obj.width, max(1, obj.depth)];
            ranges = {Yl, Xl, Zl};
            coveredAxis = cell(1, 3);
            for axis = 1:3
                pixels = obj.tileIndexOfLevelPixels(levelIdx, axis, ranges{axis});
                fullStart = (ranges{axis}(1) - 1) * sf(axis) + 1;
                fullEnd = min(ranges{axis}(2) * sf(axis), volumeSize(axis));
                tiles = pixels(1):pixels(end);
                coveredAxis{axis} = (tiles - 1) * tileSize(axis) + 1 >= fullStart & ...
                    min(tiles * tileSize(axis), volumeSize(axis)) <= fullEnd;
            end
            covered = reshape(coveredAxis{1}, [], 1) & reshape(coveredAxis{2}, 1, []) & ...
                reshape(coveredAxis{3}, 1, 1, []);
        end

        function noteSelectionWrite(obj, levelIdx, selectedVoxels, Yl, Xl, Zl, settles)
            % NOTESELECTIONWRITE - keep selectionTiles in step with a write.
            % ``selectedVoxels`` - logical [y x z] block at level ``levelIdx`` over
            % ``Yl/Xl/Zl``: the selection as written there. A tile with a selected
            % voxel becomes true. With ``settles`` true the block holds the whole
            % selection of the region, so a tile it covers whole (tilesCovered) and
            % has none in becomes false; with false nothing becomes false.
            %
            % Only where this level is authoritative for the selection (its matLevel
            % entry is this level or coarser - call after marking the write): a
            % tile whose selection lives at a finer level shows here only a nearest
            % downsample of it, in which a small piece can be missing.
            if isempty(obj.selectionTiles); return; end
            [tileY, tileX, tileZ, hasSelection] = obj.tilesHit(levelIdx, selectedVoxels, Yl, Xl, Zl);
            window = obj.selectionTiles(tileY(1):tileY(2), tileX(1):tileX(2), tileZ(1):tileZ(2));
            if settles
                selectionLevels = obj.matLevel(tileY(1):tileY(2), tileX(1):tileX(2), tileZ(1):tileZ(2), 3);
                settled = obj.tilesCovered(levelIdx, Yl, Xl, Zl) & ...
                    (selectionLevels >= levelIdx | selectionLevels == 0);
                window = hasSelection | (window & ~settled);
            else
                window = window | hasSelection;
            end
            obj.selectionTiles(tileY(1):tileY(2), tileX(1):tileX(2), tileZ(1):tileZ(2)) = window;
        end

        function [box, levelIdx, tileMask] = selectionFootprint(obj, fullZ, layerGroups)
            % SELECTIONFOOTPRINT - where the selection may be, over slices ``fullZ``.
            %
            % Returns:
            %   **box** - full-resolution box ``[y1 y2 x1 x2 z1 z2]`` over the
            %   selectionTiles tiles of the slices, aligned to whole tiles in y and
            %   x and clipped to ``fullZ`` in z; [] when no tile may hold selection.
            %   **levelIdx** - the finest level any layer of ``layerGroups``
            %   (planes of matLevel, default all three) holds data at in those
            %   tiles. An operation that rewrites those layers works there: a
            %   coarser level would replace finer data with the coarse version.
            %   **tileMask** - logical over the whole coarsest grid, the tiles.
            if nargin < 3 || isempty(layerGroups); layerGroups = 1:3; end
            box = []; levelIdx = []; tileMask = [];
            if isempty(obj.selectionTiles); return; end
            [~, ~, tileZ] = obj.tilesForFullRegion([1 1], [1 1], fullZ);
            tileMask = false(size(obj.selectionTiles));
            tileMask(:, :, tileZ(1):tileZ(2)) = obj.selectionTiles(:, :, tileZ(1):tileZ(2));
            if ~any(tileMask(:)); tileMask = []; return; end
            levels = obj.matLevel(:, :, :, layerGroups);
            levels = levels(repmat(tileMask, [1 1 1 numel(layerGroups)]));
            levels = levels(levels > 0);
            if isempty(levels)
                levelIdx = size(obj.modelLevelSizes, 1);   % nothing written yet: all zeros
            else
                levelIdx = double(min(levels));
            end
            tileSize = obj.modelScaleFactors(end, :);
            rows = find(any(tileMask, [2 3]));  cols = find(any(tileMask, [1 3]));  planes = find(any(tileMask, [1 2]));
            box = [(rows(1)-1)*tileSize(1)+1, min(rows(end)*tileSize(1), obj.height), ...
                   (cols(1)-1)*tileSize(2)+1, min(cols(end)*tileSize(2), obj.width), ...
                   max(fullZ(1), (planes(1)-1)*tileSize(3)+1), min(fullZ(2), planes(end)*tileSize(3))];
        end

        function updateSelectionBBoxFromWrite(obj, fullBlock, Yl, Xl, Zl, levelIdx)
            % UPDATESELECTIONBBOXFROMWRITE - keep selectionBBoxFull in sync after a
            % setData63 write that may have changed selection bits (type
            % 'selection'/'everything').
            %
            % Parameters:
            %   **fullBlock** - the WHOLE processed working block (the nearest-merged
            %   result over the incoming region [Yl Xl Zl]); its selection bit (bit 8,
            %   or 16 in the uint16 layout) is authoritative for the resulting
            %   selection over that region.
            %   **Yl/Xl/Zl** - working-level absolute index ranges of fullBlock.
            %   **levelIdx** - working level fullBlock lives at.
            %
            % The processed region [Yl Xl Zl] is the area we have authoritative info
            % over. When it fully covers the previous bbox we REPLACE (so a clear or a
            % selection→material consume shrinks/empties the box); otherwise we only
            % have partial info → never shrink, only UNION the new footprint in. Using
            % the exact selection bits (not the display block) catches a 1-pixel stroke.
            sf = obj.modelScaleFactors(levelIdx, :);
            writtenFull = [(Yl(1)-1)*sf(1)+1, min(Yl(2)*sf(1), obj.height), ...
                           (Xl(1)-1)*sf(2)+1, min(Xl(2)*sf(2), obj.width), ...
                           (Zl(1)-1)*sf(3)+1, min(Zl(2)*sf(3), obj.depth)];
            selOn = bitand(fullBlock, obj.selectionValue) > 0;
            if any(selOn(:))
                iy = find(any(any(selOn, 2), 3));   jx = find(any(any(selOn, 1), 3));   kz = find(any(any(selOn, 1), 2));
                ay = [Yl(1)+iy(1)-1, Yl(1)+iy(end)-1];
                ax = [Xl(1)+jx(1)-1, Xl(1)+jx(end)-1];
                az = [Zl(1)+kz(1)-1, Zl(1)+kz(end)-1];
                selFull = [(ay(1)-1)*sf(1)+1, min(ay(2)*sf(1), obj.height), ...
                           (ax(1)-1)*sf(2)+1, min(ax(2)*sf(2), obj.width), ...
                           (az(1)-1)*sf(3)+1, min(az(2)*sf(3), obj.depth)];
            else
                selFull = [];
            end
            prev = obj.selectionBBoxFull;
            writtenContainsPrev = isempty(prev) || ( ...
                writtenFull(1) <= prev(1) && writtenFull(2) >= prev(2) && ...
                writtenFull(3) <= prev(3) && writtenFull(4) >= prev(4) && ...
                writtenFull(5) <= prev(5) && writtenFull(6) >= prev(6));
            if writtenContainsPrev
                obj.selectionBBoxFull = selFull;            % authoritative → may reset to []
            elseif ~isempty(selFull)
                obj.selectionBBoxFull = core.MibBigDataLabels.bboxUnion(prev, selFull);
            end
        end

        function materializeForRead(obj, L, Yl, Xl, Zl)
            % MATERIALIZEFORREAD - ensure level L holds materialized data over the
            % level-L index window [Yl Xl Zl]. A layer of a tile whose matLevel entry
            % is coarser than L (matLevel > L) is recomputed by upsampling from that
            % source level, written to L, and its entry set to L. Bounded to this
            % window. Clean layers and tiles (matLevel <= L) are left untouched.
            %
            % Only the bits of the stale layers of the stale tiles are replaced: the
            % source block is read over the bounding box of those tiles, and the box
            % can include clean tiles, and clean layers of the stale ones, that hold
            % newer, finer data. Writing the upsampled box back whole would replace
            % that data with the coarse version (zooming in used to wipe a full-res
            % edit made between two coarse ones).
            %
            % Upsampling uses label-aware signed-distance smoothing (resizeBlockSmooth)
            % when the smoothing preference is on, so coarse-level block patterns do not
            % appear when zooming into a region drawn at a coarser zoom. Falls back to
            % nearest-neighbour when smoothing is off or when the target is not finer
            % (resizeBlockSmooth already handles this internally).
            if isempty(obj.matLevel); return; end
            sf = obj.modelScaleFactors(L, :);
            fullY = [(Yl(1)-1)*sf(1)+1, min(Yl(2)*sf(1), obj.height)];
            fullX = [(Xl(1)-1)*sf(2)+1, min(Xl(2)*sf(2), obj.width)];
            fullZ = [(Zl(1)-1)*sf(3)+1, min(Zl(2)*sf(3), obj.depth)];
            [ty, tx, tz] = obj.tilesForFullRegion(fullY, fullX, fullZ);
            win = obj.matLevel(ty(1):ty(2), tx(1):tx(2), tz(1):tz(2), :);
            stale = win > L;                             % finer-than-materialized layers of tiles
            if ~any(stale(:)); return; end
            smoothOn = io.zarr.Config.smoothing();
            layerBits = obj.layerGroupBits();
            sfN = obj.modelScaleFactors(end, :);         % tile size in full-res px = coarsest scale
            for A = reshape(unique(double(win(stale))), 1, [])
                sourceTiles = stale & win == A;          % [tiles y x z, layer]
                [iy, ix, iz] = ind2sub(size(sourceTiles, 1:3), find(any(sourceTiles, 4)));
                tY = [min(iy)+ty(1)-1, max(iy)+ty(1)-1];
                tX = [min(ix)+tx(1)-1, max(ix)+tx(1)-1];
                tZ = [min(iz)+tz(1)-1, max(iz)+tz(1)-1];
                fY = [(tY(1)-1)*sfN(1)+1, min(tY(2)*sfN(1), obj.height)];
                fX = [(tX(1)-1)*sfN(2)+1, min(tX(2)*sfN(2), obj.width)];
                fZ = [(tZ(1)-1)*sfN(3)+1, min(tZ(2)*sfN(3), obj.depth)];
                [aY, aX, aZ] = obj.regionForLevel(A, fY, fX, fZ);
                src = obj.readPackedLevel(A, aY, aX, aZ);
                [lY, lX, lZ] = obj.regionForLevel(L, fY, fX, fZ);
                tgtSize = [lY(2)-lY(1)+1, lX(2)-lX(1)+1, lZ(2)-lZ(1)+1];
                if smoothOn
                    upsampled = core.MibBigDataLabels.resizeBlockSmooth(src, tgtSize);
                else
                    upsampled = core.MibBigDataLabels.resizeBlockNearest(src, tgtSize);
                end
                boxTiles = sourceTiles(tY(1)-ty(1)+1:tY(2)-ty(1)+1, tX(1)-tx(1)+1:tX(2)-tx(1)+1, ...
                    tZ(1)-tz(1)+1:tZ(2)-tz(1)+1, :);
                if all(boxTiles(:))
                    block = upsampled;
                else
                    % tile of every level-L voxel of the box, relative to the box
                    rowTiles   = min(size(boxTiles, 1), max(1, obj.tileIndexOfLevelPixels(L, 1, lY) - tY(1) + 1));
                    colTiles   = min(size(boxTiles, 2), max(1, obj.tileIndexOfLevelPixels(L, 2, lX) - tX(1) + 1));
                    sliceTiles = min(size(boxTiles, 3), max(1, obj.tileIndexOfLevelPixels(L, 3, lZ) - tZ(1) + 1));
                    block = obj.readPackedLevel(L, lY, lX, lZ);
                    for layer = 1:3
                        if ~any(boxTiles(:, :, :, layer), 'all'); continue; end
                        replace = boxTiles(rowTiles, colTiles, sliceTiles, layer);
                        block(replace) = bitor(bitand(block(replace), bitcmp(layerBits(layer))), ...
                            bitand(upsampled(replace), layerBits(layer)));
                    end
                end
                obj.writePackedLevel(L, block, lY, lX, lZ);
                win(sourceTiles) = uint8(L);
            end
            obj.matLevel(ty(1):ty(2), tx(1):tx(2), tz(1):tz(2), :) = win;
        end

        function tiles = tileIndexOfLevelPixels(obj, levelIdx, axis, pixelRange)
            % TILEINDEXOFLEVELPIXELS - coarsest-grid tile index of each pixel of a
            % level-``levelIdx`` index range along ``axis`` (1 y, 2 x, 3 z), taken
            % from the full-resolution position of the pixel's first voxel and
            % clamped to the grid.
            fullStart = ((pixelRange(1):pixelRange(2)) - 1) * obj.modelScaleFactors(levelIdx, axis) + 1;
            tileCount = max(1, obj.modelLevelSizes(end, axis));
            tiles = min(tileCount, max(1, ceil(fullStart / obj.modelScaleFactors(end, axis))));
        end

        function materializeAll(obj, pwbFcn)
            % MATERIALIZEALL - materialize every non-empty tile down to level 1 (Save).
            % Walks the coarsest grid one tile-row per step (bounded), recomputing each
            % finer level for that row; sets matLevel = 1 for materialized tiles.
            if nargin < 2; pwbFcn = []; end
            if isempty(obj.matLevel); return; end
            nT = size(obj.matLevel, 1);
            for r = 1:nT
                rowLevels = obj.matLevel(r, :, :, :);
                if all(rowLevels(:) <= 1); continue; end   % already at finest (or empty)
                sfN = obj.modelScaleFactors(end, :);
                fY = [(r-1)*sfN(1)+1, min(r*sfN(1), obj.height)];
                fX = [1, obj.width]; fZ = [1, obj.depth];
                [lY, lX, lZ] = obj.regionForLevel(1, fY, fX, fZ);
                obj.materializeForRead(1, lY, lX, lZ);
                if ~isempty(pwbFcn); pwbFcn(r/nT); end
            end
        end

        function saveLevelMap(obj)
            % SAVELEVELMAP - persist matLevel to the side-file (<storePath>.levelmap).
            % The file has no '.mat' extension, so '-mat' forces MAT format on save.
            % Also persists the instance index (saveInstanceIndex), so everything
            % that saves the session state of the store - Save model, closeStore,
            % importMaterial - saves both.
            obj.saveInstanceIndex();
            if isempty(obj.levelMapPath) || isempty(obj.matLevel); return; end
            % mapVersion 2: one level map per layer (4th dimension of matLevel), and
            % the tiles that may hold selection
            S = struct('matLevel', obj.matLevel, 'mapVersion', 2, ...
                'coarsestSize', obj.modelLevelSizes(end, :), 'selectionTiles', obj.selectionTiles);
            save(obj.levelMapPath, '-struct', 'S', '-v7', '-mat');
        end

        function tf = loadLevelMap(obj)
            % LOADLEVELMAP - restore matLevel from the side-file; false if missing/mismatched.
            % '-mat' forces MAT parsing since the file has no '.mat' extension. A
            % mapVersion 1 file holds one map for all layers; it is copied to each,
            % which is what it meant. It has no selectionTiles either: every tile
            % may then hold selection.
            tf = false;
            if isempty(obj.levelMapPath) || ~isfile(obj.levelMapPath); return; end
            S = load(obj.levelMapPath, '-mat');
            if isfield(S, 'matLevel') && isequal(size(S.matLevel, 1:2), obj.modelLevelSizes(end, 1:2))
                levelMap = uint8(S.matLevel);
                if size(levelMap, 4) == 1; levelMap = repmat(levelMap, [1 1 1 3]); end
                obj.matLevel = levelMap; tf = true;
                if isfield(S, 'selectionTiles') && isequal(size(S.selectionTiles, 1:3), size(levelMap, 1:3))
                    obj.selectionTiles = logical(S.selectionTiles);
                else
                    obj.selectionTiles = true(size(levelMap, 1:3));
                end
            end
        end

        function initLevelMapFallback(obj)
            % INITLEVELMAPFALLBACK - no side-file: assume the on-disk pyramid is already
            % PRECISE at every level (matLevel = 1, i.e. fully materialized).
            %
            % This is the correct assumption for an imported / externally-created model
            % (all levels were properly downsampled when written) and for any model MIB
            % saved fully - MIB always persists the sidecar on closeStore, so a MISSING
            % sidecar means "not a deferred interactive session", i.e. nothing virtual.
            %
            % It must NOT assume coarsest-only: doing so would make the first zoom-in
            % past the coarsest level trigger materializeForRead, which upsamples the
            % coarsest data and OVERWRITES the precise finer levels - silently degrading
            % an imported model. With matLevel = 1, reads go straight to the requested
            % level; later edits degrade only the touched tiles (markTiles), which are
            % then recomputed lazily on read or rewritten on Save.
            obj.initLevelMapEmpty();
            obj.matLevel(:) = 1;
            obj.selectionTiles(:) = true;   % unknown: the store may hold selection anywhere
        end

        function syncInstanceIndex(obj, index, remainingDirtyBox)
            % SYNCINSTANCEINDEX - Record the instance index that now describes the store.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.syncInstanceIndex(index)
            %      obj.syncInstanceIndex(index, remainingDirtyBox)
            %
            % Called by ``core.MibDataset.buildInstanceIndex`` after every build,
            % repair or refresh. From here on setData63 grows ``indexDirtyBox``
            % with every labels change, so the next build only has to re-measure
            % that box instead of the whole store.
            %
            % Nothing is written to disk here: the side-file left on disk, if any,
            % still describes the store (it is deleted on the first change, see
            % markLabelsChanged), and ``saveInstanceIndex`` brings it up to date
            % on Save model or closeStore. Writing it on every editor operation
            % would add a file write to each click for no gain in safety.
            %
            % Input Arguments:
            %   - **index** - index struct as returned by ``buildInstanceIndex``
            %   - **remainingDirtyBox** - *(optional)* ``[y0 y1 x0 x1 z0 z1]`` of
            %     changes the index does not yet account for (default ``[]``). A
            %     refresh of named objects vouches for its own box only, so a
            %     pending dirty box outside it has to survive the refresh.
            if nargin < 3; remainingDirtyBox = []; end
            obj.syncedInstanceIndex = index;
            obj.indexDirtyBox = remainingDirtyBox;
            obj.instanceIndexUnsaved = true;
        end

        function markLabelsChanged(obj, fullBox)
            % MARKLABELSCHANGED - Note a labels change for the instance index.
            %
            % Called by setData63 for every write that changed the labels bits.
            % Grows ``indexDirtyBox`` by ``fullBox`` (full-resolution
            % ``[y0 y1 x0 x1 z0 z1]``). Does nothing when no index has been synced,
            % because then there is nothing for the box to be relative to.
            %
            % The first change after the side-file was written deletes it: from
            % this write on it would describe a store that no longer exists, and
            % if MIB crashed before the next Save, a reopen would trust it.
            if isempty(obj.syncedInstanceIndex); return; end
            obj.indexDirtyBox = core.MibBigDataLabels.bboxUnion(obj.indexDirtyBox, fullBox);
            obj.instanceIndexUnsaved = true;
            if obj.instanceIndexOnDisk
                indexPath = core.MibBigDataLabels.instanceIndexPathFor(obj.modelStorePath);
                if isfile(indexPath); delete(indexPath); end
                obj.instanceIndexOnDisk = false;
            end
        end

        function saveInstanceIndex(obj)
            % SAVEINSTANCEINDEX - Write the instance index and its dirty box to the side-file.
            %
            % Writes ``<storePath>.instanceindex`` (MAT format) when there is a
            % synced index that differs from what is on disk; no-op otherwise.
            % Called from saveLevelMap, and directly by
            % ``core.MibDataset.buildInstanceIndex`` after a full scan, which is
            % the one result too expensive to lose to a crash. Best-effort: a
            % failed write leaves the next open to rebuild, it never blocks.
            if isempty(obj.syncedInstanceIndex) || ~obj.instanceIndexUnsaved || ...
                    strlength(obj.modelStorePath) == 0
                return;
            end
            S = struct('instanceIndex', obj.syncedInstanceIndex, ...
                'indexDirtyBox', obj.indexDirtyBox, 'indexVersion', 1, ...
                'storeSize', obj.modelLevelSizes(1, :));
            try
                save(core.MibBigDataLabels.instanceIndexPathFor(obj.modelStorePath), ...
                    '-struct', 'S', '-v7', '-mat');
                obj.instanceIndexOnDisk = true;
                obj.instanceIndexUnsaved = false;
            catch
                % best-effort, see above
            end
        end

        function tf = loadInstanceIndex(obj)
            % LOADINSTANCEINDEX - Restore the instance index from the side-file.
            %
            % Accepted only when the file was written for a store of the same
            % full-resolution size; anything else is ignored and the index is
            % rebuilt on demand.
            %
            % Output Arguments:
            %   - **tf** - logical, true when an index was restored
            tf = false;
            indexPath = core.MibBigDataLabels.instanceIndexPathFor(obj.modelStorePath);
            if ~isfile(indexPath); return; end
            try
                S = load(indexPath, '-mat');
            catch
                return;
            end
            if ~isfield(S, 'instanceIndex') || ~isfield(S, 'indexDirtyBox') || ...
                    ~isfield(S, 'storeSize') || ~isequal(double(S.storeSize), obj.modelLevelSizes(1, :))
                return;
            end
            obj.syncedInstanceIndex = S.instanceIndex;
            obj.indexDirtyBox = S.indexDirtyBox;
            obj.instanceIndexOnDisk = true;
            obj.instanceIndexUnsaved = false;
            tf = true;
        end

        function resetInstanceIndexState(obj)
            % RESETINSTANCEINDEXSTATE - Forget the synced instance index (new or reopened store).
            obj.syncedInstanceIndex = [];
            obj.indexDirtyBox = [];
            obj.instanceIndexOnDisk = false;
            obj.instanceIndexUnsaved = false;
        end
    end

    methods (Access = private)
        function [physYlim, physXlim, physZlim] = orientPhysRanges(obj, levelIdx, orient, options)
            % ORIENTPHYSRANGES - map a screen request (orient + options.x/y/z) to the
            % physical [Y X Z] index ranges of pyramid level levelIdx, using the EXACT
            % convention of MibVirtualImage.getDataZarr so the model overlay lines up
            % with the image in every orientation. Shared by getData63 (read) and
            % setData63 (write) so the two are inverses by construction.
            %
            % options: .x = horizontal screen range, .y = vertical, .z = slice/depth;
            % mapped to the physical data axes per orientation, scaled by each axis'
            % own pyramid factor, and clamped to that physical dimension.
            fullSize = obj.modelLevelSizes(1, :);   % [Y X Z]
            switch orient
                case 1  % zx: vertical = Z, horizontal = X, slice = Y
                    if ~isfield(options, 'y') || isempty(options.y); options.y = [1, fullSize(3)]; end
                    if ~isfield(options, 'x') || isempty(options.x); options.x = [1, fullSize(2)]; end
                    if ~isfield(options, 'z') || isempty(options.z); options.z = [1, fullSize(1)]; end
                    physYfull = options.z; physXfull = options.x; physZfull = options.y;
                case 2  % yz: vertical = Y, horizontal = Z, slice = X
                    if ~isfield(options, 'y') || isempty(options.y); options.y = [1, fullSize(1)]; end
                    if ~isfield(options, 'x') || isempty(options.x); options.x = [1, fullSize(3)]; end
                    if ~isfield(options, 'z') || isempty(options.z); options.z = [1, fullSize(2)]; end
                    physYfull = options.y; physXfull = options.z; physZfull = options.x;
                otherwise  % 3 yx: vertical = Y, horizontal = X, slice = Z
                    if ~isfield(options, 'y') || isempty(options.y); options.y = [1, fullSize(1)]; end
                    if ~isfield(options, 'x') || isempty(options.x); options.x = [1, fullSize(2)]; end
                    if ~isfield(options, 'z') || isempty(options.z); options.z = [1, fullSize(3)]; end
                    physYfull = options.y; physXfull = options.x; physZfull = options.z;
            end
            sf  = obj.modelScaleFactors(levelIdx, :);   % [yScale xScale zScale]
            lvl = obj.modelLevelSizes(levelIdx, :);      % [Y X Z]
            physYlim = ceil(physYfull ./ sf(1));
            physXlim = ceil(physXfull ./ sf(2));
            physZlim = ceil(physZfull ./ sf(3));
            physYlim = [max(physYlim(1), 1), min(physYlim(2), lvl(1))];
            physXlim = [max(physXlim(1), 1), min(physXlim(2), lvl(2))];
            physZlim = [max(physZlim(1), 1), min(physZlim(2), lvl(3))];
        end

        function [Yl, Xl, Zl] = regionForLevel(obj, levelIdx, fullY, fullX, fullZ)
            % REGIONFORLEVEL - map a full-resolution YXZ region to a level's
            % clamped index range (shared by setData63 / getData63 / propagateRegion).
            sf = obj.modelScaleFactors(levelIdx, :);
            lv = obj.modelLevelSizes(levelIdx, :);
            Yl = core.MibBigDataLabels.clampRange([ceil(fullY(1)/sf(1)), ceil(fullY(2)/sf(1))], lv(1));
            Xl = core.MibBigDataLabels.clampRange([ceil(fullX(1)/sf(2)), ceil(fullX(2)/sf(2))], lv(2));
            Zl = core.MibBigDataLabels.clampRange([ceil(fullZ(1)/sf(3)), ceil(fullZ(2)/sf(3))], lv(3));
        end

        function propagateRegion(obj, packed, fullY, fullX, fullZ, sourceLevelIdx, direction, layerGroups)
            % PROPAGATEREGION - write a merged working-level block into other pyramid
            % levels. Downsampling (source finer than target) uses a nearest-neighbour
            % resize. Up-sampling (source coarser than target, i.e. an edit made
            % zoomed-out pushed into a higher-magnification level) uses a smooth,
            % label-aware resize when io.zarr.Config.smoothing is on.
            %
            % ``direction`` (optional) selects which levels to write - finer levels are
            % numerically SMALLER indices (level 1 = full resolution):
            %   - ``'all'``     - every other level (default)
            %   - ``'coarser'`` - only levels coarser than the source (index > source);
            %                     a cheap downsample, done eagerly per edit
            %   - ``'finer'``   - only levels finer than the source (index < source);
            %                     the expensive upsample toward full res, deferred/lazy
            %
            % ``layerGroups`` (optional) - layers whose bits are written, as indices
            % into ``layerGroupBits`` (1 labels, 2 mask, 3 selection); default all
            % three. With fewer, the target is read and only those bits replaced,
            % so a selection write leaves the labels of a coarser level exactly as
            % they were - that level may be the one the labels were drawn at.
            if nargin < 7 || isempty(direction); direction = 'all'; end
            if nargin < 8 || isempty(layerGroups); layerGroups = 1:3; end
            keptBits = cast(0, obj.containerClass);
            if numel(layerGroups) < 3
                layerBits = obj.layerGroupBits();
                keptBits = bitor(bitor(layerBits(1), layerBits(2)), layerBits(3));
                for layer = layerGroups; keptBits = bitxor(keptBits, layerBits(layer)); end
            end
            smoothOn = io.zarr.Config.smoothing();
            srcSize  = size(packed, 1:3);
            % Memory guards: an edit made zoomed-out can span (nearly) the whole slide,
            % so a finer target level can be GIGABYTES (e.g. full-res 38144x51200 ~ 2 GB).
            % Never materialise that in one array: boundary-smoothing is only worth its
            % cost (and ~6x memory) on SMALL targets; larger upsamples use a tiled,
            % index-based nearest copy whose peak memory is one strip (~tileBudget bytes).
            smoothBudget = 4e6;     % max target pixels for resizeBlockSmooth
            tileBudget   = 8e6;     % max pixels materialised per nearest write (strip)
            for L2 = 1:size(obj.modelLevelSizes, 1)
                if L2 == sourceLevelIdx; continue; end
                if strcmp(direction, 'coarser') && L2 < sourceLevelIdx; continue; end
                if strcmp(direction, 'finer')   && L2 > sourceLevelIdx; continue; end
                [A2, B2, C2] = obj.regionForLevel(L2, fullY, fullX, fullZ);
                targetSize = [A2(2)-A2(1)+1, B2(2)-B2(1)+1, C2(2)-C2(1)+1];
                isUpsample = targetSize(1) > srcSize(1) || targetSize(2) > srcSize(2);
                if smoothOn && isUpsample && prod(targetSize) <= smoothBudget
                    block2 = core.MibBigDataLabels.resizeBlockSmooth(packed, targetSize);
                    if keptBits ~= 0
                        block2 = bitor(bitand(obj.readPackedLevel(L2, A2, B2, C2), keptBits), ...
                            bitand(block2, bitcmp(keptBits)));
                    end
                    obj.writePackedLevel(L2, block2, A2, B2, C2);
                else
                    % Tiled, index-based nearest resize written in Y-strips so peak
                    % memory stays ~tileBudget pixels - never materialise a multi-GB
                    % full-resolution array (inlined, no separate method, so this body
                    % hot-reloads onto a live model instance without a MIB restart).
                    pk = cast(packed, obj.containerClass);
                    sy = size(pk, 1); sx = size(pk, 2); sz = size(pk, 3);
                    ty = targetSize(1); tx = targetSize(2); tz = targetSize(3);
                    xMap = min(sx, max(1, floor((0:tx-1) * sx / tx) + 1));
                    zMap = min(sz, max(1, floor((0:tz-1) * sz / tz) + 1));
                    yMap = min(sy, max(1, floor((0:ty-1) * sy / ty) + 1));
                    rowsPerStrip = max(1, floor(tileBudget / (max(1, tx) * max(1, tz))));
                    for r0 = 1:rowsPerStrip:ty
                        r1 = min(ty, r0 + rowsPerStrip - 1);
                        sub = pk(yMap(r0:r1), xMap, zMap);   % [(r1-r0+1) x tx x tz]
                        if keptBits ~= 0
                            sub = bitor(bitand(obj.readPackedLevel(L2, [A2(1)+r0-1, A2(1)+r1-1], B2, C2), keptBits), ...
                                bitand(sub, bitcmp(keptBits)));
                        end
                        obj.writePackedLevel(L2, sub, [A2(1)+r0-1, A2(1)+r1-1], B2, C2);
                    end
                end
            end
        end

        function writeMultiscales(obj, grp, scaleFac)
            % WRITEMULTISCALES - minimal OME-NGFF multiscales attribute so the model
            % group reopens as a pyramid (Phase 3 saver enriches voxel size / bbox).
            %
            % Also stamps the ``mibModelStore`` marker. It matters for zarr v2,
            % where a store MIB wrote (packed bytes in [y,x,z], editable) and one
            % another tool wrote (plain label indices in its own axis order,
            % read-only) are otherwise indistinguishable - see
            % ``core.MibBigDataLabels.isMibModelStore``.
            nLevels = numel(obj.modelLevelNames);
            axes = {struct('name','y','type','space'), ...
                    struct('name','x','type','space'), ...
                    struct('name','z','type','space')};
            datasets = cell(1, nLevels);
            for L = 1:nLevels
                datasets{L} = struct('path', obj.modelLevelNames{L}, ...
                    'coordinateTransformations', {{struct('type','scale','scale', scaleFac(L,:))}});
            end
            ms = struct('version','0.5', 'axes', {axes}, 'datasets', {datasets});
            marker = core.MibBigDataLabels.storeMarker();
            marker.layout = sprintf('packed-%s-yxz', obj.containerClass);
            grp.setAttributes(struct('multiscales', {{ms}}, 'mibModelStore', marker));
        end
    end

    methods (Static)
        function marker = storeMarker()
            % STOREMARKER - the ``mibModelStore`` attribute stamped on a MIB model store.
            %
            % ``layout`` records the two things a reader has to assume to use the
            % arrays directly: values are MIB's packed byte, and the axes are
            % ``[y, x, z]``. ``version`` is there so a future layout change can be
            % detected rather than silently misread. This returns the uint8 marker;
            % ``writeMultiscales`` rewrites ``layout`` to ``'packed-uint16-yxz'`` for
            % a uint16 store. ``openStore`` takes the layout from the array data
            % type, not from this field, so older stores need no marker update.
            marker = struct('version', 1, 'layout', 'packed-uint8-yxz');
        end

        function format = zarrFormatFromPath(storePath)
            % ZARRFORMATFROMPATH - zarr format implied by a store path's extension.
            %
            % ``.zarr2`` means v2; anything else (``.zarr3``, ``.zarr``, no
            % extension) means v3, which keeps every existing caller unchanged.
            %
            % Input Arguments:
            %   - **storePath** - [char|string] store path.
            %
            % Output Arguments:
            %   - **format** - [numeric] 2 or 3.
            [~, ~, ext] = fileparts(char(storePath));
            if strcmpi(ext, '.zarr2'); format = 2; else; format = 3; end
        end

        function tf = isMibModelStore(storePath)
            % ISMIBMODELSTORE - was this store written by MIB as an editable model?
            %
            % Reads the group's ``mibModelStore`` marker (see ``storeMarker``).
            % This is what separates an editable MIB model store from a foreign
            % label store that happens to be a multiscales group of uint8 arrays:
            % the two are indistinguishable from their pixels alone, and writing
            % MIB's packed bytes into a foreign store would corrupt it.
            %
            % Never throws - an unreadable or absent store simply answers
            % ``false``, which routes to the read-only path.
            %
            % Older MIB stores predate the marker. That costs nothing in
            % practice: zarr v3 stores are always opened by this class anyway,
            % and a v2 model store could not be created before this marker
            % existed, so there are none in the wild to misclassify.
            %
            % Input Arguments:
            %   - **storePath** - [char|string] store path or URL.
            %
            % Output Arguments:
            %   - **tf** - [logical] true when the marker is present.
            tf = false;
            try
                attrs = io.zarr.Group(char(storePath)).getAttributes();
                tf = isfield(attrs, 'mibModelStore');
            catch
                % not a readable zarr group -> not a MIB model store
            end
        end

        function p = levelMapPathFor(storePath)
            % LEVELMAPPATHFOR - side-file path for the level map of a model store.
            % Replaces the store's extension (e.g. '.zarr3') with '.levelmap' so the
            % sidecar sits next to the store as '<name>.levelmap' (a MAT-format file
            % saved/loaded with the '-mat' key; NOT '<name>.zarr3.levelmap.mat').
            storePath = char(storePath);
            [folder, name] = fileparts(storePath);
            p = fullfile(folder, [name '.levelmap']);
        end

        function p = instanceIndexPathFor(storePath)
            % INSTANCEINDEXPATHFOR - side-file path holding the instance index of a
            % model store: '<folder>/<name>.instanceindex', next to the levelmap.
            [folder, name] = fileparts(char(storePath));
            p = fullfile(folder, [name '.instanceindex']);
        end

        function bb = bboxUnion(a, b)
            % BBOXUNION - union of two [y0 y1 x0 x1 z0 z1] boxes ([] acts as empty).
            if isempty(a); bb = b; return; end
            if isempty(b); bb = a; return; end
            bb = [min(a(1), b(1)), max(a(2), b(2)), ...
                  min(a(3), b(3)), max(a(4), b(4)), ...
                  min(a(5), b(5)), max(a(6), b(6))];
        end

        function out = resizeBlockNearest(block, targetSize)
            % RESIZEBLOCKNEAREST - nearest-neighbour resize of a packed [y x z] uint8
            % or uint16 block to targetSize=[ty tx tz], preserving exact packed values.
            % Integer input keeps its class; anything else is cast to uint8.
            if ~isinteger(block); block = uint8(block); end
            sz = size(block, 1:3);
            ty = targetSize(1); tx = targetSize(2); tz = targetSize(3);
            if isequal(sz, [ty tx tz]); out = block; return; end
            if sz(3) == 1
                % single source slice -> resize YX, replicate across tz
                yx = imresize(block(:,:,1), [ty tx], 'nearest');
                out = repmat(reshape(yx, ty, tx, 1), [1 1 tz]);
            elseif tz == 1
                % collapse to one target slice -> use the source mid-slice, YX-resized
                out = reshape(imresize(block(:,:,max(1,round(sz(3)/2))), [ty tx], 'nearest'), ty, tx, 1);
            else
                out = imresize3(block, [ty tx tz], 'nearest');
            end
        end

        function out = resizeBlockSmooth(block, targetSize)
            % RESIZEBLOCKSMOOTH - label-aware, boundary-smoothing UP-sample of a
            % packed [y x z] block to targetSize=[ty tx tz].
            %
            % The packed layout follows the block's class: uint8 = material bits
            % 1-6, mask bit 7, selection bit 8; uint16 = index bits 1-14, mask bit
            % 15, selection bit 16 (see ``core.MibLabels63.setLayout``). Any other
            % class is cast to uint8. Taking the layout from the class keeps this a
            % static method with an unchanged signature.
            %
            % Packed integers cannot be interpolated directly, so the three layers
            % (material, mask, selection) are unpacked and each is upsampled with
            % smoothing in YX, then repacked. Smoothing uses a
            % **signed distance transform**: each region's signed distance field
            % (positive inside, negative outside) is a smooth function that is bicubic
            % upsampled and Gaussian-smoothed (sigma = half the up-sampling factor);
            % thresholding the result at 0 reconstructs a smooth boundary at sub-pixel
            % accuracy (a coarse circle becomes a smooth circle, not a faceted one - far
            % better than bilinear-on-binary, which only rounds a one-pixel ramp). The
            % Gaussian erases the working-level stair-steps while the modest sigma keeps
            % thin structures from being eroded.
            %
            %   - materials: per-label signed-distance upsample + arg-max;
            %   - mask / selection: signed-distance upsample of the binary indicator.
            %
            % Z is resized first with nearest (the pyramid keeps Z, so usually a no-op).
            % Falls back to nearest when not actually up-sampling in YX.
            if ~isa(block, 'uint16'); block = uint8(block); end
            bits = 8 * (1 + isa(block, 'uint16'));      % 8 or 16
            sz = size(block, 1:3);
            ty = targetSize(1); tx = targetSize(2); tz = targetSize(3);
            if isequal(sz, [ty tx tz]); out = block; return; end
            if ty <= sz(1) && tx <= sz(2)
                out = core.MibBigDataLabels.resizeBlockNearest(block, targetSize);
                return;
            end
            % match Z first (nearest); usually sz(3)==tz so this is skipped
            if sz(3) ~= tz
                block = core.MibBigDataLabels.resizeBlockNearest(block, [sz(1) sz(2) tz]);
            end
            material = bitand(block, 2^(bits-2) - 1);
            maskBit  = bitget(block, bits - 1);
            selBit   = bitget(block, bits);
            out = zeros(ty, tx, tz, 'like', block);
            for z = 1:tz
                lab = core.MibBigDataLabels.smoothLabelUpsampleYX(material(:, :, z), [ty tx]);
                k   = cast(core.MibBigDataLabels.signedDistUpsample(maskBit(:, :, z) > 0, [ty tx]), 'like', block);
                s   = cast(core.MibBigDataLabels.signedDistUpsample(selBit(:, :, z)  > 0, [ty tx]), 'like', block);
                out(:, :, z) = bitor(bitor(lab, k * 2^(bits-2)), s * 2^(bits-1));
            end
        end

        function out = resizeLayerSmooth(layer, targetSize, isLabelMap)
            % RESIZELAYERSMOOTH - smooth UP-sample of a raw (unpacked) layer to
            % targetSize=[ty tx tz], used by setData63 to bring a brush stroke captured
            % at display resolution onto a finer working level without blocky steps.
            %
            %   - isLabelMap=true  -> multi-material map (values 0-63, or 0-16383 for
            %     the uint16 layout): per-label SDF arg-max (smoothLabelUpsampleYX);
            %   - isLabelMap=false -> binary layer (selection / mask / single-material
            %     indicator): signed-distance upsample.
            %
            % Integer input keeps its class (uint16 instance ids must not be cut to
            % uint8); anything else, logical included, is cast to uint8.
            %
            % Z is matched first with nearest. Falls back to nearest when not up-sampling
            % in YX (down-sample / equal size).
            if ~isinteger(layer); layer = uint8(layer); end
            sz = size(layer, 1:3);
            ty = targetSize(1); tx = targetSize(2); tz = targetSize(3);
            if isequal(sz, [ty tx tz]); out = layer; return; end
            if ty <= sz(1) && tx <= sz(2)
                out = core.MibBigDataLabels.resizeBlockNearest(layer, targetSize);
                return;
            end
            if sz(3) ~= tz
                layer = core.MibBigDataLabels.resizeBlockNearest(layer, [sz(1) sz(2) tz]);
            end
            out = zeros(ty, tx, tz, 'like', layer);
            for z = 1:tz
                if isLabelMap
                    out(:, :, z) = core.MibBigDataLabels.smoothLabelUpsampleYX(layer(:, :, z), [ty tx]);
                else
                    out(:, :, z) = core.MibBigDataLabels.signedDistUpsample(layer(:, :, z) > 0, [ty tx]);
                end
            end
        end

        function F = smoothDistField(D, targetYX)
            % SMOOTHDISTFIELD - bicubic-upsample a signed distance field D to targetYX
            % and Gaussian-smooth it so the zero level set is a smooth curve (not a
            % working-level facet polygon). Sigma is half the up-sampling factor: large
            % enough to erase the coarse grid stair-steps, small enough to keep thin
            % structures from being eroded by curvature flow.
            srcYX = [size(D, 1), size(D, 2)];
            upFactor = sqrt((targetYX(1) / srcYX(1)) * (targetYX(2) / srcYX(2)));
            sigma = max(1, 0.5 * upFactor);
            F = imresize(double(D), targetYX, 'bicubic');
            F = imgaussfilt(F, sigma);
        end

        function out = signedDistUpsample(maskSlice, targetYX)
            % SIGNEDDISTUPSAMPLE - smooth boundary up-sample of a 2-D binary mask via a
            % signed distance transform: D = bwdist(~M) - bwdist(M) (>0 inside), upsampled
            % + Gaussian-smoothed (smoothDistField), then thresholded at 0. Reconstructs a
            % smooth boundary at sub-pixel accuracy. Returns a logical [ty tx]. Empty/full
            % masks short-circuit (bwdist would be Inf and break the interpolation).
            ty = targetYX(1); tx = targetYX(2);
            if ~any(maskSlice(:)); out = false(ty, tx); return; end
            if all(maskSlice(:));  out = true(ty, tx);  return; end
            D = bwdist(~maskSlice) - bwdist(maskSlice);
            out = core.MibBigDataLabels.smoothDistField(D, [ty tx]) >= 0;
        end

        function lab = smoothLabelUpsampleYX(labSlice, targetYX)
            % SMOOTHLABELUPSAMPLEYX - smooth up-sample of a 2-D label slice. For every
            % label (incl. background 0) the signed distance field of its region is
            % upsampled + Gaussian-smoothed (smoothDistField); each output pixel takes the
            % arg-max label. Because the distance field is smooth across the whole region
            % (not just a 1-px ramp), boundaries reconstruct as smooth curves rather than
            % working-level facets.
            %
            % The cost is one bwdist pair plus a bicubic upsample per distinct label,
            % which is fine for a 63-material model but not for an instance slice
            % holding hundreds of objects (uint16 layout, up to 16383). Above
            % ``maxSmoothedLabels`` distinct values the slice is upsampled with
            % nearest instead: blocky boundaries, but bounded time. The output keeps
            % the class of ``labSlice``.
            maxSmoothedLabels = 64;
            ty = targetYX(1); tx = targetYX(2);
            vals = unique(labSlice(:));
            if isscalar(vals)
                lab = repmat(vals, ty, tx);   % uniform slice
                return;
            end
            if numel(vals) > maxSmoothedLabels
                lab = imresize(labSlice, [ty tx], 'nearest');
                return;
            end
            bestScore = -inf(ty, tx);
            lab = zeros(ty, tx, 'like', labSlice);
            for vi = 1:numel(vals)
                v  = vals(vi);
                Mv = (labSlice == v);
                % both Mv and ~Mv are non-empty here (>=2 distinct labels), so the
                % distances are finite.
                D  = bwdist(~Mv) - bwdist(Mv);                 % >0 inside region v
                sc = core.MibBigDataLabels.smoothDistField(D, [ty tx]);
                better = sc > bestScore;
                bestScore(better) = sc(better);
                lab(better) = v;
            end
        end

        function r = clampRange(r, n)
            % CLAMPRANGE - clamp a [lo hi] index range to [1, n] and keep it ascending.
            % Guards against invalid zarr bboxes (e.g. when a loaded model's level
            % is smaller than the requested region).
            r = [max(1, min(round(r(1)), n)), max(1, min(round(r(2)), n))];
            if r(2) < r(1); r(2) = r(1); end
        end
    end
end

% ------------------------------------------------------------------------
function reduced = anyPerTile(voxelMask, groupIndex, dim)
% any() over runs of consecutive indices along dimension ``dim``: ``groupIndex``
% gives the (non-decreasing, 1-based) tile of each index, the result has one
% index per tile along ``dim``.
reducedSize = size(voxelMask, 1:3);
reducedSize(dim) = groupIndex(end);
reduced = false(reducedSize);
runStarts = [1, find(diff(groupIndex(:)')) + 1];
runEnds = [runStarts(2:end) - 1, numel(groupIndex)];
source = {':', ':', ':'};
target = {':', ':', ':'};
for run = 1:numel(runStarts)
    source{dim} = runStarts(run):runEnds(run);
    target{dim} = groupIndex(runStarts(run));
    reduced(target{:}) = any(voxelMask(source{:}), dim);
end
end
