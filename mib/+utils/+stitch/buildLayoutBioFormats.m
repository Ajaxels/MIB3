function layout = buildLayoutBioFormats(inputPath, options)
% BUILDLAYOUTBIOFORMATS - Build a tile layout from embedded Bio-Formats stage coordinates.
%
% Syntax:
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutBioFormats(inputPath)
%      layout = utils.stitch.buildLayoutBioFormats(inputPath, options)
%
% Reads the physical stage position stored in the OME metadata of each tile
% (``Plane PositionX/Y/Z``) and converts it into the stitcher's pixel/slice
% ``nomOrigin`` frame via :func:`utils.stitch.stageCoordsToOrigins`. This is the
% ``'Bio-Formats metadata'`` layout source: unlike the grid / position-file /
% filename-pattern sources it needs no user-supplied arrangement — the
% microscope already recorded where every tile sits.
%
% ``inputPath`` may be:
%   - a single Bio-Formats file whose **series** are the tiles (the typical
%     mosaic case, e.g. one ``.czi`` / ``.nd2`` / ``.lif`` with N series), or
%   - a newline-separated list of files, or a folder — one **file per tile**,
%     each carrying its own stage position.
%
% Pixel size is assumed uniform across tiles (MIB convention) and taken from the
% first tile; the resulting dataset ``pixSize`` should likewise come from the
% first tile. Distinct stage-Z values become separate ``zLayer`` layers, so a
% multi-focus acquisition is jointly solved just like a position file with a Z
% column.
%
% Input Arguments:
%   - **inputPath** — [char] file, newline-list of files, or folder (see above).
%   - **options** *(optional)* — struct with fields:
%
%     - ``.flipX`` / ``.flipY`` — [logical] negate the stage axis when it runs
%       opposite to the pixel axis (vendor-dependent; default ``false``).
%     - ``.bioFormatsMemoizerMemoDir`` — [char] memo dir (default: ``tempdir``).
%
% Output Arguments:
%   - **layout** — struct array per the layout contract (see
%     :func:`utils.stitch.buildLayoutGrid`) with an extra ``.seriesIndex`` field
%     (1-based Bio-Formats series) honoured by :func:`utils.stitch.makeTileReader`.
%
% **Example** — stitch a multi-series confocal mosaic:
%
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutBioFormats('C:\data\mosaic.czi');

if nargin < 2; options = struct(); end
if ~isfield(options, 'flipX'); options.flipX = false; end
if ~isfield(options, 'flipY'); options.flipY = false; end
if ~isfield(options, 'bioFormatsMemoizerMemoDir'); options.bioFormatsMemoizerMemoDir = tempdir; end

utils.ensureJavaLibraries({'bioformats'});

fileList = resolveFileList(inputPath);
if isempty(fileList)
    error('utils:stitch:buildLayoutBioFormats:noFiles', ...
        'No Bio-Formats files resolved from: %s', inputPath);
end

% ---- Read per-series dimensions + stage coordinates from every file ----
tileFile   = {};
tileSeries = [];
tileSizes  = zeros(0, 4);        % [H W D C]
tileClass  = {};
stageXYZum = zeros(0, 3);
pixSize    = [];

loci.common.DebugTools.setRootLevel('ERROR');
for fileIdx = 1:numel(fileList)
    reader = loci.formats.Memoizer(bfGetReader(), 0, java.io.File(options.bioFormatsMemoizerMemoDir));
    cleanupReader = onCleanup(@() safeCloseReader(reader));
    reader.setId(fileList{fileIdx});
    omeMeta = reader.getMetadataStore();
    numSeries = reader.getSeriesCount();

    for seriesIdx = 1:numSeries
        reader.setSeries(seriesIdx - 1);
        H = reader.getSizeY();
        W = reader.getSizeX();
        D = reader.getSizeZ();
        C = reader.getSizeC();

        tileFile{end + 1}   = fileList{fileIdx}; %#ok<AGROW>
        tileSeries(end + 1) = seriesIdx;         %#ok<AGROW>
        tileSizes(end + 1, :) = [H, W, D, C];    %#ok<AGROW>
        tileClass{end + 1}  = classFromBits(reader.getBitsPerPixel()); %#ok<AGROW>
        stageXYZum(end + 1, :) = readStageXYZ(omeMeta, seriesIdx - 1);  %#ok<AGROW>

        if isempty(pixSize)
            pixSize = readPixelSize(omeMeta, seriesIdx - 1);
        end
    end
    clear cleanupReader;   % close this file's reader before opening the next
end

numTiles = numel(tileFile);
if numTiles == 0
    error('utils:stitch:buildLayoutBioFormats:noSeries', ...
        'No readable image series found in the selected input.');
end
if isempty(pixSize); pixSize = struct('x', 1, 'y', 1, 'z', 1, 'units', 'um'); end

% ---- Convert stage coordinates to pixel/slice origins (pure, testable) ----
convOptions = struct('flipX', options.flipX, 'flipY', options.flipY);
[nomOrigin, zLayer] = utils.stitch.stageCoordsToOrigins(stageXYZum, pixSize, convOptions);

