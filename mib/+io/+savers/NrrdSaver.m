classdef NrrdSaver < io.savers.BaseSaver
% NRRDSAVER - Saver for NRRD (Nearly Raw Raster Data) format output.
%
% Handles two format variants:
% 'NRRD Data Format (``*.nrrd``)'      - standard NRRD volume
% 'NRRD for 3D Slicer (``*.nrrd``)'   - NRRD with 3D Slicer-compatible
% metadata (RAS space, voxel-to-world transform, etc.)
%
% Both image and label/mask volumes can be saved.  The layer type is
% inferred from options.layerType (default 'image').  For multi-channel
% or time-series data only the first channel (C=1) and first time point
% (T=1) are passed to the underlying helper; a warning is issued if C>1.
%
% The saver delegates the actual I/O to the legacy helper bitmap2nrrd(),
% which is ported from MIB2.
%
% DATA DIMENSIONS
% Input  data : [H, W, D, C, T]  (MIB3 native order)
% bitmap2nrrd() expects [H, W, D] - obtained by squeezing the first
% channel and time point.
%
% BOUNDING BOX
% The bounding box is read from metadata.boundingBox as
% [xmin xmax ymin ymax zmin zmax].
% If not present, zeros(1,6) is used as a default.
%
% FILENAME GENERATOR
% options.FilenameGenerator controls how the output file is named:
% 'Use sequential filename' (default) - numbered naming
% 'Use original filename'             - derived from metadata.sliceName
%
% TODO: port bitmap2nrrd from
% MIB2_RENAMED_FOR_MIB3/ImportExportTools/nrrd/bitmap2nrrd.m
% to mib/+io/+NRRD/bitmap2nrrd.m
%
% USAGE EXAMPLES
%
% .. code-block:: matlab
%
%     %% 1. Save image volume as standard NRRD
%     saver = io.SaverFactory.create('NRRD Data Format (``*.nrrd``)');
%
%     opts.Format            = 'NRRD Data Format (``*.nrrd``)';
%     opts.showWaitbar       = false;
%     opts.silent            = true;
%     opts.overwrite         = true;
%     opts.layerType         = 'image';
%     opts.FilenameGenerator = 'Use sequential filename';
%
%     meta.filename    = 'source_stack.tif';
%     meta.colorType   = 'grayscale';
%     meta.lutColors   = [1 1 1];
%     meta.dataClass   = 'uint16';
%     meta.maxInt      = 65535;
%     meta.pixSize     = struct('x',0.065,'y',0.065,'z',0.2, ...
%                               'units','um','t',1,'tunits','s');
%     meta.boundingBox = [0 33.3 0 33.3 0 10];
%
%     data = uint16(rand(512,512,50,1,1)*65535);  % [H W D C T]
%     fnOut = saver.save(data, meta, '/output/myStack.nrrd', opts);
%     fprintf('Saved: %s\n', fnOut);
%
%
%
% .. code-block:: matlab
%
%     %% 2. Save labels as NRRD for 3D Slicer
%     saver = io.SaverFactory.create('NRRD for 3D Slicer (``*.nrrd``)');
%
%     opts.Format      = 'NRRD for 3D Slicer (``*.nrrd``)';
%     opts.showWaitbar = false;
%     opts.silent      = true;
%     opts.overwrite   = true;
%     opts.layerType   = 'labels';
%
%     meta.filename    = 'source_stack.tif';
%     meta.pixSize     = struct('x',0.065,'y',0.065,'z',0.2, ...
%                               'units','um','t',1,'tunits','s');
%     meta.boundingBox = [0 33.3 0 33.3 0 10];
%
%     labels = uint8(rand(512,512,50,1,1)*3);  % [H W D C T]
%     fnOut = saver.save(labels, meta, '/output/Labels_Slicer.nrrd', opts);
%
%
% SEE ALSO
% io.SaverFactory, io.savers.BaseSaver, io.savers.TiffSaver,
% core.MibImage.save, core.MibDataset.save, models.MibModel.save

    methods

        function obj = NrrdSaver(options)
            % NRRDSAVER - Constructor for NrrdSaver class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      saver = io.savers.NrrdSaver(options)
            %
            % Input Arguments:
            %   - **options** - *(optional)* struct, saver-level options (usually empty;
            %     per-save options are passed to ``save()`` instead)
            %
            % Output Arguments:
            %   - **obj** - instance of the NrrdSaver class
            %
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            % GETSUPPORTEDFORMATS - Return format strings handled by NrrdSaver.
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
            %   - **formats** - cell array of format strings for NRRD output
            %
            formats = { ...
                'NRRD Data Format (*.nrrd)'; ...
                'NRRD for 3D Slicer (*.nrrd)' };
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % SAVE - Write data as a NRRD file.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.save(data, metadata, filename, options)
            %
            % NRRD supports single-channel data (C=1); a warning is issued and
            % only the first channel is written if C>1. Similarly, only the first
            % time point (T=1) is used for time-series data.
            %
            % Input Arguments:
            %   - **data** - [H, W, D, C, T] numeric array
            %   - **metadata** - struct with fields:
            %
            %     - ``colorType`` - ``'grayscale'`` | ``'multichannel'`` | ``'indexed'``
            %     - ``dataClass`` - ``'uint8'`` | ``'uint16'`` | ...
            %     - ``maxInt`` - maximum intensity value
            %     - ``pixSize`` - struct {``.x``, ``.y``, ``.z``, ``.units``, ``.t``, ``.tunits``}
            %     - ``boundingBox`` - [xmin xmax ymin ymax zmin zmax]; default: ``zeros(1,6)``
            %     - ``sliceName`` - *(optional)* per-slice source filenames
            %
            %   - **filename** - full output path, e.g. ``'/out/stack.nrrd'``
            %   - **options** - struct with fields:
            %
            %     - ``Format`` - format string (``'NRRD Data Format (*.nrrd)'`` or ``'NRRD for 3D Slicer (*.nrrd)'``)
            %     - ``layerType`` - ``'image'`` | ``'mask'`` | ``'labels'``; default: ``'image'``
            %     - ``showWaitbar`` - logical; default: ``true``
            %     - ``silent`` - logical, suppress dialogs; default: ``false``
            %     - ``overwrite`` - logical; default: ``true``
            %     - ``FilenameGenerator`` - ``'Use original filename'`` | ``'Use sequential filename'``
            %
            % Output Arguments:
            %   - **fnOut** - [char] path of saved ``.nrrd`` file, ``[]`` on failure
            %
            % **Example** - see class-level documentation above.
            %

            fnOut = [];

            % --- defaults ---
            if ~isfield(options, 'showWaitbar');       options.showWaitbar    = true;    end
            if ~isfield(options, 'silent');            options.silent         = false;   end
            if ~isfield(options, 'overwrite');         options.overwrite      = true;    end
            if ~isfield(options, 'layerType');         options.layerType      = 'image'; end
            if ~isfield(options, 'FilenameGenerator'); options.FilenameGenerator = 'Use sequential filename'; end
            if ~isfield(options, 'Format');            options.Format         = 'NRRD Data Format (*.nrrd)'; end

            % --- decompose filename ---
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isempty(ext); ext = '.nrrd'; end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr, 'dir') ~= 7; mkdir(pathStr); end

            % --- apply FilenameGenerator (volume file = single output) ---
            volumeFilename = fullfile(pathStr, [baseName ext]);

            % --- warn on multichannel ---
            nC = size(data, 4);
            if nC > 1
                warning('NrrdSaver:multiChannel', ...
                    'NRRD saver writes only the first colour channel (C=1 of %d).', nC);
            end

            % Squeeze to [H, W, D]
            img_hwd = squeeze(data(:, :, :, 1, 1));

            % --- bounding box ---
            if isfield(metadata, 'boundingBox') && ~isempty(metadata.boundingBox)
                boundingBox = metadata.boundingBox;
            else
                boundingBox = zeros(1, 6);
            end

            % --- build savingOptions for bitmap2nrrd ---
            savingOptions.showWaitbar   = options.showWaitbar;
            savingOptions.overwrite     = options.overwrite;
            savingOptions.layerType     = options.layerType;
            savingOptions.Format        = options.Format;
            savingOptions.ParentFigure  = obj.ParentFigure;

            if isfield(metadata, 'pixSize') && ~isempty(metadata.pixSize)
                savingOptions.pixSize = metadata.pixSize;
            else
                savingOptions.pixSize = struct('x',1,'y',1,'z',1, ...
                    'units','um','t',1,'tunits','s');
            end

            % --- call legacy bitmap2nrrd ---
            % TODO: port bitmap2nrrd from
            %   MIB2_RENAMED_FOR_MIB3/ImportExportTools/nrrd/bitmap2nrrd.m
            %   to mib/+io/+NRRD/bitmap2nrrd.m
            try
                io.NRRD.bitmap2nrrd(volumeFilename, img_hwd, boundingBox, savingOptions);
            catch ME
                error('NrrdSaver:missingHelper', ...
                    ['bitmap2nrrd() is not yet available.\n' ...
                     'Please port it from:\n' ...
                     '  MIB2_RENAMED_FOR_MIB3/ImportExportTools/nrrd/bitmap2nrrd.m\n' ...
                     'to:\n' ...
                     '  mib/+io/+NRRD/bitmap2nrrd.m\n\n' ...
                     'Original error: %s'], ME.message);
            end

            fnOut = volumeFilename;
            fprintf('NrrdSaver: saved → %s\n', volumeFilename);
        end

    end
end
