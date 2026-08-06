classdef JpgSaver < io.savers.BaseSaver
% JPGSAVER - Saver for JPEG output - one file per Z-slice (always a 2-D sequence).
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
% * options.Quality  (0-100, default 90): JPEG quality factor.
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
            %   - **options** - *(optional)* struct, saver-level options (usually empty;
            %     per-save options are passed to ``save()`` instead)
            %
            % Output Arguments:
            %   - **obj** - instance of the JpgSaver class
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
            %   - **formats** - cell array of format strings for JPEG output
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
            %   - **data** - [H, W, D, C, T] uint8 (or uint16 greyscale)
            %   - **metadata** - struct with fields:
            %
            %     - ``colorType`` - data type (multichannel RGB must be uint8)
            %     - ``sliceName`` - (optional) per-slice source filenames
            %     - ``imageDescription`` - (optional) JPEG Comment tag
            %
            %   - **filename** - full path template, e.g. ``'/out/frame.jpg'``
            %   - **options** - struct with fields:
            %
            %     - ``Quality`` - [double] 0-100; default: ``90``
            %     - ``Compression`` - [char] ``'lossy'`` | ``'lossless'``; default: ``'lossy'``
            %     - ``showWaitbar`` - logical; default: ``true``
            %     - ``silent`` - logical, suppress dialogs; default: ``false``
            %     - ``overwrite`` - logical; default: ``true``
            %     - ``FilenameGenerator`` - [char] filename generation mode
            %
            % Output Arguments:
            %   - **fnOut** - cell of char with all saved paths, or single char if only one slice
            %
            % JPEG is inherently per-slice, so ``save`` is a thin wrapper over the
            % streaming primitive ``saveStream`` (single code path).
            if nargin < 5; options = struct(); end
            fnOut = obj.saveStream(io.savers.InMemorySliceProvider(data), metadata, filename, options);
        end

        function fnOut = saveStream(obj, provider, metadata, filename, options)
            % SAVESTREAM - Write a JPEG 2-D sequence one slice at a time from a SliceProvider.
            % See ``io.savers.BaseSaver.saveStream``.
            %
            % **Example** - stream a level to a JPEG sequence (quality 90):
            %
            %   .. code-block:: matlab
            %
            %      provider = io.savers.MibImageSliceProvider(img, 'image', 2, [], numZ, 1, zScale);
            %      saver    = io.savers.JpgSaver(struct());
            %      meta.colorType = 'grayscale';
            %      saver.saveStream(provider, meta, 'C:\out\frame.jpg', ...
            %          struct('silent',true,'showWaitbar',false,'Quality',90,'Compression','lossy', ...
            %                 'FilenameGenerator','Use sequential filename'));
            if nargin < 5; options = struct(); end

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

            sz = provider.OutputSize; nD = sz(3); nC = sz(4); nT = sz(5);

            % JPEG supports ≤3 channels; multichannel must be uint8
            if nC > 3
                warning('JpgSaver:tooManyChannels', ...
                    'JPEG supports ≤3 colour channels; got %d.', nC);
                return;
            end
            if nC > 1 && ~strcmp(provider.DataClass, 'uint8')
                warning('JpgSaver:wrongClass', ...
                    'Multichannel JPEG requires uint8; got %s. Skipping.', provider.DataClass);
                return;
            end

            % --- combined "JPG saving settings" dialog ---
            % Always shown when not silent and Quality or Compression were not
            % caller-provided.  The "Filename generator" field is appended only
            % when original slice names are available and were not pre-set.
            showNaming = ~callerSetFilename && ...
                isfield(metadata, 'sliceName') && numel(metadata.sliceName) == nD && ...
                nT == 1 && nD > 1;
            hasSliceSizes = isfield(metadata, 'sliceSize') && size(metadata.sliceSize, 1) == nD;

            if ~options.silent && (~callerSetQuality || ~callerSetCompression || showNaming)
                prompts = {'Compression mode:'; 'Quality (0-100):'};
                defAns  = {{'lossy', 'lossless', 1}; 
                    struct('Spinner', true, 'Value', options.Quality, 'Limits', [0 100], 'Step', 1, 'Round', true)};

                if showNaming
                    prompts{end+1} = 'Filename generator:';
                    defAns{end+1}  = {'Use original filename', 'Use sequential filename', 1};
                end
                if hasSliceSizes && nD > 1
                    prompts{end+1} = 'Restore original slice dimensions:';
                    defAns{end+1}  = {'No', 'Yes', 1};
                end
                dlgOpts.mibPath     = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                dlgOpts.LabelPosition = 'left';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'JPG saving settings', dlgOpts);
                if isempty(answer); return; end
                options.Compression = answer{1};
                options.Quality     = answer{2};
                nextIdx = 3;
                if showNaming
                    options.FilenameGenerator = answer{nextIdx}; nextIdx = nextIdx + 1;
                end
                if hasSliceSizes && nD > 1
                    options.RestoreOriginalSize = strcmp(answer{nextIdx}, 'Yes');
                end
            end

            % --- build output names ---
            sliceNames = obj.buildSliceNames(baseName, pathStr, nD, ext, options, metadata);

            % --- progress ---
            wb = [];
            if options.showWaitbar
                wb = obj.createProgressDialog('Saving images...', sprintf('Saving JPEG - %s', baseName), false);
            end

            % Pre-compute loop-invariant values to avoid repeated checks per slice
            doRestoreSize = isfield(options, 'RestoreOriginalSize') && ...
                options.RestoreOriginalSize && hasSliceSizes;
            commentArgs = {};
            if ~isempty(comment); commentArgs = {'Comment', comment}; end
            multiTime = nT > 1;

            total = nD * nT;
            allFn = cell(total, 1);   % pre-allocate - avoids O(N²) dynamic growth
            done  = 0;
            wbStep = max(1, round(total / 100));  % throttle: update waitbar ~100 times

            % Per-slice crop flags: avoid calling crop on slices that are
            % already at canvas size (no padding was added for those slices)
            needsCrop = false(nD, 1);
            if doRestoreSize
                paddedH = provider.SliceSize(1);
                paddedW = provider.SliceSize(2);
                needsCrop = metadata.sliceSize(:,1) < paddedH | ...
                            metadata.sliceSize(:,2) < paddedW;
            end

            try
                for t = 1:nT
                    for z = 1:nD
                        img2D = squeeze(provider.getSlice(z, t));  % [H, W, C]
                        if doRestoreSize && needsCrop(z)
                            img2D = obj.cropSliceToOriginalSize(img2D, metadata.sliceSize(z, :));
                        end

                        if multiTime
                            [~, sn, se] = fileparts(sliceNames{z});
                            outName = fullfile(pathStr, sprintf('%s_T%03d%s', sn, t, se));
                        else
                            outName = sliceNames{z};
                        end

                        imwrite(img2D, outName, 'jpg', ...
                            commentArgs{:}, ...
                            'Mode',    options.Compression, ...
                            'Quality', options.Quality);

                        done = done + 1;
                        allFn{done} = outName;
                        if ~isempty(wb) && mod(done, wbStep) == 0
                            wb.Value = done / total;
                        end
                    end
                end
            catch ME
                if ~isempty(wb); delete(wb); end
                rethrow(ME);
            end
            if ~isempty(wb); delete(wb); end

            fprintf('JpgSaver: saved %d file(s) → %s\n', done, pathStr);
            if isscalar(allFn)
                fnOut = allFn{1};
            else
                fnOut = allFn(:);
            end
        end

    end
end
