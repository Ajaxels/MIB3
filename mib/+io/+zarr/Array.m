classdef Array < handle
% ARRAY - backend-agnostic handle to an OME-Zarr v2 or v3 array.
%
% Drop-in replacement for ``ZarrArray`` whose bulk read/write are routed to
% the backend selected by ``io.zarr.Config`` (native ``zarrMex`` or
% ``zarr-python``). Results are byte-identical across backends, so an array
% written by one is read correctly by the other.
%
% **Format is detected, never declared.** Opening an existing array works for
% zarr v2 (``.zarray``) and v3 (``zarr.json``) alike - neither the caller nor
% this class has to know which it is. Only ``create`` needs to choose, and it
% defaults to v3; pass ``'zarrFormat', 2`` for a v2 array.
%
% **Metadata is always native.** ``create`` / ``createFromData`` write the
% zarr metadata through ``ZarrArray`` (the transpose codec or the v2 ``order``
% field, chunk grid, etc.), guaranteeing an identical on-disk structure
% regardless of the active backend; only the bulk pixel transfer honours
% ``io.zarr.Config``. Remote (HTTP/HTTPS) arrays always use the native
% backend, which reads both formats over HTTP range requests and needs no
% python dependencies at all.
%
% **One exception, decided per array.** The native engine refuses a codec
% configuration carrying a field it does not know, which some published stores
% have (see ``fallbackToPython``). Such an array falls back to zarr-python for
% its own reads and says so once; everything else in the session stays native.
%
% **Examples**
%
%   .. code-block:: matlab
%
%      % open + read a region (uses the active backend; v2 or v3)
%      arr   = io.zarr.Array('C:\data\vol.zarr3\0');
%      block = arr.read([1 513; 1 513; 5 6]);    % [start, end+1) per dim
%
%      % create and write
%      arr = io.zarr.Array.create('C:\tmp\a.zarr3', [256 256 16], 'uint16', ...
%                                 'chunkShape', [256 256 4]);
%      arr.write(uint16(zeros(256, 256, 16)));
%
%      % create a zarr v2 array instead
%      arr = io.zarr.Array.create('C:\tmp\a.zarr2', [256 256 16], 'uint16', ...
%                                 'chunkShape', [256 256 4], 'zarrFormat', 2);
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
                try
                    if isempty(bbox); data = obj.nativeArr.read(); else; data = obj.nativeArr.read(bbox); end
                    return;
                catch nativeError
                    obj.fallbackToPython(nativeError);   % rethrows unless it switched
                end
            end
            data = io.zarr.PyBackend.readArray(obj.ensurePy(false), bbox, obj.ensureMeta());
        end

        function write(obj, data, varargin)
            % WRITE - write data at origin or at a bbox; supports 'allowResize'.
            %   Mirrors ZarrArray.write: write(data) | write(data, bbox) |
            %   write(data, 'allowResize', true) | write(data, bbox, 'allowResize', true)
            if strcmp(obj.backend, 'native')
                try
                    obj.nativeArr.write(data, varargin{:});
                    return;
                catch nativeError
                    obj.fallbackToPython(nativeError);
                end
            end
            [bbox, allowResize] = io.zarr.Array.parseWriteArgs(varargin{:});
            io.zarr.PyBackend.writeArray(obj.ensurePy(true), data, bbox, allowResize, obj.ensureMeta());
            if allowResize; obj.pyMeta = []; end   % shape may have changed
        end

        function s = info(obj)
            % INFO - struct with shape / dataType / chunkShape / shardShape.
            if strcmp(obj.backend, 'native')
                try
                    s = obj.nativeArr.info();
                    return;
                catch nativeError
                    obj.fallbackToPython(nativeError);
                end
            end
            s = io.zarr.PyBackend.infoArray(obj.ensurePy(false));
        end

        function s = shape(obj)
            % SHAPE - array shape vector.
            inf = obj.info(); s = inf.shape;
        end

        function dt = dataType(obj)
            % DATATYPE - zarr data type string.
            inf = obj.info(); dt = inf.dataType;
        end

        function format = zarrFormat(obj)
            % ZARRFORMAT - zarr format version of the array on disk (2 or 3).
            %   Reported by whichever backend is active; both read it from the
            %   metadata rather than from how the array was opened.
            inf = obj.info(); format = inf.zarrFormat;
        end

        function resize(obj, newShape)
            % RESIZE - resize the array (extends/shrinks per zarr semantics).
            if strcmp(obj.backend, 'native')
                try
                    obj.nativeArr.resize(newShape);
                    return;
                catch nativeError
                    obj.fallbackToPython(nativeError);
                end
            end
            io.zarr.PyBackend.resizeArray(obj.ensurePy(true), newShape);
            obj.pyMeta = [];   % invalidate cached shape
        end
    end

    methods (Access = private)
        function fallbackToPython(obj, nativeError)
            % FALLBACKTOPYTHON - switch this array to zarr-python, or fail clearly.
            %
            % The native engine parses codec configurations strictly and refuses
            % an array carrying a field it does not know, even an optional one
            % that changes nothing about the encoded bytes. Real stores do this:
            % OpenOrganelle's ``jrc_mus-liver-6`` declares
            % ``{"id": "zstd", "level": 6, "checksum": false}`` - numcodecs has
            % written the ``checksum`` flag since 0.13 - and the native open
            % fails with *unknown field `checksum`, expected `level`*, while
            % neighbouring datasets in the same bucket omit it and open fine.
            %
            % zarr-python accepts the same array, so the store is readable and
            % only the engine is wrong. Switching here rather than at open time
            % is deliberate: the metadata the loaders need is read from
            % ``.zarray`` as plain JSON and never fails, so this is the first
            % point at which the codec is known to be a problem.
            %
            % Anything other than a configuration complaint is rethrown
            % untouched - a 404 or a dropped connection would fail identically
            % under python, only slower and with a worse message.
            if ~io.zarr.Array.isCodecUnsupported(nativeError); rethrow(nativeError); end

            try
                io.zarr.PyBackend.ensureLoaded();
                io.zarr.PyBackend.ensureRemoteSupport(obj.path);   % no-op when local
            catch pythonError
                error('io:zarr:Array:codecUnsupported', ...
                    ['The native Zarr engine cannot open this array:\n  %s\n  %s\n\n' ...
                     'zarr-python reads arrays the native engine rejects, but it is not\n' ...
                     'usable here:\n  %s'], ...
                    obj.path, nativeError.message, pythonError.message);
            end

            obj.backend = 'python';
            io.zarr.Array.reportFallback(obj.path, nativeError);
        end


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
            %   Same arguments as ZarrArray.create, including ``'zarrFormat'``
            %   (2 or 3, default 3). Bulk writes go through the active backend.
            ZarrArray.create(char(path), shape, dataType, varargin{:});
            arr = io.zarr.Array(char(path));
        end

        function arr = createFromData(path, data, varargin)
            % CREATEFROMDATA - create an array sized/typed from data and write it.
            %   Accepts the same options as ``create``, ``'zarrFormat'`` included.
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

        function tf = isCodecUnsupported(nativeError)
            % ISCODECUNSUPPORTED - is this failure about the metadata, not the data?
            %
            % The native engine reports every store-level failure under the same
            % ``zarr:error`` identifier, so the message is the only thing that
            % separates "this array is encoded in a way I do not accept" from
            % "the network is down". Matching on the two words serde uses when
            % it refuses a codec configuration keeps genuine I/O failures on
            % their own path.
            tf = strcmp(nativeError.identifier, 'zarr:error') && ...
                 (contains(nativeError.message, 'unsupported', 'IgnoreCase', true) || ...
                  contains(nativeError.message, 'unknown field', 'IgnoreCase', true));
        end

        function reportFallback(arrayPath, nativeError)
            % REPORTFALLBACK - say once per array that the engine was switched.
            %
            % Worth saying at all because the array is now read through a
            % dependency the native engine does not need, so a later "python is
            % not configured" error on a dataset that opened yesterday has a
            % visible cause. Once per path: a pyramid opens one array per level
            % and would otherwise print the same line fifteen times.
            persistent reportedPaths
            if isempty(reportedPaths); reportedPaths = strings(0, 1); end
            if any(strcmp(reportedPaths, arrayPath)); return; end
            reportedPaths(end + 1, 1) = string(arrayPath);

            fprintf(['io.zarr.Array: the native engine refused "%s"\n' ...
                     '  %s\n' ...
                     '  reading it with zarr-python instead\n'], ...
                    arrayPath, nativeError.message);
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
