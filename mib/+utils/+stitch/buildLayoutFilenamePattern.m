function layout = buildLayoutFilenamePattern(filenames, options)
% BUILDLAYOUTFILENAMEPATTERN - Build a tile layout from MIB2 chop filename tokens.
%
% Syntax:
%   .. code-block:: matlab
%
%      layout = utils.stitch.buildLayoutFilenamePattern(filenames)
%      layout = utils.stitch.buildLayoutFilenamePattern(filenames, options)
%
% Parses the ``Z##`` / ``X##`` / ``Y##`` tokens embedded in each tile filename
% (the format produced by MIB2's rechop tool), e.g.
% ``myStack_Z01-X02-Y03.tif`` → Z=1, X=2, Y=3.
%
% The three tokens are located INDEPENDENTLY (last occurrence of each letter in
% the base name), so their ORDER and the separators between them do not matter -
% ``_Z01-X02-Y03``, ``_X02-Y03-Z01`` and ``Y03X02Z01`` all parse identically.
% Constraints that DO matter:
%
%   - the letter must be upper case and followed by EXACTLY two digits: exactly
%     two characters are read, so ``Z1`` errors and ``Z001`` silently parses as
%     ``00`` (a rename to two-digit tokens is required above 99 tiles per axis);
%   - indices are 1-based (``Z01-X01-Y01`` is the first tile);
%   - because the LAST occurrence wins, ``Z``/``X``/``Y`` may appear before the
%     tokens (``XYZstack_Z01-X01-Y01``) but not after (``..._Y01_XY``).
%
% Each entry may name a single image file OR a FOLDER holding the tile's
% Z-stack (auto-detected per entry by :func:`utils.stitch.resolveTileEntry`) -
% for folder tiles the tokens live in the FOLDER name and follow the same rules.
%
% Nominal origins are computed from the grid indices and the (uniform) tile size,
% with an optional XY overlap (default 0% = abutting chunks, the MIB2-rechop
% reassembly case). With a non-zero overlap the step shrinks like the Grid
% source, so pattern-named tiles from an overlapping acquisition get honest
% nominal positions that the measurement pass can then refine. Z layers always
% abut (no Z-overlap control). Origins are 1-based pixels.
%
% Input Arguments:
%   - **filenames** - [cell] cell array of full-path character vectors
%   - **options** *(optional)* - struct with fields:
%
%     - ``.overlapX`` - [double] horizontal overlap in percent (default: ``0``)
%     - ``.overlapY`` - [double] vertical overlap in percent (default: ``0``)
%
% Output Arguments:
%   - **layout** - struct array per contract (see ``buildLayoutGrid`` for field list)
%
% **Example** - parse a set of MIB2-chopped tiles with 12% overlap:
%
%   .. code-block:: matlab
%
%      files = dir('C:\data\chop\*.tif');
%      layout = utils.stitch.buildLayoutFilenamePattern( ...
%          fullfile({files.folder}, {files.name}), struct('overlapX', 12, 'overlapY', 12));
%

arguments
    filenames cell
    options struct = struct()
end
if ~isfield(options, 'overlapX'); options.overlapX = 0; end
if ~isfield(options, 'overlapY'); options.overlapY = 0; end

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

% Resolve every entry (single image file or folder Z-stack) and use the first
% tile's size for the abutting-grid step. Each entry may be a folder tile.
[firstSliceFiles, firstSize, ~] = utils.stitch.resolveTileEntry(filenames{1});  %#ok<ASGLU>
% XY step shrinks by the overlap (like buildLayoutGrid); Z always abuts.
stepX = firstSize(2) * (1 - options.overlapX / 100);
stepY = firstSize(1) * (1 - options.overlapY / 100);
stepZ = firstSize(3);

layout = repmat(emptyLayout(), 1, numFiles);
for fileIdx = 1:numFiles
    zIdx = zNumber(fileIdx);
    yIdx = yNumber(fileIdx);
    xIdx = xNumber(fileIdx);

    originY = (yIdx - 1) * stepY + 1;
    originX = (xIdx - 1) * stepX + 1;
    originZ = (zIdx - 1) * stepZ + 1;

    [sliceFiles, tileSize, tileClass] = utils.stitch.resolveTileEntry(filenames{fileIdx});

    layout(fileIdx).index      = fileIdx;
    layout(fileIdx).filename   = filenames{fileIdx};
    layout(fileIdx).sliceFiles = sliceFiles;
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
