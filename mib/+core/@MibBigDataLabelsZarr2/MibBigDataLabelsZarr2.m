classdef MibBigDataLabelsZarr2 < core.MibBigDataLabels
% MIBBIGDATALABELSZARR2 - read-only, python-backed labels overlay for an EXISTING zarr v2 model store.
%
% Subclass of ``core.MibBigDataLabels`` - read-only sibling used when a
% BigData dataset's model store is zarr **v2** rather than v3. Zarr v2 has no
% native (zarrMex) engine, so ``io.zarr.Group``/``io.zarr.Array`` (which
% ``MibBigDataLabels`` uses for metadata AND - depending on
% ``io.zarr.Config`` - bulk I/O) cannot open a v2 store at all: their
% metadata path is hard-wired to native zarrMex. This class instead parses
% v2 metadata directly (``.zattrs``/``.zarray``, pure MATLAB ``jsondecode``)
% and reads pixel data through ``io.zarr.PyBackend`` (python ``zarr.open`` +
% raw ``pyrun`` byte transfers), exactly like ``io.loaders.Zarr2VirtualLoader``
% does for images.
%
% **Why read-only.** MIB's editable BigData model is a MIB-specific packed
% byte format (bits 1-6 material, bit 7 mask, bit 8 selection) with a live
% disk-backed multi-resolution write-back pyramid - building a python-backed
% equivalent write path for zarr v2 is a substantially larger project and out
% of scope (see the zarr2 reader plan). An EXISTING zarr v2 labels array
% (e.g. produced by another tool) is instead treated as a plain, already
% fully-materialized single-value-per-voxel label map: its raw values ARE the
% packed byte (mask/selection bits naturally 0, since there is no editing),
% so ``getData63`` (inherited, unchanged) works correctly as long as label
% values stay within the same ``[0,63]`` ceiling BigData imposes everywhere
% else.
%
% **What's overridden.** ``getData63`` itself is inherited unchanged - it
% already does everything needed (level picking, orientation mapping,
% display resize, bit-unpacking) purely by calling ``obj.readPackedLevel``/
% ``obj.pickLevel``/``obj.materializeForRead``, all of which dispatch
% polymorphically. Only three things differ from ``MibBigDataLabels``:
%
%   - ``openStore`` - v2 metadata parsing + python array handles instead of
%     ``io.zarr.Group``/``io.zarr.Array``; sets ``matLevel(:) = 1`` so the
%     inherited ``materializeForRead`` is a guaranteed no-op (there is no lazy
%     up-propagation for a read-only, externally-complete source).
%   - ``readPackedLevel`` - reads via ``io.zarr.PyBackend.readArray`` instead
%     of ``io.zarr.Array.read``, through ``io.zarr.ChunkCache`` like the image
%     loaders. The cache needs no invalidation here because the store is
%     read-only.
%   - ``setData63`` / ``writePackedLevel`` - writes are blocked; the first
%     write attempt per session shows a one-time "read-only" notice (NOT
%     shown on every call, since ``setData63`` fires on every mouse-move
%     during a paint stroke) and the store on disk is never touched.

    properties
        modelArrayMeta = {}
        % {1 x nLevels} io.zarr.PyBackend.arrayMeta() results, one per level,
        % cached alongside modelArrays{L} (the open python array handle) to
        % avoid re-querying shape/dtype from python on every tile read.
        modelLevelPaths = {}
        % {1 x nLevels} full path or URL of each level array, kept from
        % openStore so readPackedLevel can key io.zarr.ChunkCache on it without
        % rebuilding the path on every tile read. Same key the image loaders
        % use, so a store opened both as image and as labels shares its chunks.
        modelAxisOrder = 'yxz'
        % [char] declared C-order of the underlying zarr v2 arrays (e.g.
        % 'zyx'), from the store's own multiscales.axes - unlike the native
        % zarrMex path (which always round-trips in [y,x,z] via a transpose
        % codec applied at write time), a python-opened array here is read in
        % whatever order the EXTERNAL store actually declared, so
        % readPackedLevel must build the bbox / permute the result using this
        % rather than assuming [y,x,z].
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
            % There is no ``createStore`` counterpart: a new (empty) model on a
            % zarr v2 BigData dataset is not supported.
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
            % opens each pyramid level as a python zarr array
            % (``io.zarr.PyBackend.openArray``), and restores material
            % names/colours the same way ``io.loaders.Zarr2VirtualSetupLoader``
            % resolves them for ``Model`` mode (MIB's own ``mibMaterials``
            % attribute first, else the OME-NGFF ``image-label`` convention).
            %
            % Input Arguments:
            %   - **storePath** - [char|string] path to the zarr v2 labels group
            %     (local folder or HTTP/HTTPS URL).

            storePath = char(storePath);
            isHttp = startsWith(storePath, 'http://') || startsWith(storePath, 'https://');

            try
                io.zarr.PyBackend.ensureLoaded();
            catch ME
                error('core:MibBigDataLabelsZarr2:openStore', ...
                    ['Cannot start the Python Zarr backend needed to read zarr v2 model stores:\n%s\n' ...
                     'Check preferences.ExternalDirs.PythonInstallationPath / Preferences -> Input/output -> Zarr library.'], ...
                    ME.message);
            end

            % Remote label stores additionally need the fsspec HTTP packages.
            % Left to throw its own io:zarr:PyBackend:remoteDepsMissing error,
            % which already names the interpreter and the exact install command.
            io.zarr.PyBackend.ensureRemoteSupport(storePath);

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

                pyArr = io.zarr.PyBackend.openArray(levelPath, 'r');
                meta  = io.zarr.PyBackend.arrayMeta(pyArr);
                obj.modelArrays{L}     = pyArr;
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
            obj.materialsCount = numel(obj.materialNames);
        end

        function block = readPackedLevel(obj, levelIdx, Ylim, Xlim, Zlim)
            % READPACKEDLEVEL - read a [ny x nx x nz] block from one level (python-backed).
            %
            % Overrides ``MibBigDataLabels.readPackedLevel``: the source array's
            % raw values ARE the packed byte (no bit-packing to undo - mask/
            % selection bits are always 0 since there is no editing), so this is
            % a direct read, unlike the write side which stays fully blocked.
            %
            % Unlike the native path (whose zarrMex-written arrays always
            % round-trip in [y,x,z] via a transpose codec), a python-opened
            % array here is read in the store's OWN declared axis order
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
            meta = obj.modelArrayMeta{levelIdx};
            raw  = io.zarr.ChunkCache.read(obj.modelLevelPaths{levelIdx}, bbox, ...
                meta.chunkShape, meta.shape, ...
                @(alignedBbox) io.zarr.PyBackend.readArray(obj.modelArrays{levelIdx}, alignedBbox, meta));
            perm = io.loaders.OmeZarrMetadataUtils.computePermutation(axisOrder); % -> [y,x,z,*,*]
            block = permute(raw, perm);
            block = reshape(block, Ylim(2)-Ylim(1)+1, Xlim(2)-Xlim(1)+1, Zlim(2)-Zlim(1)+1);
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
            body = sprintf(['This model was loaded from an existing zarr v2 store.\n' ...
                'Segmentation editing is not supported for zarr v2 BigData models\n' ...
                '(no python-backed editable pyramid) - the store on disk is not modified.']);
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
end
