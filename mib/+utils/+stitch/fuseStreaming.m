function fuseStreaming(layout, canvas, outputZarrPath, options)
% FUSESTREAMING - Fuse tiles straight to an OME-Zarr v3 store (out-of-core).
%
% Syntax:
%   .. code-block:: matlab
%
%      utils.stitch.fuseStreaming(layout, canvas, outputZarrPath)
%      utils.stitch.fuseStreaming(layout, canvas, outputZarrPath, options)
%
% Primary streaming fusion path. When a single output XY slice fits in
% ``options.maxSliceBytes`` (the common case), a :class:`io.savers.StitchSliceProvider`
% is fed to :meth:`io.savers.Zarr3Saver.saveStream`, which writes level 0 and the
% full downsampled pyramid with sharding - the whole mosaic is never resident.
% When even one slice is too large, a chunk-wise fallback creates the zarr array
% directly (mirroring ``Zarr3Saver`` chunk/shard defaults), iterates output
% chunks, loads only the intersecting tiles (bounded cache), blends, and writes
% each block with :meth:`io.zarr.Array.write`; a manual block-downsample pass
% then adds pyramid levels. Either way :meth:`io.savers.Zarr3Saver.patchMetadata`
% stamps the physical bounding box and pixel size so the store reopens as a MIB
% BigData dataset.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout.
%   - **canvas** - [struct] from :func:`utils.stitch.planCanvas`.
%   - **outputZarrPath** - [char] destination ``.zarr3`` folder (overwritten).
%   - **options** *(optional)* - struct with fields:
%
%     - ``.blendMode`` - [char] ``'Feather'`` (default) | ``'Average'`` | ``'Max'`` | ``'Min'`` | ``'Overwrite'``
%     - ``.background`` - [double] background fill value (default: ``0``)
%     - ``.marginPx`` - [double] feather margin (default: derived from tile size)
%     - ``.maxSliceBytes`` - [double] slice-fits threshold in bytes (default: ``4*1024^3``)
%     - ``.ChunkSize`` - [1x3 double] level-0 chunk shape (default: ``[256 256 16]``)
%     - ``.Compressors`` - [char] codec name (default: ``'zstd'``)
%     - ``.Levels`` - [double] explicit pyramid level count (default: auto)
%     - ``.ShardSize`` - [1x3 double] per-axis chunk multipliers for zarr v3 sharding
%       (``[]`` = no sharding)
%     - ``.DownsampleMethod`` - [char] pyramid downsampling method (default: ``'bilinear'``)
%     - ``.DownsampleStrategy`` - [char] ``'XY only'`` (default) | ``'Anisotropy-preserving'``
%     - ``.cacheSizeBytes`` - [double] LRU tile-cache budget (default: ``2*1024^3``)
%     - ``.tileStack`` - [1 x N] drawing order for ``'Overwrite'``, bottom first
%       (default: ``[]``, see :func:`utils.stitch.tileDrawOrder`)
%     - ``.showWaitbar`` - [logical] show progress (default: ``false``)
%     - ``.parentFigure`` - [handle] progress-dialog parent (default: ``[]``)
%     - ``.pixSize`` - [struct] override ``canvas.pixSize`` for metadata (optional)
%
% Output Arguments:
%   (none) - writes ``outputZarrPath`` to disk.
%
% **Example** - stream a mosaic to zarr and reopen as BigData:
%
%   .. code-block:: matlab
%
%      utils.stitch.fuseStreaming(layout, canvas, 'C:\out\mosaic.zarr3', ...
%          struct('blendMode', 'Feather'));
%      loader = io.loaders.Zarr3VirtualSetupLoader(struct('datasetMode', 'BigData'));

