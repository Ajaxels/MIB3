classdef Config < handle
% CONFIG - process-wide selection of the active BioFormats / WSI reader backend.
%
% Mirrors ``io.zarr.Config`` for the image-reading side. Holds one module-level
% setting shared by the ``io.BioFormats`` facade (``io.BioFormats.Reader``):
%
%   * **library** — which engine reads microscopy / whole-slide image files:
%
%     - ``'mib'`` *(default)* — MIB's bundled OME **Bio-Formats Java** reader
%       (``bfGetReader`` / ``bfGetPlane`` / ``loci.formats.Memoizer``). Broadest
%       coverage validated inside MIB; the historical path.
%     - ``'matlab'`` — MATLAB's built-in **WSI file readers**
%       (``bioformatsinfo`` / ``bioformatsread`` and, for classic WSI formats,
%       ``openslideinfo`` / ``openslideread``), which return lazy, tiled,
%       pyramid-aware ``blockedImage`` objects. No Java dependency.
%
% Benchmark (2026-06-17, 50-series CZI): the two engines are a tie for a full
% read (~2.5 s, pixel-identical), so the choice is about coverage / robustness /
% dependencies, not speed.
%
% ``models.MibModel.initializePreferences`` pushes this from
% ``preferences.IO.BioFormats.Library`` at start-up; the Preferences dialog calls
% ``setLibrary`` again whenever the user changes it (takes effect immediately).
%
% **Examples**
%
%   .. code-block:: matlab
%
%      io.BioFormats.Config.setLibrary('matlab');   % use bioformatsread/openslideread
%      tf  = io.BioFormats.Config.isMatlab();        % true
%      lib = io.BioFormats.Config.library();         % 'matlab'
%      io.BioFormats.Config.setLibrary('mib');       % back to the Java reader
%
% See also: io.zarr.Config, io.BioFormats.Reader

    methods (Static)
        function out = library(name)
            % LIBRARY - get (no args) or set (with a name) the active backend.
            %   Returns the canonical name ``'mib'`` or ``'matlab'``.
            persistent lib
            if isempty(lib); lib = 'mib'; end
            if nargin >= 1 && ~isempty(name)
                lib = io.BioFormats.Config.normalize(name);
            end
            out = lib;
        end

        function setLibrary(name)
            % SETLIBRARY - set the active backend ('mib'|'matlab', aliases accepted).
            io.BioFormats.Config.library(name);
        end

        function tf = isMatlab()
            % ISMATLAB - true when the MATLAB built-in WSI backend is active.
            tf = strcmp(io.BioFormats.Config.library(), 'matlab');
        end

        function out = memoDir(dirPath)
            % MEMODIR - get (no args) or set (with a path) the Bio-Formats Memoizer
            % directory used by the ``'mib'`` backend (where ``.bfmemo`` reader caches
            % are written). Default ``fullfile(tempdir, 'mibVirtual')``;
            % ``models.MibModel.initializePreferences`` overrides it from
            % ``preferences.ExternalDirs.BioFormatsMemoizerMemoDir`` at start-up.
            persistent memoDirectory
            if isempty(memoDirectory); memoDirectory = fullfile(tempdir, 'mibVirtual'); end
            if nargin >= 1 && ~isempty(dirPath)
                memoDirectory = char(dirPath);
            end
            out = memoDirectory;
        end

        function setMemoDir(dirPath)
            % SETMEMODIR - set the Bio-Formats Memoizer directory (mib backend).
            io.BioFormats.Config.memoDir(dirPath);
        end

        function c = normalizeName(name)
            % NORMALIZENAME - map a string to a canonical backend name WITHOUT
            % changing the process-wide setting (unlike ``library(name)``).
            c = io.BioFormats.Config.normalize(name);
        end
    end

    methods (Static, Access = private)
        function c = normalize(name)
            % NORMALIZE - map a user/preference string to a canonical backend name.
            name = lower(strtrim(char(name)));
            switch name
                case {'mib', 'java', 'bioformats', 'loci', 'ome', ''}
                    c = 'mib';
                case {'matlab', 'builtin', 'wsi', 'bioformatsread', 'openslide'}
                    c = 'matlab';
                otherwise
                    % lenient fallback: anything mentioning "matlab"/"wsi" -> matlab
                    if contains(name, 'matlab') || contains(name, 'wsi')
                        c = 'matlab';
                    else
                        c = 'mib';
                    end
            end
        end
    end
end
