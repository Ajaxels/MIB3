classdef Zarr2VirtualLoader < handle
% ZARR2VIRTUALLOADER - On-demand region reader for MIB3 Zarr v2 virtual datasets.
%
% Counterpart to ``Zarr3VirtualLoader``, and mechanically identical to it: the
% region is read through ``io.zarr.Array``, so the engine follows
% ``io.zarr.Config`` (native ``zarrMex`` or ``zarr-python``) exactly as it does
% for v3. The bundled ``zarrMex`` reads v2 stores - local and over HTTP range
% requests - so **python is no longer required for zarr v2**, and both engines
% return byte-identical data.
%
% The class stays separate from ``Zarr3VirtualLoader`` because
% ``MibVirtualImage`` dispatches on the stored ``objectType`` / ``sourceType``
% (``'zarr2'`` vs ``'zarr3'``), which is metadata recorded when the dataset was
% opened.
%
% **Relationship to Zarr2VirtualSetupLoader**
%
% Zarr2VirtualSetupLoader - runs ONCE when the user opens a zarr v2 file.
% Phase : dataset initialisation (MibModel.loadImages)
% Job : parse OME-Zarr v2 metadata (.zattrs/.zarray), build pyramid struct.
% Reads pixels? Yes (Standard/Model mode) / No (Virtual/BigData mode).
% Lifetime: discarded after open; implements BaseImageLoader.
% Created by: LoaderFactory (case "OmeZarrV2")
%
% Zarr2VirtualLoader - runs on EVERY slice/region request during the session.
% Phase : on-demand pixel reading (MibVirtualImage.getDataZarr).
% Job : read sub-region via io.zarr.PyBackend.readArray.
% Reads pixels? Yes.
% Lifetime: cached in MibVirtualImage.loaders{1} for the session.
% Created by: MibVirtualImage.getDataZarr / getOrCreateLoader
%
% Axis order convention (identical to Zarr3VirtualLoader): a read returns data
% whose layout is the reverse of the zarr ``shape`` declaration. For OME-Zarr
% with axisOrder ``'czyx'`` (shape [nC,nZ,nY,nX]), the returned MATLAB array
% has size [nX, nY, nZ, nC].
% ``io.loaders.OmeZarrMetadataUtils.computePermutation`` precomputes the
% permutation that maps this to MIB3 ``[y, x, z, c, t]``.
%
% **Example** - local OME-Zarr v2 dataset:
%
%   .. code-block:: matlab
%
%      loader = io.loaders.Zarr2VirtualLoader('C:\data\stack.zarr2', 'tczyx');
%      % Read 512x512 region at z=5, channels 1-2, t=1 from level 's0'
%      block = loader.readRegion('s0', [1,512], [1,512], [5,5], [1,2], [1,1], 'uint16');
%      % block is [512, 512, 1, 2, 1] in [y,x,z,c,t] order

properties (SetAccess = private)
    rootPath
    % [char] Zarr root path (local folder or HTTP/HTTPS URL)
    axisOrder
    % [char] OME-Zarr axis order in Python/C-order declaration, e.g. 'tczyx'.
    toMIB3perm
    % [1x5] permutation vector: permute(raw, toMIB3perm) -> [y,x,z,c,t].
    cachedLevelPath = ''
    % [char] full path of the level whose io.zarr.Array is currently cached.
    cachedArray = []
    % [io.zarr.Array] reused across slice reads at the same pyramid level, so the
    % backend handle is opened once per level rather than per read. Refreshed when
    % the requested level changes.
    cachedInfo = []
    % [struct] shape / chunkShape of cachedArray, needed by io.zarr.ChunkCache to
    % work out which chunks a request touches. Fetched with the handle above.
end

