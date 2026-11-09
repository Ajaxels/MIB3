classdef WhiteBalanceBigDataTest < matlab.unittest.TestCase
% WHITEBALANCEBIGDATATEST - White balance of a BigData dataset, through the batch path of controllers.WhiteBalance.
%
% A synthetic 3-channel OME-Zarr v3 pyramid is opened as a BigData dataset,
% corrected with ``controllers.WhiteBalance(mibModel, [], BatchOpt)`` and a manual
% white into a new store opened in container 2, and compared with ``chromadapt``
% of every whole slice. ``chromadapt`` maps each pixel on its own, so the bands
% need no halo and the result must be equal.
%
% Write to disk and drive the zarr savers/loaders, so tagged Integration.
%
% See also: controllers.WhiteBalance, controllers.BigDataOptions

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function manualWhiteOpensInAnotherBuffer(testCase)
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 3);
            BatchOpt = testCase.whiteBatchOpt(fullfile(scratch, 'white.zarr3'));
            controllers.WhiteBalance(mibModel, [], BatchOpt);

            testCase.verifyEqual(mibModel.I{2}.datasetType, 'BigData');
            expected = testCase.chromadaptSlices(volume, [200 180 160], 'sRGB', 'bradford');
            testCase.verifyNotEqual(expected, volume);
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), expected);
        end

        function otherSettingsAtACoarseLevel(testCase)
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 3);
            BatchOpt = testCase.whiteBatchOpt(fullfile(scratch, 's1.zarr3'));
            BatchOpt.ColorSpace = {'linear-RGB'};
            BatchOpt.ChromaticAdaptationMethod = {'vonkries'};
            BatchOpt.BigData_PyramidLevel = {'s1'};
            controllers.WhiteBalance(mibModel, [], BatchOpt);

            levelImage = mibModel.I{1}.image.getData('image', 3, [], struct('pyramidLevel', 2));
            levelImage = reshape(levelImage, size(levelImage, 1), size(levelImage, 2), size(levelImage, 3), []);
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), ...
                testCase.chromadaptSlices(levelImage, [200 180 160], 'linear-RGB', 'vonkries'));
        end

        function refusals(testCase)
            % A white from the selection, Correct current and a 1-channel image, before anything is written.
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 3);
            BatchOpt = testCase.whiteBatchOpt(fullfile(scratch, 'refused.zarr3'));
            BatchOpt.PickedRegion = {'SelectedAreas'};
            testCase.verifyError(@() controllers.WhiteBalance(mibModel, [], BatchOpt), ...
                'controllers:WhiteBalance:bigData', 'SelectedAreas');

            tool = controllers.WhiteBalance(mibModel, [], NaN);
            tool.BatchOpt = utils.updateBatchOptCombineFields_Shared(tool.BatchOpt, testCase.whiteBatchOpt(BatchOpt.BigData_OutputPath));
            testCase.verifyError(@() tool.correctWhiteBalance('Correct current', true), ...
                'controllers:WhiteBalance:bigData', 'Correct current');
            testCase.verifyFalse(isfolder(BatchOpt.BigData_OutputPath));

            [grayModel, ~, grayScratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            testCase.verifyError(@() controllers.WhiteBalance(grayModel, [], ...
                testCase.whiteBatchOpt(fullfile(grayScratch, 'gray.zarr3'))), 'controllers:WhiteBalance:bigData', '1 channel');
        end
    end

    methods (Static)
        function BatchOpt = whiteBatchOpt(outputPath)
            BatchOpt = struct('PickedRegion', {{'ManualValue'}}, 'ManualWhiteColor', '200 180 160', ...
                'ColorSpace', {{'sRGB'}}, 'ChromaticAdaptationMethod', {{'bradford'}}, 'showWaitbar', false, ...
                'BigData_OutputPath', outputPath, 'BigData_OpenIn', {{'Container 2'}}, 'BigData_PyramidLevel', {{'s0'}});
        end

        function expected = chromadaptSlices(volume, white, colorSpace, method)
            % chromadapt of every whole slice of [H W Z 3].
            expected = volume;
            for z = 1:size(volume, 3)
                expected(:, :, z, :) = reshape(chromadapt(squeeze(volume(:, :, z, :)), white, ...
                    'ColorSpace', colorSpace, 'Method', method), size(volume, 1), size(volume, 2), 1, 3);
            end
        end

        function data = readImage(dataset)
            % Level 1 of a BigData image as [H W Z C].
            data = dataset.image.getData('image', 3, [], struct('pyramidLevel', 1));
            data = reshape(data, size(data, 1), size(data, 2), size(data, 3), size(data, 4));
        end
    end
end
