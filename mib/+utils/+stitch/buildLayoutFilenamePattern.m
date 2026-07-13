function layout = buildLayoutFilenamePattern(filenames)
% BUILDLAYOUTFILENAMEPATTERN - Build a tile layout from MIB2 chop filename tokens.
%
% Syntax:
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutFilenamePattern(filenames)
%
% Parses the ``_Z##-X##-Y##`` token embedded in each tile filename
% (the format produced by MIB2's rechop tool).  The last occurrence of
% each letter token in the base filename is used, e.g.:
%   ``myStack_Z01-X02-Y03.tif``  → Z=1, X=2, Y=3
%
% Tiles abut (0% overlap): nominal origins are computed from cumulative
% tile sizes (each tile is assumed the same size as the first tile).
% Origins are 1-based pixels.
%
% Input Arguments:
%   - **filenames** — [cell] cell array of full-path character vectors
%
% Output Arguments:
%   - **layout** — struct array per contract (see ``buildLayoutGrid`` for field list)
%
% **Example** — parse a set of MIB2-chopped tiles:
%
%   .. code-block:: matlab
%
%      files = dir('C:\data\chop\*.tif');
%      layout = utils.stitch.buildLayoutFilenamePattern(fullfile({files.folder}, {files.name}));
%

arguments
    filenames cell
end

if isempty(filenames)
    layout = struct('index', {}, 'filename', {}, 'sliceFiles', {}, 'zLayer', {}, ...
        'gridRC', {}, 'nomOrigin', {}, 'tileSize', {}, 'dataClass', {});
    return;
end

numFiles = numel(filenames);

zNumber = zeros(numFiles, 1);
yNumber = zeros(numFiles, 1);
xNumber = zeros(numFiles, 1);

for fileIdx = 1:numFiles
    [~, baseName, ~] = fileparts(filenames{fileIdx});

    % Find last occurrence of Z, X, Y tokens and read the 2-digit number
    zIndices = strfind(baseName, 'Z');
    yIndices = strfind(baseName, 'Y');
    xIndices = strfind(baseName, 'X');

    if isempty(zIndices) || isempty(yIndices) || isempty(xIndices)
        error('utils:stitch:buildLayoutFilenamePattern:missingToken', ...
            'File %s does not contain _Z##-X##-Y## tokens.', filenames{fileIdx});
    end

    zPos = zIndices(end);
    yPos = yIndices(end);
    xPos = xIndices(end);

    zNumber(fileIdx) = str2double(baseName(zPos+1 : zPos+2));
    yNumber(fileIdx) = str2double(baseName(yPos+1 : yPos+2));
    xNumber(fileIdx) = str2double(baseName(xPos+1 : xPos+2));
end

% Validate parsing
if any(isnan(zNumber)) || any(isnan(yNumber)) || any(isnan(xNumber))
    error('utils:stitch:buildLayoutFilenamePattern:parseError', ...
        'Failed to parse Z/X/Y numbers from some filenames.');
end

numTilesZ = max(zNumber);
numTilesY = max(yNumber);
numTilesX = max(xNumber);

% Read first tile dimensions
[tileHeight, tileWidth, tileDepth, tileColors, tileClass] = readTileSize(filenames{1});
tileSize = [tileHeight, tileWidth, tileDepth, tileColors];

% Abutting placement (0% overlap)
stepX = tileWidth;
stepY = tileHeight;
stepZ = tileDepth;

layout = repmat(emptyLayout(), 1, numFiles);
for fileIdx = 1:numFiles
    zIdx = zNumber(fileIdx);
    yIdx = yNumber(fileIdx);
    xIdx = xNumber(fileIdx);

    originY = (yIdx - 1) * stepY + 1;
    originX = (xIdx - 1) * stepX + 1;
    originZ = (zIdx - 1) * stepZ + 1;

    layout(fileIdx).index      = fileIdx;
    layout(fileIdx).filename   = filenames{fileIdx};
    layout(fileIdx).sliceFiles = {};
    layout(fileIdx).zLayer     = zIdx;
    layout(fileIdx).gridRC     = [yIdx, xIdx];
    layout(fileIdx).nomOrigin  = [originY, originX, originZ];
    layout(fileIdx).tileSize   = tileSize;
    layout(fileIdx).dataClass  = tileClass;
end

% Suppress unused variable warnings
numTilesZ; %#ok<VUNUS>
numTilesY; %#ok<VUNUS>
numTilesX; %#ok<VUNUS>

end

% =========================================================================
function singleLayout = emptyLayout()
singleLayout = struct('index', {}, 'filename', {}, 'sliceFiles', {}, 'zLayer', {}, ...
    'gridRC', {}, 'nomOrigin', {}, 'tileSize', {}, 'dataClass', {});
end

% =========================================================================
function [tileHeight, tileWidth, tileDepth, tileColors, tileClass] = readTileSize(filename)
% Read tile dimensions; fast path for common image formats.

[~, ~, extension] = fileparts(filename);
extension = lower(extension);

tileDepth  = 1;
tileColors = 1;
tileClass  = 'uint8';
tileHeight = 256;
tileWidth  = 256;

if ismember(extension, {'.tif', '.tiff', '.png', '.jpg', '.jpeg', '.bmp'})
    try
        info = imfinfo(filename);
        tileHeight = info(1).Height;
        tileWidth  = info(1).Width;
        tileDepth  = numel(info);
        if isfield(info(1), 'SamplesPerPixel')
            tileColors = info(1).SamplesPerPixel;
        end
        if isfield(info(1), 'BitDepth')
            bitDepth = info(1).BitDepth;
            if tileColors > 1
                bitDepth = bitDepth / tileColors;
            end
            if bitDepth <= 8
                tileClass = 'uint8';
            elseif bitDepth <= 16
                tileClass = 'uint16';
            else
                tileClass = 'single';
            end
        end
        return;
    catch
        % Fall through
    end
end

try
    loadOpts.silent = true;
    tileData = io.loadImagesWrapper(filename, loadOpts);
    if ~isempty(tileData)
        tileHeight = size(tileData, 1);
        tileWidth  = size(tileData, 2);
        tileDepth  = size(tileData, 3);
        tileColors = size(tileData, 4);
        tileClass  = class(tileData);
    end
catch
    warning('utils:stitch:buildLayoutFilenamePattern:cannotReadTile', ...
        'Cannot read tile size from %s; using defaults 256x256.', filename);
end

end
