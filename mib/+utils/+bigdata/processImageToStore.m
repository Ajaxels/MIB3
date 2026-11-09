function outputPath = processImageToStore(image, blockFunction, outputPath, options)
% PROCESSIMAGETOSTORE - Process one pyramid level of a BigData image into a new OME-Zarr pyramid.
%
% Syntax:
%   .. code-block:: matlab
%
%       outputPath = utils.bigdata.processImageToStore(image, blockFunction, outputPath)
%       outputPath = utils.bigdata.processImageToStore(..., Level = 2, HaloYX = 6, ...)
%
% The engine behind the BigData mode of the Image tools: the source image of a
% BigData dataset is read-only, so a processed image goes to a new store.
% Level ``Level`` of ``image`` is read in bands of rows through
% ``io.savers.FilteredSliceProvider``, each band is passed to ``blockFunction``
% with a halo of ``HaloYX`` rows (and ``HaloZ`` slices for a 3D function), and
% the result is written by ``io.savers.Zarr3Saver.saveStreamResumable`` as a new
% pyramid whose level 0 is the processed level. Memory is about one band of
% rows, whatever the size of the image. The store is written only; opening it
% in a buffer is the caller's step.
%
% **Output geometry.** Level 0 of the new store has the size of level
% ``Level`` of the source. Its voxel size is the source voxel size times the
% level's scale factors, and its bounding box starts where the source box
% starts, so the result overlays the source. With ``Region`` level 0 is that
% box of the level, and its bounding box starts at the box, so it still
% overlays the source.
%
% **Pyramid settings.** ``SaverOptions`` fields override the settings derived
% from the source pyramid by ``io.savers.Zarr3Saver.optionsFromPyramid`` -
% the source chunk, sharding and downsampling strategy, and as many levels as
% the source has from ``Level`` down. Pass the answer of
% ``Zarr3Saver.reviewOptionsDialog`` here; this function opens no dialog.
%
% **Bands.** The band height is chosen so that one band of the widest working
% copy (8 bytes per element, a filter working in double) stays within
% ``BandBytes``, rounded by the saver to whole chunk (or shard) rows. Images
% whose whole slice fits are written slice by slice.
%
% **Resume.** With ``Resume = true`` an interrupted run on the same source,
% level, halo, settings and ``Fingerprint`` continues where it stopped (see
% ``saveStreamResumable``). The fingerprint is how the caller tells two runs of
% different parameters apart: ``func2str`` of an anonymous function does not
% show the values it captured, so include them in ``Fingerprint``.
%
% **Cancel.** With a valid ``ParentFigure`` the saver shows a cancelable
% progress dialog. A cancel returns ``[]`` and leaves the partial store, marked
% ``mibIncomplete`` and with its resume files, for ``Resume`` or for the caller
% to delete.
%
% Input Arguments:
%   - **image** - ``core.MibBigDataImage`` (any image with a ``pyramid`` that
%     honours ``getData`` ``pyramidLevel``)
%   - **blockFunction** - function handle ``out = f(block)``; the contract is in
%     ``io.savers.FilteredSliceProvider``. ``out`` must be ``uint8``, ``uint16``
%     or ``uint32``: MIB images are integer (a float source is converted at
%     loading), so a float result is refused with ``utils:bigdata:outputClass``
%     before anything is written
%   - **outputPath** - [char] path of the new store (``.zarr3`` or ``.zarr``); an
%     existing store there is replaced unless ``Resume`` is set. The source store
%     itself is refused
%   - **options.Level** - [double] 1-based pyramid level to process, default 1
%   - **options.ColChannel** - colour channels to read, default ``[]`` (all)
%   - **options.HaloYX** - [double] rows of halo, default 0
%   - **options.HaloZ** - [double] slices of halo, default 0 (2D function)
%   - **options.SaverOptions** - struct of ``Zarr3Saver`` options that override the derived ones
%   - **options.BandBytes** - [double] memory budget of one band, default 256 MB
%   - **options.Resume** - [logical] continue an interrupted run, default false
%   - **options.Fingerprint** - char or struct describing the processing parameters, default ``''``
%   - **options.ParentFigure** - figure for the progress dialog, default ``[]`` (no dialog)
%   - **options.Region** - ``[yFirst yLast xFirst xLast]`` box of the level to
%     process, default ``[]`` (the whole level); see ``io.savers.FilteredSliceProvider``
%   - **options.RegionMask** - logical mask of the box, default ``[]`` (all of it);
%     false pixels keep the source values
%   - **options.Pool** - process ``parallel.Pool`` whose workers process and write
%     the bands, default ``[]`` (on the client). The provider and
%     ``blockFunction`` are sent to every worker, see "Parallel writing" in
%     ``io.savers.FilteredSliceProvider``; the store equals the one written
%     without a pool
%
% Output Arguments:
%   - **outputPath** - [char] path of the written store, ``[]`` when cancelled
%
% **Example** - Gaussian of the full-resolution level into a new store:
%
%   .. code-block:: matlab
%
%      image = mibModel.I{mibModel.getActiveId()}.image;
%      sigma = 2;
%      outputPath = utils.bigdata.processImageToStore(image, @(block) imgaussfilt(block, sigma), ...
%          'C:\data\slide_gaussian.zarr3', HaloYX = ceil(3*sigma), ...
%          Fingerprint = sprintf('Gaussian sigma=%g', sigma), ParentFigure = mibModel.mibGUI);
%
% See also: io.savers.FilteredSliceProvider, io.savers.Zarr3Saver

