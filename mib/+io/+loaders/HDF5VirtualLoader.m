classdef HDF5VirtualLoader < handle
    % classdef HDF5VirtualLoader < handle
    % On-demand slice reader for MIB3 HDF5 virtual datasets.
    %
    % Wraps a single HDF5 file and its internal dataset path.
    % The full axis order is resolved from the HDF5 JSON attribute on
    % the first readRegion call and cached — h5info() is never called more
    % than once per file per session.
    %
    % Any axis order is supported (e.g. 'yxzct', 'yxczt', 'zyxct', etc.).
    % readRegion always returns data in MIB3 order [y, x, z, c, t].
    %
    % Unlike the batch loaders in +io/+loaders/ this class does NOT
    % implement BaseImageLoader — it is stateful and designed for repeated
    % sub-region reads rather than single full-dataset loads.
    %
    % Usage example:
    % @code
    % loader = io.loaders.HDF5VirtualLoader('/data/stack.h5', '/MIB/images');
    % block  = loader.readRegion([1 512], [1 512], 1, 10, 3, [1 1], 'uint16');
    % % block is [512, 512, 10, 3, 1] in [y,x,z,c,t] order
    % @endcode

    properties (SetAccess = private)
        filename
        % [char] full path to the HDF5 file
        datasetPath
        % [char] internal HDF5 dataset path (Virtual.seriesName{fileIdx})
        axisOrder
        % [char] MATLAB dimension order resolved from the HDF5 JSON attribute,
        % e.g. 'yxzct' means h5read returns [y, x, z, c, t].
        % Empty ([]) until resolveAxisOrder() is called on the first readRegion.
        toMIB3perm
        % [1 x nDims] permutation vector: permute(raw, toMIB3perm) gives [y,x,z,c,t].
        % Precomputed once alongside axisOrder.
    end

    methods
        function obj = HDF5VirtualLoader(filename, datasetPath)
            % obj = HDF5VirtualLoader(filename, datasetPath)
            % Constructor
            %
            % Parameters:
            % filename    : [char] full path to the HDF5 file
            % datasetPath : [char] internal HDF5 dataset path

            obj.filename    = filename;
            obj.datasetPath = datasetPath;
            obj.axisOrder   = [];
            obj.toMIB3perm  = [];
        end

        function block = readRegion(obj, Ylim, Xlim, z1In, zCount, nColors, Tlim, dataClass)
            % block = readRegion(obj, Ylim, Xlim, z1In, zCount, nColors, Tlim, dataClass)
            % Read a contiguous z-block from the HDF5 file.
            %
            % The axis order is resolved and cached on the first call.
            % Always returns data in MIB3 order [y, x, z, c, t].
            %
            % Parameters:
            % Ylim      : [ymin ymax] pixel range (1-based, inclusive)
            % Xlim      : [xmin xmax] pixel range (1-based, inclusive)
            % z1In      : [numeric] first z-slice index within this file (1-based)
            % zCount    : [numeric] number of z-slices to read
            % nColors   : [numeric] total number of color channels in the dataset
            % Tlim      : [tmin tmax] time-point range (1-based, inclusive)
            % dataClass : [char] output class, e.g. 'uint8' or 'uint16'
            %
            % Return values:
            % block : [nY, nX, zCount, nColors, nT] array in [y,x,z,c,t] order

            if isempty(obj.axisOrder)
                obj.resolveAxisOrder();
            end

            % Map each axis to its h5read start and count values
            nDims = numel(obj.axisOrder);
            axisRanges = struct( ...
                'y', {{Ylim(1), Ylim(2)-Ylim(1)+1}}, ...
                'x', {{Xlim(1), Xlim(2)-Xlim(1)+1}}, ...
                'z', {{z1In,    zCount}}, ...
                'c', {{1,       nColors}}, ...
                't', {{Tlim(1), Tlim(2)-Tlim(1)+1}});

            startVec = zeros(1, nDims);
            countVec = zeros(1, nDims);
            for dim = 1:nDims
                ax = obj.axisOrder(dim);
                startVec(dim) = axisRanges.(ax){1};
                countVec(dim) = axisRanges.(ax){2};
            end

            raw   = h5read(obj.filename, obj.datasetPath, startVec, countVec);
            block = permute(raw, obj.toMIB3perm);
        end
    end

    methods (Access = private)
        function resolveAxisOrder(obj)
            % resolveAxisOrder(obj)
            % Read h5info once to determine the full axis order.
            % Precomputes obj.toMIB3perm so readRegion never calls h5info again.
            %
            % The JSON attribute stores axes outermost-first (HDF5/C order);
            % flip() converts to MATLAB innermost-first (column-major) order.
            % Example: HDF5 stores (t,c,z,x,y) -> axisOrder = 'yxzct'

            try
                info   = h5info(obj.filename);
                parsed = jsondecode(info.Datasets.Attributes.Value);
                obj.axisOrder = lower(flip(strjoin({parsed.axes.key}, '')));
            catch
                obj.axisOrder = 'yxzct';    % fallback: MIB3 native order
            end

            if isempty(obj.axisOrder)
                obj.axisOrder = 'yxzct';
            end

            % Precompute permutation: native axis order -> MIB3 [y, x, z, c, t]
            % toMIB3perm(k) = position of the k-th MIB3 axis in the native order.
            % e.g. if axisOrder='yxczt': z is at position 4, c at 3
            %   -> toMIB3perm = [1, 2, 4, 3, 5]
            %   -> permute(raw_yxczt, [1,2,4,3,5]) gives [y,x,z,c,t] ✓
            mib3axes = 'yxzct';
            obj.toMIB3perm = zeros(1, numel(mib3axes));
            for k = 1:numel(mib3axes)
                pos = strfind(obj.axisOrder, mib3axes(k));
                if isempty(pos)
                    error('io:HDF5VirtualLoader:missingAxis', ...
                        'HDF5VirtualLoader: axis "%s" not found in "%s" (%s)', ...
                        mib3axes(k), obj.axisOrder, obj.filename);
                end
                obj.toMIB3perm(k) = pos;
            end
        end
    end
end
