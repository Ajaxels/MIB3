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
% ``setData63`` writes the edited region only at the working level and all
% COARSER levels (cheap downsample, preserving packed bytes), and records the
% working level in the per-tile level map (``matLevel``). Finer levels are left
% dirty and reconstructed on demand: ``getData63`` recomputes a finer tile from
% its ``matLevel`` source (no coarse-echo halo), writes it into the level
% (materialize) and caches it. ``saveLevelMap``/``loadLevelMap`` persist the map
% in a side-file; ``materializeAll`` (Save) finalizes every level. See
% development/bigdata/bigdata_logic.md.
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
        % --- multi-resolution "level map" (see setData63 / getData63 / materializeAll) ---
        matLevel = []
        % [uint8 [coarseY x coarseX x coarseZ]] per coarsest-grid tile, the FINEST
        % pyramid level index holding materialized data (0 = empty). Finer = smaller
        % index; level 1 = full resolution; level N = coarsest. An edit writes the
        % working level + coarser and sets matLevel = working level; finer levels are
        % implicitly dirty and recomputed on read (getData63) or at Save (materializeAll).
        levelMapPath = ''
        % [char] side-file path ('<storePath>.levelmap') persisting matLevel.
        selectionBBoxFull = []
        % [1x6 double] full-resolution bounding box [y0 y1 x0 x1 z0 z1] of where the
        % SELECTION layer currently has data, or [] when there is no selection. Grown
        % by setData63 on every selection write (exact written bits → reliable even for
        % a 1-pixel stroke), reset/shrunk when the selection is cleared or consumed.
        % Lets selection→material/mask moves (a/s/r) and clear (c) read/write only the
        % selection's footprint instead of the whole gigapixel slice. Transient: not
        % persisted; recomputed lazily as edits happen this session.
    end

    methods
        % declared external methods (override MibLabels63)
        dataset = getData63(obj, type, orient, materialIndex, options)
        result  = setData63(obj, dataset, type, orient, materialIndex, options)

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
            %   - **img** *(optional)* — [empty] pass ``[]``; pixel data is never stored
            %     in memory for BigData labels.
            %   - **meta** *(optional)* — [dictionary] metadata dictionary used by the
            %     parent ``core.MibLabels63`` constructor to set dimensions.  Default:
            %     empty ``MibImage`` info.
            %
            % **Example** — create a fresh labels object and attach a pyramid store:
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

        function createStore(obj, dims, storePath, pyramid)
            % CREATESTORE - Allocate a zero-filled packed label pyramid on disk.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.createStore(dims)
            %      obj.createStore(dims, storePath)
            %      obj.createStore(dims, storePath, pyramid)
            %
            % Creates a new zarr3 group at ``storePath`` with one ``uint8`` array per
            % pyramid level (bits 1–6 = material 0–63, bit 7 = mask, bit 8 = selection).
            % The level count, sizes, scale factors, and chunk shapes are copied from
            % ``pyramid`` so the model mirrors the image pyramid exactly.  An empty level
            % map (``matLevel``) is initialised and persisted as a side-file.
            %
            % Input Arguments:
            %   - **dims** — [1x3 numeric] ``[height, width, depth]`` in pixels; used as the
            %     fallback level-0 size when ``pyramid`` is empty.
            %   - **storePath** *(optional)* — [char|string] zarr group root directory.
            %     Default: a temporary path (``[tempname '_bigdata_model.zarr3']``).
            %   - **pyramid** *(optional)* — [struct] image pyramid struct with fields:
            %
            %     - ``.levelImageSizes`` — [nLevels x 3] ``[height, width, depth]`` per level
            %     - ``.levelScaleFactors`` — [nLevels x 3] ``[yScale, xScale, zScale]``
            %     - ``.chunkSizes`` — {1 x nLevels} per-level chunk vectors in axis order
            %     - ``.axisOrder`` — [char] axis order string (default ``'tczyx'``)
            %
            %   When ``pyramid`` is empty, a single full-resolution level is created.
            %
            % **Example** — create a 3-level model matching a loaded BigData image:
            %
            %   .. code-block:: matlab
            %
            %      img = mib.mibModel.I{1};   % core.MibDataset handle
            %      lb  = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            %      storePath = fullfile(fileparts(img.image.Virtual.filenames{1}), ...
            %                           'Labels.zarr3');
            %      lb.createStore([img.image.height, img.image.width, img.image.depth], ...
            %                     storePath, img.image.pyramid);
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

            % fresh store → empty level map + side-file path
            obj.levelMapPath = core.MibBigDataLabels.levelMapPathFor(storePath);
            obj.initLevelMapEmpty();
        end

        function closeStore(obj)
            % CLOSESTORE - release level handles (data remains on disk).
            % Marks the labels as non-existent so reads/writes become no-ops
            % until a store is (re)opened. Persists the level map first so a
            % reopened model knows which finer levels are still virtual.
            obj.saveLevelMap();
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
            %   - **options** — [struct] with fields:
            %
            %     - ``.pyramidLevel`` *(optional)* — [numeric] explicit level (1 = finest).
            %     - ``.magFactor``    *(optional)* — [numeric] current display magnification
            %       factor (``dataset.magFactor``).  Default: ``1`` (full resolution).
            %
            % Output Arguments:
            %   - **levelIdx** — [numeric scalar] 1-based pyramid level index (1 = finest /
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
            obj.modelArrays{levelIdx}.write(uint8(block), bbox);
        end

        function initLevelMapEmpty(obj)
            % INITLEVELMAPEMPTY - allocate an empty level map over the coarsest grid.
            cs = obj.modelLevelSizes(end, :);            % coarsest [y x z]
            obj.matLevel = zeros([cs(1), cs(2), max(1, cs(3))], 'uint8');
        end

        function [ty, tx, tz] = tilesForFullRegion(obj, fullY, fullX, fullZ)
            % TILESFORFULLREGION - full-res region -> inclusive coarsest-grid tile ranges.
            sfN = obj.modelScaleFactors(end, :);         % coarsest [yScale xScale zScale]
            cs  = obj.modelLevelSizes(end, :);
            ty = [max(1, ceil(fullY(1)/sfN(1))), min(cs(1),          ceil(fullY(2)/sfN(1)))];
            tx = [max(1, ceil(fullX(1)/sfN(2))), min(cs(2),          ceil(fullX(2)/sfN(2)))];
            tz = [max(1, ceil(fullZ(1)/sfN(3))), min(max(1, cs(3)),  ceil(fullZ(2)/sfN(3)))];
        end

        function markTiles(obj, fullY, fullX, fullZ, levelIdx)
            % MARKTILES - set matLevel = levelIdx for every coarsest tile covering the
            % full-res region (latest-edit-wins: invalidates any finer materialization).
            if isempty(obj.matLevel); obj.initLevelMapEmpty(); end
            [ty, tx, tz] = obj.tilesForFullRegion(fullY, fullX, fullZ);
            obj.matLevel(ty(1):ty(2), tx(1):tx(2), tz(1):tz(2)) = uint8(levelIdx);
        end

        function updateSelectionBBoxFromWrite(obj, fullBlock, Yl, Xl, Zl, levelIdx)
            % UPDATESELECTIONBBOXFROMWRITE - keep selectionBBoxFull in sync after a
            % setData63 write that may have changed selection bits (type
            % 'selection'/'everything').
            %
            % fullBlock : the WHOLE processed working block (the nearest-merged result
            %             over the incoming region [Yl Xl Zl]); its selection bit (bit 8)
            %             is authoritative for the resulting selection over that region.
            % Yl/Xl/Zl  : working-level absolute index ranges of fullBlock.
            % levelIdx  : working level fullBlock lives at.
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
            selOn = bitand(fullBlock, 128) > 0;
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
            % level-L index window [Yl Xl Zl] for every non-empty tile. Tiles whose
            % matLevel is FINER-than-materialized for L (matLevel > L) are recomputed by
            % upsampling from their matLevel source, written to L, and marked matLevel=L.
            % Bounded to this window. Clean tiles (matLevel <= L) are left untouched.
            %
            % Upsampling uses label-aware signed-distance smoothing (resizeBlockSmooth)
            % when the smoothing preference is on, so coarse-level block patterns do not
            % appear when zooming into a region drawn at a coarser zoom. Falls back to
            % nearest-neighbour when smoothing is off or when the target is not finer
            % (resizeBlockSmooth already handles this internally).
            if isempty(obj.matLevel); return; end
            smoothOn = io.zarr.Config.smoothing();
            sf = obj.modelScaleFactors(L, :);
            fullY = [(Yl(1)-1)*sf(1)+1, min(Yl(2)*sf(1), obj.height)];
            fullX = [(Xl(1)-1)*sf(2)+1, min(Xl(2)*sf(2), obj.width)];
            fullZ = [(Zl(1)-1)*sf(3)+1, min(Zl(2)*sf(3), obj.depth)];
            [ty, tx, tz] = obj.tilesForFullRegion(fullY, fullX, fullZ);
            win = obj.matLevel(ty(1):ty(2), tx(1):tx(2), tz(1):tz(2));
            srcLevels = unique(double(win(:)));
            srcLevels = srcLevels(srcLevels > L);        % only finer-than-materialized tiles are dirty
            sfN = obj.modelScaleFactors(end, :);         % tile size in full-res px = coarsest scale
            for A = reshape(srcLevels, 1, [])
                [iy, ix, iz] = ind2sub(size(win), find(win == A));
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
                    block = core.MibBigDataLabels.resizeBlockSmooth(src, tgtSize);
                else
                    block = core.MibBigDataLabels.resizeBlockNearest(src, tgtSize);
                end
                obj.writePackedLevel(L, block, lY, lX, lZ);
                obj.matLevel(tY(1):tY(2), tX(1):tX(2), tZ(1):tZ(2)) = ...
                    min(obj.matLevel(tY(1):tY(2), tX(1):tX(2), tZ(1):tZ(2)), uint8(L));
            end
        end

        function materializeAll(obj, pwbFcn)
            % MATERIALIZEALL - materialize every non-empty tile down to level 1 (Save).
            % Walks the coarsest grid one tile-row per step (bounded), recomputing each
            % finer level for that row; sets matLevel = 1 for materialized tiles.
            if nargin < 2; pwbFcn = []; end
            if isempty(obj.matLevel); return; end
            nT = size(obj.matLevel, 1);
            for r = 1:nT
                rowLevels = obj.matLevel(r, :, :);
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
            if isempty(obj.levelMapPath) || isempty(obj.matLevel); return; end
            S = struct('matLevel', obj.matLevel, 'mapVersion', 1, ...
                'coarsestSize', obj.modelLevelSizes(end, :));
            save(obj.levelMapPath, '-struct', 'S', '-v7', '-mat');
        end

        function tf = loadLevelMap(obj)
            % LOADLEVELMAP - restore matLevel from the side-file; false if missing/mismatched.
            % '-mat' forces MAT parsing since the file has no '.mat' extension.
            tf = false;
            if isempty(obj.levelMapPath) || ~isfile(obj.levelMapPath); return; end
            S = load(obj.levelMapPath, '-mat');
            if isfield(S, 'matLevel') && isequal(size(S.matLevel, 1:2), obj.modelLevelSizes(end, 1:2))
                obj.matLevel = uint8(S.matLevel); tf = true;
            end
        end

        function initLevelMapFallback(obj)
            % INITLEVELMAPFALLBACK - no side-file: assume the on-disk pyramid is already
            % PRECISE at every level (matLevel = 1, i.e. fully materialized).
            %
            % This is the correct assumption for an imported / externally-created model
            % (all levels were properly downsampled when written) and for any model MIB
            % saved fully — MIB always persists the sidecar on closeStore, so a MISSING
            % sidecar means "not a deferred interactive session", i.e. nothing virtual.
            %
            % It must NOT assume coarsest-only: doing so would make the first zoom-in
            % past the coarsest level trigger materializeForRead, which upsamples the
            % coarsest data and OVERWRITES the precise finer levels — silently degrading
            % an imported model. With matLevel = 1, reads go straight to the requested
            % level; later edits degrade only the touched tiles (markTiles), which are
            % then recomputed lazily on read or rewritten on Save.
            obj.initLevelMapEmpty();
            obj.matLevel(:) = 1;
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

        function propagateRegion(obj, packed, fullY, fullX, fullZ, sourceLevelIdx, direction)
            % PROPAGATEREGION - write a merged working-level block into other pyramid
            % levels. Downsampling (source finer than target) uses a nearest-neighbour
            % resize. Up-sampling (source coarser than target, i.e. an edit made
            % zoomed-out pushed into a higher-magnification level) uses a smooth,
            % label-aware resize when io.zarr.Config.smoothing is on.
            %
            % ``direction`` (optional) selects which levels to write — finer levels are
            % numerically SMALLER indices (level 1 = full resolution):
            %   - ``'all'``     — every other level (default)
            %   - ``'coarser'`` — only levels coarser than the source (index > source);
            %                     a cheap downsample, done eagerly per edit
            %   - ``'finer'``   — only levels finer than the source (index < source);
            %                     the expensive upsample toward full res, deferred/lazy
            if nargin < 7 || isempty(direction); direction = 'all'; end
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
        function p = levelMapPathFor(storePath)
            % LEVELMAPPATHFOR - side-file path for the level map of a model store.
            % Replaces the store's extension (e.g. '.zarr3') with '.levelmap' so the
            % sidecar sits next to the store as '<name>.levelmap' (a MAT-format file
            % saved/loaded with the '-mat' key; NOT '<name>.zarr3.levelmap.mat').
            storePath = char(storePath);
            [folder, name] = fileparts(storePath);
            p = fullfile(folder, [name '.levelmap']);
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
