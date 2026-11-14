classdef Zarr3SaverIsotropicSaveTest < matlab.unittest.TestCase
% ZARR3SAVERISOTROPICSAVETEST - the writers build the isotropic level of 'Anisotropy-preserving + isotropic level'.
%
% Step 3 of development/bigdata/isotropic_hr_level.md. ``save``, ``saveStream`` and
% ``saveStreamResumable`` (whole slices and bands) must write the same pyramid; the isotropic
% level must be built from the level ``computeLevelPlan`` names as its source (the 10 nm level
% for 5x5x30 nm, a 3x step), not from the level above it; the levels after it halve XY and Z.
% Voxel 1 x 1 x 6 gives the XY factors 1, 2, 4, 6, 12: level index 3 (0-based) is isotropic.

    properties (Access = private)
        OrigZarrLib
    end

    properties (Constant, Access = private)
        IsoStrategy = 'Anisotropy-preserving + isotropic level'
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (TestMethodSetup)
        function forceNativeBackend(testCase)
            testCase.OrigZarrLib = io.zarr.Config.library();
            io.zarr.Config.setLibrary('native');
        end
    end

    methods (TestMethodTeardown)
        function restoreBackend(testCase)
            io.zarr.Config.setLibrary(testCase.OrigZarrLib);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function allWritersProduceTheSamePyramid(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint16(randi(4000, 300, 289, 9));   % odd sizes
            metadata = struct('pixSize', struct('x', 1, 'y', 1, 'z', 6));
            for method = {'bilinear', 'bicubic', 'nearest', 'mode'}
                saverOpts = testCase.saverOptions(method{1});
                savePath = io.savers.Zarr3Saver().save(volume, metadata, ...
                    fullfile(tmp.Folder, ['save_' method{1} '.zarr3']), saverOpts);
                streamPath = io.savers.Zarr3Saver().saveStream(io.savers.InMemorySliceProvider(volume), metadata, ...
                    fullfile(tmp.Folder, ['stream_' method{1} '.zarr3']), saverOpts);
                resumablePath = io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                    io.savers.InMemorySliceProvider(volume), metadata, ...
                    fullfile(tmp.Folder, ['resumable_' method{1} '.zarr3']), saverOpts);
                numberOfLevels = testCase.levelCount(resumablePath);
                testCase.assertEqual(numberOfLevels, 5, 'the fixture must give factors 1 2 4 6 12');
                levelsToCompare = numberOfLevels;
                if strcmp(method{1}, 'mode')
                    % mode is not associative: where Z is halved (level 5) save reduces 3-D blocks of
                    % level 0, the streaming writers the level above. The class documents identical
                    % pyramids for the interpolating methods only; the levels that keep Z must match.
                    levelsToCompare = 4;
                end
                for L = 1:levelsToCompare
                    name = num2str(L - 1);
                    expected = io.zarr.Group(resumablePath).openArray(name).read();
                    testCase.verifyEqual(io.zarr.Group(savePath).openArray(name).read(), expected, ...
                        sprintf('%s: save level %s', method{1}, name));
                    testCase.verifyEqual(io.zarr.Group(streamPath).openArray(name).read(), expected, ...
                        sprintf('%s: saveStream level %s', method{1}, name));
                end
            end
        end

        function bandsEqualSlices(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint8(randi(255, 301, 275, 7));
            folder = fullfile(tmp.Folder, 'slices');
            mkdir(folder);
            for z = 1:size(volume, 3)
                imwrite(volume(:, :, z), fullfile(folder, sprintf('s_%03d.tif', z)));
            end
            metadata = struct('pixSize', struct('x', 1, 'y', 1, 'z', 6));
            for method = {'bilinear', 'bicubic', 'nearest'}
                saverOpts = testCase.saverOptions(method{1});
                makeProvider = @() io.savers.ImageDatastoreSliceProvider(imageDatastore(folder, 'FileExtensions', '.tif'));
                slicesPath = io.savers.Zarr3Saver(struct()).saveStreamResumable(makeProvider(), metadata, ...
                    fullfile(tmp.Folder, ['slices_' method{1} '.zarr3']), saverOpts);
                saverOpts.BandHeight = 64;
                bandsPath = io.savers.Zarr3Saver(struct()).saveStreamResumable(makeProvider(), metadata, ...
                    fullfile(tmp.Folder, ['bands_' method{1} '.zarr3']), saverOpts);
                numberOfLevels = testCase.levelCount(slicesPath);
                testCase.assertEqual(numberOfLevels, 5);
                for L = 1:numberOfLevels
                    name = num2str(L - 1);
                    testCase.verifyEqual(io.zarr.Group(bandsPath).openArray(name).read(), ...
                        io.zarr.Group(slicesPath).openArray(name).read(), ...
                        sprintf('%s: level %s in bands must equal the one in whole slices', method{1}, name));
                end
            end
        end

        function isotropicLevelComesFromTheTenNanometreLevel(testCase)
            % 5x5x30 nm: the 30 nm level is the 10 nm level resized by 1/3, not level 0 by 1/6
            % and not the 20 nm level by 2/3
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint16(randi(4000, 300, 289, 9));
            metadata = struct('pixSize', struct('x', 5, 'y', 5, 'z', 30));
            path = io.savers.Zarr3Saver().save(volume, metadata, fullfile(tmp.Folder, 'iso.zarr3'), ...
                testCase.saverOptions('bilinear'));
            group = io.zarr.Group(path);
            tenNanometre = group.openArray('1').read();
            isotropic = group.openArray('3').read();
            testCase.verifyEqual(size(isotropic, 1:2), [50 49]);   % ceil(300 / 6), ceil(289 / 6)
            testCase.verifyEqual(size(isotropic, 3), 9);           % Z unchanged
            expected = zeros(size(isotropic), 'uint16');
            for z = 1:size(expected, 3)
                expected(:, :, z) = imresize(tenNanometre(:, :, z), 1 / 3, 'bilinear');
            end
            testCase.verifyEqual(isotropic, expected);
            fromLevelZero = zeros(size(isotropic), 'uint16');
            for z = 1:size(fromLevelZero, 3)
                fromLevelZero(:, :, z) = imresize(volume(:, :, z), [50 49], 'bilinear');
            end
            testCase.verifyNotEqual(isotropic, fromLevelZero, 'it must not be built from level 0');
        end

        function nonIntegerIsotropicLevelIsWrittenByAllWriters(testCase)
            % 5x5x13 nm: F = 2.6, XY factors 1, 2, 2.6, 5.2, 10.4; the 13 nm level is built from level 0
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint16(randi(4000, 300, 289, 9));
            metadata = struct('pixSize', struct('x', 5, 'y', 5, 'z', 13));
            for method = {'bilinear', 'nearest'}
                saverOpts = testCase.saverOptions(method{1});
                savePath = io.savers.Zarr3Saver().save(volume, metadata, ...
                    fullfile(tmp.Folder, ['save_' method{1} '.zarr3']), saverOpts);
                streamPath = io.savers.Zarr3Saver().saveStream(io.savers.InMemorySliceProvider(volume), metadata, ...
                    fullfile(tmp.Folder, ['stream_' method{1} '.zarr3']), saverOpts);
                resumablePath = io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                    io.savers.InMemorySliceProvider(volume), metadata, ...
                    fullfile(tmp.Folder, ['resumable_' method{1} '.zarr3']), saverOpts);
                testCase.assertEqual(testCase.levelCount(resumablePath), 5);
                sizes = zeros(5, 3);
                for L = 1:5
                    name = num2str(L - 1);
                    expected = io.zarr.Group(resumablePath).openArray(name).read();
                    sizes(L, :) = size(expected, 1:3);
                    testCase.verifyEqual(io.zarr.Group(savePath).openArray(name).read(), expected, ...
                        sprintf('%s: save level %s', method{1}, name));
                    testCase.verifyEqual(io.zarr.Group(streamPath).openArray(name).read(), expected, ...
                        sprintf('%s: saveStream level %s', method{1}, name));
                end
                testCase.verifyEqual(sizes, [300 289 9; 150 145 9; 116 112 9; 58 56 5; 29 28 3]);
            end
            % the 13 nm level is level 0 reduced by 2.6, not the 10 nm level by 1.3
            group = io.zarr.Group(savePath);
            level0 = group.openArray('0').read();
            isotropic = group.openArray('2').read();
            expected = zeros(size(isotropic), 'uint16');
            for z = 1:size(expected, 3)
                expected(:, :, z) = io.savers.Zarr3Saver.resizeXY(level0(:, :, z), 2.6, [116 112], 'nearest');
            end
            testCase.verifyEqual(isotropic, expected);
            attrs = jsondecode(fileread(fullfile(savePath, 'zarr.json')));
            scales = attrs.attributes.multiscales.datasets;
            testCase.verifyEqual(unique(scales(3).coordinateTransformations.scale(:))', 13, 'AbsTol', 1e-9);
        end

        function maxPoolingEqualsTheBlockMaximumInEveryWriter(testCase)
            % 'max' (DeepMIB scores): each level is the maximum of the blocks of level 0, in XY
            % (the isotropic 6x step of 1x1x6 voxels included, odd sizes) and in Z; the writers
            % agree, also in bands of rows
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint8(randi(255, 301, 275, 9));
            folder = fullfile(tmp.Folder, 'slices');
            mkdir(folder);
            for z = 1:size(volume, 3)
                imwrite(volume(:, :, z), fullfile(folder, sprintf('s_%03d.tif', z)));
            end
            metadata = struct('pixSize', struct('x', 1, 'y', 1, 'z', 6));
            saverOpts = testCase.saverOptions('max');
            makeProvider = @() io.savers.ImageDatastoreSliceProvider(imageDatastore(folder, 'FileExtensions', '.tif'));
            paths = {io.savers.Zarr3Saver().save(volume, metadata, fullfile(tmp.Folder, 'save.zarr3'), saverOpts), ...
                io.savers.Zarr3Saver().saveStream(io.savers.InMemorySliceProvider(volume), metadata, fullfile(tmp.Folder, 'stream.zarr3'), saverOpts), ...
                io.savers.Zarr3Saver(struct()).saveStreamResumable(makeProvider(), metadata, fullfile(tmp.Folder, 'slices.zarr3'), saverOpts)};
            bandOpts = saverOpts;
            bandOpts.BandHeight = 64;
            paths{end+1} = io.savers.Zarr3Saver(struct()).saveStreamResumable(makeProvider(), metadata, fullfile(tmp.Folder, 'bands.zarr3'), bandOpts);
            names = {'save', 'saveStream', 'slices', 'bands'};
            xyFactors = [1 2 4 6 12];
            zFactors = [1 1 1 1 2];
            for pathIndex = 1:numel(paths)
                testCase.assertEqual(testCase.levelCount(paths{pathIndex}), 5, names{pathIndex});
                for levelIndex = 1:5
                    expected = testCase.blockMaximum(volume, xyFactors(levelIndex), zFactors(levelIndex));
                    actual = io.zarr.Group(paths{pathIndex}).openArray(num2str(levelIndex - 1)).read();
                    testCase.verifyEqual(actual, expected, sprintf('%s: level %d', names{pathIndex}, levelIndex - 1));
                end
            end
        end

        function givenLevelFactorsAreWrittenAsTheyAreByAllWriters(testCase)
            % the levels of a pyramid cut at its 20 nm level (5x5x30 nm image): XY factors 1, 1.5, 3,
            % Z 1, 1, 2. The strategy alone rebuilds 1, 2, 4 for Z / XY = 1.5
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint16(randi(4000, 300, 289, 9));
            metadata = struct('pixSize', struct('x', 20, 'y', 20, 'z', 30));
            saverOpts = testCase.saverOptions('bilinear');
            saverOpts.DownsampleStrategy = 'Anisotropy-preserving';
            saverOpts.LevelFactors = [1 1 1; 1.5 1.5 1; 3 3 2];
            savePath = io.savers.Zarr3Saver().save(volume, metadata, fullfile(tmp.Folder, 'save.zarr3'), saverOpts);
            streamPath = io.savers.Zarr3Saver().saveStream(io.savers.InMemorySliceProvider(volume), metadata, ...
                fullfile(tmp.Folder, 'stream.zarr3'), saverOpts);
            resumablePath = io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                io.savers.InMemorySliceProvider(volume), metadata, fullfile(tmp.Folder, 'resumable.zarr3'), saverOpts);
            testCase.assertEqual(testCase.levelCount(resumablePath), 3);
            sizes = zeros(3, 3);
            for L = 1:3
                name = num2str(L - 1);
                expected = io.zarr.Group(resumablePath).openArray(name).read();
                sizes(L, :) = size(expected, 1:3);
                testCase.verifyEqual(io.zarr.Group(savePath).openArray(name).read(), expected, ['save level ' name]);
                testCase.verifyEqual(io.zarr.Group(streamPath).openArray(name).read(), expected, ['saveStream level ' name]);
            end
            testCase.verifyEqual(sizes, [300 289 9; 200 193 9; 100 97 5]);
            attrs = jsondecode(fileread(fullfile(savePath, 'zarr.json')));
            scales = attrs.attributes.multiscales.datasets;
            testCase.verifyEqual(unique(scales(2).coordinateTransformations.scale(:))', [30], 'AbsTol', 1e-9);
            testCase.verifyEqual(scales(3).coordinateTransformations.scale(:)', [60 60 60], 'AbsTol', 1e-9);
        end

        function optionsFromPyramidKeepsTheLevelsOfACutPyramidAndLevelsCutsThem(testCase)
            % a 5x5x30 nm pyramid cut at its 20 nm level: factors 1, 1.5, 3 relative to it
            cutPyramid = struct('axisOrder', 'yxz', 'levelImageSizes', [200 193 9; 100 97 9; 50 49 5], ...
                'levelScaleFactors', [4 4 1; 6 6 1; 12 12 2], 'chunkSizes', {{[32 32 4], [32 32 4], [32 32 4]}});
            saverOptions = io.savers.Zarr3Saver.optionsFromPyramid(cutPyramid);
            testCase.verifyEqual(saverOptions.LevelFactors, [1 1 1; 1.5 1.5 1; 3 3 2], 'AbsTol', 1e-9);
            planOptions = struct('DownsampleStrategy', saverOptions.DownsampleStrategy, ...
                'Levels', 2, 'LevelFactors', saverOptions.LevelFactors);
            plan = io.savers.Zarr3Saver.computeLevelPlan(300, 289, 9, struct('x', 20, 'y', 20, 'z', 30), planOptions);
            testCase.verifyEqual([plan.cumXYFactor], [1 1.5], 'AbsTol', 1e-9);
        end

        function optionsFromPyramidFromACoarserLevelStartsThere(testCase)
            % 5x5x30 nm pyramid, XY factors 1 2 4 6 12 and Z 1 1 1 1 2, described from its 20 nm level
            fullPyramid = struct('axisOrder', 'yxz', ...
                'levelImageSizes', [300 289 9; 150 145 9; 75 73 9; 50 49 9; 25 25 5], ...
                'levelScaleFactors', [1 1 1; 2 2 1; 4 4 1; 6 6 1; 12 12 2], ...
                'chunkSizes', {{[32 32 4], [32 32 4], [16 16 4], [16 16 4], [8 8 4]}});
            saverOptions = io.savers.Zarr3Saver.optionsFromPyramid(fullPyramid, 3);
            testCase.verifyEqual(saverOptions.Levels, 3);
            testCase.verifyEqual(saverOptions.ChunkSize, [16 16 4]);
            testCase.verifyEqual(saverOptions.LevelFactors, [1 1 1; 1.5 1.5 1; 3 3 2], 'AbsTol', 1e-9);
            testCase.verifyEqual(io.savers.Zarr3Saver.optionsFromPyramid(fullPyramid).Levels, 5, 'default = from level 1');
        end

        function levelFactorsOfAnotherShapeAreRefused(testCase)
            testCase.verifyError(@() io.savers.Zarr3Saver.computeLevelPlan(100, 100, 10, ...
                struct('x', 1, 'y', 1, 'z', 1), struct('LevelFactors', [2 2 1; 4 4 1])), 'Zarr3Saver:levelFactors');
            testCase.verifyError(@() io.savers.Zarr3Saver.computeLevelPlan(100, 100, 10, ...
                struct('x', 1, 'y', 1, 'z', 1), struct('LevelFactors', [1 1 1; 2 3 1])), 'Zarr3Saver:levelFactors');
        end

        function levelsAfterTheIsotropicOneHalveXYAndZ(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint16(randi(4000, 300, 289, 9));
            metadata = struct('pixSize', struct('x', 5, 'y', 5, 'z', 30));
            path = io.savers.Zarr3Saver().saveStream(io.savers.InMemorySliceProvider(volume), metadata, ...
                fullfile(tmp.Folder, 'iso.zarr3'), testCase.saverOptions('bilinear'));
            sizes = zeros(5, 3);
            for L = 1:5
                sizes(L, :) = size(io.zarr.Group(path).openArray(num2str(L - 1)).read(), 1:3);
            end
            testCase.verifyEqual(sizes, [300 289 9; 150 145 9; 75 73 9; 50 49 9; 25 25 5]);
            % metadata: voxel size of the isotropic level, 30 nm in all three axes
            attrs = jsondecode(fileread(fullfile(path, 'zarr.json')));
            scales = attrs.attributes.multiscales.datasets;
            testCase.verifyEqual(unique(scales(4).coordinateTransformations.scale(:))', 30);
            testCase.verifyEqual(unique(scales(5).coordinateTransformations.scale(:))', 60);
        end
    end

    methods (Access = private)
        function saverOpts = saverOptions(testCase, method)
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 4], 'MinLevelSize', 16, ...
                'DownsampleStrategy', testCase.IsoStrategy, 'DownsampleMethod', method);
        end

        function blocked = blockMaximum(~, volume, xyFactor, zFactor)
            % Maximum of each xyFactor x xyFactor x zFactor block of ``volume``; a partial block at the end takes
            % the maximum of the voxels it has
            [height, width, depth] = size(volume);
            outSize = ceil([height, width, depth] ./ [xyFactor, xyFactor, zFactor]);
            padded = padarray(volume, outSize .* [xyFactor, xyFactor, zFactor] - [height, width, depth], 'replicate', 'post');
            padded = reshape(padded, xyFactor, outSize(1), xyFactor, outSize(2), zFactor, outSize(3));
            blocked = reshape(max(max(max(padded, [], 1), [], 3), [], 5), outSize);
        end

        function count = levelCount(~, storePath)
            attrs = jsondecode(fileread(fullfile(storePath, 'zarr.json')));
            count = numel(attrs.attributes.multiscales.datasets);
        end
    end
end
