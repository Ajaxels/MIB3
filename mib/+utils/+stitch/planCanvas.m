function canvas = planCanvas(layout, positions, options)
% PLANCANVAS - Compute the fused mosaic canvas from solved tile positions.
%
% Syntax:
%   .. code-block:: matlab
%
%      canvas = utils.stitch.planCanvas(layout, positions)
%      canvas = utils.stitch.planCanvas(layout, positions, options)
%
% Turns the fractional solved origins into an integer placement plan for the
% output mosaic: it shifts all origins so the minimum origin lands at pixel 1,
% rounds to integer tile placements (keeping the fractional remainder as a
% per-tile subpixel residual for later resampled placement), and derives the
% total canvas size and physical bounding box. All three axes use the SOLVED
% positions — ``positions(:,3)`` is a slice coordinate, so overlapping or
% jittered Z-stacks land where the global solve put them (tiles within a 2D
% layer share one z by construction of the within-layer dz constraints).
%
% Input Arguments:
%   - **layout** — [struct array] tile layout with ``.tileSize`` (``[H W D C]``),
%     ``.zLayer`` and ``.dataClass``.
%   - **positions** — [N x 3 double] solved ``[y x z]`` origins (fractional).
%   - **options** *(optional)* — struct with fields:
%
%     - ``.pixSize`` — [struct] ``.x .y .z`` physical voxel size (default: 1 µm iso)
%     - ``.numChannels`` — [double] output channel count (default: from ``tileSize(4)``)
%     - ``.numFrames`` — [double] output time frames (default: ``1``)
%
% Output Arguments:
%   - **canvas** — [struct] with fields:
%
%     - ``.size`` — [1x5] ``[H W Z C T]`` output dimensions
%     - ``.tilePlacement`` — [N x 3] integer 1-based ``[y x z]`` origins
%     - ``.subpixelResidual`` — [N x 3] fractional part discarded by rounding
%     - ``.dataClass`` — [char] numeric class of the mosaic
%     - ``.boundingBox`` — [1x6] ``[xmin xmax ymin ymax zmin zmax]`` physical extent
%     - ``.pixSize`` — [struct] the pixel size used
%     - ``.zLayers`` — [vector] sorted distinct z-layer ids
%
% **Example** — plan a canvas at 20 nm isotropic:
%
%   .. code-block:: matlab
%
%      opts.pixSize = struct('x', 0.02, 'y', 0.02, 'z', 0.02);
%      canvas = utils.stitch.planCanvas(layout, positions, opts);
%      fprintf('Canvas: %d x %d x %d\n', canvas.size(1), canvas.size(2), canvas.size(3));

if nargin < 3; options = struct(); end
if ~isfield(options, 'pixSize') || isempty(options.pixSize)
    options.pixSize = struct('x', 1, 'y', 1, 'z', 1);
end
pixSize = options.pixSize;
if ~isfield(pixSize, 'x'); pixSize.x = 1; end
if ~isfield(pixSize, 'y'); pixSize.y = 1; end
if ~isfield(pixSize, 'z'); pixSize.z = 1; end

nTiles = numel(layout);

tileSizes = reshape([layout.tileSize], 4, nTiles)';   % N x 4 [H W D C]
tileH = tileSizes(:, 1);
tileW = tileSizes(:, 2);
tileD = tileSizes(:, 3);
tileC = tileSizes(:, 4);

zLayerIds = arrayfun(@(t) t.zLayer, layout);
distinctLayers = unique(zLayerIds(:))';

% ---- placement: shift solved origins so the min origin becomes pixel/slice 1 --
% Round to integer placements; keep the fractional remainder as subpixel residual.
minY = min(positions(:, 1));
minX = min(positions(:, 2));
minZ = min(positions(:, 3));

placementY = positions(:, 1) - minY + 1;
placementX = positions(:, 2) - minX + 1;
placementZ = positions(:, 3) - minZ + 1;

intPlacementY = round(placementY);
intPlacementX = round(placementX);
intPlacementZ = round(placementZ);

subResY = placementY - intPlacementY;
subResX = placementX - intPlacementX;
subResZ = placementZ - intPlacementZ;

tilePlacement = [intPlacementY, intPlacementX, intPlacementZ];
subpixelResidual = [subResY, subResX, subResZ];

% ---- total canvas extent -----------------------------------------------------
H = max(intPlacementY + tileH - 1);
W = max(intPlacementX + tileW - 1);
Z = max(intPlacementZ + tileD - 1);

if isfield(options, 'numChannels') && ~isempty(options.numChannels)
    C = options.numChannels;
else
    C = max(tileC);
end
if isfield(options, 'numFrames') && ~isempty(options.numFrames)
    T = options.numFrames;
else
    T = 1;
end

if isfield(layout, 'dataClass') && ~isempty(layout(1).dataClass)
    dataClass = layout(1).dataClass;
else
    dataClass = 'uint8';
end

% ---- physical bounding box [xmin xmax ymin ymax zmin zmax] --------------------
% Origins are top-left 1-based pixels; physical extent spans (dim-1)*pixSize.
boundingBox = [0, (W - 1) * pixSize.x, ...
               0, (H - 1) * pixSize.y, ...
               0, (Z - 1) * pixSize.z];

canvas = struct();
canvas.size             = [H, W, Z, C, T];
canvas.tilePlacement    = tilePlacement;
canvas.subpixelResidual = subpixelResidual;
canvas.dataClass        = dataClass;
canvas.boundingBox      = boundingBox;
canvas.pixSize          = pixSize;
canvas.zLayers          = distinctLayers;
end
