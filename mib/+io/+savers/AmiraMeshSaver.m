classdef AmiraMeshSaver < io.savers.BaseSaver
    % classdef AmiraMeshSaver < io.savers.BaseSaver
    % Saver for Amira Mesh binary format output.
    %
    % Handles five format variants:
    %   'Amira Mesh binary (*.am)'                      — full 3-D volume,
    %       binary encoding, image layer
    %   'Amira Mesh binary file sequence (*.am)'        — per-slice .am files,
    %       binary encoding, image layer
    %   'Amira mesh binary (*.am)'                      — alias for labels/masks
    %   'Amira mesh binary RLE compression SLOW (*.am)' — run-length encoded,
    %       binary, labels/masks only
    %   'Amira mesh ascii (*.am)'                       — ASCII text encoding,
    %       labels/masks only
    %
    % The active layer type (image vs. mask/labels) is determined by
    % options.layerType (default 'image').  Image data is passed to the
    % legacy helper bitmap2amiraMesh(); mask and labels data are passed to
    % bitmap2amiraLabels().
    %
    % DATA DIMENSIONS
    %   Input  data : [H, W, D, C, T]  (MIB3 native order)
    %   bitmap2amiraMesh() expects [H, W, C, D] — permuted via
    %       obj.permuteMib3ToHWCD() for the first time point.
    %   bitmap2amiraLabels() expects [H, W, D] — squeezed from data.
    %
    % PIXEL-SIZE STRUCT (pixStr)
    %   For bitmap2amiraLabels the pixStr is extended with bounding-box
    %   origin fields:
    %     pixStr = metadata.pixSize
    %     pixStr.minx = boundingBox(1)
    %     pixStr.miny = boundingBox(3)
    %     pixStr.minz = boundingBox(5)
    %
    % COMPRESSION STRINGS
    %   Format string                                   compression arg
    %   'Amira Mesh binary (*.am)'                   → 'binary'
    %   'Amira Mesh binary file sequence (*.am)'     → 'binary'
    %   'Amira mesh binary (*.am)'                   → 'binary'
    %   'Amira mesh binary RLE compression SLOW (*.am)' → 'binaryRLE'
    %   'Amira mesh ascii (*.am)'                    → 'ascii'
    %
    % TODO: port bitmap2amiraMesh from
    %   MIB2_RENAMED_FOR_MIB3/ImportExportTools/Amira/bitmap2amiraMesh.m
    %   to mib/+io/+AmiraMesh/bitmap2amiraMesh.m
    %
    % TODO: port bitmap2amiraLabels from
    %   MIB2_RENAMED_FOR_MIB3/ImportExportTools/Amira/bitmap2amiraLabels.m
    %   to mib/+io/+AmiraMesh/bitmap2amiraLabels.m
    %
    % USAGE EXAMPLES
    %   @code
    %   %% 1. Save image volume as Amira Mesh binary
    %   saver = io.SaverFactory.create('Amira Mesh binary (*.am)');
    %
    %   opts.Format         = 'Amira Mesh binary (*.am)';
    %   opts.showWaitbar    = false;
    %   opts.silent         = true;
    %   opts.overwrite      = true;
    %   opts.layerType      = 'image';
    %
    %   meta.filename       = 'source_stack.tif';
    %   meta.colorType      = 'grayscale';
    %   meta.lutColors      = [1 1 1];
    %   meta.dataClass      = 'uint8';
    %   meta.maxInt         = 255;
    %   meta.pixSize        = struct('x',0.065,'y',0.065,'z',0.2, ...
    %                                'units','um','t',1,'tunits','s');
    %   meta.boundingBox    = [0 33.3 0 33.3 0 10];
    %
    %   data = uint8(rand(512,512,50,1,1)*255);  % [H W D C T]
    %   fnOut = saver.save(data, meta, '/output/myStack.am', opts);
    %   fprintf('Saved: %s\n', fnOut);
    %   @endcode
    %
    %   @code
    %   %% 2. Save segmentation labels as Amira mesh binary
    %   saver = io.SaverFactory.create('Amira mesh binary (*.am)');
    %
    %   opts.Format         = 'Amira mesh binary (*.am)';
    %   opts.showWaitbar    = false;
    %   opts.silent         = true;
    %   opts.overwrite      = true;
    %   opts.layerType      = 'labels';
    %
    %   meta.filename       = 'source_stack.tif';
    %   meta.pixSize        = struct('x',0.065,'y',0.065,'z',0.2, ...
    %                                'units','um','t',1,'tunits','s');
    %   meta.boundingBox    = [0 33.3 0 33.3 0 10];
    %   meta.materialNames  = {'Nucleus'; 'ER'};
    %   meta.materialColors = [0 0 1; 0 1 0];
    %
    %   labels = uint8(rand(512,512,50,1,1) * 2);  % [H W D C T]
    %   fnOut = saver.save(labels, meta, '/output/Labels_myStack.am', opts);
    %   @endcode
    %
    %   @code
    %   %% 3. Save labels with RLE compression
    %   saver = io.SaverFactory.create( ...
    %       'Amira mesh binary RLE compression SLOW (*.am)');
    %
    %   opts.Format      = 'Amira mesh binary RLE compression SLOW (*.am)';
    %   opts.layerType   = 'labels';
    %   opts.showWaitbar = true;
    %   opts.silent      = true;
    %   opts.overwrite   = true;
    %
    %   fnOut = saver.save(labels, meta, '/output/Labels_RLE.am', opts);
    %   @endcode
    %
    % SEE ALSO
    %   io.SaverFactory, io.savers.BaseSaver, io.savers.TiffSaver,
    %   core.MibImage.save, core.MibDataset.save, models.MibModel.save

    methods

        function obj = AmiraMeshSaver(options)
            % function obj = AmiraMeshSaver(options)
            % Constructor — accepts an optional options struct.
            %
            % Parameters:
            %   options — (struct, optional) saver-level options (usually empty;
            %             per-save options are passed to save() instead)
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            % function formats = getSupportedFormats(~)
            % Return format strings handled by AmiraMeshSaver.
            formats = { ...
                'Amira Mesh binary (*.am)'; ...
                'Amira Mesh binary file sequence (*.am)'; ...
                'Amira mesh binary (*.am)'; ...
                'Amira mesh binary RLE compression SLOW (*.am)'; ...
                'Amira mesh ascii (*.am)' };
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % function fnOut = save(obj, data, metadata, filename, options)
            % Write data as an Amira Mesh file (image or labels/mask).
            %
            % Parameters:
            %   data     — [H, W, D, C, T] numeric array
            %   metadata — struct; used fields:
            %     .colorType      — 'grayscale' | 'multichannel' | 'indexed'
            %     .lutColors      — [C x 3] per-channel LUT colours (0..1)
            %     .dataClass      — 'uint8' | 'uint16' | ...
            %     .maxInt         — maximum intensity value
            %     .pixSize        — struct {.x .y .z .units .t .tunits}
            %     .boundingBox    — [xmin xmax ymin ymax zmin zmax]
            %     .materialNames  — cell array of material name strings
            %                       (labels mode only)
            %     .materialColors — [M x 3] material RGB colours (labels mode)
            %   filename — full output path, e.g. '/out/stack.am'
            %   options  — struct; used fields:
            %     .Format         — format string (selects encoding)
            %     .layerType      — 'image' | 'mask' | 'labels' (default 'image')
            %     .showWaitbar    — logical
            %     .silent         — logical, suppress dialogs
            %     .overwrite      — logical
            %
            % Return values:
            %   fnOut — (char) path of saved .am file, [] on failure
            %
            % Example — see class-level documentation above.

            fnOut = [];

            % Track which options were explicitly provided by the caller
            callerSetFilename = isfield(options, 'FilenameGenerator');

            % --- defaults ---
            if ~isfield(options, 'showWaitbar');       options.showWaitbar       = true;    end
            if ~isfield(options, 'silent');            options.silent            = false;   end
            if ~isfield(options, 'overwrite');         options.overwrite         = true;    end
            if ~isfield(options, 'layerType');         options.layerType         = 'image'; end
            if ~isfield(options, 'Format');            options.Format            = 'Amira Mesh binary (*.am)'; end
            if ~isfield(options, 'FilenameGenerator'); options.FilenameGenerator = 'Use sequential filename'; end

            % --- decompose filename ---
            [pathStr, baseName, ext] = obj.splitFilename(filename); % split the filename and make lower(extension)
            if isempty(ext); ext = '.am'; end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr, 'dir') ~= 7; mkdir(pathStr); end
            fullFilepath = fullfile(pathStr, [baseName ext]);

            % --- map format string to compression string ---
            compressionStr = obj.formatToCompression(options.Format);

            % --- dispatch based on layer type ---
            isImageMode = strcmpi(options.layerType, 'image');

            if isImageMode
                % Build metadata dictionary for bitmap2amiraMesh.
                % All fields end up in the im_browser {} section of the AM header,
                % making the file self-describing (matches MIB2 output format).
                % Data is in MIB3 native order [H, W, D, C, T]; only first T is written.
                [nH, nW, nD, nC, nT] = size(data);
                metaMap = configureDictionary("string", "cell");

                % --- physical metadata ---
                if isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                    metaMap("pixSize") = {metadata.pixSize};
                end
                if isfield(metadata, 'boundingBox') && ~isempty(metadata.boundingBox)
                    metaMap("BoundingBox") = {metadata.boundingBox};
                end

                % --- full ImageDescription (BoundingBox prefix + action log) ---
                if isfield(metadata, 'imageDescription')
                    metaMap("ImageDescription") = {metadata.imageDescription};
                end

                % --- image properties ---
                if isfield(metadata, 'colorType')
                    metaMap("ColorType") = {metadata.colorType};
                end
                if isfield(metadata, 'lutColors')
                    metaMap("lutColors") = {metadata.lutColors};
                end
                if isfield(metadata, 'maxInt')
                    metaMap("MaxInt") = {metadata.maxInt};
                end
                if isfield(metadata, 'dataClass') && ~isempty(metadata.dataClass)
                    metaMap("imgClass") = {metadata.dataClass};
                end

                % --- dimensions ---
                metaMap("Height") = {nH};
                metaMap("Width")  = {nW};
                metaMap("Depth")  = {nD};
                metaMap("Colors") = {nC};
                metaMap("Time")   = {nT};

                % --- file origin ---
                if isfield(metadata, 'filename') && ~isempty(metadata.filename)
                    metaMap("Filename") = {metadata.filename};
                end

                % --- resolution tags (from pixSize, as stored in TIFF XResolution) ---
                if isfield(metadata, 'xResolution') && ~isempty(metadata.xResolution)
                    metaMap("XResolution")   = {metadata.xResolution};
                    metaMap("YResolution")   = {metadata.yResolution};
                    metaMap("ResolutionUnit") = {"Inch"};
                end

                savingOptions.overwrite     = options.overwrite;
                savingOptions.showWaitbar   = options.showWaitbar;
                savingOptions.compression   = compressionStr;
                savingOptions.Saving3d      = 'multi';
                savingOptions.ParentFigure  = obj.ParentFigure;
                if contains(options.Format, 'sequence', 'IgnoreCase', true)
                    savingOptions.Saving3d = 'sequence';

                    % --- "Define naming" dialog ---
                    % Show when slice names are available and FilenameGenerator
                    % was not explicitly provided by the caller.
                    if ~options.silent && ~callerSetFilename && ...
                            isfield(metadata, 'sliceName') && numel(metadata.sliceName) == nD && ...
                            nT == 1 && nD > 1
                        prompts  = {'Filename generator:'};
                        defAns   = {{'Use original filename', 'Use sequential filename', 1}};
                        dlgOpts.mibPath     = obj.mibPath;
                        dlgOpts.WindowStyle = 'modal';
                        answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                            'Define naming', dlgOpts);
                        if isempty(answer); return; end
                        options.FilenameGenerator = answer{1};
                    end

                    % Build per-slice output names and pass to bitmap2amiraMesh.
                    % bitmap2amiraMesh prepends saveDir internally, so strip
                    % the directory component and pass filenames only.
                    slicePaths = obj.buildSliceNames(baseName, pathStr, nD, ext, options, metadata);
                    fnOnly = cell(size(slicePaths));
                    for k = 1:numel(slicePaths)
                        [~, fn, fe] = fileparts(slicePaths{k});
                        fnOnly{k} = [fn, fe];
                    end
                    savingOptions.SliceName = fnOnly;
                end

                io.AmiraMesh.bitmap2amiraMesh(fullFilepath, data(:,:,:,:,1), metaMap, savingOptions);

            else
                % Mask / labels saving: squeeze to [H, W, D]
                maskOrLabels_hwd = squeeze(data(:,:,:,1,1));

                % Build pixStr with bounding-box origin
                if isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                    pixStr = metadata.pixSize;
                else
                    pixStr = struct('x',1,'y',1,'z',1,'units','um','t',1,'tunits','s');
                end
                if isfield(metadata, 'boundingBox') && numel(metadata.boundingBox) >= 6
                    bb = metadata.boundingBox;
                    pixStr.minx = bb(1);
                    pixStr.miny = bb(3);
                    pixStr.minz = bb(5);
                else
                    pixStr.minx = 0;
                    pixStr.miny = 0;
                    pixStr.minz = 0;
                end

                % Material colours
                if isfield(metadata, 'materialColors') && ~isempty(metadata.materialColors)
                    colorList = metadata.materialColors;
                else
                    colorList = rand(1, 3);
                end

                % Material names
                if isfield(metadata, 'materialNames') && ~isempty(metadata.materialNames)
                    materialNames = metadata.materialNames;
                else
                    materialNames = {'Material 1'};
                end

                extraOptions.overwrite      = options.overwrite;
                extraOptions.silent         = options.silent;
                extraOptions.ParentFigure   = obj.ParentFigure;

                % TODO: port bitmap2amiraLabels from
                %   MIB2_RENAMED_FOR_MIB3/ImportExportTools/Amira/bitmap2amiraLabels.m
                %   to mib/+io/+AmiraMesh/bitmap2amiraLabels.m
                try
                    io.AmiraMesh.bitmap2amiraLabels(fullFilepath, ...
                        maskOrLabels_hwd, compressionStr, pixStr, ...
                        colorList, materialNames, 1, options.showWaitbar, extraOptions);
                catch ME
                    error('AmiraMeshSaver:missingLabelsHelper', ...
                        ['bitmap2amiraLabels() is not yet available.\n' ...
                         'Please port it from:\n' ...
                         '  MIB2_RENAMED_FOR_MIB3/ImportExportTools/Amira/bitmap2amiraLabels.m\n' ...
                         'to:\n' ...
                         '  mib/+io/+AmiraMesh/bitmap2amiraLabels.m\n\n' ...
                         'Original error: %s'], ME.message);
                end
            end

            fnOut = fullFilepath;
            %fprintf('AmiraMeshSaver: saved → %s\n', fullFilepath);
        end

    end

    % ------------------------------------------------------------------ %
    %   Private helpers                                                    %
    % ------------------------------------------------------------------ %
    methods (Access = private)

        function compressionStr = formatToCompression(~, formatStr)
            % function compressionStr = formatToCompression(~, formatStr)
            % Map an Amira format string to the compression argument string
            % expected by bitmap2amiraMesh / bitmap2amiraLabels.
            %
            % Parameters:
            %   formatStr — (char) format string from getSupportedFormats()
            %
            % Return values:
            %   compressionStr — 'binary' | 'binaryRLE' | 'ascii'
            if contains(formatStr, 'RLE', 'IgnoreCase', true)
                compressionStr = 'binaryRLE';
            elseif contains(formatStr, 'ascii', 'IgnoreCase', true)
                compressionStr = 'ascii';
            else
                compressionStr = 'binary';
            end
        end

    end
end
