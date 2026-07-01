classdef BioFormatsVirtualSetupLoader < io.loaders.BaseImageLoader
% BIOFORMATSVIRTUALSETUPLOADER - Virtual-mode setup loader for BioFormats datasets.
%
% Wraps BioFormatsStdLoader and adapts it for virtual stacking mode:
% loadMetadata delegates entirely to BioFormatsStdLoader
% (series selection dialog, pixel-size extraction, etc.)
% loadImages does NOT read pixel data; instead returns the file
% path(s) as a cell array and stores the Virtual
% struct in imginfo{"Virtual"} so that
% MibVirtualImage.initialize can wire it up.
%
% **Relationship to BioFormatsVirtualLoader**
%
% These two classes serve different phases of the virtual dataset lifecycle:
%
% BioFormatsVirtualSetupLoader — runs ONCE when the user opens a file.
% Phase : dataset initialisation (MibModel.loadImages)
% Job : parse metadata, build the Virtual struct, return file paths.
% Reads pixels? No.
% Lifetime: discarded after open; implements BaseImageLoader.
% Created by: LoaderFactory
%
% BioFormatsVirtualLoader — runs on EVERY slice request during session.
% Phase : on-demand pixel reading (MibVirtualImage.getDataVirt)
% Job : open Memoizer reader, call bfGetPlane per channel.
% Reads pixels? Yes.
% Lifetime: cached in MibVirtualImage.loaders{} for the session.
% Created by: MibVirtualImage.getOrCreateLoader (lazily, per file)
%
% Usage example:
%
%   .. code-block:: matlab
%
%      loader = io.loaders.BioFormatsVirtualSetupLoader(options);
%      [imginfo, files] = loader.loadMetadata({'stack.czi'}, options);
%      [img, imginfo] = loader.loadImages(files, imginfo, options);
%      % img is {'C:\data\stack.czi'} and imginfo{"Virtual"} holds the struct

properties
    innerLoader
    % io.loaders.BioFormatsStdLoader instance that handles all
    % format-specific metadata parsing (series selection, pixel sizes, etc.)
end