if nargin < 4; options = struct(); end
if ~isfield(options, 'blendMode');      options.blendMode = 'Feather'; end
if ~isfield(options, 'background');     options.background = 0; end
if ~isfield(options, 'maxSliceBytes');  options.maxSliceBytes = 4 * 1024^3; end
if ~isfield(options, 'ChunkSize');      options.ChunkSize = [256 256 16]; end
if ~isfield(options, 'Compressors');    options.Compressors = 'zstd'; end
if ~isfield(options, 'cacheSizeBytes'); options.cacheSizeBytes = 2 * 1024^3; end
if ~isfield(options, 'correction');      options.correction = []; end
if ~isfield(options, 'showWaitbar');    options.showWaitbar = false; end
if ~isfield(options, 'parentFigure');   options.parentFigure = []; end

if isfield(options, 'pixSize') && ~isempty(options.pixSize)
    pixSize = options.pixSize;
else
    pixSize = canvas.pixSize;
end

H = canvas.size(1);
W = canvas.size(2);
C = canvas.size(4);
dataClass = canvas.dataClass;

sliceBytes = H * W * C * sizeofClass(dataClass);

if sliceBytes <= options.maxSliceBytes
    streamViaSaver(layout, canvas, outputZarrPath, options, pixSize);
else
    streamViaChunks(layout, canvas, outputZarrPath, options, pixSize);
end

% Stamp bounding box + pixel size for the BigData reopen recipe.
io.savers.Zarr3Saver.patchMetadata(outputZarrPath, pixSize, canvas.boundingBox);
end

% =====================================================================
function streamViaSaver(layout, canvas, outputZarrPath, options, pixSize)
% STREAMVIASAVER - Slice-fits path: delegate to Zarr3Saver.saveStream.
% correction must ride along: StitchSliceProvider builds its own tile reader, so
% leaving it out fused this path - the DEFAULT streaming path - on uncorrected
% pixels while the seams were measured and scored on corrected ones.
providerOptions = struct('blendMode', options.blendMode, ...
    'background', options.background, 'cacheSizeBytes', options.cacheSizeBytes, ...
    'correction', options.correction);
if isfield(options, 'marginPx');  providerOptions.marginPx  = options.marginPx; end
if isfield(options, 'tileStack'); providerOptions.tileStack = options.tileStack; end

provider = io.savers.StitchSliceProvider(layout, canvas, providerOptions);

metadata = struct('pixSize', pixSize);

saverOptions = struct();
saverOptions.silent      = ~options.showWaitbar;
saverOptions.showWaitbar = options.showWaitbar;
saverOptions.ChunkSize   = options.ChunkSize;
saverOptions.Compressors = options.Compressors;
% Forward the optional pyramid settings from the export-settings dialog.
% ChunkSize/Compressors above already stop Zarr3Saver from re-prompting.
for pyramidField = {'Levels', 'ShardSize', 'DownsampleMethod', ...
        'DownsampleStrategy', 'MinLevelSize', 'MaxLevels'}
    if isfield(options, pyramidField{1})
        saverOptions.(pyramidField{1}) = options.(pyramidField{1});
    end
end

% Zarr3Saver's progress dialog is gated on obj.ParentFigure, a property set
% only at CONSTRUCTION time (from a 'ParentFigure' field) - saveStream's own
% options struct (saverOptions.showWaitbar above) does not feed it. Passing
% struct() here left ParentFigure empty, so createProgressDialog always
% returned [] and the dialog silently never appeared regardless of
% showWaitbar. Same pattern as applyAlignmentBigData.m / ImageConverter.m.
saver = io.savers.Zarr3Saver(struct('ParentFigure', options.parentFigure));
saver.saveStream(provider, metadata, outputZarrPath, saverOptions);
end

% =====================================================================
function streamViaChunks(layout, canvas, outputZarrPath, options, pixSize)
% STREAMVIACHUNKS - Fallback: create the array and write chunk-aligned blocks.
%
% Writes level 0 chunk-by-chunk (loading only intersecting tiles per block) then
% builds pyramid levels by block-downsampling level 0, mirroring the level plan
% computed by Zarr3Saver.
H = canvas.size(1);
W = canvas.size(2);
Z = canvas.size(3);
C = canvas.size(4);
T = canvas.size(5);
dataClass = canvas.dataClass;

