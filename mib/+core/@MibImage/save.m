function fnOut = save(obj, filename, options)
% SAVE - Save image data from a MibImage object to a file.
%
% Syntax:
%   .. code-block:: matlab
%
%       fnOut = obj.save(filename, options)
%
% This is the LOWEST-LEVEL save entry point.  It works completely
% standalone: no MibDataset or MibModel is required.  Useful for
% scripted pipelines that create or modify a MibImage object directly
% without loading it through the full MIB application.
%
% **The method:**
%
%   1. Derives the output format from ``options.Format`` (or from the file
%      extension if ``options.Format`` is absent)
%   2. Assembles a metadata struct from the object's own properties
%   3. Calls ``io.SaverFactory.create(format)`` to get the right saver
%   4. Delegates the actual I/O to ``saver.save(data, metadata, filename, options)``
%
% NOTE ON pixSize:
% MibImage does NOT store pixel/voxel size - that information lives at
% the MibDataset level.  If you need physically correct metadata in the
% output file (e.g. for Amira, NRRD, or OME-TIFF), supply
% options.pixSize explicitly:
% opts.pixSize = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
% When options.pixSize is absent a default of 1×1×1 µm is used.
%
% Input Arguments:
%   - **obj** - ``MibImage`` instance
%   - **filename** - (char) full output path including extension, e.g.
%     ``'/data/out/myStack.tif'`` or ``'C:\data\output.h5'``.
%     The directory must already exist.
%     When filename has no path component the current directory is used.
%   - **options** - *(optional)* struct with saving options:
%
%     - ``.Format`` - (char) format descriptor as listed in
%       ``io.SaverFactory.getFormats('image')``, e.g.
%       ``'TIF format uncompressed (*.tif)'``.
%       When absent the format is inferred from the file extension.
%     - ``.Saving3DPolicy`` - (char) ``'3D stack'`` | ``'2D sequence'``, default ``'3D stack'``
%     - ``.showWaitbar`` - (logical) display progress bar, default ``true``
%     - ``.silent`` - (logical) suppress all dialogs, default ``false``
%     - ``.overwrite`` - (logical) silently overwrite existing files, default ``true``
%     - ``.Compression`` - (char) ``'none'`` | ``'lzw'`` | ``'packbits'`` (for TIF);
%       ``'lossy'`` | ``'lossless'`` (for JPG)
%     - ``.Quality`` - (double 0-100) JPEG quality, default ``90``
%     - ``.FilenameGenerator`` - (char) ``'Use original filename'`` | ``'Use sequential filename'``
%     - ``.pixSize`` - (struct) voxel size ``{.x .y .z .t .units .tunits}``;
%       injected by ``MibDataset.save()`` automatically when calling through that layer
%     - ``.ParentFigure`` - handle to the main MIB application window; passed to
%       ``io.SaverFactory.create()`` so the saver and any helper functions can create
%       ``uiprogressdlg`` dialogs properly parented to the GUI.
%       Injected by ``MibModel.saveImage()``; omit for standalone use.
%     - ``.mibPath`` - (char) path to MIB installation directory; forwarded to the saver
%       for resource/icon lookup.
%       Injected by ``MibModel.saveImage()``; omit for standalone use.
%
% Output Arguments:
%   - **fnOut** - (char or cell of char) path(s) of saved file(s).
%     Returns ``[]`` on failure or cancellation.
%
% Usage:
%   **Example 1** - Simplest case: save existing MibImage to TIF
%
%   .. code-block:: matlab
%
%
%       img = core.MibImage(uint8(rand(256,256,50,1,1)*255));
%       img.filename = '/data/input.tif';
%
%       % get the list of possible formats for images: "formats = io.SaverFactory.getFormats('image')"
%       opts.Format         = 'TIF format uncompressed (*.tif)';
%       opts.Saving3DPolicy = '3D stack';
%       opts.showWaitbar    = false;
%       opts.silent         = true;
%       opts.overwrite      = true;
%       opts.pixSize        = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
%
%       fnOut = img.save('/output/stack.tif', opts);
%       fprintf('Saved to: %s\n', fnOut);
%
%   **Example 2** - Save as LZW-compressed TIF, 2D sequence
%
%   .. code-block:: matlab
%
%
%       opts.Format            = 'TIF format LZW compression (*.tif)';
%       opts.Saving3DPolicy    = '2D sequence';
%       opts.FilenameGenerator = 'Use sequential filename';
%       opts.showWaitbar       = true;
%       opts.silent            = true;
%       opts.overwrite         = true;
%       opts.pixSize           = struct('x',0.1,'y',0.1,'z',0.5,'units','um','t',1,'tunits','s');
%
%       fnOut = img.save('/output/slice.tif', opts);
%       % Produces: /output/slice_001.tif, /output/slice_002.tif, ...
%
%   **Example 3** - Save as PNG without explicit Format (inferred from extension)
%
%   .. code-block:: matlab
%
%
%       opts.showWaitbar = false;
%       opts.silent      = true;
%       opts.overwrite   = true;
%       fnOut = img.save('/output/slice.png', opts);
%
%   **Example 4** - Save 16-bit EM data as HDF5 with voxel metadata
%
%   .. code-block:: matlab
%
%
%       imgEM = core.MibImage(uint16(rand(1024,1024,200,1,1)*65535));
%       imgEM.filename = 'em_volume.h5';
%
%       opts.Format      = 'Hierarchical Data Format (*.h5)';
%       opts.showWaitbar = true;
%       opts.silent      = true;
%       opts.overwrite   = true;
%       opts.pixSize     = struct('x',0.004,'y',0.004,'z',0.03,'units','um','t',1,'tunits','s');
%
%       fnOut = imgEM.save('/output/em_volume.h5', opts);
%
%   **Example 5** - Save from inside a controller with access to the MIB GUI
%
%   .. code-block:: matlab
%
%
%       opts.Format         = 'Amira Mesh binary (*.am)';
%       opts.Saving3DPolicy = '3D stack';
%       opts.showWaitbar    = true;
%       opts.silent         = true;
%       opts.overwrite      = true;
%       opts.pixSize        = struct('x',0.065,'y',0.065,'z',0.2,'units','um','t',1,'tunits','s');
%       opts.ParentFigure   = obj.mibModel.mibGUI;   % enables uiprogressdlg
%       opts.mibPath        = obj.mibModel.mibPath;  % enables icon lookup
%
%       fnOut = img.save('/output/stack.am', opts);
%
% See also:
%   core.MibLabels.save, core.MibDataset.saveImage, models.MibModel.saveImage, io.SaverFactory, io.savers.BaseSaver
%

