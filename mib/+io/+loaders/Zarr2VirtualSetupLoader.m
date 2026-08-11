classdef Zarr2VirtualSetupLoader < io.loaders.BaseImageLoader
% ZARR2VIRTUALSETUPLOADER - Setup loader for OME-Zarr v2 datasets - handles all dataset modes.
%
% Metadata is parsed directly from the v2 JSON sidecar files
% (``.zattrs``/``.zgroup``/``.zarray``, pure MATLAB ``jsondecode`` - no engine
% involved just to discover shape/dtype/pyramid structure), while pixel data
% is read through ``io.zarr.Array``, so the engine follows ``io.zarr.Config``
% exactly as it does for v3. The bundled ``zarrMex`` reads zarr v2, so
% **python is optional**, needed only when the python backend is explicitly
% selected in ``Preferences -> Input/output -> Zarr library``.
%
% This loader runs ONCE when the user opens a zarr v2 file and handles all
% four MIB3 loading contexts:
%
% Standard : loadImages() prompts a pyramid level and loads it fully into
% memory as pixel data.
% Virtual : loadImages() returns the zarr root path only + pyramid
% metadata; pixels are read on demand by Zarr2VirtualLoader.
% BigData : identical to Virtual mode (image reads are pyramid-aware and
% on-demand either way; BigData additionally gets a disk-backed
% *editable* label pyramid, which MIB creates in whichever zarr
% format the store path asks for. An EXISTING labels array that
% MIB did not write is displayed read-only, via
% core.MibBigDataLabelsZarr2).
% Model : loadImages() loads the full labels array into memory (same
% full-array contract every MibDataset.loadModel loader uses),
% and resolves material names/colors from the store's metadata.
%
% The dataset mode is passed via options.datasetMode (set by LoaderFactory
% from loaderInfo.mode).
%
% Supported formats:
% - OME-Zarr v2 (.zattrs/.zgroup/.zarray metadata) - local folders and HTTP/HTTPS URLs
% - Single-array zarr v2 (no multiscales metadata) - treated as 1 level
% - Nested containers where the image group sits below the selected root, e.g.
%   the OpenOrganelle / MoBIE layout ``<name>.zarr/recon-1/em/fibsem-uint8`` or
%   an OME-Zarr label container. Local roots are searched recursively; when
%   several image groups are found the user picks one, and
%   ``options.ZarrGroupPath`` skips the dialog in batch mode.
%
% **Example 1** - Virtual mode (typical usage via MibModel.loadImages):
%
%   .. code-block:: matlab
%
%      opts.datasetMode = 'Virtual';
%      loader = io.loaders.Zarr2VirtualSetupLoader(opts);
%      [imginfo, files] = loader.loadMetadata({'C:\data\stack.zarr2'}, opts);
%      [img, imginfo] = loader.loadImages(files, imginfo, opts);
%      % img = {'C:\data\stack.zarr2'} and imginfo{"Pyramid"} holds the struct
%
% **Example 2** - Standard mode (prompts user to select pyramid level, returns pixel data):
%
%   .. code-block:: matlab
%
%      opts.datasetMode = 'Standard';
%      opts.ParentFigure = gcf;
%      loader = io.loaders.Zarr2VirtualSetupLoader(opts);
%      [imginfo, files] = loader.loadMetadata({'C:\data\stack.zarr2'}, opts);
%      [img, imginfo] = loader.loadImages(files, imginfo, opts);
%      % img{1} is a [y,x,z,c,t] uint16 array

