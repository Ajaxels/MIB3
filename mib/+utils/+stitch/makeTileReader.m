function [readerFcn, isCachedFcn] = makeTileReader(layout, options)
% MAKETILEREADER - Build a cached reader closure that returns tile images on demand.
%
% Syntax:
%   .. code-block:: matlab
%
%      readerFcn = utils.stitch.makeTileReader(layout)
%      [readerFcn, isCachedFcn] = utils.stitch.makeTileReader(layout, options)
%      img = readerFcn(tileIndex)
%      img = readerFcn(tileIndex, pixelRegion)
%      tf  = isCachedFcn(tileIndex)
%
% Returns a function handle that loads and caches individual tiles described by
% the ``layout`` struct array. Only the first time point is returned. Single-file
% tiles are read via :func:`io.loadImagesWrapper`; subfolder tiles (with a
% non-empty ``.sliceFiles`` list) are read slice-by-slice and stacked along the
% depth dimension; MRC-container tiles (with a ``.sliceIndex``, from
% :func:`utils.stitch.buildLayoutMdoc`) are read one slice at a time out of the
% shared stack. A bounded least-recently-used (LRU) cache holds decoded full
% tiles so repeated reads (e.g. a tile appearing in several pairwise
% registrations) do not hit disk again. The cache is a plain cell/struct ring -
% no ``containers.Map`` - so it is safe to serialise into ``parfor`` workers.
%
% The optional ``pixelRegion`` second argument requests a sub-rectangle of a
% tile. For single-file TIFF/PNG tiles this uses ``imread(..., 'PixelRegion', ...)``
% and for MRC-container tiles a ranged ``getVolume``, both avoiding a full decode;
% for every other case the full tile is loaded (and cached) and then cropped.
%
% .. important::
%    An MRC container is opened afresh on every read rather than kept open in the
%    closure: an open file handle cannot cross into a ``parfor`` worker, and the
%    header read it costs is negligible beside the pixels. The intensity scaling
%    is likewise taken from the FILE HEADER, so every tile of a montage shares one
%    scale - per-slice statistics would give each tile its own, injecting exactly
%    the intensity mismatch a stitch must not have.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout; each element has fields
%     ``.filename`` (char, full path - a folder for subfolder tiles, the shared
%     container for MRC tiles), ``.sliceFiles`` (cellstr, ``{}`` for single-file
%     tiles), ``.sliceIndex`` *(optional)* (1-based slice inside an MRC container)
%     and ``.tileSize``.
%   - **options** *(optional)* - struct with fields:
%
%     - ``.cacheSizeBytes`` - [double] LRU cache budget in bytes (default:
%       :func:`utils.stitch.tileCacheBudget`, which sizes it to the layout and to
%       the memory this machine has - a fixed 2 GB could not hold even ONE PAIR
%       of large tiles, so the pair view re-decoded both on every revisit)
%     - ``.mibBioformatsCheck`` - [logical] force the BioFormats reader (default: ``false``)
%     - ``.correction`` - [struct] intensity correction from
%       :func:`utils.stitch.estimateIntensityCorrection`, applied to every tile as it is
%       read (default: none). Building the reader with it is what makes the
%       correction reach measurement, seam scoring and fusion identically - there
%       is no second place pixels enter the pipeline. A ``.damage`` model
%       (``'Re-exposure damage'``) is inverted first, per tile, from that tile's
%       own footprint list; the strength map is built for exactly the region read,
%       so a cropped read and a crop of a full read agree.
%
% Output Arguments:
%   - **readerFcn** - [function_handle] ``img = readerFcn(tileIndex)`` returns the
%     tile as ``[H, W, D, C]`` (first time point); ``img = readerFcn(tileIndex, pixelRegion)``
%     returns a sub-region where ``pixelRegion = [yMin yMax; xMin xMax]``.
%   - **isCachedFcn** - [function_handle] ``tf = isCachedFcn(tileIndex)``: is that
%     tile resident, i.e. would a whole-tile read return immediately? Exists so a
%     caller can tell a free read from one that will stall on disk and put a
%     progress dialog around only the latter - a decode of a large tile is
%     several seconds, and a dialog flashed on every cached read would be worse
%     than none. Never treat it as a promise: a later read can evict the tile.
%
% **Example** - read two tiles with a shared cache:
%
%   .. code-block:: matlab
%
%      readerFcn = utils.stitch.makeTileReader(layout);
%      tileA = readerFcn(1);
%      tileB = readerFcn(2);
%      crop  = readerFcn(1, [10 200; 10 200]);   % sub-region of tile 1