methods
    function obj = BioFormatsVirtualSetupLoader(options)
        % BIOFORMATSVIRTUALSETUPLOADER - Create a virtual-mode BioFormats setup loader.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj = BioFormatsVirtualSetupLoader(options)
        %
        % Input Arguments:
        %   - **options** — *(optional)* [struct] options passed to BioFormatsStdLoader
        %
        % Output Arguments:
        %   - **obj** — [BioFormatsVirtualSetupLoader] new loader instance
        %

        obj.Options = struct();
        obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);

        if nargin < 1; options = struct(); end
        obj.Options = obj.mergeOptions(obj.Options, options);
        obj.initBaseProps(options);
        obj.innerLoader = io.loaders.BioFormatsStdLoader(options);
    end

    function [imginfo, files] = loadMetadata(obj, filenames, options)
        % LOADMETADATA - Delegate metadata loading to BioFormatsStdLoader unchanged.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [imginfo, files] = obj.loadMetadata(filenames, options)
        %
        % Input Arguments:
        %   - **filenames** — [cell] cell array of file paths to load
        %   - **options** — [struct] loader options
        %
        % Output Arguments:
        %   - **imginfo** — [dictionary] image metadata dictionary
        %   - **files** — [struct array] per-file metadata; each element has fields:
        %
        %     - ``.origFilename`` — [char] path to the actual file
        %     - ``.seriesName``   — [numeric] 1-based series index
        %     - ``.noLayers``     — [numeric] number of z-slices in this series
        %     - ``.color``        — [numeric] number of colour channels
        %

        if obj.isBigDataMode(options)
            % BigData: build a pyramid-aware setup (direct WSI reading via the
            % io.BioFormats.Reader seam) instead of the flat virtual-stack setup.
            [imginfo, files] = obj.loadMetadataBigData(filenames, options);
            return;
        end
        [imginfo, files] = obj.innerLoader.loadMetadata(filenames, options);
    end

    function [img, imginfo] = loadImages(obj, files, imginfo, options) 
        % LOADIMAGES - Virtual-mode image setup — does NOT load pixel data.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [img, imginfo] = obj.loadImages(files, imginfo, options)
        %
        % Returns the file path(s) as a cell array (consumed by
        % MibVirtualImage.initialize as obj.data{}) and populates
        % imginfo{"Virtual"} with the struct fields required by MibVirtualImage.
        %
        % Input Arguments:
        %   - **files** — [struct array] per-file metadata from loadMetadata
        %   - **imginfo** — [dictionary] image metadata from loadMetadata
        %   - **options** *(optional)* — [struct] unused in virtual mode
        %
        % Output Arguments:
        %   - **img** — [nFiles x 1 cell] cell array of original file paths
        %   - **imginfo** — [dictionary] updated dictionary; ``imginfo{"Virtual"}`` is
        %     added with fields:
        %
        %     - ``.objectType``    — [cell] ``'bioformats'`` per file
        %     - ``.seriesName``    — [cell] 1-based series index per file
        %     - ``.slicesPerFile`` — [numeric] z-slice count per file
        %     - ``.filenames``     — [cell] original file paths (before multi-series rename)
        %     - ``.readerId``      — [totalZ x 1 numeric] maps each slice index to its source file index
        %

        % BigData pyramid setup: loadMetadataBigData already filled imginfo
        % (dims + Pyramid). Just hand back the file path(s) as obj.data.
        if obj.isBigDataMode(options) && isKey(imginfo, 'Pyramid')
            img = {files(1).origFilename};
            return;
        end

        nFiles = numel(files);
        img = cell([nFiles 1]);

        Virtual.objectType    = cell([nFiles 1]);
        Virtual.seriesName    = cell([nFiles 1]);
        Virtual.slicesPerFile = zeros([nFiles 1]);
        Virtual.filenames     = cell([nFiles 1]);

        for i = 1:nFiles
            img{i}                  = files(i).origFilename;
            Virtual.filenames{i}    = files(i).origFilename;
            Virtual.seriesName{i}   = files(i).seriesName;   % 1-based series index
            Virtual.slicesPerFile(i)= files(i).noLayers;
            Virtual.objectType{i}   = 'bioformats';
        end

        % Build readerId: maps each global z-slice index to its source file index
        totalSlices       = sum(Virtual.slicesPerFile);
        Virtual.readerId  = zeros([totalSlices, 1]);
        idx = 1;
        for i = 1:nFiles
            n = Virtual.slicesPerFile(i);
            Virtual.readerId(idx : idx+n-1) = i;
            idx = idx + n;
        end

        % Update imginfo dimensions from files
        imginfo{"Height"} = max([files.height]);
        imginfo{"Width"}  = max([files.width]);
        imginfo{"Depth"}  = sum([files.noLayers]);
        imginfo{"Colors"} = max([files.color]);
        imginfo{"Time"}   = max([files.time]);

        imginfo{"Virtual"} = Virtual;
    end
end

