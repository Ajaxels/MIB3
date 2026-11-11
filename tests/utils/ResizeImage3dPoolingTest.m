classdef ResizeImage3dPoolingTest < matlab.unittest.TestCase
% RESIZEIMAGE3DPOOLINGTEST - Tests for the 'max pooling' and 'min pooling' methods.
%
% Pooling was added to utils.resizeImage3d so that a membrane probability map
% (and its labels) can be downsampled without losing structures thinner than
% the block. What is tested:
%
%   - the function against an independent block reduction (reshape + max) for
%     integer factors, images and labels;
%   - the block rule for a non-integer factor and for an enlarged axis, where
%     the expected values are worked out on paper;
%   - the contract: class kept, NaN ignored, algorithm ignored, 2D input;
%   - the dialog path (controllers.ResampleDataset in batch mode) for the
%     image, a 63-material model and a 65535 instance model.
%
% See also: utils.resizeImage3d, controllers.ResampleDataset

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Static, Access = private)

        function reduced = blockReduce(volume, factorY, factorX, poolFunction)
            % independent reference: integer XY factors, Z unchanged
            [height, width, depth] = size(volume, 1:3);
            blocks = reshape(volume, factorY, height / factorY, factorX, width / factorX, depth);
            reduced = poolFunction(poolFunction(blocks, [], 1), [], 3);
            reduced = reshape(reduced, height / factorY, width / factorX, depth);
        end

        function options = poolingOptions(method, newSize)
            options = struct('method', method, 'height', newSize(1), 'width', newSize(2), ...
                'depth', newSize(3), 'showWaitbar', 0);
        end

        function BatchOpt = resampleOptions(newSize, imageMethod, labelsMethod)
            BatchOpt = struct();
            BatchOpt.ResamplingMode = {'Dimensions'};
            BatchOpt.ResamplingMethod = {imageMethod};
            BatchOpt.LabelsresampleDropDown = {labelsMethod};
            BatchOpt.DimensionY = num2str(newSize(1));
            BatchOpt.DimensionX = num2str(newSize(2));
            BatchOpt.DimensionZ = num2str(newSize(3));
            BatchOpt.showWaitbar = false;
        end
    end

    methods (Test, TestTags = {'Unit'})

        function integerFactorMatchesBlockMaximumAndMinimum(testCase)
            rng(1, 'twister');
            volume = uint8(randi(255, [12 18 5]));

            maxPooled = utils.resizeImage3d(volume, [], ResizeImage3dPoolingTest.poolingOptions('max pooling', [2 3 5]));
            minPooled = utils.resizeImage3d(volume, [], ResizeImage3dPoolingTest.poolingOptions('min pooling', [2 3 5]));

            testCase.verifyEqual(maxPooled, ResizeImage3dPoolingTest.blockReduce(volume, 6, 6, @max));
            testCase.verifyEqual(minPooled, ResizeImage3dPoolingTest.blockReduce(volume, 6, 6, @min));
        end

        function thinMembraneSurvivesAtFullStrength(testCase)
            % the reason for the method: a 1-voxel line in a 6x6 block, off the
            % position that nearest sampling would pick
            probability = zeros(36, 36, 3, 'uint8');
            probability(:, 4, :) = 200;

            pooled = utils.resizeImage3d(probability, [], ResizeImage3dPoolingTest.poolingOptions('max pooling', [6 6 3]));

            testCase.verifyEqual(pooled(:, 1, :), repmat(uint8(200), [6 1 3]));
            testCase.verifyEqual(nnz(pooled(:, 2:end, :)), 0, 'the membrane must not spread into the next block');
        end

        function zAxisIsPooledToo(testCase)
            volume = zeros(4, 4, 6, 'uint16');
            volume(:, :, 5) = 1000;

            pooled = utils.resizeImage3d(volume, [], ResizeImage3dPoolingTest.poolingOptions('max pooling', [4 4 2]));

            testCase.verifyEqual(squeeze(pooled(1, 1, :))', uint16([0 1000]));
        end

        function nonIntegerFactorSharesBoundaryVoxels(testCase)
            % 10 -> 4 (factor 2.5): output voxels cover inputs 1-3, 3-5, 6-8, 8-10
            volume = repmat(uint8(1:10), [2 1 2]);

            maxPooled = utils.resizeImage3d(volume, [], ResizeImage3dPoolingTest.poolingOptions('max pooling', [2 4 2]));
            minPooled = utils.resizeImage3d(volume, [], ResizeImage3dPoolingTest.poolingOptions('min pooling', [2 4 2]));

            testCase.verifyEqual(maxPooled(1, :, 1), uint8([3 5 8 10]));
            testCase.verifyEqual(minPooled(1, :, 1), uint8([1 3 6 8]));
        end

        function enlargedAxisTakesNearestVoxel(testCase)
            % XY halved by pooling while Z is doubled
            volume = zeros(4, 4, 3, 'uint8');
            volume(:, :, 1) = 10; volume(:, :, 2) = 20; volume(:, :, 3) = 30;
            volume(1, 1, :) = 99;

            pooled = utils.resizeImage3d(volume, [], ResizeImage3dPoolingTest.poolingOptions('max pooling', [2 2 6]));

            testCase.verifyEqual(squeeze(pooled(2, 2, :))', uint8([10 10 20 20 30 30]));
            testCase.verifyEqual(squeeze(pooled(1, 1, :))', repmat(uint8(99), 1, 6));
        end

        function classIsKeptAndNaNIgnored(testCase)
            volume = single(reshape(1:64, 4, 4, 4));
            volume(1, 1, 1) = NaN;

            pooled = utils.resizeImage3d(volume, [], ResizeImage3dPoolingTest.poolingOptions('min pooling', [2 2 2]));

            testCase.verifyClass(pooled, 'single');
            testCase.verifyEqual(pooled(1, 1, 1), single(2), 'the NaN voxel is skipped, the next lowest value wins');
        end

        function algorithmIsIgnored(testCase)
            rng(2, 'twister');
            volume = uint8(randi(255, [12 12 4]));
            reference = utils.resizeImage3d(volume, [], ResizeImage3dPoolingTest.poolingOptions('max pooling', [4 4 2]));

            for algorithm = {'interpn', 'tformarray'}
                options = ResizeImage3dPoolingTest.poolingOptions('max pooling', [4 4 2]);
                options.algorithm = algorithm{1};
                testCase.verifyEqual(utils.resizeImage3d(volume, [], options), reference, algorithm{1});
            end
        end

        function colorChannelsAndSingleSlice(testCase)
            rng(3, 'twister');
            volume = uint8(randi(255, [6 6 1 3]));

            pooled = utils.resizeImage3d(volume, [], ResizeImage3dPoolingTest.poolingOptions('max pooling', [2 3 1]));

            testCase.verifyEqual(size(pooled, 1:4), [2 3 1 3]);
            for colorIndex = 1:3
                testCase.verifyEqual(pooled(:, :, 1, colorIndex), ...
                    ResizeImage3dPoolingTest.blockReduce(volume(:, :, 1, colorIndex), 3, 2, @max));
            end
        end

        function resampleDialogPoolsImageAnd63MaterialModel(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel('dims', [24 36 4]);

            controllers.ResampleDataset(mibModel, [], ...
                ResizeImage3dPoolingTest.resampleOptions([4 6 4], 'max pooling', 'max pooling'));

            getOptions = struct('blockModeSwitch', 0);
            image = cell2mat(mibModel.getData3D('image', 1, 3, NaN, getOptions));
            labels = cell2mat(mibModel.getData3D('labels', 1, 3, NaN, getOptions));
            testCase.verifyEqual(image, ResizeImage3dPoolingTest.blockReduce(groundTruth.image, 6, 6, @max));
            testCase.verifyEqual(labels, ResizeImage3dPoolingTest.blockReduce(groundTruth.labels, 6, 6, @max));
        end

        function resampleDialogMinPoolsInstanceModel(testCase)
            % 16383 layout (packed uint16) with indices up to 16383, and a plain 65535 model
            for modelType = {'labels16383', 'labels65535'}
                [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel('dims', [24 36 4], 'modelType', modelType{1});

                controllers.ResampleDataset(mibModel, [], ...
                    ResizeImage3dPoolingTest.resampleOptions([8 12 4], 'nearest', 'min pooling'));

                labels = cell2mat(mibModel.getData3D('labels', 1, 3, NaN, struct('blockModeSwitch', 0)));
                testCase.verifyEqual(labels, cast(ResizeImage3dPoolingTest.blockReduce(groundTruth.labels, 3, 3, @min), 'like', labels), modelType{1});
            end
        end
    end
end
