classdef PngSaver < io.savers.BaseSaver
    % classdef PngSaver < io.savers.BaseSaver
    % Saver for Portable Network Graphics (PNG) output.
    %
    % PNG is a lossless raster format.  Because PNG files are inherently
    % 2-D, every Z-slice is saved as a separate file (always sequence mode).
    % Multichannel data with more than 3 colour channels is not supported
    % (PNG maximum = 3 channels + optional alpha).
    %
    % Handled format strings:
    %   'Portable Network Graphics (*.png)'  — used when saving image layer
    %   'PNG format (*.png)'                 — alias used for mask/labels
    %
    % DATA DIMENSIONS
    %   Input  data : [H, W, D, C, T]
    %   imwrite call: [H, W, C] per 2-D slice (Z and T loops)
    %
    % NOTES
    %   * For indexed images metadata.colormap (or metadata.lutColors) is
    %     used as the colour table.
    %   * Resolution metadata (pixels/unit) is stored in the PNG file if
    %     metadata.xResolution and metadata.yResolution are provided.
    %   * When options.FilenameGenerator = 'Use original filename', slice
    %     names are derived from metadata.sliceName when available.
    %
    % USAGE EXAMPLES
    %   @code
    %   %% 1. Direct saver use
    %   saver = io.SaverFactory.create('Portable Network Graphics (*.png)');
    %
    %   opts.Format            = 'Portable Network Graphics (*.png)';
    %   opts.showWaitbar       = false;
    %   opts.silent            = true;
    %   opts.overwrite         = true;
    %   opts.FilenameGenerator = 'Use sequential filename';
    %
    %   meta.filename     = 'source.tif';
    %   meta.colorType    = 'grayscale';
    %   meta.lutColors    = [1 1 1];
    %   meta.dataClass    = 'uint8';
    %   meta.maxInt       = 255;
    %   meta.sliceName    = {};
    %   meta.xResolution  = 72;
    %   meta.yResolution  = 72;
    %   meta.imageDescription = 'EM dataset';
    %
    %   data = uint8(rand(256,256,10,1,1)*255);  % [H W D C T]
    %   fnOut = saver.save(data, meta, '/output/slice.png', opts);
    %   % Generates /output/slice_01.png … /output/slice_10.png
    %   @endcode
    %
    %   @code
    %   %% 2. Via MibDataset (intermediate layer)
    %   opts.Format            = 'Portable Network Graphics (*.png)';
    %   opts.showWaitbar       = false;
    %   opts.silent            = true;
    %   opts.overwrite         = true;
    %   fnOut = dataset.save('image', '/output/slice.png', opts);
    %   @endcode
    %
    %   @code
    %   %% 3. Save mask as PNG sequence
    %   opts.Format            = 'PNG format (*.png)';
    %   opts.showWaitbar       = false;
    %   opts.silent            = true;
    %   opts.overwrite         = true;
    %   fnOut = dataset.save('mask', '/output/Mask_slice.png', opts);
    %   @endcode
    %
    % SEE ALSO
    %   io.SaverFactory, io.savers.BaseSaver, io.savers.TiffSaver,
    %   core.MibImage.save, core.MibDataset.save

    methods

        function obj = PngSaver(options)
            % Constructor.
            if nargin < 1; options = struct(); end
            obj.Options = options;
            obj.initBaseProps(options);
        end

        function formats = getSupportedFormats(~)
            formats = { ...
                'Portable Network Graphics (*.png)'; ...
                'PNG format (*.png)' };
        end

        function fnOut = save(obj, data, metadata, filename, options)
            % function fnOut = save(obj, data, metadata, filename, options)
            % Write a PNG 2-D sequence (one file per Z-slice × time point).
            %
            % Parameters:
            %   data     — [H, W, D, C, T] numeric array
            %   metadata — struct; used fields:
            %     .colorType    — 'grayscale'|'multichannel'|'indexed'
            %     .lutColors    — (optional) colormap for indexed images
            %     .sliceName    — (optional) per-slice source filenames
            %     .imageDescription — (optional) comment string for PNG files
            %     .xResolution, .yResolution — (optional) pixels/unit
            %   filename — full path template, e.g. '/out/slice.png'.
            %              The stem is used as the base for sequential names.
            %   options  — struct; used fields described in BaseSaver.save()
            %
            % Return values:
            %   fnOut — cell of char [{nD*nT} x 1] with all saved paths,
            %           or a single char when only one slice was saved
            %
            % Example — see class-level documentation above.

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

            [~, ~, nD, nC, nT] = size(data);

            % PNG supports max 3 colour channels + optional alpha
            if nC > 3
                warning('PngSaver:tooManyChannels', ...
                    'PNG supports ≤3 colour channels; got %d.', nC);
                return;
            end

            % --- "Define naming" dialog ---
            % Show when slice names are available and FilenameGenerator was not
            % explicitly provided by the caller.
            if ~options.silent && ~callerSetFilename && ...
                    isfield(metadata, 'sliceName') && numel(metadata.sliceName) == nD && ...
                    nT == 1 && nD > 1
                prompts  = {'Filename generator:'};
                defAns   = {{'Use original filename', 'Use sequential filename', 1}};
                dlgOpts.mibPath     = obj.mibPath;
                dlgOpts.WindowStyle = 'modal';
                answer = utils.dlgs.inputUniversalDlg(obj.ParentFigure, prompts, defAns, ...
                    'Define naming', dlgOpts);
                if isempty(answer); return; end
                options.FilenameGenerator = answer{1};
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
                        img2D = squeeze(data(:,:,z,:,t));  % [H, W, C]

                        % Derive output name for this (t, z) pair
                        if nT > 1
                            [~, sn, se] = fileparts(sliceNames{z});
                            outName = fullfile(pathStr, sprintf('%s_T%03d%s', sn, t, se));
                        else
                            outName = sliceNames{z};
                        end

                        if isnan(cmap)
                            imwrite(img2D, outName, 'png', ...
                                'Comment',        comment, ...
                                'XResolution',    xRes, ...
                                'YResolution',    yRes, ...
                                'ResolutionUnit', 'Unknown');
                        else
                            imwrite(img2D, cmap, outName, 'png', ...
                                'Comment',        comment, ...
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
