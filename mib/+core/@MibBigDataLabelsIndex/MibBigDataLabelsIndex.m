classdef MibBigDataLabelsIndex < core.MibLabels
% MIBBIGDATALABELSINDEX - read-only label overlay served from a pyramid the image does not share.
%
% Subclass of ``core.MibLabels``. Attaches a remote or local OME-Zarr label
% pyramid to an already-open **BigData** image and serves it slice by slice as
% the view is read - nothing is downloaded in bulk and ``obj.data`` stays empty.
%
% **Why a new class rather than a wider ``MibBigDataLabels``.** Everything that
% forces a 63-material ceiling comes from the other branch of the hierarchy::
%
%     MibImage
%     +-- MibLabels63 -- MibBigDataLabels -- MibBigDataLabelsZarr2   (packed byte, 63 max, editable store)
%     +-- MibLabels    -- MibBigDataLabelsIndex                      (separate layers, 65535+, read-only)
%
% ``MibLabels63`` packs six bits of material, bit 7 of mask and bit 8 of
% selection into one byte, so an instance segmentation's object ids cannot
% survive it - 255 arrives as material 63 with the mask and selection bits set.
% This branch has no packing, so ids pass through untouched and the "no suitable
% class" problem dissolves. Subclassing ``MibLabels63`` instead would also fire
% every ``isa(..., 'core.MibLabels63')`` branch in the codebase wrongly, starting
% with ``MibImage.getData:66``.
%
% **The one thing that must not be got wrong.** The label pyramid does **not**
% start at the image's resolution. ``jrc_mus-kidney``'s ``nuc`` has 5 levels from
% 128 nm while the EM it segments has 12 from 8 nm, so ``nuc``'s own level 0 is
% the EM's ``s4``. :attr:`modelScaleFactors` therefore holds each level's scale in
% the **image's** level-0 voxels (``[16 32 64 128 256]`` here), registered by
% ``io.loaders.OmeZarrMetadataUtils.registerLevelScales`` at open time. Numbering
% the levels from the store's own level 0 - which is what
% ``MibBigDataLabelsZarr2.openStore`` does, correctly, for a store that shares the
% image's resolution - would put every label at one-sixteenth of its true size
% with nothing to warn about it.
%
% Serving a fine view from a coarse level is then **not a resize**: the coarse
% block does not begin where the view begins. :meth:`getData` gathers one source
% voxel per screen pixel through
% ``OmeZarrMetadataUtils.screenGridForRange`` / ``levelReadWindow``; see those for
% the arithmetic and why a plain ``imresize`` produces plausible, misplaced labels.
%
% **Read-only, and deliberately so.** A remote label store belongs to another
% tool, its values are that tool's labelling scheme, and MIB has no business
% writing into it. :meth:`setData` and :meth:`setDataFast` are blocked; to segment
% on the dataset, create a new model, which MIB writes to a store of its own.
%
% Read-only is not the same as un-exportable, though. "Save model as..." writes
% **one chosen pyramid level** to any of MIB's model formats, streamed a slice at
% a time by ``io.savers.MibImageSliceProvider`` through ``core.MibLabels.save``, so
% the volume is never gathered in memory. The level has to be chosen because these
% labels have no full-resolution level to default to - that is the whole reason
% this class exists - and writing the one the image is showing would mean
% upsampling the entire volume to a resolution the labels never had.
%
% **Store access follows ``MibBigDataLabelsZarr2``, not ``MibVirtualImage``.**
% Reads go through ``io.zarr.ChunkCache`` keyed on the level path plus the store
% version (``io.zarr.ChunkCache.storeKey``), so a store opened both as an image
% and as labels shares decoded chunks, nothing here writes, and a store replaced
% on disk is never served from the old one's chunks. ``MibVirtualImage.getDataZarr``
% would have been the other candidate, but its defaults assume
% ``levelImageSizes(1,:)`` is the full-resolution extent, which is untrue for an
% offset pyramid.

    properties
        modelStorePath (1,1) string = ""
        % [string] zarr group root path or URL of the label pyramid.
        modelArrays = {}
        % {1 x nLevels} io.zarr.Array handles, one per level, finest first.
        modelArrayMeta = {}
        % {1 x nLevels} io.zarr.Array.info() results, cached beside modelArrays so
        % shape/chunkShape are not re-queried from the engine on every tile read.
        modelLevelPaths = {}
        % {1 x nLevels} full path or URL of each level array - the io.zarr.ChunkCache
        % key, and the same one the image loaders use.
        modelLevelNames = {}
        % {1 x nLevels} relative level paths within the group ('s0', 's1', ...).
        modelLevelSizes = []
        % [nLevels x 3] per-level [y, x, z] voxel counts, as the store holds them.
        modelScaleFactors = []
        % [nLevels x 3] per-level [yScale, xScale, zScale] in the IMAGE's level-0
        % voxels - NOT relative to this store's own level 0. See the class note: this
        % is the whole point of the class and the one field a wrong value in is
        % invisible. Written only by openStore, from registerLevelScales.
        modelAxisOrder = 'zyx'
        % [char] the store's own declared C-order (e.g. 'zyx'), from its
        % multiscales.axes. A foreign store is read in whatever order it declared, so
        % readLevel builds the bbox and permutes the result against this rather than
        % assuming [y,x,z].
        imageScaleFactors = []
        % [nImageLevels x 3] the IMAGE pyramid's own magnification axis, [y x z],
        % level 0 being [1 1 1]. Needed because the overlay has to come back the size
        % the image layer came back - which follows from the level the IMAGE is
        % showing, not the one the labels are read from. getRGBimage composites the
        % two with labeloverlay, where a one-row disagreement is an error.
        renderPerObject (1,1) logical = true
        % [logical] true (default) passes the store's object ids through, so an
        % instance segmentation shows one colour per object; false renders every
        % non-zero value as material 1, reading as a single merged structure.
        % Per-object is the default because it is the information the store actually
        % carries - collapsing it is the lossy view, and compositing costs the same
        % either way (``labeloverlay`` at ``getRGBimage:454`` is O(pixels), not
        % O(materials)). Applied per block read, after the chunk cache, so it can be
        % toggled on a loaded dataset without re-reading anything - the switch is
        % ``Render instances per object`` on the "Show model" context menu.
    end

    properties (Transient)
        readOnlyWarningShown (1,1) logical = false
        % Shown once per session on the first blocked write. Never re-shown: setData
        % fires on every mouse-move during a paint stroke, and a modal dialog per call
        % would freeze the UI in a dialog storm.
    end

    methods
        % declaration of methods in external files
        openStore(obj, storePath, imageReference)   % attach an existing label pyramid, registered against the open image
        dataset = getData(obj, layerType, orient, colChannel, options)  % override of MibImage.getData - the load-bearing read path

        function obj = MibBigDataLabelsIndex(img, meta)
            % MIBBIGDATALABELSINDEX - Construct an empty read-only label container.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = core.MibBigDataLabelsIndex([], meta)
            %
            % Same construction contract as ``core.MibBigDataLabels``: pass ``[]`` for
            % ``img`` and attach a store afterwards with :meth:`openStore`. Until then
            % ``obj.exists`` is false and reads return ``[]``. There is no
            % ``createStore`` counterpart - a store MIB creates is always MIB's own
            % editable packed format, which ``core.MibBigDataLabels`` owns.
            %
            % Input Arguments:
            %   - **img** *(optional)* - [empty] pass ``[]``; pixel data is never held
            %     in memory for this class.
            %   - **meta** *(optional)* - [dictionary] metadata dictionary used by the
            %     parent constructor chain to set dimensions. Default: empty MibImage
            %     info.
            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; img = []; end
            obj = obj@core.MibLabels(img, meta);

            % core.MibImage's constructor maps class -> type with a switch that has no
            % branch for this class, so obj.type would be left empty while getData.m:76
            % and a dozen other places test strcmp(obj.type, 'labels').
            obj.type = 'labels';
        end

        function levelIndex = pickLevel(obj, options)
            % PICKLEVEL - Choose which label level serves a read.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      levelIndex = obj.pickLevel(options)
            %
            % Nearest level on the scale axis, the same rule
            % ``core.MibBigDataLabels.pickLevel`` and ``getDataZarr`` use - but over
            % :attr:`modelScaleFactors`, which is in the image's scale space, so
            % "nearest to magFactor 1" is the finest level the labels HAVE rather than
            % a level that does not exist. That is what makes the missing fine levels
            % fall back to the finest published one, with no special case.
            %
            % Input Arguments:
            %   - **options** - [struct] with optional ``.pyramidLevel`` (explicit
            %     1-based level, wins outright) and ``.magFactor``
            %
            % Output Arguments:
            %   - **levelIndex** - [numeric] 1-based level, clamped to the pyramid
            if isfield(options, 'pyramidLevel') && ~isempty(options.pyramidLevel)
                levelIndex = options.pyramidLevel;
            else
                magFactor = 1;
                if isfield(options, 'magFactor') && ~isempty(options.magFactor)
                    magFactor = options.magFactor;
                end
                [~, levelIndex] = min(abs(obj.modelScaleFactors(:, 1) - magFactor));
            end
            levelIndex = max(1, min(levelIndex, size(obj.modelLevelSizes, 1)));
        end

        function imageScaleYXZ = imageScaleForMagFactor(obj, magFactor)
            % IMAGESCALEFORMAGFACTOR - Which image level the view is being served from.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      imageScaleYXZ = obj.imageScaleForMagFactor(magFactor)
            %
            % Mirrors ``getDataZarr:65-67`` exactly, because the overlay has to be the
            % size the image came back and that size follows from the image's level,
            % not the label's. Kept as its own method so the mirroring is one place
            % that can be compared against the original.
            %
            % Input Arguments:
            %   - **magFactor** - [numeric] current display magnification
            %
            % Output Arguments:
            %   - **imageScaleYXZ** - [1x3 numeric] that level's ``[y x z]`` scale
            %     factors; ``[1 1 1]`` when no image pyramid was registered
            if isempty(obj.imageScaleFactors); imageScaleYXZ = [1 1 1]; return; end
            [~, levelIndex] = min(abs(obj.imageScaleFactors(:, 1) - magFactor));
            imageScaleYXZ = obj.imageScaleFactors(levelIndex, :);
        end

        function block = readLevel(obj, levelIndex, Ylim, Xlim, Zlim, keepObjectIds)
            % READLEVEL - Read a [ny x nx x nz] block of one level, in MIB's axis order.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      block = obj.readLevel(levelIndex, Ylim, Xlim, Zlim)
            %      block = obj.readLevel(levelIndex, Ylim, Xlim, Zlim, keepObjectIds)
            %
            % The store's own values, with no bit-unpacking to undo - a foreign label
            % array holds plain indices. Reads are served through
            % ``io.zarr.ChunkCache`` on whole decoded chunks, exactly as the image
            % loaders do; safe without invalidation precisely because this class never
            % writes.
            %
            % The single-material collapse is applied here, **after** the cache, so the
            % cache keeps holding raw chunks keyed by level path and stays shareable
            % with the same store opened as an image.
            %
            % ``keepObjectIds`` suppresses that collapse. :attr:`renderPerObject` is a
            % **display** choice - "show this instance segmentation as one material" -
            % and a caller naming a single object id is not displaying, it is asking
            % about that object. Collapsing first makes the question unanswerable:
            % every id has already become 1, so id 1 matches the union of every object
            % in the volume and every other id matches nothing. That is one merged
            % surface instead of 2165, and one merged volume out of "Save model as..."
            % with a material index set.
            %
            % Input Arguments:
            %   - **levelIndex** - [numeric] 1-based level
            %   - **Ylim** / **Xlim** / **Zlim** - [1x2 numeric] 1-based inclusive
            %     ranges in that level's own voxels
            %   - **keepObjectIds** *(optional)* - [logical] return the store's own ids
            %     even when :attr:`renderPerObject` is false. Default: ``false``
            %
            % Output Arguments:
            %   - **block** - [ny x nx x nz] of class :attr:`dataClass`
            if nargin < 6; keepObjectIds = false; end
            axisRanges.y = Ylim;
            axisRanges.x = Xlim;
            axisRanges.z = Zlim;
            bbox = io.loaders.OmeZarrMetadataUtils.buildZarrBbox(obj.modelAxisOrder, axisRanges);

            % once per opened level: the cache key carries the store version (see
            % io.zarr.ChunkCache.storeKey); it matches the image loaders' key, so a
            % store opened as image and as labels still shares its chunks
            if ~isfield(obj.modelArrayMeta{levelIndex}, 'cacheKey')
                obj.modelArrayMeta{levelIndex}.cacheKey = io.zarr.ChunkCache.storeKey(obj.modelLevelPaths{levelIndex});
            end
            levelMeta  = obj.modelArrayMeta{levelIndex};
            levelArray = obj.modelArrays{levelIndex};
            raw = io.zarr.ChunkCache.read(levelMeta.cacheKey, bbox, ...
                levelMeta.chunkShape, levelMeta.shape, ...
                @(alignedBbox) levelArray.read(alignedBbox));

            perm  = io.loaders.OmeZarrMetadataUtils.computePermutation(obj.modelAxisOrder);
            block = permute(raw, perm);
            block = reshape(block, Ylim(2)-Ylim(1)+1, Xlim(2)-Xlim(1)+1, Zlim(2)-Zlim(1)+1);

            if ~obj.renderPerObject && ~keepObjectIds
                block = cast(block ~= 0, obj.dataClass);
            elseif ~isa(block, obj.dataClass)
                % A saturating cast, so an id beyond the model type shows as the last
                % colour rather than wrapping onto an unrelated object.
                block = cast(block, obj.dataClass);
            end
        end

        function result = countMaterials(obj)
            % COUNTMATERIALS - Report the object count without reading the volume.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      result = obj.countMaterials()
            %
            % Override of ``core.MibLabels.countMaterials``, which for
            % ``maxMaterials >= 256`` scans every voxel of every time point for the
            % highest index. Here that is a remote volume - ``jrc_mus-liver-6``'s ``er``
            % segmentation is 510 GiB - so the count comes from the single small
            % pyramid level :meth:`openStore` probed instead, and this method only hands
            % it back. The inherited version would in fact return 0 rather than reading
            % anything, since ``obj.data`` is empty, but it would do so by accident; the
            % number it should report is the one already in hand.
            %
            % Output Arguments:
            %   - **result** - [numeric] :attr:`materialsCount`, a lower bound on the
            %     object count when the store is an index map (see openStore), and 1
            %     when the values are being collapsed to a single material

            % Reported, not stored. The collapse is a display setting that can be
            % toggled back, while materialsCount is the store's own object count
            % measured once at open time - writing 1 into it would destroy that
            % number for good, and the next per-object action would have nothing
            % to go back to.
            result = obj.materialsCount;
            if ~obj.renderPerObject && obj.exists; result = 1; end
        end

        function result = setData(obj, dataset, layerType, orient, colChannel, options) %#ok<INUSD>
            % SETDATA - Blocked: an imported label pyramid is read-only.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      result = obj.setData(dataset, layerType, orient, colChannel, options)
            %
            % Override of ``core.MibImage.setData``. Never touches the store or any
            % in-memory state, and returns ``false`` so a caller that checks gets an
            % honest answer. The notice is shown once per session, on the first blocked
            % attempt only: a single paint stroke fires ``setData`` on every mouse-move.
            %
            % Output Arguments:
            %   - **result** - [logical] always false
            result = false;
            obj.showReadOnlyNotice();
        end

        function setDataFast(obj, dataset, z, colChannel, t) %#ok<INUSD>
            % SETDATAFAST - Blocked: the in-place write path has no target here.
            %
            % Override of ``core.MibImage.setDataFast``. ``MibDataset``'s fast paths
            % gate on ``datasetType == 'Standard'`` and so never reach a BigData
            % buffer, but the inherited version writes straight into ``obj.data`` -
            % which is empty here, so a stray call would silently **grow** a
            % full-resolution array in memory rather than fail. Blocked for that
            % reason rather than for symmetry.
            obj.showReadOnlyNotice();
        end

    end

    methods (Static)
        function reference = imageReference(image)
            % IMAGEREFERENCE - Describe an open image in the absolute terms openStore needs.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      reference = core.MibBigDataLabelsIndex.imageReference(dataset.image)
            %
            % Shared by the two places that have to answer "can this label pyramid be
            % placed on the open image": ``MibModel.loadModel``, which then attaches
            % it, and ``controllers.SelectFromUrl.resolveLabelRoute``, which only
            % needs to know before Open is pressed. Keeping one implementation is what
            % stops the panel promising a route the loader then refuses.
            %
            % **The level voxel sizes come from ``pyramid.levelScaleFactors``**, not
            % from ``pyramid.levelVoxelSizes``, deliberately: ``levelScaleFactors`` is
            % the table ``getDataZarr`` itself picks levels with, so registering
            % against it guarantees the overlay's idea of the image's magnification
            % axis is the one the image actually uses. Anisotropic voxels cancel in
            % the division, so it holds for them too.
            %
            % Input Arguments:
            %   - **image** - [core.MibImage] the dataset's image layer; needs a
            %     ``pyramid`` with ``levelScaleFactors`` and a ``boundingBox``
            %
            % Output Arguments:
            %   - **reference** - [struct] with ``.ok`` / ``.reason``, plus the three
            %     fields :meth:`openStore` reads: ``.shapeYXZ``, ``.voxelSizesXYZ``
            %     (micrometres) and ``.outerBoxUm`` (edge-based, micrometres)

            reference = struct('ok', false, 'reason', '', 'shapeYXZ', [0 0 0], ...
                'voxelSizesXYZ', [], 'outerBoxUm', []);

            pyramid = image.pyramid;
            if isempty(pyramid) || ~isfield(pyramid, 'levelScaleFactors') || ...
                    isempty(pyramid.levelScaleFactors)
                reference.reason = ['The open image has no pyramid, so there is no scale ' ...
                    'space to place these labels in.'];
                return;
            end
            if isempty(image.boundingBox) || numel(image.boundingBox) ~= 6
                reference.reason = ['The open image has no bounding box, so the two volumes ' ...
                    'cannot be compared.'];
                return;
            end

            % A Virtual/BigData image does not always populate pixSize - the
            % full-res voxel size lives in the pyramid instead, and
            % MibDataset.saveImage:163-169 reconstructs it the same way. The unit
            % is then unknown and assumed to be micrometres; a wrong guess scales
            % the voxel size and the bounding box by the SAME factor, so the level
            % scales stay right and only the extent check against the label store
            % moves - which refuses cleanly rather than misplacing anything.
            storeUnits = 'um';
            if isstruct(image.pixSize) && ~isempty(image.pixSize)
                voxelSizeXYZ = [image.pixSize.x, image.pixSize.y, image.pixSize.z];
                if isfield(image.pixSize, 'units') && ~isempty(image.pixSize.units)
                    storeUnits = image.pixSize.units;
                end
            elseif isfield(pyramid, 'levelVoxelSizes') && ~isempty(pyramid.levelVoxelSizes)
                voxel0 = pyramid.levelVoxelSizes(1, :);   % [y x z]
                voxelSizeXYZ = voxel0([2 1 3]);
            else
                reference.reason = ['The open image declares no voxel size, so these labels ' ...
                    'cannot be scaled against it.'];
                return;
            end

            toMicrometres = io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor(storeUnits);
            voxelSizeUmXYZ = voxelSizeXYZ * toMicrometres;

            reference.shapeYXZ = [image.height, image.width, image.depth];
            % levelScaleFactors is [y x z]; the reference table is [x y z].
            reference.voxelSizesXYZ = pyramid.levelScaleFactors(:, [2 1 3]) .* voxelSizeUmXYZ;
            reference.outerBoxUm = io.loaders.OmeZarrMetadataUtils.outerBoundingBox( ...
                reshape(double(image.boundingBox), 1, 6) * toMicrometres, voxelSizeUmXYZ);
            reference.ok = true;
        end
    end

    methods (Access = private)
        function showReadOnlyNotice(obj)
            % SHOWREADONLYNOTICE - One-time modal notice on the first blocked write.
            if obj.readOnlyWarningShown; return; end
            obj.readOnlyWarningShown = true;
            header = 'Read-only label overlay';
            body = sprintf(['These labels are served from a store MIB did not create, at a\n' ...
                'resolution the image pyramid does not hold, so they are displayed\n' ...
                'rather than loaded - there is nothing here to edit and the store on\n' ...
                'disk is not modified.\n\n' ...
                'To segment on this dataset, create a new model: MIB writes an editable\n' ...
                'store of its own and leaves this one untouched. To edit THESE labels,\n' ...
                'reopen them with Dataset mode = Standard, which reads the matching\n' ...
                'region into memory as an ordinary model.']);
            dlgOpt = struct('MsgBoxOnly', true, 'Icon', 'puffin_warning', 'HeaderLines', 1);
            try
                utils.dlgs.inputUniversalDlg([], header, {body}, {body}, header, dlgOpt);
            catch
                % best-effort notice; a dialog failure must never break the read-only guard
            end
        end
    end
end
