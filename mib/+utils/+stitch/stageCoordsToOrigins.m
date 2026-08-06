function [nomOrigin, zLayer] = stageCoordsToOrigins(stageXYZum, pixSize, options)
% STAGECOORDSTOORIGINS - Convert physical stage coordinates to tile pixel origins.
%
% Syntax:
%   .. code-block:: matlab
%
%      [nomOrigin, zLayer] = utils.stitch.stageCoordsToOrigins(stageXYZum, pixSize)
%      [nomOrigin, zLayer] = utils.stitch.stageCoordsToOrigins(stageXYZum, pixSize, options)
%
% Pure (Bio-Formats-free, headless-testable) core of the ``'Bio-Formats metadata'``
% layout source. Maps per-tile physical stage positions (micrometres) onto the
% 1-based pixel / slice ``nomOrigin`` frame used by the rest of the stitcher, and
% ranks distinct Z levels into ``zLayer`` indices exactly like
% :func:`utils.stitch.buildLayoutPositionFile`.
%
% Conversion per axis: ``origin = stage / pixelSize``, then the whole set is
% shifted so its minimum lands on ``1`` (X, Y kept fractional for the sub-pixel
% solver; Z rounded to whole slices). Stage X is taken to increase with image
% columns and stage Y with image rows; set ``options.flipY``/``options.flipX``
% when the microscope's stage axis runs opposite to the pixel axis (a common
% difference between vendors).
%
% Input Arguments:
%   - **stageXYZum** - [N×3 double] per-tile ``[X Y Z]`` stage position in µm.
%   - **pixSize** - struct with ``.x``, ``.y``, ``.z`` (µm per pixel / per slice).
%     A non-positive ``.z`` collapses all tiles to a single Z layer.
%   - **options** *(optional)* - struct with fields:
%
%     - ``.flipX`` - [logical] negate X before conversion (default: ``false``)
%     - ``.flipY`` - [logical] negate Y before conversion (default: ``false``)
%
% Output Arguments:
%   - **nomOrigin** - [N×3 double] ``[y x z]`` 1-based origins; ``z`` in slices.
%   - **zLayer** - [N×1 double] 1..K rank of each tile's distinct Z origin.
%
% **Example** - two tiles 100 µm apart at 0.5 µm/px → 200 px apart:
%
%   .. code-block:: matlab
%
%      pixSize = struct('x', 0.5, 'y', 0.5, 'z', 1);
%      o = utils.stitch.stageCoordsToOrigins([0 0 0; 100 0 0], pixSize);
%      % o(2,2) - o(1,2) == 200

if nargin < 3; options = struct(); end
if ~isfield(options, 'flipX'); options.flipX = false; end
if ~isfield(options, 'flipY'); options.flipY = false; end

stageX = stageXYZum(:, 1);
stageY = stageXYZum(:, 2);
stageZ = stageXYZum(:, 3);
if options.flipX; stageX = -stageX; end
if options.flipY; stageY = -stageY; end

originX = stageX / pixSize.x;
originY = stageY / pixSize.y;
originX = originX - min(originX) + 1;   % 1-based, fractional kept for the solver
originY = originY - min(originY) + 1;

if isfield(pixSize, 'z') && pixSize.z > 0
    originZ = stageZ / pixSize.z;
else
    originZ = zeros(size(stageZ));
end
originZ = round(originZ - min(originZ)) + 1;   % whole 1-based slice coordinate

nomOrigin = [originY, originX, originZ];

% Rank distinct Z origins into 1..K layer indices (ascending), matching the
% position-file source so findNeighborPairs sees the same layer structure.
uniqueZ  = sort(unique(originZ));
zLayerMap = dictionary(uniqueZ, (1:numel(uniqueZ))');
zLayer = zLayerMap(originZ);
end
