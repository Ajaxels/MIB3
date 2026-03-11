classdef (Abstract) BaseSaver < handle
    % classdef BaseSaver < handle
    % Abstract base class for all MIB3 image format savers.
    %
    % This class defines the standard interface that every concrete saver
    % must implement, and provides protected utility methods shared across
    % all formats.  The design mirrors io.loaders.BaseImageLoader so that
    % the loading and saving layers are symmetric.
    %
    % DATA CONVENTION
    %   All data passed to save() uses the MIB3 native dimension order:
    %       data = [Height, Width, Depth, Colors, Time]  (5-D)
    %   Each saver is responsible for any permutation required by the
    %   underlying file-format library (e.g. imwrite expects [H W C D]).
    %
    % METADATA CONVENTION
    %   metadata is a plain struct populated by MibImage.save() or
    %   MibLabels.save() from the object's own properties.  MibDataset
    %   additionally injects .pixSize before delegating.
    %   Required fields:
    %     .filename    — (char) source image filename
    %     .colorType   — (char) 'grayscale' | 'multichannel' | 'indexed'
    %     .lutColors   — (double [C x 3]) per-channel LUT, values 0..1
    %     .dataClass   — (char) 'uint8' | 'uint16' | 'uint32' | ...
    %     .maxInt      — (double) maximum representable intensity
    %     .sliceName   — (cell of char) per-slice source filenames
    %   Optional fields injected by MibDataset:
    %     .pixSize       — struct {.x .y .z .t .units .tunits}
    %     .boundingBox   — [xmin xmax ymin ymax zmin zmax]
    %     .imageDescription — (char) full ImageDescription tag
    %     .xResolution   — scalar pixels/unit horizontal
    %     .yResolution   — scalar pixels/unit vertical
    %   Label-specific fields injected by MibLabels.save():
    %     .materialNames  — cell array of material name strings
    %     .materialColors — [M x 3] per-material RGB (0..1)
    %     .labelsVariable — (char) variable name used inside .model/.mat
    %   Mask-specific fields injected by MibDataset.save():
    %     .maskFilename  — (char) mask output filename
    %     .maskColor     — [1 x 3] mask overlay colour (0..1)
    %
    % USAGE (from user scripts)
    %   The preferred entry points are the high-level methods:
    %     core.MibImage.save(filename, options)
    %     core.MibDataset.save(layerType, filename, options)
    %     models.MibModel.save(layerType, filename, BatchOptIn)
    %
    %   Direct use of a saver is possible for advanced workflows:
    %     saver = io.SaverFactory.create('TIF format uncompressed (*.tif)');
    %     fnOut = saver.save(data, metadata, '/tmp/out.tif', options);
    %
    % SEE ALSO
    %   io.SaverFactory, io.loaders.BaseImageLoader

    properties
        Options struct   % Options struct passed during construction (may be empty)
    end

    % ------------------------------------------------------------------ %
    %   Abstract interface — every concrete saver must implement these     %
    % ------------------------------------------------------------------ %
    methods (Abstract)
        fnOut = save(obj, data, metadata, filename, options)
        % function fnOut = save(obj, data, metadata, filename, options)
        % Write data to a file in the format handled by this saver.
        %
        % Parameters:
        %   data     — (numeric) [H, W, D, C, T] array.
        %              For mask/labels it is uint8/uint16/... with label IDs.
        %   metadata — (struct) see class-level description above.
        %   filename — (char) full output path INCLUDING extension,
        %              e.g. '/data/experiment/out.tif' or
        %                   'C:\data\Labels_myStack.model'
        %              The directory must already exist; use
        %              buildOutputPath() to assemble the path.
        %   options  — (struct) runtime options:
        %     .Format           — (char) format string matching SaverFactory
        %                         registry, e.g. 'TIF format uncompressed (*.tif)'
        %     .Saving3DPolicy   — (char) '3D stack' | '2D sequence'
        %     .showWaitbar      — (logical) display progress bar
        %     .silent           — (logical) suppress all dialogs
        %     .FilenameGenerator — (char) 'Use original filename' |
        %                                  'Use sequential filename'
        %     .Compression      — (char) 'none' | 'lzw' | 'packbits' (TIF)
        %                                 or 'lossy' | 'lossless'     (JPG)
        %     .Quality          — (double 0-100) JPG quality
        %     .MaterialIndex    — (double|[]) index of label material to
        %                         export; [] = all, NaN = currently selected
        %     .overwrite        — (logical) silently overwrite existing files
        %
        % Return values:
        %   fnOut — (char OR cell of char) path(s) of saved file(s).
        %           Returns [] on failure or cancellation.
        %
        % Example:
        %   @code
        %   saver = io.SaverFactory.create('TIF format uncompressed (*.tif)');
        %   opts.Format         = 'TIF format uncompressed (*.tif)';
        %   opts.Saving3DPolicy = '3D stack';
        %   opts.showWaitbar    = false;
        %   opts.silent         = true;
        %   opts.Compression    = 'none';
        %   opts.overwrite      = true;
        %   opts.pixSize        = struct('x',0.1,'y',0.1,'z',0.5,'units','um','t',1,'tunits','s');
        %   meta.filename       = 'source.tif';
        %   meta.colorType      = 'grayscale';
        %   meta.lutColors      = [1 1 1];
        %   meta.dataClass      = 'uint8';
        %   meta.maxInt         = 255;
        %   meta.sliceName      = {};
        %   data = uint8(rand(256,256,10,1,1) * 255);  % [H,W,D,C,T]
        %   fnOut = saver.save(data, meta, '/tmp/stack.tif', opts);
        %   @endcode

        formats = getSupportedFormats(obj)
        % function formats = getSupportedFormats(obj)
        % Return the list of format strings handled by this saver.
        %
        % These strings must exactly match the keys used in SaverFactory's
        % internal registry so that the factory can map a format string to
        % the correct saver class.
        %
        % Return values:
        %   formats — (cell of char) format strings, e.g.
        %             {'TIF format uncompressed (*.tif)',
        %              'TIF format LZW compression (*.tif)'}
        %
        % Example:
        %   @code
        %   saver   = io.savers.TiffSaver();
        %   formats = saver.getSupportedFormats();
        %   % formats{1} == 'TIF format uncompressed (*.tif)'
        %   @endcode
    end

    % ------------------------------------------------------------------ %
    %   Protected shared utilities                                         %
    % ------------------------------------------------------------------ %
    methods (Access = protected)

        function fn = generateSequentialFilename(~, baseName, idx, total, ext)
            % function fn = generateSequentialFilename(~, baseName, idx, total, ext)
            % Build a zero-padded sequential filename such as 'stack_003.tif'.
            %
            % The number of padding digits is chosen automatically based on
            % the total file count so that alphabetical and numerical order
            % match (important for downstream tools that sort by filename).
            %
            % Parameters:
            %   baseName — (char) filename stem WITHOUT extension,
            %              e.g. 'myStack' or '/output/dir/myStack'
            %   idx      — (integer) 1-based sequential index of this file
            %   total    — (integer) total number of files in the series
            %   ext      — (char) extension INCLUDING leading dot, e.g. '.tif'
            %
            % Return values:
            %   fn — (char) generated filename, e.g. 'myStack_003.tif'
            %
            % Example:
            %   @code
            %   % For a 50-slice series, generates 'out_07.tif'
            %   fn = obj.generateSequentialFilename('out', 7, 50, '.tif');
            %   % fn == 'out_07.tif'
            %
            %   % For a 1000-slice series, generates 'out_007.tif'
            %   fn = obj.generateSequentialFilename('out', 7, 1000, '.tif');
            %   % fn == 'out_007.tif'
            %   @endcode
            if total == 1
                fn = [baseName ext];
            elseif total < 100
                fn = sprintf('%s_%02d%s', baseName, idx, ext);
            elseif total < 1000
                fn = sprintf('%s_%03d%s', baseName, idx, ext);
            elseif total < 10000
                fn = sprintf('%s_%04d%s', baseName, idx, ext);
            elseif total < 100000
                fn = sprintf('%s_%05d%s', baseName, idx, ext);
            else
                fn = sprintf('%s_%06d%s', baseName, idx, ext);
            end
        end

        function fullpath = buildOutputPath(~, destDir, fname)
            % function fullpath = buildOutputPath(~, destDir, fname)
            % Combine a destination directory and a filename into a full path.
            %
            % If destDir is empty the filename is returned unchanged (useful
            % when the caller already embedded the directory in fname).
            %
            % Parameters:
            %   destDir — (char) directory portion; may be empty ('')
            %   fname   — (char) filename, with or without leading directory
            %
            % Return values:
            %   fullpath — (char) combined path
            %
            % Example:
            %   @code
            %   p = obj.buildOutputPath('/data/out', 'stack.tif');
            %   % p == '/data/out/stack.tif'
            %
            %   p = obj.buildOutputPath('', '/already/full/path.tif');
            %   % p == '/already/full/path.tif'
            %   @endcode
            if isempty(destDir)
                fullpath = fname;
            else
                fullpath = fullfile(destDir, fname);
            end
        end

        function imgOut = permuteMib3ToHWCD(~, data, t)
            % function imgOut = permuteMib3ToHWCD(~, data, t)
            % Convert MIB3 native layout [H,W,D,C,T] to legacy [H,W,C,D]
            % for a single time point, as expected by legacy helpers such
            % as the TIFF/PNG/JPG writers ported from MIB2.
            %
            % Parameters:
            %   data — (numeric) full 5-D array [H, W, D, C, T]
            %   t    — (integer) 1-based time index
            %
            % Return values:
            %   imgOut — (numeric) [H, W, C, D] slice for time t
            %
            % Example:
            %   @code
            %   % data is [512 512 10 3 2] (H W D C T)
            %   slice_t1 = obj.permuteMib3ToHWCD(data, 1);
            %   % slice_t1 is [512 512 3 10]
            %   @endcode
            imgOut = permute(data(:, :, :, :, t), [1 2 4 3]);  % [H, W, C, D]
        end

        function [pathStr, baseName, ext] = splitFilename(~, filename)
            % function [pathStr, baseName, ext] = splitFilename(~, filename)
            % Wrapper around fileparts with lower-cased extension.
            %
            % Parameters:
            %   filename — (char) full path to decompose
            %
            % Return values:
            %   pathStr  — (char) directory portion
            %   baseName — (char) file stem without extension
            %   ext      — (char) lower-case extension including dot
            %
            % Example:
            %   @code
            %   [p, n, e] = obj.splitFilename('/data/stack.TIF');
            %   % p == '/data', n == 'stack', e == '.tif'
            %   @endcode
            [pathStr, baseName, ext] = fileparts(filename);
            ext = lower(ext);
        end

        function sliceNames = buildSliceNames(obj, baseName, pathStr, depth, ext, options, metadata)
            % function sliceNames = buildSliceNames(obj, baseName, pathStr, depth, ext, options, metadata)
            % Build a cell array of per-slice output filenames for 2D sequences.
            %
            % Respects the options.FilenameGenerator policy:
            %   'Use original filename' — derives names from metadata.sliceName
            %                             when available; falls back to sequential
            %   'Use sequential filename' (default) — generates numbered names
            %
            % Parameters:
            %   baseName — (char) stem used for sequential naming
            %   pathStr  — (char) destination directory
            %   depth    — (integer) number of slices (Z)
            %   ext      — (char) extension with leading dot, e.g. '.tif'
            %   options  — (struct) must contain .FilenameGenerator (char)
            %   metadata — (struct) may contain .sliceName (cell of char)
            %
            % Return values:
            %   sliceNames — (cell of char) [depth x 1] full output paths
            %
            % Example:
            %   @code
            %   % Sequential naming for 5 slices
            %   opts.FilenameGenerator = 'Use sequential filename';
            %   names = obj.buildSliceNames('myStack', '/out', 5, '.png', opts, meta);
            %   % names == {'/out/myStack_01.png'; ...'/out/myStack_05.png'}
            %   @endcode
            useOriginal = isfield(options, 'FilenameGenerator') && ...
                strcmp(options.FilenameGenerator, 'Use original filename') && ...
                isfield(metadata, 'sliceName') && ...
                numel(metadata.sliceName) == depth;

            sliceNames = cell(depth, 1);
            if useOriginal
                for z = 1:depth
                    [~, sn] = fileparts(metadata.sliceName{z});
                    sliceNames{z} = fullfile(pathStr, [sn ext]);
                end
            else
                for z = 1:depth
                    sliceNames{z} = fullfile(pathStr, ...
                        obj.generateSequentialFilename(baseName, z, depth, ext));
                end
            end
        end

    end  % protected methods
end
