classdef ProcessImageToStoreTest < matlab.unittest.TestCase
% PROCESSIMAGETOSTORETEST - Tests for utils.bigdata.processImageToStore and io.savers.FilteredSliceProvider.
%
% A synthetic OME-Zarr v3 pyramid is opened as a BigData dataset, processed into
% a new store, and the store is read back and compared with the same function
% applied to the whole array in memory. The bands are forced small (BandBytes),
% so the comparisons test the halo: a band without enough halo rows differs from
% the whole-slice result near its edges.
%
% Write to disk and drive the zarr savers/loaders, so tagged Integration.
%
% See also: utils.bigdata.processImageToStore, io.savers.FilteredSliceProvider

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function gaussianInBandsEqualsWholeSlice(testCase)
            % Level 1 in bands of 64 rows with a 3-sigma halo equals imgaussfilt of the whole slice.
            [image, volume, scratch] = testCase.buildBigData();
            sigma = 2;
            gaussian = @(block) imgaussfilt(block, sigma);
            outputPath = utils.bigdata.processImageToStore(image, gaussian, ...
                fullfile(scratch, 'gaussian.zarr3'), HaloYX = ceil(3*sigma), ...
                BandBytes = testCase.bandBytesForRows(image, 40));
            testCase.verifyNotEmpty(outputPath);

            result = testCase.readLevel(outputPath, 1);
            expected = zeros(size(volume), 'uint8');
            for z = 1:size(volume, 3); expected(:,:,z) = imgaussfilt(volume(:,:,z), sigma); end
            testCase.verifyEqual(result, expected, ...
                'a banded Gaussian must equal the Gaussian of the whole slice');
        end

        function bandsWithoutHaloDiffer(testCase)
            % Control for the test above: without the halo the band edges differ,
            % so the equality there is evidence that the halo works.
            [image, volume, scratch] = testCase.buildBigData();
            gaussian = @(block) imgaussfilt(block, 2);
            outputPath = utils.bigdata.processImageToStore(image, gaussian, ...
                fullfile(scratch, 'nohalo.zarr3'), HaloYX = 0, ...
                BandBytes = testCase.bandBytesForRows(image, 40));
            result = testCase.readLevel(outputPath, 1);
            testCase.verifyNotEqual(result(:,:,1), imgaussfilt(volume(:,:,1), 2));
        end

        function coarseLevelGeometryAndPixelSize(testCase)
            % Level 2 gives a store of the level-2 size, twice the voxel size in XY,
            % the source bounding-box origin, and the filter of the level-2 data.
            [image, ~, scratch] = testCase.buildBigData();
            levelSize = image.pyramid.levelImageSizes(2, :);
            outputPath = utils.bigdata.processImageToStore(image, @(block) imgaussfilt(block, 1), ...
                fullfile(scratch, 'level2.zarr3'), Level = 2, HaloYX = 3);

            [result, outputImage] = testCase.readLevel(outputPath, 1);
            testCase.verifyEqual(size(result, [1 2 3]), levelSize);
            testCase.verifyEqual(outputImage.pixSize.x, 2 * image.pixSize.x, 'AbsTol', 1e-12);
            testCase.verifyEqual(outputImage.pixSize.y, 2 * image.pixSize.y, 'AbsTol', 1e-12);
            testCase.verifyEqual(outputImage.pixSize.z, image.pixSize.z, 'AbsTol', 1e-12);
            testCase.verifyEqual(outputImage.boundingBox([1 3 5]), image.boundingBox([1 3 5]), 'AbsTol', 1e-9);

            sourceLevel = image.getData('image', 3, [], struct('pyramidLevel', 2));
            expected = zeros(levelSize, 'uint8');
            for z = 1:levelSize(3); expected(:,:,z) = imgaussfilt(sourceLevel(:,:,z), 1); end
            testCase.verifyEqual(result, expected);
        end

        function threeDimensionalHalo(testCase)
            % A 3D function with a Z halo equals imgaussfilt3 of the whole volume.
            [image, volume, scratch] = testCase.buildBigData();
            gaussian3 = @(block) imgaussfilt3(block, 1);   % filter size 5: half-size 2
            outputPath = utils.bigdata.processImageToStore(image, gaussian3, ...
                fullfile(scratch, 'gaussian3.zarr3'), HaloYX = 3, HaloZ = 2, ...
                BandBytes = testCase.bandBytesForRows(image, 40));
            result = testCase.readLevel(outputPath, 1);
            testCase.verifyEqual(result, imgaussfilt3(volume, 1));
        end

        function classChangeIsWritten(testCase)
            % A function returning uint16 from uint8 writes a uint16 store.
            [image, volume, scratch] = testCase.buildBigData();
            outputPath = utils.bigdata.processImageToStore(image, @(block) uint16(block) * 256, ...
                fullfile(scratch, 'uint16.zarr3'));
            result = testCase.readLevel(outputPath, 1);
            testCase.verifyClass(result, 'uint16');
            testCase.verifyEqual(result, uint16(volume) * 256);
        end

        function floatOutputIsRefused(testCase)
            % MIB images are integer: a float result is refused before anything is written.
            [image, ~, scratch] = testCase.buildBigData();
            outputPath = fullfile(scratch, 'single.zarr3');
            testCase.verifyError(@() utils.bigdata.processImageToStore(image, @(block) single(block), ...
                outputPath), 'utils:bigdata:outputClass');
            testCase.verifyFalse(isfolder(outputPath));
        end

        function sourceStoreIsRefused(testCase)
            % Writing over the source would delete the data being read.
            [image, ~, ~] = testCase.buildBigData();
            testCase.verifyError(@() utils.bigdata.processImageToStore(image, @(block) block, ...
                image.filename), 'utils:bigdata:outputIsSource');
        end
    end

    methods
        function [image, volume, scratch] = buildBigData(testCase)
            % A 300 x 260 x 3 uint8 BigData image with 3 levels and 64 x 64 chunks.
            tf = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            scratch = tf.Folder;
            rng(4);
            height = 300; width = 260; depth = 3;
            volume = uint8(255 * mat2gray(convn(randn(height, width, depth), ones(5, 5, 1), 'same')));
            sourcePath = fullfile(scratch, 'source.zarr3');
            metadata = struct('pixSize', struct('x', 0.02, 'y', 0.03, 'z', 0.05, 'units', 'um'), ...
                'boundingBox', [10, 10 + (width-1)*0.02, 20, 20 + (height-1)*0.03, 5, 5 + (depth-1)*0.05]);
            io.savers.Zarr3Saver(struct()).save(reshape(volume, height, width, depth, 1, 1), metadata, sourcePath, ...
                struct('silent', true, 'showWaitbar', false, 'ChunkSize', [64 64 1], 'Levels', 3, ...
                'DownsampleStrategy', 'XY only'));
            image = testCase.openBigData(sourcePath);
        end

        function image = openBigData(~, storePath)
            % Open a store as the BigData dataset of a fresh headless MibModel.
            mibFolder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'mib');
            mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            loaderOptions = struct('datasetMode', 'BigData');
            loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
            [imageInfo, files] = loader.loadMetadata({storePath}, loaderOptions);
            [imageRaw, imageInfo] = loader.loadImages(files, imageInfo, loaderOptions);
            mibModel.I{1}.initialize(imageRaw, imageInfo, 'BigData');
            image = mibModel.I{1}.image;
        end

        function [data, image] = readLevel(testCase, storePath, level)
            % Read a whole level of a store as [y x z] (single channel).
            image = testCase.openBigData(storePath);
            data = image.getData('image', 3, [], struct('pyramidLevel', level));
            data = reshape(data, size(data, 1), size(data, 2), size(data, 3));
        end
    end

    methods (Static)
        function bandBytes = bandBytesForRows(image, rows)
            % The BandBytes giving bands of about ``rows`` rows (the saver rounds to chunk rows).
            bandBytes = 8 * image.width * image.colors * rows;
        end
    end
end
