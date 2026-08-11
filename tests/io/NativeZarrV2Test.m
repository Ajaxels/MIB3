classdef NativeZarrV2Test < matlab.unittest.TestCase
% NATIVEZARRV2TEST - Zarr v2 through the native (zarrMex) engine, end to end.
%
% Zarr v2 used to be python-only in MIB: every v2 read went through
% ``io.zarr.PyBackend``, and a v2 BigData model store could not be created at
% all. The bundled ``zarrMex`` now reads and writes v2, so v2 and v3 differ
% only in on-disk metadata layout.
%
% These tests pin that equivalence at the three seams where it could regress:
%
%   1. the ``io.zarr`` facade - a v2 group is created, its arrays inherit the
%      format, and attributes land in ``.zattrs`` rather than ``zarr.json``
%   2. ``core.MibBigDataLabels`` - a v2 model store is editable and reopens,
%      and carries the ``mibModelStore`` marker that separates it from a
%      foreign store (which stays read-only via ``core.MibBigDataLabelsZarr2``)
%   3. ``io.savers.Zarr3Saver`` + ``io.loaders.Zarr2VirtualSetupLoader`` - a v2
%      export is read back with identical pixels
%
% Every test asserts **values**, not just shapes and formats: an axis-order or
% chunk-order mistake between the two formats would preserve every dimension
% while silently transposing the data, which a shape-only check cannot see.
%
% All tests run offline and force the native backend, so they also serve as the
% regression guard that python is genuinely not required for zarr v2.

    properties (Access = private)
        TempDir
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

            testCase.TempDir = fullfile(tempdir, 'mib_native_zarr_v2_test');
            if isfolder(testCase.TempDir); rmdir(testCase.TempDir, 's'); end
            mkdir(testCase.TempDir);
        end
    end

    methods (TestMethodTeardown)
        function restoreBackend(testCase)
            io.zarr.Config.setLibrary(testCase.OrigZarrLib);
            if isfolder(testCase.TempDir); rmdir(testCase.TempDir, 's'); end
        end
    end

    methods (Test, TestTags = {'Unit'})

        % ---- 1. the io.zarr facade -------------------------------------

        function groupCreatesV2AndArraysInheritIt(testCase)
            storePath = fullfile(testCase.TempDir, 'group.zarr2');

            group = io.zarr.Group.create(storePath, 'zarrFormat', 2);
            array = group.createArray('0', [64, 48, 20], 'uint8', ...
                'chunkShape', [32, 32, 8], 'fillValue', 0);

            testCase.verifyEqual(group.zarrFormat(), 2);
            testCase.verifyEqual(array.zarrFormat(), 2, ...
                'an array added to a v2 group must inherit v2 without being told');

            % v2 metadata sidecars, and no v3 zarr.json anywhere
            testCase.verifyTrue(isfile(fullfile(storePath, '.zgroup')));
            testCase.verifyTrue(isfile(fullfile(storePath, '0', '.zarray')));
            testCase.verifyFalse(isfile(fullfile(storePath, 'zarr.json')));
            testCase.verifyFalse(isfile(fullfile(storePath, '0', 'zarr.json')));
        end

        function groupDefaultsToV3(testCase)
            % the format is opt-in; every existing caller must keep getting v3
            storePath = fullfile(testCase.TempDir, 'default.zarr3');
            group = io.zarr.Group.create(storePath);

            testCase.verifyEqual(group.zarrFormat(), 3);
            testCase.verifyTrue(isfile(fullfile(storePath, 'zarr.json')));
        end

        function v2AndV3RoundTripIdenticalPixels(testCase)
            % The two formats express MATLAB's column-major layout differently -
            % v3 with a transpose codec, v2 with order 'F'. Writing the same
            % array through both and comparing the READ BACK values is what
            % catches a mix-up: the shapes would agree either way.
            data = uint16(reshape(1:(40 * 30 * 12), [40, 30, 12]));

            v2Path = fullfile(testCase.TempDir, 'equiv.zarr2');
            v3Path = fullfile(testCase.TempDir, 'equiv.zarr3');

            v2Array = io.zarr.Array.createFromData(v2Path, data, ...
                'chunkShape', [16, 16, 8], 'zarrFormat', 2);
            v3Array = io.zarr.Array.createFromData(v3Path, data, ...
                'chunkShape', [16, 16, 8], 'zarrFormat', 3);

            testCase.verifyEqual(v2Array.read(), data);
            testCase.verifyEqual(v2Array.read(), v3Array.read());

            % and a sub-region, where a chunk-order mistake shows up soonest
            bbox = [11, 26; 7, 22; 3, 9];
            testCase.verifyEqual(v2Array.read(bbox), data(11:25, 7:21, 3:8));
            testCase.verifyEqual(v2Array.read(bbox), v3Array.read(bbox));
        end

        function groupAttributesRoundTripThroughZattrs(testCase)
            storePath = fullfile(testCase.TempDir, 'attrs.zarr2');
            group = io.zarr.Group.create(storePath, 'zarrFormat', 2);

            group.setAttributes(struct('multiscales', {{struct('version', '0.5')}}));

            testCase.verifyTrue(isfile(fullfile(storePath, '.zattrs')), ...
                'v2 attributes belong in .zattrs, not in the node metadata file');
            reopened = io.zarr.Group(storePath);
            testCase.verifyTrue(isfield(reopened.getAttributes(), 'multiscales'));
        end

        % ---- 2. the BigData model store --------------------------------

        function zarrFormatFromPathFollowsTheExtension(testCase)
            testCase.verifyEqual(core.MibBigDataLabels.zarrFormatFromPath('C:\d\m.zarr2'), 2);
            testCase.verifyEqual(core.MibBigDataLabels.zarrFormatFromPath('C:\d\m.zarr3'), 3);
            % anything unrecognised stays v3, so no existing caller changes
            testCase.verifyEqual(core.MibBigDataLabels.zarrFormatFromPath('C:\d\m.zarr'), 3);
            testCase.verifyEqual(core.MibBigDataLabels.zarrFormatFromPath('C:\d\model'), 3);
        end

        function v2ModelStoreIsEditableAndReopens(testCase)
            storePath = fullfile(testCase.TempDir, 'Labels.zarr2');
            block = uint8(randi([0, 63], 40, 30, 10));

            labels = testCase.createModelStore(storePath);
            labels.writePackedLevel(1, block, [11, 50], [21, 50], [5, 14]);
            testCase.verifyEqual(labels.readPackedLevel(1, [11, 50], [21, 50], [5, 14]), block);
            labels.closeStore();

            testCase.verifyEqual(io.zarr.Group(storePath).zarrFormat(), 2);

            % a reopened store must serve the same voxels, through the same
            % editable class - this is the whole point of a v2 model store
            reopened = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            reopened.openStore(storePath);
            testCase.verifyEqual([reopened.height, reopened.width, reopened.depth], [128, 96, 40]);
            testCase.verifyEqual(reopened.readPackedLevel(1, [11, 50], [21, 50], [5, 14]), block);
        end

        function mibWrittenStoresCarryTheMarker(testCase)
            % The marker is what lets loadModel send a MIB-written v2 store to
            % the editable class; both formats must carry it.
            v2Path = fullfile(testCase.TempDir, 'Marked.zarr2');
            v3Path = fullfile(testCase.TempDir, 'Marked.zarr3');

            testCase.createModelStore(v2Path).closeStore();
            testCase.createModelStore(v3Path).closeStore();

            testCase.verifyTrue(core.MibBigDataLabels.isMibModelStore(v2Path));
            testCase.verifyTrue(core.MibBigDataLabels.isMibModelStore(v3Path));
        end

        function foreignV2StoreIsNotMarked(testCase)
            % A plain multiscales group of uint8 arrays is exactly what another
            % tool writes, and is indistinguishable from a MIB store by its
            % pixels alone. Without the marker it must answer false, which is
            % what routes it to the read-only overlay.
            storePath = fullfile(testCase.TempDir, 'foreign.zarr2');
            group = io.zarr.Group.create(storePath, 'zarrFormat', 2);
            group.createArray('0', [32, 32, 4], 'uint8', 'chunkShape', [16, 16, 4]);
            group.setAttributes(struct('multiscales', {{struct( ...
                'version', '0.4', 'datasets', {{struct('path', '0')}})}}));

            testCase.verifyFalse(core.MibBigDataLabels.isMibModelStore(storePath));
        end

        function isMibModelStoreNeverThrows(testCase)
            % It gates a dispatch decision, so an unreadable path has to answer
            % rather than raise.
            testCase.verifyFalse(core.MibBigDataLabels.isMibModelStore( ...
                fullfile(testCase.TempDir, 'does_not_exist.zarr2')));
            testCase.verifyFalse(core.MibBigDataLabels.isMibModelStore(''));
        end

        % ---- 3. saver and loader ---------------------------------------

        function savedV2PyramidReadsBackIdentically(testCase)
            storePath = fullfile(testCase.TempDir, 'export.zarr2');
            data = uint16(reshape(mod(1:(120 * 100 * 6), 65535), [120, 100, 6]));
            metadata = struct('pixSize', struct('x', 0.02, 'y', 0.02, 'z', 0.1));

            io.savers.Zarr3Saver(struct()).save(data, metadata, storePath, ...
                struct('showWaitbar', false, 'Levels', 2));

            testCase.verifyEqual(io.zarr.Group(storePath).zarrFormat(), 2, ...
                'the .zarr2 extension must select the v2 format');

            options = struct('datasetMode', 'Virtual', 'ParentFigure', []);
            loader = io.loaders.Zarr2VirtualSetupLoader(options);
            [imginfo, files] = loader.loadMetadata({storePath}, options);

            testCase.verifyEqual(files.nLevels, 2);
            testCase.verifyEqual(imginfo{"Height"}, 120);
            testCase.verifyEqual(imginfo{"Width"}, 100);
            testCase.verifyEqual(imginfo{"Depth"}, 6);
            testCase.verifyEqual(imginfo{"imgClass"}, 'uint16');
            testCase.verifyEqual(files.pixSize.x, 0.02);

            level0 = io.zarr.Group(storePath).openArray(files.levelNames{1});
            testCase.verifyEqual(level0.read(), data);
        end

        function virtualLoaderReadsV2RegionInMibOrder(testCase)
            % Zarr2VirtualLoader is the per-slice reader; assert it returns the
            % requested region in MIB's [y,x,z,c,t] order with the right values,
            % which is the composition of the bbox build and the permutation.
            storePath = fullfile(testCase.TempDir, 'virtual.zarr2');
            data = uint8(reshape(mod(1:(64 * 48 * 10), 255), [64, 48, 10]));
            metadata = struct('pixSize', struct('x', 1, 'y', 1, 'z', 1));

            io.savers.Zarr3Saver(struct()).save(data, metadata, storePath, ...
                struct('showWaitbar', false, 'Levels', 1));

            options = struct('datasetMode', 'Virtual', 'ParentFigure', []);
            loader = io.loaders.Zarr2VirtualSetupLoader(options);
            [~, files] = loader.loadMetadata({storePath}, options);

            regionReader = io.loaders.Zarr2VirtualLoader(storePath, files.axisOrder);
            block = regionReader.readRegion(files.levelNames{1}, ...
                [5, 20], [9, 24], [3, 4], [1, 1], [1, 1], 'uint8');

            testCase.verifyEqual(size(block, 1:3), [16, 16, 2]);
            testCase.verifyEqual(block, data(5:20, 9:24, 3:4));
        end

        function shardingIsRefusedForV2(testCase)
            % Zarr v2 has no sharding codec. Dropping the setting silently would
            % write a store whose chunk layout differs from what was asked for,
            % so this has to fail loudly and name the format.
            metadata = struct('pixSize', struct('x', 1, 'y', 1, 'z', 1));
            testCase.verifyError(@() io.savers.Zarr3Saver(struct()).save( ...
                uint8(zeros(32, 32, 4)), metadata, fullfile(testCase.TempDir, 'shard.zarr2'), ...
                struct('showWaitbar', false, 'ShardSize', [2, 2, 1])), ...
                'io:Zarr3Saver:shardingUnsupportedV2');
        end
    end

    methods (Access = private)
        function labels = createModelStore(testCase, storePath) %#ok<INUSD>
            % CREATEMODELSTORE - a two-level packed model store at storePath.
            % The format follows the extension, which is the behaviour under test.
            labels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            pyramid = struct( ...
                'levelImageSizes',   [128, 96, 40; 64, 48, 20], ...
                'levelScaleFactors', [1, 1, 1; 2, 2, 2], ...
                'chunkSizes',        {{[32, 32, 8], [32, 32, 8]}}, ...
                'axisOrder',         'yxz');
            labels.createStore([128, 96, 40], storePath, pyramid);
        end
    end
end