if nargin < 2; options = struct(); end
if ~isfield(options, 'cacheSizeBytes') || isempty(options.cacheSizeBytes)
    options.cacheSizeBytes = utils.stitch.tileCacheBudget(layout);
end
if ~isfield(options, 'mibBioformatsCheck'); options.mibBioformatsCheck = false; end
if ~isfield(options, 'correction');         options.correction = []; end

% Resolve the correction once: the per-read path must not re-inspect a struct.
correctionField  = [];
correctionGain   = [];
correctionOffset = [];
if ~isempty(options.correction) && isstruct(options.correction)
    if isfield(options.correction, 'field');  correctionField  = single(options.correction.field); end
    if isfield(options.correction, 'gain');   correctionGain   = options.correction.gain; end
    if isfield(options.correction, 'offset'); correctionOffset = options.correction.offset; end
    % An all-neutral correction costs nothing to skip entirely.
    if isempty(correctionField) && (isempty(correctionGain) || all(correctionGain == 1)) && ...
            (isempty(correctionOffset) || all(correctionOffset == 0))
        correctionField = []; correctionGain = []; correctionOffset = [];
    end
end

% Re-exposure damage: split the footprint table per tile once, so a read only
% touches its own rows. A model with no footprints (nothing damaged, or not yet
% placed) is neutral and skipped like any other.
damageFootprints = {};
damageGain = 1; damageOffset = 0; damageDistance = []; damageProfiles = [];
if ~isempty(options.correction) && isstruct(options.correction) && ...
        isfield(options.correction, 'damage') && isstruct(options.correction.damage) && ...
        ~isempty(options.correction.damage.footprints)
    damageModel = options.correction.damage;
    damageGain     = damageModel.gain;
    damageOffset   = damageModel.offset;
    damageDistance = double(damageModel.distance);
    damageProfiles = double(damageModel.profiles);
    damageFootprints = cell(numel(layout), 1);
    for tileIdx = 1:numel(layout)
        damageFootprints{tileIdx} = damageModel.footprints(damageModel.footprints(:, 1) == tileIdx, 2:5);
    end
end
hasDamage = ~isempty(damageFootprints);
hasCorrection = ~isempty(correctionField) || ~isempty(correctionGain) || ...
    ~isempty(correctionOffset) || hasDamage;

% LRU cache state kept in closure-captured variables (no containers.Map).
cacheIndices = zeros(1, 0);      % tile index stored in each cache slot
cacheData    = {};               % [H W D C] arrays, one per slot
cacheBytes   = zeros(1, 0);      % byte size of each slot
cacheAge     = zeros(1, 0);      % monotonically increasing use counter (higher = newer)
useCounter   = 0;                % global monotonic clock
totalBytes   = 0;                % sum(cacheBytes)

loadOptions = struct('mibBioformatsCheck', options.mibBioformatsCheck, ...
    'BioFormatsIndices', 1, 'verbose', false);

