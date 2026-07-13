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
% end; Max/Overwrite write in place.
%
% Input Arguments:
%   - **layout** — [struct array] tile layout.
%   - **canvas** — [struct] from :func:`utils.stitch.planCanvas`.
%   - **zGlobal** — [double] 1-based global output slice index.
%   - **t** — [double] time frame (1-based).
%   - **readerFcn** — [function_handle] tile reader from :func:`utils.stitch.makeTileReader`.
%   - **options** — [struct] with fields:
%
%     - ``.blendMode`` — [char] ``'Feather'`` | ``'Average'`` | ``'Max'`` | ``'Overwrite'``
%     - ``.background`` — [double] background fill value
%     - ``.marginPx`` — [double] feather margin (Feather mode; default derived from tile size)
%
% Output Arguments:
%   - **outSlice** — [H x W x C] fused slice of class ``canvas.dataClass``.

blendMode  = options.blendMode;
background = options.background;

H = canvas.size(1);
W = canvas.size(2);
C = canvas.size(4);
dataClass = canvas.dataClass;

nTiles = numel(layout);
placement = canvas.tilePlacement;

% Determine which tiles contribute to this global Z-slice.
tileSizes = reshape([layout.tileSize], 4, nTiles)';   % [H W D C]
tileDepth = tileSizes(:, 3);
zStart = placement(:, 3);
zEnd   = placement(:, 3) + tileDepth - 1;
contributing = find(zGlobal >= zStart & zGlobal <= zEnd);

useAccumulator = ismember(blendMode, {'Feather', 'Average'});
if useAccumulator
    weightSum = zeros(H, W, C, 'single');
    valueSum  = zeros(H, W, C, 'single');
else
    outSlice = cast(background, dataClass) + zeros(H, W, C, dataClass);
    if strcmp(blendMode, 'Max')
        maxInitialised = false(H, W);
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

    oy = placement(t2, 1);
    ox = placement(t2, 2);
    rowRange = oy:(oy + Ht - 1);
    colRange = ox:(ox + Wt - 1);

    % Clip to canvas bounds defensively.
    validRows = rowRange >= 1 & rowRange <= H;
    validCols = colRange >= 1 & colRange <= W;
    rowRange = rowRange(validRows);
    colRange = colRange(validCols);
    if isempty(rowRange) || isempty(colRange); continue; end
    tileSlice = tileSlice(validRows, validCols, :);

    switch blendMode
        case {'Feather', 'Average'}
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
            valueSum(rowRange, colRange, :) = valueSum(rowRange, colRange, :) + ...
                single(tileSlice) .* weight;
            weightSum(rowRange, colRange, :) = weightSum(rowRange, colRange, :) + weight;

        case 'Max'
            block = outSlice(rowRange, colRange, :);
            tileCast = cast(tileSlice, dataClass);
            % Fresh (not-yet-covered) pixels take the tile value directly (so a
            % non-zero background is never max-ed in); already-covered pixels take
            % the element-wise max of the current block and the new tile.
            freshMask = ~maxInitialised(rowRange, colRange);   % [nRows nCols]
            maxed = max(block, tileCast);
            fresh3 = repmat(freshMask, 1, 1, size(block, 3));
            maxed(fresh3) = tileCast(fresh3);
            outSlice(rowRange, colRange, :) = maxed;
            maxInitialised(rowRange, colRange) = true;

        case 'Overwrite'
            outSlice(rowRange, colRange, :) = cast(tileSlice, dataClass);

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
