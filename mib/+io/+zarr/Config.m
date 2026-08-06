classdef Config < handle
% CONFIG - process-wide selection of the active OME-Zarr v3 backend.
%
% Holds two module-level settings shared by the ``io.zarr`` facade
% (``io.zarr.Array`` / ``io.zarr.Group``):
%
%   * **library** - which backend performs bulk pixel I/O:
%
%     - ``'native'`` - the bundled ``zarrMex`` engine (``ZarrArray`` /
%       ``ZarrGroup``). Default. No external dependency.
%     - ``'python'`` - the ``zarr-python`` (v3) library via ``pyrun``/numpy.
%
%   * **pythonPath** - the Python interpreter used by the python backend
%     (normally ``preferences.ExternalDirs.PythonInstallationPath``).
%
%   * **smoothing** - when ``true`` (default), the BigData label pyramid smooths
%     boundaries when an edit made at a coarse (zoomed-out) level is propagated
%     **up** into finer levels, instead of a blocky nearest-neighbour upsample
%     (see ``core.MibBigDataLabels.resizeBlockSmooth``).
%
% ``models.MibModel.initializePreferences`` pushes these from
% ``preferences.IO.Zarr.Library`` / ``preferences.IO.Zarr.Smoothing`` /
% ``preferences.ExternalDirs.PythonInstallationPath`` at start-up; the
% Preferences dialog should call ``setLibrary`` / ``setSmoothing`` /
% ``setPythonPath`` again whenever the user changes them.
%
% Metadata operations (creating arrays/groups, attributes, resize) are always
% performed natively for an identical on-disk structure; only bulk read/write
% honour the selected library - so a ``'python'`` reader is fully independent
% of ``zarrMex`` on the read path.
%
% **Examples**
%
%   .. code-block:: matlab
%
%      io.zarr.Config.setLibrary('python');           % switch backend
%      io.zarr.Config.setPythonPath('D:\Python\envs\sam4mib\python.exe');
%      tf  = io.zarr.Config.isPython();               % true
%      lib = io.zarr.Config.library();                % 'python'
%      io.zarr.Config.setLibrary('native');           % back to zarrMex
%
%      io.zarr.Config.setSmoothing(false);            % blocky (nearest) up-propagation
%      sm = io.zarr.Config.smoothing();               % false
%      io.zarr.Config.setSmoothing(true);             % smooth coarse->fine edits (default)

    methods (Static)
        function out = library(name)
            % LIBRARY - get (no args) or set (with a name) the active backend.
            %   Returns the canonical name ``'native'`` or ``'python'``.
            persistent lib
            if isempty(lib); lib = 'native'; end
            if nargin >= 1 && ~isempty(name)
                lib = io.zarr.Config.normalize(name);
            end
            out = lib;
        end

        function setLibrary(name)
            % SETLIBRARY - set the active backend ('native'|'python', aliases accepted).
            io.zarr.Config.library(name);
        end

        function tf = isPython()
            % ISPYTHON - true when the python backend is active.
            tf = strcmp(io.zarr.Config.library(), 'python');
        end

        function out = pythonPath(p)
            % PYTHONPATH - get (no args) or set the python interpreter path.
            persistent pp
            if isempty(pp); pp = ''; end
            if nargin >= 1
                if isempty(p); pp = ''; else; pp = char(p); end
            end
            out = pp;
        end

        function setPythonPath(p)
            % SETPYTHONPATH - set the python interpreter used by the python backend.
            io.zarr.Config.pythonPath(p);
        end

        function out = executionMode(m)
            % EXECUTIONMODE - get (no args) or set the pyenv execution mode.
            % Mirrors ExternalDirs.PythonExecutionMode; defaults to
            % 'OutOfProcess' so the python backend isolates torch's CUDA context
            % from MATLAB (see io.zarr.PyBackend.ensureLoaded / segmentationSAM2).
            persistent em
            if isempty(em); em = 'OutOfProcess'; end
            if nargin >= 1
                if isempty(m); em = 'OutOfProcess'; else; em = char(m); end
            end
            out = em;
        end

        function setExecutionMode(m)
            % SETEXECUTIONMODE - set the pyenv execution mode used by the python backend.
            io.zarr.Config.executionMode(m);
        end

        function out = smoothing(tf)
            % SMOOTHING - get or set the BigData label up-propagation smoothing flag.
            %
            % Process-wide flag controlling how a BigData segmentation edit made at a
            % coarse (zoomed-out) pyramid level is propagated **up** into the finer
            % levels by ``core.MibBigDataLabels``:
            %
            %   - ``true`` *(default)* - boundaries are reconstructed with a signed
            %     distance transform + Gaussian smoothing (``smoothLabelUpsampleYX`` /
            %     ``signedDistUpsample``), so a coarse circle becomes a smooth curve
            %     instead of a blocky, stair-stepped one at full magnification.
            %   - ``false`` - plain nearest-neighbour up-sampling (faster, blocky).
            %
            % Only affects **up-sampling** (coarse edit -> finer level); down-sampling
            % always uses nearest. Note this rounds the stair-steps but cannot recover
            % detail finer than the level the edit was drawn at.
            %
            % Set at start-up from ``preferences.IO.Zarr.Smoothing`` by
            % ``models.MibModel.initializePreferences`` and committed by the Preferences
            % dialog (``controllers.Preferences.ApplyButtonPushedCallback``); takes
            % effect immediately, no restart needed.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      tf = io.zarr.Config.smoothing();      % query current flag
            %      io.zarr.Config.smoothing(false);      % disable
            %
            % Input Arguments:
            %   - **tf** - *(optional)* [logical] new value; omit (or pass ``[]``) to
            %     query without changing it.
            %
            % Output Arguments:
            %   - **out** - [logical] the current (possibly just-updated) flag.
            %
            % See also:
            %   ``io.zarr.Config.setSmoothing``, ``core.MibBigDataLabels.resizeBlockSmooth``
            persistent sm
            if isempty(sm); sm = true; end
            if nargin >= 1 && ~isempty(tf); sm = logical(tf); end
            out = sm;
        end

        function setSmoothing(tf)
            % SETSMOOTHING - enable/disable smooth boundary up-propagation in the
            % BigData label pyramid.
            %
            % Thin setter wrapper around ``smoothing`` for symmetry with
            % ``setLibrary`` / ``setPythonPath``; the Preferences dialog calls it to
            % push ``preferences.IO.Zarr.Smoothing`` into the process-wide config.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      io.zarr.Config.setSmoothing(true);
            %
            % Input Arguments:
            %   - **tf** - [logical] ``true`` to smooth coarse->fine label propagation,
            %     ``false`` for nearest-neighbour.
            %
            % See also:
            %   ``io.zarr.Config.smoothing``, ``core.MibBigDataLabels.resizeBlockSmooth``
            io.zarr.Config.smoothing(tf);
        end
    end

    methods (Static, Access = private)
        function c = normalize(name)
            % NORMALIZE - map a user/preference string to a canonical backend name.
            name = lower(strtrim(char(name)));
            switch name
                case {'native', 'zarrmex', 'matlab', 'mex', ''}
                    c = 'native';
                case {'python', 'py', 'zarr-python', 'zarrpython'}
                    c = 'python';
                otherwise
                    % lenient fallback: anything mentioning "py" -> python
                    if contains(name, 'py'); c = 'python'; else; c = 'native'; end
            end
        end
    end
end