% Updates
%

arguments
    image
    blockFunction (1,1) function_handle
    outputPath {mustBeTextScalar, mustBeNonzeroLengthText}
    options.Level (1,1) double {mustBeInteger, mustBePositive} = 1
    options.ColChannel = []
    options.HaloYX (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    options.HaloZ (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    options.SaverOptions (1,1) struct = struct()
    options.BandBytes (1,1) double {mustBePositive} = 256e6
    options.Resume (1,1) logical = false
    options.Fingerprint = ''
    options.ParentFigure = []
    options.Region double = []
    options.RegionMask = []
    options.Pool = []
end
outputPath = char(outputPath);

% writing over the source would delete the data being read
sourcePath = char(image.filename);
if utils.bigdata.isSameStorePath(outputPath, sourcePath)
    error('utils:bigdata:outputIsSource', ...
        'The output store is the source image itself (%s); choose another path.', outputPath);
end

provider = io.savers.FilteredSliceProvider(image, options.Level, options.ColChannel, blockFunction, ...
    HaloYX = options.HaloYX, HaloZ = options.HaloZ, Region = options.Region, RegionMask = options.RegionMask);
% MIB images are integer: a float store could be written but not opened as a dataset
if ~ismember(provider.DataClass, {'uint8', 'uint16', 'uint32'})
    error('utils:bigdata:outputClass', ...
        'The processing returns %s; convert the result to uint8, uint16 or uint32.', provider.DataClass);
end
scale = image.pyramid.levelScaleFactors(options.Level, :);   % [y x z]

% pyramid settings: the source's, as many levels as it has from Level down, then the caller's
saverOptions = io.savers.Zarr3Saver.optionsFromPyramid(image.pyramid);
saverOptions.Levels = max(1, size(image.pyramid.levelImageSizes, 1) - options.Level + 1);
overrideFields = fieldnames(options.SaverOptions);
for fieldIndex = 1:numel(overrideFields)
    saverOptions.(overrideFields{fieldIndex}) = options.SaverOptions.(overrideFields{fieldIndex});
end
saverOptions.silent = true;
saverOptions.Resume = options.Resume;
saverOptions.SourceFingerprint = struct('source', sourcePath, 'level', options.Level, ...
    'colChannel', options.ColChannel, 'haloYX', options.HaloYX, 'haloZ', options.HaloZ, ...
    'function', func2str(blockFunction), 'parameters', options.Fingerprint, ...
    'region', options.Region, 'regionMaskSum', sum(logical(options.RegionMask(:))));

% band height: one band of the widest working copy within BandBytes
height = provider.SliceSize(1);
width  = provider.SliceSize(2);
channels = max(provider.NumChannels, image.colors);
bandRows = floor(options.BandBytes / (8 * width * channels));
if bandRows >= height
    saverOptions.BandHeight = 0;    % whole slices
else
    saverOptions.BandHeight = max(1, bandRows);
end

% metadata: voxel size of the processed level, the source bounding box origin
pixSize = image.pixSize;
pixSize.y = pixSize.y * scale(1);
pixSize.x = pixSize.x * scale(2);
pixSize.z = pixSize.z * scale(3);
metadata = struct('pixSize', pixSize);
if ~isempty(image.boundingBox)
    sourceBox = image.boundingBox;   % [xmin xmax ymin ymax zmin zmax]
    regionOrigin = [0 0];            % level pixels before the region, [y x]
    if ~isempty(options.Region); regionOrigin = options.Region([1 3]) - 1; end
    xMin = sourceBox(1) + regionOrigin(2) * pixSize.x;
    yMin = sourceBox(3) + regionOrigin(1) * pixSize.y;
    metadata.boundingBox = [xMin, xMin + (width - 1) * pixSize.x, yMin, yMin + (height - 1) * pixSize.y, ...
        sourceBox(5), sourceBox(5) + (provider.NumSlices - 1) * pixSize.z];
end

saver = io.savers.Zarr3Saver(struct('ParentFigure', options.ParentFigure));
outputPath = saver.saveStreamResumable(provider, metadata, outputPath, saverOptions, options.Pool);
end
