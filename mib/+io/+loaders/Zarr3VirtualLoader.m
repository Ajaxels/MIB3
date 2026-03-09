classdef Zarr3VirtualLoader < handle
    % classdef Zarr3VirtualLoader < handle
    % On-demand region reader for MIB3 Zarr v3 virtual datasets.
    %
    % Wraps a single OME-Zarr v3 root and reads sub-regions from any
    % pyramid level on demand via the Zarr3Matlab library (zarrMex).
    % Axis-order mapping between zarr's C-order storage and MIB3's
    % [y, x, z, c, t] Fortran order is precomputed in the constructor.
    %
    % Unlike batch loaders in +io/+loaders/ this class does NOT implement
    % BaseImageLoader — it is stateful and designed for repeated sub-region
    % reads rather than a single full-dataset load.
    %
    % --- Relationship to OmeZarrLoader -----------------------------------
    %
    %   OmeZarrLoader — runs ONCE when the user opens a .zarr3 file.
    %     Phase   : dataset initialisation (MibModel.loadImages)
    %     Job     : parse OME-Zarr metadata, build pyramid struct, return path.
    %     Reads pixels? No (Virtual/BigData mode) / Yes (Standard mode).
    %     Lifetime: discarded after open; implements BaseImageLoader.
    %     Created by: LoaderFactory (via case "OmeZarr")
    %
    %   Zarr3VirtualLoader — runs on EVERY slice request during the session.
    %     Phase   : on-demand pixel reading (MibVirtualImage.getDataZarr)
    %     Job     : read sub-region via ZarrArray.read(bbox).
    %     Reads pixels? Yes.
    %     Lifetime: cached in MibVirtualImage.loaders{1} for the session.
    %     Created by: MibVirtualImage.getDataZarr (lazy init) or getOrCreateLoader
    %
    % -----------------------------------------------------------------------
    %
    % Axis order convention:
    %   zarrMex reverses the C-order declaration from zarr.json to MATLAB
    %   Fortran order.  For an OME-Zarr array declared as [t,c,z,y,x]
    %   (Python shape [nT,nC,nZ,nY,nX]), zarrMex returns an array of size
    %   [nX, nY, nZ, nC, nT] in MATLAB.  computePermutation() precomputes
    %   the permutation vector that maps this to MIB3 [y, x, z, c, t].
    %
    % Usage examples:
    % @code
    % % Open a local OME-Zarr v3 dataset and read a sub-region
    % loader = io.loaders.Zarr3VirtualLoader('C:\data\stack.zarr3', 'tczyx');
    % % Read 512x512 region at z=5, channels 1-2, t=1 from level '0'
    % block = loader.readRegion('0', [1,512], [1,512], [5,5], [1,2], [1,1], 'uint16');
    % % block is [512, 512, 1, 2, 1] in [y,x,z,c,t] order
    % @endcode
    %
    % @code
    % % Open a remote OME-Zarr v3 dataset (HTTP)
    % loader = io.loaders.Zarr3VirtualLoader('https://example.com/data.zarr3', 'czyx');
    % block = loader.readRegion('0', [1,256], [1,256], [1,10], [1,1], [1,1], 'uint8');
    % @endcode

    properties (SetAccess = private)
        rootPath
        % [char] Zarr root path (local folder or HTTP/HTTPS URL)
        axisOrder
        % [char] OME-Zarr axis order in Python/C-order declaration, e.g. 'tczyx'.
        % zarrMex reverses this to MATLAB Fortran order on reading.
        toMIB3perm
        % [1x5] permutation vector: permute(raw_from_zarrMex, toMIB3perm) -> [y,x,z,c,t].
        % Precomputed from axisOrder in the constructor.
    end

    methods
        function obj = Zarr3VirtualLoader(rootPath, axisOrder)
            % obj = Zarr3VirtualLoader(rootPath, axisOrder)
            % Constructor — stores the zarr root path and precomputes the
            % axis-order permutation from the OME-Zarr declaration to MIB3.
            %
            % Parameters:
            % rootPath  : [char] zarr root path (local folder or HTTP/HTTPS URL)
            % axisOrder : [@em optional, char] OME-Zarr axis order in Python
            %             C-order declaration (e.g. 'tczyx', 'czyx', 'zyx').
            %             Default: 'tczyx'
            %
            % @b Examples:
            % @code
            % % Local 5D OME-Zarr (default axis order)
            % loader = io.loaders.Zarr3VirtualLoader('C:\data\vol.zarr3');
            % % Remote 4D OME-Zarr (no time axis)
            % loader = io.loaders.Zarr3VirtualLoader('https://host/data.zarr3', 'czyx');
            % @endcode

            obj.rootPath = rootPath;
            if nargin < 2 || isempty(axisOrder)
                axisOrder = 'tczyx';
            end
            obj.axisOrder  = lower(char(axisOrder));
            obj.toMIB3perm = obj.computePermutation(obj.axisOrder);
        end

        function block = readRegion(obj, levelPath, physYlim, physXlim, physZlim, Clim, Tlim, dataClass)
            % block = readRegion(obj, levelPath, physYlim, physXlim, physZlim, Clim, Tlim, dataClass)
            % Read a sub-region from a Zarr v3 array at the specified pyramid level.
            %
            % Always receives PHYSICAL coordinate ranges (not screen-remapped).
            % Always returns data in MIB3 [y, x, z, c, t] order.
            %
            % Parameters:
            % levelPath : [char] relative pyramid level path within root, e.g. '0'
            %             or '1'.  Pass '' to read from the root array directly.
            % physYlim  : [ymin, ymax] physical Y range (1-based, inclusive)
            % physXlim  : [xmin, xmax] physical X range (1-based, inclusive)
            % physZlim  : [zmin, zmax] physical Z range (1-based, inclusive)
            % Clim      : [cmin, cmax] channel range (1-based, inclusive)
            % Tlim      : [tmin, tmax] time range (1-based, inclusive)
            % dataClass : [char] output MATLAB class, e.g. 'uint8' or 'uint16'
            %
            % Return values:
            % block : [nY, nX, nZ, nC, nT] array in MIB3 [y,x,z,c,t] order
            %
            % @b Examples:
            % @code
            % loader = io.loaders.Zarr3VirtualLoader('C:\data\vol.zarr3', 'czyx');
            % % Read channel 1, z=10..20, full XY 512x512
            % block = loader.readRegion('0', [1,512], [1,512], [10,20], [1,1], [1,1], 'uint8');
            % % block is [512, 512, 11, 1, 1]
            % @endcode

            % --- Build full path to this pyramid level --------------------
            if isempty(levelPath)
                fullPath = obj.rootPath;
            else
                if startsWith(obj.rootPath, 'http://') || startsWith(obj.rootPath, 'https://')
                    fullPath = [obj.rootPath, '/', levelPath];
                else
                    fullPath = fullfile(obj.rootPath, levelPath);
                end
            end

            % --- Build axis range lookup (1-based inclusive) --------------
            axisRanges.y = physYlim;
            axisRanges.x = physXlim;
            axisRanges.z = physZlim;
            axisRanges.c = Clim;
            axisRanges.t = Tlim;

            % --- Build bbox in zarr's C-order (same as axisOrder) -----------
            % zarrMex expects bbox rows in zarr's declared C-order axis order
            % and returns data with the same dimension layout.
            % e.g. axisOrder='czyx': bbox rows are [c_range; z_range; y_range; x_range]
            % and the returned array has size [nC, nZ, nY, nX].
            nDims = numel(obj.axisOrder);

            % bbox is [nDims x 2]: [start_1based, end_exclusive (end+1)]
            bbox = zeros(nDims, 2);
            for dimIdx = 1:nDims
                ax = obj.axisOrder(dimIdx);   % C-order axis at this position
                if isfield(axisRanges, ax)
                    rng = axisRanges.(ax);
                    bbox(dimIdx, :) = [rng(1), rng(2) + 1];
                else
                    bbox(dimIdx, :) = [1, 2];   % singleton for absent axis
                end
            end

            % --- Read from zarr --------------------------------------------
            arr = ZarrArray(fullPath);
            raw = arr.read(bbox);   % returns data in zarr C-order

            % --- Permute to MIB3 [y, x, z, c, t] -------------------------
            block = permute(raw, obj.toMIB3perm);

            % --- Cast to requested class ----------------------------------
            block = cast(block, dataClass);
        end
    end

    methods (Access = public)
        function perm = computePermutation(~, axisOrder)
            % perm = computePermutation(axisOrder)
            % Compute the permutation from zarrMex output to MIB3 [y,x,z,c,t].
            %
            % zarrMex returns data in zarr's declared C-order axis layout.
            % For OME-Zarr with axisOrder 'czyx' (shape [nC,nZ,nY,nX]),
            % the returned MATLAB array has size [nC, nZ, nY, nX] where
            % dim 1 = C, dim 2 = Z, dim 3 = Y, dim 4 = X.
            % This function computes the permutation that maps that to
            % MIB3's required [y, x, z, c, t] order.
            %
            % Parameters:
            % axisOrder : [char] zarr C-order axis declaration, e.g. 'czyx' or 'tczyx'
            %
            % Return values:
            % perm : [1x5] permutation for permute(raw, perm) -> [y,x,z,c,t]
            %
            % @b Examples:
            % @code
            % loader = io.loaders.Zarr3VirtualLoader('');
            % perm = loader.computePermutation('czyx');   % returns [3,4,2,1,5]
            % perm = loader.computePermutation('tczyx');  % returns [4,5,3,2,1]
            % perm = loader.computePermutation('zyx');    % returns [2,3,1,4,5]
            % @endcode

            mib3Axes      = 'yxzct';     % MIB3 dimension order (dims 1-5)
            nDims         = numel(axisOrder);
            perm          = zeros(1, 5);
            nextSingleton = nDims + 1;

            for k = 1:5
                ax  = mib3Axes(k);
                pos = strfind(axisOrder, ax);   % find in C-order declaration
                if ~isempty(pos)
                    perm(k) = pos(1);
                else
                    % axis absent in this dataset -> trailing singleton slot
                    perm(k) = nextSingleton;
                    nextSingleton = nextSingleton + 1;
                end
            end
        end
    end
end
