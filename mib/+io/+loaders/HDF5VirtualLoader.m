classdef HDF5VirtualLoader < handle
% HDF5VIRTUALLOADER - On-demand slice reader for MIB3 HDF5 virtual datasets.
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
% **Relationship to HDF5VirtualSetupLoader**
%
% These two classes serve different phases of the virtual dataset lifecycle
% and should not be confused:
%
% HDF5VirtualSetupLoader  — runs ONCE when the user opens a file.
% Phase   : dataset initialisation (MibModel.loadImages)
% Job     : parse metadata, build the Virtual struct, return H5 paths.
% Reads pixels? No.
% Lifetime: discarded immediately after open; implements BaseImageLoader.
% Created by: LoaderFactory
%
% HDF5VirtualLoader  — runs on EVERY slice request during the session.
% Phase   : on-demand pixel reading (MibVirtualImage.getDataVirt)
% Job     : call h5read for the requested sub-region; cache axis order.
% Reads pixels? Yes — one h5read call per z-group per getDataVirt call.
% Lifetime: cached in MibVirtualImage.loaders{} for the session; does
% NOT implement BaseImageLoader.
% Created by: MibVirtualImage.getOrCreateLoader (lazily, per file)
%
%
% Usage example:
%
% .. code-block:: matlab
%
%   loader = io.loaders.HDF5VirtualLoader('/data/stack.h5', '/MIB/images');
%   block  = loader.readRegion([1 512], [1 512], 1, 10, 3, [1 1], 'uint16');
%   % block is [512, 512, 10, 3, 1] in [y,x,z,c,t] order

    properties (SetAccess = private)
        filename
        % [char] full path to the HDF5 file
        datasetPath
        % [char] internal HDF5 dataset path (Virtual.seriesName{fileIdx})
        transMatrix
        % [1 x 5] permutation from SelectHDFSeries dialog (may be [] or NaN).
        % transMatrix(k) = native HDF5 dimension position for MIB axis k
        % where MIB axes are ordered [y, x, z, c, t].
        % Passed in from Virtual.transMatrix{fileIdx} by getOrCreateLoader.
        % When non-empty and not NaN, takes priority over axis-tag parsing.
        axisOrder
        % [char] MATLAB dimension order resolved from transMatrix or the HDF5
        % JSON/axistags attribute, e.g. 'yxczt' means h5read returns
        % [y, x, c, z, t] in native order.
        % Empty ([]) until resolveAxisOrder() is called on the first readRegion.
        toMIB3perm
        % [1 x 5] permutation vector: permute(raw, toMIB3perm) gives [y,x,z,c,t].
        % Entries for axes absent from the native HDF5 dims are assigned
        % trailing singleton positions so MATLAB auto-extends correctly.
        % Precomputed once alongside axisOrder.
    end

    methods
        function obj = HDF5VirtualLoader(filename, datasetPath, transMatrix)
            % HDF5VIRTUALLOADER - obj = HDF5VirtualLoader(filename, datasetPath, transMatrix).
            %
            % Syntax:
            %   function obj = HDF5VirtualLoader(filename, datasetPath, transMatrix)
            %
            % Constructor
            %
            % Input Arguments:
            %   - **filename** — [char] full path to the HDF5 file
            %   - **datasetPath** — [char] internal HDF5 dataset path
            %   - **transMatrix** — *(optional)* [1 x 5] permutation from
            %     SelectHDFSeries dialog; [] or NaN = not available
            %

            obj.filename    = filename;
            obj.datasetPath = datasetPath;
            obj.axisOrder   = [];
            obj.toMIB3perm  = [];
            if nargin >= 3 && ~isempty(transMatrix) && isnumeric(transMatrix) && ~isnan(transMatrix(1))
                obj.transMatrix = transMatrix;
            else
                obj.transMatrix = [];
            end
        end

        function block = readRegion(obj, Ylim, Xlim, z1In, zCount, nColors, Tlim, dataClass)
            % READREGION - block = readRegion(obj, Ylim, Xlim, z1In, zCount, nColors, Tlim, dataClass).
            %
            % Syntax:
            %   function block = readRegion(obj, Ylim, Xlim, z1In, zCount, nColors, Tlim, dataClass)
            %
            % Read a contiguous z-block from the HDF5 file.
            %
            % The axis order is resolved and cached on the first call.
            % Always returns data in MIB3 order [y, x, z, c, t].
            %
            % Input Arguments:
            %   - **Ylim** — [ymin ymax] pixel range (1-based, inclusive)
            %   - **Xlim** — [xmin xmax] pixel range (1-based, inclusive)
            %   - **z1In** — [numeric] first z-slice index within this file (1-based)
            %   - **zCount** — [numeric] number of z-slices to read
            %   - **nColors** — [numeric] total number of color channels in the dataset
            %   - **Tlim** — [tmin tmax] time-point range (1-based, inclusive)
            %   - **dataClass** — [char] output class, e.g. 'uint8' or 'uint16'
            %
            % Output Arguments:
            %   - **block** — [nY, nX, zCount, nColors, nT] array in [y,x,z,c,t] order
            %

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
            % RESOLVEAXISORDER - resolveAxisOrder(obj).
            %
            % Syntax:
            %   function resolveAxisOrder(obj)
            %
            % Resolve the native HDF5 axis order and precompute toMIB3perm.
            % Called once on the first readRegion; results are cached.
            %
            % Priority order:
            % 1. transMatrix from SelectHDFSeries dialog (most reliable for
            % bare HDF5 files where axis order was set by the user)
            % 2. 'axistags' JSON attribute on the dataset (Ilastik style)
            % 3. JSON attribute on the HDF5 root (MIB/OMEZARR style)
            % 4. Fallback: first nDims characters of 'yxzct', where nDims is
            % the actual rank of the dataset from h5info.
            %
            % For axes present in the native HDF5:
            % toMIB3perm(k) = native dimension index for MIB axis k
            % For axes absent from the native HDF5 (singletons not stored):
            % toMIB3perm(k) = nDims + offset  (MATLAB auto-extends to singleton)
            % These extra dimensions evaluate to size 1 after permute().
            %
            % Example: native 'yxczt' (5 dims, Y=372,X=521,C=75,Z=1,T=1)
            % transMatrix = [1,2,4,3,5]
            % axisOrder   = 'yxczt'
            % toMIB3perm  = [1,2,4,3,5]
            % permute(raw_yxczt,[1,2,4,3,5]) [y,x,z,c,t] ✓
            %
            % Example: native 'yxz' (3 dims, no c/t stored)
            % axisOrder  = 'yxz'
            % toMIB3perm = [1,2,3,4,5]   (c,t get auto-singleton positions 4,5)
            % permute(raw_3D,[1,2,3,4,5]) [y,x,z,1,1] ✓

            mib3axes = 'yxzct';

            % **get actual HDF5 dataset rank**
            nDims = 5;  % conservative fallback
            try
                dsInfo = h5info(obj.filename, obj.datasetPath);
                nDims  = numel(dsInfo.Dataspace.Size);
            catch
            end

            % **Case 1: transMatrix provided from SelectHDFSeries**
            if ~isempty(obj.transMatrix)
                % transMatrix(k) = native dim position for MIB axis k.
                % Positions > nDims indicate axes not stored in the HDF5 file.
                axisArr     = blanks(nDims);
                obj.toMIB3perm = zeros(1, 5);
                nextMissing = nDims + 1;
                for k = 1:5
                    pos = obj.transMatrix(k);
                    if pos <= nDims
                        axisArr(pos)       = mib3axes(k);
                        obj.toMIB3perm(k)  = pos;
                    else
                        % Axis not stored — assign a trailing singleton slot
                        obj.toMIB3perm(k) = nextMissing;
                        nextMissing        = nextMissing + 1;
                    end
                end
                obj.axisOrder = axisArr;
                return;
            end

            % **Case 2: 'axistags' attribute on the dataset (Ilastik)**
            try
                attrNames = {dsInfo.Attributes.Name};
                attrIdx   = find(strcmp(attrNames, 'axistags'), 1);
                if ~isempty(attrIdx)
                    val = dsInfo.Attributes(attrIdx).Value;
                    if iscell(val); val = val{1}; end
                    jsonStruct    = jsondecode(val);
                    obj.axisOrder = lower(fliplr(strjoin({jsonStruct.axes.key}, '')));
                end
            catch
            end

            % **Case 3: JSON attribute on the HDF5 root (MIB/OMEZARR)**
            if isempty(obj.axisOrder)
                try
                    rootInfo      = h5info(obj.filename);
                    parsed        = jsondecode(rootInfo.Datasets.Attributes.Value);
                    obj.axisOrder = lower(flip(strjoin({parsed.axes.key}, '')));
                catch
                end
            end

            % **Case 4: fallback — assume dims map in order y,x,z,c,t**
            if isempty(obj.axisOrder)
                obj.axisOrder = mib3axes(1:min(nDims, 5));
            end

            % **Precompute toMIB3perm**
            % For axes present in axisOrder: use their 1-based position.
            % For axes absent (not stored in HDF5): assign trailing singleton slots
            % so that permute() auto-extends correctly.
            obj.toMIB3perm = zeros(1, 5);
            nextMissing    = numel(obj.axisOrder) + 1;
            for k = 1:5
                pos = strfind(obj.axisOrder, mib3axes(k));
                if ~isempty(pos)
                    obj.toMIB3perm(k) = pos(1);
                else
                    obj.toMIB3perm(k) = nextMissing;
                    nextMissing        = nextMissing + 1;
                end
            end
        end
    end
end
