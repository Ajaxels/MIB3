function outSlice = fuseSliceComposite(layout, canvas, zGlobal, ~, readerFcn, options)
% FUSESLICECOMPOSITE - Composite all tiles intersecting one output Z-slice.
%
% Syntax:
%   .. code-block:: matlab
%
%      outSlice = utils.stitch.fuseSliceComposite(layout, canvas, zGlobal, t, readerFcn, options)
%
% Shared per-slice fusion kernel used by :func:`utils.stitch.fuseInMemory`,
% :func:`utils.stitch.fuseStreaming` and :class:`io.savers.StitchSliceProvider`.
% It builds one output slice ``[H W C]`` of ``canvas.dataClass`` at global depth
% ``zGlobal`` (1-based) and time ``t`` by placing every tile whose Z-band covers
% ``zGlobal`` at its ``canvas.tilePlacement`` origin using the requested blend
% mode. Feather/Average use single-precision accumulators and divide once at the
% end; Max/Min/Overwrite write in place. When the plan carries per-slice mosaic
% corrections (``canvas.zShifts`` from the inspector's Fix Z), every tile on
% this slice is additionally shifted by ``canvas.zShifts(zGlobal, :)``.
%
% When ``canvas.tforms`` is present (affine plan from
% :func:`utils.stitch.planCanvas` + :func:`utils.stitch.solveGlobalAffine`),
% each tile whose transform is not an integer translation is RESAMPLED into its
% warped output footprint with ``imwarp`` (bilinear, zero fill); its blend
% weights are warped identically so the feather follows the warped footprint,
% and Max/Min/Overwrite only touch pixels the warped tile actually covers. Tiles
% whose transform reduces to an integer translation - and every tile when there
% are no ``canvas.tforms`` - take the resampling-free integer-placement fast
% path, which is bit-identical to the translation-only kernel.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout.
%   - **canvas** - [struct] from :func:`utils.stitch.planCanvas`.
%   - **zGlobal** - [double] 1-based global output slice index.
%   - **t** - [double] time frame (1-based).
%   - **readerFcn** - [function_handle] tile reader from :func:`utils.stitch.makeTileReader`.
%   - **options** - [struct] with fields:
%
%     - ``.blendMode`` - [char] ``'Feather'`` | ``'Average'`` | ``'Max'`` | ``'Min'`` | ``'Overwrite'``
%     - ``.background`` - [double] background fill value
%     - ``.marginPx`` - [double] feather margin (Feather mode; default derived from tile size)
%     - ``.correction`` - [struct] *(optional)* the intensity correction the tiles
%       are read with (see :func:`utils.stitch.estimateIntensityCorrection`). Only
%       its ``.damage.order`` is used here, and only by ``'Overwrite'``: see below.
%     - ``.tileStack`` - [1 x N] *(optional)* explicit drawing order, bottom
%       first, set in the seam inspector. ``'Overwrite'`` only.
%
% .. note::
%    **Which tile wins an ``'Overwrite'`` overlap is decided by
%    :func:`utils.stitch.tileDrawOrder`**: an explicit ``tileStack`` if set,
%    otherwise - with a re-exposure damage model - the tile imaged FIRST (the
%    later one shows specimen the beam had already hit; the correction evens its
%    brightness but cannot give back destroyed structure), otherwise the highest
%    index. The seam inspector colours the winning tile magenta from the same
%    function. Max/Min/Feather/Average do not depend on the drawing order and are
%    left alone.
%
% Output Arguments:
%   - **outSlice** - [H x W x C] fused slice of class ``canvas.dataClass``.

blendMode  = options.blendMode;
background = options.background;

H = canvas.size(1);
W = canvas.size(2);
C = canvas.size(4);
dataClass = canvas.dataClass;

nTiles = numel(layout);
placement = canvas.tilePlacement;
hasTforms = isfield(canvas, 'tforms') && ~isempty(canvas.tforms);

% Per-slice mosaic correction (inspector Fix Z): every tile on this output
% slice is shifted in-plane by canvas.zShifts(zGlobal, :) - see planCanvas.
sliceShift = [0, 0];
if isfield(canvas, 'zShifts') && ~isempty(canvas.zShifts) && ...
        zGlobal >= 1 && zGlobal <= size(canvas.zShifts, 1)
    sliceShift = canvas.zShifts(zGlobal, :);
end

% Determine which tiles contribute to this global Z-slice.
tileSizes = reshape([layout.tileSize], 4, nTiles)';   % [H W D C]
tileDepth = tileSizes(:, 3);
zStart = placement(:, 3);
zEnd   = placement(:, 3) + tileDepth - 1;
contributing = find(zGlobal >= zStart & zGlobal <= zEnd);

% Overwrite: the last tile drawn wins, so draw in the stacking order (see the
% note above).
if strcmp(blendMode, 'Overwrite')
    correction = [];
    tileStack  = [];
    if isfield(options, 'correction'); correction = options.correction; end
    if isfield(options, 'tileStack');  tileStack  = options.tileStack;  end
    stack = utils.stitch.tileDrawOrder(nTiles, correction, tileStack);
    [~, stackPosition] = ismember(contributing, stack);
    [~, drawOrder] = sort(stackPosition);
    contributing = contributing(drawOrder);
end

useAccumulator = ismember(blendMode, {'Feather', 'Average'});
if useAccumulator
    weightSum = zeros(H, W, C, 'single');
    valueSum  = zeros(H, W, C, 'single');
else
    outSlice = cast(background, dataClass) + zeros(H, W, C, dataClass);
    if ismember(blendMode, {'Max', 'Min'})
        extremaInitialised = false(H, W);
    end
end

for idx = 1:numel(contributing)
    t2 = contributing(idx);
    localZ = zGlobal - zStart(t2) + 1;    % 1-based slice within the tile

    tile = readerFcn(t2);                 % [Ht Wt Dt Ct]
    Ht = size(tile, 1);
    Wt = size(tile, 2);
    Ct = size(tile, 4);
    tileSlice = reshape(tile(:, :, localZ, :), Ht, Wt, Ct);   % [Ht Wt Ct]

    % Broadcast a single-channel tile to the canvas channel count.
    if Ct == 1 && C > 1
        tileSlice = repmat(tileSlice, 1, 1, C);
    elseif Ct > C
        tileSlice = tileSlice(:, :, 1:C);
    end

    % Resampling path: only when the plan carries per-tile transforms AND this
    % tile's transform does not reduce to an integer translation. Everything
    % else takes the integer-placement fast path below.
    needsWarp = hasTforms && ~isIntegerTranslation(canvas.tforms{t2});

    if needsWarp
        marginPx = [];
        if isfield(options, 'marginPx'); marginPx = options.marginPx; end
        sliceTform = canvas.tforms{t2};
        sliceBounds = canvas.tileBounds(t2, :);
        if any(sliceShift ~= 0)
            sliceTform(1:2, 3) = sliceTform(1:2, 3) + [sliceShift(2); sliceShift(1)];
            sliceBounds = sliceBounds + [sliceShift(1), sliceShift(1), sliceShift(2), sliceShift(2)];
            sliceBounds = [max(1, sliceBounds(1)), min(H, sliceBounds(2)), ...
                           max(1, sliceBounds(3)), min(W, sliceBounds(4))];
        end
        [tileSlice, weight, coverage, rowRange, colRange] = warpTileSlice( ...
            tileSlice, sliceTform, sliceBounds, blendMode, marginPx);
        if isempty(rowRange) || isempty(colRange); continue; end
    else
        oy = placement(t2, 1) + sliceShift(1);
        ox = placement(t2, 2) + sliceShift(2);
        rowRange = oy:(oy + Ht - 1);
        colRange = ox:(ox + Wt - 1);

        % Clip to canvas bounds defensively.
        validRows = rowRange >= 1 & rowRange <= H;
        validCols = colRange >= 1 & colRange <= W;
        rowRange = rowRange(validRows);
        colRange = colRange(validCols);
        if isempty(rowRange) || isempty(colRange); continue; end
        tileSlice = tileSlice(validRows, validCols, :);
    end

    switch blendMode
        case {'Feather', 'Average'}
            if ~needsWarp
                if strcmp(blendMode, 'Feather')
                    if isfield(options, 'marginPx') && ~isempty(options.marginPx)
                        weight = utils.stitch.blendWeights([Ht Wt], options.marginPx);
                    else
                        weight = utils.stitch.blendWeights([Ht Wt]);
                    end
                    weight = weight(validRows, validCols);
                else
                    weight = ones(numel(rowRange), numel(colRange), 'single');
                end
            end   % warped tiles arrive with their weights already warped along
            valueSum(rowRange, colRange, :) = valueSum(rowRange, colRange, :) + ...
                single(tileSlice) .* weight;
            weightSum(rowRange, colRange, :) = weightSum(rowRange, colRange, :) + weight;

        case {'Max', 'Min'}
            block = outSlice(rowRange, colRange, :);
            tileCast = cast(tileSlice, dataClass);
            % Fresh (not-yet-covered) pixels take the tile value directly (so the
            % background is never folded into the projection - critical for Min,
            % where a zero background would otherwise win everywhere); already-
            % covered pixels take the element-wise extremum of the current block
            % and the new tile. Warped tiles additionally leave pixels outside
            % their footprint untouched.
            if needsWarp
                freshMask = ~extremaInitialised(rowRange, colRange) & coverage;
            else
                freshMask = ~extremaInitialised(rowRange, colRange);   % [nRows nCols]
            end
            if strcmp(blendMode, 'Max')
                projected = max(block, tileCast);
            else
                projected = min(block, tileCast);
            end
            fresh3 = repmat(freshMask, 1, 1, size(block, 3));
            projected(fresh3) = tileCast(fresh3);
            if needsWarp
                outside3 = repmat(~coverage, 1, 1, size(block, 3));
                projected(outside3) = block(outside3);
                outSlice(rowRange, colRange, :) = projected;
                extremaInitialised(rowRange, colRange) = extremaInitialised(rowRange, colRange) | coverage;
            else
                outSlice(rowRange, colRange, :) = projected;
                extremaInitialised(rowRange, colRange) = true;
            end

        case 'Overwrite'
            if needsWarp
                block = outSlice(rowRange, colRange, :);
                tileCast = cast(tileSlice, dataClass);
                coverage3 = repmat(coverage, 1, 1, size(block, 3));
                block(coverage3) = tileCast(coverage3);
                outSlice(rowRange, colRange, :) = block;
            else
                outSlice(rowRange, colRange, :) = cast(tileSlice, dataClass);
            end

        otherwise
            error('utils:stitch:fuseSliceComposite:badBlend', ...
                'Unknown blendMode "%s"', blendMode);
    end
end

if useAccumulator
    outSlice = cast(background, dataClass) + zeros(H, W, C, dataClass);
    covered = weightSum > 0;
    fused = valueSum;
    fused(covered) = valueSum(covered) ./ weightSum(covered);
    % Write only covered pixels; leave the background value everywhere else.
    fusedCast = cast(fused, dataClass);
    outSlice(covered) = fusedCast(covered);
end
end

% =====================================================================
function tf = isIntegerTranslation(tformMatrix)
% ISINTEGERTRANSLATION - True when a 3x3 transform is a pure translation by a
% whole number of pixels, i.e. eligible for the resampling-free placement path.
tformMatrix = double(tformMatrix);
linearPart = tformMatrix(1:2, 1:2);
translation = tformMatrix(1:2, 3);
tf = max(abs(linearPart - eye(2)), [], 'all') < 1e-9 && ...
     max(abs(translation - round(translation))) < 1e-3;
end

% =====================================================================
function [warpedSlice, weight, coverage, rowRange, colRange] = warpTileSlice( ...
    tileSlice, tformMatrix, bounds, blendMode, marginPx)
% WARPTILESLICE - Resample one tile slice (and its blend weights) into the
% tile's warped output footprint.
%
% bounds is the integer canvas bbox [y0 y1 x0 x1] from planCanvas. The canvas
% world frame equals its intrinsic pixel frame (centres at integers), so the
% OutputView spans the bbox pixel EDGES (centre +- 0.5). Bilinear resampling
% with zero fill; the weight map is warped with the same transform so the
% feather follows the warped footprint (and fades with the partial pixel
% coverage at the resampled border). coverage marks pixels the warped tile
% actually reaches - Max/Min/Overwrite must not touch anything else.
y0 = bounds(1); y1 = bounds(2);
x0 = bounds(3); x1 = bounds(4);
if y1 < y0 || x1 < x0
    warpedSlice = []; weight = []; coverage = [];
    rowRange = []; colRange = [];
    return;
end
rowRange = y0:y1;
colRange = x0:x1;

Ht = size(tileSlice, 1);
Wt = size(tileSlice, 2);
outputView = imref2d([y1 - y0 + 1, x1 - x0 + 1], ...
    [x0 - 0.5, x1 + 0.5], [y0 - 0.5, y1 + 0.5]);
tformObj = affinetform2d(double(tformMatrix));

warpedSlice = imwarp(single(tileSlice), tformObj, 'linear', ...
    'OutputView', outputView, 'FillValues', 0);

switch blendMode
    case 'Feather'
        if isempty(marginPx)
            flatWeight = utils.stitch.blendWeights([Ht Wt]);
        else
            flatWeight = utils.stitch.blendWeights([Ht Wt], marginPx);
        end
        weight = imwarp(flatWeight, tformObj, 'linear', ...
            'OutputView', outputView, 'FillValues', 0);
        coverage = weight > 0;
    case 'Average'
        weight = imwarp(ones(Ht, Wt, 'single'), tformObj, 'linear', ...
            'OutputView', outputView, 'FillValues', 0);
        coverage = weight > 0;
    otherwise   % Max / Min / Overwrite need a hard footprint mask, no weights
        weight = [];
        coverage = imwarp(ones(Ht, Wt, 'single'), tformObj, 'linear', ...
            'OutputView', outputView, 'FillValues', 0) > 0.5;
end
end
