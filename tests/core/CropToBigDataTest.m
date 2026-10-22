classdef CropToBigDataTest < matlab.unittest.TestCase
% CROPTOBIGDATATEST - core.MibDataset.cropToBigData writes the crop like its source.
%
% A synthetic sharded BigData pyramid with a model is cropped to a new store. The
% cropped image must keep the source chunk, shard, level count and scale factors,
% and the model store written next to it must have exactly the image's levels.
% Writes to disk and drives the zarr saver and loader, so tagged Integration.
%
% See also: core.MibDataset.cropToBigData, io.savers.Zarr3Saver.optionsFromPyramid

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function cropKeepsSourcePyramidAndModelMatchesImage(testCase)
            [mibModel, scratch] = testCase.buildShardedBigData();
            source = mibModel.I{1}.image.pyramid;

            outputPath = fullfile(scratch, 'crop.zarr3');
            % a crop far smaller than the source: the automatic level count would stop at 1
            result = mibModel.I{1}.cropToBigData([33 17 300 280 2 5], ...
                struct('outputPath', outputPath, 'showWaitbar', false));
            testCase.verifyEqual(result, 1);

            cropped = testCase.loadBigData(outputPath);
            testCase.verifyEqual(size(cropped.levelImageSizes, 1), size(source.levelImageSizes, 1), ...
                'level count must match the source');
            testCase.verifyEqual(cropped.levelScaleFactors, source.levelScaleFactors, ...
                'scale factors must match the source level by level');
            testCase.verifyEqual(cropped.chunkSizes{1}, source.chunkSizes{1}, 'chunk must match the source');
            testCase.verifyEqual(cropped.shardSizes{1}, source.shardSizes{1}, 'shard must match the source');
            testCase.verifyEqual(cropped.levelImageSizes(1, :), [280 300 5], 'level 0 is the crop');

            modelStore = fullfile(scratch, 'Labels_crop.zarr3');
            testCase.assertTrue(isfolder(modelStore), 'the model store must be written');
            labels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            labels.openStore(modelStore);
            testCase.verifyEqual(labels.modelLevelSizes, cropped.levelImageSizes, ...
                'model levels must equal image levels');
            testCase.verifyEqual(labels.modelScaleFactors, cropped.levelScaleFactors, ...
                'model scale factors must equal image scale factors');
            labelsLevel0 = labels.getData63('labels', 3, [], struct('pyramidLevel', 1));
            labels.closeStore();
            % the 80 x 80 block lies inside the crop; slices 2-6 are kept
            testCase.verifyEqual(nnz(labelsLevel0 == 3), 80 * 80 * 5, 'the painted block must survive the crop');
        end

        function saverOptionsOverrideTheSource(testCase)
            % options.saverOptions (the dialog result) wins over the source settings
            [mibModel, scratch] = testCase.buildShardedBigData();
            outputPath = fullfile(scratch, 'crop.zarr3');
            saverOptions = io.savers.Zarr3Saver.optionsFromPyramid(mibModel.I{1}.image.pyramid);
            saverOptions.ChunkSize = [32 32 1];
            saverOptions.Levels = 2;
            saverOptions = rmfield(saverOptions, 'ShardSize');
            result = mibModel.I{1}.cropToBigData([1 1 200 200 1 6], ...
                struct('outputPath', outputPath, 'showWaitbar', false, 'saverOptions', saverOptions));
            testCase.verifyEqual(result, 1);

            cropped = testCase.loadBigData(outputPath);
            testCase.verifyEqual(size(cropped.levelImageSizes, 1), 2);
            testCase.verifyEqual(cropped.chunkSizes{1}(1:3), [32 32 1]);
            labels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            labels.openStore(fullfile(scratch, 'Labels_crop.zarr3'));
            testCase.verifyEqual(labels.modelLevelSizes, cropped.levelImageSizes);
            labels.closeStore();
        end
    end

    methods (Access = private)
        function [mibModel, scratch] = buildShardedBigData(testCase)
            % 600 x 640 x 8 voxels, chunk [64 64 2], shard 2 x 2 x 1 chunks, 4 levels,
            % anisotropy-preserving, with a model holding an 80 x 80 x 8 block of material 3
            folderFixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            scratch = folderFixture.Folder;
            sourceImage  = fullfile(scratch, 'src.zarr3');
            sourceLabels = fullfile(scratch, 'Labels_src.zarr3');
            height = 600; width = 640; depth = 8;
            rng(3);
            volume = uint8(randi(255, height, width, depth));
            meta = struct('pixSize', struct('x', 0.01, 'y', 0.01, 'z', 0.03, 'units', 'um'));
            io.savers.Zarr3Saver(struct()).save(volume, meta, sourceImage, ...
                struct('silent', true, 'showWaitbar', false, 'ChunkSize', [64 64 2], 'ShardSize', [2 2 1], ...
                'Levels', 4, 'DownsampleStrategy', 'Anisotropy-preserving'));

            mibFolder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'mib');
            mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            loaderOptions = struct('datasetMode', 'BigData');
            loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
            [imageInfo, files] = loader.loadMetadata({sourceImage}, loaderOptions);
            [image, imageInfo] = loader.loadImages(files, imageInfo, loaderOptions);
            mibModel.I{1}.initialize(image, imageInfo, 'BigData');
            mibModel.I{1}.enableSelection = true;

            labels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            labels.createStore([height width depth], sourceLabels, mibModel.I{1}.image.pyramid);
            packed = zeros(height, width, depth, 'uint8');
            packed(41:120, 51:130, :) = 3;   % covers rows 41-120, columns 51-130
            labels.setData63(packed, 'everything', 3, [], struct('pyramidLevel', 1));
            labels.materializeAll();
            labels.filename = sourceLabels;
            labels.materialNames = {'a'; 'b'; 'c'};
            labels.materialColors = lines(3);
            labels.materialsCount = 3;
            mibModel.I{1}.labels = labels;
            mibModel.I{1}.modelExist = true;

            testCase.assertNotEmpty(mibModel.I{1}.image.pyramid.shardSizes{1}, 'the source must be sharded');
            testCase.assertGreaterThan(max(diff(mibModel.I{1}.image.pyramid.levelScaleFactors(:, 3))), 0, ...
                'the source must halve Z somewhere');
        end

        function pyramid = loadBigData(~, storePath)
            loaderOptions = struct('datasetMode', 'BigData');
            loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
            [~, pyramid] = loader.loadMetadata({storePath}, loaderOptions);
        end
    end
end
