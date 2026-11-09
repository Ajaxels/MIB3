classdef ImageFiltersBigDataTest < matlab.unittest.TestCase
% IMAGEFILTERSBIGDATATEST - Image filters on a BigData dataset, through the batch path of controllers.ImageFilters.
%
% A synthetic OME-Zarr v3 pyramid is opened as a BigData dataset of a headless
% MibModel, filtered with ``controllers.ImageFilters(mibModel, [], BatchOpt)``,
% and the new store is compared with the same filter applied to the whole array
% in memory. Covers the result opened in another buffer, a single filtered
% channel, writing the store only, the filters not offered on BigData, overwriting
% the source store, Edge into the selection or mask of the model, and an
% output path that is already open.
%
% Write to disk and drive the zarr savers/loaders, so tagged Integration.
%
% See also: controllers.ImageFilters, controllers.BigDataOptions,
% utils.bigdata.processImageToStore

    properties (Constant)
        % the filters depending on the whole slice: name, group, settings, useRGB
        % (3 channels), largest mean difference to Standard from the s1 guide on the
        % sample images (measured 2026-11-06: LocalBrighten 1.85, LocalContrast and
        % FastLocalLaplacian 1.0-1.3, the others below 1)
        WholeSliceCases = {
            'FlatfieldCorrection', 'Contrast Adjustment', struct('Sigma', '20'), false, 1; ...
            'FlatfieldCorrection', 'Contrast Adjustment', struct('Sigma', '20'), true, 1; ...
            'LocalBrighten', 'Contrast Adjustment', struct('Amount', {{0.8}}), false, 2.5; ...
            'LocalBrighten', 'Contrast Adjustment', struct('Amount', {{0.8}}), true, 2.5; ...
            'ReduceHaze', 'Contrast Adjustment', struct('Method', {{'simpledcp'}}, 'ContrastEnhancement', {{'global'}}), false, 1; ...
            'ReduceHaze', 'Contrast Adjustment', struct('Method', {{'simpledcp'}}, 'ContrastEnhancement', {{'boost'}}, 'AtmosphericLight', ''), true, 1; ...
            'ReduceHaze', 'Contrast Adjustment', struct('Method', {{'approxdcp'}}, 'ContrastEnhancement', {{'none'}}), false, 1; ...
            'ReduceHaze', 'Contrast Adjustment', struct('Method', {{'approxdcp'}}, 'ContrastEnhancement', {{'global'}}, 'AtmosphericLight', ''), true, 1; ...
            'LocalContrast', 'Contrast Adjustment', struct('EdgeThreshold', {{0.3}}, 'Amount', {{0.5}}), false, 2; ...
            'LocalContrast', 'Contrast Adjustment', struct('EdgeThreshold', {{0.3}}, 'Amount', {{0.5}}), true, 2; ...
            'FastLocalLaplacian', 'Contrast Adjustment', struct('EdgeAmplitude', {{0.2}}, 'Smoothing', {{0.3}}), false, 2; ...
            'FastLocalLaplacian', 'Contrast Adjustment', struct('EdgeAmplitude', {{0.2}}, 'Smoothing', {{0.3}}, 'ColorMode', {{'separate'}}), true, 2};
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function gaussianOpensInAnotherBuffer(testCase)
            % The filtered store opens as BigData in container 2 and equals imgaussfilt
            % of every whole slice; the source buffer is not changed.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            sourcePath = mibModel.I{1}.image.filename;
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'gaussian.zarr3'), 'Container 2');
            controllers.ImageFilters(mibModel, [], BatchOpt);

            testCase.verifyEqual(mibModel.I{2}.datasetType, 'BigData');
            testCase.verifyTrue(utils.bigdata.isSameStorePath(mibModel.I{2}.image.filename, BatchOpt.BigData_OutputPath));
            testCase.verifyEqual(mibModel.I{1}.image.filename, sourcePath, 'the source buffer must keep its dataset');

            result = testCase.readImage(mibModel.I{2});
            expected = testCase.gaussianOfSlices(volume, BatchOpt);
            testCase.verifyEqual(result, expected);
        end

        function singleChannelKeepsTheOthers(testCase)
            % ColorChannel '2' filters channel 2 only; channels 1 and 3 are copied.
            [mibModel, volume, scratch] = testCase.buildBigData(3);
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'channel2.zarr3'), 'Container 2');
            BatchOpt.ColorChannel = {'2'};
            controllers.ImageFilters(mibModel, [], BatchOpt);

            result = testCase.readImage(mibModel.I{2});
            expected = volume;
            expected(:,:,:,2) = testCase.gaussianOfSlices(volume(:,:,:,2), BatchOpt);
            testCase.verifyEqual(result, expected);
        end

        function levelsAreNamedFromS0(testCase)
            % The items are s0, s1, s2; 's1' filters the second level.
            [mibModel, ~, scratch] = testCase.buildBigData(1);
            filters = controllers.ImageFilters(mibModel, [], NaN);
            testCase.verifyEqual(filters.BatchOpt.BigData_PyramidLevel{2}, {'s0', 's1', 's2'}, 'plain names, so a protocol fits a dataset of another size');
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 's1.zarr3'), 'Container 2');
            BatchOpt.BigData_PyramidLevel = {'s1'};
            controllers.ImageFilters(mibModel, [], BatchOpt);

            levelSize = mibModel.I{1}.image.pyramid.levelImageSizes(2, :);
            testCase.verifyEqual(size(testCase.readImage(mibModel.I{2}), [1 2 3]), levelSize);
        end

        function overwriteRewritesTheStoreAndKeepsTheModel(testCase)
            % "Current overwrite (BigData)" of an unlocked image: the store at the same path holds the
            % result, the model object stays attached, and no temporary folder is left.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            dataset = mibModel.I{1};
            sourcePath = dataset.image.filename;
            labels = testCase.attachModel(mibModel, scratch);
            testCase.verifyEqual(testCase.readImage(dataset), volume, 'reads the source first, so the chunk cache is warm');
            mibModel.setLockedState(1, 'image', false);
            % a voxel size edited in the session, not in the store, must survive
            pixSize = dataset.image.pixSize;
            pixSize.z = 0.07;
            dataset.setPixSize(pixSize);
            boundingBox = dataset.image.boundingBox;

            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'unused.zarr3'), 'Current overwrite (BigData)');
            controllers.ImageFilters(mibModel, [], BatchOpt);

            testCase.verifyEqual(dataset.image.pixSize, pixSize);
            testCase.verifyEqual(dataset.image.boundingBox, boundingBox);
            [stretchX, stretchY] = dataset.getDisplayStretch();   % failed in the GUI when pixSize was lost
            testCase.verifyEqual([stretchX, stretchY], [1 1]);
            testCase.verifyEqual(dataset.image.filename, sourcePath);
            testCase.verifyEqual(testCase.readImage(dataset), testCase.gaussianOfSlices(volume, BatchOpt));
            testCase.verifySameHandle(dataset.labels, labels, 'the model must stay attached');
            testCase.verifyTrue(dataset.modelExist);
            testCase.verifyFalse(dataset.image.lockedState, 'the lock state is carried over');
            testCase.verifyEqual(mibModel.I{2}.image.filename, 'none.tif', 'no other buffer may be changed');
            listing = dir(scratch);
            testCase.verifyEmpty(listing(contains({listing.name}, '.mib_')), 'temporary stores must be removed');
            testCase.verifyFalse(isfolder(BatchOpt.BigData_OutputPath), 'the output path is not used');
        end

        function overwriteOfTheShownSlice(testCase)
            % "2D, Slice" with "Current overwrite (BigData)" writes the shown slice into the store: every
            % level equals a store written from the expected volume, with 2 channels and XY-only
            % levels in one band, and with a level that halves Z in bands of 64 rows. A view
            % other than XY is refused.
            scratch = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            rng(3);
            % channels, depth, saver options, band budget (40 rows, rounded to the 64-row chunks)
            cases = {2, 3, struct('ChunkSize', [64 64 1], 'Levels', 3, 'DownsampleStrategy', 'XY only'), 256e6; ...
                1, 6, struct('ChunkSize', [64 64 2], 'Levels', 4, 'DownsampleStrategy', 'Anisotropy-preserving'), 8 * 260 * 40};
            metadata = struct('pixSize', struct('x', 0.02, 'y', 0.02, 'z', 0.05, 'units', 'um'));
            mibFolder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'mib');
            for caseIndex = 1:size(cases, 1)
                [colors, depth, saverOptions, bandBytes] = cases{caseIndex, :};
                saverOptions.silent = true;
                saverOptions.showWaitbar = false;
                volume = uint8(255 * mat2gray(convn(randn(300, 260, depth, colors), ones(5, 5), 'same')));
                sourcePath = fullfile(scratch, sprintf('source%d.zarr3', caseIndex));
                io.savers.Zarr3Saver(struct()).save(reshape(volume, 300, 260, depth, colors, 1), metadata, sourcePath, saverOptions);
                mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
                controllers.BigDataOptions.openStoreInBuffer(mibModel, sourcePath, 1);
                mibModel.setLockedState(1, 'image', false);
                if caseIndex == 2
                    testCase.assumeTrue(any(mibModel.I{1}.image.pyramid.levelScaleFactors(:, 3) > 1), ...
                        'the anisotropic store must have a level that halves Z');
                end
                shownSlice = depth - 1;
                mibModel.I{1}.slices{3} = [shownSlice shownSlice];

                BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'unused.zarr3'), 'Current overwrite (BigData)');
                BatchOpt.DatasetType = {'2D, Slice'};
                mibModel.I{1}.orientation = 1;
                testCase.verifyError(@() controllers.ImageFilters(mibModel, [], BatchOpt), ...
                    'controllers:ImageFilters:bigData', 'a ZX view is refused');
                mibModel.I{1}.orientation = 3;
                tool = controllers.ImageFilters(mibModel, [], NaN);
                tool.bigDataOptions.BandBytes = bandBytes;
                tool.BatchOpt = utils.updateBatchOptCombineFields_Shared(tool.BatchOpt, BatchOpt);
                tool.Filter([], 1);

                expected = volume;
                expected(:, :, shownSlice, :) = testCase.gaussianOfSlices(volume(:, :, shownSlice, :), BatchOpt);
                testCase.verifyEqual(testCase.readImage(mibModel.I{1}), expected, 'the dataset reads the new slice');
                referencePath = fullfile(scratch, sprintf('reference%d.zarr3', caseIndex));
                io.savers.Zarr3Saver(struct()).save(reshape(expected, 300, 260, depth, colors, 1), metadata, ...
                    referencePath, saverOptions);
                levelNames = mibModel.I{1}.image.pyramid.levelNames;
                for levelIndex = 1:numel(levelNames)
                    testCase.verifyEqual(io.zarr.Array(fullfile(sourcePath, levelNames{levelIndex})).read(), ...
                        io.zarr.Array(fullfile(referencePath, levelNames{levelIndex})).read(), ...
                        sprintf('case %d, level s%d', caseIndex, levelIndex - 1));
                end
                listing = dir(scratch);
                testCase.verifyEmpty(listing(contains({listing.name}, '.mib_')), 'the temporary array must be removed');
            end
        end

        function standardResultInMemory(testCase)
            % "Standard (in memory)": no store is written; s0 opens in container 2 with the
            % voxel size and bounding box of the source, s1 replaces the BigData dataset in its
            % own buffer with the voxel size of the level. "Do not open" is refused.
            [mibModel, volume, scratch] = testCase.buildBigData(2);
            sourceImage = mibModel.I{1}.image;
            sourcePixSize = sourceImage.pixSize;
            sourceBox = sourceImage.boundingBox;
            levelVolume = sourceImage.getData('image', 3, [], struct('pyramidLevel', 2));
            outputPath = fullfile(scratch, 'notWritten.zarr3');

            BatchOpt = testCase.gaussianBatchOpt(mibModel, outputPath, 'Container 2');
            BatchOpt.BigData_Result = {'Standard (in memory)'};
            controllers.ImageFilters(mibModel, [], BatchOpt);
            testCase.verifyEqual(mibModel.I{2}.datasetType, 'Standard');
            testCase.verifyEqual(mibModel.I{2}.image.data(:,:,:,:,1), testCase.gaussianOfSlices(volume, BatchOpt));
            testCase.verifyEqual(mibModel.I{2}.image.pixSize.x, sourcePixSize.x, 'AbsTol', 1e-12);
            testCase.verifyEqual(mibModel.I{2}.image.boundingBox, sourceBox, 'AbsTol', 1e-9);
            testCase.verifyEqual(mibModel.I{1}.datasetType, 'BigData', 'the source buffer keeps its dataset');
            testCase.verifyFalse(isfolder(outputPath), 'no store is written');
            testCase.verifyEqual(mibModel.I{2}.image.filename, fullfile(scratch, 'notWritten.tif'), 'named after the output path');

            BatchOpt.BigData_OpenIn = {'Current'};
            BatchOpt.BigData_PyramidLevel = {'s1'};
            controllers.ImageFilters(mibModel, [], BatchOpt);
            testCase.verifyEqual(mibModel.I{1}.datasetType, 'Standard');
            levelVolume = reshape(levelVolume, size(levelVolume, 1), size(levelVolume, 2), size(levelVolume, 3), size(levelVolume, 4));
            testCase.verifyEqual(mibModel.I{1}.image.data(:,:,:,:,1), ...
                testCase.gaussianOfSlices(levelVolume, BatchOpt));
            testCase.verifyEqual(mibModel.I{1}.image.pixSize.x, 2 * sourcePixSize.x, 'AbsTol', 1e-12);
            testCase.verifyEqual(mibModel.I{1}.image.boundingBox([1 3 5]), sourceBox([1 3 5]), 'AbsTol', 1e-9);
            testCase.verifyFalse(isfolder(outputPath));

            [mibModel, ~, scratch] = testCase.buildBigData(1);
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'unused.zarr3'), 'Do not open');
            BatchOpt.BigData_Result = {'Standard (in memory)'};
            testCase.verifyError(@() controllers.ImageFilters(mibModel, [], BatchOpt), 'controllers:ImageFilters:bigData');
            testCase.verifyEqual(mibModel.I{1}.datasetType, 'BigData');
        end

        function overwriteWithTheStandardResult(testCase)
            % "Current overwrite (BigData)" rewrites the source store with either Result: with
            % "Standard (in memory)" the dataset stays BigData and holds the result.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            sourcePath = mibModel.I{1}.image.filename;
            mibModel.setLockedState(1, 'image', false);
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'unused.zarr3'), 'Current overwrite (BigData)');
            BatchOpt.BigData_Result = {'Standard (in memory)'};
            controllers.ImageFilters(mibModel, [], BatchOpt);
            testCase.verifyEqual(mibModel.I{1}.datasetType, 'BigData');
            testCase.verifyEqual(mibModel.I{1}.image.filename, sourcePath);
            testCase.verifyEqual(testCase.readImage(mibModel.I{1}), testCase.gaussianOfSlices(volume, BatchOpt));
            testCase.verifyFalse(isfolder(BatchOpt.BigData_OutputPath), 'the output path is not used');
        end

        function overwriteOfLockedImageErrors(testCase)
            % A BigData image opens locked; headless the overwrite is refused and nothing changes.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'unused.zarr3'), 'Current overwrite (BigData)');
            testCase.verifyError(@() controllers.ImageFilters(mibModel, [], BatchOpt), 'controllers:ImageFilters:bigData');
            testCase.verifyEqual(testCase.readImage(mibModel.I{1}), volume);
        end

        function overwriteNeedsLevelS0(testCase)
            % A coarser level would change the size of the image under its model.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            mibModel.setLockedState(1, 'image', false);
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'unused.zarr3'), 'Current overwrite (BigData)');
            BatchOpt.BigData_PyramidLevel = {'s1'};
            testCase.verifyError(@() controllers.ImageFilters(mibModel, [], BatchOpt), 'controllers:ImageFilters:bigData');
            testCase.verifyEqual(testCase.readImage(mibModel.I{1}), volume);
            listing = dir(scratch);
            testCase.verifyEmpty(listing(contains({listing.name}, '.mib_')));
        end

        function sobelEdgesFillTheSelection(testCase)
            % Edge into the selection, computed in bands, equals edge() of every whole
            % slice; the labels and the mask are not touched.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            labels = testCase.attachModel(mibModel, scratch);
            BatchOpt = testCase.edgeBatchOpt(mibModel, 'Sobel', 'selection');
            controllers.ImageFilters(mibModel, [], BatchOpt);

            expected = testCase.edgeOfSlices(volume, 'Sobel', 0.05);
            testCase.verifyEqual(labels.getData63('selection', 3, [], struct('pyramidLevel', 1)), expected);
            testCase.verifyEqual(nnz(labels.getData63('mask', 3, [], struct('pyramidLevel', 1))), 0);
            testCase.verifyEqual(nnz(labels.getData63('labels', 3, [], struct('pyramidLevel', 1))), 0);
        end

        function bandsGiveTheWholeSliceEdges(testCase)
            % runToModel with 40-row bands and the halos of Filter.m (Sobel 3,
            % LaplacianOfGaussian sigma 2: ceil(3*2)+2): the seams are invisible.
            edgeCases = {@(block) edge(block, 'Sobel', 0.05), 3; ...
                         @(block) edge(block, 'log', 0.002, 2), ceil(3 * 2) + 2};
            for caseIndex = 1:size(edgeCases, 1)
                [mibModel, volume, scratch] = testCase.buildBigData(1);
                labels = testCase.attachModel(mibModel, scratch);
                BatchOpt = testCase.edgeBatchOpt(mibModel, 'Sobel', 'selection');
                filters = controllers.ImageFilters(mibModel, [], NaN);
                BatchOpt.id = 1;
                blockFunction = edgeCases{caseIndex, 1};
                result = filters.bigDataOptions.runToModel(BatchOpt, blockFunction, 'selection', ...
                    HaloYX = edgeCases{caseIndex, 2}, ColChannel = 1, BandBytes = 8 * 260 * 40);
                testCase.verifyTrue(result.completed);
                expected = zeros(size(volume, 1:3), 'uint8');
                for z = 1:size(volume, 3)
                    expected(:,:,z) = blockFunction(volume(:,:,z));
                end
                testCase.verifyGreaterThan(nnz(expected), 1000, 'the threshold must find edges');
                testCase.verifyEqual(labels.getData63('selection', 3, [], struct('pyramidLevel', 1)), expected, ...
                    func2str(blockFunction));
            end
        end

        function edgesAtACoarseLevel(testCase)
            % At s1 the selection of level 2 equals edge() of the level-2 image.
            [mibModel, ~, scratch] = testCase.buildBigData(1);
            labels = testCase.attachModel(mibModel, scratch);
            BatchOpt = testCase.edgeBatchOpt(mibModel, 'Prewitt', 'selection');
            BatchOpt.BigData_PyramidLevel = {'s1'};
            controllers.ImageFilters(mibModel, [], BatchOpt);

            levelImage = mibModel.I{1}.image.getData('image', 3, [], struct('pyramidLevel', 2));
            levelImage = reshape(levelImage, size(levelImage, 1), size(levelImage, 2), []);
            expected = testCase.edgeOfSlices(levelImage, 'Prewitt', 0.05);
            testCase.verifyEqual(labels.getData63('selection', 3, [], struct('pyramidLevel', 2)), expected);
        end

        function edgesIntoTheMask(testCase)
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            labels = testCase.attachModel(mibModel, scratch);
            BatchOpt = testCase.edgeBatchOpt(mibModel, 'Roberts', 'mask');
            controllers.ImageFilters(mibModel, [], BatchOpt);

            testCase.verifyTrue(logical(mibModel.I{1}.maskExist));
            testCase.verifyEqual(labels.getData63('mask', 3, [], struct('pyramidLevel', 1)), ...
                testCase.edgeOfSlices(volume, 'Roberts', 0.05));
        end

        function automaticThresholdPerSlice(testCase)
            % An empty Threshold: one threshold per slice from the statistics pass,
            % equal to the one edge() computes for the whole slice.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            labels = mibtest.helpers.attachBigDataLabels(testCase, mibModel, scratch);
            edgeCases = {'Sobel', 'both'; 'Sobel', 'horizontal'; 'Prewitt', 'vertical'; 'Roberts', 'both'; ...
                'LaplacianOfGaussian', 'both'};
            for caseIndex = 1:size(edgeCases, 1)
                BatchOpt = testCase.edgeBatchOpt(mibModel, edgeCases{caseIndex, 1}, 'selection');
                BatchOpt.Threshold = '';
                BatchOpt.Direction = edgeCases(caseIndex, 2);
                controllers.ImageFilters(mibModel, [], BatchOpt);

                expected = zeros(size(volume, 1:3), 'uint8');
                for z = 1:size(volume, 3)
                    if strcmp(edgeCases{caseIndex, 1}, 'LaplacianOfGaussian')
                        expected(:, :, z) = edge(volume(:, :, z), 'log', [], str2double(BatchOpt.Sigma));
                    else
                        expected(:, :, z) = edge(volume(:, :, z), edgeCases{caseIndex, 1}, [], edgeCases{caseIndex, 2});
                    end
                end
                testCase.verifyGreaterThan(nnz(expected), 300);
                testCase.verifyEqual(labels.getData63('selection', 3, [], struct('pyramidLevel', 1)), expected, ...
                    strjoin(edgeCases(caseIndex, :), ' '));
            end
        end

        function edgesOnTheShownSliceOnly(testCase)
            % "2D, Slice" writes the shown slice only, with a given and an automatic
            % threshold; the other slices keep their selection. A view other than
            % XY is refused.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            labels = mibtest.helpers.attachBigDataLabels(testCase, mibModel, scratch);
            mibModel.I{1}.slices{3} = [2 2];
            for threshold = {'0.05', ''}
                labels.setData63(ones(size(volume, 1:3), 'uint8'), 'selection', 3, [], struct('pyramidLevel', 1));
                BatchOpt = testCase.edgeBatchOpt(mibModel, 'Sobel', 'selection');
                BatchOpt.DatasetType = {'2D, Slice'};
                BatchOpt.Threshold = threshold{1};
                controllers.ImageFilters(mibModel, [], BatchOpt);

                selection = labels.getData63('selection', 3, [], struct('pyramidLevel', 1));
                if isempty(threshold{1})
                    expected = uint8(edge(volume(:, :, 2), 'Sobel'));
                else
                    expected = uint8(edge(volume(:, :, 2), 'Sobel', 0.05));
                end
                testCase.verifyEqual(selection(:, :, 2), expected, ['threshold "' threshold{1} '"']);
                testCase.verifyTrue(all(selection(:, :, [1 3]) == 1, 'all'), 'other slices untouched');
            end

            mibModel.I{1}.orientation = 1;
            BatchOpt.Threshold = '0.05';
            testCase.verifyError(@() controllers.ImageFilters(mibModel, [], BatchOpt), 'controllers:ImageFilters:bigData');
        end

        function binarizationRefusals(testCase)
            % Each refusal raises headless and writes nothing.
            [mibModel, ~, scratch] = testCase.buildBigData(1);
            BatchOpt = testCase.edgeBatchOpt(mibModel, 'Sobel', 'selection');
            testCase.verifyError(@() controllers.ImageFilters(mibModel, [], BatchOpt), ...
                'controllers:ImageFilters:bigData', 'no model');

            labels = testCase.attachModel(mibModel, scratch);
            canny = testCase.edgeBatchOpt(mibModel, 'Canny', 'selection');
            testCase.verifyError(@() controllers.ImageFilters(mibModel, [], canny), 'controllers:ImageFilters:bigData', 'Canny');
            noThreshold = canny;
            noThreshold.Threshold = '';
            testCase.verifyError(@() controllers.ImageFilters(mibModel, [], noThreshold), ...
                'controllers:ImageFilters:bigData', 'Canny with an automatic threshold');
            slic = BatchOpt;
            slic.FilterName = {'SlicClustering'};
            testCase.verifyError(@() controllers.ImageFilters(mibModel, [], slic), 'controllers:ImageFilters:bigData', 'SLIC');
            testCase.verifyEqual(nnz(labels.getData63('selection', 3, [], struct('pyramidLevel', 1))), 0);
        end

        function doNotOpenWritesTheStoreOnly(testCase)
            [mibModel, ~, scratch] = testCase.buildBigData(1);
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'storeonly.zarr3'), 'Do not open');
            controllers.ImageFilters(mibModel, [], BatchOpt);

            testCase.verifyTrue(isfolder(BatchOpt.BigData_OutputPath));
            testCase.verifyEqual(mibModel.I{2}.image.filename, 'none.tif', 'no buffer may be changed');
        end

        function filterNotOfferedOnBigDataErrors(testCase)
            % Headless, a refusal must raise rather than return as if it had worked.
            [mibModel, ~, scratch] = testCase.buildBigData(1);
            refusals = {'DNNdenoise', 'Edge-Preserving Filtering', struct(); ...
                'UnsharpMask', 'Contrast Adjustment', struct('Threshold', {{0.2}}); ...
                'MathOps', 'Basic Image Filtering in the Spatial Domain', struct('OutputImageClass', {{'uint16'}}); ...
                'Gaussian', 'Basic Image Filtering in the Spatial Domain', struct('DatasetType', {{'2D, Slice'}})};
            for caseIndex = 1:size(refusals, 1)
                BatchOpt = testCase.filterBatchOpt(mibModel, refusals{caseIndex, 1}, refusals{caseIndex, 2}, ...
                    refusals{caseIndex, 3}, fullfile(scratch, 'refused.zarr3'));
                testCase.verifyError(@() controllers.ImageFilters(mibModel, [], BatchOpt), ...
                    'controllers:ImageFilters:bigData', refusals{caseIndex, 1});
                testCase.verifyFalse(isfolder(BatchOpt.BigData_OutputPath));
            end
        end

        function localFiltersMatchStandardInBands(testCase)
            % The filters with a neighbourhood from their own settings, in 64-row
            % bands, equal the Standard path on the whole slices. An empty noise
            % parameter of Wiener and NonLocalMeans is estimated per slice as
            % MATLAB does: equal up to the order of summation, so at most a few
            % pixels by 1 grey level.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            filterCases = {
                'Entropy', 'Basic Image Filtering in the Spatial Domain', struct('NeighborhoodSize', '5'), true; ...
                'Range', 'Basic Image Filtering in the Spatial Domain', struct('NeighborhoodSize', '3', 'StrelShape', {{'disk'}}), true; ...
                'Std', 'Basic Image Filtering in the Spatial Domain', struct('NeighborhoodSize', '7 3'), true; ...
                'SaltAndPepper', 'Basic Image Filtering in the Spatial Domain', struct('HSize', '5', 'IntensityThreshold', {{20}}), true; ...
                'Frangi', 'Basic Image Filtering in the Spatial Domain', struct('ThicknessRange', '2 6'), true; ...
                'Bilateral', 'Edge-Preserving Filtering', struct(), true; ...
                'AnisotropicDiffusion', 'Edge-Preserving Filtering', struct('NumberOfIterations', {{6}}), true; ...
                'Wiener', 'Edge-Preserving Filtering', struct('NeighborhoodSize', '5', 'AdditiveNoise', '0.002'), true; ...
                'Wiener', 'Edge-Preserving Filtering', struct('NeighborhoodSize', '5', 'AdditiveNoise', ''), false; ...
                'NonLocalMeans', 'Edge-Preserving Filtering', struct('DegreeOfSmoothing', '12', 'SearchWindowSize', '11'), true; ...
                'NonLocalMeans', 'Edge-Preserving Filtering', struct('DegreeOfSmoothing', '', 'SearchWindowSize', '11'), false; ...
                'UnsharpMask', 'Contrast Adjustment', struct('Radius', {{2}}, 'Amount', {{1.2}}), true};
            for caseIndex = 1:size(filterCases, 1)
                filterName = filterCases{caseIndex, 1};
                BatchOpt = testCase.filterBatchOpt(mibModel, filterName, filterCases{caseIndex, 2}, ...
                    filterCases{caseIndex, 3}, fullfile(scratch, sprintf('case%d.zarr3', caseIndex)));
                tool = controllers.ImageFilters(mibModel, [], NaN);
                tool.bigDataOptions.BandBytes = 8 * 260 * 40;     % 40 rows, rounded by the saver to the 64-row chunks
                tool.BatchOpt = utils.updateBatchOptCombineFields_Shared(tool.BatchOpt, BatchOpt);
                tool.Filter([], 1);

                standardOptions = tool.BatchOpt;
                standardOptions.DatasetType = {'3D, Stack'};
                standardOptions.UseParallelComputing = false;
                expected = utils.doImageFiltering(reshape(volume, [size(volume, 1:3), 1]), standardOptions);
                result = testCase.readImage(mibModel.I{2});
                label = sprintf('%s %s', filterName, jsonencode(filterCases{caseIndex, 3}));
                testCase.verifyFalse(isequal(result, reshape(volume, size(result))), [label ': the filter changes the image']);
                if filterCases{caseIndex, 4}
                    testCase.verifyEqual(result, expected, label);
                else
                    difference = abs(double(result) - double(expected));
                    testCase.verifyLessThanOrEqual(max(difference(:)), 1, label);
                    testCase.verifyLessThan(nnz(difference) / numel(difference), 1e-3, label);
                end
            end
        end

        function wholeSliceFiltersMatchStandard(testCase)
            % The filters depending on the whole slice take that part from the
            % finest level within GuidePixels, here s0 itself, so the 64-row bands
            % equal the Standard path up to the rounding of the class conversion.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            [mibModelRGB, volumeRGB, scratchRGB] = testCase.buildBigData(3);
            for caseIndex = 1:size(testCase.WholeSliceCases, 1)
                filterCase = testCase.WholeSliceCases(caseIndex, :);
                if filterCase{4}
                    [model, source, folder] = deal(mibModelRGB, volumeRGB, scratchRGB);
                else
                    [model, source, folder] = deal(mibModel, volume, scratch);
                end
                [result, expected] = testCase.runAgainstStandard(model, source, filterCase, ...
                    fullfile(folder, sprintf('whole%d.zarr3', caseIndex)), 8 * 260 * 40 * 4, 32e6);
                label = sprintf('%s %s', filterCase{1}, jsonencode(filterCase{3}));
                testCase.verifyFalse(isequal(result, source), [label ': the filter changes the image']);
                difference = abs(double(result) - double(expected));
                testCase.verifyLessThanOrEqual(max(difference(:)), 1, label);
                testCase.verifyLessThan(nnz(difference) / numel(difference), 1e-3, label);
            end
        end

        function wholeSliceFiltersHaveNoSeams(testCase)
            % With a budget below s0 the whole-slice part comes from s1: bands of
            % 64 rows give the result of a single band. approxdcp, sized to the
            % whole image, is refused for a slice above the budget.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            [mibModelRGB, volumeRGB, scratchRGB] = testCase.buildBigData(3);
            for caseIndex = 1:size(testCase.WholeSliceCases, 1)
                filterCase = testCase.WholeSliceCases(caseIndex, :);
                if filterCase{4}
                    [model, source, folder] = deal(mibModelRGB, volumeRGB, scratchRGB);
                else
                    [model, source, folder] = deal(mibModel, volume, scratch);
                end
                label = sprintf('%s %s', filterCase{1}, jsonencode(filterCase{3}));
                if isfield(filterCase{3}, 'Method') && strcmp(filterCase{3}.Method{1}, 'approxdcp')
                    % sized to the whole image: only for a slice within the budget
                    testCase.verifyError(@() testCase.runAgainstStandard(model, source, filterCase, ...
                        fullfile(folder, sprintf('refused%d.zarr3', caseIndex)), 8 * 260 * 40 * 4, 150 * 130), ...
                        'controllers:ImageFilters:bigData', label);
                    continue;
                end
                banded = testCase.runAgainstStandard(model, source, filterCase, ...
                    fullfile(folder, sprintf('bands%d.zarr3', caseIndex)), 8 * 260 * 40 * 4, 150 * 130);
                oneBand = testCase.runAgainstStandard(model, source, filterCase, ...
                    fullfile(folder, sprintf('single%d.zarr3', caseIndex)), 1e9, 150 * 130);
                seam = abs(double(banded) - double(oneBand));
                testCase.verifyLessThanOrEqual(max(seam(:)), 1, [label ': bands and a single band']);
                testCase.verifyFalse(isequal(banded, source), [label ': the filter changes the image']);
            end
        end

        function wholeSliceFiltersFromACoarserLevel(testCase)
            % The whole-slice part from s1 (half the size) on a micrograph and an
            % H&E image of the Image Processing Toolbox: the mean difference to
            % the Standard result stays within the measured accuracy of each filter.
            images = {'AT3_1m4_01.tif', false; 'hestain.png', true};
            for imageIndex = 1:2
                [mibModel, volume, scratch] = testCase.buildBigDataFromImage(imread(images{imageIndex, 1}));
                guidePixels = prod(mibModel.I{1}.image.pyramid.levelImageSizes(2, 1:2));
                bandBytes = 8 * size(volume, 2) * size(volume, 4) * 64 * 4;
                for caseIndex = 1:size(testCase.WholeSliceCases, 1)
                    filterCase = testCase.WholeSliceCases(caseIndex, :);
                    if filterCase{4} ~= images{imageIndex, 2} || (isfield(filterCase{3}, 'Method') && ...
                            strcmp(filterCase{3}.Method{1}, 'approxdcp'))
                        continue;
                    end
                    [result, expected] = testCase.runAgainstStandard(mibModel, volume, filterCase, ...
                        fullfile(scratch, sprintf('coarse%d.zarr3', caseIndex)), bandBytes, guidePixels);
                    difference = abs(double(result) - double(expected));
                    testCase.verifyLessThan(mean(difference(:)), filterCase{5}, ...
                        sprintf('%s %s on %s', filterCase{1}, jsonencode(filterCase{3}), images{imageIndex, 1}));
                end
            end
        end

        function elasticDistortionInBands(testCase)
            % The random field is generated per row: the same result in 64-row
            % bands and in one band; the image moves; a model is not distorted.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            settings = struct('ScalingFactor', {{30}}, 'Sigma', {{4}}, 'DistortAllLAyers', false);
            outputs = cell(1, 2);
            bandBytes = [8 * 260 * 40, 1e9];
            for runIndex = 1:2
                BatchOpt = testCase.filterBatchOpt(mibModel, 'ElasticDistortion', ...
                    'Basic Image Filtering in the Spatial Domain', settings, fullfile(scratch, sprintf('elastic%d.zarr3', runIndex)));
                tool = controllers.ImageFilters(mibModel, [], NaN);
                tool.bigDataOptions.BandBytes = bandBytes(runIndex);
                tool.BatchOpt = utils.updateBatchOptCombineFields_Shared(tool.BatchOpt, BatchOpt);
                tool.Filter([], 1);
                outputs{runIndex} = testCase.readImage(mibModel.I{2});
            end
            testCase.verifyEqual(outputs{1}, outputs{2});
            difference = abs(double(outputs{1}(20:end-20, 20:end-20, :)) - double(volume(20:end-20, 20:end-20, :)));
            testCase.verifyGreaterThan(mean(difference(:)), 1, 'the image is distorted');

            testCase.attachModel(mibModel, scratch);
            mibModel.I{1}.modelExist = true;
            BatchOpt.DistortAllLAyers = true;
            testCase.verifyError(@() controllers.ImageFilters(mibModel, [], BatchOpt), 'controllers:ImageFilters:bigData');
        end

        function bm3dInBands(testCase)
            % BMxD in bands with the halo of its search windows and the block grid
            % of the slice. BM3D is not local to the last bit (its noise spectrum
            % and matching threshold come from the image it gets, its threads
            % aggregate in any order), so a third of the pixels round to the next
            % grey level; measured 2026-11-06 on a micrograph: mean 0.09, 99th
            % percentile 0.6, independent of the halo above 35 rows.
            testCase.assumeEqual(exist('BM3DProfile', 'file'), 2, 'BM3D 4.x is not on the path');
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            filterCase = {'BMxD', 'Edge-Preserving Filtering', struct('Sigma', {{6}}, 'Profile', {{'np'}}), false};
            [result, expected] = testCase.runAgainstStandard(mibModel, volume, filterCase, ...
                fullfile(scratch, 'bm3d.zarr3'), 8 * 260 * 40, 32e6);
            difference = abs(double(result) - double(expected));
            testCase.verifyFalse(isequal(result, volume));
            testCase.verifyLessThan(mean(difference(:)), 0.5);
            testCase.verifyLessThanOrEqual(prctile(difference(:), 99), 2);
        end

        function pixelFiltersInBands(testCase)
            % MathOps on all channels adds the value once to each (it used to add
            % it once per channel); AddNoise adds noise of the requested spread.
            [mibModel, volume, scratch] = testCase.buildBigData(3);
            BatchOpt = testCase.filterBatchOpt(mibModel, 'MathOps', 'Basic Image Filtering in the Spatial Domain', ...
                struct('Operation', {{'Add'}}, 'Value', '5'), fullfile(scratch, 'add.zarr3'));
            BatchOpt.ColorChannel = {'All'};
            controllers.ImageFilters(mibModel, [], BatchOpt);
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), volume + 5);

            BatchOpt = testCase.filterBatchOpt(mibModel, 'AddNoise', 'Contrast Adjustment', ...
                struct('Mode', {{'gaussian'}}, 'Mean', '0', 'Variance', '0.001'), fullfile(scratch, 'noise.zarr3'));
            BatchOpt.ColorChannel = {'All'};
            controllers.ImageFilters(mibModel, [], BatchOpt);
            difference = double(testCase.readImage(mibModel.I{2})) - double(volume);
            testCase.verifyLessThan(abs(mean(difference(:))), 1);
            testCase.verifyEqual(std(difference(:)), 255 * sqrt(0.001), 'RelTol', 0.1);
        end

        function standardDatasetIgnoresBigDataFields(testCase)
            % On a Standard dataset the BigData_* fields are ignored and the image is
            % filtered in place, as before they existed; no store is written.
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel(dims = [64 64 4]);
            scratch = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'unused.zarr3'), 'Container 2');
            BatchOpt.DatasetType = {'3D, Stack'};
            controllers.ImageFilters(mibModel, [], BatchOpt);

            result = mibModel.I{1}.image.data;
            testCase.verifyEqual(result, testCase.gaussianOfSlices(groundTruth.image, BatchOpt));
            testCase.verifyFalse(isfolder(BatchOpt.BigData_OutputPath));
        end

        function openStoreIsRefused(testCase)
            % Writing into the store of the open source would delete the data being read.
            [mibModel, ~, ~] = testCase.buildBigData(1);
            BatchOpt = testCase.gaussianBatchOpt(mibModel, mibModel.I{1}.image.filename, 'Container 2');
            testCase.verifyError(@() controllers.ImageFilters(mibModel, [], BatchOpt), 'controllers:ImageFilters:bigData');
            testCase.verifyEqual(mibModel.I{2}.image.filename, 'none.tif');
            % the message names the store as the dataset's own and says that its image is locked
            try
                controllers.ImageFilters(mibModel, [], BatchOpt);
            catch exception
                testCase.verifySubstring(exception.message, 'store of this dataset (buffer 1), whose image is locked');
            end
            mibModel.setLockedState(1, 'image', false);
            try
                controllers.ImageFilters(mibModel, [], BatchOpt);
                testCase.verifyFail('an unlocked source store is refused too');
            catch exception
                testCase.verifySubstring(exception.message, 'or set Open in to "Current overwrite (BigData)"');
                testCase.verifyFalse(contains(exception.message, 'locked'));
            end
        end

        function roiCropsTheStore(testCase)
            % Restrict to ROI with a rectangle: the new store is the box of the ROI, equal
            % to that part of the whole-slice Gaussian (the halo is read around the box),
            % and its bounding box starts at the box.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            testCase.addRoi(mibModel, 'rectangle', [41; 180], [57; 210]);
            sourceImage = mibModel.I{1}.image;
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'roi.zarr3'), 'Container 2');
            controllers.ImageFilters(mibModel, [], BatchOpt);

            expected = testCase.gaussianOfSlices(volume, BatchOpt);
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), expected(57:210, 41:180, :, :));
            boundingBox = mibModel.I{2}.image.boundingBox;
            testCase.verifyEqual(boundingBox([1 3]), sourceImage.boundingBox([1 3]) + [40 56] * 0.02, 'AbsTol', 1e-9);
        end

        function roiPolygonIntoMemory(testCase)
            % A triangle ROI into a Standard dataset at s1: the box of the ROI at the level;
            % inside the triangle the Gaussian of the level, outside it the level as it is.
            [mibModel, ~, ~] = testCase.buildBigData(1);
            testCase.addRoi(mibModel, 'polygon', [40; 200; 40], [60; 60; 220]);
            levelVolume = mibModel.I{1}.image.getData('image', 3, [], struct('pyramidLevel', 2));
            levelVolume = reshape(levelVolume, size(levelVolume, 1), size(levelVolume, 2), size(levelVolume, 3));
            BatchOpt = testCase.gaussianBatchOpt(mibModel, '', 'Container 2');
            BatchOpt.BigData_Result = {'Standard (in memory)'};
            BatchOpt.BigData_PyramidLevel = {'s1'};
            controllers.ImageFilters(mibModel, [], BatchOpt);

            rows = 30:110;     % ceil([60 220] / 2)
            columns = 20:100;  % ceil([40 200] / 2)
            result = mibModel.I{2}.image.data(:, :, :, 1, 1);
            testCase.verifySize(result, [numel(rows), numel(columns), 3]);
            filtered = testCase.gaussianOfSlices(levelVolume, BatchOpt);
            % the triangle at the level, in box coordinates; its outline pixels are left out
            triangle = poly2mask(([40 200 40] - 0.5) / 2 + 0.5 - (columns(1) - 1), ...
                ([60 60 220] - 0.5) / 2 + 0.5 - (rows(1) - 1), numel(rows), numel(columns));
            inside = repmat(imerode(triangle, ones(3)), 1, 1, 3);
            outside = repmat(~imdilate(triangle, ones(5)), 1, 1, 3);
            filtered = filtered(rows, columns, :);
            source = levelVolume(rows, columns, :);
            testCase.verifyEqual(result(inside), filtered(inside));
            testCase.verifyEqual(result(outside), source(outside));
            testCase.verifyGreaterThan(nnz(outside), 1000);
        end

        function roiOverwriteInPlace(testCase)
            % "Current overwrite (BigData)" with a rectangle ROI writes the box of every slice
            % into the store (rows and columns off the 64-px chunks); every level equals a
            % store saved from the expected volume.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            testCase.addRoi(mibModel, 'rectangle', [37; 150], [45; 201]);
            mibModel.setLockedState(1, 'image', false);
            sourcePath = mibModel.I{1}.image.filename;
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'unused.zarr3'), 'Current overwrite (BigData)');
            tool = controllers.ImageFilters(mibModel, [], NaN);
            tool.bigDataOptions.BandBytes = 8 * 114 * 40;    % 40 rows, rounded to the chunks: several bands
            tool.BatchOpt = utils.updateBatchOptCombineFields_Shared(tool.BatchOpt, BatchOpt);
            tool.Filter([], 1);

            expected = volume;
            filtered = testCase.gaussianOfSlices(volume, BatchOpt);
            expected(45:201, 37:150, :) = filtered(45:201, 37:150, :);
            testCase.verifyEqual(testCase.readImage(mibModel.I{1}), expected);
            referencePath = fullfile(scratch, 'reference.zarr3');
            io.savers.Zarr3Saver(struct()).save(reshape(expected, 300, 260, 3, 1, 1), ...
                struct('pixSize', struct('x', 0.02, 'y', 0.02, 'z', 0.05, 'units', 'um')), referencePath, ...
                struct('silent', true, 'showWaitbar', false, 'ChunkSize', [64 64 1], 'Levels', 3, 'DownsampleStrategy', 'XY only'));
            levelNames = mibModel.I{1}.image.pyramid.levelNames;
            for levelIndex = 1:numel(levelNames)
                testCase.verifyEqual(io.zarr.Array(fullfile(sourcePath, levelNames{levelIndex})).read(), ...
                    io.zarr.Array(fullfile(referencePath, levelNames{levelIndex})).read(), sprintf('level s%d', levelIndex - 1));
            end
            listing = dir(scratch);
            testCase.verifyEmpty(listing(contains({listing.name}, '.mib_')), 'the temporary array must be removed');
        end

        function roiEdgesIntoTheSelection(testCase)
            % Edge into the selection with a triangle ROI: inside the triangle the edges of
            % the whole slice, outside it the selection as it was (here all set).
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            labels = testCase.attachModel(mibModel, scratch);
            labels.setData63(ones(300, 260, 3, 'uint8'), 'selection', 3, [], struct('pyramidLevel', 1));
            testCase.addRoi(mibModel, 'polygon', [40; 200; 40], [60; 60; 220]);
            controllers.ImageFilters(mibModel, [], testCase.edgeBatchOpt(mibModel, 'Sobel', 'selection'));

            selection = labels.getData63('selection', 3, [], struct('pyramidLevel', 1));
            edges = testCase.edgeOfSlices(volume, 'Sobel', 0.05);
            triangle = poly2mask([40 200 40], [60 60 220], 300, 260);
            inside = repmat(imerode(triangle, ones(3)), 1, 1, 3);
            outside = repmat(~imdilate(triangle, ones(3)), 1, 1, 3);
            testCase.verifyEqual(selection(inside), edges(inside));
            testCase.verifyTrue(all(selection(outside) == 1), 'the selection outside the ROI is kept');
        end

        function resumeAfterAFailedRun(testCase)
            % A run that fails at slice 3 (its source chunks corrupted) leaves a resumable
            % store with the settings of the run; with the chunks back, a resume finishes it
            % and equals a whole run. A resume with another sigma is refused.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            sourcePath = mibModel.I{1}.image.filename;
            outputPath = fullfile(scratch, 'resumed.zarr3');
            sliceChunks = dir(fullfile(sourcePath, '0', 'c', '*', '*', '2'));
            if isempty(sliceChunks); sliceChunks = dir(fullfile(sourcePath, 's0', 'c', '*', '*', '2')); end
            testCase.assumeNotEmpty(sliceChunks, 'the chunk files of slice 3 must be found');
            backupFolder = fullfile(scratch, 'chunkBackup');
            mkdir(backupFolder);
            for chunkIndex = 1:numel(sliceChunks)
                chunkFile = fullfile(sliceChunks(chunkIndex).folder, sliceChunks(chunkIndex).name);
                copyfile(chunkFile, fullfile(backupFolder, sprintf('%d', chunkIndex)));
                fileId = fopen(chunkFile, 'w'); fwrite(fileId, uint8(1:7)); fclose(fileId);
            end

            BatchOpt = testCase.gaussianBatchOpt(mibModel, outputPath, 'Do not open');
            tool = controllers.ImageFilters(mibModel, [], NaN);
            tool.bigDataOptions.ResumeIncomplete = true;
            tool.BatchOpt = utils.updateBatchOptCombineFields_Shared(tool.BatchOpt, BatchOpt);
            testCase.verifyError(@() tool.Filter([], 1), 'controllers:ImageFilters:bigData');
            testCase.verifyTrue(isfile(fullfile(outputPath, '.mib_resume.json')), 'the failed store stays resumable');
            testCase.verifyTrue(isfile(fullfile(outputPath, '.mib_run_settings.mat')), 'with the settings of the run');
            testCase.verifyNotEmpty(strtrim(fileread(fullfile(outputPath, '.mib_progress.log'))), 'slices 1-2 are recorded');

            for chunkIndex = 1:numel(sliceChunks)
                copyfile(fullfile(backupFolder, sprintf('%d', chunkIndex)), ...
                    fullfile(sliceChunks(chunkIndex).folder, sliceChunks(chunkIndex).name));
            end
            io.zarr.ChunkCache.clear();
            otherSigma = tool.BatchOpt;
            otherSigma.Sigma = {2.5};
            otherTool = controllers.ImageFilters(mibModel, [], NaN);
            otherTool.bigDataOptions.ResumeIncomplete = true;
            otherTool.BatchOpt = utils.updateBatchOptCombineFields_Shared(otherTool.BatchOpt, otherSigma);
            testCase.verifyError(@() otherTool.Filter([], 1), 'controllers:ImageFilters:bigData', 'another sigma is refused');

            tool.Filter([], 1);
            testCase.verifyFalse(isfile(fullfile(outputPath, '.mib_resume.json')), 'the store is complete');
            testCase.verifyFalse(isfile(fullfile(outputPath, '.mib_run_settings.mat')));
            controllers.BigDataOptions.openStoreInBuffer(mibModel, outputPath, 2);
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), testCase.gaussianOfSlices(volume, BatchOpt));
        end

        function roiIgnoredWhenUnchecked(testCase)
            % With Restrict to ROI off the ROI does not limit the run.
            [mibModel, volume, scratch] = testCase.buildBigData(1);
            testCase.addRoi(mibModel, 'rectangle', [41; 180], [57; 210]);
            mibModel.I{1}.restrictToROI = false;
            BatchOpt = testCase.gaussianBatchOpt(mibModel, fullfile(scratch, 'whole.zarr3'), 'Container 2');
            controllers.ImageFilters(mibModel, [], BatchOpt);
            testCase.verifyEqual(testCase.readImage(mibModel.I{2}), testCase.gaussianOfSlices(volume, BatchOpt));
        end
    end

    methods
        function [mibModel, volume, scratch] = buildBigData(testCase, colors)
            % A 300 x 260 x 3 uint8 BigData dataset with ``colors`` channels in buffer 1.
            [mibModel, volume, scratch] = mibtest.helpers.buildBigDataModel(testCase, colors);
        end

        function [mibModel, volume, scratch] = buildBigDataFromImage(testCase, image)
            % A one-slice BigData dataset of ``image`` (3 levels, 64 x 64 chunks) in buffer 1; ``volume`` is [H W 1 C].
            scratch = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            [height, width, colors] = size(image);
            sourcePath = fullfile(scratch, 'source.zarr3');
            metadata = struct('pixSize', struct('x', 0.02, 'y', 0.02, 'z', 0.05, 'units', 'um'));
            io.savers.Zarr3Saver(struct()).save(reshape(image, height, width, 1, colors, 1), metadata, sourcePath, ...
                struct('silent', true, 'showWaitbar', false, 'ChunkSize', [64 64 1], 'Levels', 3, ...
                'DownsampleStrategy', 'XY only'));
            volume = reshape(image, height, width, 1, colors);
            mibFolder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'mib');
            mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            controllers.BigDataOptions.openStoreInBuffer(mibModel, sourcePath, 1);
        end

        function addRoi(~, mibModel, roiType, X, Y)
            % An XY ROI of buffer 1 in full-resolution pixels, with Restrict to ROI on and All selected.
            roi.label = cellstr('1');
            roi.type = cellstr(roiType);
            roi.X = X;
            roi.Y = Y;
            roi.orientation = 3;
            roi.BoundingBox.x = [min(X); max(X)];
            roi.BoundingBox.y = [min(Y); max(Y)];
            mibModel.I{1}.hROI.storeROI(roi);
            mibModel.I{1}.selectedROI = 0;
            mibModel.I{1}.restrictToROI = true;
        end

        function labels = attachModel(testCase, mibModel, scratch)
            % An empty BigData model store next to the source, attached to buffer 1.
            labels = mibtest.helpers.attachBigDataLabels(testCase, mibModel, scratch);
        end

        function BatchOpt = gaussianBatchOpt(~, mibModel, outputPath, openIn)
            % Batch options of a Gaussian (the session defaults) to a new store.
            if ~isfield(mibModel.sessionSettings, 'ImageFilters')
                controllers.ImageFilters(mibModel, [], NaN);   % creates the session defaults
            end
            BatchOpt = rmfield(mibModel.sessionSettings.ImageFilters.Gaussian, 'mibBatchTooltip');
            BatchOpt.DatasetType = {'3D, Stack'};     % "2D, Slice" is refused for a new store
            BatchOpt.FilterGroup = {'Basic Image Filtering in the Spatial Domain'};
            BatchOpt.FilterName = {'Gaussian'};
            BatchOpt.Sigma = {1.5};
            BatchOpt.HSize = '7';
            BatchOpt.showWaitbar = false;
            BatchOpt.BigData_OutputPath = outputPath;
            BatchOpt.BigData_OpenIn = {openIn};
        end

        function BatchOpt = filterBatchOpt(~, mibModel, filterName, filterGroup, settings, outputPath)
            % Batch options of ``filterName`` (the session defaults, then ``settings``) on channel 1 into a new store opened in buffer 2.
            if ~isfield(mibModel.sessionSettings, 'ImageFilters')
                controllers.ImageFilters(mibModel, [], NaN);   % creates the session defaults
            end
            BatchOpt = rmfield(mibModel.sessionSettings.ImageFilters.(filterName), 'mibBatchTooltip');
            BatchOpt.DatasetType = {'3D, Stack'};     % a new store holds the whole dataset, "2D, Slice" is refused
            for fieldName = fieldnames(settings)'
                BatchOpt.(fieldName{1}) = settings.(fieldName{1});
            end
            BatchOpt.FilterGroup = {filterGroup};
            BatchOpt.FilterName = {filterName};
            BatchOpt.ColorChannel = {'1'};
            BatchOpt.showWaitbar = false;
            BatchOpt.BigData_PyramidLevel = {'s0'};
            BatchOpt.BigData_OutputPath = outputPath;
            BatchOpt.BigData_OpenIn = {'Container 2'};
        end

        function [result, expected] = runAgainstStandard(testCase, mibModel, volume, filterCase, outputPath, bandBytes, guidePixels)
            % Filter buffer 1 into buffer 2 with the given band and guide budgets; ``expected`` is the Standard path on the volume.
            BatchOpt = testCase.filterBatchOpt(mibModel, filterCase{1}, filterCase{2}, filterCase{3}, outputPath);
            if filterCase{4}
                BatchOpt.ColorChannel = {'All'};
                BatchOpt.useRGB = true;
            end
            tool = controllers.ImageFilters(mibModel, [], NaN);
            tool.bigDataOptions.BandBytes = bandBytes;
            tool.bigDataOptions.GuidePixels = guidePixels;
            tool.BatchOpt = utils.updateBatchOptCombineFields_Shared(tool.BatchOpt, BatchOpt);
            tool.Filter([], 1);
            result = testCase.readImage(mibModel.I{2});

            standardOptions = tool.BatchOpt;
            standardOptions.DatasetType = {'3D, Stack'};
            standardOptions.UseParallelComputing = false;
            if filterCase{4}
                expected = utils.doImageFiltering(volume, standardOptions);
            else
                expected = utils.doImageFiltering(reshape(volume(:, :, :, 1), [size(volume, 1:3), 1]), standardOptions);
            end
            expected = reshape(expected, size(result));
        end

        function BatchOpt = edgeBatchOpt(~, mibModel, method, layer)
            % Batch options of Edge (the session defaults) with ``method``, threshold 0.05, into ``layer``.
            if ~isfield(mibModel.sessionSettings, 'ImageFilters')
                controllers.ImageFilters(mibModel, [], NaN);   % creates the session defaults
            end
            BatchOpt = rmfield(mibModel.sessionSettings.ImageFilters.Edge, 'mibBatchTooltip');
            BatchOpt.FilterGroup = {'Image Binarization'};
            BatchOpt.FilterName = {'Edge'};
            BatchOpt.Method = {method};
            BatchOpt.Threshold = '0.05';
            BatchOpt.DestinationLayer = {layer};
            BatchOpt.ColorChannel = {'1'};
            BatchOpt.DatasetType = {'3D, Stack'};
            BatchOpt.showWaitbar = false;
            BatchOpt.BigData_PyramidLevel = {'s0'};
        end

        function expected = edgeOfSlices(~, volume, method, threshold)
            % edge() of every whole slice, as uint8 0/1.
            expected = zeros(size(volume, 1:3), 'uint8');
            for z = 1:size(volume, 3)
                expected(:,:,z) = edge(volume(:,:,z), method, threshold);
            end
        end

        function expected = gaussianOfSlices(~, volume, BatchOpt)
            % imgaussfilt of every whole slice and channel, with the batch parameters.
            expected = volume;
            for channel = 1:size(volume, 4)
                for z = 1:size(volume, 3)
                    expected(:,:,z,channel) = imgaussfilt(volume(:,:,z,channel), BatchOpt.Sigma{1}, ...
                        'FilterSize', str2double(BatchOpt.HSize), 'Padding', BatchOpt.Padding{1}, ...
                        'FilterDomain', BatchOpt.FilterDomain{1});
                end
            end
        end
    end

    methods (Static)
        function data = readImage(dataset)
            % Level 1 of a BigData image as [H W Z C].
            data = dataset.image.getData('image', 3, [], struct('pyramidLevel', 1));
            data = reshape(data, size(data, 1), size(data, 2), size(data, 3), size(data, 4));
        end
    end
end
