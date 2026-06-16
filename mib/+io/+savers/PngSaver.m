classdef PngSaver < io.savers.BaseSaver
% PNGSAVER - Saver for Portable Network Graphics (PNG) output.
%
% PNG is a lossless raster format.  Because PNG files are inherently
% 2-D, every Z-slice is saved as a separate file (always sequence mode).
% Multichannel data with more than 3 colour channels is not supported
% (PNG maximum = 3 channels + optional alpha).
%
% Handled format strings:
% 'Portable Network Graphics (``*.png``)'  — used when saving image layer
% 'PNG format (``*.png``)'                 — alias used for mask/labels
%
% DATA DIMENSIONS
% Input  data : [H, W, D, C, T]
% imwrite call: [H, W, C] per 2-D slice (Z and T loops)
%
% NOTES
% * For indexed images metadata.colormap (or metadata.lutColors) is
% used as the colour table.
% * Resolution metadata (pixels/unit) is stored in the PNG file if
% metadata.xResolution and metadata.yResolution are provided.
% * When options.FilenameGenerator = 'Use original filename', slice
% names are derived from metadata.sliceName when available.
%
% USAGE EXAMPLES
%
% .. code-block:: matlab
%
%     %% 1. Direct saver use
%     saver = io.SaverFactory.create('Portable Network Graphics (``*.png``)');
%
%     opts.Format            = 'Portable Network Graphics (``*.png``)';
%     opts.showWaitbar       = false;
%     opts.silent            = true;
%     opts.overwrite         = true;
%     opts.FilenameGenerator = 'Use sequential filename';
%
%     meta.filename     = 'source.tif';
%     meta.colorType    = 'grayscale';
%     meta.lutColors    = [1 1 1];
%     meta.dataClass    = 'uint8';
%     meta.maxInt       = 255;
%     meta.sliceName    = {};
%     meta.xResolution  = 72;
%     meta.yResolution  = 72;
%     meta.imageDescription = 'EM dataset';
%
%     data = uint8(rand(256,256,10,1,1)*255);  % [H W D C T]
%     fnOut = saver.save(data, meta, '/output/slice.png', opts);
%     % Generates /output/slice_01.png … /output/slice_10.png
%
%
%
% .. code-block:: matlab
%
%     %% 2. Via MibDataset (intermediate layer)
%     opts.Format            = 'Portable Network Graphics (``*.png``)';
%     opts.showWaitbar       = false;
%     opts.silent            = true;
%     opts.overwrite         = true;
%     fnOut = dataset.save('image', '/output/slice.png', opts);
%
%
%
% .. code-block:: matlab
%
%     %% 3. Save mask as PNG sequence
%     opts.Format            = 'PNG format (``*.png``)';
%     opts.showWaitbar       = false;
%     opts.silent            = true;
%     opts.overwrite         = true;
%     fnOut = dataset.save('mask', '/output/Mask_slice.png', opts);
%
%
% SEE ALSO
% io.SaverFactory, io.savers.BaseSaver, io.savers.TiffSaver,
% core.MibImage.save, core.MibDataset.save

    methods

        function obj = PngSaver(options)
            % PNGSAVER - Constructor for PngSaver class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      saver = io.savers.PngSaver(options)
            %
            % Input Arguments:
            %   - **options** — *(optional)* struct, saver-level options (usually empty;
            %     per-save options are passed to ``save()`` instead)
            %
            % Output Arguments:
            %   - **obj** — instance of the PngSaver class
            %
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            % GETSUPPORTEDFORMATS - Return format strings handled by PngSaver.
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
            %   - **formats** — cell array of format strings for PNG output
            %
            formats = { ...
                'Portable Network Graphics (*.png)'; ...
                'PNG format (*.png)' };
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % SAVE - Write a PNG 2-D sequence (one file per Z-slice × time point).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.save(data, metadata, filename, options)
            %
            % PNG stores one 2-D image per Z-slice and optionally per time point.
            % The stem of the output filename is used as the base for sequential numbering.
            %
            % Input Arguments:
            %   - **data** — [H, W, D, C, T] numeric array
            %   - **metadata** — struct with fields:
            %
            %     - ``colorType`` — ``'grayscale'`` | ``'multichannel'`` | ``'indexed'``
            %     - ``lutColors`` — *(optional)* [N × 3] colormap for indexed images
            %     - ``colormap`` — *(optional)* [N × 3] colormap (alternative to ``lutColors``)
            %     - ``sliceName`` — *(optional)* per-slice source filenames (for 'Use original filename' mode)
            %     - ``imageDescription`` — *(optional)* [char] comment/description string for PNG files
            %     - ``xResolution`` — *(optional)* [numeric] X resolution in pixels/unit; default: ``72``
            %     - ``yResolution`` — *(optional)* [numeric] Y resolution in pixels/unit; default: ``72``
            %
            %   - **filename** — [char] full path template, e.g. ``'/out/slice.png'``;
            %     stem is used as base for sequential names
            %   - **options** — struct with fields:
            %
            %     - ``Format`` — format string
            %     - ``showWaitbar`` — logical; default: ``true``
            %     - ``silent`` — logical, suppress dialogs; default: ``false``
            %     - ``overwrite`` — logical; default: ``true``
            %     - ``FilenameGenerator`` — ``'Use original filename'`` | ``'Use sequential filename'``
            %
            % Output Arguments:
            %   - **fnOut** — cell of char [{nD × nT} × 1] with all saved paths,
            %     or single char when only one slice was saved
            %
            % **Example** — see class-level documentation above.
            %
            % PNG is inherently per-slice, so ``save`` is a thin wrapper over the
            % streaming primitive ``saveStream`` (single code path).
            if nargin < 5; options = struct(); end
            fnOut = obj.saveStream(io.savers.InMemorySliceProvider(data), metadata, filename, options);
        end

        function fnOut = saveStream(obj, provider, metadata, filename, options)
            % SAVESTREAM - Write a PNG 2-D sequence one slice at a time from a SliceProvider.
            %
            % Memory-bounded twin of ``save``: pulls each Z-slice (per time point)
            % from ``provider.getSlice(z, t)`` and writes it as an individual PNG.
            % See ``io.savers.BaseSaver.saveStream``.
            %
            % **Example** — stream a level to a numbered PNG sequence:
            %
            %   .. code-block:: matlab
            %
            %      provider = io.savers.MibImageSliceProvider(img, 'image', 2, [], numZ, 1, zScale);
            %      saver    = io.savers.PngSaver(struct());
            %      meta.colorType = 'grayscale';
            %      saver.saveStream(provider, meta, 'C:\out\slice.png', ...
            %          struct('silent',true,'showWaitbar',false,'FilenameGenerator','Use sequential filename'));
            %      % → C:\out\slice_001.png … slice_NNN.png
            if nargin < 5; options = struct(); end

            fnOut = [];

            % Track which options were explicitly provided by the caller
            callerSetFilename = isfield(options, 'FilenameGenerator');

            % --- defaults ---
            if ~isfield(options, 'showWaitbar');       options.showWaitbar = true;  end
            if ~isfield(options, 'silent');            options.silent      = false; end
            if ~isfield(options, 'overwrite');         options.overwrite   = true;  end
            if ~isfield(options, 'FilenameGenerator'); options.FilenameGenerator = 'Use sequential filename'; end

            % --- resolution ---
            xRes = 72;  yRes = 72;
            if isfield(metadata,'xResolution') && ~isempty(metadata.xResolution); xRes = metadata.xResolution; end
            if isfield(metadata,'yResolution') && ~isempty(metadata.yResolution); yRes = metadata.yResolution; end

            % --- comment / description ---
            comment = '';
            if isfield(metadata,'imageDescription'); comment = metadata.imageDescription; end

            % --- colormap ---
            cmap = NaN;
            if isfield(metadata,'colorType') && strcmp(metadata.colorType,'indexed')
                if isfield(metadata,'colormap') && ~isempty(metadata.colormap)
                    cmap = metadata.colormap;
                elseif isfield(metadata,'lutColors') && size(metadata.lutColors,1) > 1
                    cmap = metadata.lutColors;
                end
            end

            % --- decompose filename ---
            [pathStr, baseName, ext] = obj.splitFilename(filename);
            if isempty(ext); ext = '.png'; end
            if isempty(pathStr); pathStr = pwd; end
            if exist(pathStr,'dir') ~= 7; mkdir(pathStr); end

            sz = provider.OutputSize; nD = sz(3); nC = sz(4); nT = sz(5);

            % PNG supports max 3 colour channels + optional alpha
            if nC > 3
                warning('PngSaver:tooManyChannels', ...
                    'PNG supports ≤3 colour channels; got %d.', nC);
                return;
            end

            % --- "Define naming" dialog ---
            % Show when slice names are available and FilenameGenerator was not
            % explicitly provided by the caller.
            hasSliceSizes = isfield(metadata, 'sliceSize') && size(metadata.sliceSize, 1) == nD;
            showNamingDlg = ~options.silent && ~callerSetFilename && ...
                    isfield(metadata, 'sliceName') && numel(metadata.sliceName) == nD && ...
                    nT == 1 && nD > 1;
            showSizeDlg = ~options.silent && hasSliceSizes && nD > 1;
            if showNamingDlg || showSizeDlg
                prompts = {};
                defAns  = {};
                if showNamingDlg
                    prompts{end+1} = 'Filename generator:';
                    defAns{end+1}  = {'Use original filename', 'Use sequential filename', 1};
                end
                if showSizeDlg
                    prompts{end+1} = 'Restore original slice dimensions:';
                    defAns{end+1}  = {'No', 'Yes', 1};
                end
                dlgOpts.mibPath     = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, '', prompts, defAns, ...
                    'Define naming', dlgOpts);
                if isempty(answer); return; end
                answerIdx = 1;
                if showNamingDlg
                    options.FilenameGenerator = answer{answerIdx}; answerIdx = answerIdx + 1;
                end
                if showSizeDlg
                    options.RestoreOriginalSize = strcmp(answer{answerIdx}, 'Yes');
                end
            end

            % --- build per-slice output names ---
            sliceNames = obj.buildSliceNames(baseName, pathStr, nD, ext, options, metadata);

            % --- progress bar ---
            wb = [];
            if options.showWaitbar
                wb = obj.createProgressDialog('Saving images...', sprintf('Saving PNG - %s', baseName), false);
            end

            allFn = {};
            total  = nD * nT;
            done   = 0;

            try
                for t = 1:nT
                    for z = 1:nD
                        img2D = squeeze(provider.getSlice(z, t));  % [H, W, C]
                        if isfield(options, 'RestoreOriginalSize') && options.RestoreOriginalSize && ...
                                hasSliceSizes
                            img2D = obj.cropSliceToOriginalSize(img2D, metadata.sliceSize(z, :));
                        end

                        % Derive output name for this (t, z) pair
                        if nT > 1
                            [~, sn, se] = fileparts(sliceNames{z});
                            outName = fullfile(pathStr, sprintf('%s_T%03d%s', sn, t, se));
                        else
                            outName = sliceNames{z};
                        end

                        commentArgs = {};
                        if ~isempty(comment); commentArgs = {'Comment', comment}; end
                        if isnan(cmap)
                            imwrite(img2D, outName, 'png', ...
                                commentArgs{:}, ...
                                'XResolution',    xRes, ...
                                'YResolution',    yRes, ...
                                'ResolutionUnit', 'Unknown');
                        else
                            imwrite(img2D, cmap, outName, 'png', ...
                                commentArgs{:}, ...
                                'XResolution',    xRes, ...
                                'YResolution',    yRes, ...
                                'ResolutionUnit', 'Unknown');
                        end

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

            fprintf('PngSaver: saved %d file(s) → %s\n', numel(allFn), pathStr);
            if isscalar(allFn)
                fnOut = allFn{1};
            else
                fnOut = allFn(:);
            end
        end

    end
end
