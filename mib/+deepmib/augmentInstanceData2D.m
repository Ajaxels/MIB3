function dataOut = augmentInstanceData2D(dataIn, options)
% AUGMENTINSTANCEDATA2D - Augment a 2D instance-segmentation observation for SOLOv2 training.
%
% Syntax:
%   .. code-block:: matlab
%
%      dataOut = deepmib.augmentInstanceData2D(dataIn, options)
%
% Applies the augmentations enabled in ``options.AugOpt2D`` to a single instance
% observation. Geometric transforms (reflections, 90/arbitrary rotation, scale, shear)
% are applied identically to the image and every instance mask; the bounding boxes are
% then recomputed from the warped masks so that boxes, masks and labels stay in sync.
% Intensity/colour augmentations (noise, blur, hue/saturation/brightness/contrast
% jitter) are applied to the image only.
%
% Used as a datastore transform in mibDeepController.startTrainingInstances:
%   ``labelsDS = transform(labelsDS, @(d)deepmib.augmentInstanceData2D(d, options));``
%
% For StarDist (controllers.MibDeep.startTrainingStarDist) the observation is the ``1×3``
% label-map form of deepmib.readInstancePatch: the instance label map goes through the same
% geometric transforms as the image, with nearest interpolation so the ids survive, and is
% returned as a label map again; the image keeps its channel count. The targets are computed
% afterwards from the warped label map (deepmib.stardist.computeTargets), because rotation and
% scaling change the ray distances.
%
% Input Arguments:
%   - **dataIn** - ``1×4`` cell as returned by deepmib.matReadInstanceLabels:
%
%     - ``dataIn{1}`` - image ``[H×W×3]``
%     - ``dataIn{2}`` - bounding boxes ``[M×4]`` in ``[x y width height]`` format
%     - ``dataIn{3}`` - labels ``[M×1 categorical]``
%     - ``dataIn{4}`` - instance masks ``[H×W×M logical]``
%
%     or the ``1×3`` StarDist cell ``{image HxWxC, labelMap HxW, normValues 2xC}``
%
%   - **options** - struct with augmentation settings:
%
%     - ``.AugOpt2D`` - copy of ``mibDeepController.AugOpt2D`` (per-augmentation
%       ``.Min``/``.Max`` limits plus global ``.Fraction`` and ``.FillValue``)
%     - ``.Aug2DFuncNames`` - cell array with names of enabled augmentations
%     - ``.Aug2DFuncProbability`` - matching per-augmentation trigger probabilities
%     - ``.patchSize`` - *optional* ``[height width]`` of the training patch. An observation
%       larger than it was read with a margin (``.margin`` of deepmib.readInstancePatch, sized
%       by deepmib.instanceAugmentationMargin): after the transforms its centre is cropped to
%       this size, also when no augmentation fired. Rotation, scaling and shear then fill the
%       patch from the real image around it, and ``FillValue`` remains only where the image
%       itself ends. A 90-degree rotation of a non-square patch is cropped back to the
%       original orientation as well.
%     - ``.minObjectArea`` - *optional* minimum object area (pixels) kept after that crop,
%       SOLOv2 only, as in deepmib.readInstancePatch; default 0
%
% Output Arguments:
%   - **dataOut** - ``1×4`` cell with the augmented ``{image, boxes, labels, masks}``;
%     instances whose mask vanished after a geometric transform are dropped. For the
%     StarDist form, ``1×3`` ``{image, labelMap, normValues}`` with ``normValues`` unchanged.

global mibDeepTrainingProgressStruct

% Once a stop has been requested, the trainer no longer trains on anything coming through
% this transform - it only prefetches a mini-batch per remaining epoch and throws it away
% (see deepmib.readInstancePatch for the full description). Geometric warping of the
% placeholder observation those prefetches carry is pure waste, so the augmentations are
% skipped; the crop below still runs, for a patch read with a margin just before the stop.
spinDown = isfield(mibDeepTrainingProgressStruct, 'spinDownActive') && mibDeepTrainingProgressStruct.spinDownActive;

labelMapMode = numel(dataIn) == 3;     % StarDist: {image, labelMap, normValues}
image = dataIn{1};
if labelMapMode
    % the label map goes through the geometric transforms like a single mask slice
    % (nearest interpolation); there are no boxes to keep in sync
    masks = dataIn{2};
    boxes = [];
    labels = [];
