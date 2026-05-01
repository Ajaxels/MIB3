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

    end
end