methods
    function obj = Zarr2VirtualSetupLoader(options)
        % ZARR2VIRTUALSETUPLOADER - Create a setup loader for OME-Zarr v2 datasets.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      obj = Zarr2VirtualSetupLoader()
        %      obj = Zarr2VirtualSetupLoader(options)
        %
        % Input Arguments:
        %   - **options** - *(optional)* [struct] options including:
        %
        %     - ``.datasetMode`` - [char] ``'Standard'``, ``'Virtual'``, ``'BigData'``,
        %       or ``'Model'`` (set by LoaderFactory from loaderInfo.mode; default: ``'Virtual'``)
        %     - ``.ParentFigure`` - [handle] parent figure handle for dialogs
        %
        % Output Arguments:
        %   - **obj** - [Zarr2VirtualSetupLoader] new loader instance

        obj.Options = struct();
        obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);
        obj.Options.datasetMode = 'Virtual'; % safe default

        if nargin >= 1 && isstruct(options)
            obj.Options = obj.mergeOptions(obj.Options, options);
            obj.initBaseProps(options);
        end
    end

    function [imginfo, files] = loadMetadata(obj, filenames, options)
        % LOADMETADATA - Parse OME-Zarr v2 metadata from the zarr root.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [imginfo, files] = obj.loadMetadata(filenames, options)
        %
        % Confirms the selected zarr backend is usable (fails fast, once, at
        % open time - a no-op for the native engine, which has no external
        % dependency), then reads ``.zattrs``/``.zarray`` (works for local
        % paths and HTTP/HTTPS URLs).
        % Extracts pyramid levels, axis order, shapes, chunk sizes, and pixel
        % sizes from the OME-Zarr multiscales attribute. Falls back to a
        % single-level read if no multiscales found.
        %
        % Input Arguments:
        %   - **filenames** - [1x1 cell] path to the zarr root folder or URL
        %   - **options** - *(optional)* [struct] unused; present for interface compatibility
        %
        % Output Arguments:
        %   - **imginfo** - [dictionary] image metadata (Height, Width, Depth, etc.)
        %   - **files** - [struct] parsed metadata for use by loadImages

        if nargin < 3; options = struct(); end

        imginfo = core.MibImage.initializeImgInfo();
        rootPath = filenames{1};

        % ---- confirm the selected zarr backend is usable (fail fast, once) --
        % The native zarrMex engine reads zarr v2 with no external dependency,
        % local and remote alike, so there is nothing to check for it. Only the
        % opt-in python backend can fail before a single pixel is read, and it
        % is worth catching here rather than on the first slice the user
        % scrubs to.
        if io.zarr.Config.isPython()
            try
                io.zarr.PyBackend.ensureLoaded();
            catch ME
                errorMessage = sprintf(['Zarr2VirtualSetupLoader: cannot start the Python Zarr ' ...
                    'backend selected in Preferences -> Input/output -> Zarr library:\n%s\n' ...
                    'Switching that setting to ''native'' (zarrMex) reads zarr v2 without python.'], ...
                    ME.message);
                utils.dlgs.showErrorDialog(obj.Options.ParentFigure, errorMessage, ...
                    'io:Zarr2VirtualSetupLoader:pythonUnavailable', '', '');
                files = struct();
                return;
            end

            % A remote store needs two packages a local one does not. Reported
            % separately from the block above because python is running fine -
            % it just cannot reach the network - and the message says exactly
            % what to install.
            try
                io.zarr.PyBackend.ensureRemoteSupport(rootPath);
            catch ME
                utils.dlgs.showErrorDialog(obj.Options.ParentFigure, ME.message, ...
                    'Remote Zarr: missing Python packages', '', '');
                files = struct();
                return;
            end
        end

        isHttp = startsWith(rootPath, 'http://') || startsWith(rootPath, 'https://');

        % ---- root is itself a single array (no group) ---------------
        if isHttp
            rootIsArray = obj.tryHttpExists([strtrim(rootPath), '/.zarray']);
        else
            rootIsArray = isfile(fullfile(rootPath, '.zarray'));
        end
        if rootIsArray
            [files, imginfo] = obj.parseSingleArrayV2(rootPath, imginfo);
            return;
        end

        % ---- root is a group: read .zattrs for multiscales/labels ---
        attrs = obj.readZattrsV2(rootPath, isHttp);

        ms = io.loaders.OmeZarrMetadataUtils.extractMultiscales(attrs);
        if ~isempty(ms)
            [files, imginfo] = obj.parseMultiscalesV2(rootPath, ms, imginfo, options);
        else
            % multiscales not at root - containers nest the image group one or
            % more levels down (OME-Zarr label containers, and MoBIE /
            % OpenOrganelle stores such as <name>.zarr/recon-1/em/fibsem-uint8).
            [groupPath, cancelled] = obj.resolveMultiscalesGroupV2(rootPath, attrs, isHttp, options);
            if cancelled
                % user dismissed the group picker - abort quietly, loadImages
                % treats an empty files struct as "nothing to load"
                files = struct();
                return;
            end
            if isempty(groupPath)
                [files, imginfo] = obj.parseSingleArrayV2(rootPath, imginfo);
            else
                groupAttrs = obj.readZattrsV2(groupPath, isHttp);
                groupMs    = io.loaders.OmeZarrMetadataUtils.extractMultiscales(groupAttrs);
                if ~isempty(groupMs)
                    [files, imginfo] = obj.parseMultiscalesV2(groupPath, groupMs, imginfo, options);
                else
                    [files, imginfo] = obj.parseSingleArrayV2(groupPath, imginfo);
                end
            end
        end

        % ---- restore MIB bounding box if previously saved -------------------
        if isfield(attrs, 'mibBoundingBox') && numel(attrs.mibBoundingBox) == 6
            imginfo{"BoundingBox"} = reshape(double(attrs.mibBoundingBox), 1, 6);
        end

        % Every loader sets numEntries in loadMetadata (not loadImages) - it's
        % checked by core.MibDataset.loadModel right after loadMetadata returns,
        % before loadImages is ever called.
        imginfo{"numEntries"} = 1;
    end

    function [img, imginfo] = loadImages(obj, files, imginfo, options)
        % LOADIMAGES - Mode-dependent image/model setup for zarr v2 datasets.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [img, imginfo] = obj.loadImages(files, imginfo, options)
        %
        % Standard mode: prompts the user to select a pyramid level, then
        % loads the full level into memory as a [y,x,z,c,t] array.
        % Model mode: loads the full (level 0) array into memory and resolves
        % material names/colors from the store's metadata.
        % Virtual / BigData mode: returns the zarr root path and populates
        % imginfo{"Pyramid"} and imginfo{"Virtual"} for on-demand reading.
        %
        % Input Arguments:
        %   - **files** - [struct] from loadMetadata
        %   - **imginfo** - [dictionary] from loadMetadata
        %   - **options** - [struct] relevant field: ``.ParentFigure`` (for dialogs)
        %
        % Output Arguments:
        %   - **img** - Standard/Model mode: [1x1 cell] holding [y,x,z,c,t] numeric array;
        %     Virtual/BigData mode: [1x1 cell] holding the zarr root path string
        %   - **imginfo** - [dictionary] updated; Virtual mode adds ``"Pyramid"`` and
        %     ``"Virtual"`` keys; Model mode adds ``"numEntries"`` and, when found,
        %     ``"modelMaterialNames"``/``"modelMaterialColors"``

        if nargin < 4; options = struct(); end

        if isempty(fieldnames(files))
            % loadMetadata already reported the python-unavailable error
            img = {}; return;
        end

        mode = obj.Options.datasetMode;

        switch lower(mode)
            case 'standard'
                [img, imginfo] = obj.loadImagesStandardV2(files, imginfo, options);
            case 'model'
                [img, imginfo] = obj.loadImagesModelV2(files, imginfo, options);
            otherwise
                % Virtual or BigData
                [img, imginfo] = obj.loadImagesVirtualV2(files, imginfo);
        end
    end
