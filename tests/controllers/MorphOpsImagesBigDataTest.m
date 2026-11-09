classdef MorphOpsImagesBigDataTest < matlab.unittest.TestCase
% MORPHOPSIMAGESBIGDATATEST - Morphological operations on the image of a BigData dataset, through the batch path of controllers.MorphOpsImages.
%
% A synthetic OME-Zarr v3 pyramid is opened as a BigData dataset, processed
% with ``controllers.MorphOpsImages(mibModel, [], BatchOpt)`` into a new store
% opened in container 2, and compared with ``applyOperation2D`` - the Standard
% 2D arithmetic of the controller - on every whole slice. The halos of
% ``Calculate.m`` are checked separately with bands of 64 rows (the level fits
% one default band, so the controller runs alone would not show a seam).
%
% Write to disk and drive the zarr savers/loaders, so tagged Integration.
%
% See also: controllers.MorphOpsImages, controllers.BigDataOptions

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function dilateOpensInAnotherBuffer(testCase)
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            BatchOpt = testCase.morphBatchOpt('Dilate image', fullfile(scratch, 'dilate.zarr3'));
            controllers.MorphOpsImages(mibModel, [], BatchOpt);

            testCase.verifyEqual(mibModel.I{2}.datasetType, 'BigData');
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), testCase.standardResult(mibModel, volume, BatchOpt, 1));
        end

        function oneChannelWithSmoothingAndAction(testCase)
            % Top-hat of ColCh 2, smoothed, doubled and added; channels 1 and 3 are copied.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 3);
            BatchOpt = testCase.morphBatchOpt('Top-hat filtering', fullfile(scratch, 'tophat.zarr3'));
            BatchOpt.ColorChannel = {'ColCh 2'};
            BatchOpt.SmoothHSize = {5};
            BatchOpt.SmoothSigma = {1};
            BatchOpt.Multiply = {2};
            BatchOpt.ActionToResult = {'AddToImage'};
            controllers.MorphOpsImages(mibModel, [], BatchOpt);

            expected = testCase.standardResult(mibModel, volume, BatchOpt, 2);
            testCase.verifyNotEqual(expected(:, :, :, 2), volume(:, :, :, 2));
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), expected);
        end

        function bandsGiveTheWholeSliceResult(testCase)
            % Bands of 64 rows with the halos of Calculate.m: one strel height for
            % dilate / erode, two for the others, plus half the smoothing kernel.
            morphCases = {'Erode image', 'disk', '5', 0, 1; ...
                'Morphological closing', 'rectangle', '7 3', 0, 2; ...
                'Morphological opening', 'disk', '4', 0, 2; ...
                'Bottom-hat filtering', 'rectangle', '9', 7, 2};
            for caseIndex = 1:size(morphCases, 1)
                [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
                BatchOpt = testCase.morphBatchOpt(morphCases{caseIndex, 1}, '');
                BatchOpt.StrelShape = morphCases(caseIndex, 2);
                BatchOpt.StrelSize = morphCases{caseIndex, 3};
                BatchOpt.SmoothHSize = morphCases(caseIndex, 4);
                BatchOpt.SmoothSigma = {morphCases{caseIndex, 4} / 5};
                tool = testCase.viewlessTool(mibModel, BatchOpt);
                haloYX = morphCases{caseIndex, 5} * floor(size(tool.getStrelElement().Neighborhood, 1) / 2) + ...
                    floor(morphCases{caseIndex, 4} / 2);

                outputPath = utils.bigdata.processImageToStore(mibModel.I{1}.image, ...
                    @(block) tool.applyOperation2D(block), fullfile(scratch, sprintf('bands%d.zarr3', caseIndex)), ...
                    HaloYX = haloYX, BandBytes = 8 * 260 * 40);
                controllers.BigDataOptions.openStoreInBuffer(mibModel, outputPath, 2);
                testCase.verifyEqual(testCase.readImage(mibModel.I{2}), ...
                    testCase.standardResult(mibModel, volume, BatchOpt, 1), morphCases{caseIndex, 1});
            end
        end

        function coarseLevel(testCase)
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            BatchOpt = testCase.morphBatchOpt('Morphological opening', fullfile(scratch, 's1.zarr3'));
            BatchOpt.BigData_PyramidLevel = {'s1'};
            controllers.MorphOpsImages(mibModel, [], BatchOpt);

            levelImage = mibModel.I{1}.image.getData('image', 3, [], struct('pyramidLevel', 2));
            levelImage = reshape(levelImage, size(levelImage, 1), size(levelImage, 2), size(levelImage, 3), []);
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), testCase.standardResult(mibModel, levelImage, BatchOpt, 1));
        end

        function refusals(testCase)
            % Reconstruction-based operations, the 3D mode and "2D, Slice" (a new store holds the
            % whole dataset) are refused before anything is written.
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            outputPath = fullfile(scratch, 'refused.zarr3');
            for operation = {'Clear border', 'Fill regions', 'H-maxima transform', 'H-minima transform'}
                BatchOpt = testCase.morphBatchOpt(operation{1}, outputPath);
                testCase.verifyError(@() controllers.MorphOpsImages(mibModel, [], BatchOpt), ...
                    'controllers:MorphOpsImages:bigData', operation{1});
            end
            BatchOpt = testCase.morphBatchOpt('Dilate image', outputPath);
            BatchOpt.Mode = {'3D'};
            testCase.verifyError(@() controllers.MorphOpsImages(mibModel, [], BatchOpt), ...
                'controllers:MorphOpsImages:bigData', '3D mode');
            BatchOpt = testCase.morphBatchOpt('Dilate image', outputPath);
            BatchOpt.DatasetType = {'2D, Slice'};
            testCase.verifyError(@() controllers.MorphOpsImages(mibModel, [], BatchOpt), ...
                'controllers:MorphOpsImages:bigData', '2D, Slice');
            testCase.verifyFalse(isfolder(outputPath));
        end

        function standardIgnoresTheBigDataFields(testCase)
            % The Standard batch path is unchanged: the active slice is dilated in place.
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel(dims = [40 50 3]);
            BatchOpt = testCase.morphBatchOpt('Dilate image', 'unused.zarr3');
            BatchOpt.DatasetType = {'3D, Stack'};
            controllers.MorphOpsImages(mibModel, [], BatchOpt);

            expected = groundTruth.image;
            se = strel('disk', 3, 0);
            for z = 1:3; expected(:, :, z) = imdilate(groundTruth.image(:, :, z), se); end
            testCase.verifyEqual(mibModel.I{1}.image.data(:, :, :, 1), expected(:, :, :, 1));   % [H W Z C]
            testCase.verifyFalse(isfolder('unused.zarr3'));
        end
    end

    methods (Static)
        function BatchOpt = morphBatchOpt(operation, outputPath)
            BatchOpt = struct('MorphOperation', {{operation}}, 'Mode', {{'2D'}}, 'DatasetType', {{'3D, Stack'}}, ...
                'ColorChannel', {{'All'}}, 'ActionToResult', {{'None'}}, 'StrelShape', {{'disk'}}, ...
                'StrelSize', '3', 'Connectivity', {{'4'}}, 'Multiply', {{1}}, 'SmoothHSize', {{0}}, ...
                'SmoothSigma', {{0}}, 'showWaitbar', false, 'BigData_OutputPath', outputPath, ...
                'BigData_OpenIn', {{'Container 2'}}, 'BigData_PyramidLevel', {{'s0'}});
        end

        function tool = viewlessTool(mibModel, BatchOpt)
            % The controller without a view, with BatchOpt, for its Standard arithmetic.
            tool = controllers.MorphOpsImages(mibModel, [], NaN);
            assert(isempty(tool.view));
            tool.BatchOpt = utils.updateBatchOptCombineFields_Shared(tool.BatchOpt, BatchOpt);
        end

        function expected = standardResult(mibModel, volume, BatchOpt, channel)
            % applyOperation2D (the Standard 2D path) on every whole slice of one channel of [H W Z C].
            tool = MorphOpsImagesBigDataTest.viewlessTool(mibModel, BatchOpt);
            expected = volume;
            for z = 1:size(volume, 3)
                expected(:, :, z, channel) = tool.applyOperation2D(volume(:, :, z, channel));
            end
        end

        function data = readImage(dataset)
            % Level 1 of a BigData image as [H W Z C].
            data = dataset.image.getData('image', 3, [], struct('pyramidLevel', 1));
            data = reshape(data, size(data, 1), size(data, 2), size(data, 3), size(data, 4));
        end
    end
end
