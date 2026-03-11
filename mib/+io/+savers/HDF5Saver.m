classdef HDF5Saver < io.savers.BaseSaver
    % classdef HDF5Saver < io.savers.BaseSaver
    % Saver for Hierarchical Data Format (HDF5) output.
    %
    % Handles two format variants:
    %   'Hierarchical Data Format (*.h5)'                — standard HDF5 file
    %   'Hierarchical Data Format with XML header (*.xml)' — HDF5 file with an
    %       accompanying XML header (Ilastik/BDV-compatible)
    %
    % Both image data and mask/labels layers can be saved.  The layer type is
    % controlled by options.layerType ('image' | 'mask' | 'labels').
    %
    % The saver delegates the actual I/O to the legacy helper function
    % image2hdf5(), which is ported from MIB2.  For the XML variant the
    % additional helper saveXMLheader() is called afterwards to write the
    % BigDataViewer-compatible XML descriptor.
    %
    % DATA DIMENSIONS
    %   Input  data  : [H, W, D, C, T]  (MIB3 native order)
    %   image2hdf5() expects the same 5-D array; internally it handles
    %   chunking, deflate compression, and sub-sampling.
    %
    % NOTES
    %   * Sub-sampling (HDFoptions.SubSampling) is a [3 x L] matrix where
    %     each column is [xFactor; yFactor; zFactor] for one resolution level.
    %     Default (silent mode): [1;1;1] — no downsampling.
    %   * ChunkSize defaults to min([64, H, W, D]) for each spatial dimension.
    %   * Deflate=0 disables zlib compression; use 1–9 for increasing
    %     compression ratio vs. speed trade-off.
    %   * When options.silent is true the saver uses all defaults without
    %     showing any dialogs.
    %
    % TODO: port image2hdf5() from
    %   MIB2_RENAMED_FOR_MIB3/ImportExportTools/HDF5/image2hdf5.m
    %   to mib/+io/+HDF5/image2hdf5.m
    %
    % TODO: port saveXMLheader() from
    %   MIB2_RENAMED_FOR_MIB3/ImportExportTools/HDF5/saveXMLheader.m
    %   to mib/+io/+HDF5/saveXMLheader.m
    %
    % USAGE EXAMPLES
    %   @code
    %   %% 1. Direct saver use — save 5-D image to HDF5
    %   saver = io.SaverFactory.create('Hierarchical Data Format (*.h5)');
    %
    %   opts.Format         = 'Hierarchical Data Format (*.h5)';
    %   opts.showWaitbar    = false;
    %   opts.silent         = true;
    %   opts.overwrite      = true;
    %   opts.layerType      = 'image';
    %
    %   meta.filename       = 'source_stack.tif';
    %   meta.colorType      = 'grayscale';
    %   meta.lutColors      = [1 1 1];
    %   meta.dataClass      = 'uint16';
    %   meta.maxInt         = 65535;
    %   meta.pixSize        = struct('x',0.065,'y',0.065,'z',0.2, ...
    %                                'units','um','t',1,'tunits','s');
    %   meta.boundingBox    = [0 33.3 0 33.3 0 10];
    %   meta.imageDescription = 'My EM dataset';
    %
    %   data = uint16(rand(512,512,50,1,1) * 65535);  % [H W D C T]
    %   fnOut = saver.save(data, meta, '/output/myStack.h5', opts);
    %   fprintf('Saved: %s\n', fnOut);
    %   @endcode
    %
    %   @code
    %   %% 2. Save with XML header for BigDataViewer / Ilastik
    %   saver = io.SaverFactory.create( ...
    %       'Hierarchical Data Format with XML header (*.xml)');
    %
    %   opts.Format         = 'Hierarchical Data Format with XML header (*.xml)';
    %   opts.showWaitbar    = true;
    %   opts.silent         = true;
    %   opts.overwrite      = true;
    %   opts.layerType      = 'image';
    %
    %   meta.filename       = 'source_stack.tif';
    %   meta.colorType      = 'grayscale';
    %   meta.pixSize        = struct('x',0.065,'y',0.065,'z',0.2, ...
    %                                'units','um','t',1,'tunits','s');
    %   meta.boundingBox    = [0 33.3 0 33.3 0 10];
    %
    %   data = uint16(rand(512,512,50,1,1) * 65535);
    %   fnOut = saver.save(data, meta, '/output/myStack.xml', opts);
    %   @endcode
    %
    %   @code
    %   %% 3. Via MibModel batch — save labels as HDF5
    %   BatchOpt.LayerType       = {'labels'};
    %   BatchOpt.Format          = {'Hierarchical Data Format (*.h5)'};
    %   BatchOpt.OutputDirectoryPolicy = {'Full path'};
    %   BatchOpt.DestinationDirectory  = '/output/dir';
    %   BatchOpt.FilenamePolicy  = {'Use existing name'};
    %   BatchOpt.showWaitbar     = false;
    %   BatchOpt.mibBatchTooltip.LayerType = '';
    %   model.save('labels', [], BatchOpt);
    %   @endcode
    %
    % SEE ALSO
    %   io.SaverFactory, io.savers.BaseSaver, io.savers.TiffSaver,
    %   core.MibImage.save, core.MibDataset.save, models.MibModel.save

    methods

        function obj = HDF5Saver(options)
            % function obj = HDF5Saver(options)
            % Constructor — accepts an optional options struct.
            %
            % Parameters:
            %   options — (struct, optional) saver-level options (usually empty;
            %             per-save options are passed to save() instead)
            if nargin < 1; options = struct(); end
            obj.Options = options;
        end

        function formats = getSupportedFormats(~)
            % function formats = getSupportedFormats(~)
            % Return format strings handled by HDF5Saver.
            formats = { ...
                'Hierarchical Data Format (*.h5)'; ...
                'Hierarchical Data Format with XML header (*.xml)' };
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % function fnOut = save(obj, data, metadata, filename, options)
            % Write data as an HDF5 file (with optional XML header).
            %
            % Parameters:
            %   data     — [H, W, D, C, T] numeric array
            %   metadata — struct; used fields:
            %     .colorType        — 'grayscale' | 'multichannel' | 'indexed'
            %     .lutColors        — [C x 3] per-channel LUT colours (0..1)
            %     .dataClass        — 'uint8' | 'uint16' | ...
            %     .maxInt           — maximum intensity value
            %     .pixSize          — struct {.x .y .z .units .t .tunits}
            %     .boundingBox      — [xmin xmax ymin ymax zmin zmax]
            %     .imageDescription — (char) dataset description string
            %   filename — full output path, e.g. '/out/stack.h5' or
            %              '/out/stack.xml' for the XML-header variant
            %   options  — struct; used fields:
            %     .Format           — format string (selects XML header mode)
            %     .layerType        — 'image' | 'mask' | 'labels'
            %                         (default 'image')
            %     .showWaitbar      — logical
            %     .silent           — logical, suppress dialogs and use defaults
            %     .overwrite        — logical
            %     .SubSampling      — [3 x L] sub-sampling factors per level;
            %                         default [1;1;1] when silent
            %     .ChunkSize        — [1 x 3] HDF5 chunk size in voxels;
            %                         default min(64, spatial dimensions)
            %     .Deflate          — integer 0-9 (zlib level); default 0
            %
            % Return values:
            %   fnOut — (char) path of saved .h5 file, [] on failure
            %
            % Example — see class-level documentation above.

            fnOut = [];

            % --- defaults ---
            if ~isfield(options, 'showWaitbar'); options.showWaitbar = true;    end
            if ~isfield(options, 'silent');      options.silent      = false;   end
            if ~isfield(options, 'overwrite');   options.overwrite   = true;    end
            if ~isfield(options, 'layerType');   options.layerType   = 'image'; end
            if ~isfield(options, 'Format');      options.Format      = 'Hierarchical Data Format (*.h5)'; end

            isXmlFormat = contains(options.Format, 'xml', 'IgnoreCase', true);

            % --- decompose filename ---
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isXmlFormat
                if isempty(ext); ext = '.xml'; end
                h5Filename = fullfile(pathStr, [baseName '.h5']);
                xmlFilename = fullfile(pathStr, [baseName ext]);
            else
                if isempty(ext); ext = '.h5'; end
                h5Filename  = fullfile(pathStr, [baseName ext]);
                xmlFilename = '';
            end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr, 'dir') ~= 7; mkdir(pathStr); end

            [nH, nW, nD, ~, ~] = size(data);

            % --- build HDFoptions metadata struct ---
            HDFoptions.Format = 'matlab.hdf5';

            % Sub-sampling: default [1;1;1] (no downsampling)
            if isfield(options, 'SubSampling') && ~isempty(options.SubSampling)
                HDFoptions.SubSampling = options.SubSampling;
            else
                HDFoptions.SubSampling = [1; 1; 1];
            end

            % Chunk size: default min(64, spatial dim)
            if isfield(options, 'ChunkSize') && ~isempty(options.ChunkSize)
                HDFoptions.ChunkSize = options.ChunkSize;
            else
                HDFoptions.ChunkSize = [min(64, nH), min(64, nW), min(64, nD)];
            end

            % Deflate compression level
            if isfield(options, 'Deflate') && ~isempty(options.Deflate)
                HDFoptions.Deflate = options.Deflate;
            else
                HDFoptions.Deflate = 0;
            end

            HDFoptions.xmlCreate    = 1;
            HDFoptions.showWaitbar  = options.showWaitbar;
            HDFoptions.overwrite    = options.overwrite;
            HDFoptions.layerType    = options.layerType;

            % Pixel size
            if isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                HDFoptions.pixSize = metadata.pixSize;
            else
                HDFoptions.pixSize = struct('x', 1, 'y', 1, 'z', 1, ...
                    'units', 'um', 't', 1, 'tunits', 's');
            end

            % Bounding box
            if isfield(metadata, 'boundingBox') && ~isempty(metadata.boundingBox)
                HDFoptions.BoundingBox = metadata.boundingBox;
            else
                HDFoptions.BoundingBox = [0 nW*HDFoptions.pixSize.x ...
                                          0 nH*HDFoptions.pixSize.y ...
                                          0 nD*HDFoptions.pixSize.z];
            end

            % Colour LUT
            if isfield(metadata, 'lutColors') && ~isempty(metadata.lutColors)
                HDFoptions.lutColors = metadata.lutColors;
            else
                HDFoptions.lutColors = ones(1, 3);
            end

            % Image description
            if isfield(metadata, 'imageDescription')
                HDFoptions.ImageDescription = metadata.imageDescription;
            else
                HDFoptions.ImageDescription = '';
            end

            % --- call legacy image2hdf5 ---
            % TODO: port image2hdf5() from
            %   MIB2_RENAMED_FOR_MIB3/ImportExportTools/HDF5/image2hdf5.m
            %   to mib/+io/+HDF5/image2hdf5.m
            try
                io.HDF5.image2hdf5(h5Filename, data, HDFoptions);
            catch ME
                error('HDF5Saver:missingHelper', ...
                    ['image2hdf5() is not yet available.\n' ...
                     'Please port it from:\n' ...
                     '  MIB2_RENAMED_FOR_MIB3/ImportExportTools/HDF5/image2hdf5.m\n' ...
                     'to:\n' ...
                     '  mib/+io/+HDF5/image2hdf5.m\n\n' ...
                     'Original error: %s'], ME.message);
            end

            % --- write XML header if requested ---
            if isXmlFormat && ~isempty(xmlFilename)
                % TODO: port saveXMLheader() from
                %   MIB2_RENAMED_FOR_MIB3/ImportExportTools/HDF5/saveXMLheader.m
                %   to mib/+io/+HDF5/saveXMLheader.m
                try
                    io.HDF5.saveXMLheader(xmlFilename, h5Filename, HDFoptions);
                catch ME
                    error('HDF5Saver:missingXmlHelper', ...
                        ['saveXMLheader() is not yet available.\n' ...
                         'Please port it from:\n' ...
                         '  MIB2_RENAMED_FOR_MIB3/ImportExportTools/HDF5/saveXMLheader.m\n' ...
                         'to:\n' ...
                         '  mib/+io/+HDF5/saveXMLheader.m\n\n' ...
                         'Original error: %s'], ME.message);
                end
                fnOut = xmlFilename;
                fprintf('HDF5Saver: saved → %s + %s\n', h5Filename, xmlFilename);
            else
                fnOut = h5Filename;
                fprintf('HDF5Saver: saved → %s\n', h5Filename);
            end
        end

    end
end
