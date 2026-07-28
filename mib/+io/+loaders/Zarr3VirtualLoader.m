classdef Zarr3VirtualLoader < handle
% ZARR3VIRTUALLOADER - On-demand region reader for MIB3 Zarr v3 virtual datasets.
%
% Wraps a single OME-Zarr v3 root and reads sub-regions from any
% pyramid level on demand via the zarr-matlab library (zarrMex).
% Axis-order mapping between zarr's C-order storage and MIB3's
% [y, x, z, c, t] Fortran order is precomputed in the constructor.
%
% Unlike batch loaders in +io/+loaders/ this class does NOT implement
% BaseImageLoader — it is stateful and designed for repeated sub-region
% reads rather than a single full-dataset load.
%
% **Relationship to OmeZarrLoader**
%
% OmeZarrLoader — runs ONCE when the user opens a .zarr3 file.
% Phase : dataset initialisation (MibModel.loadImages)
% Job : parse OME-Zarr metadata, build pyramid struct, return path.
% Reads pixels? No (Virtual/BigData mode) / Yes (Standard mode).
% Lifetime: discarded after open; implements BaseImageLoader.
% Created by: LoaderFactory (via case "OmeZarr")
%
% Zarr3VirtualLoader — runs on EVERY slice request during the session.
% Phase : on-demand pixel reading (MibVirtualImage.getDataZarr)
% Job : read sub-region via ZarrArray.read(bbox).
% Reads pixels? Yes.
% Lifetime: cached in MibVirtualImage.loaders{1} for the session.
% Created by: MibVirtualImage.getDataZarr (lazy init) or getOrCreateLoader
%
% Axis order convention:
% zarrMex reverses the C-order declaration from zarr.json to MATLAB
% Fortran order. For an OME-Zarr array declared as [t,c,z,y,x]
% (Python shape [nT,nC,nZ,nY,nX]), zarrMex returns an array of size
% [nX, nY, nZ, nC, nT] in MATLAB. computePermutation() precomputes
% the permutation vector that maps this to MIB3 [y, x, z, c, t].
%
% **Example 1** — local OME-Zarr v3 dataset:
%
%   .. code-block:: matlab
%
%      loader = io.loaders.Zarr3VirtualLoader('C:\data\stack.zarr3', 'tczyx');
%      % Read 512x512 region at z=5, channels 1-2, t=1 from level '0'
%      block = loader.readRegion('0', [1,512], [1,512], [5,5], [1,2], [1,1], 'uint16');
%      % block is [512, 512, 1, 2, 1] in [y,x,z,c,t] order
%
% **Example 2** — remote OME-Zarr v3 dataset (HTTP):
%
%   .. code-block:: matlab
%
%      loader = io.loaders.Zarr3VirtualLoader('https://example.com/data.zarr3', 'czyx');
%      block = loader.readRegion('0', [1,256], [1,256], [1,10], [1,1], [1,1], 'uint8');

properties (SetAccess = private)
    rootPath
    % [char] Zarr root path (local folder or HTTP/HTTPS URL)
    axisOrder
    % [char] OME-Zarr axis order in Python/C-order declaration, e.g. 'tczyx'.
    % zarrMex reverses this to MATLAB Fortran order on reading.
    toMIB3perm
    % [1x5] permutation vector: permute(raw_from_zarrMex, toMIB3perm) -> [y,x,z,c,t].
    % Precomputed from axisOrder in the constructor.
    cachedLevelPath = ''
    % [char] full path of the level whose io.zarr.Array is currently cached.
    cachedArray = []
    % [io.zarr.Array] reused across slice reads at the same pyramid level, so the
    % backend handle (and, for python, the open py array + metadata) is opened once
    % per level rather than per read. Refreshed when the requested level changes.
end

