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
% Input Arguments:
%   - **dataIn** — ``1×4`` cell as returned by deepmib.matReadInstanceLabels:
%
%     - ``dataIn{1}`` — image ``[H×W×3]``
%     - ``dataIn{2}`` — bounding boxes ``[M×4]`` in ``[x y width height]`` format
%     - ``dataIn{3}`` — labels ``[M×1 categorical]``
%     - ``dataIn{4}`` — instance masks ``[H×W×M logical]``
%
%   - **options** — struct with augmentation settings:
%
%     - ``.AugOpt2D`` — copy of ``mibDeepController.AugOpt2D`` (per-augmentation
%       ``.Min``/``.Max`` limits plus global ``.Fraction`` and ``.FillValue``)
%     - ``.Aug2DFuncNames`` — cell array with names of enabled augmentations
%     - ``.Aug2DFuncProbability`` — matching per-augmentation trigger probabilities
%
% Output Arguments:
%   - **dataOut** — ``1×4`` cell with the augmented ``{image, boxes, labels, masks}``;
%     instances whose mask vanished after a geometric transform are dropped.

image = dataIn{1};
boxes = dataIn{2};
labels = dataIn{3};
masks = dataIn{4};

% dynamically convert grayscale to RGB (SOLOv2 backbone expects 3 channels)
if size(image, 3) == 1
    image = repmat(image, [1, 1, 3]);
end

numAugFunc = numel(options.Aug2DFuncNames);
if numAugFunc == 0
    dataOut = {image, boxes, labels, masks};
    return;
end

% global fraction gate: only a fraction of observations get augmented
if randi(100, 1)/100 > options.AugOpt2D.Fraction
    dataOut = {image, boxes, labels, masks};
    return;
end

% pick which augmentations fire for this observation, based on their probabilities
randVector = rand([2, numAugFunc]);
randVector(2, :) = options.Aug2DFuncProbability;
[~, index] = min(randVector, [], 1);
augFuncIndeces = find(index == 1);
if isempty(augFuncIndeces)
    dataOut = {image, boxes, labels, masks};
    return;
end

augList = options.Aug2DFuncNames(augFuncIndeces);
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

if geometricApplied
    % boxes are now stale; recompute from the warped masks and drop vanished instances
    boxes = deepmib.getBoxFromMask(masks);
    keep = ~any(isnan(boxes), 2);
    boxes = boxes(keep, :);
    labels = labels(keep);
    masks = masks(:, :, keep);
end

dataOut = {image, boxes, labels, masks};
end

function [image, masks] = i_warpImageAndMasks(image, masks, tform, fillValue)
% apply the same affine transform to the image (cubic) and every mask slice (nearest)
outputView = affineOutputView([size(image, 1), size(image, 2)], tform);
image = imwarp(image, tform, 'cubic', 'OutputView', outputView, 'FillValues', fillValue);
masks = imwarp(masks, tform, 'nearest', 'OutputView', outputView, 'FillValues', 0);
end