fnOut = [];

if nargin < 3; options = struct(); end
if nargin < 2 || isempty(filename)
    error('MibImage:save:missingFilename', ...
        'A filename must be provided to MibImage.save().');
end

% --- apply defaults ---
if ~isfield(options,'showWaitbar');    options.showWaitbar    = true;    end
if ~isfield(options,'silent');         options.silent         = false;   end
if ~isfield(options,'overwrite');      options.overwrite      = true;    end
if ~isfield(options,'Saving3DPolicy'); options.Saving3DPolicy = '3D stack'; end

% --- ensure filename has a full path ---
[pathStr, ~, ext] = fileparts(filename);
if isempty(pathStr)
    filename = fullfile(pwd, filename);
    [pathStr, ~, ext] = fileparts(filename);
end
if exist(pathStr,'dir') ~= 7; mkdir(pathStr); end
ext = lower(ext);

% fileparts('file.ome.tiff') returns '.tiff'; detect compound extension
if strcmp(ext, '.tiff') && endsWith(lower(filename), '.ome.tiff')
    ext = '.ome.tiff';
end

% --- determine output format ---
if ~isfield(options,'Format') || isempty(options.Format)
    options.Format = io.SaverFactory.getDefaultFormat('image', ext);
end

% --- default pixSize when not provided ---
if ~isfield(options,'pixSize') || isempty(options.pixSize)
    options.pixSize = struct('x',1,'y',1,'z',1,'t',1,'units','um','tunits','s');
end

% --- pyramid level selection (Virtual / BigData only) ---------------------
% A pyramidal image can be exported at a chosen resolution level. The slices
% are streamed from disk one at a time (see below), so the full volume is never
% loaded. The selected level's voxel size is pixSize scaled by the level's XY
% scale factor (the pyramid downsamples XY only, so pixSize.z is unchanged); the
% physical bounding box is identical across levels and stays as-is.
isPyramidal = isa(obj, 'core.MibVirtualImage') && ~isempty(obj.pyramid.levelNames);
exportLevel = 1;
if isfield(options, 'PyramidLevel') && ~isempty(options.PyramidLevel)
    exportLevel = round(options.PyramidLevel);
