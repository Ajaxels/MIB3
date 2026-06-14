classdef Config < handle
% CONFIG - process-wide selection of the active OME-Zarr v3 backend.
%
% Holds two module-level settings shared by the ``io.zarr`` facade
% (``io.zarr.Array`` / ``io.zarr.Group``):
%
%   * **library** — which backend performs bulk pixel I/O:
%
%     - ``'native'`` — the bundled ``zarrMex`` engine (``ZarrArray`` /
%       ``ZarrGroup``). Default. No external dependency.
%     - ``'python'`` — the ``zarr-python`` (v3) library via ``pyrun``/numpy.
%
%   * **pythonPath** — the Python interpreter used by the python backend
%     (normally ``preferences.ExternalDirs.PythonInstallationPath``).
%
% ``models.MibModel.initializePreferences`` pushes both from
% ``preferences.IO.ZarrLibrary`` / ``preferences.ExternalDirs.PythonInstallationPath``
% at start-up; the Preferences dialog should call ``setLibrary`` /
% ``setPythonPath`` again whenever the user changes them.
%
% Metadata operations (creating arrays/groups, attributes, resize) are always
% performed natively for an identical on-disk structure; only bulk read/write
% honour the selected library — so a ``'python'`` reader is fully independent
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
