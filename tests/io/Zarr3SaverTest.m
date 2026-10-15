classdef Zarr3SaverTest < matlab.unittest.TestCase
% ZARR3SAVERTEST - Unit tests for io.savers.Zarr3Saver: computeLevelPlan,
% saveStream batching and the bounding box round trip.
%
% saveStream buffers cumZFactor source slices per output slice at each
% Z-downsampled pyramid level and always flushes a trailing partial group
% (see Zarr3Saver.saveStream, "flush any remaining partial Z group"). So a
% level's planned Zl must equal ceil(Z / cumZFactor), matching how many
% slices the flush actually writes - not floor(Z / cumZFactor), which
% under-allocates by one whenever Z is not a multiple of cumZFactor and
% causes an out-of-bounds zarrMex write.

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

    methods (Test, TestTags = {'Unit'})

        function oddZ_anisotropicLevels_matchCeilDivision(testCase)
            % 171 Z-slices (odd), voxel z >> voxel xy -> triggers Z-halving
            % (Anisotropy-preserving) at the level where nextVxXY first exceeds vxZ.
            Z = 171;
            pixSize = struct('x', 0.013, 'y', 0.013, 'z', 0.030);
            options = struct('DownsampleStrategy', 'Anisotropy-preserving', ...
                'MinLevelSize', 64, 'MaxLevels', 8);

            plan = io.savers.Zarr3Saver.computeLevelPlan(888, 816, Z, pixSize, options);

            testCase.verifyGreaterThan(numel(plan), 2, 'plan must include a Z-downsampled level for this fixture');
            for L = 1:numel(plan)
                expectedZl = ceil(Z / plan(L).cumZFactor);
                testCase.verifyEqual(plan(L).Zl, expectedZl, ...
                    sprintf('level %d: Zl must equal ceil(Z/cumZFactor)=%d, matching the streamed flush', L, expectedZl));
            end
        end

        function evenZ_anisotropicLevels_unaffected(testCase)
            % regression guard: even Z (exact division) must still behave as before.
            Z = 160;
            pixSize = struct('x', 0.013, 'y', 0.013, 'z', 0.030);
            options = struct('DownsampleStrategy', 'Anisotropy-preserving', ...
                'MinLevelSize', 64, 'MaxLevels', 8);

            plan = io.savers.Zarr3Saver.computeLevelPlan(888, 816, Z, pixSize, options);
            for L = 1:numel(plan)
                testCase.verifyEqual(plan(L).Zl, Z / plan(L).cumZFactor);
            end
        end

        function saveStream_chunkAlignedBatching_multiLevel_roundTrips(testCase)
            % Regression: saveStream buffers output slices per level up to that
            % level's chunk Z-thickness before issuing one region write (instead of
            % one write per Z-slice, which forces a decompress/recompress of the
            % whole chunk per slice - a severe performance bug). This must not
            % scramble data across batch or Z-downsampling-group boundaries: chunkZ
            % (16) does not evenly divide Z (40), and Anisotropy-preserving forces a
            % Z-downsampled level whose cumZFactor (2) does not evenly divide Z
            % either, so both the write-batch flush and the Z-group flush hit their
            % trailing-partial-group edge case here.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            zarrPath = fullfile(tmp.Folder, 'out.zarr3');

            Z = 40;
            vol = zeros(200, 180, Z, 'uint8');
            for z = 1:Z
                vol(:, :, z) = uint8(mod(z - 1, 7));   % distinct, recoverable value per slice
            end
            provider = io.savers.InMemorySliceProvider(reshape(vol, 200, 180, Z, 1, 1));
            meta = struct('pixSize', struct('x', 0.013, 'y', 0.013, 'z', 0.030));

            io.savers.Zarr3Saver(struct()).saveStream(provider, meta, zarrPath, ...
                struct('showWaitbar', false, 'ChunkSize', [64 64 16], 'MinLevelSize', 32, ...
                       'DownsampleStrategy', 'Anisotropy-preserving', 'DownsampleMethod', 'nearest'));

            grp = io.zarr.Group(zarrPath);

            % level 0 (full res, cumZFactor=1): chunkZ=16 does not divide Z=40
            % (write batches of 16,16,8) - every slice must still land at its own
            % Z-index, unscrambled by the write-batch boundaries.
            vol0 = grp.openArray('0').read();
            testCase.verifyEqual(size(vol0, 1:3), [200 180 Z]);
            for z = 1:Z
                expected = uint8(mod(z - 1, 7));
                testCase.verifyEqual(unique(vol0(:, :, z)), expected, ...
                    sprintf('level0 z=%d must equal the source slice value, unscrambled by chunk batching', z));
            end

            % level 2 is the first Z-downsampled level here (cumZFactor=2): 40
            % source slices -> ceil(40/2)=20 output slices, batched into a
            % chunkZ=16 write + a 4-slice trailing flush. Each output slice is the
            % rounded mean of its 2 source slices (Zarr3Saver.reduceZBuffer).
            arr2 = grp.openArray('2');
            testCase.verifyEqual(arr2.shape(), [50 45 20]);
            vol2 = arr2.read();
            for z = 1:20
                v1 = double(mod(2*z - 2, 7));
                v2 = double(mod(2*z - 1, 7));
                expected = uint8(round((v1 + v2) / 2));
                testCase.verifyEqual(unique(vol2(:, :, z)), expected, ...
                    sprintf('level2 z=%d must equal round(mean(source z=%d,%d)), unscrambled by batching', z, 2*z-1, 2*z));
            end
        end

        function boundingBox_roundTrips_saveAndStream_v2AndV3(testCase)
            % Regression: save and saveStream ignored metadata.boundingBox, so every
            % conversion to BigData reopened with its origin at 0 and a model saved
            % against the original dataset landed offset. Both writers must store
            % it for both zarr formats, and the loaders must return it unchanged.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint8(randi(255, 90, 80, 5));
            pixSize = struct('x', 0.014, 'y', 0.014, 'z', 0.03, 'units', 'um');
            boundingBox = [4.61235, 4.61235 + 79*0.014, 6.95358, 6.95358 + 89*0.014, 4.47, 4.47 + 4*0.03];
            meta = struct('pixSize', pixSize, 'boundingBox', boundingBox);
            saverOpts = struct('silent', true, 'showWaitbar', false, 'MinLevelSize', 32);
            loaderOpts = struct('waitbar', 0, 'silentMode', true);

            for extension = {'zarr3', 'zarr2'}
                savePath = io.savers.Zarr3Saver().save(volume, meta, ...
                    fullfile(tmp.Folder, ['save.' extension{1}]), saverOpts);
                streamPath = io.savers.Zarr3Saver().saveStream(io.savers.InMemorySliceProvider(volume), meta, ...
                    fullfile(tmp.Folder, ['stream.' extension{1}]), saverOpts);
                for storePath = {savePath, streamPath}
                    if strcmp(extension{1}, 'zarr2')
                        loader = io.loaders.Zarr2VirtualSetupLoader(loaderOpts);
                    else
                        loader = io.loaders.Zarr3VirtualSetupLoader(loaderOpts);
                    end
                    imgInfo = loader.loadMetadata(storePath, loaderOpts);
                    testCase.verifyEqual(imgInfo{"BoundingBox"}, boundingBox, 'AbsTol', 1e-9, ...
                        sprintf('%s must reopen with the bounding box it was saved with', storePath{1}));
                end
            end
        end

        function patchMetadata_updatesV2Store(testCase)
            % Regression: patchMetadata read zarr.json directly and returned silently
            % on a v2 store, so editing the bounding box of an open zarr2 BigData
            % dataset was lost on reopen.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            pixSize = struct('x', 0.014, 'y', 0.014, 'z', 0.03, 'units', 'um');
            storePath = io.savers.Zarr3Saver().save(uint8(randi(255, 90, 80, 5)), struct('pixSize', pixSize), ...
                fullfile(tmp.Folder, 'patch.zarr2'), struct('silent', true, 'MinLevelSize', 32));
            boundingBox = [1, 1 + 79*0.014, 2, 2 + 89*0.014, 3, 3 + 4*0.03];

            io.savers.Zarr3Saver.patchMetadata(storePath, pixSize, boundingBox);

            loaderOpts = struct('waitbar', 0, 'silentMode', true);
            imgInfo = io.loaders.Zarr2VirtualSetupLoader(loaderOpts).loadMetadata({storePath}, loaderOpts);
            testCase.verifyEqual(imgInfo{"BoundingBox"}, boundingBox, 'AbsTol', 1e-9);
        end

        function saveAndStream_cOrderChunks_noTransposeCodec_roundTrip(testCase)
            % Arrays are written in C byte order without the transpose codec (2.5x
            % faster zarrMex writes); the logical [y x z] array must be unchanged.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            volume = uint16(randi(4000, 70, 90, 9));
            meta = struct('pixSize', struct('x', 1, 'y', 1, 'z', 1));
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 4], 'MinLevelSize', 32);

            savePath = io.savers.Zarr3Saver().save(volume, meta, fullfile(tmp.Folder, 'save.zarr3'), saverOpts);
            streamPath = io.savers.Zarr3Saver().saveStream(io.savers.InMemorySliceProvider(volume), meta, ...
                fullfile(tmp.Folder, 'stream.zarr3'), saverOpts);
            for storePath = {savePath, streamPath}
                arrayMetadata = jsondecode(fileread(fullfile(storePath{1}, '0', 'zarr.json')));
                codecs = arrayMetadata.codecs;
                if iscell(codecs); codecNames = cellfun(@(codec) codec.name, codecs, 'UniformOutput', false);
                else; codecNames = {codecs.name}; end
                testCase.verifyFalse(ismember('transpose', codecNames), ...
                    sprintf('%s: level 0 must not carry the transpose codec', storePath{1}));
                testCase.verifyEqual(io.zarr.Group(storePath{1}).openArray('0').read(), volume, ...
                    sprintf('%s: level 0 must read back unchanged', storePath{1}));
            end
        end

        function allWriters_samePyramid(testCase)
            % save (in memory), saveStream and saveStreamResumable all build each
            % level from the level above - XY by exactly 0.5, Z by the mean of
            % slice pairs; the same data must give the same store from each. Odd
            % sizes (where resizing to [Yl Xl] would stretch), Z halved once and
            % twice (cumulative Z factor 4) with odd Z, several channels.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            cases = struct( ...
                'volume', {uint16(randi(4000, 301, 275, 9)), uint8(randi(255, 257, 250, 21)), ...
                    uint8(randi(255, 190, 170, 7, 3)), uint16(randi(4000, 520, 300, 23))}, ...
                'pixSize', {struct('x', 1, 'y', 1, 'z', 1), struct('x', 0.013, 'y', 0.013, 'z', 0.03), ...
                    struct('x', 1, 'y', 1, 'z', 1), struct('x', 0.013, 'y', 0.013, 'z', 0.1)}, ...
                'strategy', {'XY only', 'Anisotropy-preserving', 'XY only', 'Anisotropy-preserving'}, ...
                'method', {'bilinear', 'bicubic', 'bilinear', 'bilinear'});
            for caseIndex = 1:numel(cases)
                volume = cases(caseIndex).volume;   % [y x z] or [y x z c]
                saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 4], 'MinLevelSize', 16, ...
                    'DownsampleStrategy', cases(caseIndex).strategy, 'DownsampleMethod', cases(caseIndex).method);
                metadata = struct('pixSize', cases(caseIndex).pixSize);
                plan = io.savers.Zarr3Saver.computeLevelPlan(size(volume, 1), size(volume, 2), size(volume, 3), ...
                    metadata.pixSize, saverOpts);
                testCase.assertGreaterThan(numel(plan), 2);
                if caseIndex == 2; testCase.assertTrue(any([plan.cumZFactor] > 1), 'case 2 must halve Z'); end
                if caseIndex == 4; testCase.assertTrue(any([plan.cumZFactor] >= 4), 'case 4 must halve Z twice'); end

                savePath = io.savers.Zarr3Saver().save(volume, metadata, ...
                    fullfile(tmp.Folder, sprintf('save%d.zarr3', caseIndex)), saverOpts);
                streamPath = io.savers.Zarr3Saver().saveStream(io.savers.InMemorySliceProvider(volume), ...
                    metadata, fullfile(tmp.Folder, sprintf('stream%d.zarr3', caseIndex)), saverOpts);
                resumablePath = io.savers.Zarr3Saver().saveStreamResumable(io.savers.InMemorySliceProvider(volume), ...
                    metadata, fullfile(tmp.Folder, sprintf('resumable%d.zarr3', caseIndex)), saverOpts);
                for L = 1:numel(plan)
                    name = num2str(L - 1);
                    resumableLevel = io.zarr.Group(resumablePath).openArray(name).read();
                    testCase.verifyEqual(io.zarr.Group(savePath).openArray(name).read(), resumableLevel, ...
                        sprintf('case %d, level %s: save must equal saveStreamResumable', caseIndex, name));
                    testCase.verifyEqual(io.zarr.Group(streamPath).openArray(name).read(), resumableLevel, ...
                        sprintf('case %d, level %s: saveStream must equal saveStreamResumable', caseIndex, name));
                end
            end
        end

        function saveStream_modeLabels_samePyramidAsResumable(testCase)
            % 'mode' reduces blocks of the full slice while a level keeps the full
            % Z and of the level above after - in both streaming writers (save
            % reduces blocks of the full-resolution volume and is not compared)
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            labels = uint8(randi([0 5], 256, 200, 19));
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 4], 'MinLevelSize', 16, ...
                'DownsampleStrategy', 'Anisotropy-preserving', 'DownsampleMethod', 'mode', 'layerType', 'labels');
            metadata = struct('pixSize', struct('x', 0.013, 'y', 0.013, 'z', 0.03));
            streamPath = io.savers.Zarr3Saver().saveStream(io.savers.InMemorySliceProvider(labels), ...
                metadata, fullfile(tmp.Folder, 'stream.zarr3'), saverOpts);
            resumablePath = io.savers.Zarr3Saver().saveStreamResumable(io.savers.InMemorySliceProvider(labels), ...
                metadata, fullfile(tmp.Folder, 'resumable.zarr3'), saverOpts);
            plan = io.savers.Zarr3Saver.computeLevelPlan(256, 200, 19, metadata.pixSize, saverOpts);
            testCase.assertTrue(any([plan.cumZFactor] > 1));
            for L = 1:numel(plan)
                name = num2str(L - 1);
                testCase.verifyEqual(io.zarr.Group(streamPath).openArray(name).read(), ...
                    io.zarr.Group(resumablePath).openArray(name).read(), sprintf('level %s', name));
            end
        end

        function saveStream_sharded_writesWholeShards_roundTrips(testCase)
            % With sharding the write depth is the shard Z (a partial-shard write
            % re-reads and rewrites the shard); shard Z 12 does not divide Z 30, so
            % the trailing partial shard is flushed too.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            Z = 30;
            volume = zeros(64, 64, Z, 'uint8');
            for z = 1:Z; volume(:, :, z) = uint8(z); end
            storePath = io.savers.Zarr3Saver().saveStream(io.savers.InMemorySliceProvider(volume), ...
                struct('pixSize', struct('x', 1, 'y', 1, 'z', 1)), fullfile(tmp.Folder, 'shard.zarr3'), ...
                struct('silent', true, 'showWaitbar', false, 'ChunkSize', [16 16 4], 'ShardSize', [2 2 3], ...
                'MinLevelSize', 16, 'DownsampleMethod', 'nearest'));

            level0 = io.zarr.Group(storePath).openArray('0').read();
            testCase.verifyEqual(level0, volume, 'sharded level 0 must read back unchanged');
        end

        function saveStream_interrupted_leavesIncompleteFlag_loaderWarns(testCase)
            % The attributes are declared before the first slice with mibIncomplete
            % = true and rewritten without it after the last one. A stream that
            % fails part way (here: a source file vanishes) leaves the flag, and the
            % loader warns; a finished stream has no flag.
            tmp = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            sourceFolder = fullfile(tmp.Folder, 'slices');
            mkdir(sourceFolder);
            for z = 1:6
                imwrite(uint8(randi(255, 40, 50)), fullfile(sourceFolder, sprintf('s_%02d.tif', z)));
            end
            saverOpts = struct('silent', true, 'showWaitbar', false, 'ChunkSize', [32 32 2], 'MinLevelSize', 16);
            meta = struct('pixSize', struct('x', 1, 'y', 1, 'z', 1));
            loaderOpts = struct('waitbar', 0, 'silentMode', true);

            finishedPath = io.savers.Zarr3Saver().saveStream(io.savers.ImageDatastoreSliceProvider( ...
                imageDatastore(sourceFolder, 'FileExtensions', '.tif')), meta, fullfile(tmp.Folder, 'done.zarr3'), saverOpts);
            finishedMetadata = jsondecode(fileread(fullfile(finishedPath, 'zarr.json')));
            finishedAttrs = finishedMetadata.attributes;
            testCase.verifyFalse(isfield(finishedAttrs, 'mibIncomplete'), 'a finished store must not be flagged');
            testCase.verifyWarningFree(@() io.loaders.Zarr3VirtualSetupLoader(loaderOpts).loadMetadata({finishedPath}, loaderOpts));

            provider = io.savers.ImageDatastoreSliceProvider(imageDatastore(sourceFolder, 'FileExtensions', '.tif'));
            delete(fullfile(sourceFolder, 's_05.tif'));   % slice 5 fails to read
            brokenPath = fullfile(tmp.Folder, 'broken.zarr3');
            testCase.verifyError(@() io.savers.Zarr3Saver().saveStream(provider, meta, brokenPath, saverOpts), ?MException);
            brokenMetadata = jsondecode(fileread(fullfile(brokenPath, 'zarr.json')));
            brokenAttrs = brokenMetadata.attributes;
            testCase.verifyTrue(isfield(brokenAttrs, 'mibIncomplete') && brokenAttrs.mibIncomplete, ...
                'an interrupted store must keep the mibIncomplete flag');
            testCase.verifyTrue(isfield(brokenAttrs, 'multiscales'), ...
                'an interrupted store must still declare its pyramid, so it can be opened');
            testCase.verifyWarning(@() io.loaders.Zarr3VirtualSetupLoader(loaderOpts).loadMetadata({brokenPath}, loaderOpts), ...
                'io:Zarr3VirtualSetupLoader:incompleteStore');
        end

    end
end
