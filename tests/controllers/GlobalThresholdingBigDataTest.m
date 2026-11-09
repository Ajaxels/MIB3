classdef GlobalThresholdingBigDataTest < matlab.unittest.TestCase
% GLOBALTHRESHOLDINGBIGDATATEST - Global thresholding of a BigData dataset, through the batch path of controllers.GlobalThresholding.
%
% A synthetic OME-Zarr v3 pyramid is opened as a BigData dataset with an empty
% BigData model, thresholded with
% ``controllers.GlobalThresholding(mibModel, [], BatchOpt)``, and the mask or
% selection is compared with the Standard computation on every whole slice:
% one threshold per slice from ``computeThreshold``, the 8-bit scaling of a
% 16-bit image for the algorithms other than Otsu. The level fits the default
% statistics budget, so the histograms are exact and the results must be
% equal; the sampling itself is covered by ``SampleStripesTest``.
%
% Write to disk and drive the zarr savers/loaders, so tagged Integration.
%
% See also: controllers.GlobalThresholding, utils.bigdata.sliceHistograms

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function otsuIntoTheMask(testCase)
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            labels = mibtest.helpers.attachBigDataLabels(testCase, mibModel, scratch);
            BatchOpt = testCase.thresholdBatchOpt('Otsu', 'mask');
            controllers.GlobalThresholding(mibModel, [], BatchOpt);

            expected = testCase.standardResult(mibModel, volume, BatchOpt);
            testCase.verifyGreaterThan(nnz(expected), 1000);
            testCase.verifyEqual(labels.getData63('mask', 3, [], struct('pyramidLevel', 1)), expected);
            testCase.verifyEqual(nnz(labels.getData63('selection', 3, [], struct('pyramidLevel', 1))), 0);
            testCase.verifyTrue(logical(mibModel.I{1}.maskExist));
        end

        function twoDSliceThresholdsTheShownSlice(testCase)
            % Mode "2D, Slice": the histogram and the result of the shown slice only.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            labels = mibtest.helpers.attachBigDataLabels(testCase, mibModel, scratch);
            mibModel.I{1}.slices{3} = [3 3];
            BatchOpt = testCase.thresholdBatchOpt('Otsu', 'selection');
            BatchOpt.Mode = {'2D, Slice'};
            controllers.GlobalThresholding(mibModel, [], BatchOpt);

            expected = testCase.standardResult(mibModel, volume, BatchOpt);
            selection = labels.getData63('selection', 3, [], struct('pyramidLevel', 1));
            testCase.verifyGreaterThan(nnz(expected(:, :, 3)), 1000);
            testCase.verifyEqual(selection(:, :, 3), expected(:, :, 3));
            testCase.verifyEqual(nnz(selection(:, :, 1:2)), 0, 'other slices untouched');
        end

        function everyAlgorithmMatchesStandard(testCase)
            % The HistThresh algorithms and the percentile, with an offset, into the selection.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            labels = mibtest.helpers.attachBigDataLabels(testCase, mibModel, scratch);
            algorithms = {'Concavity', 'Entropy', 'InterMeans iter', 'InterModes', 'Mean', 'Median', ...
                'MinError', 'MinError iter', 'Minimum', 'Moments', 'Otsu', 'Percentile'};
            for algorithmIndex = 1:numel(algorithms)
                BatchOpt = testCase.thresholdBatchOpt(algorithms{algorithmIndex}, 'selection');
                BatchOpt.ThresholdOffset = {3};
                BatchOpt.ForegroundFraction = {0.3};
                controllers.GlobalThresholding(mibModel, [], BatchOpt);
                testCase.verifyEqual(labels.getData63('selection', 3, [], struct('pyramidLevel', 1)), ...
                    testCase.standardResult(mibModel, volume, BatchOpt), algorithms{algorithmIndex});
            end
        end

        function sixteenBitIsScaledLikeStandard(testCase)
            % Algorithms other than Otsu threshold an 8-bit copy scaled by the slice maximum.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1, DataClass = 'uint16');
            labels = mibtest.helpers.attachBigDataLabels(testCase, mibModel, scratch);
            for algorithm = {'Moments', 'Otsu'}
                BatchOpt = testCase.thresholdBatchOpt(algorithm{1}, 'selection');
                controllers.GlobalThresholding(mibModel, [], BatchOpt);
                testCase.verifyEqual(labels.getData63('selection', 3, [], struct('pyramidLevel', 1)), ...
                    testCase.standardResult(mibModel, volume, BatchOpt), algorithm{1});
            end
        end

        function coarseLevel(testCase)
            % At s1 the thresholds come from the level-2 image and the selection of level 2 is written.
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            labels = mibtest.helpers.attachBigDataLabels(testCase, mibModel, scratch);
            BatchOpt = testCase.thresholdBatchOpt('Otsu', 'selection');
            BatchOpt.BigData_PyramidLevel = {'s1'};
            controllers.GlobalThresholding(mibModel, [], BatchOpt);

            levelImage = mibModel.I{1}.image.getData('image', 3, [], struct('pyramidLevel', 2));
            levelImage = reshape(levelImage, size(levelImage, 1), size(levelImage, 2), []);
            testCase.verifyEqual(labels.getData63('selection', 3, [], struct('pyramidLevel', 2)), ...
                testCase.standardResult(mibModel, levelImage, BatchOpt));
        end

        function noModelIsRefusedBeforeReading(testCase)
            [mibModel, ~, ~] = mibtest.helpers.buildBigDataModel(testCase, 1);
            BatchOpt = testCase.thresholdBatchOpt('Otsu', 'mask');
            testCase.verifyError(@() controllers.GlobalThresholding(mibModel, [], BatchOpt), ...
                'controllers:GlobalThresholding:bigData');
        end
    end

    methods (Static)
        function BatchOpt = thresholdBatchOpt(algorithm, destination)
            BatchOpt = struct('Algorithm', {{algorithm}}, 'Mode', {{'3D, Stack'}}, 'ColorChannel', {{'Ch 1'}}, ...
                'Destination', {{destination}}, 'ForegroundFraction', {{0.5}}, 'ThresholdOffset', {{0}}, ...
                'showWaitbar', false, 'BigData_PyramidLevel', {{'s0'}});
        end

        function expected = standardResult(mibModel, volume, BatchOpt)
            % The Standard path on every whole slice of [H W Z], as uint8 0/1.
            tool = controllers.GlobalThresholding(mibModel, [], NaN);
            maxInt = double(intmax(class(volume)));
            expected = zeros(size(volume, 1:3), 'uint8');
            for z = 1:size(volume, 3)
                slice = volume(:, :, z);
                localMaxInt = maxInt;
                if maxInt > 255 && ~strcmp(BatchOpt.Algorithm{1}, 'Otsu')
                    slice = uint8(double(slice) / double(max(slice(:))) * 255);
                    localMaxInt = 255;
                end
                threshold = tool.computeThreshold(slice, BatchOpt.Algorithm{1}, BatchOpt.ForegroundFraction{1}, ...
                    localMaxInt) + BatchOpt.ThresholdOffset{1};
                expected(:, :, z) = uint8(slice > threshold);
            end
        end
    end
end
