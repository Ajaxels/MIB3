function [result, stopStage] = cropToBigData(obj, cropF, options)
% CROPTOBIGDATA - Crop a BigData dataset and write the result to a new Zarr pyramid.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.cropToBigData(cropF, options)
%       [result, stopStage] = obj.cropToBigData(cropF, options)
%
% Writes the full-resolution crop of the image as a new OME-Zarr v3 pyramid at
% ``options.outputPath`` and, when the dataset has a BigData model, the crop of
% the model to a sibling store whose name has a ``Labels_`` prefix:
%
%   - image  -> ``options.outputPath``          (e.g. ``crop.zarr3``)
%   - model  -> ``<dir>/Labels_<stem><ext>``    (e.g. ``Labels_crop.zarr3``)
%
% Neither is read whole: memory stays about one band of rows (per worker) for
% the image and one strip of 128 MB for the model, whatever the size of the crop.
%
% **Image.** Written by ``utils.bigdata.processImageToStore`` with an identity
% block function, ``Region`` = the crop box and ``SliceRange`` = the crop slices
% of level 1: ``io.savers.FilteredSliceProvider`` reads bands of rows and
% ``io.savers.Zarr3Saver.saveStreamResumable`` writes them, on the workers of
% ``options.Pool`` when given. The store keeps its position in the source (its
% bounding box starts at the crop origin). With ``options.Resume`` an
% interrupted crop to the same path, of the same box and settings, continues
% where it stopped.
%
% **Pyramid.** Without ``options.saverOptions`` the crop is written like its
% source (``Zarr3Saver.optionsFromPyramid``: chunk, level count, downsampling
% strategy, sharding), so level ``sN`` of the crop has the scale of level ``sN``
% of the source. Fields ``Levels``, ``ShardSize`` and ``LevelFactors`` missing
% from ``options.saverOptions`` (the answer of ``Zarr3Saver.reviewOptionsDialog``
% omits them for "auto", "no sharding" and a changed strategy) are passed as
% empty, so the values derived from the source do not come back.
%
% **Model.** Copied on the client, in strips (the pattern of
% ``controllers.Alignment.applyAlignmentBigData``):
%
%   - level 1: ``getData63('everything')`` of the source over a strip of rows x
%     the crop width x one Z chunk of the new store, written with
%     ``writePackedLevel``; the source read honours its level map, so a region
%     drawn at a coarser zoom is read upsampled. Strips of zeros are skipped
%     (the store's fill value)
%   - every coarser level from the level above it, by nearest decimation with
%     the index map of ``MibBigDataLabels.propagateRegion``
%     (``floor((0:t-1) * s / t) + 1``), in strips of target rows
%   - the level map is then set to level 1 everywhere (``markTiles``), and
%     ``selectionTiles`` to true, so every level reads directly
%
% The store is built from the pyramid of the written image store, so its levels
% equal the image's whatever the saver chose. Its layout follows the source
% (``setLayout(source.containerClass)``: 63 materials in uint8, 16383 objects in
% uint16), and ``objects3D``, the material names, colours, count and
% ``maxIndexUsed`` are carried over.
%
% **Time.** One time point: ``cropF`` must have ``dt == 1``
% (``core:MibDataset:cropToBigDataTime`` otherwise), at any ``t1``.
%
% **Cancel.** With ``options.showWaitbar`` and a valid ``options.UIFigure``:
%
%   - during the image, the saver's dialog is cancelable per band; the partial
%     store is left marked ``mibIncomplete`` with its resume files, for
%     ``Resume`` or for the caller to delete (``stopStage = 'image'``)
%   - during the model, per strip; the model store is removed, the complete
%     image store is left (``stopStage = 'model'``)
%
% A failed band raises the saver's error and leaves the image store resumable,
% as a cancel does. An error while copying the model removes the model store and
% is raised again.
%
% Input Arguments:
%   - **cropF** - a vector ``[x1, y1, dx, dy, z1, dz, t1, dt]`` in pixels
%
%     - *x1,* *y1* - top-left corner of the crop region
%     - *dx,* *dy* - width and height of the crop region
%     - *z1,* *dz* - first slice index and number of slices
%     - *t1,* *dt* - first time point and number of time points (1)
%     - when ``numel(cropF)`` < 7, *t1* and *dt* default to ``[1, 1]``
%
%   - **options** - structure with additional parameters
%
%     - ``.outputPath`` - [char] path to the destination zarr folder (required);
%       an existing store there is replaced unless ``.Resume`` is set
%     - ``.showWaitbar`` - logical, show progress dialogs (default: **true**)
%     - ``.UIFigure`` - handle to the parent UIFigure for the dialogs
%     - ``.saverOptions`` - *(optional)* ``Zarr3Saver`` options for the image
%       store; default ``Zarr3Saver.optionsFromPyramid(obj.image.pyramid)``
%     - ``.Pool`` - *(optional)* process ``parallel.Pool`` whose workers read and
%       write the image bands, default ``[]`` (the client)
%     - ``.Resume`` - *(optional)* logical, continue an interrupted crop, default false
%     - ``.BandBytes`` - *(optional)* memory budget of one image band, default 256 MB
%
% Output Arguments:
%   - **result** - **1** on success, **0** on cancel
%   - **stopStage** - ``''`` on success, ``'image'`` or ``'model'``: where a
%     cancel stopped the crop
%
% Usage:
%   **Example**
%
%   .. code-block:: matlab
%
%
%     opts.outputPath  = 'C:\data\crop.zarr3';
%     opts.showWaitbar = true;
%     opts.UIFigure    = obj.view.gui;
%     opts.Pool        = gcp('nocreate');
%     result = obj.mibModel.I{id}.cropToBigData(crop_factor, opts);
%

% Updates
% 2026-06-26 created
% 2026-11-19 streamed image (pool, resume) and strip-wise model copy

result = 0;
stopStage = '';

if nargin < 3; options = struct(); end
if ~isfield(options, 'showWaitbar'); options.showWaitbar = true; end
if ~isfield(options, 'UIFigure');    options.UIFigure    = [];   end
if ~isfield(options, 'Pool');        options.Pool        = [];   end
if ~isfield(options, 'Resume');      options.Resume      = false; end
if ~isfield(options, 'BandBytes');   options.BandBytes   = 256e6; end
if ~isfield(options, 'outputPath') || isempty(options.outputPath)
    error('core:MibDataset:cropToBigData', 'options.outputPath is required');
end
outputPath = char(options.outputPath);

if numel(cropF) < 7; cropF(7:8) = [1, 1]; end
x1 = cropF(1);  dx = cropF(3);
y1 = cropF(2);  dy = cropF(4);
z1 = cropF(5);  dz = cropF(6);
t1 = cropF(7);  dt = cropF(8);
if dt ~= 1
    error('core:MibDataset:cropToBigDataTime', ...
        'A crop to BigData writes one time point; %d time points (%d-%d) were requested.', dt, t1, t1 + dt - 1);
end

parentFigure = [];
if options.showWaitbar && ~isempty(options.UIFigure) && all(isvalid(options.UIFigure))
    parentFigure = options.UIFigure;
end

% =========================================================================
%  1. The image: streamed from the source into the new pyramid
% =========================================================================
if isfield(options, 'saverOptions') && ~isempty(options.saverOptions)
    saverOptions = options.saverOptions;
else
    saverOptions = io.savers.Zarr3Saver.optionsFromPyramid(obj.image.pyramid);
end
% absent means "auto", "no sharding", "the strategy's own levels": say so
% explicitly, or processImageToStore puts back the values derived from the source
for fieldName = {'Levels', 'ShardSize', 'LevelFactors'}
    if ~isfield(saverOptions, fieldName{1}); saverOptions.(fieldName{1}) = []; end
end

writtenPath = utils.bigdata.processImageToStore(obj.image, @(block) block, outputPath, ...
    Level = 1, Region = [y1, y1 + dy - 1, x1, x1 + dx - 1], SliceRange = [z1, z1 + dz - 1], ...
    TimePoint = t1, SaverOptions = saverOptions, Resume = options.Resume, Fingerprint = 'crop', ...
    ParentFigure = parentFigure, BandBytes = options.BandBytes, Pool = options.Pool);
if isempty(writtenPath)
    stopStage = 'image';
    return;
end

% =========================================================================
%  2. The model: copied in strips into a store with the image's levels
% =========================================================================
if ~(isa(obj.labels, 'core.MibBigDataLabels') && obj.labels.exists)
    result = 1;
    return;
end
source = obj.labels;
[parentDir, stem, ext] = fileparts(outputPath);
modelStorePath = fullfile(parentDir, ['Labels_' stem ext]);

loaderOptions = struct('datasetMode', 'BigData');
loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
[~, croppedPyramid] = loader.loadMetadata({outputPath}, loaderOptions);

target = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
target.setLayout(source.containerClass);
target.createStore([dy, dx, dz], modelStorePath, croppedPyramid);

wb = [];
if ~isempty(parentFigure)
    wb = uiprogressdlg(parentFigure, 'Title', 'Crop to BigData', 'Value', 0, 'Cancelable', 'on', ...
        'Message', sprintf('Copying the model\nPlease wait...'));
end
try
    copied = localCopyModel(source, target, [y1 x1 z1], [dy dx dz], wb);
catch copyError
    localRemoveStore(target, modelStorePath);
    if ~isempty(wb); delete(wb); end
    rethrow(copyError);
end
if ~copied
    localRemoveStore(target, modelStorePath);
    delete(wb);
    stopStage = 'model';
    return;
end

% every level was written, so each reads directly
target.markTiles([1 dy], [1 dx], [1 dz], 1);
target.selectionTiles(:) = true;      % the strips carry the selection bits too
target.objects3D      = source.objects3D;
target.materialNames  = source.materialNames;
target.materialColors = source.materialColors;
target.materialsCount = source.materialsCount;
target.maxIndexUsed   = source.maxIndexUsed;
target.writeMaterialMetadata();
target.closeStore();                  % persists the level map

if ~isempty(wb); delete(wb); end
result = 1;
end

% =====================================================================
function copied = localCopyModel(source, target, cropOrigin, cropSize, wb)
% Level 1 from the source crop box, then each coarser level from the one above.
% Returns false when the dialog was cancelled.
copied = false;
stripBytes = 2^27;                                       % 128 MB per strip
bytesPerVoxel = numel(typecast(zeros(1, target.containerClass), 'uint8'));   % 1, 2 or 4
levelSizes = target.modelLevelSizes;                     % [y x z] per level
totalVoxels = sum(prod(levelSizes, 2));
voxelsDone = 0;

% --- level 1: the crop box of the source, full resolution -----------------
chunkShape = double(target.modelArrays{1}.info().chunkShape);   % [y x z]
planesPerStrip = min(chunkShape(3), cropSize(3));
rowsPerStrip = max(chunkShape(1), ...
    floor(stripBytes / (cropSize(2) * planesPerStrip * bytesPerVoxel) / chunkShape(1)) * chunkShape(1));
for firstPlane = 1:planesPerStrip:cropSize(3)
    planes = [firstPlane, min(firstPlane + planesPerStrip - 1, cropSize(3))];
    for firstRow = 1:rowsPerStrip:cropSize(1)
        if ~isempty(wb) && wb.CancelRequested; return; end
        rows = [firstRow, min(firstRow + rowsPerStrip - 1, cropSize(1))];
        readOptions = struct('pyramidLevel', 1, ...
            'y', cropOrigin(1) - 1 + rows, ...
            'x', cropOrigin(2) - 1 + [1, cropSize(2)], ...
            'z', cropOrigin(3) - 1 + planes);
        block = source.getData63('everything', 3, [], readOptions);
        block = reshape(block, diff(rows) + 1, cropSize(2), diff(planes) + 1);
        if any(block(:))
            target.writePackedLevel(1, cast(block, target.containerClass), rows, [1 cropSize(2)], planes);
        end
        voxelsDone = voxelsDone + numel(block);
        if ~isempty(wb); wb.Value = voxelsDone / totalVoxels; end
    end
end

% --- coarser levels: nearest decimation of the level above ----------------
for level = 2:size(levelSizes, 1)
    sourceSize = levelSizes(level - 1, :);
    targetSize = levelSizes(level, :);
    yMap = min(sourceSize(1), max(1, floor((0:targetSize(1)-1) * sourceSize(1) / targetSize(1)) + 1));
    xMap = min(sourceSize(2), max(1, floor((0:targetSize(2)-1) * sourceSize(2) / targetSize(2)) + 1));
    zMap = min(sourceSize(3), max(1, floor((0:targetSize(3)-1) * sourceSize(3) / targetSize(3)) + 1));
    chunkShape = double(target.modelArrays{level}.info().chunkShape);
    planesPerStrip = min(chunkShape(3), targetSize(3));
    % source voxels read per target row of a strip: the rows and planes it decimates
    sourceRowsPerRow = sourceSize(1) / targetSize(1);
    sourcePlanes = planesPerStrip * sourceSize(3) / targetSize(3);
    rowsPerStrip = max(chunkShape(1), floor(stripBytes / ...
        (sourceSize(2) * sourcePlanes * sourceRowsPerRow * bytesPerVoxel) / chunkShape(1)) * chunkShape(1));
    for firstPlane = 1:planesPerStrip:targetSize(3)
        planes = [firstPlane, min(firstPlane + planesPerStrip - 1, targetSize(3))];
        sourceZ = zMap(planes(1):planes(2));
        for firstRow = 1:rowsPerStrip:targetSize(1)
            if ~isempty(wb) && wb.CancelRequested; return; end
            rows = [firstRow, min(firstRow + rowsPerStrip - 1, targetSize(1))];
            sourceY = yMap(rows(1):rows(2));
            strip = target.readPackedLevel(level - 1, [sourceY(1) sourceY(end)], [1 sourceSize(2)], ...
                [sourceZ(1) sourceZ(end)]);
            block = strip(sourceY - sourceY(1) + 1, xMap, sourceZ - sourceZ(1) + 1);
            if any(block(:))
                target.writePackedLevel(level, block, rows, [1 targetSize(2)], planes);
            end
            voxelsDone = voxelsDone + numel(block);
            if ~isempty(wb); wb.Value = min(1, voxelsDone / totalVoxels); end
        end
    end
end
copied = true;
end

% =====================================================================
function localRemoveStore(labels, storePath)
% Close and delete the model store this crop created, with its level map
try labels.closeStore(); catch; end %#ok<CTCH>
if isfolder(storePath); rmdir(storePath, 's'); end
levelMapPath = core.MibBigDataLabels.levelMapPathFor(storePath);
if isfile(levelMapPath); delete(levelMapPath); end
end
