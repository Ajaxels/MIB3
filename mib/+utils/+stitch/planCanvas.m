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
% When per-tile transforms from :func:`utils.stitch.solveGlobalAffine` are
% passed in ``options.tforms``, the in-plane extent comes from the WARPED tile
% footprints instead: the corner points of every tile are pushed through its
% transform, the union bounding box defines the canvas, and the transforms are
% re-expressed in canvas coordinates (tile-local xy → canvas xy, pixel centres
% at integers) in ``canvas.tforms`` together with each tile's integer output
% bounding box in ``canvas.tileBounds``. The z axis keeps the translation
% placement logic. Without ``options.tforms`` the behaviour is bit-identical to
% the translation-only planner.
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
%     - ``.tforms`` — [N x 1 cell] per-tile 3x3 tile-local→global xy transforms
%       from :func:`utils.stitch.solveGlobalAffine`; enables the warped-footprint
%       plan (default: none — translation placement)
%     - ``.zSliceFixes`` — [K x 3] per-slice mosaic corrections ``[z dy dx]``
%       from the seam inspector's Fix Z: every output slice ``>= z`` shifts
%       in-plane by ``[dy dx]`` (cumulative over rows). Produces
%       ``canvas.zShifts`` and grows the canvas so nothing is clipped
%       (default: none)
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
%     - ``.tforms`` — [N x 1 cell] tile-local→CANVAS xy transforms (only when
%       ``options.tforms`` was given; canvas world frame == intrinsic pixels)
%     - ``.tileBounds`` — [N x 4] integer output bbox ``[y0 y1 x0 x1]`` of each
%       warped tile footprint, clipped to the canvas (only with ``options.tforms``)
%     - ``.zShifts`` — [Z x 2] integer extra ``[dy dx]`` applied to every tile
%       on that output slice by the fusers (only with ``options.zSliceFixes``;
%       baseline-shifted so all entries are >= 0 and fit the grown canvas)
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

useTforms = isfield(options, 'tforms') && ~isempty(options.tforms);

% ---- placement: shift solved origins so the min origin becomes pixel/slice 1 --
% Round to integer placements; keep the fractional remainder as subpixel residual.
minZ = min(positions(:, 3));
placementZ = positions(:, 3) - minZ + 1;
intPlacementZ = round(placementZ);
subResZ = placementZ - intPlacementZ;

if useTforms
    % Warped-footprint plan: the in-plane canvas extent is the union bounding
    % box of every tile's corner points pushed through its transform. The
    % canvas world frame equals its intrinsic pixel frame (centres at integers),
    % so shifting all transforms by (1 - min corner) puts the mosaic at pixel 1.
    cornerMinXY = zeros(nTiles, 2);
    cornerMaxXY = zeros(nTiles, 2);
    for tileIdx = 1:nTiles
        tileTform = double(options.tforms{tileIdx});
        corners = tileTform(1:2, 1:2) * ...
            [1, tileW(tileIdx), 1, tileW(tileIdx); ...
             1, 1, tileH(tileIdx), tileH(tileIdx)] + tileTform(1:2, 3);
        cornerMinXY(tileIdx, :) = min(corners, [], 2)';
        cornerMaxXY(tileIdx, :) = max(corners, [], 2)';
    end
    shiftXY = [1 - min(cornerMinXY(:, 1)); 1 - min(cornerMinXY(:, 2))];

    H = ceil(max(cornerMaxXY(:, 2)) + shiftXY(2));
    W = ceil(max(cornerMaxXY(:, 1)) + shiftXY(1));
    Z = max(intPlacementZ + tileD - 1);

    canvasTforms = cell(nTiles, 1);
    tileBounds = zeros(nTiles, 4);
    tilePlacement = zeros(nTiles, 3);
    subpixelResidual = zeros(nTiles, 3);
    for tileIdx = 1:nTiles
        tileTform = double(options.tforms{tileIdx});
        tileTform(1:2, 3) = tileTform(1:2, 3) + shiftXY;
        canvasTforms{tileIdx} = tileTform;
        tileBounds(tileIdx, :) = [ ...
            max(1, floor(cornerMinXY(tileIdx, 2) + shiftXY(2))), ...
            min(H,  ceil(cornerMaxXY(tileIdx, 2) + shiftXY(2))), ...
            max(1, floor(cornerMinXY(tileIdx, 1) + shiftXY(1))), ...
            min(W,  ceil(cornerMaxXY(tileIdx, 1) + shiftXY(1)))];
        % Placement of tile pixel (1,1) — kept for previews and back-compat.
        origin11 = tileTform(1:2, 1:2) * [1; 1] + tileTform(1:2, 3);
        tilePlacement(tileIdx, :) = [round(origin11(2)), round(origin11(1)), intPlacementZ(tileIdx)];
        subpixelResidual(tileIdx, :) = [origin11(2) - round(origin11(2)), ...
                                        origin11(1) - round(origin11(1)), subResZ(tileIdx)];
    end
else
    minY = min(positions(:, 1));
    minX = min(positions(:, 2));

    placementY = positions(:, 1) - minY + 1;
    placementX = positions(:, 2) - minX + 1;

    intPlacementY = round(placementY);
    intPlacementX = round(placementX);

    subResY = placementY - intPlacementY;
    subResX = placementX - intPlacementX;

    tilePlacement = [intPlacementY, intPlacementX, intPlacementZ];
    subpixelResidual = [subResY, subResX, subResZ];

    % ---- total canvas extent ---------------------------------------------------
    H = max(intPlacementY + tileH - 1);
    W = max(intPlacementX + tileW - 1);
    Z = max(intPlacementZ + tileD - 1);
end

% ---- per-slice mosaic corrections (inspector Fix Z) ---------------------------
% Cumulative [dy dx] per output slice: each fix row [z dy dx] shifts every
% slice >= z. Rounded to integers (keeps the resampling-free placement path),
% baseline-shifted to be non-negative, and the canvas grows by the range so no
% slice is clipped.
zShifts = [];
if isfield(options, 'zSliceFixes') && ~isempty(options.zSliceFixes)
    cumulative = zeros(Z, 2);
    fixRows = options.zSliceFixes;
    for fixIdx = 1:size(fixRows, 1)
        zBoundary = round(fixRows(fixIdx, 1));
        if zBoundary < 1 || zBoundary > Z; continue; end
        cumulative(zBoundary:end, 1) = cumulative(zBoundary:end, 1) + fixRows(fixIdx, 2);
        cumulative(zBoundary:end, 2) = cumulative(zBoundary:end, 2) + fixRows(fixIdx, 3);
    end
    zShifts = round(cumulative) - min(round(cumulative), [], 1);
    if any(zShifts(:) ~= 0)
        H = H + max(zShifts(:, 1));
        W = W + max(zShifts(:, 2));
    else
        zShifts = [];   % uniform shift of ALL slices is a no-op translation
    end
end

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
if useTforms
    canvas.tforms     = canvasTforms;
    canvas.tileBounds = tileBounds;
end
if ~isempty(zShifts)
    canvas.zShifts = zShifts;
end
end
