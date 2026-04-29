classdef Zarr3VirtualSetupLoader < io.loaders.BaseImageLoader
% ZARR3VIRTUALSETUPLOADER - Setup loader for OME-Zarr v3 datasets — handles all dataset modes.
%
% This loader runs ONCE when the user opens a .zarr3 file and handles
% all three MIB3 dataset modes:
%
% Standard : loadImages() loads the full selected pyramid level into
% memory and returns pixel data.
% Virtual  : loadImages() returns the zarr root path only + pyramid
% metadata; pixels are read on demand by Zarr3VirtualLoader.
% BigData  : identical to Virtual mode.
%
% The dataset mode is passed via options.datasetMode (set by LoaderFactory
% from loaderInfo.mode).
%
% **Relationship to Zarr3VirtualLoader**
%
% Zarr3VirtualSetupLoader  — runs ONCE when the user opens a file.
% Phase   : dataset initialisation (MibModel.loadImages)
% Job     : parse OME-Zarr metadata, build pyramid struct, return path.
% Reads pixels? Yes (Standard mode) / No (Virtual/BigData mode).
% Lifetime: discarded after open; implements BaseImageLoader.
% Created by: LoaderFactory (case "OmeZarr")
%
% Zarr3VirtualLoader  — runs on EVERY slice request during the session.
% Phase   : on-demand pixel reading (MibVirtualImage.getDataZarr)
% Job     : read sub-region via ZarrArray.read(bbox).
% Reads pixels? Yes.
% Lifetime: cached in MibVirtualImage.loaders{1} for the session.
% Created by: MibVirtualImage.getDataZarr / getOrCreateLoader
%
%
% Supported formats:
% - OME-Zarr v3 (zarr.json metadata) — local folders and HTTP/HTTPS URLs
% - Single-array zarr v3 (no multiscales metadata) — treated as 1 level
% - NOT zarr v2 (.zattrs / .zgroup) — clear error message is shown
%
% Usage examples:
%
% .. code-block:: matlab
%
%   % Virtual mode (typical usage via MibModel.loadImages)
%   opts.datasetMode = 'Virtual';
%   loader = io.loaders.Zarr3VirtualSetupLoader(opts);
%   [imginfo, files] = loader.loadMetadata({'C:\data\stack.zarr3'}, opts);
%   [img, imginfo]   = loader.loadImages(files, imginfo, opts);
%   % img = {'C:\data\stack.zarr3'} and imginfo{"Pyramid"} holds the struct
%
%
%
% .. code-block:: matlab
%
%   % Standard mode — prompts user to select pyramid level, returns pixel data
%   opts.datasetMode  = 'Standard';
%   opts.ParentFigure = gcf;
%   loader = io.loaders.Zarr3VirtualSetupLoader(opts);
%   [imginfo, files] = loader.loadMetadata({'C:\data\stack.zarr3'}, opts);
%   [img, imginfo]   = loader.loadImages(files, imginfo, opts);
%   % img{1} is a [y,x,z,c,t] uint16 array

    methods
        function obj = Zarr3VirtualSetupLoader(options)
            % ZARR3VIRTUALSETUPLOADER - obj = Zarr3VirtualSetupLoader(options).
            %
            % Syntax:
            %   function obj = Zarr3VirtualSetupLoader(options)
            %
            % Constructor
            %
            % Input Arguments:
            %   - **options** — [*optional,* struct] options including:
            %
            %     - ``.datasetMode`` — [char] ``'Standard'``, ``'Virtual'``, or ``'BigData'``
            %       (set by LoaderFactory from loaderInfo.mode)
            %     - ``.ParentFigure`` — handle to parent figure for dialogs
            %

            obj.Options = struct();
            obj.Options.Font = struct('FontName', 'Helvetica', 'FontSize', 12);
            obj.Options.datasetMode = 'Virtual';   % safe default

            if nargin >= 1 && isstruct(options)
                obj.Options = obj.mergeOptions(obj.Options, options);
                obj.initBaseProps(options);
            end
        end

        function [imginfo, files] = loadMetadata(obj, filenames, options) %#ok<INUSD>
            % LOADMETADATA - [imginfo, files] = loadMetadata(obj, filenames, options).
            %
            % Syntax:
            %   function [imginfo, files] = loadMetadata(obj, filenames, options) %#ok<INUSD>
            %
            % Parse OME-Zarr v3 metadata from the zarr root.
            %
            % Reads zarr.json via ZarrGroup / ZarrNode (works for local paths
            % and HTTP/HTTPS URLs).  Extracts pyramid levels, axis order, shapes,
            % chunk/shard sizes, and pixel sizes from the OME-Zarr multiscales
            % attribute.  Falls back to single-level if no multiscales found.
            %
            % Input Arguments:
            %   - **filenames** — {1 x 1} cell — path to the zarr root folder or URL
            %   - **options** — (unused; present for interface compatibility)
            %
            % Output Arguments:
            %   - **imginfo** — dictionary with image metadata (Height, Width, Depth, etc.)
            %   - **files** — struct with parsed metadata for use by loadImages
            %
            % Usage:
            %   Example 1::
            %
            %     loader  = io.loaders.Zarr3VirtualSetupLoader();
            %     [info, files] = loader.loadMetadata({'C:\data\vol.zarr3'}, struct());
            %     fprintf('Height=%d  Width=%d  Depth=%d\n', ...
            %         info{"Height"}, info{"Width"}, info{"Depth"});
            %

            imginfo  = core.MibImage.initializeImgInfo();
            rootPath = filenames{1};

            % ---- zarr v2 detection (local paths only) --------------------
            if ~(startsWith(rootPath, 'http://') || startsWith(rootPath, 'https://'))
                if ~isfile(fullfile(rootPath, 'zarr.json'))
                    if isfile(fullfile(rootPath, '.zattrs')) || ...
                            isfile(fullfile(rootPath, '.zgroup'))

                        errorMessage = sprintf(['Zarr3VirtualSetupLoader: zarr v2 format detected at\n'
                                                '  %s\n(.zattrs / .zgroup found, but no zarr.json)\n\n' ...
                                                'Only zarr v3 is supported by the Zarr3Matlab library.\n' ...
                                                'Please convert the dataset to zarr v3 and try again.'], rootPath);
                        utils.dlgs.showErrorDialog(obj.Options.ParentFigure, errorMessage, 'io:Zarr3VirtualSetupLoader:zarr2Detected', '', '');
                    end
                end
            end

            % ---- fetch zarr.json directly to get the full metadata tree -----
            % getAttributes() only returns the "attributes" sub-key, but some
            % OME-NGFF versions put multiscales at other levels.  We fetch the
            % raw JSON ourselves so we can search the whole tree.
            isHttp = startsWith(rootPath, 'http://') || startsWith(rootPath, 'https://');
            try
                if isHttp
                    jsonUrl = [strtrim(rootPath), '/zarr.json'];
                    rawMeta = webread(jsonUrl, weboptions('ContentType', 'json', 'Timeout', 30));
                else
                    rawMeta = jsondecode(fileread(fullfile(rootPath, 'zarr.json')));
                end
            catch ME
                errorMessage = sprintf('Zarr3VirtualSetupLoader: cannot read zarr.json at\n  %s\n%s', rootPath, ME.message);
                utils.dlgs.showErrorDialog(obj.Options.ParentFigure, errorMessage, 'io:Zarr3VirtualSetupLoader:openFailed', '', '');
            end

            % Keep ZarrGroup open for listContents() (local paths only)
            grp = [];
            if ~isHttp
                try; grp = ZarrGroup(rootPath); catch; end
            end

            % attrs = rawMeta.attributes (or empty struct if absent)
            if isfield(rawMeta, 'attributes') && isstruct(rawMeta.attributes)
                attrs = rawMeta.attributes;
            else
                attrs = struct();
            end

            % ---- extract multiscales — search the whole JSON tree ----------
            % Locations tried (in order):
            %   1. attrs.multiscales          (OME-NGFF v0.4)
            %   2. attrs.ome.multiscales      (OME-NGFF v0.5)
            %   3. rawMeta.multiscales        (non-standard: top-level in zarr.json)
            ms = obj.extractMultiscales(attrs);
            if isempty(ms) && isfield(rawMeta, 'multiscales') && ~isempty(rawMeta.multiscales)
                ms = rawMeta.multiscales;
            end

            % ---- parse or search one level deeper --------------------------
            if ~isempty(ms)
                [files, imginfo] = obj.parseMultiscales(rootPath, ms, imginfo);
            else
                % multiscales not at root — common in OME-Zarr label containers
                % where root has "labels": ["name"] and multiscales is one level down.
                subPath = obj.findMultiscalesSubPath(rootPath, attrs, grp);
                if ~isempty(subPath)
                    subMs = [];
                    try
                        % Fetch sub-group zarr.json directly — works for both
                        % local paths and HTTP, and handles arrays vs groups
                        if isHttp
                            subRaw = webread([strtrim(subPath), '/zarr.json'], ...
                                weboptions('ContentType','json','Timeout',30));
                        else
                            subRaw = jsondecode(fileread(fullfile(subPath, 'zarr.json')));
                        end
                        subAttrs = struct();
                        if isfield(subRaw, 'attributes') && isstruct(subRaw.attributes)
                            subAttrs = subRaw.attributes;
                        end
                        subMs = obj.extractMultiscales(subAttrs);
                        if isempty(subMs) && isfield(subRaw, 'multiscales')
                            subMs = subRaw.multiscales;
                        end
                    catch
                    end
                    if ~isempty(subMs)
                        [files, imginfo] = obj.parseMultiscales(subPath, subMs, imginfo);
                    else
                        [files, imginfo] = obj.parseSingleArray(subPath, imginfo);
                    end
                else
                    % Could not locate multiscales — display zarr.json to help diagnose
                    fprintf('Zarr3VirtualSetupLoader: zarr.json content for debugging:\n%s\n', ...
                        jsonencode(rawMeta));
                    [files, imginfo] = obj.parseSingleArray(rootPath, imginfo);
                end
            end
        end

        function [img, imginfo] = loadImages(obj, files, imginfo, options)
            % LOADIMAGES - [img, imginfo] = loadImages(obj, files, imginfo, options).
            %
            % Syntax:
            %   function [img, imginfo] = loadImages(obj, files, imginfo, options)
            %
            % Mode-dependent image setup.
            %
            % Standard mode: prompts the user to select a pyramid level, then
            % loads the full level into memory as a [y,x,z,c,t] array.
            % Virtual / BigData mode: returns the zarr root path and populates
            % imginfo{"Pyramid"} and imginfo{"Virtual"} for on-demand reading.
            %
            % Input Arguments:
            %   - **files** — struct from loadMetadata
            %   - **imginfo** — dictionary from loadMetadata
            %   - **options** — struct; relevant field: .ParentFigure (for dialogs)
            %
            % Output Arguments:
            %   - **img** — Standard mode — {1 x 1} cell holding [y,x,z,c,t] array.
            %     Virtual/BigData mode — {1 x 1} cell holding root path.
            %   - **imginfo** — updated dictionary; Virtual mode adds "Pyramid" and "Virtual"
            %
            % Usage:
            %   Example 1 - img = {'C:\data\vol.zarr3'}, info{"Pyramid"}.levelNames = {'0','1',...}::
            %
            %     opts.datasetMode  = 'Virtual';
            %     loader = io.loaders.Zarr3VirtualSetupLoader(opts);
            %     [info, f] = loader.loadMetadata({'C:\data\vol.zarr3'}, opts);
            %     [img, info] = loader.loadImages(f, info, opts);
            %     % img = {'C:\data\vol.zarr3'}, info{"Pyramid"}.levelNames = {'0','1',...}
            %

            if nargin < 4; options = struct(); end

            mode = obj.Options.datasetMode;

            if strcmpi(mode, 'Standard')
                [img, imginfo] = obj.loadImagesStandard(files, imginfo, options);
            else
                % Virtual or BigData
                [img, imginfo] = obj.loadImagesVirtual(files, imginfo);
            end
        end
    end

    %% Private helpers
    methods (Access = private)

        function [files, imginfo] = parseMultiscales(obj, rootPath, multiscales, imginfo)
            % PARSEMULTISCALES - Parse OME-Zarr multiscales metadata and populate files + imginfo.
            %
            % Syntax:
            %   function [files, imginfo] = parseMultiscales(obj, rootPath, multiscales, imginfo)
            %

            ms = multiscales(1);   % use first multiscales entry

            % ---- axis order ---------------------------------------------
            axisOrder = obj.extractAxisOrder(ms);

            % ---- find y/x/z/c/t positions in the C-order axis list ------
            axisLabels = obj.axisOrderToLabels(axisOrder);  % cell array of chars
            yIdx = find(strcmp(axisLabels, 'y'), 1);
            xIdx = find(strcmp(axisLabels, 'x'), 1);
            zIdx = find(strcmp(axisLabels, 'z'), 1);
            cIdx = find(strcmp(axisLabels, 'c'), 1);
            tIdx = find(strcmp(axisLabels, 't'), 1);

            % ---- parse levels -------------------------------------------
            nLevels = numel(ms.datasets);

            levelNames             = cell(nLevels, 1);
            levelImageSizes        = zeros(nLevels, 3);   % [y, x, z]
            levelImageTranslations = zeros(nLevels, 3);
            levelScaleFactors      = zeros(nLevels, 3);
            levelVoxelSizes        = zeros(nLevels, 3);
            chunkSizes             = cell(nLevels, 1);
            shardSizes             = cell(nLevels, 1);

            % **Coordinate transformation semantics**
            %
            % globalScales  [1 x nAxes] — top-level coordinateTransformations
            %   on the multiscales object (OME-NGFF v0.5 pattern).
            %   Represents a common physical unit multiplier applied to ALL
            %   pyramid levels before the per-level scale.
            %   Axis order matches axisLabels, e.g. for 'tczyx':
            %     globalScales = [t_fac, c_fac, z_fac, y_fac, x_fac]
            %   In OME-NGFF v0.4 datasets (no top-level CT) this stays ones.
            %
            % levelScales   [1 x nAxes] — per-dataset coordinateTransformations
            %   giving the ABSOLUTE physical voxel size at this pyramid level
            %   after multiplying with globalScales.
            %   For a 'tczyx' dataset: [t_s, c_s, z_s, y_s, x_s] where y_s/x_s
            %   double with each downsampled level, z_s is usually constant.
            %   Indexed via yIdx/xIdx/zIdx so safeRatio/safeGetScale always
            %   pick the correct element regardless of axis count or order.
            %
            % level0Scales  — levelScales of the first (full-resolution) level.
            %   Used as the reference for computing relative levelScaleFactors.
            %
            % levelScaleFactors [nLevels x 3, columns y/x/z] — ratio of each
            %   level's physical voxel size to level 0.  Level 0 = [1,1,1].
            %   Used by getDataZarr to pick the best pyramid level for the
            %   current display magnification (magFactor).

            % global scale from top-level coordinateTransformations (OME-Zarr v0.5)
            globalScales = ones(1, numel(axisLabels));
            if isfield(ms, 'coordinateTransformations')
                globalScales = obj.extractScaleFromCT(ms.coordinateTransformations, ...
                    numel(axisLabels));
            end

            level0Scales = [];   % filled on first level

            for iLevel = 1:nLevels
                ds = ms.datasets(iLevel);

                % level path (e.g. '0', '1', '2' or 's0', 's1', ...)
                levelNames{iLevel} = ds.path;

                % open array and read info
                if startsWith(rootPath, 'http://') || startsWith(rootPath, 'https://')
                    levelPath = [strtrim(rootPath), '/', ds.path];
                else
                    levelPath = fullfile(rootPath, ds.path);
                end

                try
                    arr     = ZarrArray(levelPath);
                    arrInfo = arr.info();
                catch ME
                    errorMessage = sprintf('Zarr3VirtualSetupLoader: cannot open level "%s":\n  %s', ds.path, ME.message);
                    utils.dlgs.showErrorDialog(obj.Options.ParentFigure, errorMessage, 'io:Zarr3VirtualSetupLoader:arrayOpenFailed', '', '');
                end

                % shape is declared in C-order (Python): index matches axisLabels
                shape = arrInfo.shape;   % [nT, nC, nZ, nY, nX] for 'tczyx'

                nY = obj.safeGetDim(shape, yIdx, 1);
                nX = obj.safeGetDim(shape, xIdx, 1);
                nZ = obj.safeGetDim(shape, zIdx, 1);
                nC = obj.safeGetDim(shape, cIdx, 1);
                nT = obj.safeGetDim(shape, tIdx, 1);

                levelImageSizes(iLevel, :) = [nY, nX, nZ];

                % levelScales: absolute physical voxel sizes at this pyramid level.
                % Axis order matches axisLabels (C-order), e.g. for 'tczyx':
                %   levelScales = [t_scale, c_scale, z_scale, y_scale, x_scale]
                % For OME-NGFF v0.4: levelScales from per-dataset CT directly.
                % For OME-NGFF v0.5: per-dataset CT is a relative factor; multiply
                %   by globalScales to get the absolute physical size.
                levelScales = globalScales;
                if isfield(ds, 'coordinateTransformations')
                    levelScales = obj.extractScaleFromCT(ds.coordinateTransformations, ...
                        numel(axisLabels));
                    % combine per-level relative scale with global base scale
                    levelScales = levelScales .* globalScales;
                end

                if iLevel == 1
                    level0Scales = levelScales;
                    levelScaleFactors(1, :) = [1, 1, 1];
                else
                    % levelScaleFactors = ratio of this level's voxel size to
                    % level 0 (full resolution). E.g. level 1 with 2× downsampling
                    % in Y and X gives sfY=2, sfX=2, sfZ=1.
                    sfY = obj.safeRatio(levelScales, yIdx, level0Scales);
                    sfX = obj.safeRatio(levelScales, xIdx, level0Scales);
                    sfZ = obj.safeRatio(levelScales, zIdx, level0Scales);
                    levelScaleFactors(iLevel, :) = [sfY, sfX, sfZ];
                end

                % absolute voxel sizes in physical units (always from level 0)
                vY = obj.safeGetScale(level0Scales, yIdx, 1);
                vX = obj.safeGetScale(level0Scales, xIdx, 1);
                vZ = obj.safeGetScale(level0Scales, zIdx, 1);
                levelVoxelSizes(iLevel, :) = [vY, vX, vZ];

                % chunk / shard sizes (in C-order, as stored)
                chunkSizes{iLevel} = arrInfo.chunkShape;
                shardSizes{iLevel} = arrInfo.shardShape;
            end

            % ---- pixel size from level 0 physical scale -----------------
            pixSize = utils.defaults.initializePixSize();
            pixSize.y = obj.safeGetScale(level0Scales, yIdx, 1);
            pixSize.x = obj.safeGetScale(level0Scales, xIdx, 1);
            pixSize.z = obj.safeGetScale(level0Scales, zIdx, 1);
            pixSize.units = obj.extractAxisUnit(ms, yIdx);

            % ---- populate imginfo from level 0 --------------------------
            imginfo{"Height"}     = levelImageSizes(1, 1);
            imginfo{"Width"}      = levelImageSizes(1, 2);
            imginfo{"Depth"}      = levelImageSizes(1, 3);
            imginfo{"Colors"}     = nC;
            imginfo{"Time"}       = nT;
            imginfo{"imgClass"}   = obj.zarrTypeToMatlabClass(arrInfo.dataType);
            imginfo{"MaxInt"}     = obj.classMaxInt(imginfo{"imgClass"});
            imginfo{"ColorType"}  = obj.colorType(nC);
            imginfo{"Filename"}   = rootPath;
            imginfo{"pixSize"}    = pixSize;
            imginfo{"viewPort"}   = obj.buildViewPort(nC, imginfo{"MaxInt"});

            % ---- build files struct -------------------------------------
            files.filename             = rootPath;
            files.height               = levelImageSizes(1, 1);
            files.width                = levelImageSizes(1, 2);
            files.noLayers             = levelImageSizes(1, 3);
            files.color                = nC;
            files.time                 = nT;
            files.imgClass             = imginfo{"imgClass"};
            files.axisOrder            = axisOrder;
            files.nLevels              = nLevels;
            files.levelNames           = levelNames;
            files.levelImageSizes      = levelImageSizes;
            files.levelScaleFactors    = levelScaleFactors;
            files.levelVoxelSizes      = levelVoxelSizes;
            files.levelImageTranslations = levelImageTranslations;
            files.chunkSizes           = chunkSizes;
            files.shardSizes           = shardSizes;
            files.pixSize              = pixSize;
        end

        function ms = extractMultiscales(~, attrs)
            % EXTRACTMULTISCALES - Extract the multiscales array from zarr attributes.
            %
            % Syntax:
            %   function ms = extractMultiscales(~, attrs)
            %
            % Handles two OME-NGFF versions:
            % v0.4: attrs.multiscales  (top-level)
            % v0.5: attrs.ome.multiscales  (nested under "ome" namespace)
            %
            % Returns the multiscales struct array, or [] if not found.

            ms = [];
            if isfield(attrs, 'multiscales') && ~isempty(attrs.multiscales)
                ms = attrs.multiscales;
            elseif isfield(attrs, 'ome') && isstruct(attrs.ome) && ...
                    isfield(attrs.ome, 'multiscales') && ~isempty(attrs.ome.multiscales)
                ms = attrs.ome.multiscales;
            end
        end

        function subPath = findMultiscalesSubPath(~, rootPath, attrs, grp)
            % FINDMULTISCALESSUBPATH - Find the sub-group path most likely to contain multiscales.
            %
            % Syntax:
            %   function subPath = findMultiscalesSubPath(~, rootPath, attrs, grp)
            %
            % Strategy (in order):
            % 1. OME-Zarr label container: attrs.labels lists sub-group names.
            % 2. Local path: use listContents() to find the first sub-group.
            % 3. HTTP path fallback: try the sub-path '0' (common convention).
            %
            % Returns '' if nothing useful is found.

            subPath = '';
            isHttp  = startsWith(rootPath, 'http://') || startsWith(rootPath, 'https://');

            % Local helper: join zarr path components (HTTP or filesystem)
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

            % 2. Local path: list sub-groups via listContents()
            if ~isHttp && ~isempty(grp)
                try
                    [subGroups, ~] = grp.listContents();
                    if ~isempty(subGroups)
                        subPath = joinFn(rootPath, subGroups{1});
                        return;
                    end
                catch
                end
            end

            % 3. HTTP fallback: probe common sub-path names by fetching zarr.json
            % directly (ZarrGroup() is not used here since it fails for arrays).
            if isHttp
                for candidateName = {'0', '1', 's0', 's1', 'cells', 'nuclei'}
                    candidate = joinFn(rootPath, candidateName{1});
                    try
                        meta = webread([candidate, '/zarr.json'], ...
                            weboptions('ContentType','json','Timeout',15));
                        if isfield(meta, 'node_type') && strcmp(meta.node_type, 'group')
                            subPath = candidate;
                            return;
                        end
                    catch
                    end
                end
            end
        end

        function [files, imginfo] = parseSingleArray(obj, rootPath, imginfo)
            % PARSESINGLEARRAY - Fallback: open root as a single ZarrArray (no multiscales metadata).
            %
            % Syntax:
            %   function [files, imginfo] = parseSingleArray(obj, rootPath, imginfo)
            %

            try
                arr     = ZarrArray(rootPath);
                arrInfo = arr.info();
            catch ME
                hint = '';
                if contains(ME.message, 'group')
                    hint = ['\n\nHint: the path points to a zarr group, not an array. ' ...
                        'If this is an OME-Zarr label container, select the specific ' ...
                        'label sub-folder (e.g. append "/0") instead of the root.'];
                end

                errorMessage = sprintf('Zarr3VirtualSetupLoader: no multiscales metadata found and cannot open as ZarrArray at\n  %s\n%s%s', rootPath, ME.message, hint);
                utils.dlgs.showErrorDialog(obj.Options.ParentFigure, errorMessage, 'io:Zarr3VirtualSetupLoader:arrayOpenFailed', '', '');
            end

            shape = arrInfo.shape;
            nDims = numel(shape);

            % infer axis order from number of dimensions (last N chars of 'tczyx')
            fullAxes = 'tczyx';
            axisOrder = fullAxes(max(1, end-nDims+1) : end);

            axisLabels = num2cell(axisOrder);
            yIdx = find(strcmp(axisLabels, 'y'), 1);
            xIdx = find(strcmp(axisLabels, 'x'), 1);
            zIdx = find(strcmp(axisLabels, 'z'), 1);
            cIdx = find(strcmp(axisLabels, 'c'), 1);
            tIdx = find(strcmp(axisLabels, 't'), 1);

            nY = obj.safeGetDim(shape, yIdx, 1);
            nX = obj.safeGetDim(shape, xIdx, 1);
            nZ = obj.safeGetDim(shape, zIdx, 1);
            nC = obj.safeGetDim(shape, cIdx, 1);
            nT = obj.safeGetDim(shape, tIdx, 1);

            imgClass = obj.zarrTypeToMatlabClass(arrInfo.dataType);
            pixSize  = utils.defaults.initializePixSize();

            imginfo{"Height"}     = nY;
            imginfo{"Width"}      = nX;
            imginfo{"Depth"}      = nZ;
            imginfo{"Colors"}     = nC;
            imginfo{"Time"}       = nT;
            imginfo{"imgClass"}   = imgClass;
            imginfo{"MaxInt"}     = obj.classMaxInt(imgClass);
            imginfo{"ColorType"}  = obj.colorType(nC);
            imginfo{"Filename"}   = rootPath;
            imginfo{"pixSize"}    = pixSize;
            imginfo{"viewPort"}   = obj.buildViewPort(nC, imginfo{"MaxInt"});

            files.filename             = rootPath;
            files.height               = nY;
            files.width                = nX;
            files.noLayers             = nZ;
            files.color                = nC;
            files.time                 = nT;
            files.imgClass             = imgClass;
            files.axisOrder            = axisOrder;
            files.nLevels              = 1;
            files.levelNames           = {''};   % empty = read from root
            files.levelImageSizes      = [nY, nX, nZ];
            files.levelScaleFactors    = [1, 1, 1];
            files.levelVoxelSizes      = [1, 1, 1];
            files.levelImageTranslations = [0, 0, 0];
            files.chunkSizes           = {arrInfo.chunkShape};
            files.shardSizes           = {arrInfo.shardShape};
            files.pixSize              = pixSize;
        end

        function [img, imginfo] = loadImagesStandard(obj, files, imginfo, options)
            % LOADIMAGESSTANDARD - loadImages for Standard mode: prompt level selection, load pixels.
            %
            % Syntax:
            %   function [img, imginfo] = loadImagesStandard(obj, files, imginfo, options)
            %

            nLevels = files.nLevels;

            % ---- level selection dialog ---------------------------------
            selectedLevel = 1;
            if nLevels > 1
                labels = cell(nLevels, 1);
                for k = 1:nLevels
                    sz = files.levelImageSizes(k, :);
                    sf = files.levelScaleFactors(k, :);
                    if k == 1
                        labels{k} = sprintf('Level %d: %d x %d x %d px  [full resolution]', ...
                            k-1, sz(2), sz(1), sz(3));
                    else
                        labels{k} = sprintf('Level %d: %d x %d x %d px  [downscale x%.4g]', ...
                            k-1, sz(2), sz(1), sz(3), sf(1));
                    end
                end

                dlgOpts = struct();
                dlgOpts.WindowWidth  = 460;
                dlgOpts.WindowHeight  = 180;
                dlgOpts.LabelPosition = 'top';
                if isfield(options, 'mibPath'); dlgOpts.mibPath = options.mibPath; end
                [answer, selIndices] = utils.dlgs.inputUniversalDlg(options.ParentFigure, '',...
                    {'Select pyramid level to load into memory:'}, ...
                    {labels(:)', {1}}, ...
                    'Zarr3: select resolution level', ...
                    dlgOpts);
                if isempty(answer); img = {}; return; end
                selectedLevel = selIndices(1);
            end

            % ---- load selected level ------------------------------------
            rootPath  = files.filename;
            levelPath = files.levelNames{selectedLevel};
            sz        = files.levelImageSizes(selectedLevel, :);

            if isempty(levelPath)
                fullPath = rootPath;
            else
                if startsWith(rootPath, 'http://') || startsWith(rootPath, 'https://')
                    fullPath = [strtrim(rootPath), '/', levelPath];
                else
                    fullPath = fullfile(rootPath, levelPath);
                end
            end

            arr = ZarrArray(fullPath);
            raw = arr.read();   % read full array

            % permute from native MATLAB order to MIB3 [y,x,z,c,t]
            tempLoader = io.loaders.Zarr3VirtualLoader('', files.axisOrder);
            perm       = tempLoader.computePermutation(files.axisOrder);
            data       = permute(raw, perm);

            % MibImage only supports integer data types (intmax fails for
            % non-integer classes like single, double, logical).
            % Check the ACTUAL class of the permuted array (not just files.imgClass)
            % so we catch cases where zarrMex returns a different type.
            actualClass  = class(data);
            intClasses   = {'uint8','uint16','uint32','uint64','int8','int16','int32','int64'};
            targetClass  = files.imgClass;

            if ismember(actualClass, intClasses)
                % Integer data — cast to declared class, skip if already correct
                if ~strcmp(actualClass, targetClass)
                    data = cast(data, targetClass);
                end
            else
                % Non-integer (float32/float64 → single/double, or logical).
                % Normalise to uint16 range based on actual data min/max.
                
                dlgTitle = 'Zarr3VirtualSetupLoader:nonIntToUint16';
                message = sprintf(['Zarr data class is ''%s'' (non-integer); MIB standard mode requires integer data.\n' ...
                    'Normalising to uint16 using actual data range [%g, %g]'], ...
                    actualClass, double(min(data(:))), double(max(data(:))));
                options.MsgBoxOnly = true;
                options.WindowHeight = 150;
                options.Icon = 'puffin_warning';
                [answer, selIndex, dontShow] = utils.dlgs.inputUniversalDlg(options.ParentFigure, '', {message}, {message}, dlgTitle, options);

                dMin = double(min(data(:)));
                dMax = double(max(data(:)));
                if dMax > dMin
                    data = uint16((double(data) - dMin) ./ (dMax - dMin) .* 65535);
                else
                    data = zeros(size(data), 'uint16');
                end
                targetClass         = 'uint16';
                imginfo{"imgClass"} = targetClass;
                imginfo{"MaxInt"}   = 65535;
            end

            % update imginfo for the selected level (may differ from level 0)
            imginfo{"Height"}   = sz(1);
            imginfo{"Width"}    = sz(2);
            imginfo{"Depth"}    = sz(3);
            imginfo{"viewPort"} = obj.buildViewPort(files.color, imginfo{"MaxInt"});

            img = data;   % bare numeric array; MibImage.initialize wraps it as obj.data{1}
        end

        function [img, imginfo] = loadImagesVirtual(~, files, imginfo)
            % LOADIMAGESVIRTUAL - loadImages for Virtual / BigData mode: return path + pyramid metadata.
            %
            % Syntax:
            %   function [img, imginfo] = loadImagesVirtual(~, files, imginfo)
            %

            rootPath = files.filename;
            img = {rootPath};   % path only; no pixel data loaded

            % ---- populate imginfo{"Pyramid"} ----------------------------
            Pyramid.levelNames             = files.levelNames;
            Pyramid.levelImageSizes        = files.levelImageSizes;
            Pyramid.levelImageTranslations = files.levelImageTranslations;
            Pyramid.levelScaleFactors      = files.levelScaleFactors;
            Pyramid.levelVoxelSizes        = files.levelVoxelSizes;
            Pyramid.chunkSizes             = files.chunkSizes;
            Pyramid.shardSizes             = files.shardSizes;
            Pyramid.axisOrder              = files.axisOrder;
            imginfo{"Pyramid"} = Pyramid;

            % ---- populate imginfo{"Virtual"} ----------------------------
            % Required by MibVirtualImage.initialize() to wire up obj.Virtual.
            % objectType='zarr3' enables getOrCreateLoader to create Zarr3VirtualLoader.
            nZ = files.noLayers;
            Virtual.objectType    = {'zarr3'};
            Virtual.seriesName    = {''};          % unused for zarr3
            Virtual.slicesPerFile = nZ;
            Virtual.filenames     = {rootPath};
            Virtual.readerId      = (1:nZ)';       % all slices map to file index 1
            Virtual.transMatrix   = {[]};           % unused for zarr3
            imginfo{"Virtual"} = Virtual;
        end

        % ---- Metadata parsing helpers ------------------------------------

        function axisOrder = extractAxisOrder(~, ms)
            % EXTRACTAXISORDER - Extract axis order string (e.g. 'tczyx') from multiscales entry.
            %
            % Syntax:
            %   function axisOrder = extractAxisOrder(~, ms)
            %
            axisOrder = 'tczyx';   % OME-Zarr default if not specified
            if ~isfield(ms, 'axes') || isempty(ms.axes)
                return;
            end
            try
                axes = ms.axes;
                if isstruct(axes)
                    names = {axes.name};
                elseif iscell(axes)
                    names = cellfun(@(a) a.name, axes, 'UniformOutput', false);
                else
                    return;
                end
                axisOrder = lower(strjoin(names, ''));
            catch
                % leave default
            end
        end

        function labels = axisOrderToLabels(~, axisOrder)
            % AXISORDERTOLABELS - Convert axis order string to cell array of single-char labels.
            %
            % Syntax:
            %   function labels = axisOrderToLabels(~, axisOrder)
            %
            labels = num2cell(lower(char(axisOrder)));
        end

        function scales = extractScaleFromCT(~, ct, nAxes)
            % EXTRACTSCALEFROMCT - Extract physical scale vector from an OME-Zarr coordinateTransformations.
            %
            % Syntax:
            %   function scales = extractScaleFromCT(~, ct, nAxes)
            %
            % The returned vector has length nAxes and is aligned to the axis
            % order declared in multiscales.axes (C-order, e.g. [t,c,z,y,x]).
            % Missing leading axes (t, c) default to 1.0.
            %
            % Input Arguments:
            %   ct     — coordinateTransformations value from zarr.json.
            %   May be a struct array or cell array of transform objects.
            %   nAxes  — number of axes declared in multiscales.axes (numel(axisLabels)).
            %   Equals the length of the desired output vector.
            %
            % Output Arguments:
            %   scales — [1 x nAxes] vector in axisLabels order.
            %   Example for 'tczyx' (nAxes=5):
            %   scales(1)=t_scale, (2)=c_scale, (3)=z_scale,
            %   (4)=y_scale, (5)=x_scale
            %
            %   Alignment rule when CT provides fewer values than nAxes:
            %   In OME-Zarr, non-spatial axes (t, c) come BEFORE spatial axes
            %   (z, y, x) and typically have scale=1.  So a 3-element CT scale
            %   [0.03, 0.13, 0.13] for a 'tczyx' dataset means [z, y, x] — the
            %   values belong at the END of the output vector:
            %   scales = [1, 1, 0.03, 0.13, 0.13]
            %   This is why values are right-aligned, not left-aligned.
            %

            scales = ones(1, nAxes);
            try
                % Normalise ct to a flat row vector sc
                sc = [];
                if isstruct(ct) && ~isempty(ct)
                    for k = 1:numel(ct)
                        if strcmp(ct(k).type, 'scale')
                            sc = ct(k).scale;
                            break;
                        end
                    end
                elseif iscell(ct)
                    for k = 1:numel(ct)
                        entry = ct{k};
                        if isfield(entry, 'type') && strcmp(entry.type, 'scale')
                            sc = entry.scale;
                            break;
                        end
                    end
                end

                if isempty(sc); return; end

                % Flatten to row vector
                if iscell(sc)
                    sc = cell2mat(sc(:)');
                else
                    sc = sc(:)';
                end

                nSc = numel(sc);
                if nSc == nAxes
                    % Exact match: values are already in axisLabels order
                    scales = sc;
                elseif nSc < nAxes
                    % Fewer CT values than axes — right-align so spatial axes
                    % (z, y, x at the end) receive the physical scale values.
                    % Non-spatial leading axes (t, c) remain 1.0.
                    scales(end - nSc + 1 : end) = sc;
                else
                    % More CT values than declared axes (non-standard).
                    % Take the last nAxes values (spatial axes are at the end).
                    scales = sc(end - nAxes + 1 : end);
                end
            catch
                % Return default ones on any parsing failure
            end
        end

        function unit = extractAxisUnit(~, ms, yIdx)
            % EXTRACTAXISUNIT - Extract physical unit from the Y axis definition.
            %
            % Syntax:
            %   function unit = extractAxisUnit(~, ms, yIdx)
            %
            unit = 'um';   % default
            if ~isfield(ms, 'axes') || isempty(ms.axes) || isempty(yIdx)
                return;
            end
            try
                axes = ms.axes;
                if isstruct(axes)
                    ax = axes(yIdx);
                elseif iscell(axes)
                    ax = axes{yIdx};
                else
                    return;
                end
                if isfield(ax, 'unit') && ~isempty(ax.unit)
                    rawUnit = lower(ax.unit);
                    % normalise common spellings to MIB3 conventions
                    switch rawUnit
                        case {'micrometer', 'micron', 'um', 'µm'}
                            unit = 'um';
                        case {'nanometer', 'nm'}
                            unit = 'nm';
                        case {'millimeter', 'mm'}
                            unit = 'mm';
                        otherwise
                            unit = rawUnit;
                    end
                end
            catch
                % leave default
            end
        end
    end

    %% Static utility helpers (also used by parseSingleArray which has no obj)
    methods (Static, Access = private)

        function v = safeGetDim(shape, idx, default)
            % SAFEGETDIM - Return shape(idx) or default if idx is empty/out of range.
            %
            % Syntax:
            %   function v = safeGetDim(shape, idx, default)
            %
            if isempty(idx) || idx > numel(shape)
                v = default;
            else
                v = shape(idx);
            end
        end

        function v = safeGetScale(scales, idx, default)
            % SAFEGETSCALE - Return scales(idx) or default if idx is empty/out of range.
            %
            % Syntax:
            %   function v = safeGetScale(scales, idx, default)
            %
            if isempty(idx) || isempty(scales) || idx > numel(scales)
                v = default;
            else
                v = scales(idx);
            end
        end

        function r = safeRatio(levelScales, idx, level0Scales)
            % SAFERATIO - Compute levelScales(idx) / level0Scales(idx), default 1.
            %
            % Syntax:
            %   function r = safeRatio(levelScales, idx, level0Scales)
            %
            if isempty(idx) || isempty(level0Scales) || idx > numel(level0Scales) ...
                    || level0Scales(idx) == 0
                r = 1;
            else
                r = levelScales(idx) / level0Scales(idx);
            end
        end

        function matlabClass = zarrTypeToMatlabClass(zarrType)
            % ZARRTYPETOMATLABCLASS - Convert zarr v3 data type string to MATLAB class string.
            %
            % Syntax:
            %   function matlabClass = zarrTypeToMatlabClass(zarrType)
            %
            switch lower(char(zarrType))
                case {'float32'}
                    matlabClass = 'single';
                case {'float64'}
                    matlabClass = 'double';
                case {'bool'}
                    matlabClass = 'uint8';
                otherwise
                    % uint8, uint16, uint32, uint64, int8, int16, int32, int64
                    matlabClass = lower(char(zarrType));
            end
        end

        function mx = classMaxInt(imgClass)
            % CLASSMAXINT - Maximum intensity value for the given MATLAB class.
            %
            % Syntax:
            %   function mx = classMaxInt(imgClass)
            %
            switch imgClass
                case {'uint8','uint16','uint32','uint64','int8','int16','int32','int64'}
                    mx = double(intmax(imgClass));
                case {'single','double'}
                    mx = 1;
                otherwise
                    mx = 255;
            end
        end

        function ct = colorType(nColors)
            if nColors == 1
                ct = 'grayscale';
            else
                ct = 'multichannel';
            end
        end

        function vp = buildViewPort(nColors, maxInt)
            vp.min   = zeros(1, nColors);
            vp.max   = repmat(maxInt, 1, nColors);
            vp.gamma = ones(1, nColors);
        end

    end

end