chunkSize = options.ChunkSize;
chunkY = min(chunkSize(1), H);
chunkX = min(chunkSize(2), W);
chunkZ = min(chunkSize(3), Z);

outputZarrPath = char(outputZarrPath);
if isfolder(outputZarrPath); rmdir(outputZarrPath, 's'); end
grp = io.zarr.Group.create(outputZarrPath);

% Build the level plan (same as Zarr3Saver so pyramid geometry matches).
planOptions = struct();
for planField = {'DownsampleStrategy', 'Levels', 'MinLevelSize', 'MaxLevels'}
    if isfield(options, planField{1}); planOptions.(planField{1}) = options.(planField{1}); end
end
if ~isfield(planOptions, 'DownsampleStrategy'); planOptions.DownsampleStrategy = 'XY only'; end
plan = io.savers.Zarr3Saver.computeLevelPlan(H, W, Z, pixSize, planOptions);
nLevels = numel(plan);

axesNames = {'y', 'x', 'z'}; axesTypes = {'space', 'space', 'space'};
if C > 1; axesNames{end+1} = 'c'; axesTypes{end+1} = 'channel'; end
if T > 1; axesNames{end+1} = 't'; axesTypes{end+1} = 'time'; end
nKeep = numel(axesNames);

levelArr  = cell(1, nLevels);
datasets  = cell(1, nLevels);
for L = 1:nLevels
    keepShape = [plan(L).Yl, plan(L).Xl, plan(L).Zl];
    if C > 1; keepShape(end+1) = C; end %#ok<AGROW>
    if T > 1; keepShape(end+1) = T; end %#ok<AGROW>
    chunk = min([chunkY chunkX chunkZ], keepShape(1:3));
    chunk = max(chunk, [1 1 1]);
    if numel(keepShape) > 3; chunk = [chunk, keepShape(4:end)]; end %#ok<AGROW>
    createArgs = {'chunkShape', chunk, 'compressors', options.Compressors};
    if isfield(options, 'ShardSize') && ~isempty(options.ShardSize)
        createArgs = [createArgs, {'shardShape', ...
            io.savers.Zarr3Saver.computeShard(chunk, options.ShardSize)}]; %#ok<AGROW>
    end
    levelArr{L} = grp.createArray(num2str(L - 1), keepShape, dataClass, createArgs{:});
    scaleVec = [plan(L).physScaleY, plan(L).physScaleX, plan(L).physScaleZ];
    if C > 1; scaleVec(end+1) = 1; end %#ok<AGROW>
    if T > 1; scaleVec(end+1) = 1; end %#ok<AGROW>
    datasets{L} = struct('path', num2str(L - 1), ...
        'coordinateTransformations', {{struct('type', 'scale', 'scale', scaleVec)}});
end

readerFcn = utils.stitch.makeTileReader(layout, ...
    struct('cacheSizeBytes', options.cacheSizeBytes, 'correction', options.correction));
% The correction and the tile stack ride along to the kernel too: Overwrite takes
% its drawing order from them (see utils.stitch.tileDrawOrder).
fuseOptions = struct('blendMode', options.blendMode, 'background', options.background, ...
    'correction', options.correction);
if isfield(options, 'tileStack'); fuseOptions.tileStack = options.tileStack; end
if isfield(options, 'marginPx'); fuseOptions.marginPx = options.marginPx; end

progressDialog = [];
if options.showWaitbar && ~isempty(options.parentFigure)
    progressDialog = uiprogressdlg(options.parentFigure, 'Value', 0, ...
        'Message', 'Streaming mosaic to zarr...', 'Title', 'Stitching');
end

