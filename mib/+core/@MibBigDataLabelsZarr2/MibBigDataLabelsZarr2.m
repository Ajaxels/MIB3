classdef MibBigDataLabelsZarr2 < core.MibBigDataLabels
% MIBBIGDATALABELSZARR2 - read-only labels overlay for a FOREIGN zarr v2 model store.
%
% Subclass of ``core.MibBigDataLabels`` - read-only sibling used when a
% BigData dataset's model store is a zarr **v2** store MIB did not write. It
% parses v2 metadata directly (``.zattrs``/``.zarray``, pure MATLAB
% ``jsondecode``) rather than through ``io.zarr.Group``, because a foreign
% store declares its own axis order and its own multiscales layout, neither of
% which matches what ``MibBigDataLabels.openStore`` expects. Pixel data is read
% through ``io.zarr.Array``, so the engine follows ``io.zarr.Config`` exactly
% as it does everywhere else.
%
% **This is not the class for a MIB-written v2 store.** MIB can create an
% editable zarr v2 model store (``MibBigDataLabels.createStore`` with
% ``'zarrFormat', 2``); such a store carries the ``mibModelStore`` marker
% attribute and is opened by ``core.MibBigDataLabels`` itself, fully editable.
% ``models.MibModel.loadModel`` picks between the two on that marker.
%
% **Why read-only.** MIB's editable BigData model is a MIB-specific packed
% byte format (bits 1-6 material, bit 7 mask, bit 8 selection) laid out in
% ``[y, x, z]`` with a live disk-backed multi-resolution write-back pyramid. A
% foreign store is none of those things: its values are plain label indices in
% the store's own axis order, and writing MIB's packed bytes back into it would
% corrupt another tool's data. It is instead treated as an already
% fully-materialized single-value-per-voxel label map - its raw values ARE the
% packed byte (mask/selection bits naturally 0, since there is no editing) - so
% ``getData63`` (inherited, unchanged) works correctly as long as label values
% stay within the same ``[0,63]`` ceiling BigData imposes everywhere else.
%
% **What's overridden.** ``getData63`` itself is inherited unchanged - it
% already does everything needed (level picking, orientation mapping,
% display resize, bit-unpacking) purely by calling ``obj.readPackedLevel``/
% ``obj.pickLevel``/``obj.materializeForRead``, all of which dispatch
% polymorphically. Only three things differ from ``MibBigDataLabels``:
%
%   - ``openStore`` - v2 sidecar metadata parsing instead of
%     ``io.zarr.Group.getAttributes``; sets ``matLevel(:) = 1`` so the
%     inherited ``materializeForRead`` is a guaranteed no-op (there is no lazy
%     up-propagation for a read-only, externally-complete source).
%   - ``readPackedLevel`` - permutes from the store's own declared axis order,
%     which the native path never has to do. Reads go through
%     ``io.zarr.ChunkCache`` like the image loaders; MIB never writes this
%     store, and a store replaced on disk gets a new key from
%     ``io.zarr.ChunkCache.storeKey``, so cached chunks never go stale.
%   - ``setData63`` / ``writePackedLevel`` - writes are blocked; the first
%     write attempt per session shows a one-time "read-only" notice (NOT
%     shown on every call, since ``setData63`` fires on every mouse-move
%     during a paint stroke) and the store on disk is never touched.

    properties
        modelArrayMeta = {}
        % {1 x nLevels} io.zarr.Array.info() results, one per level, cached
        % alongside modelArrays{L} (the open array handle) so shape/chunkShape
        % are not re-queried from the engine on every tile read.
        modelLevelPaths = {}
        % {1 x nLevels} full path or URL of each level array, kept from
        % openStore so readPackedLevel can key io.zarr.ChunkCache on it without
        % rebuilding the path on every tile read. Same key the image loaders
        % use, so a store opened both as image and as labels shares its chunks.
        modelAxisOrder = 'yxz'
        % [char] declared C-order of the underlying zarr v2 arrays (e.g.
        % 'zyx'), from the store's own multiscales.axes - unlike a MIB-written
        % store (which always round-trips in [y,x,z], via a transpose codec in
        % v3 or Fortran chunk order in v2), a FOREIGN store is read in whatever
        % order it actually declared, so readPackedLevel must build the bbox /
        % permute the result using this rather than assuming [y,x,z].
        valueRemap = []
        % [256 x 1 uint8] lookup applied to every block read, or ``[]`` for
        % pass-through. A foreign store's values are its own labelling scheme,
        % and MIB's packed byte only has room for 0-63 (bit 7 is the mask, bit 8
        % the selection). A value of 255 - which is what a COSEM inference
        % segmentation writes for "foreground", and what the COSEM ground-truth
        % encoding uses for "not annotated" - would otherwise arrive as material
        % 63 with the mask AND selection bits set. Built by
        % ``resolveValueRemap`` at open time; see there for the rules.
    end

    properties (Transient)
        readOnlyWarningShown (1,1) logical = false
        % Shown once per session on the first blocked write attempt (see
        % setData63) - never re-shown for the rest of the session, since a
        % single paint stroke fires setData63 on every mouse-move.
    end

    methods
        function obj = MibBigDataLabelsZarr2(img, meta)
            % MIBBIGDATALABELSZARR2 - Construct an empty read-only labels container.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = core.MibBigDataLabelsZarr2([], meta)
            %
            % Same construction contract as ``core.MibBigDataLabels`` - pass ``[]``
            % for ``img`` and attach an existing store afterwards via ``openStore``.
            % There is no ``createStore`` counterpart, because a new model store
            % is always MIB's own: ``core.MibBigDataLabels.createStore`` writes it,
            % in v2 or v3, and that editable class then owns it.
            %
            % Input Arguments:
            %   - **img** *(optional)* - [empty] pass ``[]``.
            %   - **meta** *(optional)* - [dictionary] metadata dictionary used by the
            %     parent constructor chain to set dimensions. Default: empty MibImage info.
            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; img = []; end
            obj = obj@core.MibBigDataLabels(img, meta);
        end

        function openStore(obj, storePath)
            % OPENSTORE - attach to an EXISTING zarr v2 labels array/pyramid (read-only).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.openStore(storePath)
            %
            % Overrides ``MibBigDataLabels.openStore``: parses OME-NGFF multiscales
            % metadata from ``.zattrs`` (pure MATLAB JSON, version-agnostic helpers
            % shared with the image reader via ``io.loaders.OmeZarrMetadataUtils``),
            % opens each pyramid level as an ``io.zarr.Array``, and restores
            % material names/colours the same way
            % ``io.loaders.Zarr2VirtualSetupLoader`` resolves them for ``Model``
            % mode (MIB's own ``mibMaterials`` attribute first, else the OME-NGFF
            % ``image-label`` convention).
            %
            % Input Arguments:
            %   - **storePath** - [char|string] path to the zarr v2 labels group
            %     (local folder or HTTP/HTTPS URL).

            storePath = char(storePath);
            isHttp = startsWith(storePath, 'http://') || startsWith(storePath, 'https://');

            % The native engine reads zarr v2 with no external dependency, so
            % only the opt-in python backend has anything to verify up front.
            if io.zarr.Config.isPython()
                try
                    io.zarr.PyBackend.ensureLoaded();
                catch ME
                    error('core:MibBigDataLabelsZarr2:openStore', ...
                        ['Cannot start the Python Zarr backend selected in\n' ...
                         'Preferences -> Input/output -> Zarr library:\n%s\n' ...
                         'Switching that setting to ''native'' (zarrMex) reads zarr v2 without python.'], ...
                        ME.message);
                end

                % Remote stores additionally need the fsspec HTTP packages.
                % Left to throw its own io:zarr:PyBackend:remoteDepsMissing
                % error, which already names the interpreter and the exact
                % install command.
                io.zarr.PyBackend.ensureRemoteSupport(storePath);
            end

            attrs = obj.readZattrsV2(storePath, isHttp);
            ms = io.loaders.OmeZarrMetadataUtils.extractMultiscales(attrs);
            if isempty(ms)
                error('core:MibBigDataLabelsZarr2:openStore', ...
                    'No multiscales metadata found at "%s"', storePath);
            end
            ms = ms(1);

            axisOrder  = io.loaders.OmeZarrMetadataUtils.extractAxisOrder(ms);
            axisLabels = io.loaders.OmeZarrMetadataUtils.axisOrderToLabels(axisOrder);
            yIdx = find(strcmp(axisLabels, 'y'), 1);
            xIdx = find(strcmp(axisLabels, 'x'), 1);
            zIdx = find(strcmp(axisLabels, 'z'), 1);

            nLevels = numel(ms.datasets);
            obj.modelArrays     = cell(1, nLevels);
            obj.modelArrayMeta  = cell(1, nLevels);
            obj.modelLevelPaths = cell(1, nLevels);
            obj.modelLevelNames = cell(1, nLevels);
            levelSizes = zeros(nLevels, 3); % [y x z]
            scaleFac   = zeros(nLevels, 3); % [yScale xScale zScale]

            globalScales = ones(1, numel(axisLabels));
            if isfield(ms, 'coordinateTransformations')
                globalScales = io.loaders.OmeZarrMetadataUtils.extractScaleFromCT(ms.coordinateTransformations, ...
                    numel(axisLabels));
            end
            level0Scales = [];

            for L = 1:nLevels
                ds   = ms.datasets(L);
                name = char(ds.path);
                obj.modelLevelNames{L} = name;

                if isHttp
                    levelPath = [strtrim(storePath), '/', name];
                else
                    levelPath = fullfile(storePath, name);
                end

                levelArray = io.zarr.Array(levelPath);
                meta       = levelArray.info();
                obj.modelArrays{L}     = levelArray;
                obj.modelArrayMeta{L}  = meta;
                obj.modelLevelPaths{L} = levelPath;

                shape = meta.shape;
                nY = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, yIdx, io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, 1, 1));
                nX = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, xIdx, io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, 2, 1));
                nZ = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, zIdx, 1);
                levelSizes(L, :) = [nY, nX, nZ];

                levelScales = globalScales;
                if isfield(ds, 'coordinateTransformations')
                    levelScales = io.loaders.OmeZarrMetadataUtils.extractScaleFromCT(ds.coordinateTransformations, ...
                        numel(axisLabels));
                    levelScales = levelScales .* globalScales;
                end
                if L == 1
                    level0Scales  = levelScales;
                    scaleFac(1,:) = [1, 1, 1];
                else
                    sfY = io.loaders.OmeZarrMetadataUtils.safeRatio(levelScales, yIdx, level0Scales);
                    sfX = io.loaders.OmeZarrMetadataUtils.safeRatio(levelScales, xIdx, level0Scales);
                    sfZ = io.loaders.OmeZarrMetadataUtils.safeRatio(levelScales, zIdx, level0Scales);
                    scaleFac(L, :) = [sfY, sfX, sfZ];
                end
            end

            obj.modelStorePath    = string(storePath);
            obj.modelLevelSizes   = levelSizes;
            obj.modelScaleFactors = scaleFac;
            obj.modelAxisOrder    = axisOrder;

            obj.height    = levelSizes(1, 1);
            obj.width     = levelSizes(1, 2);
            obj.depth     = levelSizes(1, 3);
            obj.colors    = 1;
            obj.time      = 1;
            obj.dim_yxzct = [obj.height, obj.width, obj.depth, 1, 1];
            obj.dataClass = 'uint8';
            obj.maxInt    = 255;
            obj.exists    = true;

            % No local level-map side-file exists for an externally-created
            % store (MIB never wrote one) - treat every level as already fully
            % materialized, same assumption MibBigDataLabels.initLevelMapFallback
            % makes for any "imported" model. This makes the inherited
            % materializeForRead a guaranteed no-op (nothing is ever dirty).
            obj.levelMapPath = '';
            obj.initLevelMapEmpty();
            obj.matLevel(:) = 1;

            % restore material names/colours (mibMaterials attr, else OME-NGFF image-label)
            [names, colors] = obj.readMaterialMetadataV2(storePath, obj.modelLevelNames{1}, isHttp);
            if ~isempty(names);  obj.materialNames  = names(:); end
            if ~isempty(colors); obj.materialColors = colors;   end

            % How this store's values map onto MIB's 0-63 material indices, and
            % - when the answer is "one class" - what to call the one material.
            % Only when the store said nothing about its materials: a store that
            % named them describes its own values and must be left alone.
            if isempty(names)
                singleMaterialName = obj.resolveValueRemap(attrs, storePath);
                if ~isempty(singleMaterialName)
                    obj.materialNames = {singleMaterialName};
                end
            end

            obj.materialsCount = numel(obj.materialNames);
        end

        function singleMaterialName = resolveValueRemap(obj, attrs, storePath)
            % RESOLVEVALUEREMAP - Decide how the store's values become materials.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      singleMaterialName = obj.resolveValueRemap(attrs, storePath)
            %
            % Sets :attr:`valueRemap` and reports whether the store turned out to
            % hold a single class, in which case the caller names the one
            % material after it rather than leaving 63 numbered slots.
            %
            % Three kinds of foreign store, decided in this order:
            %
            %   1. **A declared encoding.** A COSEM ground-truth class group
            %      carries ``cellmap.annotation`` with ``{absent, present,
            %      unknown}``. ``present`` becomes material 1 and everything else
            %      - including ``unknown`` (255), which means "not annotated",
            %      not "background" - becomes 0. One material, named by the
            %      store's own ``class_name``.
            %   2. **An index map.** Values inside 1-63 are already MIB material
            %      indices; they pass through untouched, which is what makes a
            %      merged ``all`` group (ids 3, 4, 5 ... 48) keep its classes.
            %   3. **A binary mask.** An inference segmentation declares nothing
            %      and writes 0 / 255. Any non-zero value becomes material 1,
            %      named after the group's own folder.
            %
            % **The distinction between 2 and 3 needs pixels**, so the COARSEST
            % pyramid level is read whole - the top of a pyramid is a few tens of
            % kilobytes, one request. When it is empty, which a thin sparse
            % structure often is by the time it has been downsampled eight times,
            % the binary reading is assumed: it is the one that cannot corrupt
            % the mask and selection layers, and an index map dense enough to be
            % worth its ids survives downsampling.
            %
            % Input Arguments:
            %   - **attrs** - [struct] the store's ``.zattrs``, already parsed
            %   - **storePath** - [char] used only for the fallback material name
            %
            % Output Arguments:
            %   - **singleMaterialName** - [char] name for the one material, or
            %     ``''`` when the store holds an index map

            obj.valueRemap     = [];
            singleMaterialName = '';

            % ---- 1. the store declares what its values mean -----------------
            annotation = [];
            if isstruct(attrs) && isfield(attrs, 'cellmap') && isstruct(attrs.cellmap) && ...
                    isfield(attrs.cellmap, 'annotation')
                annotation = attrs.cellmap.annotation;
            end
            if isstruct(annotation) && isfield(annotation, 'annotation_type') && ...
                    isstruct(annotation.annotation_type) && ...
                    isfield(annotation.annotation_type, 'encoding') && ...
                    isstruct(annotation.annotation_type.encoding) && ...
                    isfield(annotation.annotation_type.encoding, 'present')
                presentValue   = double(annotation.annotation_type.encoding.present);
                obj.valueRemap = zeros(256, 1, 'uint8');
                if presentValue >= 0 && presentValue <= 255
                    obj.valueRemap(presentValue + 1) = 1;
                end
                singleMaterialName = core.MibBigDataLabelsZarr2.lastPathSegment(storePath);
                if isfield(annotation, 'class_name') && ~isempty(annotation.class_name)
                    singleMaterialName = char(string(annotation.class_name));
                end
                return;
            end

            % ---- 2 vs 3: ask the smallest level there is --------------------
            distinctValues = [];
            try
                coarsest = obj.modelArrays{end}.read();
                distinctValues = double(unique(coarsest(:)));
                distinctValues = distinctValues(distinctValues ~= 0);
            catch
                % Unreadable coarsest level: fall through to the binary reading,
                % which is the safe one - a pass-through here is what puts 255
                % into the mask and selection bits.
            end

            if ~isempty(distinctValues) && all(distinctValues <= 63)
                return;   % an index map in MIB's own range - nothing to do
            end

            obj.valueRemap    = ones(256, 1, 'uint8');
            obj.valueRemap(1) = 0;   % value 0 stays background
            singleMaterialName = core.MibBigDataLabelsZarr2.lastPathSegment(storePath);
        end

        function block = readPackedLevel(obj, levelIdx, Ylim, Xlim, Zlim)
            % READPACKEDLEVEL - read a [ny x nx x nz] block from one level.
            %
            % Overrides ``MibBigDataLabels.readPackedLevel``: the source array's
            % raw values ARE the packed byte (no bit-packing to undo - mask/
            % selection bits are always 0 since there is no editing), so this is
            % a direct read, unlike the write side which stays fully blocked.
            %
            % Unlike a MIB-written store (whose arrays always round-trip in
            % [y,x,z]), a foreign store is read in its OWN declared axis order
            % (``obj.modelAxisOrder``, e.g. ``'zyx'``) - the bbox rows and the
            % result must both be built/permuted against that, not assumed.
            axisOrder = obj.modelAxisOrder;
            nDims     = numel(axisOrder);

            axisRanges.y = Ylim;
            axisRanges.x = Xlim;
            axisRanges.z = Zlim;

            bbox = zeros(nDims, 2);
            for dimIdx = 1:nDims
                ax = axisOrder(dimIdx);
                if isfield(axisRanges, ax)
                    rng = axisRanges.(ax);
                    bbox(dimIdx, :) = [rng(1), rng(2) + 1];
                else
                    bbox(dimIdx, :) = [1, 2]; % singleton for absent axis
                end
            end

            % Serve whole decoded chunks from memory where possible, exactly as
            % the image loaders do. Safe here precisely because this store is
            % read-only (writePackedLevel errors), so a cached chunk can never
            % go stale behind an edit.
            % once per opened level: the cache key carries the store version (see
            % io.zarr.ChunkCache.storeKey) - "read-only" covers MIB's own writes,
            % not a store replaced on disk at the same path
            if ~isfield(obj.modelArrayMeta{levelIdx}, 'cacheKey')
                obj.modelArrayMeta{levelIdx}.cacheKey = io.zarr.ChunkCache.storeKey(obj.modelLevelPaths{levelIdx});
            end
            meta       = obj.modelArrayMeta{levelIdx};
            levelArray = obj.modelArrays{levelIdx};
            raw  = io.zarr.ChunkCache.read(meta.cacheKey, bbox, ...
                meta.chunkShape, meta.shape, ...
                @(alignedBbox) levelArray.read(alignedBbox));
            perm = io.loaders.OmeZarrMetadataUtils.computePermutation(axisOrder); % -> [y,x,z,*,*]
            block = permute(raw, perm);
            block = reshape(block, Ylim(2)-Ylim(1)+1, Xlim(2)-Xlim(1)+1, Zlim(2)-Zlim(1)+1);

            % The store's values -> MIB material indices. AFTER the chunk cache
            % on purpose: the cache holds raw chunks keyed by level path, which
            % is what lets a store opened as an image and as labels share them.
            if ~isempty(obj.valueRemap) && isa(block, 'uint8')
                block = intlut(block, obj.valueRemap);
            end
        end

        function writePackedLevel(~, ~, ~, ~, ~, ~)
            % WRITEPACKEDLEVEL - blocked; should never be reached (setData63 blocks all writes).
            error('core:MibBigDataLabelsZarr2:readOnly', ...
                'MibBigDataLabelsZarr2 is read-only - writePackedLevel must never be called.');
        end

        function result = setData63(obj, dataset, type, orient, materialIndex, options) %#ok<INUSD>
            % SETDATA63 - blocked: zarr v2 BigData models are read-only.
            %
            % Overrides ``MibBigDataLabels.setData63``. Never modifies the store
            % on disk or any in-memory state. Shows a one-time "read-only" notice
            % on the FIRST blocked write attempt of the session only - setData63
            % fires on every mouse-move during a paint stroke, so showing a modal
            % dialog on every call would freeze the UI in a dialog storm.
            result = false;
            if obj.readOnlyWarningShown; return; end
            obj.readOnlyWarningShown = true;
            header = 'Read-only zarr v2 model';
            body = sprintf(['This model was loaded from a zarr v2 store MIB did not create,\n' ...
                'so its values are another tool''s label indices rather than MIB''s packed\n' ...
                'bytes - editing it would corrupt them. The store on disk is not modified.\n\n' ...
                'To segment on this dataset, create a new model instead: MIB writes an\n' ...
                'editable store of its own and leaves this one untouched.']);
            dlgOpt = struct('MsgBoxOnly', true, 'Icon', 'puffin_warning', 'HeaderLines', 1);
            try
                utils.dlgs.inputUniversalDlg([], header, {body}, {body}, header, dlgOpt);
            catch
                % best-effort notice; never let a dialog failure break the read-only guard
            end
        end
    end

    methods (Access = private)
        function attrs = readZattrsV2(~, groupPath, isHttp)
            % READZATTRSV2 - Read a zarr v2 .zattrs sidecar (local or HTTP); '' -> empty struct.
            attrs = struct();
            try
                if isHttp
                    attrs = webread([strtrim(groupPath), '/.zattrs'], weboptions('ContentType', 'json', 'Timeout', 30));
                else
                    zattrsFile = fullfile(groupPath, '.zattrs');
                    if isfile(zattrsFile)
                        attrs = jsondecode(fileread(zattrsFile));
                    end
                end
            catch
                % missing/unreadable .zattrs -> treat as no attributes
            end
        end

        function [names, colors] = readMaterialMetadataV2(obj, rootPath, levelName, isHttp)
            % READMATERIALMETADATAV2 - Resolve material names/colors from store metadata.
            %
            % Fetches the v2 ``.zattrs`` sidecars (root group and, if present,
            % the array level - level-array attributes take precedence on key
            % collisions) and delegates the actual name/color extraction to the
            % version-agnostic ``io.loaders.OmeZarrMetadataUtils.resolveMaterialMetadata``
            % (shared with ``Zarr3VirtualSetupLoader`` and ``Zarr2VirtualSetupLoader``).
            attrs = obj.readZattrsV2(rootPath, isHttp);
            if ~isempty(levelName)
                if isHttp
                    levelRoot = [strtrim(rootPath), '/', levelName];
                else
                    levelRoot = fullfile(rootPath, levelName);
                end
                levelAttrs = obj.readZattrsV2(levelRoot, isHttp);
                fn = fieldnames(levelAttrs);
                for k = 1:numel(fn)
                    attrs.(fn{k}) = levelAttrs.(fn{k});
                end
            end

            [names, colors] = io.loaders.OmeZarrMetadataUtils.resolveMaterialMetadata(attrs);
        end
    end

    methods (Static, Access = private)
        function segment = lastPathSegment(storePath)
            % LASTPATHSEGMENT - Group name from a path or URL, for a material name.
            % Both separators are split on: a URL uses '/' and a local store on
            % Windows arrives with '\'.
            segments = strsplit(regexprep(char(storePath), '[/\\]+$', ''), {'/', '\'});
            segment  = segments{end};
            if isempty(segment); segment = 'labels'; end
        end
    end
end
