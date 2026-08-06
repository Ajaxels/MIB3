function fnOut = fuseToFiles(layout, canvas, outputPath, options)
% FUSETOFILES - Fuse tiles straight into standard image files (TIF/PNG/AM).
%
% Syntax:
%   .. code-block:: matlab
%
%      fnOut = utils.stitch.fuseToFiles(layout, canvas, outputPath)
%      fnOut = utils.stitch.fuseToFiles(layout, canvas, outputPath, options)
%
% Third fusion path beside :func:`utils.stitch.fuseInMemory` (a resident MIB
% dataset) and :func:`utils.stitch.fuseStreaming` (an OME-Zarr BigData store):
% writes the mosaic as ordinary image files, so it can be handed to software
% that reads nothing else.
%
% A :class:`io.savers.StitchSliceProvider` is fed to the saver's
% ``saveStream``, which is the same slice-by-slice contract the zarr path uses -
% so for the 2-D sequence formats (TIF, PNG, Amira file sequence) only ONE
% output slice is ever resident, whatever the mosaic's depth. ``Amira Mesh
% binary`` writes a single 3-D file and has no streaming writer, so
% ``io.savers.BaseSaver.saveStream`` gathers the volume first: that format needs
% the whole mosaic in RAM, exactly as ``In memory`` does.
%
% Per-slice filenames are the saver's own (``utils.generateSequentialFilename``
% via ``io.savers.BaseSaver.buildSliceNames``): ``<stem>_001.tif`` ...
% ``<stem>_NNN.tif``, zero-padded to the digit count the slice total needs, so
% the files sort in acquisition order. No naming or format dialog is raised -
% every choice arrives through ``options``.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout.
%   - **canvas** - [struct] from :func:`utils.stitch.planCanvas`.
%   - **outputPath** - [char] full destination path INCLUDING the extension; for
%     a 2-D sequence it is the stem the numbered files are derived from.
%   - **options** *(optional)* - struct with fields:
%
%     - ``.Format`` - [char] ``io.SaverFactory`` format string
%       (default: ``'TIF format uncompressed (*.tif)'``)
%     - ``.Saving3DPolicy`` - [char] ``'2D sequence'`` (default) | ``'3D stack'``
%     - ``.blendMode`` - [char] ``'Feather'`` (default) | ``'Average'`` | ``'Max'`` | ``'Min'`` | ``'Overwrite'``
%     - ``.background`` - [double] background fill value (default: ``0``)
%     - ``.marginPx`` - [double] feather margin (default: derived from tile size)
%     - ``.correction`` - [struct] intensity correction from
%       :func:`utils.stitch.estimateIntensityCorrection` (default: ``[]``)
%     - ``.cacheSizeBytes`` - [double] LRU tile-cache budget (default: ``2*1024^3``)
%     - ``.readerFcn`` - [function_handle] reuse an existing tile reader (optional)
%     - ``.pixSize`` - [struct] override ``canvas.pixSize`` for the file metadata
%     - ``.filename`` - [char] source name recorded in the metadata (default: ``outputPath``)
%     - ``.showWaitbar`` - [logical] show progress (default: ``false``)
%     - ``.parentFigure`` - [handle] progress-dialog parent (default: ``[]``)
%     - ``.mibPath`` - [char] MIB installation directory, for saver dialogs
%
% Output Arguments:
%   - **fnOut** - [char] the single written file for a 3-D stack, or a FLAT
%     [cell of char] of the per-slice paths for a 2-D sequence; ``[]`` when the
%     saver declined the job (e.g. more colour channels than the format holds).
%
% **Example** - write a mosaic as a numbered TIF sequence:
%
%   .. code-block:: matlab
%
%      opts.Format = 'TIF format uncompressed (*.tif)';
%      opts.Saving3DPolicy = '2D sequence';
%      opts.blendMode = 'Overwrite';
%      fnOut = utils.stitch.fuseToFiles(layout, canvas, 'C:\out\mosaic.tif', opts);
%      % -> C:\out\mosaic_01.tif ... C:\out\mosaic_NN.tif
%
% See also: utils.stitch.fuseInMemory, utils.stitch.fuseStreaming,
% io.savers.StitchSliceProvider, io.SaverFactory

if nargin < 4; options = struct(); end
if ~isfield(options, 'Format');         options.Format = 'TIF format uncompressed (*.tif)'; end
if ~isfield(options, 'Saving3DPolicy'); options.Saving3DPolicy = '2D sequence'; end
if ~isfield(options, 'blendMode');      options.blendMode = 'Feather'; end
if ~isfield(options, 'background');     options.background = 0; end
if ~isfield(options, 'cacheSizeBytes'); options.cacheSizeBytes = 2 * 1024^3; end
if ~isfield(options, 'correction');     options.correction = []; end
if ~isfield(options, 'showWaitbar');    options.showWaitbar = false; end
if ~isfield(options, 'parentFigure');   options.parentFigure = []; end
if ~isfield(options, 'mibPath');        options.mibPath = ''; end

