classdef MibBigDataLabels < core.MibLabels63
% MIBBIGDATALABELS - disk-backed, packed 63-class segmentation labels for BigData datasets.
%
% Subclass of ``core.MibLabels63``. Keeps the identical bit-packing scheme
% (bits 1–6 = material 0–63, bit 7 = mask, bit 8 = selection) but stores the
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
% ``setData63`` writes the working level then **propagates** the edited region
% to all other levels (nearest-neighbour, preserving packed bytes). Propagation
% is deferred by default: the working level is written synchronously and the
% other levels are flushed on idle by a debounce timer (``flushPropagation``),
% so rapid brush strokes don't pay one write per level per stroke. ``getData63``
% flushes before reading a stale level and ``closeStore`` flushes before
% releasing the store, so on-disk levels are never observably inconsistent.
%
% **Axis order.** Levels are created with ``ZarrArray`` (transpose codec) → they
% round-trip in native MATLAB ``[y, x, z]`` order, no permutation. ``obj.data``
% stays empty; dimensions come from level 0.

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
    end

    properties (Transient)
        % --- deferred cross-level propagation (see setData63 / flushPropagation) ---
        deferPropagation (1,1) logical = true
        % [logical] when true, ``setData63`` writes only the working level
        % synchronously and defers propagation to the other pyramid levels via a
        % debounce timer (coalesced on idle). When false, every level is written
        % synchronously inside ``setData63`` (legacy behaviour).
        propagationDelay (1,1) double = 0.3
        % [double] idle seconds before the deferred propagation flush fires.
        propagationQueue = {}
        % {1 x N} FIFO of pending propagation entries (struct: packed, fullY/X/Z, levelIdx).
        dirtyLevels = false(1, 0)
        % [1 x nLevels logical] true where a level is stale on disk pending propagation.
        propagationTimer = []
        % timer object that flushes the propagation queue when the user pauses.
    end

    methods
        % declared external methods (override MibLabels63)
        dataset = getData63(obj, type, orient, materialIndex, options)
        result  = setData63(obj, dataset, type, orient, materialIndex, options)

        function obj = MibBigDataLabels(img, meta)
            % MIBBIGDATALABELS - construct an (empty) disk-backed label container.
            % The store is created later by createStore(). Pass [] for img.
            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; img = []; end
            obj = obj@core.MibLabels63(img, meta);
            obj.type = 'labels63';
        end

        function createStore(obj, dims, storePath, pyramid)
            % CREATESTORE - allocate a zero-filled packed model pyramid on disk.
            %
            % Input Arguments:
            %   - **dims** — [1x3] ``[height, width, depth]`` (level-0 / fallback size)
            %   - **storePath** — *(optional)* [char] zarr group root; default temp scratch
            %   - **pyramid** — *(optional)* image pyramid struct (``levelImageSizes``,
            %     ``levelScaleFactors``, ``chunkSizes``). When given, the model mirrors it;
            %     otherwise a single full-resolution level is created.
            if nargin < 4; pyramid = []; end
            if nargin < 3 || isempty(storePath); storePath = [tempname '_bigdata_model.zarr3']; end
            storePath = char(storePath);
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

            % --- build the group + one packed uint8 array per level -----------
            grp = io.zarr.Group.create(storePath);   % backend per io.zarr.Config
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
                obj.modelArrays{L} = grp.createArray(name, sz, 'uint8', ...
                    'chunkShape', ch, 'compressors', obj.Compressors, 'fillValue', 0);
                obj.modelLevelNames{L} = name;
            end
            obj.writeMultiscales(grp, scaleFac);

            obj.modelStorePath    = string(storePath);
            obj.modelLevelSizes   = levelSizes;
            obj.modelScaleFactors = scaleFac;
            obj.dirtyLevels       = false(1, nLevels);
            obj.propagationQueue  = {};

            % --- state from level 0 (obj.data stays empty) --------------------
            obj.height    = levelSizes(1, 1);
            obj.width     = levelSizes(1, 2);
            obj.depth     = levelSizes(1, 3);
            obj.colors    = 1;
            obj.time      = 1;
            obj.dim_yxzct = [obj.height, obj.width, obj.depth, 1, 1];
            obj.dataClass = 'uint8';
            obj.maxInt    = 255;
            obj.exists    = true;
        end

        function closeStore(obj)
            % CLOSESTORE - release level handles (data remains on disk).
            % Marks the labels as non-existent so reads/writes become no-ops
            % until a store is (re)opened — avoids crashes on a stale handle.
            % Flushes any deferred cross-level propagation first so every level
            % on disk is consistent before the handles are dropped.
            obj.flushPropagation();
            obj.stopPropagationTimer();
            obj.propagationQueue = {};
            obj.modelArrays = {};
            obj.exists = false;
        end

        function delete(obj)
            % DELETE - destructor: stop the propagation timer so it cannot fire
            % on a deleted object (data on disk is left as-is).
            obj.stopPropagationTimer();
        end

        function openStore(obj, storePath)
            % OPENSTORE - attach to an EXISTING packed model pyramid on disk.
            %
            % Reattaches this labels object to a model store previously written
            % by createStore (or a compatible OME-NGFF multiscales group of
            % packed uint8 levels). Level sizes and scale factors are restored
            % from the stored ``multiscales`` metadata and array shapes; no
            % pixel data is read into memory. Use this to reopen a saved model
            % so segmentation can continue across sessions.
            %
            % Input Arguments:
            %   - **storePath** — [char|string] path to the model zarr group.
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

            obj.modelStorePath    = string(storePath);
            obj.modelLevelSizes   = levelSizes;
            obj.dirtyLevels       = false(1, nL);
            obj.propagationQueue  = {};
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
            obj.dataClass = 'uint8';
            obj.maxInt    = 255;
            obj.exists    = true;

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
                if ~isempty(obj.materialColors)
                    mm.materialColors = obj.materialColors;
                end
                attrs.mibMaterials = mm;
                grp.setAttributes(attrs);
            catch
                % persistence is best-effort; never block segmentation on it
            end
        end

        function levelIdx = pickLevel(obj, options)
            % PICKLEVEL - choose the pyramid level for the given options
            % (explicit options.pyramidLevel, else closest scale to options.magFactor).
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
            obj.modelArrays{levelIdx}.write(uint8(block), bbox);
        end

        function enqueuePropagation(obj, packed, fullY, fullX, fullZ, levelIdx)
            % ENQUEUEPROPAGATION - defer propagating a merged working-level block
            % to the other pyramid levels. Records the block + its full-resolution
            % region, marks every level that does not yet hold this edit as dirty,
            % and (re)arms the debounce timer so the flush fires on idle.
            entry = struct('packed', {uint8(packed)}, ...
                'fullY', {fullY}, 'fullX', {fullX}, 'fullZ', {fullZ}, ...
                'levelIdx', {levelIdx});
            obj.propagationQueue{end+1} = entry;

            % A level is clean only if EVERY queued edit was written to it; the only
            % level guaranteed written per edit is its own working level. So a level
            % is clean now iff all queued edits share that working level.
            nLevels = size(obj.modelLevelSizes, 1);
            workingLevels = cellfun(@(e) e.levelIdx, obj.propagationQueue);
            dirty = true(1, nLevels);
            uniqueWorking = unique(workingLevels);
            if isscalar(uniqueWorking); dirty(uniqueWorking) = false; end
            obj.dirtyLevels = dirty;

            obj.schedulePropagationFlush();
        end

        function flushPropagation(obj)
            % FLUSHPROPAGATION - propagate every queued edit to all other levels now.
            % Safe to call at any time (no-op when the queue is empty or the store
            % is closed). Used by the debounce timer, by getData63 before reading a
            % stale level, and by closeStore before dropping the handles.
            if isempty(obj.propagationQueue)
                obj.dirtyLevels = false(1, size(obj.modelLevelSizes, 1));
                return;
            end
            if ~obj.exists || isempty(obj.modelArrays)
                obj.propagationQueue = {};
                obj.dirtyLevels = false(1, size(obj.modelLevelSizes, 1));
                return;
            end
            queue = obj.propagationQueue;
            obj.propagationQueue = {};   % take ownership before writing
            for k = 1:numel(queue)
                e = queue{k};
                obj.propagateRegion(e.packed, e.fullY, e.fullX, e.fullZ, e.levelIdx);
            end
            obj.dirtyLevels = false(1, size(obj.modelLevelSizes, 1));
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
                case 1  % xz: vertical = X, horizontal = Z, slice = Y
                    if ~isfield(options, 'y') || isempty(options.y); options.y = [1, fullSize(2)]; end
                    if ~isfield(options, 'x') || isempty(options.x); options.x = [1, fullSize(3)]; end
                    if ~isfield(options, 'z') || isempty(options.z); options.z = [1, fullSize(1)]; end
                    physYfull = options.z; physXfull = options.y; physZfull = options.x;
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

        function propagateRegion(obj, packed, fullY, fullX, fullZ, sourceLevelIdx)
            % PROPAGATEREGION - write a merged working-level block into every other
            % pyramid level. Downsampling (source finer than target) uses a
            % nearest-neighbour resize. Up-sampling (source coarser than target,
            % i.e. an edit made zoomed-out pushed into a higher-magnification level)
            % uses a smooth, label-aware resize when io.zarr.Config.smoothing is on,
            % so coarse edits don't look blocky at full resolution.
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
                [A2, B2, C2] = obj.regionForLevel(L2, fullY, fullX, fullZ);
                targetSize = [A2(2)-A2(1)+1, B2(2)-B2(1)+1, C2(2)-C2(1)+1];
                isUpsample = targetSize(1) > srcSize(1) || targetSize(2) > srcSize(2);
                if smoothOn && isUpsample && prod(targetSize) <= smoothBudget
                    block2 = core.MibBigDataLabels.resizeBlockSmooth(packed, targetSize);
                    obj.writePackedLevel(L2, block2, A2, B2, C2);
                else
                    % Tiled, index-based nearest resize written in Y-strips so peak
                    % memory stays ~tileBudget pixels — never materialise a multi-GB
                    % full-resolution array (inlined, no separate method, so this body
                    % hot-reloads onto a live model instance without a MIB restart).
                    pk = uint8(packed);
                    sy = size(pk, 1); sx = size(pk, 2); sz = size(pk, 3);
                    ty = targetSize(1); tx = targetSize(2); tz = targetSize(3);
                    xMap = min(sx, max(1, floor((0:tx-1) * sx / tx) + 1));
                    zMap = min(sz, max(1, floor((0:tz-1) * sz / tz) + 1));
                    yMap = min(sy, max(1, floor((0:ty-1) * sy / ty) + 1));
                    rowsPerStrip = max(1, floor(tileBudget / (max(1, tx) * max(1, tz))));
                    for r0 = 1:rowsPerStrip:ty
                        r1 = min(ty, r0 + rowsPerStrip - 1);
                        sub = pk(yMap(r0:r1), xMap, zMap);   % [(r1-r0+1) x tx x tz]
                        obj.writePackedLevel(L2, sub, [A2(1)+r0-1, A2(1)+r1-1], B2, C2);
                    end
                end
            end
        end

        function schedulePropagationFlush(obj)
            % SCHEDULEPROPAGATIONFLUSH - (re)arm the debounce timer so the queued
            % propagation flushes after propagationDelay seconds of idle. A delay
            % of 0 flushes immediately (synchronous fallback).
            if obj.propagationDelay <= 0; obj.flushPropagation(); return; end
            if isempty(obj.propagationTimer) || ~isvalid(obj.propagationTimer)
                obj.propagationTimer = timer( ...
                    'Name', 'MibBigDataLabelsPropagation', ...
                    'ExecutionMode', 'singleShot', ...
                    'StartDelay', obj.propagationDelay, ...
                    'ObjectVisibility', 'off', ...
                    'TimerFcn', @(~,~) obj.onPropagationTimer());
            end
            stop(obj.propagationTimer);
            start(obj.propagationTimer);
        end

        function onPropagationTimer(obj)
            % ONPROPAGATIONTIMER - timer callback: flush the queue, guarded against
            % the object being torn down between arming and firing.
            if ~isvalid(obj); return; end
            try
                obj.flushPropagation();
            catch
                % never let a deferred flush escape onto the timer thread
            end
        end

        function stopPropagationTimer(obj)
            % STOPPROPAGATIONTIMER - stop and delete the debounce timer if present.
            if ~isempty(obj.propagationTimer) && isvalid(obj.propagationTimer)
                stop(obj.propagationTimer);
                delete(obj.propagationTimer);
            end
            obj.propagationTimer = [];
        end

        function writeMultiscales(obj, grp, scaleFac)
            % WRITEMULTISCALES - minimal OME-NGFF multiscales attribute so the model
            % group reopens as a pyramid (Phase 3 saver enriches voxel size / bbox).
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
            grp.setAttributes(struct('multiscales', {{ms}}));
        end
    end

    methods (Static)
        function out = resizeBlockNearest(block, targetSize)
            % RESIZEBLOCKNEAREST - nearest-neighbour resize of a packed [y x z] uint8
            % block to targetSize=[ty tx tz], preserving exact packed bytes.
            block = uint8(block);
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
            % packed [y x z] uint8 block to targetSize=[ty tx tz].
            %
            % Packed integers cannot be interpolated directly, so the three layers
            % (material bits 1-6, mask bit 7, selection bit 8) are unpacked and
            % each is upsampled with smoothing in YX, then repacked. Smoothing uses a
            % **signed distance transform**: each region's signed distance field
            % (positive inside, negative outside) is a smooth function that is bicubic
            % upsampled and Gaussian-smoothed (sigma = half the up-sampling factor);
            % thresholding the result at 0 reconstructs a smooth boundary at sub-pixel
            % accuracy (a coarse circle becomes a smooth circle, not a faceted one — far
            % better than bilinear-on-binary, which only rounds a one-pixel ramp). The
            % Gaussian erases the working-level stair-steps while the modest sigma keeps
            % thin structures from being eroded.
            %   - materials: per-label signed-distance upsample + arg-max;
            %   - mask / selection: signed-distance upsample of the binary indicator.
            % Z is resized first with nearest (the pyramid keeps Z, so usually a no-op).
            % Falls back to nearest when not actually up-sampling in YX.
            block = uint8(block);
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
            material = bitand(block, 63);
            maskBit  = uint8(bitget(block, 7));
            selBit   = uint8(bitget(block, 8));
            out = zeros(ty, tx, tz, 'uint8');
            for z = 1:tz
                lab = core.MibBigDataLabels.smoothLabelUpsampleYX(material(:, :, z), [ty tx]);
                k   = uint8(core.MibBigDataLabels.signedDistUpsample(maskBit(:, :, z) > 0, [ty tx]));
                s   = uint8(core.MibBigDataLabels.signedDistUpsample(selBit(:, :, z)  > 0, [ty tx]));
                out(:, :, z) = bitor(bitor(lab, k * 64), s * 128);
            end
        end

        function out = resizeLayerSmooth(layer, targetSize, isLabelMap)
            % RESIZELAYERSMOOTH - smooth UP-sample of a raw (unpacked) layer to
            % targetSize=[ty tx tz], used by setData63 to bring a brush stroke captured
            % at display resolution onto a finer working level without blocky steps.
            %   - isLabelMap=true  -> multi-material map (values 0-63): per-label SDF
            %     arg-max (smoothLabelUpsampleYX);
            %   - isLabelMap=false -> binary layer (selection / mask / single-material
            %     indicator): signed-distance upsample.
            % Z is matched first with nearest. Falls back to nearest when not up-sampling
            % in YX (down-sample / equal size).
            layer = uint8(layer);
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
            out = zeros(ty, tx, tz, 'uint8');
            for z = 1:tz
                if isLabelMap
                    out(:, :, z) = core.MibBigDataLabels.smoothLabelUpsampleYX(layer(:, :, z), [ty tx]);
                else
                    out(:, :, z) = uint8(core.MibBigDataLabels.signedDistUpsample(layer(:, :, z) > 0, [ty tx]));
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
            ty = targetYX(1); tx = targetYX(2);
            vals = unique(labSlice(:));
            if isscalar(vals)
                lab = repmat(uint8(vals), ty, tx);   % uniform slice
                return;
            end
            bestScore = -inf(ty, tx);
            lab = zeros(ty, tx, 'uint8');
            for vi = 1:numel(vals)
                v  = vals(vi);
                Mv = (labSlice == v);
                % both Mv and ~Mv are non-empty here (>=2 distinct labels), so the
                % distances are finite.
                D  = bwdist(~Mv) - bwdist(Mv);                 % >0 inside region v
                sc = core.MibBigDataLabels.smoothDistField(D, [ty tx]);
                better = sc > bestScore;
                bestScore(better) = sc(better);
                lab(better) = uint8(v);
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
