classdef Array < handle
% ARRAY - backend-agnostic handle to an OME-Zarr v3 array.
%
% Drop-in replacement for ``ZarrArray`` whose bulk read/write are routed to
% the backend selected by ``io.zarr.Config`` (native ``zarrMex`` or
% ``zarr-python``). Results are byte-identical across backends, so an array
% written by one is read correctly by the other.
%
% **Metadata is always native.** ``create`` / ``createFromData`` write the
% zarr metadata through ``ZarrArray`` (the transpose codec, chunk grid, etc.),
% guaranteeing an identical on-disk structure regardless of the active
% backend; only the bulk pixel transfer honours ``io.zarr.Config``. Remote
% (HTTP/HTTPS) arrays always use the native backend (python remote access
% needs extra dependencies).
%
% **Examples**
%
%   .. code-block:: matlab
%
%      % open + read a region (uses the active backend)
%      arr   = io.zarr.Array('C:\data\vol.zarr3\0');
%      block = arr.read([1 513; 1 513; 5 6]);    % [start, end+1) per dim
%
%      % create and write
%      arr = io.zarr.Array.create('C:\tmp\a.zarr3', [256 256 16], 'uint16', ...
%                                 'chunkShape', [256 256 4]);
%      arr.write(uint16(zeros(256, 256, 16)));
%
%      % create from data in one step
%      io.zarr.Array.createFromData('C:\tmp\b.zarr3', uint8(rand(64,64,8)*255));

    properties (SetAccess = private)
        path
        % [char] array path (local folder or HTTP/HTTPS URL).
        backend
        % [char] 'native' or 'python' resolved at construction.
    end

    properties (Access = private)
        nativeArr        % ZarrArray handle (native backend)
        pyArr            % cached py zarr array handle (python backend)
        pyMode = ''      % mode the py handle was opened with ('r' / 'r+')
        pyMeta = []      % cached array metadata (shape/dtype) for the python backend
    end

    methods
        function obj = Array(path)
            % ARRAY - open an existing zarr array using the active backend.
            obj.path = char(path);
            if io.zarr.Array.isHttp(obj.path)
                obj.backend = 'native';   % remote -> native only
            else
                obj.backend = io.zarr.Config.library();
            end
            if strcmp(obj.backend, 'native')
                obj.nativeArr = ZarrArray(obj.path);
            end
        end

        function data = read(obj, bbox)
            % READ - read a region (or the whole array if bbox omitted/empty).
            %   bbox: [nDims x 2] [start, end+1) 1-based (declared/C-order).
            if nargin < 2; bbox = []; end
            if strcmp(obj.backend, 'native')
                if isempty(bbox); data = obj.nativeArr.read(); else; data = obj.nativeArr.read(bbox); end
            else
                data = io.zarr.PyBackend.readArray(obj.ensurePy(false), bbox, obj.ensureMeta());
            end
        end

        function write(obj, data, varargin)
            % WRITE - write data at origin or at a bbox; supports 'allowResize'.
            %   Mirrors ZarrArray.write: write(data) | write(data, bbox) |
            %   write(data, 'allowResize', true) | write(data, bbox, 'allowResize', true)
            if strcmp(obj.backend, 'native')
                obj.nativeArr.write(data, varargin{:});
            else
                [bbox, allowResize] = io.zarr.Array.parseWriteArgs(varargin{:});
                io.zarr.PyBackend.writeArray(obj.ensurePy(true), data, bbox, allowResize, obj.ensureMeta());
                if allowResize; obj.pyMeta = []; end   % shape may have changed
            end
        end

        function s = info(obj)
            % INFO - struct with shape / dataType / chunkShape / shardShape.
            if strcmp(obj.backend, 'native')
                s = obj.nativeArr.info();
            else
                s = io.zarr.PyBackend.infoArray(obj.ensurePy(false));
            end
        end

        function s = shape(obj)
            % SHAPE - array shape vector.
            inf = obj.info(); s = inf.shape;
        end

        function dt = dataType(obj)
            % DATATYPE - zarr data type string.
            inf = obj.info(); dt = inf.dataType;
        end

        function resize(obj, newShape)
            % RESIZE - resize the array (extends/shrinks per zarr semantics).
            if strcmp(obj.backend, 'native')
                obj.nativeArr.resize(newShape);
            else
                io.zarr.PyBackend.resizeArray(obj.ensurePy(true), newShape);
                obj.pyMeta = [];   % invalidate cached shape
            end
        end
    end

    methods (Access = private)
        function a = ensurePy(obj, needWrite)
            % ENSUREPY - lazily open & cache the py handle with a sufficient mode.
            if needWrite; wantMode = 'r+'; else; wantMode = 'r'; end
            if isempty(obj.pyArr) || (needWrite && ~strcmp(obj.pyMode, 'r+'))
                obj.pyArr  = io.zarr.PyBackend.openArray(obj.path, wantMode);
                obj.pyMode = wantMode;
            end
            a = obj.pyArr;
        end

        function m = ensureMeta(obj)
            % ENSUREMETA - fetch & cache the array's shape/dtype once (python backend).
            if isempty(obj.pyMeta)
                obj.pyMeta = io.zarr.PyBackend.arrayMeta(obj.ensurePy(false));
            end
            m = obj.pyMeta;
        end
    end

    methods (Static)
        function arr = create(path, shape, dataType, varargin)
            % CREATE - create a new array (native metadata) and return a facade handle.
            %   Same arguments as ZarrArray.create. Bulk writes go through the
            %   active backend.
            ZarrArray.create(char(path), shape, dataType, varargin{:});
            arr = io.zarr.Array(char(path));
        end

        function arr = createFromData(path, data, varargin)
            % CREATEFROMDATA - create an array sized/typed from data and write it.
            if io.zarr.Config.isPython() && ~io.zarr.Array.isHttp(path)
                ZarrArray.create(char(path), size(data), ...
                    io.zarr.Array.zarrTypeFromClass(class(data)), varargin{:});
                arr = io.zarr.Array(char(path));
                arr.write(data);
            else
                ZarrArray.createFromData(char(path), data, varargin{:});
                arr = io.zarr.Array(char(path));
            end
        end
    end

    methods (Static, Access = private)
        function tf = isHttp(path)
            tf = startsWith(char(path), 'http://') || startsWith(char(path), 'https://');
        end

        function [bbox, allowResize] = parseWriteArgs(varargin)
            % PARSEWRITEARGS - split optional bbox (nx2) and 'allowResize' name-value.
            bbox = [];
            if ~isempty(varargin) && isnumeric(varargin{1}) && size(varargin{1}, 2) == 2
                bbox = varargin{1};
                rest = varargin(2:end);
            else
                rest = varargin;
            end
            allowResize = false;
            for k = 1:2:numel(rest) - 1
                if strcmpi(rest{k}, 'allowResize'); allowResize = logical(rest{k + 1}); end
            end
        end

        function zarrType = zarrTypeFromClass(matlabClass)
            % ZARRTYPEFROMCLASS - MATLAB class -> zarr data type string.
            switch matlabClass
                case 'logical'; zarrType = 'bool';
                case 'single';  zarrType = 'float32';
                case 'double';  zarrType = 'float64';
                case {'uint8', 'uint16', 'uint32', 'uint64', 'int8', 'int16', 'int32', 'int64'}
                    zarrType = matlabClass;
                otherwise
                    error('io:zarr:Array:dtype', 'Unsupported data type: %s', matlabClass);
            end
        end
    end
end
