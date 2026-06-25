classdef Reader < handle
% READER - backend-agnostic, on-demand region reader for microscopy / WSI files.
%
% Facade over the BioFormats / WSI engine selected by ``io.BioFormats.Config``
% (``'mib'`` = bundled OME Bio-Formats Java reader, ``'matlab'`` = MATLAB built-in
% ``bioformatsread`` / ``openslideread``). It exposes a small, reader-agnostic
% contract designed to match ``io.loaders.Zarr3VirtualLoader`` so that — in a later
% phase — the BigData image read seam (``MibVirtualImage.getDataZarr`` →
% ``loaders{1}.readRegion(...)``) can be backed by a WSI file directly, giving the
% same on-demand, level-aware read experience as a zarr3 dataset.
%
% **Contract**
%   - ``s = info()`` — dimensions, class, and resolution-level metadata.
%   - ``block = readRegion(level, Ylim, Xlim, Zlim, Clim, Tlim, dataClass)`` —
%     read a sub-region at a 1-based resolution ``level``; returns MIB3-order
%     ``[y, x, z, c, t]``.
%   - ``close()`` — release the underlying handle.
%
% **Phase A (2026-06-17):** only the ``'mib'`` (Java) backend is implemented, and
% only full resolution (``level == 1``); nothing in the app calls this class yet
% (no behaviour change). True pyramid-level reads (``setResolution``) and the
% ``'matlab'`` backend land in later phases (see
% ``development/bigdata/bigdata_implementation_plan.md``).
%
% **Examples**
%
%   .. code-block:: matlab
%
%      r = io.BioFormats.Reader('C:\data\slide.czi', 0);   % series 0
%      s = r.info();                                        % dims + levels
%      blk = r.readRegion(1, [1 512], [1 512], [1 1], [1 s.colors], [1 1], s.imgClass);
%      r.close();
%
% See also: io.BioFormats.Config, io.loaders.Zarr3VirtualLoader,
% io.loaders.BioFormatsVirtualLoader

    properties (SetAccess = private)
        filename     (1,:) char = ''
        % [char] full path to the microscopy / WSI file.
        seriesIndex  (1,1) double = 0
        % [double] 0-based series index.
        library      (1,:) char = 'mib'
        % [char] resolved backend ('mib' | 'matlab') at construction.
        memoDir      (1,:) char = ''
        % [char] directory for the Bio-Formats Memoizer (mib backend).
    end

    properties (Access = private)
        reader        % loci.formats.Memoizer Java handle (mib backend), [] until opened
        bim           % blockedImage / array (matlab backend), [] until opened
        blockedAxes   % struct (hasZ/hasC/hasT, Z/C/T) describing the blockedImage dim layout
    end

    methods
        function obj = Reader(filename, seriesIndex, options)
            % READER - construct an on-demand reader; backend from io.BioFormats.Config.
            %
            % Input Arguments:
            %   - **filename** — [char] full path to the file
            %   - **seriesIndex** — *(optional)* [double] 0-based series index (default 0)
            %   - **options** — *(optional)* struct:
            %
            %     - ``.library`` — [char] override the backend: ``'mib'`` (Java),
            %       ``'matlab'`` (bioformatsread), or ``'openslide'`` (openslideread).
            %       When omitted, the BioFormats engine comes from io.BioFormats.Config
            %       (``'mib'``|``'matlab'``); ``'openslide'`` must be requested explicitly.
            %     - ``.memoDir`` — [char] Bio-Formats Memoizer directory (mib backend)
            if nargin < 2 || isempty(seriesIndex); seriesIndex = 0; end
            if nargin < 3; options = struct(); end

            obj.filename    = char(filename);
            obj.seriesIndex = seriesIndex;

            if isfield(options, 'library') && ~isempty(options.library)
                obj.library = io.BioFormats.Reader.normalizeBackend(options.library);  % per-instance override
            else
                obj.library = io.BioFormats.Config.library();   % 'mib' | 'matlab'
            end

            if isfield(options, 'memoDir') && ~isempty(options.memoDir)
                obj.memoDir = char(options.memoDir);
            else
                obj.memoDir = io.BioFormats.Config.memoDir();   % from preferences.ExternalDirs.BioFormatsMemoizerMemoDir
            end
            if ~isfolder(obj.memoDir)
                try
                    mkdir(obj.memoDir);
                catch  %#ok<CTCH>
                end
            end
        end

        function s = info(obj)
            % INFO - return dimensions + resolution-level metadata.
            %
            % Output Arguments:
            %   - **s** — struct with fields:
            %
            %     - ``.height`` ``.width`` ``.depth`` ``.colors`` ``.time``
            %     - ``.imgClass`` — [char] e.g. ``'uint8'`` / ``'uint16'``
            %     - ``.numLevels`` — number of resolution (pyramid) levels
            %     - ``.levelSizes`` — [numLevels x 2] per-level ``[height width]``
            switch obj.library
                case 'mib'
                    s = obj.infoMib();
                otherwise   % 'matlab' (bioformatsread) | 'openslide' (openslideread)
                    s = obj.infoBlocked();
            end
        end

        function block = readRegion(obj, level, Ylim, Xlim, Zlim, Clim, Tlim, dataClass)
            % READREGION - read a sub-region; returns MIB3-order [y, x, z, c, t].
            %
            % Input Arguments:
            %   - **level** — [double] 1-based resolution level (1 = full resolution)
            %   - **Ylim**, **Xlim**, **Zlim** — [1x2] inclusive 1-based LEVEL-LOCAL ranges
            %   - **Clim** — [1x2] inclusive 1-based colour-channel range
            %   - **Tlim** — [1x2] inclusive 1-based time range
            %   - **dataClass** — [char] output class
            if nargin < 8 || isempty(dataClass); dataClass = 'uint8'; end
            switch obj.library
                case 'mib'
                    block = obj.readRegionMib(level, Ylim, Xlim, Zlim, Clim, Tlim, dataClass);
                otherwise   % 'matlab' | 'openslide'
                    block = obj.readRegionBlocked(level, Ylim, Xlim, Zlim, Clim, Tlim, dataClass);
            end
        end

        function pyramid = pyramidStruct(obj, voxelSize)
            % PYRAMIDSTRUCT - build the MIB ``pyramid`` metadata struct for this image.
            %
            % Returns the fields ``core.MibVirtualImage`` / ``MibBigDataImage`` need so
            % the existing pyramidal read path (``getDataZarr`` / future
            % ``getDataPyramid``) can drive this WSI reader exactly like a zarr3 dataset
            % (level selection by magnification + level-local region reads).
            %
            % Input Arguments:
            %   - **voxelSize** — *(optional)* [1x3] full-resolution ``[y x z]`` voxel
            %     size (µm); default ``[1 1 1]``.
            %
            % Output Arguments:
            %   - **pyramid** — struct with fields:
            %
            %     - ``.sourceType`` — ``'bioformats'`` (used by the read dispatch)
            %     - ``.levelNames`` — {1 x nLevels} ``'0'..'N-1'`` (resolution keys)
            %     - ``.levelImageSizes`` — [nLevels x 3] per-level ``[Y X Z]``
            %     - ``.levelScaleFactors`` — [nLevels x 3] level0 ./ levelN ``[y x z]``
            %     - ``.levelVoxelSizes`` — [1 x 3] full-resolution ``[y x z]`` voxel size
            %     - ``.axisOrder`` — ``''`` (the reader returns native MIB3 [y x z c t])
            %     - ``.chunkSizes`` / ``.shardSizes`` — ``[]``
            if nargin < 2 || isempty(voxelSize); voxelSize = [1 1 1]; end
            s = obj.info();
            nL = s.numLevels;
            pyramid = struct();
            pyramid.sourceType        = 'bioformats';
            pyramid.levelNames        = arrayfun(@(k) num2str(k-1), 1:nL, 'UniformOutput', false);
            pyramid.levelImageSizes   = s.levelYXZ;                       % [nL x 3] [Y X Z]
            level0 = s.levelYXZ(1, :);
            pyramid.levelScaleFactors = level0 ./ s.levelYXZ;            % [nL x 3] [y x z]
            pyramid.levelVoxelSizes   = voxelSize(:)';
            pyramid.axisOrder         = '';
            pyramid.chunkSizes        = [];
            pyramid.shardSizes        = [];
            % record which engine built this pyramid so the read seam
            % (getDataZarr) re-opens the matching backend ('mib'|'matlab'|'openslide')
            pyramid.sourceReaderLibrary = obj.library;
        end

        function close(obj)
            % CLOSE - release the underlying handle. Safe to call repeatedly.
            if ~isempty(obj.reader)
                try
                    obj.reader.close();
                catch  %#ok<CTCH>
                end
                obj.reader = [];
            end
            obj.bim = [];
            obj.blockedAxes = [];
        end

        function delete(obj)
            % DELETE - destructor; closes the reader.
            obj.close();
        end
    end

    % ------------------------------------------------------------------ %
    %   MIB (Bio-Formats Java) backend                                    %
    % ------------------------------------------------------------------ %
    methods (Access = private)
        function openMib(obj)
            % OPENMIB - lazily open the Memoizer Java reader and select the series.
            %
            % Resolutions are kept UN-flattened (``setFlattenedResolutions(false)``) so
            % a WSI pyramid is exposed as multiple resolutions of one series (accessible
            % via ``setResolution``) instead of being split into separate series. A
            % dedicated Memoizer sub-directory isolates these unflattened memo files from
            % MIB's other (flattened) Bio-Formats readers.
            if ~isempty(obj.reader); return; end
            utils.ensureJavaLibraries({'bioformats'});
            loci.common.DebugTools.setRootLevel('ERROR');
            baseReader = bfGetReader();
            baseReader.setFlattenedResolutions(false);
            facadeMemo = fullfile(obj.memoDir, 'bfFacade');
            if ~isfolder(facadeMemo)
                try
                    mkdir(facadeMemo);
                catch  %#ok<CTCH>
                end
            end
            obj.reader = loci.formats.Memoizer(baseReader, 0, java.io.File(facadeMemo));
            obj.reader.setId(obj.filename);
            obj.reader.setSeries(obj.seriesIndex);
        end

        function s = infoMib(obj)
            obj.openMib();
            s = struct();
            % base (full-resolution) dimensions
            obj.reader.setResolution(0);
            s.height = double(obj.reader.getSizeY());
            s.width  = double(obj.reader.getSizeX());
            s.depth  = double(obj.reader.getSizeZ());
            s.colors = double(obj.reader.getSizeC());
            s.time   = double(obj.reader.getSizeT());
            % a Z==1, T>1 movie is treated as a depth stack (mirrors MIB loaders)
            if s.depth == 1 && s.time > 1; s.depth = s.time; s.time = 1; end
            bpp = double(obj.reader.getBitsPerPixel());
            if     bpp == 8;  s.imgClass = 'uint8';
            elseif bpp == 16; s.imgClass = 'uint16';
            elseif bpp == 32; s.imgClass = 'uint32';
            else;             s.imgClass = 'double';
            end
            % resolution levels (WSI pyramids expose getResolutionCount > 1)
            try
                rawN = double(obj.reader.getResolutionCount());
            catch
                rawN = 1;
            end
            if rawN < 1; rawN = 1; end
            % Keep only the leading run of TRUE pyramid levels. Some WSI readers append
            % an associated image (macro / label / overview) as a trailing "resolution"
            % with a different aspect ratio, channel count or pixel type — including it
            % would corrupt the pyramid (wrong scale factors / class). We keep level 0
            % then accept further levels only while they stay consistent with level 0
            % (same C, same bytes-per-pixel, same aspect ratio ±2 %) and strictly
            % smaller — and stop at the first inconsistent one.
            % (Note: in un-flattened mode such associated images are usually exposed as
            % a separate *series* anyway, e.g. NDPI "macro image"; this is a safety net.)
            aspect0   = s.width / s.height;
            bytesPP0  = double(loci.formats.FormatTools.getBytesPerPixel(obj.reader.getPixelType()));
            c0        = double(obj.reader.getSizeC());
            yxz = zeros(rawN, 3);
            keep = false(1, rawN);
            prevY = inf; prevX = inf;
            for L = 1:rawN
                obj.reader.setResolution(L - 1);
                ly = double(obj.reader.getSizeY());
                lx = double(obj.reader.getSizeX());
                lz = double(obj.reader.getSizeZ());
                if lz == 1 && double(obj.reader.getSizeT()) > 1; lz = double(obj.reader.getSizeT()); end
                yxz(L, :) = [ly, lx, lz];
                if L == 1
                    keep(L) = true;
                else
                    consistent = double(obj.reader.getSizeC()) == c0 && ...
                        double(loci.formats.FormatTools.getBytesPerPixel(obj.reader.getPixelType())) == bytesPP0 && ...
                        abs((lx/ly) / aspect0 - 1) < 0.02 && ...
                        ly < prevY && lx < prevX;
                    if ~consistent; break; end
                    keep(L) = true;
                end
                prevY = ly; prevX = lx;
            end
            keepIdx = find(keep);
            s.numLevels  = numel(keepIdx);
            s.levelYXZ   = yxz(keepIdx, :);          % [Y X Z] true pyramid levels only
            s.levelSizes = s.levelYXZ(:, 1:2);       % [Y X] (kept for back-compat)
            obj.reader.setResolution(0);   % restore to base
        end

        function block = readRegionMib(obj, level, Ylim, Xlim, Zlim, Clim, Tlim, dataClass)
            % READREGIONMIB - region read at a 1-based resolution ``level``.
            % Ylim/Xlim/Zlim are LEVEL-LOCAL pixel ranges (i.e. coordinates within the
            % chosen resolution), matching the zarr3 loader convention.
            obj.openMib();
            nLevels = double(obj.reader.getResolutionCount());
            if level < 1 || level > nLevels
                error('io:BioFormats:Reader:badLevel', ...
                    'Requested level %d is out of range (1..%d).', level, nLevels);
            end
            obj.reader.setResolution(level - 1);
            nY = Ylim(2) - Ylim(1) + 1;
            nX = Xlim(2) - Xlim(1) + 1;
            zList = Zlim(1):Zlim(2);
            cList = Clim(1):Clim(2);
            tList = Tlim(1):Tlim(2);
            block = zeros(nY, nX, numel(zList), numel(cList), numel(tList), dataClass);
            for ti = 1:numel(tList)
                for zi = 1:numel(zList)
                    for ci = 1:numel(cList)
                        iPlane = obj.reader.getIndex(zList(zi) - 1, cList(ci) - 1, tList(ti) - 1) + 1;
                        cPlane = bfGetPlane(obj.reader, iPlane, Xlim(1), Ylim(1), nX, nY);
                        if isa(cPlane, 'int8')   % BF may return signed for unsigned 8-bit
                            cPlane = int16(cPlane);
                            cPlane(cPlane < 0) = cPlane(cPlane < 0) + 256;
                        end
                        block(:, :, zi, ci, ti) = cast(cPlane, dataClass);
                    end
                end
            end
            obj.reader.setResolution(0);   % restore to base
        end
    end

    % ------------------------------------------------------------------ %
    %   MATLAB built-in backends (bioformatsread / openslideread)         %
    %   — return lazy, tiled, pyramid-aware blockedImage objects.         %
    % ------------------------------------------------------------------ %
    methods (Access = private)
        function openBlocked(obj)
            % OPENBLOCKED - lazily open the blockedImage for the matlab/openslide backend.
            if ~isempty(obj.bim); return; end
            % MATLAB's bioformatsread/openslideread call javaaddpath, which warns
            % "Objects of loci/formats/Memoizer class exist - not clearing java"
            % (MATLAB:Java:DuplicateClass) when MIB's bundled Bio-Formats Java reader
            % already has live objects. The two Bio-Formats stacks coexist fine on the
            % path; the warning is benign, so silence it for these calls.
            prevWarn = warning('off', 'MATLAB:Java:DuplicateClass');
            cleanupWarn = onCleanup(@() warning(prevWarn));
            switch obj.library
                case 'openslide'
                    if exist('openslideread', 'file') ~= 2
                        error('io:BioFormats:Reader:noOpenSlide', ...
                            ['The OpenSlide reader requires the "Medical Imaging Toolbox Interface ' ...
                             'for Whole Slide Imaging File Reader" support package.']);
                    end
                    bims = openslideread(obj.filename);   % one slide → one blockedImage
                    obj.bim = bims(1);
                otherwise   % 'matlab'
                    if exist('bioformatsread', 'file') ~= 2
                        error('io:BioFormats:Reader:noBioformatsread', ...
                            ['The MATLAB BioFormats reader requires the "Medical Imaging Toolbox ' ...
                             'Interface for Whole Slide Imaging File Reader" support package; ' ...
                             'switch the BioFormats library preference to "MIB" instead.']);
                    end
                    bims = bioformatsread(obj.filename);   % one blockedImage per series
                    si = obj.seriesIndex + 1;              % 0-based → 1-based
                    if si < 1 || si > numel(bims); si = 1; end
                    obj.bim = bims(si);
            end
            obj.blockedAxes = obj.canonicalDims();
        end

        function ax = canonicalDims(obj)
            % CANONICALDIMS - describe the blockedImage dimension layout.
            %
            % A blockedImage from bioformatsread/openslideread is [Y, X, ...] with the
            % trailing dims being whichever of Z, C, T are > 1 (in that order; singleton
            % axes are dropped). After dropping, dim 3 alone is ambiguous (Z vs C), so
            % the canonical Z/C/T counts are taken from the Bio-Formats Java metadata
            % (always available); OpenSlide slides are 2-D RGB ([Y X (C)]).
            ax = struct('hasZ', false, 'hasC', false, 'hasT', false, 'Z', 1, 'C', 1, 'T', 1);
            nTrail = size(obj.bim.Size, 2) - 2;
            if strcmp(obj.library, 'openslide')
                if nTrail >= 1; ax.hasC = true; ax.C = double(obj.bim.Size(1, 3)); end
                return;
            end
            % matlab (bioformatsread) — query Z/C/T from Bio-Formats
            try
                utils.ensureJavaLibraries({'bioformats'});
                loci.common.DebugTools.setRootLevel('ERROR');
                br = bfGetReader(); br.setFlattenedResolutions(false);
                br.setId(obj.filename); br.setSeries(obj.seriesIndex);
                ax.Z = double(br.getSizeZ()); ax.C = double(br.getSizeC()); ax.T = double(br.getSizeT());
                br.close();
            catch
                % fallback: treat a single trailing dim as colour channels
                if nTrail >= 1; ax.C = double(obj.bim.Size(1, 3)); end
            end
            ax.hasZ = ax.Z > 1; ax.hasC = ax.C > 1; ax.hasT = ax.T > 1;
        end

        function s = infoBlocked(obj)
            % INFOBLOCKED - dims + per-level [Y X Z] from a blockedImage pyramid.
            obj.openBlocked();
            sz = obj.bim.Size;                       % [numLevels x nDims]
            nLevels = double(obj.bim.NumLevels);
            ax = obj.blockedAxes;
            s = struct();
            s.numLevels = nLevels;
            s.height = double(sz(1, 1));
            s.width  = double(sz(1, 2));
            s.depth  = ax.Z;
            s.colors = ax.C;
            s.time   = ax.T;
            cu = obj.bim.ClassUnderlying;
            if isstring(cu) || iscell(cu); cu = char(string(cu(1))); end
            s.imgClass = cu;
            % per-level [Y X Z]; the pyramid downsamples XY only → Z constant
            s.levelYXZ   = [double(sz(:, 1)), double(sz(:, 2)), repmat(ax.Z, nLevels, 1)];
            s.levelSizes = s.levelYXZ(:, 1:2);
        end

        function block = readRegionBlocked(obj, level, Ylim, Xlim, Zlim, Clim, Tlim, dataClass)
            % READREGIONBLOCKED - level-local region read via blockedImage getRegion;
            % returns MIB3-order [y x z c t]. Builds the getRegion start/end over the
            % blockedImage's actual dims ([Y X] + present Z/C/T in that order) and
            % reshapes the result to [y x z c t].
            obj.openBlocked();
            ax = obj.blockedAxes;
            n = size(obj.bim.Size, 2);
            pStart = ones(1, n); pEnd = ones(1, n);
            pStart(1) = Ylim(1); pEnd(1) = Ylim(2);
            pStart(2) = Xlim(1); pEnd(2) = Xlim(2);
            d = 3;
            if ax.hasZ; pStart(d) = Zlim(1); pEnd(d) = Zlim(2); d = d + 1; end
            if ax.hasC; pStart(d) = Clim(1); pEnd(d) = Clim(2); d = d + 1; end
            if ax.hasT; pStart(d) = Tlim(1); pEnd(d) = Tlim(2); d = d + 1; end %#ok<NASGU>
            region = getRegion(obj.bim, pStart, pEnd, Level=level);
            nY = Ylim(2) - Ylim(1) + 1;
            nX = Xlim(2) - Xlim(1) + 1;
            nZ = 1; nC = 1; nT = 1;
            if ax.hasZ; nZ = Zlim(2) - Zlim(1) + 1; end
            if ax.hasC; nC = Clim(2) - Clim(1) + 1; end
            if ax.hasT; nT = Tlim(2) - Tlim(1) + 1; end
            % region dims are [Y X (Z) (C) (T)] (present axes in Z,C,T order); inserting
            % singletons for absent axes makes the column-major reshape to [Y X Z C T] exact.
            block = cast(reshape(region, [nY, nX, nZ, nC, nT]), dataClass);
        end
    end

    methods (Static, Access = private)
        function b = normalizeBackend(name)
            % NORMALIZEBACKEND - resolve a backend name, keeping 'openslide' distinct
            % from 'matlab' (unlike io.BioFormats.Config.normalizeName, which folds
            % openslide into the matlab/built-in family).
            name = lower(strtrim(char(name)));
            switch name
                case {'openslide', 'openslideread'}
                    b = 'openslide';
                case {'mib', 'java', 'bioformats', 'loci', 'ome', ''}
                    b = 'mib';
                otherwise   % matlab / bioformatsread / builtin / wsi
                    b = 'matlab';
            end
        end
    end
end
