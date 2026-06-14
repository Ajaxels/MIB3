classdef Zarr3Saver < handle
% ZARR3SAVER - write an image as an OME-Zarr v3 multi-resolution (multiscales) pyramid.
%
% Produces a chunked OME-Zarr v3 group with one downsampled level per
% pyramid step, written through the native Zarr3Matlab engine
% (``ZarrArray``/``ZarrGroup``). The result is readable by MIB's
% ``io.loaders.Zarr3VirtualSetupLoader`` (and thus openable as a **BigData**
% dataset) and by other OME-Zarr tools.
%
% **Primary use — ingest/convert:** turn an in-memory (Standard) dataset into
% a zarr3 BigData pyramid on disk, so large datasets can be moved into the
% BigData segmentation workflow. (A non-zarr Virtual/BioFormats source must
% first be gathered to memory or streamed level-by-level — future.)
%
% **Axis order.** Arrays are created with the Zarr3Matlab transpose codec, so
% they store/return in native MATLAB ``[y, x, z, c, t]`` order. The
% ``multiscales.axes`` are declared to match (``y, x, z`` plus ``c`` and/or
% ``t`` only when those dimensions are > 1). ``Zarr3VirtualSetupLoader`` reads
% ``axes.name`` to recover this order, and ``Zarr3VirtualLoader`` applies the
% (identity) permutation — so the round-trip is exact.
%
% **Pyramid.** Level 0 = full resolution; each further level halves Y and X
% (Z is kept — XY-only downsampling). The per-level ``scale`` coordinate
% transformation encodes the physical voxel size (``pixSize`` × 2^level in XY),
% which the loader turns into the magnification→level mapping.
%
% **Examples**
%
% **Example 1** — convert the active dataset to a BigData pyramid:
%
%   .. code-block:: matlab
%
%      ds   = mibModel.I{mibModel.getActiveId()};
%      data = ds.getData4D('image', 3, NaN);          % returns a cell; {1} = [y x z c t]
%      data = data{1};
%      meta = struct('pixSize', ds.image.pixSize);
%      io.savers.Zarr3Saver().save(data, meta, 'C:\data\out.zarr3');
%      % then open 'C:\data\out.zarr3' in BigData mode
%
% **Example 2** — minimal call (no metadata, default options ⇒ voxel size 1):
%
%   .. code-block:: matlab
%
%      vol = uint16(rand(800, 600, 20) * 1000);       % [y x z]
%      io.savers.Zarr3Saver().save(vol, struct(), 'C:\data\vol.zarr3');
%
% **Example 3** — force a fixed number of pyramid levels:
%
%   .. code-block:: matlab
%
%      opt = struct('Levels', 4);                     % level 0..3 (full, /2, /4, /8 in XY)
%      io.savers.Zarr3Saver().save(vol, meta, 'C:\data\vol.zarr3', opt);
%
% **Example 4** — control where the auto-pyramid stops and its chunking:
%
%   .. code-block:: matlab
%
%      opt = struct('MinLevelSize', 512, ...          % stop once min(Y,X) < 512
%                   'MaxLevels',   6, ...             % never exceed 6 levels
%                   'ChunkSize',   [512 512 8]);      % [y x z] zarr chunk
%      io.savers.Zarr3Saver().save(vol, meta, 'C:\data\vol.zarr3', opt);
%
% **Example 5** — uncompressed store, nearest-neighbour downsampling:
%
%   .. code-block:: matlab
%
%      opt = struct('Compressors', 'none', ...        % e.g. for fastest write
%                   'DownsampleMethod', 'nearest');   % e.g. label-like data
%      io.savers.Zarr3Saver().save(vol, meta, 'C:\data\vol.zarr3', opt);
%
% **Example 6** — multichannel image (axes become ``yxzc``, colours preserved):
%
%   .. code-block:: matlab
%
%      rgb = uint8(rand(512, 512, 10, 3) * 255);      % [y x z c]
%      io.savers.Zarr3Saver().save(rgb, struct('pixSize', struct('x',.1,'y',.1,'z',.5)), ...
%                                  'C:\data\rgb.zarr3');
%
% **Example 7** — export ONE pyramid level of a BigData dataset back to zarr3
% (gather the level you want, then write it as a fresh single/low pyramid):
%
%   .. code-block:: matlab
%
%      ds    = mibModel.I{mibModel.getActiveId()};                 % BigData
%      level = ds.getData4D('image', 3, NaN, struct('pyramidLevel', 3));   % coarse level
%      level = level{1};
%      io.savers.Zarr3Saver().save(level, struct('pixSize', ds.image.pixSize), ...
%                                  'C:\data\level3.zarr3', struct('Levels', 1));
%
% **Example 8** — round-trip check (write, reopen via the BigData loader):
%
%   .. code-block:: matlab
%
%      io.savers.Zarr3Saver().save(vol, meta, 'C:\data\vol.zarr3');
%      lo = struct('datasetMode', 'BigData');
%      L  = io.loaders.Zarr3VirtualSetupLoader(lo);
%      [info, files] = L.loadMetadata({'C:\data\vol.zarr3'}, lo);
%      % files.levelImageSizes / files.levelScaleFactors describe the pyramid

    methods
        function fnOut = save(obj, data, metadata, filename, options) %#ok<INUSL>
            % SAVE - write ``data`` as an OME-Zarr v3 multiscales pyramid.
            %
            % Input Arguments:
            %   - **data** — [y x z c t] numeric image array (full resolution).
            %   - **metadata** — struct; uses ``.pixSize`` (``.x .y .z``) when present.
            %   - **filename** — [char] output ``.zarr3`` group path (overwritten if it exists).
            %   - **options** — *(optional)* struct:
            %
            %     - ``.Levels`` — explicit number of pyramid levels (default: auto)
            %     - ``.MinLevelSize`` — stop auto-pyramid when min(Y,X) < this (default 256)
            %     - ``.MaxLevels`` — cap on auto levels (default 8)
            %     - ``.ChunkSize`` — [y x z] chunk shape (default [256 256 16], clamped)
            %     - ``.Compressors`` — codec spec for ZarrArray.create (default 'zstd')
            %     - ``.DownsampleMethod`` — imresize method for levels (default 'bilinear')
            %
            % Output Arguments:
            %   - **fnOut** — [char] the written group path.

            if nargin < 5; options = struct(); end
            if nargin < 4 || isempty(filename); error('io:Zarr3Saver:noFilename', 'Output filename is required'); end
            if ~isfield(options, 'Levels');          options.Levels = []; end
            if ~isfield(options, 'MinLevelSize');    options.MinLevelSize = 256; end
            if ~isfield(options, 'MaxLevels');       options.MaxLevels = 8; end
            if ~isfield(options, 'ChunkSize');       options.ChunkSize = [256 256 16]; end
            if ~isfield(options, 'Compressors');     options.Compressors = 'zstd'; end
            if ~isfield(options, 'DownsampleMethod'); options.DownsampleMethod = 'bilinear'; end

            % physical voxel size (default 1)
            pixSize = struct('x', 1, 'y', 1, 'z', 1);
            if isstruct(metadata) && isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                ps = metadata.pixSize;
                if isfield(ps, 'x'); pixSize.x = ps.x; end
                if isfield(ps, 'y'); pixSize.y = ps.y; end
                if isfield(ps, 'z'); pixSize.z = ps.z; end
            end

            sz = size(data, 1:5);
            Y = sz(1); X = sz(2); Z = sz(3); C = sz(4); T = sz(5);
            imgClass = class(data);

            % axes declared to match the kept (non-trailing-singleton) dims
            axesNames = {'y', 'x', 'z'};
            axesTypes = {'space', 'space', 'space'};
            if C > 1; axesNames{end+1} = 'c'; axesTypes{end+1} = 'channel'; end
            if T > 1; axesNames{end+1} = 't'; axesTypes{end+1} = 'time'; end
            nKeep = numel(axesNames);

            % number of pyramid levels
            if ~isempty(options.Levels)
                nLevels = max(1, options.Levels);
            else
                nLevels = 1;
                m = min(Y, X);
                while floor(m/2) >= options.MinLevelSize && nLevels < options.MaxLevels
                    m = floor(m/2);
                    nLevels = nLevels + 1;
                end
            end

            % fresh group
            filename = char(filename);
            if isfolder(filename); rmdir(filename, 's'); end
            grp = io.zarr.Group.create(filename);   % bulk writes follow io.zarr.Config backend

            datasets = cell(1, nLevels);
            for L = 1:nLevels
                factor = 2^(L-1);
                Yl = max(1, round(Y / factor));
                Xl = max(1, round(X / factor));

                if L == 1
                    lvl = data;
                else
                    lvl = zeros(Yl, Xl, Z, C, T, imgClass);
                    for t = 1:T
                        for c = 1:C
                            for z = 1:Z
                                lvl(:, :, z, c, t) = imresize(data(:, :, z, c, t), [Yl Xl], options.DownsampleMethod);
                            end
                        end
                    end
                end

                % drop trailing singleton c/t to match the declared axes
                keepShape = [Yl, Xl, Z];
                if C > 1; keepShape(end+1) = C; end %#ok<AGROW>
                if T > 1; keepShape(end+1) = T; end %#ok<AGROW>
                lvl = reshape(lvl, keepShape);

                % chunk: clamp [y x z] to level size; full extent for c/t
                chunk = min(options.ChunkSize(1:3), keepShape(1:3));
                chunk = max(chunk, [1 1 1]);
                if numel(keepShape) > 3; chunk = [chunk, keepShape(4:end)]; end %#ok<AGROW>

                name = num2str(L - 1);
                arr = grp.createArray(name, keepShape, imgClass, ...
                    'chunkShape', chunk, 'compressors', options.Compressors);
                arr.write(lvl);

                % per-level scale in axes order (XY doubles per level; Z constant)
                scaleVec = [pixSize.y * factor, pixSize.x * factor, pixSize.z];
                if C > 1; scaleVec(end+1) = 1; end %#ok<AGROW>
                if T > 1; scaleVec(end+1) = 1; end %#ok<AGROW>
                datasets{L} = struct('path', name, ...
                    'coordinateTransformations', {{struct('type', 'scale', 'scale', scaleVec)}});
            end

            % OME-NGFF multiscales attribute
            axesCells = cell(1, nKeep);
            for a = 1:nKeep
                axesCells{a} = struct('name', axesNames{a}, 'type', axesTypes{a});
            end
            ms = struct('version', '0.4', 'axes', {axesCells}, 'datasets', {datasets});
            grp.setAttributes(struct('multiscales', {{ms}}));

            fnOut = filename;
        end
    end

    methods (Static)
        function fnOut = exportDataset(mibModel, datasetId, filename, options)
            % EXPORTDATASET - write an open dataset's image to a zarr3 pyramid.
            %
            % Convenience wrapper used by the UI entry points (the dataset-type
            % dropdown "Convert to BigData" and the Export ribbon menu). Gathers
            % the dataset's full image volume into memory and writes it with
            % ``save``. Voxel size is taken from the image's ``pixSize``.
            %
            % Input Arguments:
            %   - **mibModel** — the ``models.MibModel`` instance.
            %   - **datasetId** — *(optional)* dataset index; default = active id.
            %   - **filename** — [char] output ``.zarr3`` path.
            %   - **options** — *(optional)* struct forwarded to ``save`` (Levels,
            %     ChunkSize, Compressors, …).
            %
            % Output Arguments:
            %   - **fnOut** — [char] the written group path.
            %
            % NOTE: gathers the whole volume into memory — fine for Standard
            % datasets; out-of-core streaming for huge sources is future work.
            if nargin < 4; options = struct(); end
            if nargin < 3 || isempty(filename); error('io:Zarr3Saver:noFilename', 'Output filename is required'); end
            if nargin < 2 || isempty(datasetId); datasetId = mibModel.getActiveId(); end

            ds = mibModel.I{datasetId};
            data = ds.getData4D('image', 3, NaN);   % full [y x z c t]; returns a cell
            if iscell(data); data = data{1}; end
            meta = struct('pixSize', ds.image.pixSize);
            fnOut = io.savers.Zarr3Saver().save(data, meta, filename, options);
        end

        function fnOut = exportModel(mibModel, datasetId, filename, options)
            % EXPORTMODEL - write an open dataset's MODEL (labels) to a zarr3 pyramid.
            %
            % Gathers the material-index label volume and writes it as an
            % OME-Zarr v3 multiscales pyramid with **nearest-neighbour**
            % downsampling (labels are categorical), then stores material names
            % and colours in a ``mibMaterials`` attribute (same convention as
            % ``core.MibBigDataLabels``).
            %
            % Input/Output mirror ``exportDataset``; ``DownsampleMethod`` is
            % forced to ``'nearest'``.
            if nargin < 4; options = struct(); end
            if nargin < 3 || isempty(filename); error('io:Zarr3Saver:noFilename', 'Output filename is required'); end
            if nargin < 2 || isempty(datasetId); datasetId = mibModel.getActiveId(); end

            ds = mibModel.I{datasetId};
            if ~ds.modelExist
                error('io:Zarr3Saver:noModel', 'There is no model to export.');
            end
            data = ds.getData4D('labels', 3, NaN);   % material indices, [y x z 1 t]; returns a cell
            if iscell(data); data = data{1}; end
            options.DownsampleMethod = 'nearest';     % labels must use nearest
            meta = struct('pixSize', ds.image.pixSize);
            fnOut = io.savers.Zarr3Saver().save(data, meta, filename, options);

            % persist material names/colours alongside the pyramid (best-effort)
            try
                grp = io.zarr.Group(char(fnOut));
                attrs = grp.getAttributes();      % preserve multiscales
                names = ds.labels.materialNames;
                if isempty(names); names = {}; end
                mm = struct('materialNames', {names});
                if ~isempty(ds.labels.materialColors); mm.materialColors = ds.labels.materialColors; end
                attrs.mibMaterials = mm;
                grp.setAttributes(attrs);
            catch
            end
        end

        function options = optionsDialog(parentFig, mibPath, isModel)
            % OPTIONSDIALOG - collect zarr3 export settings; returns [] if cancelled.
            %
            % Shared by the image/model export menus and the "Convert to BigData"
            % dropdown. ``isModel`` hides the downsample-method choice (models are
            % always written nearest-neighbour).
            %
            % Output Arguments:
            %   - **options** — struct with optional fields ``Levels`` (omitted when
            %     auto), ``ChunkSize`` [y x z], ``Compressors``, ``DownsampleMethod``;
            %     ``[]`` when the user cancels.
            if nargin < 3; isModel = false; end
            if nargin < 2; mibPath = ''; end

            prompts = {'Pyramid levels (0 = auto):', 'Chunk size [Y, X, Z]:', 'Compression:'};
            defAns  = {struct('Spinner', true, 'Value', 0, 'Limits', [0 12], 'Step', 1, 'Round', true), ...
                       '256, 256, 16', ...
                       {'zstd', 'gzip', 'none', 1}};
            if ~isModel
                prompts{end+1} = 'Downsampling method:';
                defAns{end+1}  = {'bilinear', 'nearest', 'bicubic', 1};
            end

            dlgOpts = struct('LabelPosition', 'left', 'WindowWidth', 430);
            if ~isempty(mibPath); dlgOpts.mibPath = mibPath; end
            answer = utils.dlgs.inputUniversalDlg(parentFig, 'Zarr3 (OME-Zarr v3) export settings', ...
                prompts, defAns, 'Export to Zarr3', dlgOpts);
            if isempty(answer); options = []; return; end

            options = struct();
            if answer{1} > 0; options.Levels = answer{1}; end       % 0 -> auto
            chunk = str2num(answer{2}); %#ok<ST2NM>
            if numel(chunk) == 3; options.ChunkSize = chunk; end
            options.Compressors = answer{3};
            if ~isModel
                options.DownsampleMethod = answer{4};
            else
                options.DownsampleMethod = 'nearest';
            end
        end
    end
end
