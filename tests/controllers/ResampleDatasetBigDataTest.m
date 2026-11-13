classdef ResampleDatasetBigDataTest < matlab.unittest.TestCase
% RESAMPLEDATASETBIGDATATEST - Resample of a BigData dataset, through the batch path of controllers.ResampleDataset.
%
% A synthetic OME-Zarr v3 pyramid (300 x 260 x 3, levels s0-s2) is opened as a
% BigData dataset of a headless MibModel and resampled with
% ``controllers.ResampleDataset(mibModel, [], BatchOpt)``. The result is
% compared with ``imresize3`` of the whole array, which Standard Resample
% calls for the ``imresize`` function, and with ``utils.resizeImage3d`` for
% pooling. Covers bands of rows (a small ``BandBytes``), a resampled Z, a
% coarser level with sizes from a percentage, enlarging, a Standard result in
% memory, and the refusals.
%
% Write to disk and drive the zarr savers/loaders, so tagged Integration.
%
% See also: controllers.ResampleDataset, io.savers.ResampledSliceProvider,
% controllers.BigDataOptions

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function bandsEqualImresize3(testCase)
            % Every interpolation method, written in bands of a few rows, equals imresize3
            % of the whole volume, with XY shrunk and Z resampled: nearest exactly, the
            % others up to 1 grey level on a few pixels (a rounding tie, summed in
            % another order than imresize3 sums it).
            [mibModel, volume] = mibtest.helpers.buildBigDataModel(testCase, 1);
            image = mibModel.I{1}.image;
            outputSize = [137 101 2];
            for method = {'nearest', 'linear', 'cubic', 'box', 'triangle', 'lanczos2', 'lanczos3'}
                provider = io.savers.ResampledSliceProvider(image, 1, [], outputSize, method{1});
                result = testCase.readInBands(provider, 17);
                expected = imresize3(volume, outputSize, 'Method', method{1});
                testCase.verifyDifferenceOfRounding(result, expected, method{1});
            end
            provider = io.savers.ResampledSliceProvider(image, 1, [], outputSize, 'nearest');
            testCase.verifyEqual(testCase.readInBands(provider, 17), imresize3(volume, outputSize, 'Method', 'nearest'));
        end

        function poolingEqualsStandard(testCase)
            % Max and min pooling in bands equal utils.resizeImage3d, which Standard uses,
            % for an integer and a non-integer factor.
            [mibModel, volume] = mibtest.helpers.buildBigDataModel(testCase, 2);
            image = mibModel.I{1}.image;
            for outputSize = {[100 130 3], [77 91 2]}
                for method = {'max pooling', 'min pooling'}
                    provider = io.savers.ResampledSliceProvider(image, 1, [], outputSize{1}, method{1});
                    result = testCase.readInBands(provider, 9);
                    expected = utils.resizeImage3d(volume, [], struct('height', outputSize{1}(1), ...
                        'width', outputSize{1}(2), 'depth', outputSize{1}(3), 'method', method{1}, 'showWaitbar', 0));
                    testCase.verifyEqual(result, expected, sprintf('%s to %s', method{1}, mat2str(outputSize{1})));
                end
            end
        end

        function enlargingInBands(testCase)
            % Enlarging XY (and keeping Z) in bands equals imresize3; channels are kept apart.
            [mibModel, volume] = mibtest.helpers.buildBigDataModel(testCase, 2);
            provider = io.savers.ResampledSliceProvider(mibModel.I{1}.image, 1, [], [451 390 3], 'cubic');
            result = testCase.readInBands(provider, 64);
            for channel = 1:2
                testCase.verifyEqual(result(:,:,:,channel), imresize3(volume(:,:,:,channel), [451 390 3], 'Method', 'cubic'));
            end
        end

        function dimensionsIntoANewStore(testCase)
            % Dimensions mode at s0 into a new store opened in container 2: the store
            % equals imresize3, written in bands, with the voxel size scaled by the size
            % ratio and the bounding box starting at the source's. The source is kept.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            source = mibModel.I{1}.image;
            BatchOpt = testCase.resampleBatchOpt(mibModel, fullfile(scratch, 'resampled.zarr3'), [150 130 3]);
            tool = controllers.ResampleDataset(mibModel, [], NaN);
            tool.bigDataOptions.BandBytes = 1e6;     % two bands per slice
            provider = io.savers.ResampledSliceProvider(source, 1, [], [150 130 3], 'cubic');
            testCase.assertLessThan(provider.bandRows(tool.bigDataOptions.BandBytes), 150, 'the store is written in bands');
            tool.BatchOpt = utils.updateBatchOptCombineFields_Shared(tool.BatchOpt, BatchOpt);
            tool.resampleBtn_Callback(true);

            testCase.verifyEqual(mibModel.I{2}.datasetType, 'BigData');
            testCase.verifyTrue(utils.bigdata.isSameStorePath(mibModel.I{2}.image.filename, BatchOpt.BigData_OutputPath));
            testCase.verifyEqual(mibModel.I{1}.image.filename, source.filename, 'the source buffer keeps its dataset');
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), imresize3(volume, [150 130 3], 'Method', 'cubic'));
            result = mibModel.I{2}.image;
            testCase.verifyEqual(result.pixSize.x, source.pixSize.x * 2, 'AbsTol', 1e-12);
            testCase.verifyEqual(result.pixSize.y, source.pixSize.y * 2, 'AbsTol', 1e-12);
            testCase.verifyEqual(result.pixSize.z, source.pixSize.z, 'AbsTol', 1e-12);
            testCase.verifyEqual(result.boundingBox([1 3 5]), source.boundingBox([1 3 5]), 'AbsTol', 1e-9);
        end

        function percentageOfACoarserLevel(testCase)
            % PercentageXY 50 of level s1 resamples that level: the target is half the
            % level size, Z stays, and the result equals imresize3 of the level.
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            source = mibModel.I{1}.image;
            levelSize = source.pyramid.levelImageSizes(2, :);
            levelVolume = source.getData('image', 3, [], struct('pyramidLevel', 2));
            levelVolume = reshape(levelVolume, levelSize);
            BatchOpt = testCase.resampleBatchOpt(mibModel, fullfile(scratch, 's1half.zarr3'), []);
            BatchOpt.BigData_PyramidLevel = {'s1'};
            BatchOpt.ResamplingMode = {'PercentageXY'};
            BatchOpt.Percentage = '50';
            BatchOpt.ResamplingMethod = {'lanczos3'};
            controllers.ResampleDataset(mibModel, [], BatchOpt);

            expectedSize = [floor(levelSize(1:2) / 2), levelSize(3)];
            result = testCase.readImage(mibModel.I{2});
            testCase.verifyEqual(size(result, 1:3), expectedSize);
            testCase.verifyEqual(result, imresize3(levelVolume, expectedSize, 'Method', 'lanczos3'));
            testCase.verifyEqual(mibModel.I{2}.image.pixSize.x, source.pixSize.x * 2 * levelSize(2) / expectedSize(2), 'AbsTol', 1e-12);
        end

        function standardResultInMemory(testCase)
            % "Standard (in memory)" opens the resampled volume in container 2 with the
            % new voxel size; no store is written.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 3);
            outputPath = fullfile(scratch, 'notWritten.zarr3');
            BatchOpt = testCase.resampleBatchOpt(mibModel, outputPath, [120 104 5]);
            BatchOpt.BigData_Result = {'Standard (in memory)'};
            controllers.ResampleDataset(mibModel, [], BatchOpt);

            testCase.verifyEqual(mibModel.I{2}.datasetType, 'Standard');
            testCase.verifyFalse(isfolder(outputPath), 'no store is written');
            expected = zeros(120, 104, 5, 3, 'uint8');
            for channel = 1:3
                expected(:,:,:,channel) = imresize3(volume(:,:,:,channel), [120 104 5], 'Method', 'cubic');
            end
            testCase.verifyDifferenceOfRounding(mibModel.I{2}.image.data(:,:,:,:,1), expected, 'Standard result');
            testCase.verifyEqual(mibModel.I{2}.image.pixSize.z, mibModel.I{1}.image.pixSize.z * 3 / 5, 'AbsTol', 1e-12);
            testCase.verifyEqual(mibModel.I{1}.datasetType, 'BigData', 'the source buffer keeps its dataset');
        end

        function refusals(testCase)
            % Current overwrite, the interpn and tformarray functions and the spline / osc
            % methods are refused before anything is written.
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            outputPath = fullfile(scratch, 'refused.zarr3');
            BatchOpt = testCase.resampleBatchOpt(mibModel, outputPath, [150 130 3]);

            overwrite = BatchOpt;
            overwrite.BigData_OpenIn = {'Current overwrite (BigData)'};
            testCase.verifyError(@() controllers.ResampleDataset(mibModel, [], overwrite), 'controllers:ResampleDataset:bigData');
            for functionName = {'interpn', 'tformarray'}
                refused = BatchOpt;
                refused.ResamplingFunction = functionName;
                testCase.verifyError(@() controllers.ResampleDataset(mibModel, [], refused), ...
                    'controllers:ResampleDataset:bigData', functionName{1});
            end
            for method = {'spline', 'osc'}
                refused = BatchOpt;
                refused.ResamplingMethod = method;
                testCase.verifyError(@() controllers.ResampleDataset(mibModel, [], refused), ...
                    'controllers:ResampleDataset:bigData', method{1});
            end
            testCase.verifyFalse(isfolder(outputPath), 'nothing is written');
            testCase.verifyEqual(mibModel.I{1}.datasetType, 'BigData');
        end

        function levelsAndCurrentSize(testCase)
            % The defaults carry the BigData fields, and the current size and voxel size
            % follow the selected level.
            [mibModel, ~] = mibtest.helpers.buildBigDataModel(testCase, 1);
            tool = controllers.ResampleDataset(mibModel, [], NaN);
            testCase.verifyEmpty(tool.view, 'built without a window');
            testCase.verifyEqual(tool.BatchOpt.BigData_PyramidLevel{2}, {'s0', 's1', 's2'});
            testCase.verifyEqual([tool.height tool.width tool.depth], [300 260 3]);
            tool.BatchOpt.BigData_PyramidLevel{1} = 's2';
            tool.readCurrentSize();
            testCase.verifyEqual([tool.height tool.width tool.depth], mibModel.I{1}.image.pyramid.levelImageSizes(3, :));
            testCase.verifyEqual(tool.pixSize.x, mibModel.I{1}.image.pixSize.x * 4, 'AbsTol', 1e-12);
        end
    end

    methods
        function verifyDifferenceOfRounding(testCase, actual, expected, diagnostic)
            % Same size and class; at most 1 grey level apart, on under 0.1 % of the voxels.
            testCase.verifySize(actual, size(expected), diagnostic);
            testCase.verifyClass(actual, class(expected), diagnostic);
            difference = abs(double(actual(:)) - double(expected(:)));
            testCase.verifyLessThanOrEqual(max(difference), 1, diagnostic);
            testCase.verifyLessThan(nnz(difference) / numel(difference), 1e-3, diagnostic);
        end

        function BatchOpt = resampleBatchOpt(~, mibModel, outputPath, outputSize)
            % Batch options of Resample (the defaults) to ``outputSize`` [H W Z] in Dimensions mode, into a new store opened in container 2.
            tool = controllers.ResampleDataset(mibModel, [], NaN);
            BatchOpt = rmfield(tool.BatchOpt, 'mibBatchTooltip');
            BatchOpt.ResamplingMode = {'Dimensions'};
            BatchOpt.ResamplingFunction = {'imresize'};
            BatchOpt.ResamplingMethod = {'cubic'};
            if ~isempty(outputSize)
                BatchOpt.DimensionY = num2str(outputSize(1));
                BatchOpt.DimensionX = num2str(outputSize(2));
                BatchOpt.DimensionZ = num2str(outputSize(3));
            end
            BatchOpt.showWaitbar = false;
            BatchOpt.BigData_PyramidLevel = {'s0'};
            BatchOpt.BigData_OutputPath = outputPath;
            BatchOpt.BigData_OpenIn = {'Container 2'};
        end
    end

    methods (Static)
        function data = readInBands(provider, bandRows)
            % Every slice of the provider read in bands of ``bandRows`` rows, as [H W Z C].
            data = zeros(provider.OutputSize(1:4), provider.DataClass);
            for z = 1:provider.NumSlices
                for firstRow = 1:bandRows:provider.SliceSize(1)
                    lastRow = min(provider.SliceSize(1), firstRow + bandRows - 1);
                    rows = provider.getSliceRows(z, firstRow, lastRow);
                    data(firstRow:lastRow, :, z, :) = reshape(rows, size(rows, 1), size(rows, 2), 1, size(rows, 3));
                end
            end
        end

        function data = readImage(dataset)
            % Level 1 of a BigData image as [H W Z C].
            data = dataset.image.getData('image', 3, [], struct('pyramidLevel', 1));
            data = reshape(data, size(data, 1), size(data, 2), size(data, 3), size(data, 4));
        end
    end
end
