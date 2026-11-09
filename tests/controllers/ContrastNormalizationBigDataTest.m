classdef ContrastNormalizationBigDataTest < matlab.unittest.TestCase
% CONTRASTNORMALIZATIONBIGDATATEST - Z-stack normalization of a BigData dataset, through the batch path of controllers.ContrastNormalization.
%
% A synthetic OME-Zarr v3 pyramid is opened as a BigData dataset, normalized
% with ``controllers.ContrastNormalization(mibModel, [], BatchOpt)`` into a new
% store opened in container 2, and compared with the arithmetic of
% ``normalizeZStack`` on the whole slices in memory. The level fits the
% statistics budget, so the statistics are exact; a slice mean taken from a
% histogram instead of the pixels can differ in the last bits, so a value may
% round the other way: up to 1 grey level is accepted.
%
% Write to disk and drive the zarr savers/loaders, so tagged Integration.
%
% See also: controllers.ContrastNormalization, utils.bigdata.sliceHistograms

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function automaticOpensInAnotherBuffer(testCase)
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            BatchOpt = testCase.normalizationBatchOpt(fullfile(scratch, 'normalized.zarr3'));
            controllers.ContrastNormalization(mibModel, [], BatchOpt);

            testCase.verifyEqual(mibModel.I{2}.datasetType, 'BigData');
            testCase.verifyNormalized(testCase.readImage(mibModel.I{2}), ...
                testCase.normalizeSlices(volume, 1, 'Automatic', 'Whole range', []));
        end

        function oneChannelExcludingBlacks(testCase)
            % ColCh 2 is normalized without its black pixels; channels 1 and 3 are copied.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 3);
            BatchOpt = testCase.normalizationBatchOpt(fullfile(scratch, 'channel2.zarr3'));
            BatchOpt.ColChannel = {'ColCh 2'};
            BatchOpt.Exculude = {'Excude blacks'};
            controllers.ContrastNormalization(mibModel, [], BatchOpt);

            testCase.verifyNormalized(testCase.readImage(mibModel.I{2}), ...
                testCase.normalizeSlices(volume, 2, 'Automatic', 'Excude blacks', []));
        end

        function manualAtACoarseLevel(testCase)
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            BatchOpt = testCase.normalizationBatchOpt(fullfile(scratch, 'manual.zarr3'));
            BatchOpt.Mode = {'Manual'};
            BatchOpt.Mean = {100};
            BatchOpt.Std = {20};
            BatchOpt.BigData_PyramidLevel = {'s1'};
            controllers.ContrastNormalization(mibModel, [], BatchOpt);

            levelImage = mibModel.I{1}.image.getData('image', 3, [], struct('pyramidLevel', 2));
            levelImage = reshape(levelImage, size(levelImage, 1), size(levelImage, 2), size(levelImage, 3), []);
            testCase.verifyNormalized(testCase.readImage(mibModel.I{2}), ...
                testCase.normalizeSlices(levelImage, 1, 'Manual', 'Whole range', [100 20]));
        end

        function maskedAreaIsRefused(testCase)
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            mibModel.I{1}.maskExist = true;
            BatchOpt = testCase.normalizationBatchOpt(fullfile(scratch, 'refused.zarr3'));
            BatchOpt.Target = {'Masked area'};
            testCase.verifyError(@() controllers.ContrastNormalization(mibModel, [], BatchOpt), ...
                'controllers:ContrastNormalization:bigData');
            testCase.verifyFalse(isfolder(BatchOpt.BigData_OutputPath));
        end
    end

    methods
        function verifyNormalized(testCase, actual, expected)
            % Equal up to 1 grey level; at most 0.1 % of the pixels may differ.
            difference = abs(double(actual) - double(expected));
            testCase.verifyLessThanOrEqual(max(difference(:)), 1);
            testCase.verifyLessThanOrEqual(nnz(difference) / numel(difference), 1e-3);
        end
    end

    methods (Static)
        function BatchOpt = normalizationBatchOpt(outputPath)
            BatchOpt = struct('Target', {{'Z stack'}}, 'Mode', {{'Automatic'}}, 'ColChannel', {{'All channels'}}, ...
                'Exculude', {{'Whole range'}}, 'ReferenceSliceNo', {{1}}, 'showWaitbar', false, ...
                'BigData_OutputPath', outputPath, 'BigData_OpenIn', {{'Container 2'}}, 'BigData_PyramidLevel', {{'s0'}});
        end

        function expected = normalizeSlices(volume, channel, mode, exclude, manualValues)
            % The arithmetic of normalizeZStack on [H W Z C], for one channel.
            expected = volume;
            channelVolume = double(volume(:, :, :, channel));
            depth = size(channelVolume, 3);
            sliceMean = zeros(1, depth);
            sliceStd = zeros(1, depth);
            for z = 1:depth
                values = channelVolume(:, :, z);
                switch exclude
                    case 'Excude blacks'; values = values(values > 0);
                    otherwise; values = values(:);
                end
                sliceMean(z) = mean(values);
                sliceStd(z) = std(values);
            end
            if strcmp(mode, 'Manual')
                targetMean = manualValues(1);
                targetStd = manualValues(2);
            else
                targetMean = mean(sliceMean);
                targetStd = mean(sliceStd);
            end
            for z = 1:depth
                slice = channelVolume(:, :, z);
                shifted = (slice - sliceMean(z)) * (targetStd / sliceStd(z)) + targetMean;
                if strcmp(exclude, 'Excude blacks')
                    shifted(slice == 0) = slice(slice == 0);
                end
                expected(:, :, z, channel) = cast(shifted, class(volume));
            end
        end

        function data = readImage(dataset)
            % Level 1 of a BigData image as [H W Z C].
            data = dataset.image.getData('image', 3, [], struct('pyramidLevel', 1));
            data = reshape(data, size(data, 1), size(data, 2), size(data, 3), size(data, 4));
        end
    end
end
