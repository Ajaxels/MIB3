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
% to all other levels (nearest-neighbour, preserving packed bytes).
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
                if ~isempty(chunkCell) && numel(chunkCell) >= L && ~isempty(chunkCell{L})
                    c = chunkCell{L};                 % image chunk in [t c z y x]
                    ch = [c(4), c(5), c(3)];          % -> [y x z]
                else
                    ch = [256 256 16];
                end
                ch = max(min(ch, sz), [1 1 1]);
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
        end

        function closeStore(obj)
            % CLOSESTORE - release level handles (data remains on disk).
            % Marks the labels as non-existent so reads/writes become no-ops
            % until a store is (re)opened — avoids crashes on a stale handle.
            obj.modelArrays = {};
            obj.exists = false;
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

            % restore material names/colours if previously saved (see writeMaterialMetadata)
            if isfield(attrs, 'mibMaterials')
                mm = attrs.mibMaterials;
                if isfield(mm, 'materialNames') && ~isempty(mm.materialNames)
                    names = mm.materialNames;
                    if ischar(names); names = {names}; end
                    if iscell(names); obj.materialNames = names(:); end
                end
                if isfield(mm, 'materialColors') && ~isempty(mm.materialColors) && isnumeric(mm.materialColors)
                    obj.materialColors = mm.materialColors;
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
    end

    methods (Access = private)
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

        function r = clampRange(r, n)
            % CLAMPRANGE - clamp a [lo hi] index range to [1, n] and keep it ascending.
            % Guards against invalid zarr bboxes (e.g. when a loaded model's level
            % is smaller than the requested region).
            r = [max(1, min(round(r(1)), n)), max(1, min(round(r(2)), n))];
            if r(2) < r(1); r(2) = r(1); end
        end
    end
end
