classdef ZarrBlockedAdapter < images.blocked.Adapter
% ZARRBLOCKEDADAPTER - a MATLAB ``blockedImage`` adapter backed by an OME-Zarr v3 store.
%
% This class lets MATLAB's ``blockedImage`` framework read and write a
% chunked, multi-resolution OME-Zarr v3 dataset through MIB3's native zarr
% engine (``ZarrArray`` / ``ZarrGroup`` / the ``zarrMex`` MEX library in
% ``mib/external/zarr-matlab``). It is the "hybrid" piece of the BigData
% design: ``blockedImage`` provides the tiling / ``apply`` / ``gather`` /
% memory-management / parallel-write machinery, while zarr remains the
% on-disk format.
%
% **What a blockedImage adapter is.**
%   ``blockedImage`` never touches files itself — it delegates every read and
%   write to an ``images.blocked.Adapter`` subclass. To create a custom
%   backing store you implement three required methods (``openToRead``,
%   ``getInfo``, ``getIOBlock``) and, for writable stores, ``openToWrite`` and
%   ``setIOBlock``. ``blockedImage`` then calls them as needed; user code only
%   ever sees the high-level ``blockedImage`` API (``gather``, ``getRegion``,
%   ``getBlock``, ``setBlock``, ``apply``, ``write``).
%
% **Lifecycle.**
%   *Read:* ``blockedImage(src, Adapter=ZarrBlockedAdapter)`` triggers
%   ``openToRead(src)`` (resolve which zarr arrays are the pyramid levels) then
%   ``getInfo()`` (report sizes/block sizes/datatype). Each subsequent
%   ``gather``/``getRegion``/``getBlock`` is serviced by one or more
%   ``getIOBlock(ioBlockSub, level)`` calls.
%   *Write:* ``blockedImage(dst, imageSize, blockSize, initVal, Mode="w",
%   Adapter=ZarrBlockedAdapter)`` triggers ``openToWrite(dst, info, ...)``
%   (create the levels + OME-NGFF metadata); each ``setBlock`` becomes one
%   ``setIOBlock(ioBlockSub, level, data)`` call.
%
% **Pyramid / level model.**
%   Each entry in the OME-Zarr group's ``multiscales.datasets`` becomes one
%   ``blockedImage`` resolution level. Level 1 (MATLAB 1-based) is the finest.
%   ``getInfo`` returns ``Size`` and ``IOBlockSize`` as ``[nLevels x nDims]``
%   matrices. A bare zarr array (no group / no ``multiscales``) is exposed as a
%   single-level image.
%
% **IOBlockSize.**
%   The reported I/O block size is the zarr **chunk** shape (clamped so it
%   never exceeds the level ``Size`` — a ``blockedImage`` requirement that
%   coarse pyramid levels can otherwise violate). Aligning the ``blockedImage``
%   block grid to the zarr chunk grid means partial reads/writes touch whole
%   chunks, which is the efficient access pattern for zarr.
%
% **Axis order — important.**
%   Arrays created **through this adapter** (and through ``ZarrArray.create``)
%   carry a *transpose codec*, so pixels are stored and returned in MATLAB
%   column-major ``[y, x, z, ...]`` order. No axis permutation is applied here,
%   and ``bbox``/``Size`` are all in MATLAB order. This is the right behaviour
%   for **MIB-native** stores (the ones MIB writes itself).
%
%   Externally authored OME-Zarr is usually declared in Python/C-order
%   (e.g. ``tczyx``); reading those correctly requires an axis permutation that
%   this adapter does **not** perform. That C-order path is handled elsewhere
%   by ``io.loaders.Zarr3VirtualLoader`` (used by ``core.MibVirtualImage`` /
%   ``core.MibBigDataImage`` to display the image). In short: use this adapter
%   for stores MIB creates; use ``Zarr3VirtualLoader`` to read foreign ones.
%
% **bbox convention.**
%   ``ZarrArray.read``/``write`` take an ``[nDims x 2]`` bbox of
%   ``[start, end_exclusive]`` per dimension, 1-based (MATLAB). Throughout this
%   class an inclusive pixel range ``[a b]`` is therefore passed as
%   ``[a, b+1]``.
%
% **getInfo contract** (the struct returned to ``blockedImage``):
%   - ``Size``        — ``[nLevels x nDims]`` pixel size of each level
%   - ``IOBlockSize`` — ``[nLevels x nDims]`` I/O block (= zarr chunk) size
%   - ``Datatype``    — ``[nLevels x 1]`` string array of MATLAB classes
%   - ``InitialValue``— scalar fill value for not-yet-written blocks
%
% **Where this fits in MIB3 BigData.**
%   This adapter is the reusable ``blockedImage``↔zarr bridge (handy for
%   block-wise processing, ``apply``-based pipelines, parallel writes, and a
%   future Zarr3 saver). **Note:** the interactive segmentation model
%   (``core.MibBigDataLabels``) does *not* currently go through this adapter —
%   for the packed read-modify-write + cross-level propagation it talks to
%   ``ZarrArray``/``ZarrGroup`` directly (see that class). The two share the
%   same native zarr engine and axis-order conventions.
%
% **Examples**
%
% **Example 1** — open a MIB-native pyramid and pull data:
%
%   .. code-block:: matlab
%
%      bim = blockedImage('C:\data\vol.zarr3', Adapter=io.adapters.ZarrBlockedAdapter);
%      L1  = gather(bim, 'Level', 1);              % finest level into memory
%      sub = getRegion(bim, [10 5 3], [20 9 4]);   % arbitrary sub-region (level 1)
%
% **Example 2** — inspect the store before reading (sizes, block grid, levels):
%
%   .. code-block:: matlab
%
%      bim = blockedImage('C:\data\vol.zarr3', Adapter=io.adapters.ZarrBlockedAdapter);
%      bim.NumLevels        % e.g. 5
%      bim.Size             % [nLevels x nDims] pixels per level (finest first)
%      bim.IOBlockSize      % [nLevels x nDims] zarr chunk size per level
%      bim.ClassUnderlying  % e.g. "uint16"
%
% **Example 3** — read a specific coarse level (fast, low memory):
%
%   .. code-block:: matlab
%
%      bim   = blockedImage('C:\data\vol.zarr3', Adapter=io.adapters.ZarrBlockedAdapter);
%      thumb = gather(bim, 'Level', bim.NumLevels);   % coarsest level (a thumbnail)
%
% **Example 4** — read just one I/O block (no full gather):
%
%   .. code-block:: matlab
%
%      bim  = blockedImage('C:\data\vol.zarr3', Adapter=io.adapters.ZarrBlockedAdapter);
%      blk  = getBlock(bim, [1 1 1]);                 % first block of level 1
%      blk2 = getBlock(bim, [2 1 1], 'Level', 2);     % a block of level 2
%
% **Example 5** — create a writable multi-level store and write blocks:
%
%   .. code-block:: matlab
%
%      adapter   = io.adapters.ZarrBlockedAdapter;
%      imageSize = [887 813 171; 444 407 171; 222 204 86];   % 3 levels [y x z]
%      blockSize = [ 64  64  16;  64  64  16;  64  64 16];   % I/O block per level
%      bim = blockedImage('C:\data\out.zarr3', imageSize, blockSize, ...
%                         uint8(0), Mode="w", Adapter=adapter);
%      setBlock(bim, [1 1 1], uint8(block));          % -> setIOBlock -> ZarrArray.write
%
% **Example 6** — single bare array (no pyramid group) round-trip:
%
%   .. code-block:: matlab
%
%      data = uint16(randi(1000, 128, 96, 8));
%      ZarrArray.createFromData('C:\data\plain.zarr3', data, 'chunkShape', [64 64 4]);
%      bim  = blockedImage('C:\data\plain.zarr3', Adapter=io.adapters.ZarrBlockedAdapter);
%      isequal(gather(bim), data)                     % true (1 level, native order)
%
% **Example 7** — choose a different codec on write:
%
%   .. code-block:: matlab
%
%      adapter = io.adapters.ZarrBlockedAdapter;
%      adapter.Compressors = 'none';                  % or struct('name','gzip'), etc.
%      bim = blockedImage('C:\data\raw.zarr3', [256 256 16], [64 64 8], ...
%                         uint8(0), Mode="w", Adapter=adapter);
%
% **Example 8** — block-wise ``apply`` straight to a new zarr:
%
%   .. code-block:: matlab
%
%      bin  = blockedImage('C:\data\vol.zarr3', Adapter=io.adapters.ZarrBlockedAdapter);
%      bout = apply(bin, @(bs) imgaussfilt(bs.Data, 2), ...
%                   'OutputLocation', 'C:\data\smoothed.zarr3', ...
%                   'Adapter', io.adapters.ZarrBlockedAdapter);
%
% **Example 9** — parallel ``apply`` (the adapter supports parallel append):
%
%   .. code-block:: matlab
%
%      bin  = blockedImage('C:\data\vol.zarr3', Adapter=io.adapters.ZarrBlockedAdapter);
%      bout = apply(bin, @(bs) bs.Data > 128, ...
%                   'OutputLocation', 'C:\data\mask.zarr3', ...
%                   'Adapter', io.adapters.ZarrBlockedAdapter, ...
%                   'UseParallel', true);
%
% **Example 10** — feed a deep-learning pipeline via a datastore:
%
%   .. code-block:: matlab
%
%      bim = blockedImage('C:\data\vol.zarr3', Adapter=io.adapters.ZarrBlockedAdapter);
%      bimds = blockedImageDatastore(bim, 'BlockSize', [256 256], 'Levels', 1);
%      blk = read(bimds);                             % one block, ready for training
%
% See also: blockedImage, blockedImageDatastore, images.blocked.Adapter,
% ZarrArray, ZarrGroup, io.loaders.Zarr3VirtualLoader, core.MibBigDataLabels,
% core.MibBigDataImage.

    properties
        Compressors = 'zstd'
        % [char | struct | cell] codec specification forwarded to
        % ``ZarrArray.create`` when writing (``openToWrite``). Accepts anything
        % ``ZarrArray.create``'s ``compressors`` argument accepts, e.g.
        % ``'zstd'``, ``'none'``, ``struct('name','gzip')``.
    end

    properties (Access = private)
        Location (1,1) string = ""
        % [string] zarr root path: an OME-Zarr group of pyramid levels, or a
        % single bare array. Set by openToRead/openToWrite.
        LevelNames cell = {}
        % {1 x nLevels} relative level paths within the group, finest first
        % (e.g. ``{'0','1','2'}``). ``{''}`` when the root is a single array.
        Arrays cell = {}
        % {1 x nLevels} cached ZarrArray handles, one per resolution level.
        Info struct = struct()
        % cached getInfo() result (Size, IOBlockSize, Datatype, InitialValue),
        % reused by getIOBlock/setIOBlock to avoid re-reading metadata.
    end

    % ============================================================ read path
    methods
        function openToRead(obj, source)
            % OPENTOREAD - Prepare to read a zarr store (required Adapter method).
            %
            % Called by ``blockedImage`` before any read. Records the root path
            % and resolves the pyramid levels (via ``discoverLevels``).
            %
            % Input Arguments:
            %   - **source** — [char | string] path to the zarr group or array.
            obj.Location = string(source);
            obj.discoverLevels();
        end

        function info = getInfo(obj)
            % GETINFO - Describe the store to blockedImage (required Adapter method).
            %
            % Builds the per-level ``Size``/``IOBlockSize``/``Datatype`` and the
            % scalar ``InitialValue`` from each level's zarr metadata. ``Size``
            % comes from each array's shape; ``IOBlockSize`` from its chunk
            % shape, clamped so it never exceeds ``Size`` (blockedImage rejects
            % a block size larger than the image — common at coarse levels).
            %
            % Output Arguments:
            %   - **info** — struct with fields ``Size`` ``[nLevels x nDims]``,
            %     ``IOBlockSize`` ``[nLevels x nDims]``, ``Datatype``
            %     ``[nLevels x 1]`` string, and ``InitialValue`` (scalar).
            if isempty(obj.Arrays); obj.discoverLevels(); end
            nLevels = numel(obj.Arrays);
            nd = numel(obj.Arrays{1}.shape());

            info.Size        = zeros(nLevels, nd);
            info.IOBlockSize = zeros(nLevels, nd);
            dataType = strings(nLevels, 1);
            for level = 1:nLevels
                meta = obj.Arrays{level}.info();
                sz = double(meta.shape);
                % zarr stores the chunk granularity in chunkShape; clamp to the
                % level size so IOBlockSize never exceeds Size (blockedImage rule).
                ib = double(meta.chunkShape);
                ib = min(ib, sz);
                info.Size(level, :)        = obj.padDims(sz, nd);
                info.IOBlockSize(level, :) = obj.padDims(ib, nd);
                dataType(level) = string(meta.dataType);
            end
            info.Datatype     = dataType;
            info.InitialValue = cast(0, char(dataType(1)));
            obj.Info = info;
        end

        function data = getIOBlock(obj, ioBlockSub, level)
            % GETIOBLOCK - Read one I/O block (required Adapter method).
            %
            % Converts a block subscript into a pixel range and reads it from
            % the level's zarr array. Edge blocks are clamped to the level size,
            % so the returned block may be smaller than ``IOBlockSize`` at the
            % image border.
            %
            % Input Arguments:
            %   - **ioBlockSub** — [1 x nDims] 1-based block subscript.
            %   - **level** — [scalar] 1-based resolution level (1 = finest).
            %
            % Output Arguments:
            %   - **data** — the block, in native MATLAB ``[y, x, z, ...]`` order.
            if isempty(fieldnames(obj.Info)); obj.getInfo(); end
            ib = obj.Info.IOBlockSize(level, :);
            sz = obj.Info.Size(level, :);
            start = (double(ioBlockSub(:)') - 1) .* ib + 1;
            edge  = min(start + ib - 1, sz);
            bbox  = [start(:), edge(:) + 1];        % end-exclusive (zarr convention)
            data  = obj.Arrays{level}.read(bbox);
            % restore any trailing singleton dimensions MATLAB drops on read
            data  = reshape(data, edge - start + 1);
        end
    end

    % =========================================================== write path
    methods
        function openToWrite(obj, destination, info, ~)
            % OPENTOWRITE - Create a writable store (optional Adapter method).
            %
            % Creates the OME-Zarr group and one zarr array per level (sized and
            % chunked from ``info``), then writes a minimal ``multiscales``
            % attribute so the result reopens as a pyramid. An existing folder
            % at the destination is removed first.
            %
            % Input Arguments:
            %   - **destination** — [char | string] zarr group path to create.
            %   - **info** — blockedImage info struct (``Size``, ``IOBlockSize``,
            %     ``Datatype``, ``InitialValue``); the 4th arg (level) is unused
            %     because all levels are created up front.
            obj.Location = string(destination);
            obj.Info = info;
            nLevels = size(info.Size, 1);
            obj.LevelNames = arrayfun(@(k) num2str(k-1), 1:nLevels, 'UniformOutput', false);

            dst = char(destination);
            if isfolder(dst); rmdir(dst, 's'); end
            grp = ZarrGroup.create(dst);

            obj.Arrays = cell(1, nLevels);
            for level = 1:nLevels
                dt = char(info.Datatype(level));
                if strcmp(dt, 'logical'); dt = 'uint8'; end
                shp = double(info.Size(level, :));
                chk = min(double(info.IOBlockSize(level, :)), shp);
                obj.Arrays{level} = grp.createArray(obj.LevelNames{level}, shp, dt, ...
                    'chunkShape', chk, 'compressors', obj.Compressors, ...
                    'fillValue', double(info.InitialValue));
            end
            obj.writeMultiscales(grp, info);
        end

        function setIOBlock(obj, ioBlockSub, level, data)
            % SETIOBLOCK - Write one I/O block (optional Adapter method).
            %
            % Writes ``data`` at the pixel offset implied by ``ioBlockSub``. The
            % written extent is taken from ``size(data)`` (edge blocks may be
            % smaller than ``IOBlockSize``). ``logical`` data is stored as uint8.
            %
            % Input Arguments:
            %   - **ioBlockSub** — [1 x nDims] 1-based block subscript.
            %   - **level** — [scalar] 1-based resolution level.
            %   - **data** — block data in native MATLAB ``[y, x, z, ...]`` order.
            ib = obj.Info.IOBlockSize(level, :);
            start = (double(ioBlockSub(:)') - 1) .* ib + 1;
            dt = char(obj.Info.Datatype(level));
            if strcmp(dt, 'logical'); dt = 'uint8'; end
            data = cast(data, dt);
            ds = size(data, 1:numel(start));        % actual (possibly edge-clamped) size
            edge = start + ds - 1;
            bbox = [start(:), edge(:) + 1];
            obj.Arrays{level}.write(data, bbox);
        end
    end

    % =============================================================== private
    methods (Access = private)
        function discoverLevels(obj)
            % DISCOVERLEVELS - Resolve the pyramid levels at obj.Location.
            %
            % If the path is an OME-Zarr group with a ``multiscales`` attribute,
            % the level paths are taken (in order) from ``multiscales.datasets``.
            % If it is a group without ``multiscales``, all child arrays are used.
            % Otherwise the path is treated as a single bare array (one level).
            % Opened ZarrArray handles are cached in ``obj.Arrays``.
            try
                grp = ZarrGroup(char(obj.Location));
                attrs = grp.getAttributes();
                if isfield(attrs, 'multiscales')
                    ms = attrs.multiscales;
                    if iscell(ms); ms = ms{1}; elseif numel(ms) > 1; ms = ms(1); end
                    ds = ms.datasets;
                    nL = numel(ds);
                    obj.LevelNames = cell(1, nL);
                    for k = 1:nL
                        if iscell(ds); d = ds{k}; else; d = ds(k); end
                        obj.LevelNames{k} = char(d.path);
                    end
                else
                    obj.LevelNames = grp.list();
                end
                obj.Arrays = cellfun(@(n) grp.openArray(n), obj.LevelNames, ...
                    'UniformOutput', false);
            catch
                % not a group -> a single zarr array at the root
                obj.LevelNames = {''};
                obj.Arrays = { ZarrArray(char(obj.Location)) };
            end
        end

        function writeMultiscales(obj, grp, info)
            % WRITEMULTISCALES - Write a minimal OME-NGFF v0.5 ``multiscales`` attribute.
            %
            % Records each level's relative downsampling (``Size(1)./Size(level)``)
            % as a ``scale`` coordinate transformation so the group reopens as a
            % pyramid. Physical voxel size / bounding-box enrichment is left to
            % the dedicated Zarr3 saver (a later phase).
            nLevels = size(info.Size, 1);
            nd = size(info.Size, 2);
            axisNames = {'y', 'x', 'z', 'c', 't'};
            axisNames = axisNames(1:min(nd, 5));
            axes = cell(1, numel(axisNames));
            for a = 1:numel(axisNames)
                axes{a} = struct('name', axisNames{a}, 'type', 'space');
            end
            datasets = cell(1, nLevels);
            base = info.Size(1, :);
            for level = 1:nLevels
                scale = base ./ info.Size(level, :);
                datasets{level} = struct('path', obj.LevelNames{level}, ...
                    'coordinateTransformations', {{struct('type', 'scale', 'scale', scale)}});
            end
            ms = struct('version', '0.5', 'axes', {axes}, 'datasets', {datasets});
            grp.setAttributes(struct('multiscales', {{ms}}));
        end
    end

    methods (Static, Access = private)
        function v = padDims(v, nd)
            % PADDIMS - Pad a size/chunk vector with trailing singletons to nd dims.
            % Keeps Size and IOBlockSize rectangular when a level's shape vector
            % has fewer entries than the reference dimensionality.
            v = double(v(:)');
            if numel(v) < nd
                v(end+1:nd) = 1;
            end
        end
    end
end