if isfield(options, 'pixSize') && ~isempty(options.pixSize)
    pixSize = options.pixSize;
else
    pixSize = canvas.pixSize;
end

% --- the mosaic, as a memory-bounded stream of output slices -----------------
providerOptions = struct('blendMode', options.blendMode, ...
    'background', options.background, 'cacheSizeBytes', options.cacheSizeBytes, ...
    'correction', options.correction);
if isfield(options, 'marginPx');  providerOptions.marginPx  = options.marginPx; end
if isfield(options, 'readerFcn'); providerOptions.readerFcn = options.readerFcn; end

provider = io.savers.StitchSliceProvider(layout, canvas, providerOptions);

% --- file metadata (mirrors core.MibImage.save, which is what makes the voxel
% size survive: TIF/PNG carry it as the XResolution tag, every format carries
% the BoundingBox in its ImageDescription, and Amira additionally writes the
% pixSize struct into its own header) -----------------------------------------
numColors = canvas.size(4);

metadata = struct();
if isfield(options, 'filename') && ~isempty(options.filename)
    metadata.filename = options.filename;
else
    metadata.filename = outputPath;
end
if numColors == 1
    metadata.colorType = 'grayscale';
else
    metadata.colorType = 'multichannel';
end
metadata.lutColors = utils.defaults.generateLUT(numColors);
metadata.dataClass = canvas.dataClass;
switch canvas.dataClass
    case {'single', 'double'}
        metadata.maxInt = realmax(canvas.dataClass);
    otherwise
        metadata.maxInt = double(intmax(canvas.dataClass));
end
metadata.pixSize = fillPixSizeDefaults(pixSize);

% Empty on purpose: the mosaic's slices have no source file of their own, and a
% sliceName list is what would make the savers offer "Use original filename".
metadata.sliceName = {};
metadata.sliceSize = [];

resolution = utils.calculateResolution(metadata.pixSize);
metadata.xResolution = resolution(1);
metadata.yResolution = resolution(2);

metadata.boundingBox = canvas.boundingBox;
metadata.imageDescription = core.MibImage.buildImageDescription(metadata.boundingBox, {});

% --- hand it to the saver ----------------------------------------------------
saverConstructorOptions = struct('ParentFigure', options.parentFigure, ...
    'mibPath', options.mibPath);
saver = io.SaverFactory.create(options.Format, saverConstructorOptions);

saveOptions = struct();
saveOptions.Format            = options.Format;
saveOptions.Saving3DPolicy    = options.Saving3DPolicy;
saveOptions.layerType         = 'image';
% Both fields also act as "the caller has decided": the savers gate their naming
% / 3D-policy dialogs on them, so passing them is what keeps the export silent.
saveOptions.FilenameGenerator = 'Use sequential filename';
saveOptions.silent            = true;
saveOptions.overwrite         = true;
saveOptions.showWaitbar       = options.showWaitbar;
saveOptions.ParentFigure      = options.parentFigure;
saveOptions.mibPath           = options.mibPath;
saveOptions.pixSize           = metadata.pixSize;

fnOut = saver.saveStream(provider, metadata, outputPath, saveOptions);

% The savers disagree on the shape of a sequence's return - PngSaver hands back
% a flat cell of paths, TiffSaver one cell per time point each holding its own
% cell of slices - so flatten before it reaches a caller. Without this the
% "one file per slice" contract silently means "one cell per time point" for
% exactly one of the four formats.
if ~ischar(fnOut)
    fnOut = flattenFileList(fnOut);
end
end

% =========================================================================
function flatList = flattenFileList(fileList)
% FLATTENFILELIST - Collapse a saver's nested return value into a cell of paths.
if ischar(fileList) || isstring(fileList)
    flatList = {char(fileList)};
    return;
end
flatList = {};
for entryIdx = 1:numel(fileList)
    flatList = [flatList; flattenFileList(fileList{entryIdx})]; %#ok<AGROW>
end
end

% =========================================================================
function pixSize = fillPixSizeDefaults(pixSize)
% FILLPIXSIZEDEFAULTS - Complete a canvas pixSize into the full MIB struct.
% planCanvas only guarantees .x/.y/.z; utils.calculateResolution needs .units and
% the Amira header writes .t/.tunits. Defaulting here rather than at each reader
% keeps a partially-filled struct from silently reaching a file.
if ~isstruct(pixSize) || isempty(pixSize)
    pixSize = struct();
end
if ~isfield(pixSize, 'x') || isempty(pixSize.x); pixSize.x = 1; end
if ~isfield(pixSize, 'y') || isempty(pixSize.y); pixSize.y = 1; end
if ~isfield(pixSize, 'z') || isempty(pixSize.z); pixSize.z = 1; end
if ~isfield(pixSize, 'units') || isempty(pixSize.units); pixSize.units = 'um'; end
if ~isfield(pixSize, 't') || isempty(pixSize.t); pixSize.t = 1; end
if ~isfield(pixSize, 'tunits') || isempty(pixSize.tunits); pixSize.tunits = 's'; end
end