methods (Access = private)
    function tf = isBigDataMode(obj, options)
        % ISBIGDATAMODE - true when the dataset mode is BigData (from the per-call
        % options or, more reliably, the constructor options injected by LoaderFactory).
        tf = (isfield(options, 'datasetMode') && strcmp(options.datasetMode, 'BigData')) || ...
             (isfield(obj.Options, 'datasetMode') && strcmp(obj.Options.datasetMode, 'BigData'));
    end

    function [imginfo, files] = loadMetadataBigData(obj, filenames, options)
        % LOADMETADATABIGDATA - pyramid-aware BigData setup for a WSI/BioFormats file.
        %
        % Enumerates the pyramid *scenes* (un-flattened series), picks one
        % (single scene → auto; several → selection dialog, or options.BioFormatsIndices
        % when provided), builds the MIB pyramid via io.BioFormats.Reader.pyramidStruct,
        % and fills imginfo so MibBigDataImage/MibVirtualImage read on demand through the
        % getDataZarr → io.BioFormats.Reader seam (sourceType='bioformats').
        filename = filenames{1};
        utils.ensureJavaLibraries({'bioformats'});
        loci.common.DebugTools.setRootLevel('ERROR');

        % Open ONE Memoizer-cached reader for every setup-phase metadata query
        % (scenes, voxel size, LUT). This replaces the three separate raw setId
        % calls the setup path used before with a single parse and — because the
        % Memoizer persists that parse to a .bfmemo in the shared 'bfFacade' dir
        % (the same one io.BioFormats.Reader reads at pixel-read time) — makes
        % subsequent opens of the same file skip the multi-minute CZI subblock-
        % directory scan, even in a fresh MATLAB session with a cold OS cache.
        % onCleanup releases the handle on every exit path (incl. dialog cancel).
        sharedReader  = obj.openSharedReader(filename);
        cleanupReader = onCleanup(@() obj.safeCloseReader(sharedReader));

        % --- enumerate pyramid scenes (un-flattened series) -------------------
        [sceneIdx, sceneName, sceneLevel0] = obj.enumeratePyramidScenes(sharedReader);
        if isempty(sceneIdx)
            error('io:BioFormatsVirtualSetupLoader:noPyramidScene', ...
                'No readable image series found in:\n%s', filename);
        end

        % --- choose the scene -------------------------------------------------
        chosen = 1;   % index into sceneIdx
        if isfield(options, 'BioFormatsIndices') && ~isempty(options.BioFormatsIndices)
            req = options.BioFormatsIndices;
            if ischar(req); req = str2num(req); end %#ok<ST2NM>
            hit = find(sceneIdx == (req(1) - 1), 1);   % BioFormatsIndices is 1-based series
            if ~isempty(hit); chosen = hit; end
        elseif numel(sceneIdx) > 1
            silent = isfield(options, 'silentMode') && options.silentMode;
            if ~silent
                items = arrayfun(@(k) sprintf('%s  [%d x %d]', sceneName{k}, ...
                    sceneLevel0(k, 2), sceneLevel0(k, 1)), 1:numel(sceneIdx), 'UniformOutput', false);
                % default to the largest scene
                [~, defIdx] = max(prod(sceneLevel0, 2));
                dlgOpts.mibPath = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                dlgOpts.HeaderLines = 2;
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, ...
                    'This file contains several image scenes - choose one to open as BigData:', ...
                    {'Scene:'}, {[items, {defIdx}]}, 'Select scene', dlgOpts);
                if isempty(answer); imginfo = dictionary(); files = struct([]); return; end
                chosen = find(strcmp(items, answer{1}), 1);
                if isempty(chosen); chosen = defIdx; end
            else
                [~, chosen] = max(prod(sceneLevel0, 2));
            end
        end
        seriesIndex0 = sceneIdx(chosen);   % 0-based series index of the chosen scene

        % --- voxel size from OME (best-effort) --------------------------------
        voxel = obj.readVoxelSize(sharedReader, seriesIndex0);   % [y x z] um

        % --- reader backend: OpenSlide family → openslideread engine; otherwise
        %     the BioFormats engine from the preference (io.BioFormats.Config) ----
        family = '';
        if isfield(options, 'readerFamily') && ~isempty(options.readerFamily)
            family = options.readerFamily;
        elseif isfield(obj.Options, 'readerFamily') && ~isempty(obj.Options.readerFamily)
            family = obj.Options.readerFamily;
        end
        if strcmpi(family, 'OpenSlide')
            backend = 'openslide';
        else
            backend = io.BioFormats.Config.library();   % 'mib' | 'matlab'
        end

        % --- pyramid + dimensions via io.BioFormats.Reader (chosen backend) ---
        % OpenSlide's bundled libopenslide may not support every format on the vendor
        % list in a given MATLAB build (e.g. CZI/DICOM need a newer libopenslide). If
        % the OpenSlide engine can't open this file, fall back to the BioFormats engine.
        rdr = io.BioFormats.Reader(filename, seriesIndex0, struct('library', backend));
        try
            s = rdr.info();
        catch openErr
            if strcmp(backend, 'openslide')
                try
                    rdr.close();
                catch  %#ok<CTCH>
                end
                backend = io.BioFormats.Config.library();   % 'mib' | 'matlab'
                fprintf(['io.loaders.BioFormatsVirtualSetupLoader: OpenSlide could not open\n  %s\n' ...
                    '  (%s)\n  Falling back to the BioFormats engine ("%s").\n'], filename, openErr.message, backend);
                rdr = io.BioFormats.Reader(filename, seriesIndex0, struct('library', backend));
                s = rdr.info();
            else
                rethrow(openErr);
            end
        end
        py  = rdr.pyramidStruct(voxel);   % records sourceReaderLibrary = backend
        py.sourceSeries = seriesIndex0;
        rdr.close();

        % --- assemble imginfo -------------------------------------------------
        imginfo = core.MibImage.initializeImgInfo();
        imginfo{'Height'}    = s.height;
        imginfo{'Width'}     = s.width;
        imginfo{'Depth'}     = s.depth;
        imginfo{'Colors'}    = s.colors;
        imginfo{'Time'}      = s.time;
        imginfo{'imgClass'}  = s.imgClass;
        % Sync MaxInt and viewPort to actual bit depth (mirrors Zarr3VirtualSetupLoader pattern).
        % initializeImgInfo() defaults both to 255; the BigData path never calls finalizeImgInfo().
        if any(strcmp(s.imgClass, {'uint8','uint16','uint32','uint64','int8','int16','int32','int64'}))
            maxInt = double(intmax(s.imgClass));
        else
            maxInt = 1;   % float data (rare for WSI)
        end
        imginfo{'MaxInt'}   = maxInt;
        imginfo{'viewPort'} = struct('min', zeros(1, s.colors), 'max', maxInt*ones(1, s.colors), 'gamma', ones(1, s.colors));
        imginfo{'Filename'}  = filename;
        if s.colors > 1; imginfo{'ColorType'} = 'multichannel'; else; imginfo{'ColorType'} = 'grayscale'; end
        pixSize = imginfo{'pixSize'};
        pixSize.x = voxel(2); pixSize.y = voxel(1); pixSize.z = voxel(3);
        imginfo{'pixSize'} = pixSize;
        imginfo{'Pyramid'} = py;

        % channel LUT colours from OME metadata (as the Virtual/Standard path does)
        lut = obj.readLutColors(sharedReader, seriesIndex0, s.colors);
        if ~isempty(lut); imginfo{'lutColors'} = lut; end

        % --- minimal files struct --------------------------------------------
        files = struct();
        files(1).origFilename = filename;
        files(1).filename     = filename;
        files(1).seriesName   = seriesIndex0 + 1;   % 1-based
        files(1).noLayers     = s.depth;
        files(1).color        = s.colors;
        files(1).height       = s.height;
        files(1).width        = s.width;
        files(1).time         = s.time;
        files(1).imgClass     = s.imgClass;
    end

    function reader = openSharedReader(~, filename)
        % OPENSHAREDREADER - open ONE Memoizer-cached, un-flattened Bio-Formats
        % reader used for all setup-phase metadata queries (scenes/voxel/LUT).
        %
        % The reader is configured identically to io.BioFormats.Reader's Java
        % backend (``bfGetReader`` + ``setFlattenedResolutions(false)`` wrapped in a
        % ``loci.formats.Memoizer`` pointed at the shared ``bfFacade`` memo dir), so
        % the ``.bfmemo`` written here is reused by the pixel-read path and, on any
        % later open of the same file, lets ``setId`` load the cached parse (~0.2 s)
        % instead of re-scanning the CZI subblock directory (minutes over a network
        % share). Caller owns the returned handle (close via safeCloseReader).
        utils.ensureJavaLibraries({'bioformats'});
        loci.common.DebugTools.setRootLevel('ERROR');
        baseReader = bfGetReader();
        baseReader.setFlattenedResolutions(false);
        facadeMemo = fullfile(io.BioFormats.Config.memoDir(), 'bfFacade');
        if ~isfolder(facadeMemo)
            try
                mkdir(facadeMemo);
            catch  %#ok<CTCH>
            end
        end
        reader = loci.formats.Memoizer(baseReader, 0, java.io.File(facadeMemo));
        reader.setId(filename);
    end

    function safeCloseReader(~, reader)
        % SAFECLOSEREADER - close a shared Bio-Formats reader, ignoring errors.
        if isempty(reader); return; end
        try
            reader.close();
        catch  %#ok<CTCH>
        end
    end

    function [sceneIdx, sceneName, sceneLevel0] = enumeratePyramidScenes(~, br)
        % ENUMERATEPYRAMIDSCENES - list pyramid scenes (un-flattened series),
        % excluding associated images (macro/label/overview/thumbnail).
        % Returns 0-based series indices, names, and per-scene level-0 [Y X].
        % Operates on an already-open, un-flattened reader (caller owns lifetime).
        nS = double(br.getSeriesCount());
        sceneIdx = []; sceneName = {}; sceneLevel0 = [];
        for s = 0:nS-1
            br.setSeries(s);
            nR  = double(br.getResolutionCount());
            nm  = char(br.getMetadataStore().getImageName(s));
            isAssoc = ~isempty(regexpi(nm, 'label|macro|overview|thumbnail', 'once'));
            % a true scene: a pyramid (resolutions>1) OR a non-associated single image
            if nR > 1 || ~isAssoc
                br.setResolution(0);
                sceneIdx(end+1)      = s; %#ok<AGROW>
                sceneName{end+1}     = nm; %#ok<AGROW>
                sceneLevel0(end+1,:) = [double(br.getSizeY()), double(br.getSizeX())]; %#ok<AGROW>
            end
        end
    end

    function voxel = readVoxelSize(~, br, seriesIndex0)
        % READVOXELSIZE - OME physical voxel size [y x z] (um); defaults to 1.
        % Reads from the already-open reader's metadata store (caller owns lifetime).
        voxel = [1 1 1];
        try
            omeMeta = br.getMetadataStore();
            vx = omeMeta.getPixelsPhysicalSizeX(seriesIndex0);
            vy = omeMeta.getPixelsPhysicalSizeY(seriesIndex0);
            vz = omeMeta.getPixelsPhysicalSizeZ(seriesIndex0);
            if ~isempty(vx); voxel(2) = double(vx.value(ome.units.UNITS.MICROMETER)); end
            if ~isempty(vy); voxel(1) = double(vy.value(ome.units.UNITS.MICROMETER)); end
            if ~isempty(vz); voxel(3) = double(vz.value(ome.units.UNITS.MICROMETER)); end
        catch
        end
        if any(~isfinite(voxel)) || any(voxel <= 0); voxel = [1 1 1]; end
    end

    function lut = readLutColors(~, br, seriesIndex0, colors)
        % READLUTCOLORS - per-channel LUT colours [colors x 3] in 0..1 from OME
        % metadata (channel colour, or emission wavelength → RGB). Returns [] when
        % unavailable, so the caller keeps the default LUT. Mirrors the logic in
        % io.loaders.BioFormatsStdLoader.loadMetadata. Reads from the already-open
        % reader's metadata store (caller owns lifetime).
        lut = [];
        try
            omeMeta = br.getMetadataStore();
            if ~isempty(omeMeta.getChannelColor(seriesIndex0, 0))
                rgb = zeros(colors, 3);
                for colCh = 1:colors
                    col = omeMeta.getChannelColor(seriesIndex0, colCh - 1);
                    if isempty(col); continue; end
                    rgb(colCh, 1) = col.getRed();
                    rgb(colCh, 2) = col.getGreen();
                    rgb(colCh, 3) = col.getBlue();
                end
                lut = rgb / 255;
            elseif ~isempty(omeMeta.getChannelEmissionWavelength(seriesIndex0, 0))
                rgb = zeros(colors, 3);
                for colCh = 1:colors
                    wl = omeMeta.getChannelEmissionWavelength(seriesIndex0, colCh - 1);
                    if isempty(wl); continue; end
                    rgb(colCh, :) = io.BioFormats.wavelength2rgb(double(wl.value()));
                end
                lut = rgb / 255;
            end
        catch
            lut = [];
        end
        if ~isempty(lut)
            lut = max(0, min(1, lut));   % clamp to [0,1]
        end
    end
end
end
