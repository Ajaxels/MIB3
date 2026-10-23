classdef EditInstanceObjectsBigDataTest < matlab.unittest.TestCase
% EDITINSTANCEOBJECTSBIGDATATEST - Instance index and instance editing on a BigData 16383 store.
%
% A synthetic 600 x 640 x 3 BigData dataset with a disk-backed uint16 instance
% model. Covers:
%
%   - the strip-by-strip full scan of core.MibDataset.buildInstanceIndex agrees
%     with utils.instances.objectIndex of the whole volume, for objects that
%     cross a strip boundary and span several slices
%   - the side-file: written after a full scan, restored on reopen, deleted by
%     the first labels change, and the dirty box repaired on the next build
%   - a write at a coarser level widens the dirty box to whole tiles
%   - models.MibModel.editInstanceObjects on BigData: per-object actions, undo,
%     Compact, and the refusal of Cleanup - each leaving the index equal to a
%     fresh measure of the store, and the objects next to the edit unchanged at
%     full resolution
%   - models.MibModel.convertModel 63 -> 16383 on BigData: a new store, every
%     level remapped without materializing, the old store left on disk
%
% Writes to disk and drives the zarr saver and loader, so tagged Integration.
%
% See also: core.MibDataset.buildInstanceIndex, models.MibModel.editInstanceObjects,
% core.MibBigDataLabels.syncInstanceIndex

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function fullScanMatchesWholeVolumeIndex(testCase)
            mibModel = testCase.buildBigDataInstanceModel();
            index = mibModel.I{1}.buildInstanceIndex();
            testCase.verifyFalse(index.stale);
            testCase.verifyEqual(index.timePoint, 1);
            EditInstanceObjectsBigDataTest.verifyIndexAgreesWithStore(testCase, mibModel, 'full scan');
            testCase.verifyEqual(double(index.sliceCount(7)), 3, 'object 7 spans the three slices');
            testCase.verifyEqual(double(index.bbox(7, 1:2)), [240 270], 'object 7 crosses the strip boundary at row 256');
        end

        function sideFileRestoresTheIndexOnReopen(testCase)
            [mibModel, storePath] = testCase.buildBigDataInstanceModel();
            index = mibModel.I{1}.buildInstanceIndex();
            sideFile = core.MibBigDataLabels.instanceIndexPathFor(storePath);
            testCase.verifyTrue(isfile(sideFile), 'a full scan is saved at once');

            mibModel.I{1}.labels.closeStore();
            reopened = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            reopened.openStore(storePath);
            testCase.verifyEqual(reopened.syncedInstanceIndex, index, 'the side-file restores the index');
            testCase.verifyEmpty(reopened.indexDirtyBox);

            % the first labels change deletes the side-file and opens a dirty box
            patch = zeros(10, 10, 1, 'uint16') + 4000;
            reopened.setData63(patch, 'labels', 3, [], struct('y', [11 20], 'x', [11 20], 'z', [2 2]));
            testCase.verifyFalse(isfile(sideFile), 'a changed store must not keep a side-file describing the old one');
            testCase.verifyEqual(reopened.indexDirtyBox, [11 20 11 20 2 2]);

            % a selection-only write leaves the labels and the dirty box alone
            reopened.setData63(ones(5, 5, 1, 'uint8'), 'selection', 3, [], struct('y', [301 305], 'x', [301 305], 'z', [1 1]));
            testCase.verifyEqual(reopened.indexDirtyBox, [11 20 11 20 2 2]);

            mibModel.I{1}.labels = reopened;
            mibModel.I{1}.instanceIndex = [];
            mibModel.I{1}.buildInstanceIndex();
            testCase.verifyEmpty(reopened.indexDirtyBox, 'the repair accounts for the dirty box');
            EditInstanceObjectsBigDataTest.verifyIndexAgreesWithStore(testCase, mibModel, 'repair after reopen');
            testCase.verifyTrue(mibModel.I{1}.instanceIndex.exists(4000));

            reopened.saveLevelMap();
            testCase.verifyTrue(isfile(sideFile), 'Save writes the side-file again');
        end

        function coarseWriteWidensTheDirtyBoxToTiles(testCase)
            mibModel = testCase.buildBigDataInstanceModel();
            mibModel.I{1}.buildInstanceIndex();
            labels = mibModel.I{1}.labels;

            % a 4x4 patch at level 2 = an 8x8 region at full resolution
            patch = zeros(4, 4, 1, 'uint16') + 9000;
            labels.setData63(patch, 'labels', 3, [], struct('magFactor', 2, 'y', [201 208], 'x', [201 208], 'z', [1 1]));
            tile = labels.modelScaleFactors(end, 1:2);
            box = labels.indexDirtyBox;
            testCase.verifyEqual(mod(box([1 3]) - 1, tile), [0 0], 'the box starts on a tile edge');
            testCase.verifyTrue(box(2) - box(1) + 1 >= tile(1) && box(4) - box(3) + 1 >= tile(2), ...
                'the box covers whole tiles');

            mibModel.I{1}.buildInstanceIndex();
            EditInstanceObjectsBigDataTest.verifyIndexAgreesWithStore(testCase, mibModel, 'coarse write');
        end

        function coarseSelectionStrokeMarksTheLabelsDirty(testCase)
            % A selection drawn zoomed out leaves the labels bits alone at that
            % level, but makes it authoritative for its tiles, and the next
            % full-resolution read rebuilds their labels from it. The index has
            % to hear about that like any labels write.
            mibModel = testCase.buildBigDataInstanceModel();
            mibModel.I{1}.buildInstanceIndex();
            labels = mibModel.I{1}.labels;
            labels.setData63(ones(8, 8, 1, 'uint8'), 'selection', 3, [], ...
                struct('magFactor', 4, 'y', [233 264], 'x', [17 48], 'z', [1 1]));   % over object 7
            testCase.verifyNotEmpty(labels.indexDirtyBox, 'a coarse selection stroke can change the labels');

            mibModel.I{1}.buildInstanceIndex();
            EditInstanceObjectsBigDataTest.verifyIndexAgreesWithStore(testCase, mibModel, 'coarse selection stroke');

            labels.setData63(ones(8, 8, 1, 'uint8'), 'selection', 3, [], ...
                struct('y', [301 308], 'x', [301 308], 'z', [1 1]));
            testCase.verifyEmpty(labels.indexDirtyBox, 'a full-resolution selection stroke leaves the labels alone');
        end

        function perObjectActionsKeepIndexAndNeighbours(testCase)
            mibModel = testCase.buildBigDataInstanceModel();
            mibModel.I{1}.buildInstanceIndex();
            before = EditInstanceObjectsBigDataTest.readStore(mibModel);

            EditInstanceObjectsBigDataTest.runAction(mibModel, 'Merge', '7, 12');
            after = EditInstanceObjectsBigDataTest.readStore(mibModel);
            testCase.verifyEqual(nnz(after == 12), 0, 'the larger index is gone');
            testCase.verifyEqual(nnz(after == 7), nnz(before == 7) + nnz(before == 12));
            testCase.verifyEqual(after == 5, before == 5, 'the neighbour of object 7 is untouched at full resolution');
            EditInstanceObjectsBigDataTest.verifyIndexAgreesWithStore(testCase, mibModel, 'merge');

            EditInstanceObjectsBigDataTest.runAction(mibModel, 'SplitComponents', '300');
            after = EditInstanceObjectsBigDataTest.readStore(mibModel);
            testCase.verifyEqual(nnz(after == 300), 21 * 21 * 2, 'the larger blob keeps the index');
            EditInstanceObjectsBigDataTest.verifyIndexAgreesWithStore(testCase, mibModel, 'split');

            EditInstanceObjectsBigDataTest.runAction(mibModel, 'Delete', '16383');
            after = EditInstanceObjectsBigDataTest.readStore(mibModel);
            testCase.verifyEqual(nnz(after == 16383), 0);
            EditInstanceObjectsBigDataTest.verifyIndexAgreesWithStore(testCase, mibModel, 'delete');
            testCase.verifyEmpty(mibModel.I{1}.labels.indexDirtyBox, 'each refresh accounts for its own writes');
        end

        function drawingBecomesAnObjectAndIsCleared(testCase)
            mibModel = testCase.buildBigDataInstanceModel();
            mibModel.I{1}.buildInstanceIndex();
            selection = zeros(20, 30, 1, 'uint8') + 1;
            mibModel.setData3D(selection, 'selection', 1, 3, [], ...
                struct('id', 1, 'blockModeSwitch', 0, 'y', [31 50], 'x', [501 530], 'z', [2 2]));

            EditInstanceObjectsBigDataTest.runAction(mibModel, 'Merge', '');
            after = EditInstanceObjectsBigDataTest.readStore(mibModel);
            newId = double(after(40, 515, 2));
            testCase.verifyGreaterThan(newId, 0, 'a drawing over background becomes an object');
            testCase.verifyEqual(nnz(after == newId), 20 * 30);
            EditInstanceObjectsBigDataTest.verifyIndexAgreesWithStore(testCase, mibModel, 'add object');

            leftOver = mibModel.I{1}.labels.getData63('selection', 3, [], ...
                struct('pyramidLevel', 1, 'y', [31 50], 'x', [501 530], 'z', [2 2]));
            testCase.verifyEqual(nnz(leftOver), 0, 'the drawing is used up');
        end

        function undoRestoresFullResolution(testCase)
            mibModel = testCase.buildBigDataInstanceModel();
            mibModel.I{1}.buildInstanceIndex();
            before = EditInstanceObjectsBigDataTest.readStore(mibModel);

            EditInstanceObjectsBigDataTest.runAction(mibModel, 'Delete', '7');
            testCase.assertEqual(nnz(EditInstanceObjectsBigDataTest.readStore(mibModel) == 7), 0);
            mibModel.undo();
            testCase.verifyEqual(EditInstanceObjectsBigDataTest.readStore(mibModel), before, ...
                'undo brings back the exact full-resolution voxels');

            backup = mibModel.Backup;
            options = backup.undoList(backup.undoIndex).options;
            testCase.verifyEqual(options.magFactor, 1, 'BigData backups are taken at full resolution');

            % the repair the editor window does on the Undo event
            mibModel.I{1}.buildInstanceIndex(options.instanceIndexRepair);
            EditInstanceObjectsBigDataTest.verifyIndexAgreesWithStore(testCase, mibModel, 'undo repair');
        end

        function compactRenumbersThroughTheIndex(testCase)
            mibModel = testCase.buildBigDataInstanceModel();
            mibModel.I{1}.buildInstanceIndex();
            before = EditInstanceObjectsBigDataTest.readStore(mibModel);
            oldIds = unique(before(before > 0))';

            EditInstanceObjectsBigDataTest.runAction(mibModel, 'Compact', '');
            after = EditInstanceObjectsBigDataTest.readStore(mibModel);
            testCase.verifyEqual(unique(after(after > 0))', uint16(1:numel(oldIds)));
            for k = 1:numel(oldIds)
                testCase.verifyEqual(after == k, before == oldIds(k), ...
                    sprintf('object %d keeps its voxels as %d', oldIds(k), k));
            end
            index = mibModel.I{1}.instanceIndex;
            testCase.verifyEqual(double(index.maxIndex), numel(oldIds), 'Compact brings the highest index down');
            testCase.verifyEqual(mibModel.I{1}.labels.maxIndexUsed, numel(oldIds));
            EditInstanceObjectsBigDataTest.verifyIndexAgreesWithStore(testCase, mibModel, 'compact');
        end

        function cleanupIsRefused(testCase)
            mibModel = testCase.buildBigDataInstanceModel();
            mibModel.I{1}.buildInstanceIndex();
            before = EditInstanceObjectsBigDataTest.readStore(mibModel);
            BatchOpt = struct('Action', {{'Cleanup'}}, 'showWaitbar', false);
            BatchOpt.cleanupMinObjectVoxels = {1e6, [0, 1e9], 'on'};
            applied = testCase.verifyWarningFree(@() mibModel.editInstanceObjects(BatchOpt));
            testCase.verifyFalse(applied);
            testCase.verifyEqual(EditInstanceObjectsBigDataTest.readStore(mibModel), before);
        end
    end

    methods (Test, TestTags = {'Integration'})
        function convert63To16383CopiesEveryLevel(testCase)
            % BigData 63 -> 16383 (models.MibModel.convertModel): a new store,
            % every level remapped voxel for voxel without materializing, the
            % level map carried over, the old store left as it was
            [mibModel, scratch] = testCase.buildBigDataDataset();
            sourcePath = fullfile(scratch, 'Labels_63.zarr3');
            source = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            source.createStore([600 640 3], sourcePath, mibModel.I{1}.image.pyramid);
            packed = zeros(600, 640, 3, 'uint8');
            packed(240:270, 20:60, :) = 7;
            packed(100:130, 300:340, 2) = 63;
            packed(400:420, 100:120, 1) = 2 + 64;          % material 2 under the mask
            packed(500:520, 500:520, 3) = 128;             % selection over background
            source.setData63(packed, 'everything', 3, [], struct('pyramidLevel', 1));
            % a stroke drawn zoomed out: level 2 holds it, level 1 is still deferred
            source.setData63(zeros(10, 10, 1, 'uint8') + 5, 'labels', 3, [], ...
                struct('magFactor', 2, 'y', [21 40], 'x', [21 40], 'z', [1 1]));
            source.materialNames = {'a'; 'b'; 'c'};
            source.materialColors = lines(63);
            source.materialsCount = 3;
            mibModel.I{1}.labels = source;
            mibModel.I{1}.modelExist = true;
            testCase.addTeardown(@() EditInstanceObjectsBigDataTest.closeQuietly(mibModel));

            levelCount = size(source.modelLevelSizes, 1);
            before = cell(1, levelCount);
            for level = 1:levelCount
                levelSize = source.modelLevelSizes(level, :);
                before{level} = source.readPackedLevel(level, [1 levelSize(1)], [1 levelSize(2)], [1 levelSize(3)]);
            end
            matLevelBefore = source.matLevel;
            testCase.assertTrue(any(matLevelBefore(:) > 1), 'the fixture needs a deferred tile');

            targetPath = fullfile(scratch, 'Labels_16383.zarr3');
            BatchOpt = struct('ModelType', {{'16383'}}, 'ModelStorePath', targetPath, ...
                'showWaitbar', false, 'mibBatchTooltip', struct());
            mibModel.convertModel([], BatchOpt);

            target = mibModel.I{1}.labels;
            testCase.assertEqual(target.maxMaterials, 16383, 'the dataset uses the new store');
            testCase.verifyEqual(char(target.modelStorePath), targetPath);
            testCase.verifyEqual(target.matLevel, matLevelBefore, 'deferred levels stay deferred');
            for level = 1:levelCount
                levelSize = target.modelLevelSizes(level, :);
                after = target.readPackedLevel(level, [1 levelSize(1)], [1 levelSize(2)], [1 levelSize(3)]);
                expected = uint16(bitand(before{level}, 63)) + uint16(bitget(before{level}, 7)) * 16384 + ...
                    uint16(bitget(before{level}, 8)) * 32768;
                testCase.verifyEqual(after, expected, sprintf('level %d is the bit remap of the 63 level', level));
            end
            testCase.verifyEqual(target.maxIndexUsed, 63);
            testCase.verifyEqual(target.materialColors(1:63, :), lines(63), 'material k keeps its colour as object k');
            testCase.verifyTrue(target.objects3D);

            reopened = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            reopened.openStore(sourcePath);
            testCase.verifyEqual(reopened.containerClass, 'uint8', 'the 63 store is left on disk');
            testCase.verifyEqual(reopened.readPackedLevel(1, [1 600], [1 640], [1 3]), before{1});
            reopened.closeStore();

            % and the result is an editable instance model
            mibModel.I{1}.buildInstanceIndex();
            EditInstanceObjectsBigDataTest.verifyIndexAgreesWithStore(testCase, mibModel, 'after conversion');
            EditInstanceObjectsBigDataTest.runAction(mibModel, 'Merge', '5, 7');
            labels = EditInstanceObjectsBigDataTest.readStore(mibModel);
            testCase.verifyEqual(nnz(labels == 7), 0);
            mask = mibModel.I{1}.labels.getData63('mask', 3, [], struct('pyramidLevel', 1));
            testCase.verifyEqual(nnz(mask), 21 * 21, 'the mask survives the conversion');
        end
    end

    methods (Test, TestTags = {'Integration'})
        function convert63To16383MirrorsAShorterStore(testCase)
            % A model store may have fewer levels than its image (seen in use: 3
            % against 4). The new store must copy the old store's geometry, not
            % the image pyramid, or the level-for-level copy cannot line up.
            [mibModel, scratch] = testCase.buildBigDataDataset();
            imagePyramid = mibModel.I{1}.image.pyramid;
            shorter = imagePyramid;
            shorter.levelImageSizes = imagePyramid.levelImageSizes(1:2, :);
            shorter.levelScaleFactors = imagePyramid.levelScaleFactors(1:2, :);
            shorter.chunkSizes = imagePyramid.chunkSizes(1:2);
            testCase.assertGreaterThan(size(imagePyramid.levelImageSizes, 1), 2, 'the image needs more levels');

            sourcePath = fullfile(scratch, 'Labels_63.zarr3');
            source = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            source.createStore([600 640 3], sourcePath, shorter);
            packed = zeros(600, 640, 3, 'uint8');
            packed(240:270, 20:60, :) = 7;
            source.setData63(packed, 'everything', 3, [], struct('pyramidLevel', 1));
            source.materialColors = lines(63);
            mibModel.I{1}.labels = source;
            mibModel.I{1}.modelExist = true;
            testCase.addTeardown(@() EditInstanceObjectsBigDataTest.closeQuietly(mibModel));

            BatchOpt = struct('ModelType', {{'16383'}}, 'ModelStorePath', fullfile(scratch, 'Labels_16383.zarr3'), ...
                'showWaitbar', false, 'mibBatchTooltip', struct());
            mibModel.convertModel([], BatchOpt);

            target = mibModel.I{1}.labels;
            testCase.assertEqual(target.maxMaterials, 16383, 'the conversion went through');
            testCase.verifyEqual(target.modelLevelSizes, source.modelLevelSizes, 'the levels of the old store');
            testCase.verifyEqual(target.modelScaleFactors, source.modelScaleFactors);
            labels = EditInstanceObjectsBigDataTest.readStore(mibModel);
            testCase.verifyEqual(labels, uint16(packed), 'the labels arrive intact');
        end
    end

    methods (Access = private)
        function [mibModel, scratch] = buildBigDataDataset(testCase)
            % 600 x 640 x 3 BigData dataset, 3 levels, no model yet
            folderFixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            scratch = folderFixture.Folder;
            sourceImage = fullfile(scratch, 'src.zarr3');
            rng(4);
            io.savers.Zarr3Saver(struct()).save(uint8(randi(255, 600, 640, 3)), ...
                struct('pixSize', struct('x', 0.01, 'y', 0.01, 'z', 0.03, 'units', 'um')), sourceImage, ...
                struct('silent', true, 'showWaitbar', false, 'ChunkSize', [64 64 1], ...
                'Levels', 3, 'DownsampleStrategy', 'XY only'));

            mibFolder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'mib');
            mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            loaderOptions = struct('datasetMode', 'BigData');
            loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
            [imageInfo, files] = loader.loadMetadata({sourceImage}, loaderOptions);
            [image, imageInfo] = loader.loadImages(files, imageInfo, loaderOptions);
            mibModel.I{1}.initialize(image, imageInfo, 'BigData');
            mibModel.I{1}.enableSelection = true;
        end

        function [mibModel, storePath] = buildBigDataInstanceModel(testCase)
            % buildBigDataDataset with a 16383 store holding
            %   7     - rows 240:270 (across the 256-row strip edge), all slices
            %   5     - its close neighbour, rows 240:270 cols 70:90, all slices
            %   12    - one slice, rows 100:130
            %   300   - two disconnected blobs on slices 1:2 (21x21 and 21x15)
            %   16383 - the highest index, slice 3
            [mibModel, scratch] = testCase.buildBigDataDataset();
            storePath = fullfile(scratch, 'Labels_src.zarr3');
            height = 600; width = 640; depth = 3;

            labels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            labels.setLayout('uint16');
            labels.createStore([height width depth], storePath, mibModel.I{1}.image.pyramid);
            volume = zeros(height, width, depth, 'uint16');
            volume(240:270, 20:60, :) = 7;
            volume(240:270, 70:90, :) = 5;
            volume(100:130, 300:340, 2) = 12;
            volume(400:420, 100:120, 1:2) = 300;
            volume(400:420, 150:164, 1:2) = 300;
            volume(500:590, 560:630, 3) = 16383;
            labels.setData63(volume, 'everything', 3, [], struct('pyramidLevel', 1));
            labels.materializeAll();
            labels.objects3D = true;
            labels.materialNames = {'1'; '2'};
            labels.materialColors = rand(65535, 3);
            labels.materialsCount = labels.maxIndexUsed;
            mibModel.I{1}.labels = labels;
            mibModel.I{1}.modelExist = true;
            testCase.addTeardown(@() EditInstanceObjectsBigDataTest.closeQuietly(mibModel));
        end
    end

    methods (Static, Access = private)
        function volume = readStore(mibModel)
            % the whole model at full resolution, straight from the store
            volume = mibModel.I{1}.labels.getData63('labels', 3, [], struct('pyramidLevel', 1));
        end

        function runAction(mibModel, action, indices)
            BatchOpt = struct();
            BatchOpt.Action = {action};
            BatchOpt.ObjectIndices = indices;
            BatchOpt.showWaitbar = false;
            mibModel.editInstanceObjects(BatchOpt);
        end

        function verifyIndexAgreesWithStore(testCase, mibModel, message)
            % the index kept by the BigData path must equal a fresh measure of
            % the whole store; centroids are merged from strips in single
            % precision, so they are compared with a tolerance
            actual = mibModel.I{1}.instanceIndex;
            expected = utils.instances.objectIndex(EditInstanceObjectsBigDataTest.readStore(mibModel));
            shared = expected.maxIndex;
            testCase.verifyGreaterThanOrEqual(actual.maxIndex, shared, message);
            for field = {'exists', 'voxels', 'bbox', 'sliceCount'}
                testCase.verifyEqual(actual.(field{1})(1:shared, :), expected.(field{1})(1:shared, :), ...
                    sprintf('%s: index field %s disagrees with the store', message, field{1}));
            end
            testCase.verifyEqual(actual.centroid(1:shared, :), expected.centroid(1:shared, :), ...
                'AbsTol', single(1e-2), sprintf('%s: centroids disagree with the store', message));
            testCase.verifyFalse(any(actual.exists(shared+1:end)), ...
                sprintf('%s: index claims objects the store does not have', message));
            testCase.verifyEqual(actual.numObjects, expected.numObjects, message);
        end

        function closeQuietly(mibModel)
            % release the store handles before the temporary folder is removed
            if isvalid(mibModel) && isa(mibModel.I{1}.labels, 'core.MibBigDataLabels') && ...
                    mibModel.I{1}.labels.exists
                try mibModel.I{1}.labels.closeStore(); catch; end %#ok<CTCH>
            end
        end
    end
end
