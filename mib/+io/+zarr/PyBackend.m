classdef PyBackend
% PYBACKEND - read/write Zarr v3 arrays through the Python ``zarr`` library.
%
% Implements the bulk-I/O half of the ``io.zarr`` facade for the
% ``'python'`` backend (``io.zarr.Config.library() == 'python'``), producing
% results **byte-identical** to the native ``zarrMex`` backend so the two are
% fully interchangeable on disk.
%
% **Axis / byte convention (matches zarrMex).** ``zarrMex`` returns an array
% whose layout is the reverse of the zarr ``shape`` declaration (MATLAB
% Fortran order), and applies any declared codecs (e.g. the transpose codec
% the native writer adds). The same result is obtained from ``zarr-python`` by
% taking the decoded, C-contiguous numpy region's raw bytes and computing::
%
%     out = permute(reshape(typecast(bytes, mtype), fliplr(shape)), nd:-1:1)
%
% Writing is the exact inverse: the MATLAB array (zarrMex convention) is
% F-flattened after ``permute(data, nd:-1:1)`` to obtain the C-order bytes of
% the logical region, rebuilt as a numpy array of the declared (C-order)
% region shape, and assigned into the array.
%
% **Performance.** Python runs out-of-process, so each ``py.*`` call is an IPC
% round-trip and large arrays cross a process boundary. Two things keep this
% fast (≈1.3× native rather than ≈9×):
%
%   1. The whole slice → contiguify → ``tobytes`` (read) or
%      ``frombuffer`` → reshape → assign (write) is done in a **single**
%      ``pyrun`` call (one round-trip), with the slice tuple built inside
%      Python from numeric start/end vectors.
%   2. The payload crosses the boundary **once** and is converted with
%      ``uint8(py.bytes)`` directly (≈4× faster than routing back through
%      ``numpy.frombuffer``).
%
% ``io.zarr.Array`` opens/caches the ``py`` handle and the array metadata
% (shape/dtype) so neither is re-queried per read. Metadata *creation* stays
% native (see ``io.zarr.Array.create`` / ``io.zarr.Group``).

    methods (Static)
        function ensureLoaded()
            % ENSURELOADED - start Python (configured interpreter) and import modules.
            % Idempotent; safe to call before every operation. Throws a clear,
            % actionable error if Python cannot be used.
            persistent ready
            if ~isempty(ready) && ready; return; end

            % A Terminated OutOfProcess interpreter cannot be restarted within the
            % same MATLAB session (happens e.g. after 'clear classes' while live
            % py objects existed). Detect it up front with a helpful message.
            if strcmp(string(pyenv().Status), "Terminated")
                error('io:zarr:PyBackend:pythonTerminated', ...
                    ['The Python interpreter is terminated and cannot be restarted in this MATLAB session.\n' ...
                     'Restart MATLAB to use the ''python'' Zarr backend, or set\n' ...
                     'Preferences -> Input/output -> Zarr library to ''native'' (zarrMex).']);
            end

            try
                pyPath = io.zarr.Config.pythonPath();
                if ~isempty(pyPath)
                    try
                        pyenv('Version', pyPath, 'ExecutionMode', 'OutOfProcess');
                    catch err
                        % already loaded -> keep the running interpreter
                        if ~strcmp(err.identifier, 'MATLAB:Pyenv:PythonLoaded'); rethrow(err); end
                    end
                end
                py.importlib.import_module('zarr');
                py.importlib.import_module('numpy');
            catch err
                error('io:zarr:PyBackend:pythonUnavailable', ...
                    ['Could not start the Python Zarr backend:\n  %s\n' ...
                     'Check that preferences.ExternalDirs.PythonInstallationPath points to a Python with the\n' ...
                     '"zarr" (v3) and "numpy" packages installed. If Python was terminated, restart MATLAB.\n' ...
                     'Alternatively set Preferences -> Input/output -> Zarr library to ''native'' (zarrMex).'], ...
                    err.message);
            end
            ready = true;
        end

        function pyArr = openArray(path, mode)
            % OPENARRAY - open a zarr array, returning the py handle.
            %   mode: 'r' (read only) or 'r+' (read/write existing).
            if nargin < 2 || isempty(mode); mode = 'r'; end
            io.zarr.PyBackend.ensureLoaded();
            z = py.importlib.import_module('zarr');
            pyArr = z.open(char(path), pyargs('mode', char(mode)));
        end

        function meta = arrayMeta(pyArr)
            % ARRAYMETA - one-time metadata for an open py array (cached by io.zarr.Array).
            meta.shape = io.zarr.PyBackend.tupleToVec(pyArr.shape);
            zType = char(pyArr.dtype.name);
            [meta.mtype, meta.isBool] = io.zarr.PyBackend.numpyToMatlabType(zType);
            meta.dataType   = zType;                                   % zarr type name
            meta.chunkShape = io.zarr.PyBackend.tupleToVec(pyArr.chunks);
        end

        function data = readArray(pyArr, bbox, meta)
            % READARRAY - read a region (or all) from an open py zarr array.
            %   bbox: [nDims x 2] [start, end+1) 1-based (declared/C-order), or [].
            %   meta: optional struct from arrayMeta (avoids re-querying shape/dtype).
            if nargin < 3 || isempty(meta); meta = io.zarr.PyBackend.arrayMeta(pyArr); end
            declShape = meta.shape;
            nd = numel(declShape);

            if nargin < 2 || isempty(bbox)
                starts = zeros(1, nd);
                ends   = declShape;
            else
                starts = zeros(1, nd);
                ends   = declShape;
                m = min(nd, size(bbox, 1));
                starts(1:m) = bbox(1:m, 1)' - 1;     % 0-based inclusive
                ends(1:m)   = bbox(1:m, 2)' - 1;     % 0-based exclusive (bbox is end+1)
            end
            outShape = ends - starts;

            % single round-trip: slice -> C-contiguous -> raw bytes
            b = pyrun(io.zarr.PyBackend.readCode(), 'mibOb', ...
                mibZa = pyArr, mibSa = int64(starts), mibEa = int64(ends));

            vals = typecast(uint8(b), meta.mtype);   % one boundary crossing + direct convert
            if nd >= 2
                data = permute(reshape(vals(:).', fliplr(outShape)), nd:-1:1);
            else
                data = reshape(vals(:), outShape(1), 1);
            end
            if meta.isBool; data = logical(data); end
        end

        function writeArray(pyArr, data, bbox, allowResize, meta)
            % WRITEARRAY - write a MATLAB array (zarrMex layout) into an open py array.
            %   bbox: [nDims x 2] [start, end+1) 1-based, or [] to write at origin.
            if nargin < 4 || isempty(allowResize); allowResize = false; end
            if nargin < 5 || isempty(meta); meta = io.zarr.PyBackend.arrayMeta(pyArr); end
            declShape = meta.shape;
            nd = numel(declShape);

            % normalise data to nd dimensions (restore dropped trailing singletons)
            dsz = ones(1, nd);
            s = size(data); dsz(1:numel(s)) = s;
            data = reshape(data, dsz);

            if nargin < 3 || isempty(bbox)
                bbox = [ones(nd, 1), dsz(:) + 1];
            end

            if allowResize
                bboxEnd = bbox(:, 2)' - 1;
                newShape = max(declShape, bboxEnd);
                if any(newShape > declShape)
                    io.zarr.PyBackend.resizeArray(pyArr, newShape);
                end
            end

            sliceShape = (bbox(:, 2) - bbox(:, 1))';   % declared-order region shape
            starts = bbox(:, 1)' - 1;                  % 0-based inclusive

            % C-order bytes of the logical region (inverse of read)
            dataR = permute(data, nd:-1:1);
            cls = class(data);
            switch cls
                case 'logical'; npDtype = 'bool';    raw = uint8(dataR(:).');
                case 'single';  npDtype = 'float32'; raw = dataR(:).';
                case 'double';  npDtype = 'float64'; raw = dataR(:).';
                otherwise;      npDtype = cls;        raw = dataR(:).';   % integer types
            end
            u8 = typecast(raw, 'uint8');

            % single round-trip: rebuild numpy region from bytes and assign
            pyrun(io.zarr.PyBackend.writeCode(), ...
                mibZa = pyArr, mibBuf = u8, mibDt = npDtype, ...
                mibShp = int64(sliceShape), mibSa = int64(starts));
        end

        function resizeArray(pyArr, newShape)
            % RESIZEARRAY - resize an open py zarr array (opened 'r+').
            pyArr.resize(py.tuple(num2cell(int64(newShape(:)'))));
        end

        function s = infoArray(pyArr)
            % INFOARRAY - struct mirroring ZarrArray.info (shape/dataType/chunkShape).
            m = io.zarr.PyBackend.arrayMeta(pyArr);
            s.shape      = m.shape;
            s.chunkShape = m.chunkShape;
            s.shardShape = m.chunkShape;                 % best-effort (no separate shard query)
            s.dataType   = m.dataType;
        end
    end

    methods (Static, Access = private)
        function code = readCode()
            % READCODE - cached Python for: slice -> C-contiguous -> raw bytes.
            persistent c
            if isempty(c)
                c = sprintf(['import numpy as _mibnp\n' ...
                    'mibSl = tuple(slice(int(mibSa[i]), int(mibEa[i])) for i in range(len(mibSa)))\n' ...
                    'mibOb = _mibnp.ascontiguousarray(mibZa[mibSl]).tobytes()']);
            end
            code = c;
        end

        function code = writeCode()
            % WRITECODE - cached Python for: bytes -> numpy region -> assign into array.
            persistent c
            if isempty(c)
                c = sprintf(['import numpy as _mibnp\n' ...
                    'mibReg = _mibnp.frombuffer(bytes(mibBuf), dtype=mibDt).reshape([int(v) for v in mibShp])\n' ...
                    'mibSl = tuple(slice(int(mibSa[i]), int(mibSa[i] + mibShp[i])) for i in range(len(mibSa)))\n' ...
                    'mibZa[mibSl] = mibReg']);
            end
            code = c;
        end

        function v = tupleToVec(pyTuple)
            % TUPLETOVEC - convert a python int tuple to a numeric row vector.
            v = cellfun(@double, cell(pyTuple));
            v = v(:)';
        end

        function [mtype, isBool] = numpyToMatlabType(name)
            % NUMPYTOMATLABTYPE - map numpy dtype name to MATLAB typecast class.
            isBool = false;
            switch name
                case 'bool';    mtype = 'uint8'; isBool = true;   % 1 byte/element, cast to logical after
                case 'float32'; mtype = 'single';
                case 'float64'; mtype = 'double';
                case {'uint8', 'uint16', 'uint32', 'uint64', 'int8', 'int16', 'int32', 'int64'}
                    mtype = name;
                otherwise
                    error('io:zarr:PyBackend:dtype', 'Unsupported numpy dtype: %s', name);
            end
        end
    end
end
