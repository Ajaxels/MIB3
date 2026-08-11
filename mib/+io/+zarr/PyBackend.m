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

            % A Terminated interpreter is only fatal for ExecutionMode
            % 'InProcess', which cannot be restarted within the same MATLAB
            % session. 'OutOfProcess' starts a fresh python process on the next
            % call, so "Terminated" there is the normal state after
            % terminate(pyenv) and recovers by itself - it must not be reported
            % as an error before it has even been tried. It stays unrecoverable
            % when the process crashed rather than exited cleanly, which is
            % indistinguishable up front, so that case is caught below instead.
            pyEnvironment  = pyenv();
            wasTerminated  = strcmp(string(pyEnvironment.Status), "Terminated");
            isInProcess    = strcmp(string(pyEnvironment.ExecutionMode), "InProcess");

            if wasTerminated && isInProcess
                error('io:zarr:PyBackend:pythonTerminated', ...
                    ['The Python interpreter is terminated and cannot be restarted in this MATLAB session\n' ...
                     '(ExecutionMode is ''InProcess'').\n' ...
                     'Restart MATLAB to use the ''python'' Zarr backend, or set\n' ...
                     'Preferences -> Input/output -> Zarr library to ''native'' (zarrMex).']);
            end

            try
                pyPath = io.zarr.Config.pythonPath();
                if ~isempty(pyPath)
                    try
                        pyenv('Version', pyPath, 'ExecutionMode', io.zarr.Config.executionMode());
                    catch err
                        % already loaded -> keep the running interpreter
                        if ~strcmp(err.identifier, 'MATLAB:Pyenv:PythonLoaded'); rethrow(err); end
                    end
                end
                py.importlib.import_module('zarr');
                py.importlib.import_module('numpy');
            catch err
                if wasTerminated
                    % the restart attempt above is the proof that this one is
                    % genuinely dead, e.g. after an out-of-process crash
                    error('io:zarr:PyBackend:pythonTerminated', ...
                        ['The Python interpreter was terminated and could not be restarted:\n  %s\n' ...
                         'Restart MATLAB to use the ''python'' Zarr backend, or set\n' ...
                         'Preferences -> Input/output -> Zarr library to ''native'' (zarrMex).'], ...
                        err.message);
                end
                error('io:zarr:PyBackend:pythonUnavailable', ...
                    ['Could not start the Python Zarr backend:\n  %s\n' ...
                     'Check that preferences.ExternalDirs.PythonInstallationPath points to a Python with the\n' ...
                     '"zarr" (v3) and "numpy" packages installed.\n' ...
                     'Alternatively set Preferences -> Input/output -> Zarr library to ''native'' (zarrMex).'], ...
                    err.message);
            end
            ready = true;
        end

        function [tf, diagnostic] = hasRemoteSupport()
            % HASREMOTESUPPORT - can the configured interpreter reach remote stores?
            %
            % ``zarr-python`` opens ``http(s)`` stores through fsspec's
            % ``HTTPFileSystem``, which imports ``aiohttp`` and ``requests``
            % lazily. Neither is a dependency of ``zarr`` itself, so an
            % environment that reads local v2 stores perfectly well can still
            % fail on the first remote chunk read.
            %
            % Never throws - it answers a question, and is meant for enabling or
            % disabling a control. Use ``ensureRemoteSupport`` when the answer
            % should stop the operation.
            %
            % ``diagnostic`` is what makes the two failure modes distinguishable:
            % a dead interpreter and a missing package both make ``tf`` false,
            % but only one of them is fixed by installing anything.
            %
            % A ``true`` result is cached for the session; ``false`` is not, so
            % installing the packages into the running interpreter's environment
            % is picked up without restarting MATLAB.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      tf = io.zarr.PyBackend.hasRemoteSupport()
            %      [tf, diagnostic] = io.zarr.PyBackend.hasRemoteSupport()
            %
            % Output Arguments:
            %   - **tf** - [logical] true when both packages are importable
            %   - **diagnostic** - [char] empty when ``tf`` is true, otherwise why
            %     the check failed

            persistent confirmedAvailable
            if ~isempty(confirmedAvailable) && confirmedAvailable
                tf = true; diagnostic = ''; return;
            end

            tf = false;
            try
                io.zarr.PyBackend.ensureLoaded();
            catch err
                diagnostic = err.message;   % python itself unusable
                return;
            end

            try
                tf = logical(pyrun(io.zarr.PyBackend.remoteProbeCode(), 'mibHasRemote'));
            catch err
                diagnostic = err.message;   % e.g. the interpreter died mid-session
                return;
            end

            if tf
                confirmedAvailable = true;
                diagnostic = '';
            else
                diagnostic = 'aiohttp and/or requests are not installed';
            end
        end

        function ensureRemoteSupport(path)
            % ENSUREREMOTESUPPORT - throw an actionable error for a remote path
            % when the python environment cannot fetch over the network.
            %
            % A no-op for local paths, so callers can invoke it unconditionally
            % next to ``ensureLoaded``. Calling it at open time turns a failure
            % that would otherwise appear on the first slice scrub into one
            % message at the moment the user asked for the dataset.
            %
            % Distinguishes a **dead interpreter** from **missing packages**:
            % both make the check fail, but telling someone to ``pip install``
            % when the Python process has actually exited sends them chasing the
            % wrong problem. An out-of-process interpreter is killed by
            % ``clear classes``, among other things.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      io.zarr.PyBackend.ensureRemoteSupport(path)
            %
            % Input Arguments:
            %   - **path** - [char|string] store path or URL about to be opened

            if nargin < 1 || isempty(path); return; end
            if ~io.RemoteStore.isRemote(path); return; end

            [isSupported, diagnostic] = io.zarr.PyBackend.hasRemoteSupport();
            if isSupported; return; end

            if io.zarr.PyBackend.looksLikeDeadInterpreter(diagnostic)
                error('io:zarr:PyBackend:pythonTerminated', ...
                    ['The Python interpreter is not running, so remote Zarr support could not be\n' ...
                     'checked:\n  %s\n\n' ...
                     'Restart MATLAB, or run "terminate(pyenv)" and open the dataset again.\n' ...
                     'Note that "clear classes" kills an out-of-process interpreter.'], ...
                    strtrim(diagnostic));
            end

            error('io:zarr:PyBackend:remoteDepsMissing', '%s', ...
                io.zarr.PyBackend.remoteDepsMessage());
        end

        function pyArr = openArray(path, mode)
            % OPENARRAY - open a zarr array, returning the py handle.
            %   mode: 'r' (read only) or 'r+' (read/write existing).
            if nargin < 2 || isempty(mode); mode = 'r'; end
            io.zarr.PyBackend.ensureLoaded();
            z = py.importlib.import_module('zarr');
            try
                pyArr = z.open(char(path), pyargs('mode', char(mode)));
            catch err
                % Translate the raw python ImportError into the same actionable
                % message ensureRemoteSupport produces, for any caller that
                % reached a remote store without checking first.
                io.zarr.PyBackend.raiseIfRemoteDepsMissing(err);
                rethrow(err);
            end
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
        function code = remoteProbeCode()
            % REMOTEPROBECODE - cached Python testing for the remote-access packages.
            % find_spec only looks the modules up on sys.path, so this stays cheap
            % and does not pull aiohttp's own imports into the interpreter.
            persistent c
            if isempty(c)
                c = sprintf(['import importlib.util as _mibutil\n' ...
                    'mibHasRemote = (_mibutil.find_spec("aiohttp") is not None) ' ...
                    'and (_mibutil.find_spec("requests") is not None)']);
            end
            code = c;
        end

        function tf = looksLikeDeadInterpreter(diagnostic)
            % LOOKSLIKEDEADINTERPRETER - does this failure mean python is not running?
            % Matches the wording MATLAB uses when an out-of-process interpreter
            % has exited or crashed, so that case is never reported as a missing
            % package.

            if isempty(diagnostic); tf = false; return; end
            tf = contains(diagnostic, 'terminated', 'IgnoreCase', true) || ...
                 contains(diagnostic, 'Python process', 'IgnoreCase', true) || ...
                 contains(diagnostic, 'could not be started', 'IgnoreCase', true) || ...
                 contains(diagnostic, 'pythonUnavailable', 'IgnoreCase', true);
        end

        function raiseIfRemoteDepsMissing(err)
            % RAISEIFREMOTEDEPSMISSING - convert a python import failure into the
            % actionable remote-dependency error, or return and let the caller
            % rethrow the original.

            message = err.message;
            looksLikeMissingRemoteDeps = ...
                contains(message, 'HTTPFileSystem requires') || ...
                contains(message, 's3fs') || ...
                (contains(message, 'ImportError') && contains(message, 'aiohttp'));

            if ~looksLikeMissingRemoteDeps; return; end

            error('io:zarr:PyBackend:remoteDepsMissing', '%s\n\nOriginal error:\n  %s', ...
                io.zarr.PyBackend.remoteDepsMessage(), strtrim(message));
        end

        function message = remoteDepsMessage()
            % REMOTEDEPSMESSAGE - the install instructions, naming the actual interpreter.

            interpreterPath = '';
            try
                interpreterPath = char(io.zarr.Config.pythonPath());
                if isempty(interpreterPath)
                    interpreterPath = char(pyenv().Executable);
                end
            catch
                % leave empty and print a generic form below
            end

            if isempty(interpreterPath)
                pipCommand   = 'python -m pip install aiohttp requests';
                condaCommand = 'conda install -c conda-forge aiohttp requests';
                whereClause  = 'the configured Python interpreter';
            else
                pipCommand = sprintf('"%s" -m pip install aiohttp requests', interpreterPath);
                environmentName = io.zarr.PyBackend.environmentNameOf(interpreterPath);
                if isempty(environmentName)
                    condaCommand = 'conda install -c conda-forge aiohttp requests';
                else
                    condaCommand = sprintf('conda install -n %s -c conda-forge aiohttp requests', ...
                        environmentName);
                end
                whereClause = interpreterPath;
            end

            message = sprintf([ ...
                'Reading a remote Zarr v2 store needs the "aiohttp" and "requests" Python packages,\n' ...
                'which zarr-python uses to fetch chunks over the network. They are missing from:\n' ...
                '  %s\n\n' ...
                'Install them with:\n' ...
                '  %s\n' ...
                'or, for a conda environment:\n' ...
                '  %s\n\n' ...
                'The interpreter is set in Preferences -> External directories -> Python installation path.\n' ...
                'Local Zarr v2 stores are unaffected, and remote Zarr v3 stores need no Python at all\n' ...
                '(they are read by the native zarrMex engine using HTTP range requests).'], ...
                whereClause, pipCommand, condaCommand);
        end

        function environmentName = environmentNameOf(interpreterPath)
            % ENVIRONMENTNAMEOF - conda environment name from a python executable path.
            % "...\envs\sam4mib\python.exe" -> "sam4mib". Empty when the layout
            % does not look like a conda environment.

            environmentName = '';
            try
                [interpreterDir, ~] = fileparts(interpreterPath);
                [parentDir, candidateName] = fileparts(interpreterDir);
                [~, parentName] = fileparts(parentDir);
                if strcmpi(parentName, 'envs')
                    environmentName = candidateName;
                end
            catch
                environmentName = '';
            end
        end

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