end
if isPyramidal
    nLevels = numel(obj.pyramid.levelNames);
    exportLevel = max(1, min(exportLevel, nLevels));
    levelScale = obj.pyramid.levelScaleFactors(exportLevel, :);   % [yScale xScale zScale]
    options.pixSize.y = options.pixSize.y * levelScale(1);
    options.pixSize.x = options.pixSize.x * levelScale(2);
    options.pixSize.z = options.pixSize.z * levelScale(3);
end

% Show indeterminate progress dialog immediately so the user sees feedback
% while the (potentially slow) data-extraction step runs.
earlyWb = [];
if options.showWaitbar && isfield(options,'ParentFigure') && ~isempty(options.ParentFigure)
    try
        if isvalid(options.ParentFigure)
            earlyWb = uiprogressdlg(options.ParentFigure, ...
                'Title',         'Saving image', ...
                'Message',       'Preparing data...', ...
                'Indeterminate', 'on', ...
                'Cancelable',    'on');
            options.waitbarHandle = earlyWb;
        end
    catch
    end
end

% --- assemble metadata from object properties ---
metadata.filename   = obj.filename;
metadata.colorType  = obj.colorType;
metadata.lutColors  = obj.lutColors;
metadata.dataClass  = obj.dataClass;
metadata.maxInt     = obj.maxInt;
metadata.pixSize    = options.pixSize;

% per-slice source filenames
if ~isempty(obj.sliceName)
    metadata.sliceName = obj.sliceName;
else
    metadata.sliceName = {};
end

% per-slice original dimensions
if ~isempty(obj.sliceSize)
    metadata.sliceSize = obj.sliceSize;
else
    metadata.sliceSize = [];
end

% resolution for PNG/TIF Resolution tags - pixels per inch
resolution = utils.calculateResolution(options.pixSize);
metadata.xResolution = resolution(1);
metadata.yResolution = resolution(2);

% Reconstruct the full ImageDescription tag (BoundingBox + action log)
% and expose the bounding box as a separate numeric field so that savers
% that need it (AmiraMesh, HDF5, NRRD, …) do not have to re-parse the string.
exportBoundingBox = obj.boundingBox;
% BioFormats-backed BigData carries an EMPTY boundingBox (its voxel size lives only
% in the pyramid), so buildImageDescription would omit the BoundingBox and the
% reloaded dataset would default to voxel 1. Synthesize the physical box from the
% level-scaled pixSize + exported level dimensions so the voxel size round-trips.
if isPyramidal && (isempty(exportBoundingBox) || numel(exportBoundingBox) ~= 6)
    lvlSize = obj.pyramid.levelImageSizes(exportLevel, :);   % [Y X Z]
    exportBoundingBox = [0, max(lvlSize(2) - 1, 0) * options.pixSize.x, ...
                         0, max(lvlSize(1) - 1, 0) * options.pixSize.y, ...
                         0, max(lvlSize(3) - 1, 0) * options.pixSize.z];
end
metadata.imageDescription = core.MibImage.buildImageDescription(exportBoundingBox, obj.actionLog);
metadata.boundingBox      = exportBoundingBox;

% colormap for indexed images
if isfield(obj,'colormap') && ~isempty(obj.colormap)
    metadata.colormap = obj.colormap;
end

% --- dispatch to appropriate saver ---
saver = io.SaverFactory.create(options.Format, options);

if isPyramidal
    % Stream the selected pyramid level slice-by-slice - memory stays bounded
    % to one slice (savers that haven't migrated to true streaming fall back to
    % gathering this single level inside BaseSaver.saveStream).
    numSlices = obj.pyramid.levelImageSizes(exportLevel, 3);
    zScale    = obj.pyramid.levelScaleFactors(exportLevel, 3);
    provider  = io.savers.MibImageSliceProvider(obj, 'image', exportLevel, [], numSlices, obj.time, zScale);
    fnOut = saver.saveStream(provider, metadata, filename, options);
else
    % --- get full 5-D data [H, W, D, C, T] ---
    data = obj.getData('image', 3, []);

    % Check if user cancelled during data extraction
    if ~isempty(earlyWb) && isvalid(earlyWb) && earlyWb.CancelRequested
        delete(earlyWb);
        fnOut = [];
        return;
    end

    fnOut = saver.save(data, metadata, filename, options);
end
end