else
    boxes = dataIn{2};
    labels = dataIn{3};
    masks = dataIn{4};
    % dynamically convert grayscale to RGB (SOLOv2 backbone expects 3 channels)
    if size(image, 3) == 1
        image = repmat(image, [1, 1, 3]);
    end
end

% the augmentations that fire for this observation: none, unless the global fraction gate
% passes; then each by its probability
augList = {};
numAugFunc = numel(options.Aug2DFuncNames);
if ~spinDown && numAugFunc > 0 && randi(100, 1)/100 <= options.AugOpt2D.Fraction
    randVector = rand([2, numAugFunc]);
    randVector(2, :) = options.Aug2DFuncProbability;
    [~, index] = min(randVector, [], 1);
    augList = options.Aug2DFuncNames(index == 1);
end
geometricApplied = false;   % whether the mask geometry changed (-> recompute boxes)

for augId = 1:numel(augList)
    switch augList{augId}
        case 'RandXReflection'
            image = fliplr(image);
            masks = fliplr(masks);
            geometricApplied = true;
        case 'RandYReflection'
            image = flipud(image);
            masks = flipud(masks);
            geometricApplied = true;
        case 'Rotation90'
            if randi(2) == 1
                image = rot90(image);       masks = rot90(masks);
            else
                image = rot90(image, 3);    masks = rot90(masks, 3);
            end
            geometricApplied = true;
        case 'ReflectedRotation90'
            image = rot90(fliplr(image));
            masks = rot90(fliplr(masks));
            geometricApplied = true;
        case 'RandRotation'
            angle = options.AugOpt2D.RandRotation.Min + (options.AugOpt2D.RandRotation.Max-options.AugOpt2D.RandRotation.Min)*rand;
            tform = randomAffine2d('Rotation', [angle angle]);
            [image, masks] = i_warpImageAndMasks(image, masks, tform, options.AugOpt2D.FillValue);
            geometricApplied = true;
        case 'RandScale'
            sc = exp((log(options.AugOpt2D.RandScale.Max) - log(options.AugOpt2D.RandScale.Min))*rand + log(options.AugOpt2D.RandScale.Min));
            tform = randomAffine2d('Scale', [sc sc]);
            [image, masks] = i_warpImageAndMasks(image, masks, tform, options.AugOpt2D.FillValue);
            geometricApplied = true;
        case 'RandXScale'
            sc = exp((log(options.AugOpt2D.RandXScale.Max) - log(options.AugOpt2D.RandXScale.Min))*rand + log(options.AugOpt2D.RandXScale.Min));
            tform = affine2d([sc 0 0; 0 1 0; 0 0 1]);
            [image, masks] = i_warpImageAndMasks(image, masks, tform, options.AugOpt2D.FillValue);
            geometricApplied = true;
        case 'RandYScale'
            sc = exp((log(options.AugOpt2D.RandYScale.Max) - log(options.AugOpt2D.RandYScale.Min))*rand + log(options.AugOpt2D.RandYScale.Min));
            tform = affine2d([1 0 0; 0 sc 0; 0 0 1]);
            [image, masks] = i_warpImageAndMasks(image, masks, tform, options.AugOpt2D.FillValue);
            geometricApplied = true;
        case 'RandXShear'
            sh = options.AugOpt2D.RandXShear.Min + (options.AugOpt2D.RandXShear.Max-options.AugOpt2D.RandXShear.Min)*rand;
            tform = randomAffine2d('XShear', [sh sh]);
            [image, masks] = i_warpImageAndMasks(image, masks, tform, options.AugOpt2D.FillValue);
            geometricApplied = true;
        case 'RandYShear'
            sh = options.AugOpt2D.RandYShear.Min + (options.AugOpt2D.RandYShear.Max-options.AugOpt2D.RandYShear.Min)*rand;
            tform = randomAffine2d('YShear', [sh sh]);
            [image, masks] = i_warpImageAndMasks(image, masks, tform, options.AugOpt2D.FillValue);
            geometricApplied = true;
        case 'GaussianNoise'
            v = options.AugOpt2D.GaussianNoise.Min + (options.AugOpt2D.GaussianNoise.Max-options.AugOpt2D.GaussianNoise.Min)*rand;
            image = imnoise(image, 'gaussian', 0, v);
        case 'PoissonNoise'
            image = imnoise(image, 'poisson');
        case 'HueJitter'
            if size(image, 3) == 3
                v = options.AugOpt2D.HueJitter.Min + (options.AugOpt2D.HueJitter.Max-options.AugOpt2D.HueJitter.Min)*rand;
                image = jitterColorHSV(image, 'Hue', [v v]);
            end
        case 'SaturationJitter'
            if size(image, 3) == 3
                v = options.AugOpt2D.SaturationJitter.Min + (options.AugOpt2D.SaturationJitter.Max-options.AugOpt2D.SaturationJitter.Min)*rand;
                image = jitterColorHSV(image, 'Saturation', [v v]);
            end
        case 'BrightnessJitter'
            v = options.AugOpt2D.BrightnessJitter.Min + (options.AugOpt2D.BrightnessJitter.Max-options.AugOpt2D.BrightnessJitter.Min)*rand;
            if size(image, 3) == 3
                image = jitterColorHSV(image, 'Brightness', [v v]);
            else
                image = image + v*255;
            end
        case 'ContrastJitter'
            v = options.AugOpt2D.ContrastJitter.Min + (options.AugOpt2D.ContrastJitter.Max-options.AugOpt2D.ContrastJitter.Min)*rand;
            if size(image, 3) == 3
                image = jitterColorHSV(image, 'Contrast', [v v]);
            else
                image = image.*v;
            end
        case 'ImageBlur'
            v = options.AugOpt2D.ImageBlur.Min + (options.AugOpt2D.ImageBlur.Max-options.AugOpt2D.ImageBlur.Min)*rand;
            image = imgaussfilt(image, v);
    end
