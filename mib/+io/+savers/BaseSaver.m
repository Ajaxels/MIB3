classdef (Abstract) BaseSaver < handle
% BASESAVER - Abstract base class for all MIB3 image format savers.
%
% This class defines the standard interface that every concrete saver
% must implement, and provides protected utility methods shared across
% all formats.  The design mirrors io.loaders.BaseImageLoader so that
% the loading and saving layers are symmetric.
%
% DATA CONVENTION
% All data passed to save() uses the MIB3 native dimension order:
% data = [Height, Width, Depth, Colors, Time]  (5-D)
% Each saver is responsible for any permutation required by the
% underlying file-format library (e.g. imwrite expects [H W C D]).
%
% METADATA CONVENTION
% metadata is a plain struct populated by MibImage.save() or
% MibLabels.save() from the object's own properties.  MibDataset
% additionally injects .pixSize before delegating.
% Required fields:
% .filename    - (char) source image filename
% .colorType   - (char) 'grayscale' | 'multichannel' | 'indexed'
% .lutColors   - (double [C x 3]) per-channel LUT, values 0..1
% .dataClass   - (char) 'uint8' | 'uint16' | 'uint32' | ...
% .maxInt      - (double) maximum representable intensity
% .sliceName   - (cell of char) per-slice source filenames
% .sliceSize   - (double [N×2]) per-slice original [height, width]; empty when uniform
% Optional fields injected by MibDataset:
% .pixSize       - struct {.x .y .z .t .units .tunits}
% .boundingBox   - [xmin xmax ymin ymax zmin zmax]
% .imageDescription - (char) full ImageDescription tag
% .xResolution   - scalar pixels/unit horizontal
% .yResolution   - scalar pixels/unit vertical
% Label-specific fields injected by MibLabels.save():
% .materialNames  - cell array of material name strings
% .materialColors - [M x 3] per-material RGB (0..1)
% .labelsVariable - (char) variable name used inside .model/.mat
% Mask-specific fields injected by MibDataset.save():
% .maskFilename  - (char) mask output filename
% .maskColor     - [1 x 3] mask overlay colour (0..1)
%
% USAGE (from user scripts)
% The preferred entry points are the high-level methods:
% core.MibImage.save(filename, options)
% core.MibDataset.save(layerType, filename, options)
% models.MibModel.save(layerType, filename, BatchOptIn)
%
% Direct use of a saver is possible for advanced workflows:
% saver = io.SaverFactory.create('TIF format uncompressed (``*.tif``)');
% fnOut = saver.save(data, metadata, '/tmp/out.tif', options);
%
% SEE ALSO
% io.SaverFactory, io.loaders.BaseImageLoader

    properties
        Options struct   % Options struct passed during construction (may be empty)
        mibPath  (1,:) char = ''
        % Path to MIB installation directory; used by dialogs.
        % Set from options.mibPath at construction time; empty in standalone use.
        ParentFigure = []
        % Handle to the main MIB application window.
        % Required as parent for uiprogressdlg progress bars.
        % Set from options.ParentFigure at construction time; empty in standalone use.
        WaitbarHandle = []
        % Handle to an indeterminate uiprogressdlg created upstream (before data
        % extraction).  When set, createProgressDialog() reuses and switches this
        % dialog to determinate mode instead of creating a new one.
    end

    % ------------------------------------------------------------------ %
    %   Abstract interface - every concrete saver must implement these     %
    % ------------------------------------------------------------------ %
    methods (Abstract)
        fnOut = save(obj, data, metadata, filename, options)
        % SAVE - Write data to a file in the format handled by this saver.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      fnOut = obj.save(data, metadata, filename, options)
        %
        % Input Arguments:
        %   - **data** - [H, W, D, C, T] numeric array;
        %     for mask/labels it contains uint8/uint16/... label IDs
        %   - **metadata** - struct (see class-level description for fields)
        %   - **filename** - [char] full output path INCLUDING extension, e.g.
        %     ``'/data/experiment/out.tif'`` or ``'C:\data\Labels_myStack.model'``;
        %     directory must already exist
        %   - **options** - struct with runtime options:
        %
        %     - ``Format`` - format string matching SaverFactory registry
        %     - ``Saving3DPolicy`` - ``'3D stack'`` | ``'2D sequence'``
        %     - ``showWaitbar`` - logical, display progress bar
        %     - ``silent`` - logical, suppress dialogs
        %     - ``FilenameGenerator`` - ``'Use original filename'`` | ``'Use sequential filename'``
        %     - ``Compression`` - ``'none'`` | ``'lzw'`` | ``'packbits'`` (TIFF) or ``'lossy'`` | ``'lossless'`` (JPEG)
        %     - ``Quality`` - [0-100] JPEG quality
        %     - ``MaterialIndex`` - [numeric | []] material index to export; ``[]`` = all, ``NaN`` = currently selected
        %     - ``overwrite`` - logical, silently overwrite existing files
        %
        % Output Arguments:
        %   - **fnOut** - [char or cell of char] path(s) of saved file(s);
        %     ``[]`` on failure or cancellation
        %
        % **Example** - save TIFF stack with standard settings:
        %
        %   .. code-block:: matlab
        %
        %      saver = io.SaverFactory.create('TIF format uncompressed (``*.tif``)');
        %      opts.Format         = 'TIF format uncompressed (``*.tif``)';
        %      opts.Saving3DPolicy = '3D stack';
        %      opts.showWaitbar    = false;
        %      opts.silent         = true;
        %      opts.Compression    = 'none';
        %      opts.overwrite      = true;
        %      opts.pixSize        = struct('x',0.1,'y',0.1,'z',0.5,'units','um','t',1,'tunits','s');
        %      meta.filename       = 'source.tif';
        %      meta.colorType      = 'grayscale';
        %      meta.lutColors      = [1 1 1];
        %      meta.dataClass      = 'uint8';
        %      meta.maxInt         = 255;
        %      meta.sliceName      = {};
        %      data = uint8(rand(256,256,10,1,1) * 255);  % [H,W,D,C,T]
        %      fnOut = saver.save(data, meta, '/tmp/stack.tif', opts);

        formats = getSupportedFormats(obj)
        % GETSUPPORTEDFORMATS - Return the list of format strings handled by this saver.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      formats = obj.getSupportedFormats()
        %
        % Format strings must exactly match the keys in SaverFactory's internal
        % registry so the factory can map format strings to saver classes.
        %
        % Output Arguments:
        %   - **formats** - cell of char with format strings, e.g.
        %     ``{'TIF format uncompressed (*.tif)', 'TIF format LZW compression (*.tif)'}``
        %
        % **Example** - get supported TIFF formats:
        %
        %   .. code-block:: matlab
        %
        %      saver   = io.savers.TiffSaver();
        %      formats = saver.getSupportedFormats();
        %      % formats{1} == 'TIF format uncompressed (*.tif)'
    end

    % ------------------------------------------------------------------ %
    %   Streaming interface (per-slice, memory-bounded)                    %
    % ------------------------------------------------------------------ %
    methods

        function fnOut = saveStream(obj, provider, metadata, filename, options)
            % SAVESTREAM - Write a dataset one Z-slice at a time from a SliceProvider.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fnOut = obj.saveStream(provider, metadata, filename, options)
            %
            % This is the memory-bounded entry point used by ``core.MibImage.save`` /
            % ``core.MibLabels.save`` to export pyramidal (Virtual / BigData) datasets
            % without ever gathering the full volume: the saver pulls each slice from
            % ``provider`` (an ``io.savers.SliceProvider``) on demand.
            %
            % **Default implementation** (this method) is a *fallback*: it gathers the
            % provider into a full ``[H W D C T]`` array and delegates to ``obj.save``.
            % That keeps every not-yet-migrated saver working - memory is still bounded
            % by the **selected pyramid level** (the caller chooses a coarse level), but
            % a level is held whole. Savers override ``saveStream`` to write truly
            % slice-by-slice (e.g. ``io.savers.TiffSaver``).
            %
            % Input Arguments:
            %   - **provider** - ``io.savers.SliceProvider`` exposing ``OutputSize``,
            %     ``DataClass``, ``NumSlices``, ``NumFrames``, ``NumChannels`` and
            %     ``getSlice(z, t)``
            %   - **metadata** - struct (see class-level description)
            %   - **filename** - [char] full output path including extension
            %   - **options** - struct of runtime options (see ``save``)
            %
            % Output Arguments:
            %   - **fnOut** - [char | cell of char] saved path(s); ``[]`` on failure
            %
            % **Example** - stream a resident volume to any registered format:
            %
            %   .. code-block:: matlab
            %
            %      data     = uint8(rand(128,128,20,1,1) * 255);   % [H W D C T]
            %      provider = io.savers.InMemorySliceProvider(data);
            %      saver    = io.SaverFactory.create('NRRD Data Format (*.nrrd)');
            %      meta.colorType = 'grayscale'; meta.dataClass = 'uint8';
            %      meta.pixSize   = struct('x',1,'y',1,'z',1,'t',1,'units','um','tunits','s');
            %      fnOut = saver.saveStream(provider, meta, 'C:\out\vol.nrrd', struct('silent',true));
            if nargin < 5; options = struct(); end

            sz = provider.OutputSize;
            H = sz(1); W = sz(2); D = sz(3); C = sz(4); T = sz(5);
            data = zeros(sz, provider.DataClass);
            for t = 1:T
                for z = 1:D
                    data(:, :, z, :, t) = reshape(provider.getSlice(z, t), H, W, 1, C);
                end
            end
            fnOut = obj.save(data, metadata, filename, options);
        end

    end

    % ------------------------------------------------------------------ %
    %   Protected shared utilities                                         %
    % ------------------------------------------------------------------ %
    methods (Access = protected)

        function initBaseProps(obj, options)
            % INITBASEPROPS - Extract mibPath and ParentFigure from options into properties.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.initBaseProps(options)
            %
            % Call at the end of every concrete saver constructor.
            %
            % Input Arguments:
            %   - **options** - *(optional)* struct with recognized fields:
            %
            %     - `` `.mibPath` `` - [char] path to MIB installation directory
            %     - `` `.ParentFigure` `` - handle to main MIB window for ``uiprogressdlg``
            %     - `` `.waitbarHandle` `` - *(optional)* handle to upstream indeterminate progress dialog
            %
            %     All fields are optional; absent or empty values are silently ignored.
            %
            % Output Arguments:
            %   (none)
            if nargin < 2 || isempty(options); return; end
            if isfield(options, 'mibPath') && ~isempty(options.mibPath)
                obj.mibPath = options.mibPath;
            end
            if isfield(options, 'ParentFigure') && ~isempty(options.ParentFigure)
                obj.ParentFigure = options.ParentFigure;
            end
            if isfield(options, 'waitbarHandle') && ~isempty(options.waitbarHandle)
                obj.WaitbarHandle = options.waitbarHandle;
            end
        end

        function wb = createProgressDialog(obj, title, message, cancelable, indeterminate)
            % CREATEPROGRESSDIALOG - Create a uiprogressdlg or reuse upstream handle.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      wb = obj.createProgressDialog(title, message, cancelable, indeterminate)
            %
            % Attempts to reuse an indeterminate progress dialog created upstream
            % (stored in ``obj.WaitbarHandle``). If not available or invalid,
            % creates a new ``uiprogressdlg`` attached to ``obj.ParentFigure``.
            % Returns ``[]`` when no valid parent is available (standalone or headless use).
            %
            % Input Arguments:
            %   - **title** - [char] dialog title bar text
            %   - **message** - [char] dialog body message
            %   - **cancelable** - *(optional)* [logical] show Cancel button; default: ``false``
            %   - **indeterminate** - *(optional)* [logical] indeterminate spinner mode; default: ``false``
            %
            % Output Arguments:
            %   - **wb** - ``matlab.ui.dialog.ProgressDialog`` handle, or ``[]`` when no
            %     valid parent is available. **Callers must guard all ``wb`` access with
            %     ``if ~isempty(wb) ... end``**
            if nargin < 4; cancelable    = false; end
            if nargin < 5; indeterminate = false; end

            % Reuse a dialog created upstream (during data-gathering phase)
            if ~isempty(obj.WaitbarHandle)
                try
                    if isvalid(obj.WaitbarHandle)
                        wb = obj.WaitbarHandle;
                        obj.WaitbarHandle = [];   % consume - caller now owns it
                        wb.Indeterminate = 'off';
                        wb.Value         = 0;
                        wb.Title         = title;
                        wb.Message       = message;
                        if cancelable; wb.Cancelable = 'on'; end
                        return;
                    end
                catch
                end
                obj.WaitbarHandle = [];
            end

            wb = [];
            if isempty(obj.ParentFigure); return; end
            try
                if ~isvalid(obj.ParentFigure); return; end
            catch; return; end
            try
                args = {'Title', title, 'Message', message};
                if indeterminate; args = [args, {'Indeterminate', 'on'}]; end
                if cancelable;    args = [args, {'Cancelable', 'on'}]; end
                wb = uiprogressdlg(obj.ParentFigure, args{:});
            catch
                wb = [];
            end
        end

        function fullpath = buildOutputPath(~, destDir, fname)
            % BUILDOUTPUTPATH - Combine a destination directory and filename into a full path.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      fullpath = obj.buildOutputPath(destDir, fname)
            %
            % If ``destDir`` is empty, ``fname`` is returned unchanged (useful when the
            % caller has already embedded the directory in ``fname``).
            %
            % Input Arguments:
            %   - **destDir** - [char] directory portion; may be empty (``''``)
            %   - **fname** - [char] filename, with or without leading directory
            %
            % Output Arguments:
            %   - **fullpath** - [char] combined path
            %
            % **Example 1** - combine directory and filename:
            %
            %   .. code-block:: matlab
            %
            %      p = obj.buildOutputPath('/data/out', 'stack.tif');
            %      % p == '/data/out/stack.tif'
            %
            % **Example 2** - empty directory returns filename unchanged:
            %
            %   .. code-block:: matlab
            %
            %      p = obj.buildOutputPath('', '/already/full/path.tif');
            %      % p == '/already/full/path.tif'
            %
            if isempty(destDir)
                fullpath = fname;
            else
                fullpath = fullfile(destDir, fname);
            end
        end

        function imgOut = permuteMib3ToHWCD(~, data, t)
            % PERMUTEMIB3TOHWCD - Convert MIB3 native [H,W,D,C,T] to legacy [H,W,C,D] layout.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      imgOut = obj.permuteMib3ToHWCD(data, t)
            %
            % Extracts a single time point and reorders dimensions for legacy
            % helpers such as TIFF/PNG/JPG writers ported from MIB2.
            %
            % Input Arguments:
            %   - **data** - [H, W, D, C, T] numeric array (full 5-D)
            %   - **t** - [integer] 1-based time point index
            %
            % Output Arguments:
            %   - **imgOut** - [H, W, C, D] numeric array for time point t
            %
            % **Example 1** - extract first time point with dimension swap:
            %
            %   .. code-block:: matlab
            %
            %      % data is [512 512 10 3 2] (H W D C T)
            %      slice_t1 = obj.permuteMib3ToHWCD(data, 1);
            %      % slice_t1 is [512 512 3 10]
            %
            imgOut = permute(data(:, :, :, :, t), [1 2 4 3]);  % [H, W, C, D]
        end

        function [pathStr, baseName, ext] = splitFilename(~, filename)
            % SPLITFILENAME - Wrapper around fileparts with lower-cased extension.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [pathStr, baseName, ext] = obj.splitFilename(filename)
            %
            % Input Arguments:
            %   - **filename** - [char] full path to decompose
            %
            % Output Arguments:
            %   - **pathStr** - [char] directory portion
            %   - **baseName** - [char] file stem without extension
            %   - **ext** - [char] lower-case extension including dot
            %
            % **Example 1** - decompose mixed-case filename:
            %
            %   .. code-block:: matlab
            %
            %      [p, n, e] = obj.splitFilename('/data/stack.TIF');
            %      % p == '/data', n == 'stack', e == '.tif'
            %
            [pathStr, baseName, ext] = fileparts(filename);
            ext = lower(ext);
        end

        function sliceNames = buildSliceNames(obj, baseName, pathStr, depth, ext, options, metadata)
            % BUILDSLICENAMES - Build per-slice output filenames for 2-D sequences.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      sliceNames = obj.buildSliceNames(baseName, pathStr, depth, ext, options, metadata)
            %
            % Respects the ``options.FilenameGenerator`` policy:
            % - ``'Use original filename'`` - derives names from ``metadata.sliceName``
            %   when available; falls back to sequential if unavailable
            % - ``'Use sequential filename'`` - generates numbered names (default)
            %
            % Input Arguments:
            %   - **baseName** - [char] stem used for sequential naming
            %   - **pathStr** - [char] destination directory
            %   - **depth** - [integer] number of slices (Z dimension)
            %   - **ext** - [char] extension with leading dot, e.g. ``'.tif'``
            %   - **options** - struct, must contain ``FilenameGenerator`` field;
            %     optionally ``FilenamePrefix`` (char, e.g. ``'Labels_'``) prepended to
            %     the stem when using original filenames
            %   - **metadata** - struct, may contain `` `.sliceName` `` (cell of char)
            %
            % Output Arguments:
            %   - **sliceNames** - [cell of char] {depth × 1} full output paths
            %
            % **Example 1** - sequential naming for 5 slices:
            %
            %   .. code-block:: matlab
            %
            %      opts.FilenameGenerator = 'Use sequential filename';
            %      names = obj.buildSliceNames('myStack', '/out', 5, '.png', opts, meta);
            %      % names == {'/out/myStack_01.png'; ... '/out/myStack_05.png'}
            %
            useOriginal = isfield(options, 'FilenameGenerator') && ...
                strcmp(options.FilenameGenerator, 'Use original filename') && ...
                isfield(metadata, 'sliceName') && ...
                numel(metadata.sliceName) == depth;

            prefix = '';
            if isfield(options, 'FilenamePrefix')
                prefix = options.FilenamePrefix;
            end

            sliceNames = cell(depth, 1);
            if useOriginal
                for z = 1:depth
                    [~, sn] = fileparts(metadata.sliceName{z});
                    sliceNames{z} = fullfile(pathStr, [prefix sn ext]);
                end
            else
                for z = 1:depth
                    sliceNames{z} = fullfile(pathStr, ...
                        utils.generateSequentialFilename(baseName, z, depth, ext));
                end
            end
        end

        function img2D = cropSliceToOriginalSize(~, img2D, sliceSize)
            % CROPSLICETOORIGINALSIZE - Crop a padded 2-D slice back to its original dimensions.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      img2D = obj.cropSliceToOriginalSize(img2D, sliceSize)
            %
            % Input Arguments:
            %   - **img2D** - [H, W] or [H, W, C] image slice (possibly padded)
            %   - **sliceSize** - [1x2] vector ``[origHeight, origWidth]``
            %
            % Output Arguments:
            %   - **img2D** - cropped to ``[origHeight, origWidth, :]``
            %
            if ~isempty(sliceSize)
                origH = min(sliceSize(1), size(img2D, 1));
                origW = min(sliceSize(2), size(img2D, 2));
                if origH < size(img2D, 1) || origW < size(img2D, 2)
                    img2D = img2D(1:origH, 1:origW, :);
                end
            end
        end

    end  % protected methods
end