methods
    function obj = Zarr2VirtualLoader(rootPath, axisOrder)
        % ZARR2VIRTUALLOADER - Create an on-demand Zarr v2 region reader.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj = Zarr2VirtualLoader(rootPath)
        %      obj = Zarr2VirtualLoader(rootPath, axisOrder)
        %
        % Input Arguments:
        %   - **rootPath** - [char] zarr root path (local folder or HTTP/HTTPS URL)
        %   - **axisOrder** - *(optional)* [char] OME-Zarr axis order in Python
        %     C-order declaration, e.g. ``'tczyx'``, ``'czyx'``, ``'zyx'``
        %     (default: ``'tczyx'``)
        %
        % Output Arguments:
        %   - **obj** - [Zarr2VirtualLoader] new loader instance

        obj.rootPath = rootPath;
        if nargin < 2 || isempty(axisOrder)
            axisOrder = 'tczyx';
        end
        obj.axisOrder  = lower(char(axisOrder));
        obj.toMIB3perm = io.loaders.OmeZarrMetadataUtils.computePermutation(obj.axisOrder);
    end

    function block = readRegion(obj, levelPath, physYlim, physXlim, physZlim, Clim, Tlim, dataClass)
        % READREGION - Read a sub-region from a Zarr v2 array at the specified pyramid level.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      block = obj.readRegion(levelPath, physYlim, physXlim, physZlim, Clim, Tlim, dataClass)
        %
        % Always receives PHYSICAL coordinate ranges (not screen-remapped).
        % Always returns data in MIB3 [y, x, z, c, t] order.
        %
        % Input Arguments:
        %   - **levelPath** - [char] relative pyramid level path within root,
        %     e.g. ``'s0'`` or ``'0'``; pass ``''`` to read from the root array directly
        %   - **physYlim** - [1x2 numeric] physical Y range ``[ymin ymax]`` (1-based, inclusive)
        %   - **physXlim** - [1x2 numeric] physical X range ``[xmin xmax]`` (1-based, inclusive)
        %   - **physZlim** - [1x2 numeric] physical Z range ``[zmin zmax]`` (1-based, inclusive)
        %   - **Clim** - [1x2 numeric] channel range ``[cmin cmax]`` (1-based, inclusive)
        %   - **Tlim** - [1x2 numeric] time range ``[tmin tmax]`` (1-based, inclusive)
        %   - **dataClass** - [char] output MATLAB class, e.g. ``'uint8'`` or ``'uint16'``
        %
        % Output Arguments:
        %   - **block** - [nY x nX x nZ x nC x nT numeric] array in MIB3 [y,x,z,c,t] order

        if isempty(levelPath)
            fullPath = obj.rootPath;
        else
            if startsWith(obj.rootPath, 'http://') || startsWith(obj.rootPath, 'https://')
                fullPath = [obj.rootPath, '/', levelPath];
            else
                fullPath = fullfile(obj.rootPath, levelPath);
            end
        end

        % Build axis range lookup (1-based inclusive)
        axisRanges.y = physYlim;
        axisRanges.x = physXlim;
        axisRanges.z = physZlim;
        axisRanges.c = Clim;
        axisRanges.t = Tlim;

        % Build bbox in zarr's C-order (same convention as Zarr3VirtualLoader).
        bbox = io.loaders.OmeZarrMetadataUtils.buildZarrBbox(obj.axisOrder, axisRanges);

        % Open (or reuse) the array handle for this level - one open + one
        % metadata query per level, not per slice read.
        if isempty(obj.cachedArray) || ~strcmp(fullPath, obj.cachedLevelPath)
            obj.cachedArray     = io.zarr.Array(fullPath);
            obj.cachedInfo      = obj.cachedArray.info();
            obj.cachedLevelPath = fullPath;
        end
        % once per opened level: the cache key carries the store version, so a store
        % rewritten at this path is never served from the old one's chunks
        if ~isfield(obj.cachedInfo, 'cacheKey')
            obj.cachedInfo.cacheKey = io.zarr.ChunkCache.storeKey(fullPath);
        end
        % Serve whole decoded chunks from memory where possible. Chunks are the
        % smallest unit the store will hand over and are usually many slices
        % deep, so without this every z-step re-fetches the same chunks and
        % throws away all but one plane of each.
        raw = io.zarr.ChunkCache.read(obj.cachedInfo.cacheKey, bbox, obj.cachedInfo.chunkShape, ...
            obj.cachedInfo.shape, @(alignedBbox) obj.cachedArray.read(alignedBbox));

        % Permute to MIB3 [y, x, z, c, t] and cast to the requested class
        block = permute(raw, obj.toMIB3perm);
        block = cast(block, dataClass);
    end
end
end
