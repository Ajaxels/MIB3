function readerFcn = makeTileReader(layout, options)
% MAKETILEREADER - Build a cached reader closure that returns tile images on demand.
%
% Syntax:
%   .. code-block:: matlab
%
%      readerFcn = utils.stitch.makeTileReader(layout)
%      readerFcn = utils.stitch.makeTileReader(layout, options)
%      img = readerFcn(tileIndex)
%      img = readerFcn(tileIndex, pixelRegion)
%
% Returns a function handle that loads and caches individual tiles described by
% the ``layout`` struct array. Only the first time point is returned. Single-file
% tiles are read via :func:`io.loadImagesWrapper`; subfolder tiles (with a
% non-empty ``.sliceFiles`` list) are read slice-by-slice and stacked along the
% depth dimension. A bounded least-recently-used (LRU) cache holds decoded full
% tiles so repeated reads (e.g. a tile appearing in several pairwise
% registrations) do not hit disk again. The cache is a plain cell/struct ring —
% no ``containers.Map`` — so it is safe to serialise into ``parfor`` workers.
%
% The optional ``pixelRegion`` second argument requests a sub-rectangle of a
% tile. For single-file TIFF/PNG tiles this uses ``imread(..., 'PixelRegion', ...)``
% as a fast path that avoids decoding the whole image; for every other case the
% full tile is loaded (and cached) and then cropped.
%
% Input Arguments:
%   - **layout** — [struct array] tile layout; each element has fields
%     ``.filename`` (char, full path — a folder for subfolder tiles),
%     ``.sliceFiles`` (cellstr, ``{}`` for single-file tiles) and ``.tileSize``.
%   - **options** *(optional)* — struct with fields:
%
%     - ``.cacheSizeBytes`` — [double] LRU cache budget in bytes (default: ``2*1024^3``)
%     - ``.mibBioformatsCheck`` — [logical] force the BioFormats reader (default: ``false``)
%
% Output Arguments:
%   - **readerFcn** — [function_handle] ``img = readerFcn(tileIndex)`` returns the
%     tile as ``[H, W, D, C]`` (first time point); ``img = readerFcn(tileIndex, pixelRegion)``
%     returns a sub-region where ``pixelRegion = [yMin yMax; xMin xMax]``.
%
% **Example** — read two tiles with a shared cache:
%
%   .. code-block:: matlab
%
%      readerFcn = utils.stitch.makeTileReader(layout);
%      tileA = readerFcn(1);
%      tileB = readerFcn(2);
%      crop  = readerFcn(1, [10 200; 10 200]);   % sub-region of tile 1

if nargin < 2; options = struct(); end
if ~isfield(options, 'cacheSizeBytes') || isempty(options.cacheSizeBytes)
    options.cacheSizeBytes = 2 * 1024^3;
end
if ~isfield(options, 'mibBioformatsCheck'); options.mibBioformatsCheck = false; end

% LRU cache state kept in closure-captured variables (no containers.Map).
cacheIndices = zeros(1, 0);      % tile index stored in each cache slot
cacheData    = {};               % [H W D C] arrays, one per slot
cacheBytes   = zeros(1, 0);      % byte size of each slot
cacheAge     = zeros(1, 0);      % monotonically increasing use counter (higher = newer)
useCounter   = 0;                % global monotonic clock
totalBytes   = 0;                % sum(cacheBytes)

loadOptions = struct('mibBioformatsCheck', options.mibBioformatsCheck, ...
    'BioFormatsIndices', 1, 'verbose', false);

