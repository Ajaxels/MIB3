classdef MrcSaver < io.savers.BaseSaver
    % classdef MrcSaver < io.savers.BaseSaver
    % Saver for MRC format output (used by IMOD and related EM tools).
    %
    % Handles two format variants (both write the same MRC file; the second
    % is an alias used in the SaverFactory registry for volume export):
    %   'MRC format for IMOD (*.mrc)'  — standard MRC file for IMOD
    %   'MRC Volume for IMOD (*.mrc)'      — alias, same output format
    %
    % Both image and label/mask volumes can be saved.  The layer type is
    % controlled by options.layerType (default 'image').
    %
    % IMPORTANT: MRC supports only single-channel data (C=1).  If the input
    % data has more than one colour channel a warning is issued and only the
    % first channel is written.
    %
    % The saver delegates the actual I/O to the legacy helper mibImage2mrc(),
    % which is ported from MIB2.
    %
    % DATA DIMENSIONS
    %   Input  data    : [H, W, D, C, T]  (MIB3 native order)
    %   mibImage2mrc() expects [H, W, D] — obtained by squeezing C=1, T=1.
    %
    % FILENAME GENERATOR
    %   options.FilenameGenerator controls how the output file is named:
    %     'Use sequential filename' (default) — numbered naming
    %     'Use original filename'             — derived from metadata.sliceName
    %
    % TODO: port mibImage2mrc from
    %   MIB2_RENAMED_FOR_MIB3/ImportExportTools/mibImage2mrc.m
    %   to mib/+io/mibImage2mrc.m
    %
    % USAGE EXAMPLES
    %   @code
    %   %% 1. Save EM tomogram as MRC for IMOD
    %   saver = io.SaverFactory.create('MRC format for IMOD (*.mrc)');
    %
    %   opts.Format            = 'MRC format for IMOD (*.mrc)';
    %   opts.showWaitbar       = false;
    %   opts.silent            = true;
    %   opts.overwrite         = true;
    %   opts.layerType         = 'image';
    %   opts.FilenameGenerator = 'Use sequential filename';
    %
    %   meta.filename  = 'source_tomo.tif';
    %   meta.colorType = 'grayscale';
    %   meta.dataClass = 'uint8';
    %   meta.maxInt    = 255;
    %   meta.pixSize   = struct('x',0.35,'y',0.35,'z',1.4, ...
    %                           'units','nm','t',1,'tunits','s');
    %
    %   data = uint8(rand(512,512,200,1,1)*255);  % [H W D C T]
    %   fnOut = saver.save(data, meta, '/output/myTomo.mrc', opts);
    %   fprintf('Saved: %s\n', fnOut);
    %   @endcode
    %
    %   @code
    %   %% 2. Save segmentation labels volume for IMOD
    %   saver = io.SaverFactory.create('MRC Volume for IMOD (*.mrc)');
    %
    %   opts.Format      = 'MRC Volume for IMOD (*.mrc)';
    %   opts.showWaitbar = false;
    %   opts.silent      = true;
    %   opts.overwrite   = true;
    %   opts.layerType   = 'labels';
    %
    %   meta.filename  = 'source_tomo.tif';
    %   meta.pixSize   = struct('x',0.35,'y',0.35,'z',1.4, ...
    %                           'units','nm','t',1,'tunits','s');
    %
    %   labels = uint8(rand(512,512,200,1,1)*3);  % [H W D C T]
    %   fnOut = saver.save(labels, meta, '/output/Labels_myTomo.mrc', opts);
    %   @endcode
    %
    % SEE ALSO
    %   io.SaverFactory, io.savers.BaseSaver, io.savers.NrrdSaver,
    %   core.MibImage.save, core.MibDataset.save, models.MibModel.save

    methods

        function obj = MrcSaver(options)
            % function obj = MrcSaver(options)
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
            % Return format strings handled by MrcSaver.
            formats = { ...
                'MRC format for IMOD (*.mrc)'; ...
                'MRC Volume for IMOD (*.mrc)' };
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % function fnOut = save(obj, data, metadata, filename, options)
            % Write data as an MRC file for IMOD.
            %
            % Parameters:
            %   data     — [H, W, D, C, T] numeric array.
            %              MRC supports only C=1; a warning is issued and
            %              only the first channel is written if C>1.
            %   metadata — struct; used fields:
            %     .colorType  — 'grayscale' | 'multichannel' | 'indexed'
            %     .dataClass  — 'uint8' | 'uint16' | ...
            %     .maxInt     — maximum intensity value
            %     .pixSize    — struct {.x .y .z .units .t .tunits};
            %                   used for MRC cell/voxel size header
            %   filename — full output path, e.g. '/out/tomo.mrc'
            %   options  — struct; used fields:
            %     .Format           — format string
            %     .layerType        — 'image' | 'mask' | 'labels'
            %                         (default 'image')
            %     .showWaitbar      — logical
            %     .silent           — logical, suppress dialogs
            %     .overwrite        — logical
            %     .FilenameGenerator — 'Use original filename' |
            %                          'Use sequential filename'
            %
            % Return values:
            %   fnOut — (char) path of saved .mrc file, [] on failure
            %
            % Example — see class-level documentation above.

            fnOut = [];

            % --- defaults ---
            if ~isfield(options, 'showWaitbar');       options.showWaitbar    = true;    end
            if ~isfield(options, 'silent');            options.silent         = false;   end
            if ~isfield(options, 'overwrite');         options.overwrite      = true;    end
            if ~isfield(options, 'layerType');         options.layerType      = 'image'; end
            if ~isfield(options, 'FilenameGenerator'); options.FilenameGenerator = 'Use sequential filename'; end
            if ~isfield(options, 'Format');            options.Format         = 'MRC format for IMOD (*.mrc)'; end

            % --- decompose filename ---
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isempty(ext); ext = '.mrc'; end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr, 'dir') ~= 7; mkdir(pathStr); end
            volumeFilename = fullfile(pathStr, [baseName ext]);

            % --- single-channel restriction ---
            nC = size(data, 4);
            if nC > 1
                warning('MrcSaver:multiChannel', ...
                    ['MRC format supports only single-channel data; ' ...
                     'got C=%d. Only the first channel will be saved.'], nC);
            end

            % Squeeze to [H, W, D]
            img_hwd = squeeze(data(:, :, :, 1, 1));

            % --- build mrcOptions ---
            mrcOptions.volumeFilename = volumeFilename;
            mrcOptions.showWaitbar    = options.showWaitbar;
            mrcOptions.overwrite      = options.overwrite;
            mrcOptions.layerType      = options.layerType;
            mrcOptions.ParentFigure   = obj.ParentFigure;

            if isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                mrcOptions.pixSize = metadata.pixSize;
            else
                mrcOptions.pixSize = struct('x',1,'y',1,'z',1, ...
                    'units','nm','t',1,'tunits','s');
            end

            % --- call legacy mibImage2mrc ---
            % TODO: port mibImage2mrc from
            %   MIB2_RENAMED_FOR_MIB3/ImportExportTools/mibImage2mrc.m
            %   to mib/+io/mibImage2mrc.m
            try
                io.mibImage2mrc(img_hwd, mrcOptions);
            catch ME
                error('MrcSaver:missingHelper', ...
                    ['mibImage2mrc() is not yet available.\n' ...
                     'Please port it from:\n' ...
                     '  MIB2_RENAMED_FOR_MIB3/ImportExportTools/mibImage2mrc.m\n' ...
                     'to:\n' ...
                     '  mib/+io/mibImage2mrc.m\n\n' ...
                     'Original error: %s'], ME.message);
            end

            fnOut = volumeFilename;
            fprintf('MrcSaver: saved → %s\n', volumeFilename);
        end

    end
end
