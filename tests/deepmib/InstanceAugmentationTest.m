classdef InstanceAugmentationTest < matlab.unittest.TestCase
    % INSTANCEAUGMENTATIONTEST - geometric augmentation of 2D instance training patches without fill.
    %
    % deepmib.readInstancePatch reads a training patch with the margin from
    % deepmib.instanceAugmentationMargin, deepmib.augmentInstanceData2D warps it and crops it back.
    % On an image of one constant value, any FillValue pixel left inside the cropped patch would
    % show up as a second value, so a run of strong random augmentations checks that the margin
    % is large enough for every combination they draw.

    properties (Constant)
        ImageValue = uint8(100)
        FillValue = 255
        PatchSize = [32 48]
    end

    methods (TestClassSetup)
        function addMibToPath(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})
        function marginOfRotation(testCase)
            augOpt.AugOpt2D.RandRotation = struct('Min', -10, 'Max', 10);
            augOpt.Aug2DFuncNames = {'RandRotation'};
            % a 256 x 256 square rotated by 10 degrees spans 256 * (cos 10 + sin 10) = 296.6 px
            expected = ceil(256 * (cosd(10) + sind(10)) / 2 - 128) + 2;
            testCase.verifyEqual(deepmib.instanceAugmentationMargin(augOpt, [256 256]), expected);
        end

        function noMarginWithoutWarps(testCase)
            augOpt.AugOpt2D = struct();
            augOpt.Aug2DFuncNames = {'RandXReflection', 'RandYReflection', 'GaussianNoise', 'BrightnessJitter'};
            testCase.verifyEqual(deepmib.instanceAugmentationMargin(augOpt, [64 64]), 0);
        end

        function marginTurnsNonSquarePatch(testCase)
            augOpt.AugOpt2D = struct();
            augOpt.Aug2DFuncNames = {'Rotation90'};
            % 32 x 48 turned by 90 degrees must still hold a 32 x 48 centre: 8 px per side, + 2
            testCase.verifyEqual(deepmib.instanceAugmentationMargin(augOpt, [32 48]), 10);
        end

        function labelMapPatchesHoldNoFill(testCase)
            [filename, options, augOpt] = testCase.prepareData('labelMap');
            for drawId = 1:150
                patch = deepmib.readInstancePatch(filename, options);
                augmented = deepmib.augmentInstanceData2D(patch, augOpt);
                testCase.verifySize(augmented{1}, testCase.PatchSize);
                testCase.verifySize(augmented{2}, testCase.PatchSize);
                testCase.assertTrue(all(augmented{1}(:) == testCase.ImageValue), ...
                    sprintf('fill inside the patch at draw %d', drawId));
            end
        end

        function solov2PatchesHoldNoFill(testCase)
            [filename, options, augOpt] = testCase.prepareData('solov2');
            for drawId = 1:50
                patch = deepmib.readInstancePatch(filename, options);
                augmented = deepmib.augmentInstanceData2D(patch, augOpt);
                [image, boxes, labels, masks] = augmented{:};
                testCase.verifySize(image, [testCase.PatchSize 3]);
                testCase.verifyEqual(size(masks, [1 2]), testCase.PatchSize);
                testCase.verifyEqual([size(boxes, 1), numel(labels)], [size(masks, 3), size(masks, 3)]);
                testCase.verifyTrue(all(reshape(sum(masks, [1 2]), [], 1) >= options.minObjectArea), ...
                    'remnants below minObjectArea are dropped after the crop');
                testCase.assertTrue(all(image(:) == testCase.ImageValue), ...
                    sprintf('fill inside the patch at draw %d', drawId));
            end
        end

        function noAugmentationStillCrops(testCase)
            [filename, options, augOpt] = testCase.prepareData('labelMap');
            augOpt.AugOpt2D.Fraction = 0;       % no observation is augmented
            patch = deepmib.readInstancePatch(filename, options);
            testCase.verifySize(patch{1}, testCase.PatchSize + 2 * options.margin);
            augmented = deepmib.augmentInstanceData2D(patch, augOpt);
            testCase.verifySize(augmented{1}, testCase.PatchSize);
            centre = patch{2}(options.margin + (1:testCase.PatchSize(1)), options.margin + (1:testCase.PatchSize(2)));
            testCase.verifyEqual(augmented{2}, centre, 'the crop is the window picked by the reader');
        end

        function marginPastImageBorderIsFilled(testCase)
            [filename, options] = testCase.prepareData('labelMap');
            options.objectFraction = 0;         % uniform-random windows, also at the image border
            options.patchSeed = 1;
            options.margin = 500;               % larger than the image
            patch = deepmib.readInstancePatch(filename, options);
            testCase.verifyTrue(any(patch{1}(:) == testCase.FillValue), 'outside the image: FillValue');
            testCase.verifyTrue(any(patch{1}(:) == testCase.ImageValue), 'inside the image: the image');
        end
    end

    methods (Access = private)
        function [filename, options, augOpt] = prepareData(testCase, outputFormat)
            % constant image with a few objects far from its border, and strong augmentations
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            imageSize = [400 420];
            imwrite(repmat(testCase.ImageValue, imageSize), fullfile(folder, 'image.tif'));
            imageFilename = 'image.tif';
            instanceLabelMap = zeros(imageSize, 'uint16');
            instanceLabelMap(190:200, 190:205) = 1;
            instanceLabelMap(202:215, 200:212) = 2;
            instanceLabelMap(180:188, 215:225) = 3;
            filename = fullfile(folder, 'labels.mat');
            save(filename, 'imageFilename', 'instanceLabelMap');

            augOpt.AugOpt2D = struct('Fraction', 1, 'FillValue', testCase.FillValue, ...
                'RandRotation', struct('Min', -45, 'Max', 45), ...
                'RandScale', struct('Min', 0.7, 'Max', 1.3), ...
                'RandXScale', struct('Min', 0.8, 'Max', 1.2), ...
                'RandYScale', struct('Min', 0.8, 'Max', 1.2), ...
                'RandXShear', struct('Min', -20, 'Max', 20), ...
                'RandYShear', struct('Min', -20, 'Max', 20));
            augOpt.Aug2DFuncNames = {'RandXReflection', 'Rotation90', 'RandRotation', 'RandScale', ...
                'RandXScale', 'RandYScale', 'RandXShear', 'RandYShear'};
            augOpt.Aug2DFuncProbability = 0.7 * ones(1, numel(augOpt.Aug2DFuncNames));
            augOpt.patchSize = testCase.PatchSize;
            augOpt.minObjectArea = 4;

            options = struct('imageDir', folder, 'patchSize', testCase.PatchSize, 'objectFraction', 1, ...
                'minObjectArea', 4, 'outputFormat', outputFormat, 'normalizePercentiles', [1 99.8], ...
                'getImageOptions', struct('mibBioformatsCheck', false, 'BioFormatsIndices', 1, 'Workflow', '2D Instance'));
            options.margin = deepmib.instanceAugmentationMargin(augOpt, testCase.PatchSize);
            options.fillValue = testCase.FillValue;
            % the objects and every window placed on them stay further than the margin from the border
            testCase.assertLessThan(options.margin, 140, 'test design: the margin stays inside the image');
        end
    end
end