readerFcn = @readTile;

    function img = readTile(tileIndex, pixelRegion)
        if nargin < 2; pixelRegion = []; end

        % Fast path: single-file TIFF/PNG sub-region read via imread PixelRegion.
        if ~isempty(pixelRegion) && ~cacheHas(tileIndex)
            fastImg = tryImreadPixelRegion(tileIndex, pixelRegion);
            if ~isempty(fastImg)
                img = fastImg;
                return;
            end
        end

        fullTile = getFullTile(tileIndex);
        if isempty(pixelRegion)
            img = fullTile;
        else
            yRange = pixelRegion(1, 1):pixelRegion(1, 2);
            xRange = pixelRegion(2, 1):pixelRegion(2, 2);
            img = fullTile(yRange, xRange, :, :);
        end
    end

    function tf = cacheHas(tileIndex)
        tf = any(cacheIndices == tileIndex);
    end

    function fullTile = getFullTile(tileIndex)
        slot = find(cacheIndices == tileIndex, 1);
        if ~isempty(slot)
            useCounter = useCounter + 1;
            cacheAge(slot) = useCounter;
            fullTile = cacheData{slot};
            return;
        end
        fullTile = loadTileFromDisk(tileIndex);
        insertIntoCache(tileIndex, fullTile);
    end

    function fullTile = loadTileFromDisk(tileIndex)
        entry = layout(tileIndex);
        if isfield(entry, 'sliceFiles') && ~isempty(entry.sliceFiles)
            % Subfolder tile: stack per-slice files along the depth dimension.
            sliceFiles = entry.sliceFiles;
            nSlices    = numel(sliceFiles);
            firstSlice = io.loadImagesWrapper(sliceFiles{1}, loadOptions);   % [H W 1 C 1]
            [H, W, ~, C, ~] = size(firstSlice);
            fullTile = zeros(H, W, nSlices, C, class(firstSlice));
            fullTile(:, :, 1, :) = firstSlice(:, :, 1, :, 1);
            for sliceIdx = 2:nSlices
                oneSlice = io.loadImagesWrapper(sliceFiles{sliceIdx}, loadOptions);
                fullTile(:, :, sliceIdx, :) = oneSlice(:, :, 1, :, 1);
            end
        else
            tileLoadOptions = loadOptions;
            % Bio-Formats tiles (from buildLayoutBioFormats) carry a series index;
            % force the Bio-Formats reader and select that series.
            if isfield(entry, 'seriesIndex') && ~isempty(entry.seriesIndex)
                tileLoadOptions.BioFormatsIndices  = entry.seriesIndex;
                tileLoadOptions.mibBioformatsCheck = true;
            end
            raw = io.loadImagesWrapper(entry.filename, tileLoadOptions);   % [H W D C T]
            fullTile = raw(:, :, :, :, 1);                                 % first time point
        end
    end

    function insertIntoCache(tileIndex, fullTile)
        bytes = numel(fullTile) * sizeofClass(class(fullTile));
        % Evict least-recently-used slots until the new tile fits (but always
        % keep at least the tile just requested).
        while ~isempty(cacheData) && (totalBytes + bytes) > options.cacheSizeBytes
            [~, oldest] = min(cacheAge);
            totalBytes = totalBytes - cacheBytes(oldest);
            cacheIndices(oldest) = [];
            cacheData(oldest)    = [];
            cacheBytes(oldest)   = [];
            cacheAge(oldest)     = [];
        end
        useCounter = useCounter + 1;
        cacheIndices(end + 1) = tileIndex;
        cacheData{end + 1}    = fullTile;
        cacheBytes(end + 1)   = bytes;
        cacheAge(end + 1)     = useCounter;
        totalBytes = totalBytes + bytes;
    end

    function img = tryImreadPixelRegion(tileIndex, pixelRegion)
        img = [];
        entry = layout(tileIndex);
        if isfield(entry, 'sliceFiles') && ~isempty(entry.sliceFiles); return; end
        % Bio-Formats series tiles cannot be sub-region-read via imread (which
        % only sees the first IFD) — fall through to the full Bio-Formats load.
        if isfield(entry, 'seriesIndex') && ~isempty(entry.seriesIndex); return; end
        [~, ~, ext] = fileparts(entry.filename);
        ext = lower(ext);
        if ~ismember(ext, {'.tif', '.tiff', '.png'}); return; end
        try
            rows = {pixelRegion(1, 1), pixelRegion(1, 2)};
            cols = {pixelRegion(2, 1), pixelRegion(2, 2)};
            raw = imread(entry.filename, 'PixelRegion', {rows, cols});
            % raw is [h w] or [h w c]; normalise to [H W 1 C].
            if ndims(raw) == 3
                img = reshape(raw, size(raw, 1), size(raw, 2), 1, size(raw, 3));
            else
                img = reshape(raw, size(raw, 1), size(raw, 2), 1, 1);
            end
        catch
            img = [];   % fall back to full-load-then-crop
        end
    end
end

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
