classdef Zarr2VirtualLoader < handle
% ZARR2VIRTUALLOADER - On-demand region reader for MIB3 Zarr v2 virtual datasets.
%
% Python-backed counterpart to ``Zarr3VirtualLoader``. Zarr v2 has no native
% (zarrMex) engine, so this reader always goes through ``io.zarr.PyBackend``
% (``zarr.open`` + raw ``pyrun`` byte transfers) rather than ``io.zarr.Array``
% - the latter's metadata path is native-only and cannot open a v2 store at
% all. ``io.zarr.PyBackend``'s bulk-I/O calls are otherwise format-agnostic
% (``zarr-python`` auto-detects v2 vs v3), so no separate python code is
% needed here beyond calling that facade.
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
% Axis order convention (identical to Zarr3VirtualLoader): a python zarr read
% returns data in zarr's declared C-order axis layout. For OME-Zarr with
% axisOrder ``'czyx'`` (shape [nC,nZ,nY,nX]), the returned MATLAB array has
% size [nC, nZ, nY, nX]. ``io.loaders.OmeZarrMetadataUtils.computePermutation``
% precomputes the permutation that maps this to MIB3 ``[y, x, z, c, t]``.
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
    % [char] full path of the level whose python array handle is currently cached.
    cachedPyArray = []
    % [py object] open python zarr array handle, reused across slice reads at
    % the same pyramid level so it is opened once per level, not once per read.
    cachedMeta = []
    % [struct] io.zarr.PyBackend.arrayMeta() result for cachedPyArray (shape/dtype
    % cached alongside the handle to avoid re-querying python on every read).
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
        % Always returns data in MIB3 [y, x, z, c, t] order. Assumes the
        % python zarr backend is already available - ``Zarr2VirtualSetupLoader``
        % calls ``io.zarr.PyBackend.ensureLoaded()`` at file-open time so any
        % "python unavailable" failure surfaces once, up front, rather than on
        % every slice scrub.
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
        nDims = numel(obj.axisOrder);
        bbox  = zeros(nDims, 2); % [start_1based, end_exclusive (end+1)]
        for dimIdx = 1:nDims
            ax = obj.axisOrder(dimIdx);
            if isfield(axisRanges, ax)
                rng = axisRanges.(ax);
                bbox(dimIdx, :) = [rng(1), rng(2) + 1];
            else
                bbox(dimIdx, :) = [1, 2]; % singleton for absent axis
            end
        end

        % Open (or reuse) the python array handle for this level - one open +
        % one metadata query per level, not per slice read.
        if isempty(obj.cachedPyArray) || ~strcmp(fullPath, obj.cachedLevelPath)
            obj.cachedPyArray   = io.zarr.PyBackend.openArray(fullPath, 'r');
            obj.cachedMeta      = io.zarr.PyBackend.arrayMeta(obj.cachedPyArray);
            obj.cachedLevelPath = fullPath;
        end
        % Serve whole decoded chunks from memory where possible. Chunks are the
        % smallest unit the store will hand over and are usually many slices
        % deep, so without this every z-step re-fetches the same chunks and
        % throws away all but one plane of each.
        raw = io.zarr.ChunkCache.read(fullPath, bbox, obj.cachedMeta.chunkShape, ...
            obj.cachedMeta.shape, ...
            @(alignedBbox) io.zarr.PyBackend.readArray(obj.cachedPyArray, alignedBbox, obj.cachedMeta));

        % Permute to MIB3 [y, x, z, c, t] and cast to the requested class
        block = permute(raw, obj.toMIB3perm);
        block = cast(block, dataClass);
    end
end
end
