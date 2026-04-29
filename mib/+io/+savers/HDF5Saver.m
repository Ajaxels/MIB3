classdef HDF5Saver < io.savers.BaseSaver
% HDF5SAVER - Saver for Hierarchical Data Format (HDF5) output.
%
% Handles three format variants:
% 'Hierarchical Data Format (``*.h5``)'                — standard HDF5 file
% 'Hierarchical Data Format with XML header (``*.xml``)' — HDF5 with an
% accompanying XML header (Ilastik/MIB-compatible, matlab.hdf5)
% 'Big Data Viewer HDF5 (``*.h5``)'                    — Fiji BigDataViewer
% format with int16 data, image pyramid, and mandatory XML header
%
% Both image data and mask/labels layers can be saved.  The layer type is
% controlled by options.layerType ('image' | 'mask' | 'labels').
%
% The saver delegates the actual I/O to:
% io.HDF5.image2hdf5()            for the first two formats
% io.HDF5.saveBigDataViewerFormat() for the BDV format
% For any XML variant io.HDF5.saveXMLheader() is called afterwards.
%
% DATA DIMENSIONS
% Input  data : [H, W, D, C, T]  (MIB3 native order)
%
% NOTES
% * Sub-sampling (options.SubSampling) is a [3 x L] matrix where
% each column is [xFactor; yFactor; zFactor] for one pyramid level.
% Default (silent mode): [1;1;1] — no downsampling.
% * ChunkSize defaults to min([64, H, W, D]) for each spatial dim.
% * Deflate=0 disables zlib compression; use 1–9 for increasing
% compression ratio vs. speed trade-off.
% * BDV format always forces an XML header and converts data to int16.
% * When options.silent is true the saver uses all defaults without
% showing any dialogs.
%
% USAGE EXAMPLES
%
% .. code-block:: matlab
%
%     %% 1. Direct saver use — save 5-D image to HDF5
%     saver = io.SaverFactory.create('Hierarchical Data Format (``*.h5``)');
%
%     opts.Format         = 'Hierarchical Data Format (``*.h5``)';
%     opts.showWaitbar    = false;
%     opts.silent         = true;
%     opts.overwrite      = true;
%     opts.layerType      = 'image';
%
%     meta.filename       = 'source_stack.tif';
%     meta.colorType      = 'grayscale';
%     meta.lutColors      = [1 1 1];
%     meta.dataClass      = 'uint16';
%     meta.maxInt         = 65535;
%     meta.pixSize        = struct('x',0.065,'y',0.065,'z',0.2, ...
%                                  'units','um','t',1,'tunits','s');
%     meta.boundingBox    = [0 33.3 0 33.3 0 10];
%     meta.imageDescription = 'My EM dataset';
%
%     data = uint16(rand(512,512,50,1,1) * 65535);  % [H W D C T]
%     fnOut = saver.save(data, meta, '/output/myStack.h5', opts);
%     fprintf('Saved: %s\n', fnOut);
%
%
%
% .. code-block:: matlab
%
%     %% 2. Save in Fiji BigDataViewer format (int16, image pyramid, XML)
%     saver = io.SaverFactory.create('Big Data Viewer HDF5 (``*.h5``)');
%
%     opts.Format         = 'Big Data Viewer HDF5 (``*.h5``)';
%     opts.showWaitbar    = true;
%     opts.silent         = true;
%     opts.overwrite      = true;
%     opts.SubSampling    = [1 2 4; 1 2 4; 1 2 4];  % 3-level pyramid
%     opts.ChunkSize      = [64;64;64];
%     opts.Deflate        = 0;
%
%     meta.pixSize        = struct('x',0.065,'y',0.065,'z',0.2, ...
%                                  'units','um','t',1,'tunits','s');
%     meta.boundingBox    = [0 33.3 0 33.3 0 10];
%
%     data = uint16(rand(512,512,50,1,1) * 65535);
%     fnOut = saver.save(data, meta, '/output/myStack.h5', opts);
%     % Produces myStack.h5 + myStack.xml
%
%
%
% .. code-block:: matlab
%
%     %% 3. Via MibModel batch — save labels as HDF5
%     BatchOpt.LayerType       = {'labels'};
%     BatchOpt.Format          = {'Hierarchical Data Format (``*.h5``)'};
%     BatchOpt.OutputDirectoryPolicy = {'Full path'};
%     BatchOpt.DestinationDirectory  = '/output/dir';
%     BatchOpt.FilenamePolicy  = {'Use existing name'};
%     BatchOpt.showWaitbar     = false;
%     BatchOpt.mibBatchTooltip.LayerType = '';
%     model.save('labels', [], BatchOpt);
%
%
% SEE ALSO
% io.SaverFactory, io.savers.BaseSaver, io.savers.TiffSaver,
% io.HDF5.image2hdf5, io.HDF5.saveBigDataViewerFormat,
% io.HDF5.saveXMLheader,
% core.MibImage.save, core.MibDataset.save, models.MibModel.save

    methods

        function obj = HDF5Saver(options)
            % HDF5SAVER - Constructor — accepts an optional options struct.
            %
            % Syntax:
            %   function obj = HDF5Saver(options)
            %
            % Input Arguments:
            %   options — (struct, optional) saver-level options (usually empty;
            %   per-save options are passed to save() instead)
            %
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            % GETSUPPORTEDFORMATS - Return format strings handled by HDF5Saver.
            %
            % Syntax:
            %   function formats = getSupportedFormats(~)
            %
            formats = { ...
                'Hierarchical Data Format (*.h5)'; ...
                'Hierarchical Data Format with XML header (*.xml)'; ...
                'Big Data Viewer HDF5 (*.h5)' };
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % SAVE - Write data as an HDF5 file (standard, XML-header, or BDV variant).
            %
            % Syntax:
            %   function fnOut = save(obj, data, metadata, filename, options)
            %
            % Input Arguments:
            %   data     — [H, W, D, C, T] numeric array
            %   metadata — struct; used fields:
            %   .colorType        — 'grayscale' | 'multichannel' | 'indexed'
            %   .lutColors        — [C x 3] per-channel LUT colours (0..1)
            %   .dataClass        — 'uint8' | 'uint16' | ...
            %   .maxInt           — maximum intensity value
            %   .pixSize          — struct {.x .y .z .units .t .tunits}
            %   .boundingBox      — [xmin xmax ymin ymax zmin zmax]
            %   .imageDescription — (char) dataset description string
            %   filename — full output path, e.g. '/out/stack.h5',
            %   '/out/stack.xml' for the XML-header variant, or
            %   '/out/stack.h5'  for the BDV variant
            %   options  — struct; used fields:
            %   .Format           — format string (selects saving mode)
            %   .layerType        — 'image' | 'mask' | 'labels' (default 'image')
            %   .showWaitbar      — logical
            %   .silent           — logical, suppress dialogs and use defaults
            %   .overwrite        — logical
            %   .SubSampling      — [3 x L] sub-sampling factors per level
            %   .ChunkSize        — [3 x 1] HDF5 chunk size [y x z]
            %   .Deflate          — integer 0-9 (zlib level)
            %   .DimOrder         — 'yxzct' | 'yxczt' (HDF5 only)
            %   .ResamplingMethod — 'nearest'|'bicubic'|'bilinear' (BDV only)
            %
            % Output Arguments:
            %   fnOut — (char) path of saved .h5 or .xml file, [] on failure
            %

            fnOut = [];

            % Track which options were explicitly provided by the caller
            callerSetChunkSize   = isfield(options, 'ChunkSize');
            callerSetDeflate     = isfield(options, 'Deflate');
            callerSetSubSampling = isfield(options, 'SubSampling');
            callerSetDimOrder    = isfield(options, 'DimOrder') && ~isempty(options.DimOrder);

            % --- defaults ---
            if ~isfield(options, 'showWaitbar'); options.showWaitbar = true;    end
            if ~isfield(options, 'silent');      options.silent      = false;   end
            if ~isfield(options, 'overwrite');   options.overwrite   = true;    end
            if ~isfield(options, 'layerType');   options.layerType   = 'image'; end
            if ~isfield(options, 'Format');      options.Format      = 'Hierarchical Data Format (*.h5)'; end

            % isXmlFormat: true for the explicit *.xml format entry
            isXmlFormat = contains(options.Format, 'xml', 'IgnoreCase', true);

            % --- decompose filename ---
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isXmlFormat
                if isempty(ext); ext = '.xml'; end
                h5Filename = fullfile(pathStr, [baseName '.h5']);
            else
                if isempty(ext); ext = '.h5'; end
                h5Filename = fullfile(pathStr, [baseName ext]);
            end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr, 'dir') ~= 7; mkdir(pathStr); end

            [nH, nW, nD, nC, nT] = size(data);
            defaultChunk = [min(64, nH); min(64, nW); min(64, max(1,nD))];

            % ============================================================
            % UNIFIED "HDF5 saving settings" DIALOG
            % ============================================================
            if ~options.silent && (~callerSetChunkSize || ~callerSetDeflate)
                % Default sub-sampling text (for BDV row)
                if callerSetSubSampling && ~isempty(options.SubSampling)
                    ss = options.SubSampling;
                    lvlStrs = arrayfun(@(c) num2str(ss(:,c)', '%g '), 1:size(ss,2), 'UniformOutput', false);
                    defSubSamp = strjoin(lvlStrs, '; ');
                else
                    defSubSamp = '1 1 1; 2 2 2; 4 4 4';
                end

                defUseChunk = callerSetChunkSize && ~isempty(options.ChunkSize);

                prompts = { ...
                    sprintf('Export format\n(dimension order):'); ...
                    'Chunk the dataset:'; ...
                    'Chunk Y (height):'; ...
                    'Chunk X (width):'; ...
                    'Chunk Z (depth):'; ...
                    sprintf('Deflate\n(0=none, 1-9=zlib):'); ...
                    sprintf('Create XML header\n(ignored for BDV):'); ...
                    sprintf('Sub-sampling (BDV only),\ne.g. "1 1 1" or "1 1 1; 2 2 2; 4 4 4":'); ...
                    sprintf('Resampling method\n(BDV only):')};

                defAns = { ...
                    {'yxzct - MIB3 default [H,W,D,C,T]', ...
                     'yxczt - MIB2/Ilastik [H,W,C,D,T]', ...
                     'bdv   - Fiji BigDataViewer (int16, pyramid)', 1}; ...
                    defUseChunk; ...
                    struct('Spinner',true,'Value',defaultChunk(1),'Limits',[1 nH],       'Step',1,'Round',true); ...
                    struct('Spinner',true,'Value',defaultChunk(2),'Limits',[1 nW],       'Step',1,'Round',true); ...
                    struct('Spinner',true,'Value',defaultChunk(3),'Limits',[1 max(1,nD)],'Step',1,'Round',true); ...
                    struct('Spinner',true,'Value',0,              'Limits',[0 9],        'Step',1,'Round',true); ...
                    isXmlFormat; ...
                    defSubSamp; ...
                    {'bicubic', 'nearest', 'bilinear', 1}};
                dlgOpts.mibPath       = obj.mibPath;
                dlgOpts.WindowStyle   = 'modal';
                dlgOpts.LabelPosition = 'left';
                dlgOpts.WindowWidth   = 600;
                dlgOpts.WindowHeight  = 360;
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'HDF5 saving settings', dlgOpts);
                if isempty(answer); return; end

                formatChoice = answer{1};
                isBDV        = startsWith(lower(strtrim(formatChoice)), 'bdv');
                useChunk     = answer{2};
                if useChunk
                    options.ChunkSize = [answer{3}; answer{4}; answer{5}];
                else
                    options.ChunkSize = [];
                end
                options.Deflate = answer{6};

                if isBDV
                    % parse sub-sampling: user enters e.g. '1 1 1; 2 2 2; 4 4 4'
                    ssRaw = str2num(answer{8}); %#ok<ST2NM>
                    if isempty(ssRaw); ssRaw = [1;1;1]; end
                    if size(ssRaw,1) == 1; ssRaw = ssRaw(:); end            % row → column
                    if size(ssRaw,2) == 3 && size(ssRaw,1) ~= 3; ssRaw = ssRaw'; end  % levels-as-rows → [3xL]
                    options.SubSampling      = ssRaw;
                    options.ResamplingMethod = answer{9};
                    isXmlFormat              = true;   % BDV always produces XML
                else
                    options.DimOrder = formatChoice(1:5);   % 'yxzct' or 'yxczt'
                    isXmlFormat      = answer{7};
                end
            else
                % silent / all options pre-set by caller
                isBDV = isBDVByFormat || (callerSetDimOrder && strcmpi(options.DimOrder, 'bdv'));
                if isBDV; isXmlFormat = true; end
            end

            % --- apply defaults for any still-unset fields ---
            % Note: options.ChunkSize == [] means "no chunking" (user explicitly
            % unchecked the chunk box).  Only set the default when the field is
            % absent, i.e. the caller never addressed chunking at all.
            if ~isfield(options,'ChunkSize')
                options.ChunkSize = defaultChunk;
            end
            if ~isfield(options,'Deflate');          options.Deflate          = 0;        end
            if ~isfield(options,'SubSampling');      options.SubSampling      = [1;1;1];  end
            if ~isfield(options,'DimOrder');         options.DimOrder         = 'yxzct';  end
            if ~isfield(options,'ResamplingMethod'); options.ResamplingMethod = 'bicubic'; end

            % ============================================================
            % BDV SAVE PATH
            % ============================================================
            if isBDV
                BDVoptions = obj.buildCommonHDFOptions(options, metadata, baseName, nH, nW, nD, nC, nT);
                BDVoptions.SubSampling      = options.SubSampling;
                BDVoptions.ResamplingMethod = options.ResamplingMethod;
                % BDV always needs a chunk size; fall back to 64³ if user unchecked chunking
                if ~isempty(options.ChunkSize)
                    BDVoptions.ChunkSize = options.ChunkSize;
                else
                    BDVoptions.ChunkSize = [64; 64; 64];
                end

                % BDV requires X/Y swap: permute [H,W,D,C,T] → [W,H,C,D,T]
                dataBDV = permute(data, [2 1 4 3 5]);
                io.HDF5.saveBigDataViewerFormat(h5Filename, dataBDV, BDVoptions);

                % BDV always writes an XML header
                BDVoptions.Format = 'bdv.hdf5';
                BDVoptions.pixSize.units = sprintf('\xB5m');
                io.HDF5.saveXMLheader(h5Filename, BDVoptions);

                [~, bn, ~] = fileparts(h5Filename);
                xmlOut = fullfile(pathStr, [bn '.xml']);
                fnOut  = xmlOut;
                fprintf('HDF5Saver: saved BDV → %s + %s\n', h5Filename, xmlOut);
                return;
            end

            % ============================================================
            % STANDARD HDF5 SAVE PATH (matlab.hdf5 with optional XML)
            % ============================================================

            % Permute data when a non-default order was requested.
            switch options.DimOrder
                case 'yxczt'
                    dataOut = permute(data, [1 2 4 3 5]);  % [H,W,D,C,T]→[H,W,C,D,T]
                otherwise
                    dataOut = data;   % MIB3 native [H,W,D,C,T], no permutation
            end

            HDFoptions = obj.buildCommonHDFOptions(options, metadata, baseName, nH, nW, nD, nC, nT);
            HDFoptions.Format      = 'matlab.hdf5';
            HDFoptions.order       = options.DimOrder;
            HDFoptions.SubSampling = options.SubSampling;
            if ~isempty(options.ChunkSize)
                HDFoptions.ChunkSize = options.ChunkSize(:)';  % row vector [y x z]
            else
                HDFoptions.ChunkSize = [];   % no chunking
            end

            io.HDF5.image2hdf5(h5Filename, dataOut, HDFoptions);

            if isXmlFormat
                io.HDF5.saveXMLheader(h5Filename, HDFoptions);
                [~, bn, ~] = fileparts(h5Filename);
                xmlOut = fullfile(pathStr, [bn '.xml']);
                fnOut  = xmlOut;
                fprintf('HDF5Saver: saved → %s + %s\n', h5Filename, xmlOut);
            else
                fnOut = h5Filename;
                fprintf('HDF5Saver: saved → %s\n', h5Filename);
            end
        end

    end

    methods (Access = private)

        function HDFoptions = buildCommonHDFOptions(~, options, metadata, baseName, nH, nW, nD, nC, nT)
            % BUILDCOMMONHDFOPTIONS - Assemble the HDFoptions struct shared by both save paths.
            %
            % Syntax:
            %   function HDFoptions = buildCommonHDFOptions(~, options, metadata, baseName, nH, nW, nD, nC, nT)
            %
            HDFoptions.Deflate      = options.Deflate;
            HDFoptions.showWaitbar  = options.showWaitbar;
            HDFoptions.overwrite    = options.overwrite;
            HDFoptions.layerType    = options.layerType;
            if isfield(options, 'ParentFigure')
                HDFoptions.ParentFigure = options.ParentFigure;
            else
                HDFoptions.ParentFigure = [];
            end
            HDFoptions.height  = nH;
            HDFoptions.width   = nW;
            HDFoptions.colors  = nC;
            HDFoptions.depth   = nD;
            HDFoptions.time    = nT;
            HDFoptions.DatasetName = baseName;

            if isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                HDFoptions.pixSize = metadata.pixSize;
            else
                HDFoptions.pixSize = struct('x',1,'y',1,'z',1,'units','um','t',1,'tunits','s');
            end
            if isfield(metadata, 'boundingBox') && ~isempty(metadata.boundingBox)
                HDFoptions.BoundingBox = metadata.boundingBox;
            else
                HDFoptions.BoundingBox = [0 nW*HDFoptions.pixSize.x ...
                                          0 nH*HDFoptions.pixSize.y ...
                                          0 nD*HDFoptions.pixSize.z];
            end
            if isfield(metadata, 'lutColors') && ~isempty(metadata.lutColors)
                HDFoptions.lutColors = metadata.lutColors;
            else
                HDFoptions.lutColors = ones(1,3);
            end

            % For model/label layers, store material names and colors so that
            % saveXMLheader can write the Materials section into the XML file.
            if isfield(metadata, 'materialNames') && ~isempty(metadata.materialNames)
                HDFoptions.ModelMaterialNames = metadata.materialNames;
                % Prefer materialColors for per-material RGB; fall back to lutColors
                if isfield(metadata, 'materialColors') && ~isempty(metadata.materialColors)
                    HDFoptions.lutColors = metadata.materialColors;
                end
            end
            HDFoptions.ImageDescription = '';
            if isfield(metadata, 'imageDescription')
                HDFoptions.ImageDescription = metadata.imageDescription;
            end
        end

    end
end
