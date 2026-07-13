function layout = buildLayoutPositionFile(positionFilePath, options)
% BUILDLAYOUTPOSITIONFILE - Build a tile layout struct from a position text file.
%
% Syntax:
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutPositionFile(positionFilePath)
%      layout = utils.stitch.buildLayoutPositionFile(positionFilePath, options)
%
% The position file contains one tile per line with columns:
%   ``filename  X  Y  [Z]``
% Delimiter is auto-detected among space, tab, and comma; repeated spaces
% are treated as a single delimiter.  Filenames may be relative to the
% position file's folder.  X and Y are 0-based pixel origins in the file;
% they are stored as 1-based in the layout.
%
% Distinct Z values are mapped to ``zLayer`` 1..K in ascending order.
% When ``options.subfolderMode`` is ``true`` the position file is ignored
% and instead each direct subfolder of the position file's parent directory
% is treated as one Z-stack tile; subfolder images are natural-sorted into
% ``layout(i).sliceFiles``.
%
% Input Arguments:
%   - **positionFilePath** — [char] full path to the position file
%   - **options** *(optional)* — struct with fields:
%
%     - ``.subfolderMode`` — [logical] treat subfolders as Z-stack tiles (default: ``false``)
%
% Output Arguments:
%   - **layout** — struct array per contract (see ``buildLayoutGrid`` for field list)
%
% **Example** — load a comma-delimited position file:
%
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutPositionFile('/data/positions.txt');
%

arguments
    positionFilePath (1,:) char
    options.subfolderMode logical = false
end

rootFolder = fileparts(positionFilePath);
if isempty(rootFolder)
    rootFolder = pwd;
end

if options.subfolderMode
    layout = buildFromSubfolders(rootFolder);
    return;
end

layout = buildFromFile(positionFilePath, rootFolder);

end

% =========================================================================
function layout = buildFromFile(positionFilePath, rootFolder)
% Parse the position text file and build the layout struct array.

rawText = fileread(positionFilePath);
rawLines = strsplit(rawText, {'\n', '\r\n', '\r'});
% Remove empty and comment lines
validLines = {};
for lineIdx = 1:numel(rawLines)
    trimmedLine = strtrim(rawLines{lineIdx});
    if ~isempty(trimmedLine) && trimmedLine(1) ~= '#' && trimmedLine(1) ~= '%'
        validLines{end+1} = trimmedLine; %#ok<AGROW>
    end
end

if isempty(validLines)
    layout = emptyLayout();
    return;
end

% Auto-detect delimiter from first line
firstLine = validLines{1};
if contains(firstLine, ',')
    delimiterPattern = ',';
elseif contains(firstLine, char(9))
    delimiterPattern = '\t';
else
    delimiterPattern = '\s+';
end

numTiles = numel(validLines);
filenames   = cell(numTiles, 1);
originX     = zeros(numTiles, 1);
originY     = zeros(numTiles, 1);
originZ     = zeros(numTiles, 1);
hasZColumn  = false;

for lineIdx = 1:numTiles
    if strcmp(delimiterPattern, '\s+')
        tokens = regexp(strtrim(validLines{lineIdx}), '\s+', 'split');
    else
        tokens = strsplit(validLines{lineIdx}, delimiterPattern);
        tokens = strtrim(tokens);
        tokens = tokens(~cellfun(@isempty, tokens));
    end

    if numel(tokens) < 3
        warning('utils:stitch:buildLayoutPositionFile:badLine', ...
            'Skipping line %d: fewer than 3 columns.', lineIdx);
        continue;
    end

    tileName = tokens{1};
    % Resolve relative paths
    if ~java.io.File(tileName).isAbsolute()
        tileName = fullfile(rootFolder, tileName);
    end
    filenames{lineIdx} = tileName;
    originX(lineIdx)   = str2double(tokens{2});
    originY(lineIdx)   = str2double(tokens{3});

    if numel(tokens) >= 4
        originZ(lineIdx) = str2double(tokens{4});
        hasZColumn = true;
    end
end

% Remove rows that were skipped
validMask = ~cellfun(@isempty, filenames);
filenames  = filenames(validMask);
originX    = originX(validMask);
originY    = originY(validMask);
originZ    = originZ(validMask);
numTiles   = numel(filenames);

