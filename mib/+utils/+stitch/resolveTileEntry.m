function [sliceFiles, tileSize, dataClass] = resolveTileEntry(entryPath)
% RESOLVETILEENTRY - Resolve a tile source path to its slices, size and class.
%
% Syntax:
%   .. code-block:: matlab
%
%      [sliceFiles, tileSize, dataClass] = utils.stitch.resolveTileEntry(entryPath)
%
% A tile source is either a single image file or a FOLDER holding the tile's
% Z-stack (one image per slice). This helper is the single place that decides
% which, so every layout builder (:func:`utils.stitch.buildLayoutGrid`,
% :func:`utils.stitch.buildLayoutPositionFile`,
% :func:`utils.stitch.buildLayoutFilenamePattern`) supports folder Z-stack tiles
% identically: whether a tile is a folder is a property of the SOURCE, orthogonal
% to how the tiles are ARRANGED (grid, position file, filename pattern).
%
% Input Arguments:
%   - **entryPath** - [char] path to a single image file or a tile folder.
%
% Output Arguments:
%   - **sliceFiles** - [cell] ``{}`` for a single-file tile, otherwise the
%     natural-sorted list of per-slice image paths in the folder.
%   - **tileSize** - [1x4 double] ``[H W D C]``; ``D`` is the slice count for a
%     folder tile.
%   - **dataClass** - [char] numeric class of the tile pixels.
%
% **Example** - resolve a folder Z-stack tile:
%
%   .. code-block:: matlab
%
%      [slices, sz, cls] = utils.stitch.resolveTileEntry('C:\data\tile_01');
%      % numel(slices) == sz(3)

if isfolder(entryPath)
    sliceFiles = listFolderImages(entryPath);
    [tileHeight, tileWidth, ~, tileColors, dataClass] = readImageDims(sliceFiles{1});
    tileSize = [tileHeight, tileWidth, numel(sliceFiles), tileColors];
else
    sliceFiles = {};
    [tileHeight, tileWidth, tileDepth, tileColors, dataClass] = readImageDims(entryPath);
    tileSize = [tileHeight, tileWidth, tileDepth, tileColors];
end
end

% =========================================================================
function imageFiles = listFolderImages(folderPath)
% LISTFOLDERIMAGES - Natural-sorted image files inside a tile folder (Z-stack).
imagePattern = {'*.tif', '*.tiff', '*.png', '*.jpg', '*.jpeg', '*.bmp'};
imageFiles = {};
for extIdx = 1:numel(imagePattern)
    found = dir(fullfile(folderPath, imagePattern{extIdx}));
    if ~isempty(found)
        imageFiles = fullfile(folderPath, {found.name});
        break;
    end
end
if isempty(imageFiles)
    error('utils:stitch:resolveTileEntry:emptyFolder', ...
        'Tile folder contains no images: %s', folderPath);
end
imageFiles = utils.stitch.naturalSortFiles(imageFiles);
end

% =========================================================================
function [tileHeight, tileWidth, tileDepth, tileColors, tileClass] = readImageDims(filename)
% READIMAGEDIMS - Read [H W D C] + class of an image file (imfinfo fast path).
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
        % Fall through to loadImagesWrapper.
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
    warning('utils:stitch:resolveTileEntry:cannotReadTile', ...
        'Cannot read tile size from %s; using defaults 256x256.', filename);
end
end
