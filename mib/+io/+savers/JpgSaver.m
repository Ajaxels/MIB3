classdef JpgSaver < io.savers.BaseSaver
% JPGSAVER - Saver for JPEG output — one file per Z-slice (always a 2-D sequence).
%
% JPEG is a lossy format suitable for display purposes; it is NOT
% recommended for quantitative analysis.  uint16 multichannel data
% cannot be saved as JPEG (MATLAB limitation); use uint8 RGB only.
%
% Handled format string:
% 'Joint Photographic Experts Group (``*.jpg``)'
%
% DATA DIMENSIONS
% Input  data : [H, W, D, C, T]
% imwrite call: [H, W, C] per 2-D slice (C ≤ 3, class == uint8)
%
% NOTES
% * options.Quality  (0–100, default 90): JPEG quality factor.
% * options.Compression ('lossy'|'lossless', default 'lossy').
% * JPEG does not support indexed colourmaps; 'indexed' colour images
% will be saved using the raw index values as greyscale.
%
% USAGE EXAMPLES
%
% .. code-block:: matlab
%
%     %% 1. Direct saver use
%     saver = io.SaverFactory.create('Joint Photographic Experts Group (``*.jpg``)');
%
%     opts.Format      = 'Joint Photographic Experts Group (``*.jpg``)';
%     opts.Quality     = 90;
%     opts.Compression = 'lossy';
%     opts.showWaitbar = false;
%     opts.silent      = true;
%     opts.overwrite   = true;
%     opts.FilenameGenerator = 'Use sequential filename';
%
%     meta.filename         = 'source.tif';
%     meta.colorType        = 'multichannel';
%     meta.lutColors        = eye(3);
%     meta.dataClass        = 'uint8';
%     meta.maxInt           = 255;
%     meta.sliceName        = {};
%     meta.imageDescription = '';
%
%     data = uint8(rand(256,256,10,3,1)*255);   % [H W D C T], RGB
%     fnOut = saver.save(data, meta, '/output/slice.jpg', opts);
%     % Generates /output/slice_01.jpg … /output/slice_10.jpg
%
% .. code-block:: matlab
%
%     %% 2. Via MibModel with quality control
%     BatchOpt.LayerType       = {'image'};
%     BatchOpt.Format          = {'Joint Photographic Experts Group (``*.jpg``)'};
%     BatchOpt.Quality         = '90';
%     BatchOpt.Compression     = 'lossy';
%     BatchOpt.OutputDirectoryPolicy = {'Full path'};
%     BatchOpt.DestinationDirectory  = '/output';
%     BatchOpt.FilenamePolicy  = {'Use existing name'};
%     BatchOpt.showWaitbar     = false;
%     BatchOpt.mibBatchTooltip.LayerType = '';
%     model.save('image', [], BatchOpt);
%
% SEE ALSO
% io.SaverFactory, io.savers.BaseSaver, io.savers.PngSaver

    methods

        function obj = JpgSaver(options)
            % JPGSAVER - Constructor for JpgSaver class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      saver = io.savers.JpgSaver(options)
            %
            % Input Arguments:
            %   - **options** — *(optional)* struct, saver-level options (usually empty;
            %     per-save options are passed to ``save()`` instead)
            %
            % Output Arguments:
            %   - **obj** — instance of the JpgSaver class
            %
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            % GETSUPPORTEDFORMATS - Return format strings handled by JpgSaver.
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
            %   - **formats** — cell array of format strings for JPEG output
            %
            formats = {'Joint Photographic Experts Group (*.jpg)'};
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % SAVE - Write JPEG 2-D sequence (one file per Z-slice × time point).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.save(data, metadata, filename, options)
            %
            % Input Arguments:
            %   - **data** — [H, W, D, C, T] uint8 (or uint16 greyscale)
            %   - **metadata** — struct with fields:
            %
            %     - ``colorType`` — data type (multichannel RGB must be uint8)
            %     - ``sliceName`` — (optional) per-slice source filenames
            %     - ``imageDescription`` — (optional) JPEG Comment tag
            %
            %   - **filename** — full path template, e.g. ``'/out/frame.jpg'``
            %   - **options** — struct with fields:
            %
            %     - ``Quality`` — [double] 0–100; default: ``90``
            %     - ``Compression`` — [char] ``'lossy'`` | ``'lossless'``; default: ``'lossy'``
            %     - ``showWaitbar`` — logical; default: ``true``
            %     - ``silent`` — logical, suppress dialogs; default: ``false``
            %     - ``overwrite`` — logical; default: ``true``
            %     - ``FilenameGenerator`` — [char] filename generation mode
            %
            % Output Arguments:
            %   - **fnOut** — cell of char with all saved paths, or single char if only one slice
            %

            fnOut = [];

            % Track which options were explicitly provided by the caller
            callerSetQuality     = isfield(options, 'Quality');
            callerSetCompression = isfield(options, 'Compression');
            callerSetFilename    = isfield(options, 'FilenameGenerator');

            % --- defaults ---
            if ~isfield(options, 'showWaitbar');       options.showWaitbar    = true;   end
            if ~isfield(options, 'silent');            options.silent         = false;  end
            if ~isfield(options, 'overwrite');         options.overwrite      = true;   end
            if ~isfield(options, 'FilenameGenerator'); options.FilenameGenerator = 'Use sequential filename'; end
            if ~isfield(options, 'Quality');           options.Quality        = 90;     end
            if ~isfield(options, 'Compression');       options.Compression    = 'lossy'; end

            comment = '';
            if isfield(metadata,'imageDescription'); comment = metadata.imageDescription; end

            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isempty(ext); ext = '.jpg'; end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr,'dir') ~= 7; mkdir(pathStr); end

            [~, ~, nD, nC, nT] = size(data);

            % JPEG supports ≤3 channels; multichannel must be uint8
            if nC > 3
                warning('JpgSaver:tooManyChannels', ...
                    'JPEG supports ≤3 colour channels; got %d.', nC);
                return;
            end
            if nC > 1 && ~isa(data,'uint8')
                warning('JpgSaver:wrongClass', ...
                    'Multichannel JPEG requires uint8; got %s. Skipping.', class(data));
                return;
            end

            % --- combined "JPG saving settings" dialog ---
            % Always shown when not silent and Quality or Compression were not
            % caller-provided.  The "Filename generator" field is appended only
            % when original slice names are available and were not pre-set.
            showNaming = ~callerSetFilename && ...
                isfield(metadata, 'sliceName') && numel(metadata.sliceName) == nD && ...
                nT == 1 && nD > 1;

            if ~options.silent && (~callerSetQuality || ~callerSetCompression || showNaming)
                prompts = {'Compression mode:'; 'Quality (0-100):'};
                defAns  = {{'lossy', 'lossless', 1}; 
                    struct('Spinner', true, 'Value', options.Quality, 'Limits', [0 100], 'Step', 1, 'Round', true)};

                if showNaming
                    prompts{end+1} = 'Filename generator:';
                    defAns{end+1}  = {'Use original filename', 'Use sequential filename', 1};
                end
                dlgOpts.mibPath     = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                dlgOpts.LabelPosition = 'left';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'JPG saving settings', dlgOpts);
                if isempty(answer); return; end
                options.Compression = answer{1};
                options.Quality     = answer{2};
                if showNaming
                    options.FilenameGenerator = answer{3};
                end
            end

            % --- build output names ---
            sliceNames = obj.buildSliceNames(baseName, pathStr, nD, ext, options, metadata);

            % --- progress ---
            wb = [];
            if options.showWaitbar
                wb = obj.createProgressDialog('Saving images...', sprintf('Saving JPEG — %s', baseName), false);
            end

            allFn = {};
            done  = 0;
            total = nD * nT;

            try
                for t = 1:nT
                    for z = 1:nD
                        img2D = squeeze(data(:,:,z,:,t));  % [H, W, C]

                        if nT > 1
                            [~, sn, se] = fileparts(sliceNames{z});
                            outName = fullfile(pathStr, sprintf('%s_T%03d%s', sn, t, se));
                        else
                            outName = sliceNames{z};
                        end

                        commentArgs = {};
                        if ~isempty(comment); commentArgs = {'Comment', comment}; end
                        imwrite(img2D, outName, 'jpg', ...
                            commentArgs{:}, ...
                            'Mode',    options.Compression, ...
                            'Quality', options.Quality);

                        allFn{end+1} = outName; %#ok<AGROW>
                        done = done + 1;
                        if ~isempty(wb); wb.Value = done/total; end
                    end
                end
            catch ME
                if ~isempty(wb); delete(wb); end
                rethrow(ME);
            end
            if ~isempty(wb); delete(wb); end

            fprintf('JpgSaver: saved %d file(s) → %s\n', numel(allFn), pathStr);
            if isscalar(allFn)
                fnOut = allFn{1};
            else
                fnOut = allFn(:);
            end
        end

    end
end
