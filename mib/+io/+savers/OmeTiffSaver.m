classdef OmeTiffSaver < io.savers.BaseSaver
% OMETIFFSAVER - Saver for OME-TIFF (Open Microscopy Environment TIFF) output.
%
% Handles two format variants:
% 'OME-TIFF 5D (*.ome.tiff)'          — full 5-D OME-TIFF (single file)
% 'OME-TIFF 2D sequence (*.ome.tiff)' — one OME-TIFF per Z×T slice
%
% OME-TIFF stores the full 5-D data set [H, W, C, D, T] together with
% standardised OME-XML metadata describing pixel sizes, channel names,
% LUT colours, and acquisition information.
%
% The saver calls io.BioFormats.mibImage2ometiff(), which is already
% present in MIB3 at mib/+io/+BioFormats/mibImage2ometiff.m.
%
% DATA DIMENSIONS
% Input  data : [H, W, D, C, T]  (MIB3 native order)
% mibImage2ometiff() expects [H, W, C, D, T] — the saver permutes
% dimensions 3 and 4 before the call.
%
% SAVING OPTIONS PASSED TO mibImage2ometiff
% savingOptions.pixSize          — struct {.x .y .z .units .t .tunits}
% savingOptions.lutColors        — [C x 3] channel LUT colours (0..1)
% savingOptions.ImageDescription — (char) dataset description
% savingOptions.DimensionOrder   — always 'XYCZT'
% savingOptions.Saving3d         — '5D' | '2D'
% savingOptions.overwrite        — logical
% savingOptions.DatasetType      — 'image' | 'mask' | 'labels'
% savingOptions.showWaitbar      — logical
%
% NOTES
% * OME-TIFF is the preferred format for multichannel, multi-Z,
% multi-time datasets because it stores all metadata in standardised
% OME-XML.
% * The output file extension is always '.ome.tiff'; if the user
% provides a different extension it is replaced automatically.
%
% USAGE EXAMPLES
%
% .. code-block:: matlab
%
%     %% 1. Save 5-D multichannel stack as OME-TIFF
%     saver = io.SaverFactory.create('OME-TIFF 5D (*.ome.tiff)');
%
%     opts.Format         = 'OME-TIFF 5D (*.ome.tiff)';
%     opts.showWaitbar    = false;
%     opts.silent         = true;
%     opts.overwrite      = true;
%     opts.layerType      = 'image';
%
%     meta.filename       = 'source_stack.tif';
%     meta.colorType      = 'multichannel';
%     meta.lutColors      = [1 0 0; 0 1 0; 0 0 1];   % R, G, B channels
%     meta.dataClass      = 'uint16';
%     meta.maxInt         = 65535;
%     meta.pixSize        = struct('x',0.065,'y',0.065,'z',0.2, ...
%                                  'units','um','t',1,'tunits','s');
%     meta.imageDescription = 'My confocal dataset';
%
%     data = uint16(rand(512,512,50,3,4)*65535);  % [H W D C T]
%     fnOut = saver.save(data, meta, '/output/myStack.ome.tiff', opts);
%     fprintf('Saved: %s\n', fnOut);
%
%
%
% .. code-block:: matlab
%
%     %% 2. Save as OME-TIFF 2D sequence
%     saver = io.SaverFactory.create('OME-TIFF 2D sequence (*.ome.tiff)');
%
%     opts.Format      = 'OME-TIFF 2D sequence (*.ome.tiff)';
%     opts.showWaitbar = true;
%     opts.silent      = true;
%     opts.overwrite   = true;
%     opts.layerType   = 'image';
%
%     meta.filename    = 'source_stack.tif';
%     meta.colorType   = 'multichannel';
%     meta.lutColors   = [1 0 0; 0 1 0; 0 0 1];
%     meta.dataClass   = 'uint16';
%     meta.maxInt      = 65535;
%     meta.pixSize     = struct('x',0.065,'y',0.065,'z',0.2, ...
%                               'units','um','t',1,'tunits','s');
%
%     data = uint16(rand(512,512,50,3,1)*65535);  % [H W D C T]
%     fnOut = saver.save(data, meta, '/output/myStack.ome.tiff', opts);
%
%
%
% .. code-block:: matlab
%
%     %% 3. Via MibModel batch
%     BatchOpt.LayerType       = {'image'};
%     BatchOpt.Format          = {'OME-TIFF 5D (*.ome.tiff)'};
%     BatchOpt.OutputDirectoryPolicy = {'Full path'};
%     BatchOpt.DestinationDirectory  = '/output/dir';
%     BatchOpt.FilenamePolicy  = {'Use existing name'};
%     BatchOpt.showWaitbar     = false;
%     BatchOpt.mibBatchTooltip.LayerType = '';
%     model.save('image', [], BatchOpt);
%
%
% SEE ALSO
% io.SaverFactory, io.savers.BaseSaver, io.savers.TiffSaver,
% io.BioFormats.mibImage2ometiff,
% core.MibImage.save, core.MibDataset.save, models.MibModel.save

    methods

        function obj = OmeTiffSaver(options)
            % OMETIFFSAVER - Constructor for OmeTiffSaver class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      saver = io.savers.OmeTiffSaver(options)
            %
            % Input Arguments:
            %   - **options** — *(optional)* struct, saver-level options (usually empty;
            %     per-save options are passed to ``save()`` instead)
            %
            % Output Arguments:
            %   - **obj** — instance of the OmeTiffSaver class
            %
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            % GETSUPPORTEDFORMATS - Return format strings handled by OmeTiffSaver.
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
            %   - **formats** — cell array of format strings for OME-TIFF output
            %
            formats = { ...
                'OME-TIFF 5D (*.ome.tiff)'; ...
                'OME-TIFF 2D sequence (*.ome.tiff)' };
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % SAVE - Write data as an OME-TIFF file or 2-D OME-TIFF sequence.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.save(data, metadata, filename, options)
            %
            % Input Arguments:
            %   - **data** — [H, W, D, C, T] numeric array
            %   - **metadata** — struct with fields:
            %
            %     - ``colorType`` — ``'grayscale'`` | ``'multichannel'`` | ``'indexed'``
            %     - ``lutColors`` — [C × 3] per-channel LUT colours (0–1 range)
            %     - ``dataClass`` — ``'uint8'`` | ``'uint16'`` | ...
            %     - ``maxInt`` — maximum intensity value
            %     - ``pixSize`` — struct {``.x``, ``.y``, ``.z``, ``.units``, ``.t``, ``.tunits``}
            %     - ``imageDescription`` — *(optional)* [char] dataset description string
            %     - ``sliceName`` — *(optional)* per-slice source filenames (used in 2D mode)
            %
            %   - **filename** — [char] full output path; extension is always normalized to ``.ome.tiff``
            %   - **options** — struct with fields:
            %
            %     - ``Format`` — format string (``'OME-TIFF 5D (*.ome.tiff)'`` or ``'OME-TIFF 2D sequence (*.ome.tiff)'``)
            %     - ``layerType`` — ``'image'`` | ``'mask'`` | ``'labels'``; default: ``'image'``
            %     - ``showWaitbar`` — logical; default: ``true``
            %     - ``silent`` — logical, suppress dialogs; default: ``false``
            %     - ``overwrite`` — logical; default: ``true``
            %     - ``FilenameGenerator`` — ``'Use original filename'`` | ``'Use sequential filename'`` (2D mode only)
            %
            % Output Arguments:
            %   - **fnOut** — [char] path of saved ``.ome.tiff`` file, ``[]`` on failure
            %
            % **Example** — see class-level documentation above.
            %

            fnOut = [];

            % Track which options were explicitly provided by the caller
            callerSetFilename = isfield(options, 'FilenameGenerator');

            % --- defaults ---
            if ~isfield(options, 'showWaitbar');       options.showWaitbar       = true;                     end
            if ~isfield(options, 'silent');            options.silent            = false;                    end
            if ~isfield(options, 'overwrite');         options.overwrite         = true;                     end
            if ~isfield(options, 'layerType');         options.layerType         = 'image';                  end
            if ~isfield(options, 'Format');            options.Format            = 'OME-TIFF 5D (*.ome.tiff)'; end
            if ~isfield(options, 'FilenameGenerator'); options.FilenameGenerator = 'Use sequential filename'; end

            % --- determine 5D vs 2D saving mode ---
            if contains(options.Format, '2D', 'IgnoreCase', false)
                saving3d = '2D';
            else
                saving3d = '5D';
            end

            % --- normalise filename to .ome.tiff extension ---
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            % Strip a double .ome.tiff if the user already included it
            if strcmpi(ext, '.tiff') && endsWith(lower(baseName), '.ome')
                baseName = baseName(1:end-4);  % remove trailing '.ome'
            end
            fullFilepath = fullfile(pathStr, [baseName '.ome.tiff']);
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr, 'dir') ~= 7; mkdir(pathStr); end

            % --- "Define naming" dialog (2D mode only) ---
            if strcmp(saving3d, '2D') && ~options.silent && ~callerSetFilename
                prompts = {'Filename generator:'};
                defAns  = {{'Use original filename', 'Use sequential filename', 2}};
                dlgOpts.mibPath     = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'Define naming', dlgOpts);
                if isempty(answer); return; end
                options.FilenameGenerator = answer{1};
            end

            % --- permute MIB3 [H,W,D,C,T] → [H,W,C,D,T] for mibImage2ometiff ---
            img_hwcdt = permute(data, [1 2 4 3 5]);  % [H, W, C, D, T]

            % --- build savingOptions for mibImage2ometiff ---
            savingOptions.DimensionOrder = 'XYCZT';
            savingOptions.Saving3d       = saving3d;
            savingOptions.overwrite      = options.overwrite;
            savingOptions.DatasetType    = options.layerType;
            savingOptions.showWaitbar    = options.showWaitbar;
            savingOptions.silent         = options.silent;
            savingOptions.sequentialFn   = strcmp(options.FilenameGenerator, 'Use sequential filename');
            savingOptions.ParentFigure   = obj.ParentFigure;

            if isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                savingOptions.pixSize = metadata.pixSize;
            else
                savingOptions.pixSize = struct('x',1,'y',1,'z',1, ...
                    'units','um','t',1,'tunits','s');
            end

            if isfield(metadata, 'lutColors') && ~isempty(metadata.lutColors)
                savingOptions.lutColors = metadata.lutColors;
            else
                savingOptions.lutColors = ones(size(data,4), 3);
            end

            if isfield(metadata, 'imageDescription')
                savingOptions.ImageDescription = metadata.imageDescription;
            else
                savingOptions.ImageDescription = '';
            end

            % Pass per-slice source filenames for the 'Use original filename' path
            if isfield(metadata, 'sliceName') && ~isempty(metadata.sliceName)
                savingOptions.SliceName = metadata.sliceName;
            end

            % --- call io.BioFormats.mibImage2ometiff (already in MIB3) ---
            try
                io.BioFormats.mibImage2ometiff(fullFilepath, img_hwcdt, savingOptions);
            catch ME
                error('OmeTiffSaver:saveError', ...
                    ['io.BioFormats.mibImage2ometiff() failed.\n' ...
                     'Check that mib/+io/+BioFormats/mibImage2ometiff.m exists ' ...
                     'and the BioFormats Java library is on the Java class path.\n\n' ...
                     'Original error: %s'], ME.message);
            end

            fnOut = fullFilepath;
            fprintf('OmeTiffSaver: saved → %s\n', fullFilepath);
        end

        function fnOut = saveStream(obj, provider, metadata, filename, options)
            % SAVESTREAM - Stream an OME-TIFF from a SliceProvider (memory-bounded).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.saveStream(provider, metadata, filename, options)
            %
            % Memory-bounded twin of ``save``: instead of receiving a full
            % ``[H W D C T]`` array it pulls each Z-slice from ``provider.getSlice(z, t)``
            % (an ``io.savers.SliceProvider``) so a large pyramid level is never gathered
            % whole — peak memory stays at one XY slice.
            %
            % - **5D mode** — writes a single OME-TIFF, streaming one plane at a time
            %   through the Bio-Formats Java writer (``loci.formats.ImageWriter`` /
            %   ``OMETiffWriter.saveBytes``). OME-XML metadata is built from the provider's
            %   dimensions (``MetadataTools.populateMetadata``), so no full array is needed.
            % - **2D sequence mode** — writes one ``.ome.tiff`` per Z×T slice via ``imwrite``.
            %
            % NOTE: streaming bounds memory along Z. A single very large XY plane (e.g.
            % a gigapixel WSI at full resolution, Z=1) is still held whole; tiled BigTIFF
            % output for that case is separate future work.
            %
            % Input/Output: see ``io.savers.BaseSaver.saveStream``.
            if nargin < 5; options = struct(); end
            fnOut = [];

            callerSetFilename = isfield(options, 'FilenameGenerator');

            % --- defaults (mirror save) ---
            if ~isfield(options, 'showWaitbar');       options.showWaitbar       = true;  end
            if ~isfield(options, 'silent');            options.silent            = false; end
            if ~isfield(options, 'overwrite');         options.overwrite         = true;  end
            if ~isfield(options, 'layerType');         options.layerType         = 'image'; end
            if ~isfield(options, 'Format');            options.Format            = 'OME-TIFF 5D (*.ome.tiff)'; end
            if ~isfield(options, 'FilenameGenerator'); options.FilenameGenerator = 'Use sequential filename'; end

            if contains(options.Format, '2D', 'IgnoreCase', false)
                saving3d = '2D';
            else
                saving3d = '5D';
            end

            % --- normalise filename to .ome.tiff extension ---
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if strcmpi(ext, '.tiff') && endsWith(lower(baseName), '.ome')
                baseName = baseName(1:end-4);
            end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr, 'dir') ~= 7; mkdir(pathStr); end
            fullFilepath = fullfile(pathStr, [baseName '.ome.tiff']);

            % --- "Define naming" dialog (2D mode only) ---
            if strcmp(saving3d, '2D') && ~options.silent && ~callerSetFilename
                prompts = {'Filename generator:'};
                defAns  = {{'Use original filename', 'Use sequential filename', 2}};
                dlgOpts.mibPath     = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'Define naming', dlgOpts);
                if isempty(answer); return; end
                options.FilenameGenerator = answer{1};
            end

            % --- pixel size (default 1×1×1 µm) ---
            if isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                pixSize = metadata.pixSize;
            else
                pixSize = struct('x',1,'y',1,'z',1,'units','um','t',1,'tunits','s');
            end

            if strcmp(saving3d, '5D')
                fnOut = obj.writeOmeTiffStream5D(provider, metadata, pixSize, fullFilepath, options);
            else
                fnOut = obj.writeOmeTiffStream2D(provider, metadata, pixSize, pathStr, baseName, options);
            end
        end

    end

    % ------------------------------------------------------------------ %
    %   Private streaming helpers                                          %
    % ------------------------------------------------------------------ %
    methods (Access = private)

        function fnOut = writeOmeTiffStream5D(obj, provider, metadata, pixSize, fullFilepath, options)
            % WRITEOMETIFFSTREAM5D - Stream a single OME-TIFF plane-by-plane.
            %
            % Builds OME-XML metadata from the provider's dimensions (no full array),
            % opens the Bio-Formats Java writer, and writes each plane in XYCZT order
            % (C fastest, then Z, then T) pulling one [H W C] slice from the provider per
            % (z, t). Mirrors ``bfsave``'s plane loop / byte conversion and
            % ``io.BioFormats.mibImage2ometiff``'s metadata setup.
            utils.ensureJavaLibraries({'bioformats'});

            sz = provider.OutputSize;
            H = sz(1); W = sz(2); D = sz(3); C = sz(4); T = sz(5);
            imgClass = provider.DataClass;

            [pixelType, getBytes] = io.savers.OmeTiffSaver.pixelTypeAndConverter(imgClass);

            % scale physical sizes to micrometers (normalize long spellings, e.g. zarr 'micrometers')
            scaleFactor = io.savers.OmeTiffSaver.umScaleFactor(pixSize.units);
            pxX = pixSize.x * scaleFactor;
            pxY = pixSize.y * scaleFactor;
            pxZ = pixSize.z * scaleFactor;
            tIncr  = 1; if isfield(pixSize, 't') && ~isempty(pixSize.t); tIncr = pixSize.t; end
            tunits = io.savers.OmeTiffSaver.omeTimeUnit(pixSize);

            % --- OME metadata from dimensions ---
            littleEndian = true;
            meta = loci.formats.MetadataTools.createOMEXMLMetadata();
            loci.formats.MetadataTools.populateMetadata(meta, 0, [], littleEndian, ...
                'XYCZT', pixelType, W, H, D, C, T, 1);
            meta.setPixelsPhysicalSizeX(ome.units.quantity.Length(java.lang.Double(pxX), ome.units.UNITS.MICROMETER), 0);
            meta.setPixelsPhysicalSizeY(ome.units.quantity.Length(java.lang.Double(pxY), ome.units.UNITS.MICROMETER), 0);
            meta.setPixelsPhysicalSizeZ(ome.units.quantity.Length(java.lang.Double(pxZ), ome.units.UNITS.MICROMETER), 0);
            meta.setPixelsTimeIncrement(ome.units.quantity.Time(java.lang.Double(tIncr), tunits), 0);

            % ImageDescription — carries the MIB BoundingBox string
            if isfield(metadata, 'imageDescription') && ~isempty(metadata.imageDescription)
                desc = metadata.imageDescription;
                if iscell(desc); desc = desc{1}; end
                if ~isempty(desc); meta.setImageDescription(desc, 0); end
            end

            % Channel LUT colours
            if isfield(metadata, 'lutColors') && ~isempty(metadata.lutColors)
                nCh = min(C, size(metadata.lutColors, 1));
                for iCh = 1:nCh
                    r = int32(round(metadata.lutColors(iCh, 1) * 255));
                    g = int32(round(metadata.lutColors(iCh, 2) * 255));
                    b = int32(round(metadata.lutColors(iCh, 3) * 255));
                    meta.setChannelColor(ome.xml.model.primitives.Color(r, g, b, int32(255)), 0, iCh-1);
                end
            end

            % --- writer ---
            if exist(fullFilepath, 'file') == 2; delete(fullFilepath); end
            loci.common.DebugTools.enableLogging('ERROR');
            imageWriter = javaObject('loci.formats.ImageWriter');
            writer = imageWriter.getWriter(fullFilepath);
            writer.setWriteSequentially(true);
            writer.setMetadataRetrieve(meta);
            if isfield(options, 'Compression') && ~isempty(options.Compression) && ...
                    ~strcmpi(options.Compression, 'none')
                try; writer.setCompression(options.Compression); catch; end %#ok<NOSEMI,CTCH>
            end
            writer.setId(fullFilepath);

            wb = [];
            if options.showWaitbar
                wb = obj.createProgressDialog('Saving OME-TIFF...', sprintf('Writing %s', fullFilepath), true);
            end

            try
                index = 0;
                total = D * T; done = 0;
                for t = 1:T
                    for z = 1:D
                        if ~isempty(wb) && wb.CancelRequested
                            writer.close();
                            delete(wb);
                            if exist(fullFilepath, 'file') == 2; delete(fullFilepath); end
                            fnOut = [];
                            return;
                        end
                        slice = provider.getSlice(z, t);   % [H W C]
                        for c = 1:C
                            plane = slice(:, :, c).';      % transpose → X-fastest byte order (mirror bfsave)
                            writer.saveBytes(index, getBytes(plane));
                            index = index + 1;
                        end
                        done = done + 1;
                        if ~isempty(wb); wb.Value = done/total; end
                    end
                end
                writer.close();
            catch ME
                try; writer.close(); catch; end %#ok<NOSEMI,CTCH>
                if ~isempty(wb); delete(wb); end
                rethrow(ME);
            end
            if ~isempty(wb); delete(wb); end

            fnOut = fullFilepath;
            fprintf('OmeTiffSaver: streamed → %s\n', fullFilepath);
        end

        function fnOut = writeOmeTiffStream2D(obj, provider, metadata, pixSize, pathStr, baseName, options)
            % WRITEOMETIFFSTREAM2D - Stream a 2-D OME-TIFF sequence (one file per Z×T slice).
            %
            % Pulls each slice from the provider and writes it with ``imwrite`` (matching
            % the 2-D branch of ``io.BioFormats.mibImage2ometiff``), so the full stack is
            % never resident. Honours the ``FilenameGenerator`` policy via
            % ``BaseSaver.buildSliceNames``.
            sz = provider.OutputSize;
            D = sz(3); T = sz(5);

            resolution = utils.calculateResolution(pixSize);

            descBase = '';
            if isfield(metadata, 'imageDescription') && ~isempty(metadata.imageDescription)
                descBase = metadata.imageDescription;
                if iscell(descBase); descBase = descBase{1}; end
            end

            cmap = NaN;
            if isfield(metadata, 'colorType') && strcmp(metadata.colorType, 'indexed') && ...
                    isfield(metadata, 'lutColors') && size(metadata.lutColors, 1) > 1
                cmap = metadata.lutColors;
            end

            baseNames = obj.buildSliceNames(baseName, pathStr, D, '.ome.tiff', options, metadata);

            wb = [];
            if options.showWaitbar
                wb = obj.createProgressDialog('Saving OME-TIFF...', ...
                    sprintf('Writing %s sequence', baseName), true);
            end

            allFn = {};
            total = D * T; done = 0;
            for t = 1:T
                for z = 1:D
                    if ~isempty(wb) && wb.CancelRequested; delete(wb); fnOut = []; return; end
                    [~, sn, se] = fileparts(baseNames{z});
                    if T > 1
                        outFn = fullfile(pathStr, sprintf('%s_T%03d%s', sn, t, se));
                    else
                        outFn = fullfile(pathStr, [sn se]);
                    end
                    slice = squeeze(provider.getSlice(z, t));   % [H W] or [H W C]
                    descArgs = {};
                    if ~isempty(descBase); descArgs = {'Description', descBase}; end
                    if isnan(cmap)
                        imwrite(slice, outFn, 'tif', 'Compression', 'none', descArgs{:}, 'Resolution', resolution);
                    else
                        imwrite(slice, cmap, outFn, 'tif', 'Compression', 'none', descArgs{:}, 'Resolution', resolution);
                    end
                    allFn{end+1} = outFn; %#ok<AGROW>
                    done = done + 1;
                    if ~isempty(wb); wb.Value = done/total; end
                end
            end
            if ~isempty(wb); delete(wb); end
            fnOut = allFn;
            fprintf('OmeTiffSaver: streamed 2D sequence → %s\n', pathStr);
        end

    end

    methods (Static, Access = private)

        function [pixelType, getBytes] = pixelTypeAndConverter(imgClass)
            % PIXELTYPEANDCONVERTER - OME pixel-type string + MATLAB→bytes converter.
            % Mirrors bfsave's per-class byte conversion (little-endian).
            switch imgClass
                case {'int8', 'uint8'}
                    pixelType = imgClass;
                    getBytes  = @(x) x(:);
                case {'uint16', 'int16'}
                    pixelType = imgClass;
                    getBytes  = @(x) javaMethod('shortsToBytes', 'loci.common.DataTools', x(:), true);
                case {'uint32', 'int32'}
                    pixelType = imgClass;
                    getBytes  = @(x) javaMethod('intsToBytes', 'loci.common.DataTools', x(:), true);
                case 'single'
                    pixelType = 'float';
                    getBytes  = @(x) javaMethod('floatsToBytes', 'loci.common.DataTools', x(:), true);
                case 'double'
                    pixelType = 'double';
                    getBytes  = @(x) javaMethod('doublesToBytes', 'loci.common.DataTools', x(:), true);
                otherwise
                    error('OmeTiffSaver:unsupportedClass', ...
                        'Unsupported pixel class for OME-TIFF streaming: %s', imgClass);
            end
        end

        function scaleFactor = umScaleFactor(units)
            % UMSCALEFACTOR - factor that converts a length in `units` to micrometers.
            switch utils.normalizeUnits(units)
                case 'm';  scaleFactor = 1e6;
                case 'cm'; scaleFactor = 1e4;
                case 'mm'; scaleFactor = 1e3;
                case 'um'; scaleFactor = 1;
                case 'nm'; scaleFactor = 1e-3;
                otherwise; scaleFactor = 1;   % 'pixels'/unknown → no scaling
            end
        end

        function tunits = omeTimeUnit(pixSize)
            % OMETIMEUNIT - map pixSize.tunits to an ome.units.UNITS time unit.
            tu = 's';
            if isfield(pixSize, 'tunits') && ~isempty(pixSize.tunits)
                tu = lower(strtrim(char(pixSize.tunits)));
            end
            switch tu
                case {'min', 'm', 'minute', 'minutes'}; tunits = ome.units.UNITS.MINUTE;
                case {'hour', 'h', 'hours'};            tunits = ome.units.UNITS.HOUR;
                otherwise;                               tunits = ome.units.UNITS.SECOND;
            end
        end

    end
end