readerFcn   = @readTile;
isCachedFcn = @cacheHas;

    function img = readTile(tileIndex, pixelRegion)
        if nargin < 2; pixelRegion = []; end

        % Fast path: sub-region read that avoids decoding the whole tile.
        if ~isempty(pixelRegion) && ~cacheHas(tileIndex)
            if isMrcTile(layout(tileIndex))
                fastImg = tryMrcRegion(tileIndex, pixelRegion);
            else
                fastImg = tryImreadPixelRegion(tileIndex, pixelRegion);
            end
            if ~isempty(fastImg)
                % Cropped reads bypass the cache, so they correct their own patch.
                img = applyCorrection(fastImg, tileIndex, pixelRegion);
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
        % Corrected ONCE on the way into the cache, so repeated reads (and every
        % crop taken from a cached tile) neither re-do the arithmetic nor risk
        % applying it twice.
        fullTile = applyCorrection(loadTileFromDisk(tileIndex), tileIndex, []);
        insertIntoCache(tileIndex, fullTile);
    end

    function img = applyCorrection(img, tileIndex, pixelRegion)
        % APPLYCORRECTION - Divide out the illumination field, then per-tile gain.
        % `pixelRegion` is [] for a whole tile, or the sub-rectangle a fast-path
        % read returned - the field has to be cropped to match it.
        if ~hasCorrection; return; end
        pixelClass = class(img);
        value = single(img);

        if hasDamage && ~isempty(damageFootprints{tileIndex})
            value = removeDamage(value, tileIndex, pixelRegion);
        end

        if ~isempty(correctionField)
            if isempty(pixelRegion)
                fieldPatch = correctionField;
            else
                fieldPatch = correctionField(pixelRegion(1, 1):pixelRegion(1, 2), ...
                                             pixelRegion(2, 1):pixelRegion(2, 2));
            end
            if ~isequal(size(fieldPatch), [size(value, 1), size(value, 2)])
                error('utils:stitch:makeTileReader:correctionSizeMismatch', ...
                    ['The intensity correction was estimated for %dx%d tiles but ' ...
                     'tile %d reads as %dx%d. Re-estimate it for this layout.'], ...
                    size(correctionField, 1), size(correctionField, 2), ...
                    tileIndex, size(value, 1), size(value, 2));
            end
            value = value ./ fieldPatch;      % [H W] broadcasts over depth + colour
        end

        if ~isempty(correctionOffset) && correctionOffset(tileIndex) ~= 0
            value = value - single(correctionOffset(tileIndex));
        end
        if ~isempty(correctionGain) && correctionGain(tileIndex) ~= 1
            value = value * single(correctionGain(tileIndex));
        end

        img = cast(value, pixelClass);   % integer casts round and SATURATE
    end

    function value = removeDamage(value, tileIndex, pixelRegion)
        % REMOVEDAMAGE - Invert observed = truth + S * ((gain - 1) * truth + offset).
        % S is the sum over this tile's earlier footprints of a separable product
        % of the across-side profiles - see estimateIntensityCorrection.
        if isempty(pixelRegion)
            rows = (1:size(value, 1))';
            cols = 1:size(value, 2);
        else
            rows = (pixelRegion(1, 1):pixelRegion(1, 2))';
            cols = pixelRegion(2, 1):pixelRegion(2, 2);
        end
        footprints = damageFootprints{tileIndex};
        strength = zeros(numel(rows), numel(cols), 'single');
        for footprintIdx = 1:size(footprints, 1)
            fp = footprints(footprintIdx, :);
            colStrength = sideStrength(cols, fp(3), fp(4), damageProfiles(1, :), damageProfiles(2, :));
            if ~any(colStrength); continue; end
            rowStrength = sideStrength(rows, fp(1), fp(2), damageProfiles(3, :), damageProfiles(4, :));
            if ~any(rowStrength); continue; end
            strength = strength + single(rowStrength(:) * colStrength(:)');
        end
        denominator = max(0.05, 1 + strength * single(damageGain - 1));
        value = (value - strength * single(damageOffset)) ./ denominator;   % [H W] broadcasts
    end

    function strength = sideStrength(coords, lowEdge, highEdge, lowProfile, highProfile)
        % SIDESTRENGTH - One axis of a footprint's strength: the profile of
        % whichever of its two sides is nearer, at the signed outward distance.
        distanceLow  = (lowEdge - 0.5) - coords;
        distanceHigh = coords - (highEdge + 0.5);
        useHigh = distanceHigh >= distanceLow;
        distance = max(distanceLow, distanceHigh);
        distance = max(distance, damageDistance(1));   % deep inside: the plateau
        strength = zeros(size(coords));
        strength(useHigh)  = interp1(damageDistance, highProfile, distance(useHigh), 'linear', 0);
        strength(~useHigh) = interp1(damageDistance, lowProfile, distance(~useHigh), 'linear', 0);
    end

    function fullTile = loadTileFromDisk(tileIndex)
        entry = layout(tileIndex);
        if isMrcTile(entry)
            % One slice of a shared MRC container (SerialEM montage).
            fullTile = readMrcSlice(entry, []);
        elseif isfield(entry, 'sliceFiles') && ~isempty(entry.sliceFiles)
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

    function img = tryMrcRegion(tileIndex, pixelRegion)
        % Ranged read straight out of the container - no full-slice decode.
        try
            img = readMrcSlice(layout(tileIndex), pixelRegion);
        catch
            img = [];   % fall back to full-load-then-crop
        end
    end

    function img = tryImreadPixelRegion(tileIndex, pixelRegion)
        img = [];
        entry = layout(tileIndex);
        if isfield(entry, 'sliceFiles') && ~isempty(entry.sliceFiles); return; end
        % Bio-Formats series tiles cannot be sub-region-read via imread (which
        % only sees the first IFD) - fall through to the full Bio-Formats load.
        if isfield(entry, 'seriesIndex') && ~isempty(entry.seriesIndex); return; end
        % Multi-page z-stack tiles: imread reads only the FIRST page, so the
        % depth would be silently lost - full-load-then-crop instead.
        if isfield(entry, 'tileSize') && numel(entry.tileSize) >= 3 && entry.tileSize(3) > 1
            return;
        end
        [~, ~, ext] = fileparts(entry.filename);
        ext = lower(ext);
        if ~ismember(ext, {'.tif', '.tiff', '.png'}); return; end
        try
            % NUMERIC row/column vectors. Building these as cells - {r0, r1} -
            % makes imread reject PIXELREGION outright ("its type was cell"),
            % which the catch below then swallowed: every TIFF sub-region read
            % silently fell back to decoding the whole file. On a 24000x24000
            % single-row-strip tile that turned a 0.7 s overlap read into 10 s.
            % The regression test asserts the tile is NOT cached afterwards -
            % only the fallback path caches, so that is what tells the two apart.
            rows = [pixelRegion(1, 1), pixelRegion(1, 2)];
            cols = [pixelRegion(2, 1), pixelRegion(2, 2)];
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

% =========================================================================
function tf = isMrcTile(entry)
% ISMRCTILE - Is this layout entry a slice of a shared MRC container?
tf = isfield(entry, 'sliceIndex') && ~isempty(entry.sliceIndex) && entry.sliceIndex > 0;
end

% =========================================================================
function img = readMrcSlice(entry, pixelRegion)
% READMRCSLICE - Read one slice (or a sub-rectangle of it) from an MRC container.
%
% Returns ``[H W 1 1]`` in MIB's frame, converted to the class
% :func:`utils.stitch.mrcTargetClass` picks for the container's mode.
%
% Two coordinate facts drive the index arithmetic, both matching what
% :class:`io.loaders.ImodLoader` does to a whole stack:
%
%   - MRC is stored ``[x y z]`` and MIB wants ``[row col]``, hence the permute;
%   - MRC rows run BOTTOM-UP, so ImodLoader flips the y axis. A MIB row ``r``
%     therefore reads MRC ``j = nY - r + 1``, and a row RANGE maps to the
%     mirrored range, which is then flipped back inside the block.

mrcFile = MRCImage(entry.filename, 0);   % header only until getVolume is called
cleanup = onCleanup(@() close(mrcFile));
header  = getHeader(mrcFile);

sliceIndex = entry.sliceIndex;
if sliceIndex < 1 || sliceIndex > header.nZ
    error('utils:stitch:makeTileReader:badSliceIndex', ...
        'Slice %d requested from %s, which holds %d slices.', ...
        sliceIndex, entry.filename, header.nZ);
end

if isempty(pixelRegion)
    columnRange = [];
    mirroredRowRange = [];
else
    columnRange = [pixelRegion(2, 1), pixelRegion(2, 2)];
    % Mirror the row range into the container's bottom-up y axis.
    mirroredRowRange = [header.nY - pixelRegion(1, 2) + 1, ...
                        header.nY - pixelRegion(1, 1) + 1];
end

raw = getVolume(mrcFile, columnRange, mirroredRowRange, [sliceIndex sliceIndex]);
raw = permute(flip(raw, 2), [2 1 3]);    % [x y] bottom-up -> [row col] top-down

[targetClass, needsScaling] = utils.stitch.mrcTargetClass(header.mode);
if needsScaling
    % Header densities, never per-slice statistics: one scale for every tile.
    [minDensity, maxDensity] = getMinAndMaxDensity(mrcFile);
    densityRange = double(maxDensity) - double(minDensity);
    if ~isfinite(densityRange) || densityRange <= 0; densityRange = 1; end
    raw = (single(raw) - single(minDensity)) / single(densityRange) * ...
        single(double(intmax(targetClass)));
    raw = max(0, min(single(double(intmax(targetClass))), raw));
end
img = cast(raw, targetClass);
img = reshape(img, size(img, 1), size(img, 2), 1, 1);

end

% =========================================================================
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