methods
    function obj = Zarr3VirtualLoader(rootPath, axisOrder)
        % ZARR3VIRTUALLOADER - Create an on-demand Zarr v3 region reader.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj = Zarr3VirtualLoader(rootPath)
        %      obj = Zarr3VirtualLoader(rootPath, axisOrder)
        %
        % Stores the zarr root path and precomputes the axis-order
        % permutation from the OME-Zarr C-order declaration to MIB3.
        %
        % Input Arguments:
        %   - **rootPath** — [char] zarr root path (local folder or HTTP/HTTPS URL)
        %   - **axisOrder** — *(optional)* [char] OME-Zarr axis order in Python
        %     C-order declaration, e.g. ``'tczyx'``, ``'czyx'``, ``'zyx'``
        %     (default: ``'tczyx'``)
        %
        % Output Arguments:
        %   - **obj** — [Zarr3VirtualLoader] new loader instance
        %
        % **Example** — local and remote datasets:
        %
        %   .. code-block:: matlab
        %
        %      % Local 5D OME-Zarr (default axis order)
        %      loader = io.loaders.Zarr3VirtualLoader('C:\data\vol.zarr3');
        %      % Remote 4D OME-Zarr (no time axis)
        %      loader = io.loaders.Zarr3VirtualLoader('https://host/data.zarr3', 'czyx');
        %

        obj.rootPath = rootPath;
        if nargin < 2 || isempty(axisOrder)
            axisOrder = 'tczyx';
        end
        obj.axisOrder  = lower(char(axisOrder));
        obj.toMIB3perm = io.loaders.OmeZarrMetadataUtils.computePermutation(obj.axisOrder);
    end

    function block = readRegion(obj, levelPath, physYlim, physXlim, physZlim, Clim, Tlim, dataClass)
        % READREGION - Read a sub-region from a Zarr v3 array at the specified pyramid level.
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
        %   - **levelPath** — [char] relative pyramid level path within root,
        %     e.g. ``'0'`` or ``'1'``; pass ``''`` to read from the root array directly
        %   - **physYlim** — [1x2 numeric] physical Y range ``[ymin ymax]`` (1-based, inclusive)
        %   - **physXlim** — [1x2 numeric] physical X range ``[xmin xmax]`` (1-based, inclusive)
        %   - **physZlim** — [1x2 numeric] physical Z range ``[zmin zmax]`` (1-based, inclusive)
        %   - **Clim** — [1x2 numeric] channel range ``[cmin cmax]`` (1-based, inclusive)
        %   - **Tlim** — [1x2 numeric] time range ``[tmin tmax]`` (1-based, inclusive)
        %   - **dataClass** — [char] output MATLAB class, e.g. ``'uint8'`` or ``'uint16'``
        %
        % Output Arguments:
        %   - **block** — [nY x nX x nZ x nC x nT numeric] array in MIB3 [y,x,z,c,t] order
        %
        % **Example** — read channel 1, z=10..20, full XY 512x512:
        %
        %   .. code-block:: matlab
        %
        %      loader = io.loaders.Zarr3VirtualLoader('C:\data\vol.zarr3', 'czyx');
        %      block = loader.readRegion('0', [1,512], [1,512], [10,20], [1,1], [1,1], 'uint8');
        %      % block is [512, 512, 11, 1, 1]
        %

        % Build full path to this pyramid level
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

        % Build bbox in zarr's C-order (same as axisOrder).
        % zarrMex expects bbox rows in zarr's declared C-order axis order
        % and returns data with the same dimension layout.
        % e.g. axisOrder='czyx': bbox rows are [c_range; z_range; y_range; x_range]
        % and the returned array has size [nC, nZ, nY, nX].
        nDims = numel(obj.axisOrder);

        % bbox is [nDims x 2]: [start_1based, end_exclusive (end+1)]
        bbox = zeros(nDims, 2);
        for dimIdx = 1:nDims
            ax = obj.axisOrder(dimIdx);     % C-order axis at this position
            if isfield(axisRanges, ax)
                rng = axisRanges.(ax);
                bbox(dimIdx, :) = [rng(1), rng(2) + 1];
            else
                bbox(dimIdx, :) = [1, 2];   % singleton for absent axis
            end
        end

        % Read from zarr through the backend-selectable facade
        % (native zarrMex or python zarr, per io.zarr.Config / preferences.IO.Zarr.Library).
        % Cache the level handle so the backend (and python py-handle/metadata) is
        % opened once per level instead of per slice read.
        if isempty(obj.cachedArray) || ~strcmp(fullPath, obj.cachedLevelPath)
            obj.cachedArray     = io.zarr.Array(fullPath);
            obj.cachedLevelPath = fullPath;
        end
        raw = obj.cachedArray.read(bbox);   % returns data in zarr C-order

        % Permute to MIB3 [y, x, z, c, t]
        block = permute(raw, obj.toMIB3perm);

        % Cast to requested class
        block = cast(block, dataClass);
    end
end

methods (Access = public)
    function perm = computePermutation(~, axisOrder)
        % COMPUTEPERMUTATION - Compute the permutation from zarrMex output to MIB3 [y,x,z,c,t].
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      perm = obj.computePermutation(axisOrder)
        %
        % Thin wrapper kept for backward compatibility (e.g.
        % ``Zarr3VirtualSetupLoader`` previously created a throwaway loader
        % instance just to call this) — delegates to the version-agnostic
        % ``io.loaders.OmeZarrMetadataUtils.computePermutation``.
        %
        % Input Arguments:
        %   - **axisOrder** — [char] zarr C-order axis declaration,
        %     e.g. ``'czyx'`` or ``'tczyx'``
        %
        % Output Arguments:
        %   - **perm** — [1x5 numeric] permutation for ``permute(raw, perm)`` → [y,x,z,c,t]
        %
        % **Example** — permutation for common axis orders:
        %
        %   .. code-block:: matlab
        %
        %      loader = io.loaders.Zarr3VirtualLoader('');
        %      perm = loader.computePermutation('czyx');   % returns [3,4,2,1,5]
        %      perm = loader.computePermutation('tczyx');  % returns [4,5,3,2,1]
        %      perm = loader.computePermutation('zyx');    % returns [2,3,1,4,5]
        %

        perm = io.loaders.OmeZarrMetadataUtils.computePermutation(axisOrder);
    end
end
end
