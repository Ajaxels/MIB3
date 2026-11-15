classdef MibBigDataStoreSettingsTest < matlab.unittest.TestCase
% MIBBIGDATASTORESETTINGSTEST - chunking, sharding and codec of a BigData model store.
%
% New model asks for these settings in a dialog seeded from the image
% (``io.savers.Zarr3Saver.optionsFromPyramid``) and hands them to
% ``core.MibBigDataLabels.createStore`` through the pyramid ``chunkSizes``,
% ``ShardFactors`` and ``Compressors``. The dialog itself needs a window, so these
% tests cover what it feeds: the seed taken from an image pyramid, and a store
% created with those settings on disk, headless.
%
% Why it matters: a model with one file per chunk is very slow on a network drive
% (a missing chunk costs a round trip), so sharding must reach the store.

    properties (Access = private)
        StorePath    % char path of the temp .zarr3 store
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (TestMethodTeardown)
        function cleanupStore(testCase)
            if ~isempty(testCase.StorePath)
                if isfolder(testCase.StorePath); rmdir(testCase.StorePath, 's'); end
                levelMapPath = core.MibBigDataLabels.levelMapPathFor(testCase.StorePath);
                if isfile(levelMapPath); delete(levelMapPath); end
            end
            testCase.StorePath = '';
        end
    end

    methods (Test, TestTags = {'Unit'})
        function seedTakesChunkAndShardOfTheImage(testCase)
            % image: chunk 128 x 128 x 4 bundled in 1024 x 1024 x 4 shards
            pyramid = struct('axisOrder', 'yxz', ...
                'levelImageSizes', [2048 2048 16; 1024 1024 16], ...
                'levelScaleFactors', [1 1 1; 2 2 1], ...
                'chunkSizes', {{[128 128 4], [128 128 4]}}, ...
                'shardSizes', {{[1024 1024 4], [1024 1024 4]}});
            seed = io.savers.Zarr3Saver.optionsFromPyramid(pyramid);
            testCase.verifyEqual(seed.ChunkSize, [128 128 4]);
            testCase.verifyEqual(seed.ShardSize, [8 8 1], 'shard is given in chunks per shard');
        end

        function seedHasNoShardWhenImageIsNotSharded(testCase)
            pyramid = struct('axisOrder', 'yxz', ...
                'levelImageSizes', [512 512 8], 'levelScaleFactors', [1 1 1], ...
                'chunkSizes', {{[64 64 2]}}, 'shardSizes', {{[64 64 2]}});
            seed = io.savers.Zarr3Saver.optionsFromPyramid(pyramid);
            testCase.verifyEqual(seed.ChunkSize, [64 64 2]);
            testCase.verifyFalse(isfield(seed, 'ShardSize'), 'a shard of one chunk means no sharding');
        end

        function storeIsShardedWithTheRequestedChunks(testCase)
            lb = testCase.createStoreWith({[64 64 2]}, [4 4 1], 'zstd');
            testCase.addTeardown(@() lb.closeStore());
            info = lb.modelArrays{1}.info();
            testCase.verifyEqual(double(info.chunkShape(:))', [64 64 2]);
            testCase.verifyEqual(double(info.shardShape(:))', [256 256 2], ...
                'a shard holds 4 x 4 x 1 chunks');
            arrayJson = fileread(fullfile(testCase.StorePath, '0', 'zarr.json'));
            testCase.verifyTrue(contains(arrayJson, 'sharding_indexed'));
        end

        function storeIsUnshardedByDefault(testCase)
            lb = testCase.createStoreWith({[64 64 2]}, [], 'zstd');
            testCase.addTeardown(@() lb.closeStore());
            arrayJson = fileread(fullfile(testCase.StorePath, '0', 'zarr.json'));
            testCase.verifyFalse(contains(arrayJson, 'sharding_indexed'));
        end

        function compressionLevelReachesTheStore(testCase)
            codec = struct('name', 'zstd', 'configuration', struct('level', 5));
            lb = testCase.createStoreWith({[64 64 2]}, [4 4 1], codec);
            testCase.addTeardown(@() lb.closeStore());
            arrayJson = fileread(fullfile(testCase.StorePath, '0', 'zarr.json'));
            testCase.verifyNotEmpty(regexp(arrayJson, '"level"\s*:\s*5', 'once'));
        end

        function chunkFoldersExistSoMissingFilesAreCheapToLookUp(testCase)
            % shard 256 x 256 x 2 over 512 x 512 x 8: a 2 x 2 grid of shard folders c/<y>/<x>
            lb = testCase.createStoreWith({[64 64 2]}, [4 4 1], 'zstd');
            testCase.addTeardown(@() lb.closeStore());
            for folderY = 0:1
                for folderX = 0:1
                    testCase.verifyTrue(isfolder(fullfile(testCase.StorePath, '0', 'c', ...
                        sprintf('%d', folderY), sprintf('%d', folderX))), ...
                        sprintf('folder c/%d/%d', folderY, folderX));
                end
            end
            testCase.verifyFalse(isfolder(fullfile(testCase.StorePath, '0', 'c', '2')), 'no folder beyond the grid');
            testCase.verifyEqual(lb.readPackedLevel(1, [1 512], [1 512], [1 8]), zeros(512, 512, 8, 'uint8'), ...
                'an empty store reads as zeros');
        end

        function unshardedStoreGetsOneFolderPerChunkColumn(testCase)
            lb = testCase.createStoreWith({[128 128 2]}, [], 'zstd');   % 4 x 4 chunks
            testCase.addTeardown(@() lb.closeStore());
            testCase.verifyTrue(isfolder(fullfile(testCase.StorePath, '0', 'c', '3', '3')));
            testCase.verifyFalse(isfolder(fullfile(testCase.StorePath, '0', 'c', '4')));
        end

        function bigStoreKeepsFoldersLazy(testCase)
            % 64 x 64 chunks of one level = 4096 folders, over the 100 limit
            pyramid = struct('axisOrder', 'yxz', 'levelImageSizes', [4096 4096 2], ...
                'levelScaleFactors', [1 1 1], 'chunkSizes', {{[64 64 2]}});
            imageInfo = core.MibImage.initializeImgInfo('Height', 4096, 'Width', 4096, ...
                'Depth', 2, 'Time', 1, 'Colors', 1);
            testCase.StorePath = [tempname '_settings.zarr3'];
            lb = core.MibBigDataLabels([], imageInfo);
            lb.createStore([4096 4096 2], testCase.StorePath, pyramid);
            testCase.addTeardown(@() lb.closeStore());
            testCase.verifyFalse(isfolder(fullfile(testCase.StorePath, '0', 'c')), ...
                'too many folders to create up front');
        end

        function zarr2StoreNeedsNoChunkFolders(testCase)
            % a v2 chunk file sits in the array folder itself, which exists
            pyramid = struct('axisOrder', 'yxz', 'levelImageSizes', [512 512 8], ...
                'levelScaleFactors', [1 1 1], 'chunkSizes', {{[64 64 2]}});
            imageInfo = core.MibImage.initializeImgInfo('Height', 512, 'Width', 512, ...
                'Depth', 8, 'Time', 1, 'Colors', 1);
            testCase.StorePath = [tempname '_settings.zarr2'];
            lb = core.MibBigDataLabels([], imageInfo);
            lb.createStore([512 512 8], testCase.StorePath, pyramid);
            testCase.addTeardown(@() lb.closeStore());
            testCase.verifyFalse(isfolder(fullfile(testCase.StorePath, '0', 'c')));
        end

        function shardedStoreReadsBackWhatWasWritten(testCase)
            lb = testCase.createStoreWith({[64 64 2]}, [4 4 1], 'zstd');
            testCase.addTeardown(@() lb.closeStore());
            block = uint8(randi([0 63], 100, 120, 3));
            lb.writePackedLevel(1, block, [10 109], [20 139], [2 4]);
            testCase.verifyEqual(lb.readPackedLevel(1, [10 109], [20 139], [2 4]), block);
            testCase.verifyEqual(lb.readPackedLevel(1, [1 9], [1 19], [1 1]), zeros(9, 19, 1, 'uint8'), ...
                'untouched voxels of a partly written shard stay empty');
        end
    end

    methods (Access = private)
        function lb = createStoreWith(testCase, chunkSizes, shardFactors, compressor)
            % one level 512 x 512 x 8 store with the given settings
            pyramid = struct('axisOrder', 'yxz', ...
                'levelImageSizes', [512 512 8], 'levelScaleFactors', [1 1 1], ...
                'chunkSizes', {chunkSizes});
            imageInfo = core.MibImage.initializeImgInfo('Height', 512, 'Width', 512, ...
                'Depth', 8, 'Time', 1, 'Colors', 1);
            testCase.StorePath = [tempname '_settings.zarr3'];
            lb = core.MibBigDataLabels([], imageInfo);
            lb.Compressors = compressor;
            if ~isempty(shardFactors); lb.ShardFactors = shardFactors; end
            lb.createStore([512 512 8], testCase.StorePath, pyramid);
        end
    end
end
