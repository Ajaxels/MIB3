function [regionSlice, usedTiles] = fuseSliceRegion(layout, canvas, zGlobal, region, readerFcn, options)
% FUSESLICEREGION - Fuse one rectangle of one output Z-slice of the mosaic.
%
% Syntax:
%   .. code-block:: matlab
%
%      regionSlice = utils.stitch.fuseSliceRegion(layout, canvas, zGlobal, region, readerFcn, options)
%      [regionSlice, usedTiles] = utils.stitch.fuseSliceRegion(...)
%
% The same pixels :func:`utils.stitch.fuseSliceComposite` would produce for
% ``region`` of slice ``zGlobal`` - same blend mode, drawing order, warps and
% per-slice corrections - without composing (or reading the tiles of) the rest
% of the slice. Used by the seam inspector's Fix Z view, which compares two
% consecutive mosaic slices around a point the user picked.
%
% Implemented as a re-framed call to ``fuseSliceComposite`` rather than a
% region branch inside it: only the tiles whose footprint meets the region on
% this slice are kept, the canvas origin is moved to the region's corner (tile
% placements, warped bounds and transforms shifted by the same amount) and the
% canvas size is the region's. The kernel's own clipping then cuts the tiles to
% the region, so the result is bit-identical to cropping a full fuse (pinned by
% a test). Tile indices are renumbered for the subset, so the reader is wrapped
% and the ``'Overwrite'`` drawing order is resolved on the FULL tile set first
% (``utils.stitch.tileDrawOrder``) and passed on as an explicit stack.
%
% Input Arguments:
%   - **layout** - [struct array] tile layout.
%   - **canvas** - [struct] from :func:`utils.stitch.planCanvas`.
%   - **zGlobal** - [double] 1-based output slice.
%   - **region** - [2x2 double] ``[rowStart rowEnd; colStart colEnd]`` in canvas
%     pixels (clipped to the canvas).
%   - **readerFcn** - [function_handle] tile reader (:func:`utils.stitch.makeTileReader`).
%   - **options** - [struct] as :func:`utils.stitch.fuseSliceComposite`
%     (``.blendMode``, ``.background``, optional ``.marginPx``, ``.correction``,
%     ``.tileStack``).
%
% Output Arguments:
%   - **regionSlice** - [h x w x C] the fused region, class ``canvas.dataClass``
%   - **usedTiles** - [1 x K] indices (into ``layout``) of the tiles that
%     contributed
%
% **Example** - a 512 px square around canvas pixel (1000, 2000) of slice 7:
%
%   .. code-block:: matlab
%
%      region = [1000 - 255, 1000 + 256; 2000 - 255, 2000 + 256];
%      crop = utils.stitch.fuseSliceRegion(layout, canvas, 7, region, readerFcn, ...
%          struct('blendMode', 'Overwrite', 'background', 0));
%

region = round(region);
region(1, :) = min(max(region(1, :), 1), canvas.size(1));
region(2, :) = min(max(region(2, :), 1), canvas.size(2));
regionH = region(1, 2) - region(1, 1) + 1;
regionW = region(2, 2) - region(2, 1) + 1;
offsetYX = [region(1, 1) - 1, region(2, 1) - 1];

% ---- the tiles that reach the region on this slice ---------------------------
numTiles = numel(layout);
tileSizes = reshape([layout.tileSize], 4, numTiles)';
placement = canvas.tilePlacement;
onSlice = zGlobal >= placement(:, 3) & zGlobal <= placement(:, 3) + tileSizes(:, 3) - 1;
sliceShift = [0, 0];
if isfield(canvas, 'zShifts') && ~isempty(canvas.zShifts) && zGlobal <= size(canvas.zShifts, 1)
    sliceShift = canvas.zShifts(zGlobal, :);
end
hasTforms = isfield(canvas, 'tforms') && ~isempty(canvas.tforms);
if hasTforms
    footprint = canvas.tileBounds + [sliceShift(1), sliceShift(1), sliceShift(2), sliceShift(2)];
else
    footprint = [placement(:, 1), placement(:, 1) + tileSizes(:, 1) - 1, ...
                 placement(:, 2), placement(:, 2) + tileSizes(:, 2) - 1] + ...
                [sliceShift(1), sliceShift(1), sliceShift(2), sliceShift(2)];
end
meets = footprint(:, 1) <= region(1, 2) & footprint(:, 2) >= region(1, 1) & ...
        footprint(:, 3) <= region(2, 2) & footprint(:, 4) >= region(2, 1);
usedTiles = find(onSlice & meets)';

% ---- the region as a canvas of its own ---------------------------------------
subCanvas = canvas;
subCanvas.size(1:2) = [regionH, regionW];
subCanvas.tilePlacement = placement(usedTiles, :) - [offsetYX, 0];
if hasTforms
    subCanvas.tforms = canvas.tforms(usedTiles);
    for k = 1:numel(usedTiles)
        subCanvas.tforms{k}(1:2, 3) = subCanvas.tforms{k}(1:2, 3) - [offsetYX(2); offsetYX(1)];
    end
    % Clipped to the region like planCanvas clips them to the canvas: the
    % kernel only re-clips bounds that a zShift moved.
    shiftedBounds = canvas.tileBounds(usedTiles, :) - ...
        [offsetYX(1), offsetYX(1), offsetYX(2), offsetYX(2)];
    subCanvas.tileBounds = [max(1, shiftedBounds(:, 1)), min(regionH, shiftedBounds(:, 2)), ...
                            max(1, shiftedBounds(:, 3)), min(regionW, shiftedBounds(:, 4))];
end
if isfield(canvas, 'zShifts')
    subCanvas.zShifts = canvas.zShifts;   % per-slice shifts are relative - unchanged
end

subOptions = options;
if strcmp(options.blendMode, 'Overwrite')
    correction = [];
    tileStack = [];
    if isfield(options, 'correction'); correction = options.correction; end
    if isfield(options, 'tileStack');  tileStack  = options.tileStack;  end
    fullStack = utils.stitch.tileDrawOrder(numTiles, correction, tileStack);
    [~, subStack] = ismember(fullStack(ismember(fullStack, usedTiles)), usedTiles);
    subOptions.tileStack = subStack;
    subOptions.correction = [];
end

if isempty(usedTiles)
    regionSlice = cast(options.background, canvas.dataClass) + ...
        zeros(regionH, regionW, canvas.size(4), canvas.dataClass);
    return;
end
regionSlice = utils.stitch.fuseSliceComposite(layout(usedTiles), subCanvas, zGlobal, 1, ...
    @(k) readerFcn(usedTiles(k)), subOptions);
end
