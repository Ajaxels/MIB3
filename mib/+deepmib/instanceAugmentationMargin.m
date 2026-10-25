function margin = instanceAugmentationMargin(augOpt, patchSize)
% INSTANCEAUGMENTATIONMARGIN - Margin around a 2D instance training patch that the geometric augmentations need.
%
% Syntax:
%   .. code-block:: matlab
%
%      margin = deepmib.instanceAugmentationMargin(augOpt, patchSize)
%
% Rotation, scaling and shear of a patch bring pixels from outside the patch into it; without
% them the corners of the warped patch are filled with ``AugOpt2D.FillValue``, which the
% network then learns as background. deepmib.readInstancePatch therefore reads the training
% patch with this margin of real image around it, deepmib.augmentInstanceData2D warps the
% larger patch and crops its centre back to ``patchSize``. The margin is the worst case over
% every combination of the enabled geometric augmentations, each at either end of its range
% (rotation sampled across its range), applied in the order of ``augOpt.Aug2DFuncNames`` - the
% order deepmib.augmentInstanceData2D applies them in. For every combination, and for every
% tail of it, the corners of the cropped patch are traced back through the inverse
% transforms; the margin covers the largest distance they reach. Only the convex hull of the
% traced points is kept after each step: the transforms are linear about the patch centre,
% so the hull holds the extreme points of every later step too.
%
% Rotation and shear ranges are taken together with their negatives, so the result does not
% depend on the sign convention of randomAffine2d. Reflections leave the extent unchanged.
% 90-degree rotations swap height and width, so a non-square patch gets enough margin to be
% cropped back to its own orientation. 2 pixels are added for the cubic interpolation kernel.
%
% Input Arguments:
%   - **augOpt** - struct as passed to deepmib.augmentInstanceData2D:
%
%     - ``.AugOpt2D`` - augmentation settings with ``.Min``/``.Max`` per augmentation
%     - ``.Aug2DFuncNames`` - cell array with names of the enabled augmentations
%
%   - **patchSize** - ``[height width]`` of the training patch
%
% Output Arguments:
%   - **margin** - [double] number of pixels to add on every side of the patch; 0 when no
%     geometric augmentation that moves pixels across the patch edge is enabled
%
% **Example** - a 256 x 256 patch rotated by up to 10 degrees:
%
%   .. code-block:: matlab
%
%      augOpt.AugOpt2D.RandRotation = struct('Min', -10, 'Max', 10);
%      augOpt.Aug2DFuncNames = {'RandRotation'};
%      margin = deepmib.instanceAugmentationMargin(augOpt, [256 256]);   % 23

halfSize = [patchSize(2) patchSize(1)] / 2;     % [x y] about the patch centre
points = [-1 -1; -1 1; 1 -1; 1 1] .* halfSize;
maxExtent = halfSize;
movesPixels = false;

% from the last applied transform back to the first: the source of an output point is the
% inverse transform of it; the identity stands for a transform that did not fire
names = augOpt.Aug2DFuncNames;
for nameId = numel(names):-1:1
    inverseMatrices = localInverseMatrices(names{nameId}, augOpt.AugOpt2D);
    if isempty(inverseMatrices); continue; end
    tracedPoints = points;
    for matrixId = 1:numel(inverseMatrices)
        tracedPoints = [tracedPoints; points * inverseMatrices{matrixId}']; %#ok<AGROW>
    end
    hullIndices = convhull(tracedPoints(:, 1), tracedPoints(:, 2));
    points = tracedPoints(unique(hullIndices), :);
    maxExtent = max(maxExtent, max(abs(points), [], 1));
    movesPixels = true;
end

if ~movesPixels
    margin = 0;
    return;
end
% a 90-degree rotation swaps the axes, so both sides get the larger of the two needs
margin = ceil(max(maxExtent) - min(halfSize)) + 2;
end

% -------------------------------------------------------------------------------------
function inverseMatrices = localInverseMatrices(name, augmentationSettings)
% inverse linear maps [x y] for the extreme settings of one augmentation; empty when the
% augmentation does not move pixels across the patch edge
inverseMatrices = {};
switch name
    case 'Rotation90'
        inverseMatrices = {[0 -1; 1 0], [0 1; -1 0]};
    case 'ReflectedRotation90'
        inverseMatrices = {[0 1; 1 0]};
    case 'RandRotation'
        range = [augmentationSettings.RandRotation.Min augmentationSettings.RandRotation.Max];
        angles = unique([linspace(range(1), range(2), 25), -linspace(range(1), range(2), 25)]);
        inverseMatrices = arrayfun(@(angle) [cosd(angle) -sind(angle); sind(angle) cosd(angle)], ...
            angles, 'UniformOutput', false);
    case 'RandScale'
        scales = [augmentationSettings.RandScale.Min augmentationSettings.RandScale.Max];
        inverseMatrices = arrayfun(@(scale) eye(2) / scale, scales, 'UniformOutput', false);
    case 'RandXScale'
        scales = [augmentationSettings.RandXScale.Min augmentationSettings.RandXScale.Max];
        inverseMatrices = arrayfun(@(scale) diag([1 / scale, 1]), scales, 'UniformOutput', false);
    case 'RandYScale'
        scales = [augmentationSettings.RandYScale.Min augmentationSettings.RandYScale.Max];
        inverseMatrices = arrayfun(@(scale) diag([1, 1 / scale]), scales, 'UniformOutput', false);
    case 'RandXShear'
        angles = [augmentationSettings.RandXShear.Min augmentationSettings.RandXShear.Max];
        angles = unique([angles, -angles]);
        inverseMatrices = arrayfun(@(angle) [1 tand(angle); 0 1], angles, 'UniformOutput', false);
    case 'RandYShear'
        angles = [augmentationSettings.RandYShear.Min augmentationSettings.RandYShear.Max];
        angles = unique([angles, -angles]);
        inverseMatrices = arrayfun(@(angle) [1 0; tand(angle) 1], angles, 'UniformOutput', false);
end
end