end

if isfield(options, 'patchSize') && all(size(image, [1 2]) >= options.patchSize) ...
        && any(size(image, [1 2]) > options.patchSize)
    % the patch was read with a margin (deepmib.readInstancePatch): keep its centre, which
    % the warps above filled from real image instead of FillValue. Without a margin, a
    % 90-degree rotation of a non-square patch is narrower on one side and stays uncropped
    rows = floor((size(image, 1) - options.patchSize(1)) / 2) + (1:options.patchSize(1));
    cols = floor((size(image, 2) - options.patchSize(2)) / 2) + (1:options.patchSize(2));
    image = image(rows, cols, :);
    masks = masks(rows, cols, :);
    if ~labelMapMode
        % drop the remnants the crop leaves, as readInstancePatch does after its own crop
        minObjectArea = 0;
        if isfield(options, 'minObjectArea'); minObjectArea = options.minObjectArea; end
        keep = reshape(sum(masks, [1 2]), [], 1) >= minObjectArea;
        masks = masks(:, :, keep);
        labels = labels(keep);
        geometricApplied = true;
    end
end

if geometricApplied && ~labelMapMode
    % boxes are now stale; recompute from the warped masks and drop vanished instances
    boxes = deepmib.getBoxFromMask(masks);
    keep = ~any(isnan(boxes), 2);
    boxes = boxes(keep, :);
    labels = labels(keep);
    masks = masks(:, :, keep);
end

dataOut = localPackOutput(dataIn, labelMapMode, image, boxes, labels, masks);
end

function [image, masks] = i_warpImageAndMasks(image, masks, tform, fillValue)
% apply the same affine transform to the image (cubic) and every mask slice (nearest)
outputView = affineOutputView([size(image, 1), size(image, 2)], tform);
image = imwarp(image, tform, 'cubic', 'OutputView', outputView, 'FillValues', fillValue);
if size(masks, 3) > 0
    masks = imwarp(masks, tform, 'nearest', 'OutputView', outputView, 'FillValues', 0);
else
    % background-only patch (no instances): imwarp rejects an empty array, so skip the
    % mask warp and just keep an empty stack sized to match the warped image
    masks = false([size(image, 1), size(image, 2), 0]);
end
end

function dataOut = localPackOutput(dataIn, labelMapMode, image, boxes, labels, masks)
% SOLOv2: {image, boxes, labels, masks}; StarDist: {image, labelMap, normValues}
if labelMapMode
    dataOut = {image, masks, dataIn{3}};
else
    dataOut = {image, boxes, labels, masks};
end
end
