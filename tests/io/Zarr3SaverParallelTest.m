classdef Zarr3SaverParallelTest < matlab.unittest.TestCase
% ZARR3SAVERPARALLELTEST - io.savers.Zarr3Saver.saveStreamResumable on a pool, against saveStream.
%
% saveStreamResumable lets the pool workers read their own Z-slabs and write
% level 0 (plus the levels that keep the full Z) directly, then builds the
% Z-downsampled levels from the level above, as saveStream does too: every level
% of both stores must be identical.
%
% Tagged Integration: it starts a process pool (~20 s) unless one is running.

    properties (Access = private)
        Pool
        CreatedPool = false
        OrigZarrLib
    end

    methods (TestClassSetup)
        function addPathsAndPool(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
            testCase.Pool = gcp('nocreate');
            if isempty(testCase.Pool)
                testCase.Pool = parpool('Processes', 2);
                testCase.CreatedPool = true;
            end
        end
    end

    methods (TestClassTeardown)
        function deletePool(testCase)
            if testCase.CreatedPool; delete(testCase.Pool); end
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
        function ds = writeStack(folder, volume)
            % one TIF per Z-slice of volume [H W D] or [H W C D]
            if ndims(volume) == 3
                for z = 1:size(volume, 3)
                    imwrite(volume(:, :, z), fullfile(folder, sprintf('s_%03d.tif', z)));
                end
            else
                for z = 1:size(volume, 4)
                    imwrite(volume(:, :, :, z), fullfile(folder, sprintf('s_%03d.tif', z)));
                end
            end
            ds = imageDatastore(folder, 'FileExtensions', '.tif');
        end
    end

    methods
        function [serialPath, parallelPath] = writeBoth(testCase, ds, saverOpts, metadata)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            serialPath = io.savers.Zarr3Saver(struct()).saveStream( ...
                io.savers.ImageDatastoreSliceProvider(ds), metadata, fullfile(tmp.Folder, 'serial.zarr3'), saverOpts);
            parallelPath = io.savers.Zarr3Saver(struct()).saveStreamResumable( ...
                io.savers.ImageDatastoreSliceProvider(ds), metadata, fullfile(tmp.Folder, 'parallel.zarr3'), ...
                saverOpts, testCase.Pool);
        end

        function verifySameStore(testCase, serialPath, parallelPath)
            serialGroup = io.zarr.Group(serialPath);
            parallelGroup = io.zarr.Group(parallelPath);
            serialAttrs = jsondecode(fileread(fullfile(serialPath, 'zarr.json')));
            parallelAttrs = jsondecode(fileread(fullfile(parallelPath, 'zarr.json')));
            testCase.verifyEqual(parallelAttrs.attributes, serialAttrs.attributes, ...
                'both writers must leave the same group attributes, without mibIncomplete');
            numberOfLevels = numel(serialAttrs.attributes.multiscales.datasets);
            for L = 1:numberOfLevels
                name = num2str(L - 1);
                testCase.verifyEqual(parallelGroup.openArray(name).read(), serialGroup.openArray(name).read(), ...
                    sprintf('level %s must be identical', name));
            end
        end
    end

    methods (Test, TestTags = {'Integration'})

        function xyOnly_shardedAndUneven_identicalToSaveStream(testCase)
            % every level keeps the full Z: all written by the slab tasks. Z = 37
            % leaves a short last slab; shard Z 2 x chunk Z 4 = slab depth 8.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint8(randi(255, 300, 260, 37));
            ds = Zarr3SaverParallelTest.writeStack(tmp.Folder, volume);
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [64 64 4], ...
                'ShardSize', [2 2 2], 'MinLevelSize', 64, 'DownsampleStrategy', 'XY only');
            metadata = struct('pixSize', struct('x', 1, 'y', 1, 'z', 1));
            [serialPath, parallelPath] = testCase.writeBoth(ds, saverOpts, metadata);
            testCase.verifyEqual(io.zarr.Group(parallelPath).openArray('0').read(), volume);
            testCase.verifySameStore(serialPath, parallelPath);
        end

        function anisotropic_zDownsampledLevelsBuiltFromAbove(testCase)
            % voxel z >> xy: the coarser levels halve Z too, so they are built in
            % the second phase from the level above. Z = 45 is odd.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint16(randi(4000, 256, 240, 45));
            ds = Zarr3SaverParallelTest.writeStack(tmp.Folder, volume);
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [64 64 8], ...
                'MinLevelSize', 32, 'DownsampleStrategy', 'Anisotropy-preserving');
            metadata = struct('pixSize', struct('x', 0.013, 'y', 0.013, 'z', 0.03));
            plan = io.savers.Zarr3Saver.computeLevelPlan(256, 240, 45, metadata.pixSize, saverOpts);
            numberOfDirectLevels = find([plan.cumZFactor] > 1, 1) - 1;
            testCase.assertNotEmpty(numberOfDirectLevels, 'the fixture must produce a Z-downsampled level');
            [serialPath, parallelPath] = testCase.writeBoth(ds, saverOpts, metadata);
            testCase.verifySameStore(serialPath, parallelPath);
        end

        function labels_materialNamesFromData_andRgbChannels(testCase)
            % labels: the largest value of all slabs names the materials; RGB:
            % the channel axis is written by the slab tasks.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            labelFolder = fullfile(tmp.Folder, 'labels'); mkdir(labelFolder);
            labels = uint8(randi([0 5], 128, 128, 20));
            labels(:, :, 17) = 7;   % the maximum sits in a late slab
            ds = Zarr3SaverParallelTest.writeStack(labelFolder, labels);
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [64 64 4], ...
                'MinLevelSize', 32, 'layerType', 'labels', 'DownsampleMethod', 'nearest', 'MaterialNamesFromData', true);
            [serialPath, parallelPath] = testCase.writeBoth(ds, saverOpts, struct('pixSize', struct('x', 1, 'y', 1, 'z', 1)));
            attrs = jsondecode(fileread(fullfile(parallelPath, 'zarr.json')));
            testCase.verifyEqual(numel(attrs.attributes.mibMaterials.materialNames), 7);
            testCase.verifySameStore(serialPath, parallelPath);

            rgbFolder = fullfile(tmp.Folder, 'rgb'); mkdir(rgbFolder);
            rgb = uint8(randi(255, 100, 90, 3, 11));
            ds = Zarr3SaverParallelTest.writeStack(rgbFolder, rgb);
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 4], 'MinLevelSize', 32);
            [serialPath, parallelPath] = testCase.writeBoth(ds, saverOpts, struct('pixSize', struct('x', 1, 'y', 1, 'z', 1)));
            testCase.verifyEqual(io.zarr.Group(parallelPath).openArray('0').read(), permute(rgb, [1 2 4 3]));
            testCase.verifySameStore(serialPath, parallelPath);
        end

        function failedSlab_raisesWithZRange_leavesIncompleteFlag(testCase)
            % a slab that cannot be read must fail the whole write, name its Z
            % range and leave the store flagged mibIncomplete - never a success
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            sourceFolder = fullfile(tmp.Folder, 'slices'); mkdir(sourceFolder);
            ds = Zarr3SaverParallelTest.writeStack(sourceFolder, uint8(randi(255, 64, 64, 12)));
            provider = io.savers.ImageDatastoreSliceProvider(ds);
            delete(fullfile(sourceFolder, 's_010.tif'));
            storePath = fullfile(tmp.Folder, 'broken.zarr3');
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 4], 'MinLevelSize', 32);
            try
                io.savers.Zarr3Saver(struct()).saveStreamResumable(provider, ...
                    struct('pixSize', struct('x', 1, 'y', 1, 'z', 1)), storePath, saverOpts, testCase.Pool);
                testCase.verifyFail('a failed slab must raise an error');
            catch err
                testCase.verifyEqual(err.identifier, 'io:Zarr3Saver:taskFailed');
                testCase.verifySubstring(err.message, 'level 0, Z 9-12');
            end
            attrs = jsondecode(fileread(fullfile(storePath, 'zarr.json')));
            testCase.verifyTrue(isfield(attrs.attributes, 'mibIncomplete') && attrs.attributes.mibIncomplete);
        end
    end
end
