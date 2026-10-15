classdef Zarr3SaverBandsTest < matlab.unittest.TestCase
% ZARR3SAVERBANDSTEST - io.savers.Zarr3Saver.saveStreamResumable in bands of rows.
%
% With options.BandHeight the writer reads level 0 in bands of rows
% (ImageDatastoreSliceProvider.getSliceRows on TIFF) and builds every coarser
% level band by band from the level above. Every resize is by exactly 0.5 and a
% band reads enough rows around it, so a banded store must equal one written in
% whole slices, level by level - also for odd sizes, Z-downsampled levels,
% several channels and sharding. Runs without a pool.

    properties (Access = private)
        OrigZarrLib
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

    methods (Static)
        function folder = writeStack(parent, name, volume)
            % one TIF per Z-slice of volume [H W D] or [H W C D]
            folder = fullfile(parent, name);
            mkdir(folder);
            if ndims(volume) == 4
                for z = 1:size(volume, 4)
                    imwrite(volume(:, :, :, z), fullfile(folder, sprintf('s_%03d.tif', z)));
                end
            else
                for z = 1:size(volume, 3)
                    imwrite(volume(:, :, z), fullfile(folder, sprintf('s_%03d.tif', z)));
                end
            end
        end

        function provider = makeProvider(folder)
            provider = io.savers.ImageDatastoreSliceProvider(imageDatastore(folder, 'FileExtensions', '.tif'));
        end
    end

    methods
        function verifyBandsEqualSlices(testCase, folder, metadata, saverOpts, bandHeight)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            slicesPath = io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                Zarr3SaverBandsTest.makeProvider(folder), metadata, fullfile(tmp.Folder, 'slices.zarr3'), saverOpts);
            saverOpts.BandHeight = bandHeight;
            bandsPath = io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                Zarr3SaverBandsTest.makeProvider(folder), metadata, fullfile(tmp.Folder, 'bands.zarr3'), saverOpts);
            attrs = jsondecode(fileread(fullfile(slicesPath, 'zarr.json')));
            numberOfLevels = numel(attrs.attributes.multiscales.datasets);
            testCase.assertGreaterThan(numberOfLevels, 2, 'the fixture must produce a pyramid');
            for L = 1:numberOfLevels
                name = num2str(L - 1);
                testCase.verifyEqual(io.zarr.Group(bandsPath).openArray(name).read(), ...
                    io.zarr.Group(slicesPath).openArray(name).read(), ...
                    sprintf('level %s written in bands must equal the one written in whole slices', name));
            end
        end
    end

    methods (Test, TestTags = {'Unit'})

        function oddSizes_xyOnly_bilinear_bandsEqualSlices(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint16(randi(4000, 301, 275, 9));
            folder = Zarr3SaverBandsTest.writeStack(tmp.Folder, 'slices', volume);
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 4], 'MinLevelSize', 32, ...
                'DownsampleStrategy', 'XY only', 'DownsampleMethod', 'bilinear');
            testCase.verifyBandsEqualSlices(folder, struct('pixSize', struct('x', 1, 'y', 1, 'z', 1)), saverOpts, 64);
        end

        function anisotropic_zDownsampled_bicubic_bandsEqualSlices(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint8(randi(255, 257, 250, 21));
            folder = Zarr3SaverBandsTest.writeStack(tmp.Folder, 'slices', volume);
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 4], 'MinLevelSize', 16, ...
                'DownsampleStrategy', 'Anisotropy-preserving', 'DownsampleMethod', 'bicubic');
            metadata = struct('pixSize', struct('x', 0.013, 'y', 0.013, 'z', 0.03));
            plan = io.savers.Zarr3Saver.computeLevelPlan(257, 250, 21, metadata.pixSize, saverOpts);
            testCase.assertTrue(any([plan.cumZFactor] > 1), 'the fixture must have a Z-downsampled level');
            testCase.verifyBandsEqualSlices(folder, metadata, saverOpts, 40);   % rounds down to 32 rows
        end

        function rgb_sharded_labelsNearest_bandsEqualSlices(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            rgb = uint8(randi(255, 190, 170, 3, 6));
            folder = Zarr3SaverBandsTest.writeStack(tmp.Folder, 'rgb', rgb);
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [16 16 2], 'ShardSize', [2 2 1], ...
                'MinLevelSize', 16);
            testCase.verifyBandsEqualSlices(folder, struct('pixSize', struct('x', 1, 'y', 1, 'z', 1)), saverOpts, 50);   % -> 32 rows (shard)

            labels = uint8(randi([0 6], 180, 160, 7));
            folder = Zarr3SaverBandsTest.writeStack(tmp.Folder, 'labels', labels);
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 4], 'MinLevelSize', 16, ...
                'layerType', 'labels', 'DownsampleMethod', 'nearest', 'MaterialNamesFromData', true);
            testCase.verifyBandsEqualSlices(folder, struct('pixSize', struct('x', 1, 'y', 1, 'z', 1)), saverOpts, 32);
        end

        function interruptedBands_resumeKeepsRecordedBandHeight(testCase)
            % a resume takes the band height from the record, not from the call -
            % the plugin sizes bands from the free memory, which changes
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint8(randi(255, 200, 120, 16));
            folder = Zarr3SaverBandsTest.writeStack(tmp.Folder, 'slices', volume);
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 4], 'MinLevelSize', 16, ...
                'BandHeight', 64, 'SourceFingerprint', 'bands', 'Resume', false);
            metadata = struct('pixSize', struct('x', 1, 'y', 1, 'z', 1));
            freshPath = io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                Zarr3SaverBandsTest.makeProvider(folder), metadata, fullfile(tmp.Folder, 'fresh.zarr3'), saverOpts);

            storePath = fullfile(tmp.Folder, 'resumed.zarr3');
            provider = Zarr3SaverBandsTest.makeProvider(folder);
            delete(fullfile(folder, 's_010.tif'));
            testCase.verifyError(@() io.savers.Zarr3Saver(struct()).saveStreamResumable(provider, metadata, storePath, saverOpts), ...
                'io:Zarr3Saver:taskFailed');
            record = jsondecode(fileread(fullfile(storePath, '.mib_resume.json')));
            testCase.verifyEqual(record.bandHeight, 64);
            Zarr3SaverBandsTest.writeStack(tmp.Folder, 'restore', volume(:, :, 10));
            movefile(fullfile(tmp.Folder, 'restore', 's_001.tif'), fullfile(folder, 's_010.tif'));

            saverOpts.Resume = true;
            saverOpts.BandHeight = 96;   % ignored: the record says 64
            io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                Zarr3SaverBandsTest.makeProvider(folder), metadata, storePath, saverOpts);
            for L = 1:3
                name = num2str(L - 1);
                testCase.verifyEqual(io.zarr.Group(storePath).openArray(name).read(), ...
                    io.zarr.Group(freshPath).openArray(name).read(), sprintf('level %s after resume', name));
            end
        end

        function provider_rowReads_tiffOnly_andRefusedCombinations(testCase)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint16(randi(4000, 70, 60, 3));
            folder = Zarr3SaverBandsTest.writeStack(tmp.Folder, 'tif', volume);
            provider = Zarr3SaverBandsTest.makeProvider(folder);
            testCase.verifyTrue(provider.SupportsRowReads);
            testCase.verifyEqual(provider.getSliceRows(2, 11, 40), volume(11:40, :, 2));

            pngFolder = fullfile(tmp.Folder, 'png'); mkdir(pngFolder);
            imwrite(volume(:, :, 1), fullfile(pngFolder, 's_001.png'));
            pngProvider = io.savers.ImageDatastoreSliceProvider(imageDatastore(pngFolder, 'FileExtensions', '.png'));
            testCase.verifyFalse(pngProvider.SupportsRowReads);
            testCase.verifyError(@() io.savers.Zarr3Saver(struct()).saveStreamResumable(pngProvider, ...
                struct('pixSize', struct('x', 1, 'y', 1, 'z', 1)), fullfile(tmp.Folder, 'png.zarr3'), ...
                struct('silent', true, 'showWaitbar', false, 'ChunkSize', [16 16 1], 'BandHeight', 16)), ...
                'io:Zarr3Saver:bandsUnsupported');
            testCase.verifyError(@() io.savers.Zarr3Saver(struct()).saveStreamResumable(provider, ...
                struct('pixSize', struct('x', 1, 'y', 1, 'z', 1)), fullfile(tmp.Folder, 'mode.zarr3'), ...
                struct('silent', true, 'showWaitbar', false, 'ChunkSize', [16 16 1], 'BandHeight', 16, ...
                'DownsampleMethod', 'mode', 'layerType', 'labels')), 'io:Zarr3Saver:bandsUnsupported');
        end
    end
end