% --- level 0: iterate Z-chunks, fuse each contained slice, write the block ----
totalChunks = T * ceil(Z / chunkZ);
doneChunks = 0;
for t = 1:T
    for zStart = 1:chunkZ:Z
        zEnd = min(zStart + chunkZ - 1, Z);
        block = cast(options.background, dataClass) + ...
            zeros(H, W, zEnd - zStart + 1, C, dataClass);
        for z = zStart:zEnd
            outSlice = utils.stitch.fuseSliceComposite(layout, canvas, z, t, readerFcn, fuseOptions);
            block(:, :, z - zStart + 1, :) = reshape(outSlice, H, W, 1, C);
        end
        bbox = buildBbox(zStart, zEnd, H, W, C, T, t);
        levelArr{1}.write(block, bbox);
        doneChunks = doneChunks + 1;
        if ~isempty(progressDialog) && isvalid(progressDialog)
            progressDialog.Value = doneChunks / totalChunks;
        end
    end
end

% --- pyramid levels: block-downsample the previous level, chunk by chunk ------
for L = 2:nLevels
    downsampleLevel(levelArr{L - 1}, levelArr{L}, plan(L - 1), plan(L), C, T, dataClass);
end

if ~isempty(progressDialog) && isvalid(progressDialog); close(progressDialog); end

% --- OME-NGFF multiscales attribute ------------------------------------------
axesCells = cell(1, nKeep);
for a = 1:nKeep; axesCells{a} = struct('name', axesNames{a}, 'type', axesTypes{a}); end
ms = struct('version', '0.4', 'axes', {axesCells}, 'datasets', {datasets});
grp.setAttributes(struct('multiscales', {{ms}}));
end

% =====================================================================
function downsampleLevel(srcArr, dstArr, srcPlan, dstPlan, C, T, dataClass)
% DOWNSAMPLELEVEL - XY-halve one pyramid level into the next (whole-slice pass).
srcZ = srcPlan.Zl;
dstY = dstPlan.Yl; dstX = dstPlan.Xl;
for t = 1:T
    for z = 1:srcZ
        bbox = sliceBbox(z, srcPlan.Yl, srcPlan.Xl, C, T, t);
        srcSlice = srcArr.read(bbox);                        % [Yl Xl (C) (T)]
        srcSlice = reshape(srcSlice, srcPlan.Yl, srcPlan.Xl, []);
        dstSlice = imresize(srcSlice, [dstY dstX], 'bilinear');
        dstSlice = cast(dstSlice, dataClass);
        wbox = sliceBbox(z, dstY, dstX, C, T, t);
        dstArr.write(reshape(dstSlice, wboxShape(dstY, dstX, C, T)), wbox);
    end
end
end

% =====================================================================
function bbox = buildBbox(zStart, zEnd, H, W, C, T, t)
% BUILDBBOX - Region bbox [start end+1) for a full-XY Z-block write.
bbox = [1, H + 1; 1, W + 1; zStart, zEnd + 1];
if C > 1; bbox(end+1, :) = [1, C + 1]; end
if T > 1; bbox(end+1, :) = [t, t + 1]; end
end

% =====================================================================
function bbox = sliceBbox(z, Y, X, C, T, t)
% SLICEBBOX - Region bbox [start end+1) for one full-XY slice at depth z.
bbox = [1, Y + 1; 1, X + 1; z, z + 1];
if C > 1; bbox(end+1, :) = [1, C + 1]; end
if T > 1; bbox(end+1, :) = [t, t + 1]; end
end

% =====================================================================
function shp = wboxShape(Y, X, C, T)
% WBOXSHAPE - Expected array shape for a single-slice region write.
shp = [Y, X, 1];
if C > 1; shp(end+1) = C; end
if T > 1; shp(end+1) = 1; end
end

% =====================================================================
function nBytes = sizeofClass(className)
% SIZEOFCLASS - Bytes per element for a numeric class name.
switch className
    case {'uint8', 'int8', 'logical'};   nBytes = 1;
    case {'uint16', 'int16'};            nBytes = 2;
    case {'uint32', 'int32', 'single'};  nBytes = 4;
    case {'uint64', 'int64', 'double'};  nBytes = 8;
    otherwise;                           nBytes = 8;
end
end