% ---- Assemble the layout struct array ----
layout = repmat(emptyLayout(), 1, numTiles);
for tileIdx = 1:numTiles
    layout(tileIdx).index       = tileIdx;
    layout(tileIdx).filename    = tileFile{tileIdx};
    layout(tileIdx).sliceFiles  = {};                 % Bio-Formats reads the stack directly
    layout(tileIdx).seriesIndex = tileSeries(tileIdx);
    layout(tileIdx).zLayer      = zLayer(tileIdx);
    layout(tileIdx).gridRC      = [NaN, NaN];
    layout(tileIdx).nomOrigin   = nomOrigin(tileIdx, :);
    layout(tileIdx).tileSize    = tileSizes(tileIdx, :);
    layout(tileIdx).dataClass   = tileClass{tileIdx};
    % Read from the first tile's OME metadata above; carried per tile so the
    % stitched dataset inherits the scale instead of defaulting to 1 um.
    layout(tileIdx).pixSize     = pixSize;
end
end

% =========================================================================
function fileList = resolveFileList(inputPath)
% RESOLVEFILELIST - Turn inputPath into a cell list of Bio-Formats files.
fileList = {};
% Newline-separated list (GUI multi-select) takes priority.
parts = strtrim(strsplit(inputPath, newline));
parts = parts(~cellfun(@isempty, parts));
if numel(parts) > 1
    fileList = parts;
    return;
end
singlePath = parts{1};
if isfolder(singlePath)
    extensions = {'*.czi', '*.nd2', '*.lif', '*.ome.tif', '*.ome.tiff', ...
        '*.tif', '*.tiff', '*.oib', '*.oif', '*.vsi', '*.lsm'};
    for extIdx = 1:numel(extensions)
        found = dir(fullfile(singlePath, extensions{extIdx}));
        if ~isempty(found)
            fileList = [fileList, fullfile(singlePath, {found.name})]; %#ok<AGROW>
        end
    end
    fileList = unique(fileList, 'stable');
elseif isfile(singlePath)
    fileList = {singlePath};
end
end

% =========================================================================
function stageXYZ = readStageXYZ(omeMeta, series0)
% READSTAGEXYZ - Plane (0,0) stage position in µm; missing values → 0.
stageXYZ = [getPlanePos(@omeMeta.getPlanePositionX, series0), ...
            getPlanePos(@omeMeta.getPlanePositionY, series0), ...
            getPlanePos(@omeMeta.getPlanePositionZ, series0)];
end

% =========================================================================
function value = getPlanePos(accessor, series0)
% GETPLANEPOS - Read one plane-position component in µm, 0 on any failure.
value = 0;
try
    quantity = accessor(series0, 0);
    if ~isempty(quantity)
        value = double(quantity.value(ome.units.UNITS.MICROMETER));
    end
catch
    value = 0;
end
end

% =========================================================================
function pixSize = readPixelSize(omeMeta, series0)
% READPIXELSIZE - Physical pixel size in µm; defaults to 1 when absent.
pixSize = struct('x', 1, 'y', 1, 'z', 1, 'units', 'um');
pixSize.x = getPhysicalSize(@omeMeta.getPixelsPhysicalSizeX, series0, 1);
pixSize.y = getPhysicalSize(@omeMeta.getPixelsPhysicalSizeY, series0, pixSize.x);
pixSize.z = getPhysicalSize(@omeMeta.getPixelsPhysicalSizeZ, series0, pixSize.y);
end

% =========================================================================
function value = getPhysicalSize(accessor, series0, defaultValue)
% GETPHYSICALSIZE - Read one physical-size component in µm, default on failure.
value = defaultValue;
try
    quantity = accessor(series0);
    if ~isempty(quantity)
        candidate = double(quantity.value(ome.units.UNITS.MICROMETER));
        if ~isempty(candidate) && candidate > 0
            value = candidate;
        end
    end
catch
    value = defaultValue;
end
end

% =========================================================================
function className = classFromBits(bitsPerPixel)
% CLASSFROMBITS - MATLAB class name for a Bio-Formats bit depth.
switch bitsPerPixel
    case 8;  className = 'uint8';
    case 16; className = 'uint16';
    case 32; className = 'uint32';
    otherwise; className = 'double';
end
end

% =========================================================================
function safeCloseReader(reader)
% SAFECLOSEREADER - Close a Bio-Formats reader, ignoring errors.
try
    if ~isempty(reader); reader.close(); end
catch
end
end

% =========================================================================
function singleLayout = emptyLayout()
% EMPTYLAYOUT - Layout contract + the Bio-Formats-only seriesIndex field.
singleLayout = struct('index', {}, 'filename', {}, 'sliceFiles', {}, ...
    'seriesIndex', {}, 'zLayer', {}, 'gridRC', {}, 'nomOrigin', {}, ...
    'tileSize', {}, 'dataClass', {}, 'pixSize', {});
end
