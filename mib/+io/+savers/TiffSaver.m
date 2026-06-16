classdef TiffSaver < io.savers.BaseSaver
% TIFFSAVER - Saver for TIFF (Tagged Image File Format) output.
%
% Handles three format variants:
% 'TIF format uncompressed (``*.tif``)'    — no compression, broadest compat.
% 'TIF format LZW compression (``*.tif``)' — lossless LZW, smaller files
% 'TIF format (``*.tif``)'                 — alias used for mask/labels export
%
% Both 3-D multi-frame TIF (all slices in one file) and 2-D sequence
% (one file per slice) modes are supported via options.Saving3DPolicy.
%
% DATA DIMENSIONS
% Input  data : [H, W, D, C, T]  (MIB3 native order)
% imwrite call: [H, W, C]  per individual Z-slice
% [H, W, C, D] for the full Z-stack in multi mode
%
% NOTES
% * TIFF supports at most 3 colour channels via standard imwrite.
% Multichannel data with C > 3 is not supported; use Amira or HDF5.
% * Indexed images (colorType == 'indexed') are saved with the
% colourmap stored in metadata.lutColors (or metadata.colormap).
% * Time series (T > 1) are saved as separate 3-D stack files or
% separate 2-D sequence directories, with '_T001', '_T002' suffixes.
%
% USAGE EXAMPLES
%
% .. code-block:: matlab
%
%     %% 1. Lowest level — direct saver use (scripted pipeline)
%     saver = io.SaverFactory.create('TIF format uncompressed (``*.tif``)');
%
%     opts.Format         = 'TIF format uncompressed (``*.tif``)';
%     opts.Saving3DPolicy = '3D stack';    % or '2D sequence'
%     opts.Compression    = 'none';        % 'none' | 'lzw' | 'packbits'
%     opts.showWaitbar    = false;
%     opts.silent         = true;
%     opts.overwrite      = true;
%     opts.FilenameGenerator = 'Use sequential filename';
%
%     meta.filename   = 'source_stack.tif';
%     meta.colorType  = 'grayscale';
%     meta.lutColors  = [1 1 1];
%     meta.dataClass  = 'uint16';
%     meta.maxInt     = 65535;
%     meta.sliceName  = {};
%     meta.pixSize    = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
%     meta.imageDescription = '';
%
%     data = uint16(rand(512,512,50,1,1) * 65535);  % [H W D C T]
%     fnOut = saver.save(data, meta, '/output/myStack.tif', opts);
%     fprintf('Saved: %s\n', fnOut);
%
%
%
% .. code-block:: matlab
%
%     %% 2. Via MibImage standalone (without MibModel/MibDataset)
%     img = core.MibImage(uint8(rand(256,256,30,1,1)*255));
%     img.filename = '/data/input.tif';
%
%     opts.Format         = 'TIF format LZW compression (``*.tif``)';
%     opts.Saving3DPolicy = '3D stack';
%     opts.showWaitbar    = false;
%     opts.silent         = true;
%     opts.overwrite      = true;
%     opts.pixSize        = struct('x',1,'y',1,'z',1,'units','um','t',1,'tunits','s');
%     fnOut = img.save('/output/compressed.tif', opts);
%
%
%
% .. code-block:: matlab
%
%     %% 3. Via MibModel (BatchOpt-compatible, recommended for GUI workflows)
%     BatchOpt.LayerType       = {'image'};
%     BatchOpt.Format          = {'TIF format uncompressed (``*.tif``)'};
%     BatchOpt.OutputDirectoryPolicy = {'Full path'};
%     BatchOpt.DestinationDirectory  = '/output/dir';
%     BatchOpt.FilenamePolicy  = {'Use existing name'};
%     BatchOpt.Saving3DPolicy  = {'3D stack'};
%     BatchOpt.showWaitbar     = false;
%     BatchOpt.mibBatchTooltip.LayerType = '';   % marks as batch mode
%     model.save('image', [], BatchOpt);
%
%
% SEE ALSO
% io.SaverFactory, io.savers.BaseSaver, io.savers.PngSaver,
% core.MibImage.save, core.MibDataset.save, models.MibModel.save

    methods

        function obj = TiffSaver(options)
            % TIFFSAVER - Constructor for TiffSaver class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      saver = io.savers.TiffSaver(options)
            %
            % Input Arguments:
            %   - **options** — *(optional)* struct, saver-level options (usually empty;
            %     per-save options are passed to ``save()`` instead)
            %
            % Output Arguments:
            %   - **obj** — instance of the TiffSaver class
            %
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            % GETSUPPORTEDFORMATS - Return format strings handled by TiffSaver.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      formats = obj.getSupportedFormats()
            %
            % Input Arguments:
            %   (none)
            %
            % Output Arguments:
            %   - **formats** — cell array of format strings for TIFF output
            %
            formats = { ...
                'TIF format uncompressed (*.tif)'; ...
                'TIF format LZW compression (*.tif)'; ...
                'TIF format (*.tif)' };
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % SAVE - Write data as a TIFF file or 2-D TIFF sequence.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.save(data, metadata, filename, options)
            %
            % Supports both 3-D multi-frame TIFF (all slices in one file) and
            % 2-D sequence (one file per slice) modes via ``options.Saving3DPolicy``.
            % Time-series data (T > 1) is saved with ``_T001``, ``_T002`` suffixes.
            %
            % Input Arguments:
            %   - **data** — [H, W, D, C, T] numeric array
            %   - **metadata** — struct with fields:
            %
            %     - ``colorType`` — ``'grayscale'`` | ``'multichannel'`` | ``'indexed'``
            %     - ``lutColors`` — *(optional)* [N × 3] colormap for indexed images
            %     - ``colormap`` — *(optional)* [N × 3] colormap (alternative to ``lutColors``)
            %     - ``sliceName`` — *(optional)* cell of char, per-slice source filenames
            %     - ``imageDescription`` — *(optional)* [char] TIFF ``ImageDescription`` tag
            %     - ``xResolution`` — *(optional)* [numeric] X resolution in pixels/unit; default: ``72``
            %     - ``yResolution`` — *(optional)* [numeric] Y resolution in pixels/unit; default: ``72``
            %
            %   - **filename** — [char] full output path, e.g. ``'/out/stack.tif'``
            %   - **options** — struct with fields:
            %
            %     - ``Format`` — format string (selects compression mode)
            %     - ``Saving3DPolicy`` — ``'3D stack'`` | ``'2D sequence'``; default: ``'3D stack'``
            %     - ``showWaitbar`` — logical; default: ``true``
            %     - ``silent`` — logical, suppress dialogs; default: ``false``
            %     - ``overwrite`` — logical; default: ``true``
            %     - ``FilenameGenerator`` — ``'Use original filename'`` | ``'Use sequential filename'``
            %     - ``Compression`` — *(optional)* ``'none'`` | ``'lzw'`` | ``'packbits'``; overrides Format
            %
            % Output Arguments:
            %   - **fnOut** — [char] for 3D stack single file, or [cell of char] for 2D sequence;
            %     ``[]`` on failure
            %
            % **Example** — see class-level documentation above.
            %

            if nargin < 5; options = struct(); end
            fnOut = [];

            % Track which options were explicitly provided by the caller
            % (must be done before applying defaults below).
            % NOTE: callerSetSaving3D is intentionally NOT used to gate the
            % dialog — MibImage.save() always injects a default Saving3DPolicy
            % before reaching here, so that flag would always be true and the
            % dialog would never appear.  We gate on callerSetFilename instead,
            % mirroring PngSaver's approach.
            callerSetFilename = isfield(options, 'FilenameGenerator');

            % --- defaults ---
            if ~isfield(options, 'showWaitbar');       options.showWaitbar = true; end
            if ~isfield(options, 'silent');            options.silent      = false; end
            if ~isfield(options, 'overwrite');         options.overwrite   = true;  end
            if ~isfield(options, 'Saving3DPolicy');    options.Saving3DPolicy = '3D stack'; end
            if ~isfield(options, 'FilenameGenerator'); options.FilenameGenerator = 'Use sequential filename'; end

            % Determine compression from Format string or explicit field.
            % 'TIF format (``*.tif``)' is the labels/mask alias — always LZW.
            if isfield(options, 'Compression')
                compression = options.Compression;
            elseif isfield(options, 'Format') && contains(options.Format, 'LZW')
                compression = 'lzw';
            elseif isfield(options, 'Format') && strcmp(options.Format, 'TIF format (*.tif)')
                compression = 'lzw';
            else
                compression = 'none';
            end

            % --- resolution ---
            xRes = 72; yRes = 72;
            if isfield(metadata, 'xResolution') && ~isempty(metadata.xResolution)
                xRes = metadata.xResolution;
            end
            if isfield(metadata, 'yResolution') && ~isempty(metadata.yResolution)
                yRes = metadata.yResolution;
            end
            resolution = [xRes, yRes];

            % --- colormap for indexed images ---
            cmap = NaN;
            if isfield(metadata, 'colorType') && strcmp(metadata.colorType, 'indexed')
                if isfield(metadata, 'colormap') && ~isempty(metadata.colormap)
                    cmap = metadata.colormap;
                elseif isfield(metadata, 'lutColors') && size(metadata.lutColors,1) > 1
                    cmap = metadata.lutColors;
                end
            end

            % --- image description (one per Z-slice) ---
            imgDescBase = '';
            if isfield(metadata, 'imageDescription')
                imgDescBase = metadata.imageDescription;
            end

            % --- decompose filename ---
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isempty(ext); ext = '.tif'; end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr, 'dir') ~= 7; mkdir(pathStr); end

            [~, ~, nD, nC, nT] = size(data);

            % TIF supports max 3 colour channels via imwrite
            if nC > 3
                warning('TiffSaver:tooManyChannels', ...
                    'TIFF supports ≤3 colour channels; got %d. Use Amira or HDF5 for multichannel data.', nC);
                return;
            end

            % --- "TIF saving settings" dialog ---
            % Show when FilenameGenerator was not explicitly provided by the
            % caller and the dataset has more than one slice (same logic as
            % PngSaver; Saving3DPolicy is also asked here since TIFF supports
            % both 3D stack and 2D sequence modes).
            hasSliceSizes = isfield(metadata, 'sliceSize') && size(metadata.sliceSize, 1) == nD;
            if ~options.silent && ~callerSetFilename && nD > 1
                prompts = {'Filename generator:'; 'Multi-dimensional saving policy:'};
                defAns  = {{'Use original filename', 'Use sequential filename', 2}; ...
                           {'3D stack', '2D sequence', 1}};
                if hasSliceSizes
                    prompts{end+1} = 'Restore original slice dimensions:';
                    defAns{end+1}  = {'No', 'Yes', 1};
                end
                dlgOpts.mibPath     = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'TIF saving settings', dlgOpts);
                if isempty(answer); return; end
                options.FilenameGenerator = answer{1};
                options.Saving3DPolicy    = answer{2};
                if hasSliceSizes
                    options.RestoreOriginalSize = strcmp(answer{3}, 'Yes');
                end
            end

            % --- outer waitbar for time series ---
            wbOuter = [];
            if options.showWaitbar && nT > 1
                wbOuter = obj.createProgressDialog('Saving images...', 'Saving TIFF series...', true);
            end

            allFn = cell(nT, 1);

            try
                for t = 1:nT
                    if ~isempty(wbOuter) && wbOuter.CancelRequested
                        delete(wbOuter); return;
                    end
                    % Build filename for this time point
                    if nT > 1
                        tSuffix = sprintf('_T%03d', t);
                        fnThisT = [baseName tSuffix ext];
                    else
                        fnThisT = [baseName ext];
                    end
                    outPath = fullfile(pathStr, fnThisT);

                    % Get 4-D slice [H, W, D, C] for this time point,
                    % then permute to legacy [H, W, C, D] for imwrite
                    slice4D = permute(data(:,:,:,:,t), [1 2 4 3]);  % [H, W, C, D]

                    % Build per-slice ImageDescription array
                    imgDescArr = repmat({imgDescBase}, nD, 1);

                    if strcmp(options.Saving3DPolicy, '3D stack')
                        % --- Save all Z-slices in one multi-frame TIFF ---
                        cancelled = obj.writeTiffStack(outPath, slice4D, cmap, imgDescArr, ...
                            compression, resolution, options);
                        if cancelled; if ~isempty(wbOuter); delete(wbOuter); end; return; end
                        allFn{t} = outPath;

                    else
                        % --- Save individual 2-D TIF files per slice ---
                        sliceNames = obj.buildSliceNames(baseName, pathStr, nD, ext, options, metadata);
                        if nT > 1
                            % Prefix with T-index when saving time series
                            for z = 1:nD
                                [~, sn, se] = fileparts(sliceNames{z});
                                sliceNames{z} = fullfile(pathStr, ...
                                    sprintf('%s_T%03d%s', sn, t, se));
                            end
                        end

                        % Inner waitbar (for Z slices)
                        wbInner = [];
                        if options.showWaitbar && isempty(wbOuter)
                            wbInner = obj.createProgressDialog('Saving images...', sprintf('Saving TIFF — %s', baseName), true);
                        end

                        for z = 1:nD
                            if ~isempty(wbInner) && wbInner.CancelRequested
                                delete(wbInner); return;
                            end
                            img2D = squeeze(slice4D(:, :, :, z));  % [H, W, C]
                            if isfield(options, 'RestoreOriginalSize') && options.RestoreOriginalSize && ...
                                    hasSliceSizes
                                img2D = obj.cropSliceToOriginalSize(img2D, metadata.sliceSize(z, :));
                            end
                            descArgs = {};
                            if ~isempty(imgDescArr{z}); descArgs = {'Description', imgDescArr{z}}; end
                            if isnan(cmap)
                                imwrite(img2D, sliceNames{z}, 'tif', ...
                                    'Compression', compression, ...
                                    descArgs{:}, ...
                                    'Resolution',  resolution);
                            else
                                imwrite(img2D, cmap, sliceNames{z}, 'tif', ...
                                    'Compression', compression, ...
                                    descArgs{:}, ...
                                    'Resolution',  resolution);
                            end
                            if ~isempty(wbInner); wbInner.Value = z/nD; end
                        end
                        if ~isempty(wbInner); delete(wbInner); end
                        allFn{t} = sliceNames;
                    end

                    if ~isempty(wbOuter); wbOuter.Value = t/nT; end
                end

            catch ME
                if ~isempty(wbOuter); delete(wbOuter); end
                rethrow(ME);
            end
            if ~isempty(wbOuter); delete(wbOuter); end

            % Return a scalar filename for 3D stack, or cell array for sequences
            if strcmp(options.Saving3DPolicy, '3D stack') && nT == 1
                fnOut = allFn{1};
            else
                fnOut = allFn;
            end
            fprintf('TiffSaver: saved → %s\n', filename);
        end

        function fnOut = saveStream(obj, provider, metadata, filename, options)
            % SAVESTREAM - Streaming TIFF writer: one Z-slice from the provider at a time.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.saveStream(provider, metadata, filename, options)
            %
            % Memory-bounded twin of ``save``: instead of receiving a full
            % ``[H W D C T]`` array it pulls each slice from ``provider.getSlice(z, t)``
            % (an ``io.savers.SliceProvider``) and appends it to the output, so a large
            % pyramid level can be exported without ever holding the whole volume.
            % Honors the same compression / resolution / colormap / 3D-stack vs
            % 2D-sequence options as ``save``.
            %
            % Input/Output: see ``io.savers.BaseSaver.saveStream``.
            %
            % **Example** — stream a BigData image level to a 3-D TIFF stack:
            %
            %   .. code-block:: matlab
            %
            %      img      = mibModel.I{mibModel.getActiveId()}.image;   % MibBigDataImage
            %      numZ     = img.pyramid.levelImageSizes(1,3);
            %      zScale   = img.pyramid.levelScaleFactors(1,3);
            %      provider = io.savers.MibImageSliceProvider(img,'image',1,[],numZ,img.time,zScale);
            %      saver    = io.savers.TiffSaver(struct());
            %      meta.colorType='grayscale'; meta.dataClass=img.dataClass; meta.imageDescription='';
            %      opts = struct('Saving3DPolicy','3D stack','silent',true,'showWaitbar',false, ...
            %                    'FilenameGenerator','Use sequential filename');
            %      saver.saveStream(provider, meta, 'C:\out\level0.tif', opts);
            if nargin < 5; options = struct(); end
            fnOut = [];

            callerSetFilename = isfield(options, 'FilenameGenerator');

            % --- defaults (mirror save) ---
            if ~isfield(options, 'showWaitbar');       options.showWaitbar = true; end
            if ~isfield(options, 'silent');            options.silent      = false; end
            if ~isfield(options, 'overwrite');         options.overwrite   = true;  end
            if ~isfield(options, 'Saving3DPolicy');    options.Saving3DPolicy = '3D stack'; end
            if ~isfield(options, 'FilenameGenerator'); options.FilenameGenerator = 'Use sequential filename'; end

            % --- compression ---
            if isfield(options, 'Compression')
                compression = options.Compression;
            elseif isfield(options, 'Format') && contains(options.Format, 'LZW')
                compression = 'lzw';
            elseif isfield(options, 'Format') && strcmp(options.Format, 'TIF format (*.tif)')
                compression = 'lzw';
            else
                compression = 'none';
            end

            % --- resolution ---
            xRes = 72; yRes = 72;
            if isfield(metadata, 'xResolution') && ~isempty(metadata.xResolution); xRes = metadata.xResolution; end
            if isfield(metadata, 'yResolution') && ~isempty(metadata.yResolution); yRes = metadata.yResolution; end
            resolution = [xRes, yRes];

            % --- colormap for indexed images ---
            cmap = NaN;
            if isfield(metadata, 'colorType') && strcmp(metadata.colorType, 'indexed')
                if isfield(metadata, 'colormap') && ~isempty(metadata.colormap)
                    cmap = metadata.colormap;
                elseif isfield(metadata, 'lutColors') && size(metadata.lutColors,1) > 1
                    cmap = metadata.lutColors;
                end
            end

            imgDescBase = '';
            if isfield(metadata, 'imageDescription'); imgDescBase = metadata.imageDescription; end

            % --- decompose filename ---
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isempty(ext); ext = '.tif'; end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr, 'dir') ~= 7; mkdir(pathStr); end

            sz = provider.OutputSize;
            nD = sz(3); nC = sz(4); nT = sz(5);

            if nC > 3
                warning('TiffSaver:tooManyChannels', ...
                    'TIFF supports ≤3 colour channels; got %d. Use Amira or HDF5 for multichannel data.', nC);
                return;
            end

            % --- "TIF saving settings" dialog (mirror save) ---
            hasSliceSizes = isfield(metadata, 'sliceSize') && size(metadata.sliceSize, 1) == nD;
            if ~options.silent && ~callerSetFilename && nD > 1
                prompts = {'Filename generator:'; 'Multi-dimensional saving policy:'};
                defAns  = {{'Use original filename', 'Use sequential filename', 2}; ...
                           {'3D stack', '2D sequence', 1}};
                if hasSliceSizes
                    prompts{end+1} = 'Restore original slice dimensions:';
                    defAns{end+1}  = {'No', 'Yes', 1};
                end
                dlgOpts.mibPath     = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'TIF saving settings', dlgOpts);
                if isempty(answer); return; end
                options.FilenameGenerator = answer{1};
                options.Saving3DPolicy    = answer{2};
                if hasSliceSizes
                    options.RestoreOriginalSize = strcmp(answer{3}, 'Yes');
                end
            end

            wbOuter = [];
            if options.showWaitbar && nT > 1
                wbOuter = obj.createProgressDialog('Saving images...', 'Saving TIFF series...', true);
            end

            allFn = cell(nT, 1);
            try
                for t = 1:nT
                    if ~isempty(wbOuter) && wbOuter.CancelRequested; delete(wbOuter); return; end
                    if nT > 1
                        fnThisT = [baseName sprintf('_T%03d', t) ext];
                    else
                        fnThisT = [baseName ext];
                    end
                    outPath = fullfile(pathStr, fnThisT);
                    imgDescArr = repmat({imgDescBase}, nD, 1);

                    if strcmp(options.Saving3DPolicy, '3D stack')
                        cancelled = obj.writeTiffStackStream(outPath, provider, t, cmap, ...
                            imgDescArr, compression, resolution, options);
                        if cancelled; if ~isempty(wbOuter); delete(wbOuter); end; return; end
                        allFn{t} = outPath;
                    else
                        sliceNames = obj.buildSliceNames(baseName, pathStr, nD, ext, options, metadata);
                        if nT > 1
                            for z = 1:nD
                                [~, sn, se] = fileparts(sliceNames{z});
                                sliceNames{z} = fullfile(pathStr, sprintf('%s_T%03d%s', sn, t, se));
                            end
                        end
                        wbInner = [];
                        if options.showWaitbar && isempty(wbOuter)
                            wbInner = obj.createProgressDialog('Saving images...', sprintf('Saving TIFF — %s', baseName), true);
                        end
                        for z = 1:nD
                            if ~isempty(wbInner) && wbInner.CancelRequested; delete(wbInner); return; end
                            img2D = squeeze(provider.getSlice(z, t));   % [H, W, C]
                            if isfield(options, 'RestoreOriginalSize') && options.RestoreOriginalSize && hasSliceSizes
                                img2D = obj.cropSliceToOriginalSize(img2D, metadata.sliceSize(z, :));
                            end
                            descArgs = {};
                            if ~isempty(imgDescArr{z}); descArgs = {'Description', imgDescArr{z}}; end
                            if isnan(cmap)
                                imwrite(img2D, sliceNames{z}, 'tif', 'Compression', compression, descArgs{:}, 'Resolution', resolution);
                            else
                                imwrite(img2D, cmap, sliceNames{z}, 'tif', 'Compression', compression, descArgs{:}, 'Resolution', resolution);
                            end
                            if ~isempty(wbInner); wbInner.Value = z/nD; end
                        end
                        if ~isempty(wbInner); delete(wbInner); end
                        allFn{t} = sliceNames;
                    end
                    if ~isempty(wbOuter); wbOuter.Value = t/nT; end
                end
            catch ME
                if ~isempty(wbOuter); delete(wbOuter); end
                rethrow(ME);
            end
            if ~isempty(wbOuter); delete(wbOuter); end

            if strcmp(options.Saving3DPolicy, '3D stack') && nT == 1
                fnOut = allFn{1};
            else
                fnOut = allFn;
            end
            fprintf('TiffSaver: streamed → %s\n', filename);
        end

    end

    % ------------------------------------------------------------------ %
    %   Private helpers                                                    %
    % ------------------------------------------------------------------ %
    methods (Access = private)

        function cancelled = writeTiffStackStream(obj, outPath, provider, t, cmap, ...
                imgDescArr, compression, resolution, options)
            % WRITETIFFSTACKSTREAM - Append a multi-frame TIFF stack pulling each frame from provider.
            %
            % Streaming counterpart of ``writeTiffStack``: frame ``z`` is obtained via
            % ``provider.getSlice(z, t)`` so the full stack is never resident.
            cancelled = false;
            nD = provider.NumSlices;
            wb = [];
            if options.showWaitbar
                wb = obj.createProgressDialog('Saving TIFF...', sprintf('Writing %s', outPath), true);
            end
            for z = 1:nD
                if ~isempty(wb) && wb.CancelRequested; delete(wb); cancelled = true; return; end
                frame = squeeze(provider.getSlice(z, t));   % [H, W, C]
                writeMode = 'overwrite';
                if z > 1; writeMode = 'append'; end
                descArgs = {};
                if ~isempty(imgDescArr{z}); descArgs = {'Description', imgDescArr{z}}; end
                if isnan(cmap)
                    imwrite(frame, outPath, 'tif', 'WriteMode', writeMode, ...
                        'Compression', compression, descArgs{:}, 'Resolution', resolution);
                else
                    imwrite(frame, cmap, outPath, 'tif', 'WriteMode', writeMode, ...
                        'Compression', compression, descArgs{:}, 'Resolution', resolution);
                end
                if ~isempty(wb); wb.Value = z/nD; end
            end
            if ~isempty(wb); delete(wb); end
        end

        function cancelled = writeTiffStack(obj, outPath, slice4D, cmap, imgDescArr, ...
                compression, resolution, options)
            % WRITETIFFSTACK - Write a multi-frame TIFF stack where slice4D is [H, W, C, D].
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      cancelled = obj.writeTiffStack(outPath, slice4D, cmap, imgDescArr, ...
            %                                     compression, resolution, options)
            %
            % Uses ``imwrite`` 'overwrite'/'append' modes to build the stack
            % frame by frame, allowing large files to be written without
            % loading completely into memory.
            %
            % Input Arguments:
            %   - **outPath** — [char] full output path
            %   - **slice4D** — [H, W, C, D] image data for one time point
            %   - **cmap** — colormap matrix or ``NaN`` (no colormap)
            %   - **imgDescArr** — {D × 1} cell of ImageDescription strings
            %   - **compression** — [char] ``'none'`` | ``'lzw'`` | ``'packbits'``
            %   - **resolution** — [xRes yRes] vector with resolution in pixels/unit
            %   - **options** — struct with fields used (e.g., ``showWaitbar``, ``overwrite``)
            %
            % Output Arguments:
            %   - **cancelled** — [logical] ``true`` if user cancelled during progress dialog
            %

            cancelled = false;
            nD = size(slice4D, 4);
            wb = [];
            if options.showWaitbar
                wb = obj.createProgressDialog('Saving TIFF...', sprintf('Writing %s', outPath), true);
            end

            for z = 1:nD
                if ~isempty(wb) && wb.CancelRequested
                    delete(wb); cancelled = true; return;
                end
                frame = squeeze(slice4D(:, :, :, z));   % [H, W, C]
                writeMode = 'overwrite';
                if z > 1; writeMode = 'append'; end

                descArgs = {};
                if ~isempty(imgDescArr{z}); descArgs = {'Description', imgDescArr{z}}; end
                if isnan(cmap)
                    imwrite(frame, outPath, 'tif', ...
                        'WriteMode',   writeMode, ...
                        'Compression', compression, ...
                        descArgs{:}, ...
                        'Resolution',  resolution);
                else
                    imwrite(frame, cmap, outPath, 'tif', ...
                        'WriteMode',   writeMode, ...
                        'Compression', compression, ...
                        descArgs{:}, ...
                        'Resolution',  resolution);
                end
                if ~isempty(wb); wb.Value = z/nD; end
            end
            if ~isempty(wb); delete(wb); end
        end

    end
end