end

%% Private helpers
methods (Access = private)

    function [files, imginfo] = parseMultiscalesV2(obj, rootPath, multiscales, imginfo, options)
        % PARSEMULTISCALESV2 - Parse OME-Zarr v2 multiscales metadata and populate files + imginfo.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [files, imginfo] = obj.parseMultiscalesV2(rootPath, multiscales, imginfo, options)
        %
        % ``options.Region`` crops the whole pyramid to a world sub-volume; see
        % :meth:`applyRequestedRegion`. Absent or empty, nothing about the parse
        % changes.

        if nargin < 5; options = struct(); end

        ms = multiscales(1); % use first multiscales entry
        isHttp = startsWith(rootPath, 'http://') || startsWith(rootPath, 'https://');

        % ---- axis order + y/x/z/c/t positions (version-agnostic) ----
        axisOrder  = io.loaders.OmeZarrMetadataUtils.extractAxisOrder(ms);
        axisLabels = io.loaders.OmeZarrMetadataUtils.axisOrderToLabels(axisOrder);
        yIdx = find(strcmp(axisLabels, 'y'), 1);
        xIdx = find(strcmp(axisLabels, 'x'), 1);
        zIdx = find(strcmp(axisLabels, 'z'), 1);
        cIdx = find(strcmp(axisLabels, 'c'), 1);
        tIdx = find(strcmp(axisLabels, 't'), 1);

        % ---- parse levels -------------------------------------------
        nLevels = numel(ms.datasets);

        levelNames             = cell(nLevels, 1);
        levelImageSizes        = zeros(nLevels, 3); % [y, x, z]
        levelImageTranslations = zeros(nLevels, 3);
        levelScaleFactors      = zeros(nLevels, 3);
        levelVoxelSizes        = zeros(nLevels, 3);
        levelWorldBoxes        = zeros(nLevels, 6);
        chunkSizes             = cell(nLevels, 1);
        shardSizes             = cell(nLevels, 1); % v2 has no sharding; mirrors chunkSizes

        % See Zarr3VirtualSetupLoader.parseMultiscales for the full
        % coordinateTransformation semantics - identical here (version-agnostic).
        globalScales = ones(1, numel(axisLabels));
        if isfield(ms, 'coordinateTransformations')
            globalScales = io.loaders.OmeZarrMetadataUtils.extractScaleFromCT(ms.coordinateTransformations, ...
                numel(axisLabels));
        end

        level0Scales = []; % filled on first level
        arrMeta = struct('dtype', 'u1'); % overwritten in the loop; fallback keeps dtype resolution safe

        levelPresent = true(nLevels, 1);

        for iLevel = 1:nLevels
            ds = ms.datasets(iLevel);
            levelNames{iLevel} = ds.path;

            if isHttp
                levelPath = [strtrim(rootPath), '/', ds.path];
            else
                levelPath = fullfile(rootPath, ds.path);
            end

            % multiscales may declare levels that were never written (or are
            % not present in a partial copy of the store) - drop them rather
            % than failing the whole dataset
            if ~isHttp && ~isfile(fullfile(levelPath, '.zarray'))
                levelPresent(iLevel) = false;
                continue;
            end

            arrMeta = obj.readZarrayV2(levelPath, isHttp);
            shape   = arrMeta.shape; % C-order: index matches axisLabels

            nY = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, yIdx, 1);
            nX = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, xIdx, 1);
            nZ = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, zIdx, 1);
            nC = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, cIdx, 1);
            nT = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, tIdx, 1);

            levelImageSizes(iLevel, :) = [nY, nX, nZ];

            levelScales = globalScales;
            if isfield(ds, 'coordinateTransformations')
                levelScales = io.loaders.OmeZarrMetadataUtils.extractScaleFromCT(ds.coordinateTransformations, ...
                    numel(axisLabels));
                levelScales = levelScales .* globalScales;
            end

            if isempty(level0Scales)
                % first level that is actually present defines the reference
                % resolution for every scale factor below
                level0Scales                 = levelScales;
                levelScaleFactors(iLevel, :) = [1, 1, 1];
            else
                sfY = io.loaders.OmeZarrMetadataUtils.safeRatio(levelScales, yIdx, level0Scales);
                sfX = io.loaders.OmeZarrMetadataUtils.safeRatio(levelScales, xIdx, level0Scales);
                sfZ = io.loaders.OmeZarrMetadataUtils.safeRatio(levelScales, zIdx, level0Scales);
                levelScaleFactors(iLevel, :) = [sfY, sfX, sfZ];
            end

            vY = io.loaders.OmeZarrMetadataUtils.safeGetScale(levelScales, yIdx, 1);
            vX = io.loaders.OmeZarrMetadataUtils.safeGetScale(levelScales, xIdx, 1);
            vZ = io.loaders.OmeZarrMetadataUtils.safeGetScale(levelScales, zIdx, 1);
            levelVoxelSizes(iLevel, :) = [vY, vX, vZ];

            % Where this level sits in the container's coordinate space. Needed
            % per level rather than only for level 0, because a region crop
            % intersects each level on its own grid.
            levelBox = io.loaders.OmeZarrMetadataUtils.worldBoundingBox(ms, iLevel, shape);
            if ~isempty(levelBox); levelWorldBoxes(iLevel, :) = levelBox; end

            chunkSizes{iLevel} = arrMeta.chunks;
            shardSizes{iLevel} = arrMeta.chunks; % no sharding concept in zarr v2
        end

        % ---- drop declared levels that are missing on disk ----------
        if ~any(levelPresent)
            errorMessage = sprintf(['Zarr2VirtualSetupLoader: none of the %d pyramid levels\n' ...
                'declared by the multiscales metadata exist in\n %s'], nLevels, rootPath);
            utils.dlgs.showErrorDialog(obj.ParentFigure, errorMessage, ...
                'io:Zarr2VirtualSetupLoader:noLevelsPresent', '', '');
            files = struct();
            return;
        end
        if ~all(levelPresent)
            levelNames             = levelNames(levelPresent);
            levelImageSizes        = levelImageSizes(levelPresent, :);
            levelImageTranslations = levelImageTranslations(levelPresent, :);
            levelScaleFactors      = levelScaleFactors(levelPresent, :);
            levelVoxelSizes        = levelVoxelSizes(levelPresent, :);
            levelWorldBoxes        = levelWorldBoxes(levelPresent, :);
            chunkSizes             = chunkSizes(levelPresent);
            shardSizes             = shardSizes(levelPresent);
            nLevels                = sum(levelPresent);
        end

        % ---- pixel size from level 0 physical scale -----------------
        pixSize         = utils.defaults.initializePixSize();
        pixSize.y       = io.loaders.OmeZarrMetadataUtils.safeGetScale(level0Scales, yIdx, 1);
        pixSize.x       = io.loaders.OmeZarrMetadataUtils.safeGetScale(level0Scales, xIdx, 1);
        pixSize.z       = io.loaders.OmeZarrMetadataUtils.safeGetScale(level0Scales, zIdx, 1);
        pixSize.units   = io.loaders.OmeZarrMetadataUtils.extractAxisUnit(ms, yIdx);

        % ---- optional crop to a requested world region ---------------
        % A literal no-op when no region was asked for - see
        % applyRequestedRegion, which returns the inputs untouched in that case.
        requestedRegion = io.loaders.OmeZarrMetadataUtils.resolveRegionOption(options, obj.Options);
        [levelImageSizes, levelRegionOrigins, levelWorldBoxes, regionReport] = ...
            io.loaders.OmeZarrMetadataUtils.applyRequestedRegion(requestedRegion, ...
                levelImageSizes, levelVoxelSizes, levelWorldBoxes, pixSize.units);

        % ---- world bounding box from the OME translation ------------
        % Where the group actually sits in the container's coordinate space.
        % Until now every foreign store landed at the origin, which is right for
        % a whole volume but wrong for anything cropped out of one - an
        % OpenOrganelle ground-truth crop, say. A store with no translation
        % still lands at the origin, so this changes nothing for them.
        % loadMetadata applies MIB's own mibBoundingBox after this, so a store
        % MIB wrote keeps winning.
        worldBoundingBox = levelWorldBoxes(1, :);
        imginfo{"BoundingBox"} = worldBoundingBox;

        % ---- populate imginfo from level 0 --------------------------
        imgClass = obj.zarrV2TypeToMatlabClass(arrMeta.dtype);
        imginfo{"Height"}    = levelImageSizes(1, 1);
        imginfo{"Width"}     = levelImageSizes(1, 2);
        imginfo{"Depth"}     = levelImageSizes(1, 3);
        imginfo{"Colors"}    = nC;
        imginfo{"Time"}      = nT;
        imginfo{"imgClass"}  = imgClass;
        imginfo{"MaxInt"}    = io.loaders.OmeZarrMetadataUtils.classMaxInt(imgClass);
        imginfo{"ColorType"} = io.loaders.OmeZarrMetadataUtils.colorType(nC);
        imginfo{"Filename"}  = rootPath;
        imginfo{"pixSize"}   = pixSize;
        imginfo{"viewPort"}  = io.loaders.OmeZarrMetadataUtils.buildViewPort(nC, imginfo{"MaxInt"});

        % ---- build files struct -------------------------------------
        files.filename               = rootPath;
        files.height                 = levelImageSizes(1, 1);
        files.width                  = levelImageSizes(1, 2);
        files.noLayers                = levelImageSizes(1, 3);
        files.color                  = nC;
        files.time                   = nT;
        files.imgClass               = imgClass;
        files.axisOrder              = axisOrder;
        files.nLevels                = nLevels;
        files.levelNames             = levelNames;
        files.levelImageSizes        = levelImageSizes;
        files.levelScaleFactors      = levelScaleFactors;
        files.levelVoxelSizes        = levelVoxelSizes;
        files.levelImageTranslations = levelImageTranslations;
        files.chunkSizes             = chunkSizes;
        files.shardSizes             = shardSizes;
        files.pixSize                = pixSize;
        files.worldBoundingBox       = worldBoundingBox;
        files.levelWorldBoxes        = levelWorldBoxes;
        files.levelRegionOrigins     = levelRegionOrigins;
        files.regionReport           = regionReport;
        files.multiscale             = ms;
    end

    function [files, imginfo] = parseSingleArrayV2(obj, rootPath, imginfo)
        % PARSESINGLEARRAYV2 - Fallback: read the root as a single zarr v2 array (no multiscales).
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [files, imginfo] = obj.parseSingleArrayV2(rootPath, imginfo)

        isHttp  = startsWith(rootPath, 'http://') || startsWith(rootPath, 'https://');
        arrMeta = obj.readZarrayV2(rootPath, isHttp);
        shape   = arrMeta.shape;
        nDims   = numel(shape);

        % infer axis order from number of dimensions (last N chars of 'tczyx')
        fullAxes  = 'tczyx';
        axisOrder = fullAxes(max(1, end-nDims+1) : end);

        axisLabels = num2cell(axisOrder);
        yIdx = find(strcmp(axisLabels, 'y'), 1);
        xIdx = find(strcmp(axisLabels, 'x'), 1);
        zIdx = find(strcmp(axisLabels, 'z'), 1);
        cIdx = find(strcmp(axisLabels, 'c'), 1);
        tIdx = find(strcmp(axisLabels, 't'), 1);

        nY = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, yIdx, 1);
        nX = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, xIdx, 1);
        nZ = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, zIdx, 1);
        nC = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, cIdx, 1);
        nT = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, tIdx, 1);

        imgClass = obj.zarrV2TypeToMatlabClass(arrMeta.dtype);
        pixSize  = utils.defaults.initializePixSize();

        imginfo{"Height"}    = nY;
        imginfo{"Width"}     = nX;
        imginfo{"Depth"}     = nZ;
        imginfo{"Colors"}    = nC;
        imginfo{"Time"}      = nT;
        imginfo{"imgClass"}  = imgClass;
        imginfo{"MaxInt"}    = io.loaders.OmeZarrMetadataUtils.classMaxInt(imgClass);
        imginfo{"ColorType"} = io.loaders.OmeZarrMetadataUtils.colorType(nC);
        imginfo{"Filename"}  = rootPath;
        imginfo{"pixSize"}   = pixSize;
        imginfo{"viewPort"}  = io.loaders.OmeZarrMetadataUtils.buildViewPort(nC, imginfo{"MaxInt"});

        files.filename                = rootPath;
        files.height                  = nY;
        files.width                   = nX;
        files.noLayers                = nZ;
        files.color                   = nC;
        files.time                    = nT;
        files.imgClass                = imgClass;
        files.axisOrder               = axisOrder;
        files.nLevels                 = 1;
        files.levelNames              = {''}; % empty = read from root
        files.levelImageSizes         = [nY, nX, nZ];
        files.levelScaleFactors       = [1, 1, 1];
        files.levelVoxelSizes         = [1, 1, 1];
        files.levelImageTranslations  = [0, 0, 0];
        files.chunkSizes              = {arrMeta.chunks};
        files.shardSizes              = {arrMeta.chunks};
        files.pixSize                 = pixSize;
        % A bare array carries no multiscales, hence no coordinateTransformations
        % and no place to sit other than the origin - and, with no world
        % coordinates, nothing a region could be expressed against either. The
        % fields exist so callers never have to test which parse produced the
        % struct.
        files.worldBoundingBox        = [];
        files.levelWorldBoxes         = zeros(1, 6);
        files.levelRegionOrigins      = [1, 1, 1];
        files.regionReport            = struct('requested', false, 'isExact', true, ...
                                               'residual', zeros(3, 2), 'message', '');
        files.multiscale              = [];
    end

    function [img, imginfo] = loadImagesStandardV2(obj, files, imginfo, options)
        % LOADIMAGESSTANDARDV2 - Standard-mode loadImages: prompt level selection, load pixels.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [img, imginfo] = obj.loadImagesStandardV2(files, imginfo, options)

        nLevels = files.nLevels;

        % ---- level selection dialog ---------------------------------
        % An explicit options.ZarrLevel skips it. That is not only a batch
        % convenience: when a region was requested to line this dataset up with
        % something else - a ground-truth crop and its labels - the level is
        % already determined by that pairing, and letting the user pick a
        % different one would silently break the match the caller just asserted.
        selectedLevel = 1;
        requestedLevel = io.loaders.OmeZarrMetadataUtils.resolveLevelOption( ...
            options, obj.Options, nLevels);
        if ~isempty(requestedLevel)
            selectedLevel = requestedLevel;
        elseif nLevels > 1
            labels = cell(nLevels, 1);
            for k = 1:nLevels
                sz = files.levelImageSizes(k, :);
                sf = files.levelScaleFactors(k, :);
                if k == 1
                    labels{k} = sprintf('Level %d: %d x %d x %d px [full resolution]', ...
                        k-1, sz(2), sz(1), sz(3));
                else
                    labels{k} = sprintf('Level %d: %d x %d x %d px [downscale x%.4g]', ...
                        k-1, sz(2), sz(1), sz(3), sf(1));
                end
            end

            dlgOpts = struct();
            dlgOpts.WindowWidth  = 460;
            dlgOpts.WindowHeight = 180;
            dlgOpts.LabelPosition = 'top';
            if isfield(options, 'mibPath'); dlgOpts.mibPath = options.mibPath; end
            [answer, selIndices] = utils.dlgs.inputUniversalDlg(options.ParentFigure, '',...
                {'Select pyramid level to load into memory:'}, ...
                {labels(:)', {1}}, ...
                'Zarr2: select resolution level', ...
                dlgOpts);
            if isempty(answer); img = {}; return; end
            selectedLevel = selIndices(1);
        end

        % ---- load selected level ------------------------------------
        fullPath = obj.buildLevelPath(files.filename, files.levelNames{selectedLevel});
        sz       = files.levelImageSizes(selectedLevel, :);

        raw = obj.readLevelRegionV2(fullPath, files, selectedLevel);

        % permute from zarr C-order to MIB3 [y,x,z,c,t]
        perm = io.loaders.OmeZarrMetadataUtils.computePermutation(files.axisOrder);
        data = permute(raw, perm);

        % MibImage only supports integer data types (intmax fails for
        % non-integer classes like single, double, logical).
        actualClass = class(data);
        intClasses  = {'uint8','uint16','uint32','uint64','int8','int16','int32','int64'};
        targetClass = files.imgClass;

        if ismember(actualClass, intClasses)
            if ~strcmp(actualClass, targetClass)
                data = cast(data, targetClass);
            end
        else
            % Non-integer (float32/float64 -> single/double, or logical).
            % Normalise to uint16 range based on actual data min/max.
            dlgTitle = 'Zarr2VirtualSetupLoader:nonIntToUint16';
            message  = sprintf(['Zarr data class is ''%s'' (non-integer); MIB standard mode requires integer data.\n' ...
                'Normalising to uint16 using actual data range [%g, %g]'], ...
                actualClass, double(min(data(:))), double(max(data(:))));
            options.MsgBoxOnly    = true;
            options.WindowHeight  = 150;
            options.Icon          = 'puffin_warning';
            utils.dlgs.inputUniversalDlg(options.ParentFigure, '', {message}, {message}, dlgTitle, options);

            dMin = double(min(data(:)));
            dMax = double(max(data(:)));
            if dMax > dMin
                data = uint16((double(data) - dMin) ./ (dMax - dMin) .* 65535);
            else
                data = zeros(size(data), 'uint16');
            end
            targetClass          = 'uint16';
            imginfo{"imgClass"}  = targetClass;
            imginfo{"MaxInt"}    = 65535;
        end

        imginfo{"Height"}   = sz(1);
        imginfo{"Width"}    = sz(2);
        imginfo{"Depth"}    = sz(3);
        imginfo{"viewPort"} = io.loaders.OmeZarrMetadataUtils.buildViewPort(files.color, imginfo{"MaxInt"});

        img = data; % bare numeric array; MibImage.initialize wraps it as obj.data
    end

    function [img, imginfo] = loadImagesModelV2(obj, files, imginfo, options) %#ok<INUSD>
        % LOADIMAGESMODELV2 - Model-mode loadImages: load the full labels array + material metadata.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [img, imginfo] = obj.loadImagesModelV2(files, imginfo, options)
        %
        % Always reads level 0 (the finest/only level) fully into memory -
        % models are always loaded whole, regardless of dataset mode, mirroring
        % every other MibDataset.loadModel loader. Material names/colors are
        % resolved from the store's metadata: MIB's own ``mibMaterials``
        % attribute first (the same one Zarr3Saver.exportModel /
        % MibBigDataLabels.writeMaterialMetadata write), then the OME-NGFF
        % ``image-label`` convention, else left empty so
        % core.MibDataset.loadModel auto-generates numbered names / a palette.

        levelPath = files.levelNames{1};
        fullPath  = obj.buildLevelPath(files.filename, levelPath);

        raw = obj.readLevelRegionV2(fullPath, files, 1);

        perm = io.loaders.OmeZarrMetadataUtils.computePermutation(files.axisOrder);
        img  = permute(raw, perm);

        [names, colors] = obj.readMaterialMetadataV2(files.filename, levelPath);
        if ~isempty(names);  imginfo{"modelMaterialNames"}  = names;  end
        if ~isempty(colors); imginfo{"modelMaterialColors"} = colors; end
    end

    function [img, imginfo] = loadImagesVirtualV2(~, files, imginfo)
        % LOADIMAGESVIRTUALV2 - Virtual/BigData-mode loadImages: return path + pyramid metadata.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [img, imginfo] = obj.loadImagesVirtualV2(files, imginfo)

        rootPath = files.filename;
        img      = {rootPath}; % path only; no pixel data loaded

        % ---- populate imginfo{"Pyramid"} ----------------------------
        Pyramid.levelNames             = files.levelNames;
        Pyramid.levelImageSizes        = files.levelImageSizes;
        Pyramid.levelImageTranslations = files.levelImageTranslations;
        Pyramid.levelScaleFactors      = files.levelScaleFactors;
        Pyramid.levelVoxelSizes        = files.levelVoxelSizes;
        % 1-based first voxel of the crop within each level's own array; all ones
        % when nothing was cropped, which readRegion treats as no offset.
        Pyramid.levelRegionOrigins     = files.levelRegionOrigins;
        Pyramid.chunkSizes             = files.chunkSizes;
        Pyramid.shardSizes             = files.shardSizes;
        Pyramid.axisOrder              = files.axisOrder;
        % Selects the Zarr2VirtualLoader branch in MibVirtualImage.getDataZarr
        % (default 'zarr3' otherwise). Both loaders now use the same engine, so
        % this records which format the store is in rather than which library
        % can open it.
        Pyramid.sourceType              = 'zarr2';
        imginfo{"Pyramid"} = Pyramid;

        % ---- populate imginfo{"Virtual"} ----------------------------
        % Required by MibVirtualImage.initialize() to wire up obj.Virtual.
        % objectType='zarr2' enables getOrCreateLoader to create Zarr2VirtualLoader.
        nZ                     = files.noLayers;
        Virtual.objectType     = {'zarr2'};
        Virtual.seriesName     = {''}; % unused for zarr2
        Virtual.slicesPerFile  = nZ;
        Virtual.filenames      = {rootPath};
        Virtual.readerId       = (1:nZ)'; % all slices map to file index 1
        Virtual.transMatrix    = {[]}; % unused for zarr2
        imginfo{"Virtual"} = Virtual;
    end

    % ---- v2-specific metadata I/O helpers ----------------------------

    function raw = readLevelRegionV2(~, fullPath, files, levelIndex)
        % READLEVELREGIONV2 - Read one whole pyramid level, honouring a region crop.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      raw = obj.readLevelRegionV2(fullPath, files, levelIndex)
        %
        % Used by the Standard and Model paths, which take a level in one go
        % rather than region by region.
        %
        % **Without a region this is the plain ``read()`` it replaced**, not a
        % full-extent bbox that happens to mean the same thing. A region touches
        % the read path of every zarr dataset MIB opens, and the overwhelming
        % majority will never ask for one, so the uncropped case has to stay the
        % identical call it always was rather than merely an equivalent one.
        %
        % Input Arguments:
        %   - **fullPath** - [char] path or URL of the level array
        %   - **files** - [struct] from loadMetadata
        %   - **levelIndex** - [numeric] 1-based pyramid level to read
        %
        % Output Arguments:
        %   - **raw** - numeric array in the store's own C-order layout

        zarrArray = io.zarr.Array(fullPath);

        if ~isfield(files, 'regionReport') || ~files.regionReport.requested
            raw = zarrArray.read();
            return;
        end

        bbox = io.loaders.OmeZarrMetadataUtils.levelRegionBbox(files.axisOrder, ...
            files.levelRegionOrigins(levelIndex, :), files.levelImageSizes(levelIndex, :), ...
            files.color, files.time);
        raw = zarrArray.read(bbox);
    end

    function fullPath = buildLevelPath(~, rootPath, levelPath)
        % BUILDLEVELPATH - Join a zarr root path and a relative level path (local or HTTP).
        if isempty(levelPath)
            fullPath = rootPath;
        elseif startsWith(rootPath, 'http://') || startsWith(rootPath, 'https://')
            fullPath = [strtrim(rootPath), '/', levelPath];
        else
            fullPath = fullfile(rootPath, levelPath);
        end
    end

    function tf = tryHttpExists(~, url)
        % TRYHTTPEXISTS - Best-effort check that a remote JSON sidecar file exists.
        tf = false;
        try
            webread(url, weboptions('ContentType', 'json', 'Timeout', 15));
            tf = true;
        catch
        end
    end

    function attrs = readZattrsV2(~, groupPath, isHttp)
        % READZATTRSV2 - Read a zarr v2 ``.zattrs`` sidecar (local or HTTP); '' -> empty struct.
        attrs = struct();
        try
            if isHttp
                attrs = webread([strtrim(groupPath), '/.zattrs'], weboptions('ContentType', 'json', 'Timeout', 30));
            else
                zattrsFile = fullfile(groupPath, '.zattrs');
                if isfile(zattrsFile)
                    attrs = jsondecode(fileread(zattrsFile));
                end
            end
        catch
            % missing/unreadable .zattrs -> treat as no attributes
        end
    end

    function arrMeta = readZarrayV2(obj, levelPath, isHttp)
        % READZARRAYV2 - Read a zarr v2 ``.zarray`` sidecar (local or HTTP).
        %
        % Returns a struct with ``.shape``, ``.chunks`` (numeric row vectors,
        % C-order) and ``.dtype`` (numpy typestring, e.g. ``'<u1'``).
        if isHttp
            raw = webread([strtrim(levelPath), '/.zarray'], weboptions('ContentType', 'json', 'Timeout', 30));
        else
            zarrayFile = fullfile(levelPath, '.zarray');
            if ~isfile(zarrayFile)
                errorMessage = sprintf('Zarr2VirtualSetupLoader: no .zarray found at\n %s', levelPath);
                utils.dlgs.showErrorDialog(obj.Options.ParentFigure, errorMessage, ...
                    'io:Zarr2VirtualSetupLoader:arrayMetaMissing', '', '');
            end
            raw = jsondecode(fileread(zarrayFile));
        end
        arrMeta.shape  = reshape(double(raw.shape), 1, []);
        arrMeta.chunks = reshape(double(raw.chunks), 1, []);
        arrMeta.dtype  = raw.dtype;
    end

    function [groupPath, cancelled] = resolveMultiscalesGroupV2(obj, rootPath, attrs, isHttp, options)
        % RESOLVEMULTISCALESGROUPV2 - Decide which nested group of a v2 container to open.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [groupPath, cancelled] = obj.resolveMultiscalesGroupV2(rootPath, attrs, isHttp, options)
        %
        % Called only when the root group itself carries no multiscales.
        % Resolution order:
        %
        %   1. An explicit ``options.ZarrGroupPath`` (relative to the root, or
        %      absolute) - lets batch mode open a nested group without a dialog.
        %   2. Local path: recursive search for every group with multiscales;
        %      one hit opens silently, several hits raise a picker.
        %   3. HTTP, or a local search that found nothing: the original
        %      single-level heuristic (``findMultiscalesSubPathV2``), which also
        %      covers sub-groups that are plain arrays without multiscales.
        %
        % Input Arguments:
        %   - **rootPath** - [char] container root path or URL
        %   - **attrs** - [struct] already-read root ``.zattrs``
        %   - **isHttp** - [logical] true when rootPath is a URL
        %   - **options** - [struct] loader options; ``.ZarrGroupPath`` honoured
        %
        % Output Arguments:
        %   - **groupPath** - [char] group to parse; ``''`` when none was found
        %   - **cancelled** - [logical] true when the user dismissed the picker

        cancelled = false;

        % ---- 1. explicit override (batch mode) --------------------------
        requestedGroup = '';
        if isstruct(options) && isfield(options, 'ZarrGroupPath')
            requestedGroup = char(options.ZarrGroupPath);
        elseif isfield(obj.Options, 'ZarrGroupPath')
            requestedGroup = char(obj.Options.ZarrGroupPath);
        end
        if ~isempty(requestedGroup)
            if isHttp
                % join() takes a relative group path as well as an absolute URL,
                % so a batch protocol can carry the short readable form
                % ('recon-1/em/fibsem-uint8') rather than the whole URL again.
                groupPath = io.RemoteStore.join(rootPath, requestedGroup);
            elseif isfolder(requestedGroup)
                groupPath = requestedGroup;
            else
                groupPath = fullfile(rootPath, requestedGroup);
            end
            return;
        end

        % ---- 2. containers: recursive search ----------------------------
        % Runs for local roots and for remote roots on a listable (S3) host;
        % the remote walk stops at the shallowest level that matches.
        candidates = io.loaders.OmeZarrMetadataUtils.findMultiscalesGroups(rootPath, 2);
        if ~isempty(candidates)
            groupPath = io.loaders.OmeZarrMetadataUtils.selectMultiscalesGroup(...
                rootPath, candidates, obj.ParentFigure, ...
                'Zarr2: select image group');
            cancelled = isempty(groupPath);
            return;
        end

        % ---- 3. fallback: original single-level heuristic ---------------
        % Still the only option for an HTTP host with no directory listing.
        groupPath = obj.findMultiscalesSubPathV2(rootPath, attrs, isHttp);
    end

    function subPath = findMultiscalesSubPathV2(~, rootPath, attrs, isHttp)
        % FINDMULTISCALESSUBPATHV2 - Find the sub-group path most likely to contain multiscales.
        %
        % Strategy (in order):
        %
        %   1. OME-Zarr label container: attrs.labels lists sub-group names.
        %   2. Local path: list sub-directories directly (pure MATLAB dir()).
        %   3. HTTP path fallback: probe a handful of common sub-path names.
        %
        % Returns ``''`` if nothing useful is found.

        subPath = '';

        if isHttp
            if endsWith(rootPath, '/')
                joinFn = @(base, name) [base, name];
            else
                joinFn = @(base, name) [base, '/', name];
            end
        else
            joinFn = @(base, name) fullfile(base, name);
        end

        % 1. OME-Zarr label container format: attrs.labels = {"name", ...}
        if isfield(attrs, 'labels') && ~isempty(attrs.labels)
            labels = attrs.labels;
            if iscell(labels) && ~isempty(labels)
                firstName = char(labels{1});
            elseif ischar(labels) || isstring(labels)
                firstName = char(labels);
            else
                firstName = '';
            end
            if ~isempty(firstName)
                subPath = joinFn(rootPath, firstName);
                return;
            end
        end

        % 2. Local path: list sub-directories directly
        if ~isHttp
            try
                items = dir(rootPath);
                items = items([items.isdir] & ~ismember({items.name}, {'.', '..'}));
                if ~isempty(items)
                    subPath = joinFn(rootPath, items(1).name);
                    return;
                end
            catch
            end
        end

        % 3. HTTP fallback: probe common sub-path names via .zgroup
        if isHttp
            for candidateName = {'0', '1', 's0', 's1', 'cells', 'nuclei'}
                candidate = joinFn(rootPath, candidateName{1});
                try
                    meta = webread([candidate, '/.zgroup'], weboptions('ContentType', 'json', 'Timeout', 15));
                    if isfield(meta, 'zarr_format')
                        subPath = candidate;
                        return;
                    end
                catch
                end
            end
        end
    end

    function [names, colors] = readMaterialMetadataV2(obj, rootPath, levelPath)
        % READMATERIALMETADATAV2 - Resolve model material names/colors from store metadata.
        %
        % Fetches the v2 ``.zattrs`` sidecars (root group and, if present, the
        % array level - level-array attributes take precedence on key
        % collisions) and delegates the actual name/color extraction to the
        % version-agnostic ``io.loaders.OmeZarrMetadataUtils.resolveMaterialMetadata``
        % (shared with ``Zarr3VirtualSetupLoader`` and ``core.MibBigDataLabelsZarr2``).
        % Returns empty when neither the ``mibMaterials`` nor OME-NGFF
        % ``image-label`` convention is present; the caller
        % (core.MibDataset.loadModel) already auto-generates numbered names /
        % a color palette in that case.

        isHttp = startsWith(rootPath, 'http://') || startsWith(rootPath, 'https://');
        attrs  = obj.readZattrsV2(rootPath, isHttp);

        if ~isempty(levelPath)
            levelRoot  = obj.buildLevelPath(rootPath, levelPath);
            levelAttrs = obj.readZattrsV2(levelRoot, isHttp);
            fn = fieldnames(levelAttrs);
            for k = 1:numel(fn)
                attrs.(fn{k}) = levelAttrs.(fn{k});
            end
        end

        [names, colors] = io.loaders.OmeZarrMetadataUtils.resolveMaterialMetadata(attrs);
    end
end

%% Static utility helpers
% Public because the dialog that previews a remote store before opening it
% (controllers.SelectFromUrl) has to report the same data type this loader will
% produce - duplicating the table there would let the two drift apart.
methods (Static)

    function matlabClass = zarrV2TypeToMatlabClass(zarrType)
        % ZARRV2TYPETOMATLABCLASS - Convert a zarr v2 numpy typestring to a MATLAB class string.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      matlabClass = obj.zarrV2TypeToMatlabClass(zarrType)
        %
        % Strips the endian marker (``<``/``>``/``|``) and maps the numpy
        % single-character-code + byte-width typestring (e.g. ``'u1'``,
        % ``'f4'``) to a MATLAB class, mirroring MIB2's readZarrMetadata.m.

        t = erase(char(zarrType), {'<', '>', '|', '='});
        switch t
            case 'u1'; matlabClass = 'uint8';
            case 'u2'; matlabClass = 'uint16';
            case 'u4'; matlabClass = 'uint32';
            case 'u8'; matlabClass = 'uint64';
            case 'i1'; matlabClass = 'int8';
            case 'i2'; matlabClass = 'int16';
            case 'i4'; matlabClass = 'int32';
            case 'i8'; matlabClass = 'int64';
            case 'f4'; matlabClass = 'single';
            case 'f8'; matlabClass = 'double';
            case 'b1'; matlabClass = 'uint8';
            otherwise
                matlabClass = t; % best-effort fallback
        end
    end

end
end
