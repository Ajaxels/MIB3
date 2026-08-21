function layout = buildLayoutPositionFile(positionFilePath, options)
% BUILDLAYOUTPOSITIONFILE - Build a tile layout struct from a position text file.
%
% Syntax:
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutPositionFile(positionFilePath)
%      layout = utils.stitch.buildLayoutPositionFile(positionFilePath, options)
%
% The position file contains one tile per line with columns
% ``filename  X  Y  [Z]``.
% Delimiter is auto-detected among space, tab, and comma; repeated spaces
% are treated as a single delimiter.  Filenames may be relative to the
% position file's folder.  X, Y and Z are 0-based pixel/slice origins in the
% file; they are stored 1-based in ``nomOrigin`` (``[y x z]``, z in SLICES).
%
% Distinct Z values are additionally ranked into ``zLayer`` 1..K in ascending
% order - ``zLayer`` drives layer-adjacency logic (``findNeighborPairs``),
% while ``nomOrigin(3)`` carries the actual nominal slice coordinate used by
% the solver and canvas.
%
% A ``filename`` entry may name a single image file OR a FOLDER holding the
% tile's Z-stack (one image per slice) - this is auto-detected per entry by
% ``utils.stitch.resolveTileEntry``, so folder Z-stack tiles work here exactly
% as in the grid and filename-pattern sources.
%
% Input Arguments:
%   - **positionFilePath** - [char] full path to the position file
%   - **options** *(optional)* - struct (reserved; no fields used currently)
%
% Output Arguments:
%   - **layout** - struct array per contract (see ``buildLayoutGrid`` for field list)
%
% **Example** - load a comma-delimited position file:
%
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutPositionFile('/data/positions.txt');
%

arguments
    positionFilePath (1,:) char
    options struct = struct() %#ok<INUSA>
end

rootFolder = fileparts(positionFilePath);
if isempty(rootFolder)
    rootFolder = pwd;
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
    if ~isAbsolutePath(tileName)
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

layout = repmat(emptyLayout(), 1, numTiles);
for tileIdx = 1:numTiles
    zValue = originZ(tileIdx);
    % Resolve each entry (single image file or folder Z-stack) individually.
    [sliceFiles, tileSize, tileClass] = utils.stitch.resolveTileEntry(filenames{tileIdx});
    layout(tileIdx).index      = tileIdx;
    layout(tileIdx).filename   = filenames{tileIdx};
    layout(tileIdx).sliceFiles = sliceFiles;
    layout(tileIdx).zLayer     = zLayerMap(zValue);
    layout(tileIdx).gridRC     = [NaN, NaN];
    % File uses 0-based origins; store 1-based. z is a SLICE coordinate.
    layout(tileIdx).nomOrigin  = [originY(tileIdx) + 1, originX(tileIdx) + 1, zValue + 1];
    layout(tileIdx).tileSize   = tileSize;
    layout(tileIdx).dataClass  = tileClass;
end

end

% =========================================================================
function tf = isAbsolutePath(pathStr)
% ISABSOLUTEPATH - Pure-MATLAB absolute-path check (no Java - required for
% compiled standalone builds). Absolute forms: Windows drive roots ('C:\',
% 'C:/'), UNC shares ('\\server\...'), and POSIX roots ('/...').
tf = ~isempty(regexp(pathStr, '^([A-Za-z]:[\\/]|\\\\|/)', 'once'));
end

% =========================================================================
function singleLayout = emptyLayout()
singleLayout = struct('index', {}, 'filename', {}, 'sliceFiles', {}, 'zLayer', {}, ...
    'gridRC', {}, 'nomOrigin', {}, 'tileSize', {}, 'dataClass', {});
end