if numTiles == 0
    layout = emptyLayout();
    return;
end

% Map Z values to 1-based zLayer indices
if hasZColumn
    uniqueZ = unique(originZ);
    uniqueZ = sort(uniqueZ);
    zLayerMap = dictionary(uniqueZ, (1:numel(uniqueZ))');
else
    zLayerMap = dictionary(0, 1);
    originZ = zeros(numTiles, 1);
end

% Read first tile size
[tileHeight, tileWidth, tileDepth, tileColors, tileClass] = readTileSize(filenames{1});
tileSize = [tileHeight, tileWidth, tileDepth, tileColors];

layout = repmat(emptyLayout(), 1, numTiles);
for tileIdx = 1:numTiles
    zValue = originZ(tileIdx);
    layout(tileIdx).index      = tileIdx;
    layout(tileIdx).filename   = filenames{tileIdx};
    layout(tileIdx).sliceFiles = {};
    layout(tileIdx).zLayer     = zLayerMap(zValue);
    layout(tileIdx).gridRC     = [NaN, NaN];
    % File uses 0-based origins; store 1-based
    layout(tileIdx).nomOrigin  = [originY(tileIdx) + 1, originX(tileIdx) + 1, layout(tileIdx).zLayer];
    layout(tileIdx).tileSize   = tileSize;
    layout(tileIdx).dataClass  = tileClass;
end

end

% =========================================================================
function layout = buildFromSubfolders(rootFolder)
% Each direct subfolder is one tile (Z-stack); images inside are natural-sorted.

subFolderList = dir(rootFolder);
subFolderList = subFolderList([subFolderList.isdir]);
subFolderList = subFolderList(~ismember({subFolderList.name}, {'.', '..'}));

if isempty(subFolderList)
    layout = emptyLayout();
    return;
end

folderNames = {subFolderList.name};
sortedFolderNames = utils.stitch.naturalSortFiles(folderNames);
numTiles = numel(sortedFolderNames);

% Read first tile size from first image in first subfolder
firstTileClass = 'uint8';
firstTileSize  = [256, 256, 1, 1];
firstSubfolder = fullfile(rootFolder, sortedFolderNames{1});
imagePattern   = {'*.tif','*.tiff','*.png','*.jpg','*.jpeg','*.bmp'};
firstImages    = {};
for extIdx = 1:numel(imagePattern)
    foundFiles = dir(fullfile(firstSubfolder, imagePattern{extIdx}));
    if ~isempty(foundFiles)
        firstImages = fullfile(firstSubfolder, {foundFiles.name});
        break;
    end
end
if ~isempty(firstImages)
    sortedFirstImages = utils.stitch.naturalSortFiles(firstImages);
    [h, w, d, c, cls] = readTileSize(sortedFirstImages{1});
    numSlices = numel(sortedFirstImages);
    firstTileSize  = [h, w, d * numSlices, c];
    firstTileClass = cls;
end

layout = repmat(emptyLayout(), 1, numTiles);
for tileIdx = 1:numTiles
    subfolderPath = fullfile(rootFolder, sortedFolderNames{tileIdx});
    % Collect images in the subfolder
    sliceFiles = {};
    for extIdx = 1:numel(imagePattern)
        foundFiles = dir(fullfile(subfolderPath, imagePattern{extIdx}));
        if ~isempty(foundFiles)
            sliceFiles = fullfile(subfolderPath, {foundFiles.name});
            sliceFiles = utils.stitch.naturalSortFiles(sliceFiles);
            break;
        end
    end

    layout(tileIdx).index      = tileIdx;
    layout(tileIdx).filename   = subfolderPath;
    layout(tileIdx).sliceFiles = sliceFiles;
    layout(tileIdx).zLayer     = tileIdx;
    layout(tileIdx).gridRC     = [NaN, NaN];
    layout(tileIdx).nomOrigin  = [1, 1, tileIdx];
    layout(tileIdx).tileSize   = firstTileSize;
    layout(tileIdx).dataClass  = firstTileClass;
end

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
    warning('utils:stitch:buildLayoutPositionFile:cannotReadTile', ...
        'Cannot read tile size from %s; using defaults 256x256.', filename);
end

end
