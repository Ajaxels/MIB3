classdef MibBigDataLabelsUint32Test < matlab.unittest.TestCase
% MIBBIGDATALABELSUINT32TEST - The packed uint32 BigData instance model (type 1073741823).
%
% Layout: bits 1-30 = object index, bit 31 = mask, bit 32 = selection
% (core.MibLabels63.setLayout('uint32')). Covers:
%
%   - the layout constants, and the constructor picking the layout from uint32 data
%   - a uint32 store: create, write indices above 65535 with the mask and
%     selection bits, propagate to the coarser levels, reopen as uint32
%   - a labels stroke drawn zoomed out keeps a 30-bit index when the finer level
%     is rebuilt on read; a selection stroke leaves the labels alone
%   - the static smooth resize keeps the class and the flag bits
%   - models.MibModel.createModel: '1073741823' builds a uint32 store on BigData
%     and a 4294967295 model on a Standard dataset
%   - models.MibModel.convertModel on BigData: 63 -> 1073741823 and
%     16383 -> 1073741823 into a new store, and the refusal of 1073741823 -> 16383
%   - crop of a BigData uint32 model to a Standard buffer gives a 4294967295 model
%
% The store tests write to disk and drive the zarr saver and loader, so they are
% tagged Integration; the layout test is Unit.
%
% See also: core.MibLabels63.setLayout, core.MibBigDataLabels, models.MibModel.convertModel

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})
        function layoutConstants(testCase)
            labels = core.MibLabels63();
            labels.setLayout('uint32');
            testCase.verifyEqual(labels.containerClass, 'uint32');
            testCase.verifyEqual(labels.materialMask, 2^30 - 1);
            testCase.verifyEqual(labels.maxMaterials, 1073741823);
            testCase.verifyEqual([labels.maskBit, labels.selectionBit], [31 32]);
            testCase.verifyEqual([labels.maskValue, labels.selectionValue], [2^30, 2^31]);
            testCase.verifyEqual(labels.flagsMask, 2^30 + 2^31);

            fromData = core.MibLabels63(zeros(4, 5, 2, 'uint32'));
            testCase.verifyEqual(fromData.maxMaterials, 1073741823, 'uint32 data selects the uint32 layout');
            testCase.verifyError(@() labels.setLayout('uint64'), 'MibLabels63:setLayout:badClass');
        end

        function smoothResizeKeepsUint32(testCase)
            % an up-sample of a packed uint32 block: class kept, index and flags
            % decoded from bits 1-30, 31 and 32
            block = zeros(8, 8, 1, 'uint32');
            block(3:6, 3:6) = uint32(1000000000) + uint32(2^30);     % object under the mask
            block(1:2, 7:8) = uint32(2^31);                          % selection over background
            upsampled = core.MibBigDataLabels.resizeBlockSmooth(block, [32 32 1]);
            testCase.verifyClass(upsampled, 'uint32');
            testCase.verifyEqual(double(upsampled(18, 18)), 1000000000 + 2^30, 'object and mask inside');
            testCase.verifyEqual(double(upsampled(2, 31)), 2^31, 'selection only');
            testCase.verifyEqual(double(upsampled(30, 2)), 0, 'background');
        end

        function createModelStandardGivesSeparateLayers(testCase)
            % the packed uint32 type is BigData only: Standard gets 4294967295
            mibModel = mibtest.helpers.buildSyntheticModel();
            BatchOpt = struct('ModelType', {{'1073741823'}}, 'showWaitbar', false);
            mibModel.createModel([], [], BatchOpt);
            testCase.verifyEqual(mibModel.I{1}.labels.maxMaterials, 4294967295);
            testCase.verifyClass(mibModel.I{1}.labels, 'core.MibLabels');
        end
    end

    methods (Test, TestTags = {'Integration'})
        function storeRoundTrip(testCase)
            [mibModel, scratch] = testCase.buildBigDataDataset();
            storePath = fullfile(scratch, 'Labels_32.zarr3');
            labels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            labels.setLayout('uint32');
            labels.createStore([600 640 3], storePath, mibModel.I{1}.image.pyramid);
            testCase.addTeardown(@() MibBigDataLabelsUint32Test.closeQuietly(labels));

            packed = zeros(600, 640, 3, 'uint32');
            packed(240:270, 20:60, :) = 70000;                                  % above 65535
            packed(100:131, 300:339, 2) = uint32(1073741823) + uint32(2^30);    % top index, under the mask
            packed(500:520, 500:520, 3) = uint32(2^31) + uint32(12);            % selected object 12
            labels.setData63(packed, 'everything', 3, [], struct('pyramidLevel', 1));

            stored = labels.readPackedLevel(1, [1 600], [1 640], [1 3]);
            testCase.verifyEqual(stored, packed, 'level 1 holds the bytes as written');
            testCase.verifyEqual(labels.maxIndexUsed, 1073741823);
            coarse = labels.readPackedLevel(2, [51 65], [151 169], [2 2]);
            testCase.verifyTrue(all(coarse(:) == uint32(1073741823) + uint32(2^30)), ...
                'the coarser level holds the index and the mask unclipped');

            mask = labels.getData63('mask', 3, [], struct('pyramidLevel', 1));
            selection = labels.getData63('selection', 3, [], struct('pyramidLevel', 1));
            index = labels.getData63('labels', 3, [], struct('pyramidLevel', 1));
            testCase.verifyEqual(nnz(mask), 32 * 40);
            testCase.verifyEqual(nnz(selection), 21 * 21);
            testCase.verifyClass(index, 'uint32');
            testCase.verifyEqual(double(index(110, 310, 2)), 1073741823);

            labels.closeStore();
            reopened = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            reopened.openStore(storePath);
            testCase.addTeardown(@() MibBigDataLabelsUint32Test.closeQuietly(reopened));
            testCase.verifyEqual(reopened.containerClass, 'uint32', 'the layout comes from the array type');
            testCase.verifyEqual(reopened.maxMaterials, 1073741823);
            testCase.verifyEqual(reopened.maxIndexUsed, 1073741823, 'persisted in mibMaterials');
            testCase.verifyEqual(reopened.readPackedLevel(1, [1 600], [1 640], [1 3]), packed);
        end

        function coarseStrokesKeepHighIndex(testCase)
            % a labels stroke drawn at level 2 is rebuilt at level 1 on read with its
            % 30-bit index (smoothed upsample); a selection stroke at level 2 over it
            % leaves the full-resolution labels alone
            [mibModel, scratch] = testCase.buildBigDataDataset();
            labels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            labels.setLayout('uint32');
            labels.createStore([600 640 3], fullfile(scratch, 'Labels_32.zarr3'), mibModel.I{1}.image.pyramid);
            testCase.addTeardown(@() MibBigDataLabelsUint32Test.closeQuietly(labels));

            objectIndex = 987654321;
            stroke = zeros(40, 40, 1, 'uint32');
            stroke(11:30, 11:30) = objectIndex;
            labels.setData63(stroke, 'labels', 3, [], struct('magFactor', 2, 'y', [1 80], 'x', [1 80], 'z', [1 1]));
            fine = labels.getData63('labels', 3, [], struct('pyramidLevel', 1, 'y', [1 80], 'x', [1 80], 'z', [1 1]));
            testCase.verifyEqual(unique(fine(:))', uint32([0 objectIndex]), 'only the background and the index');
            testCase.verifyEqual(double(fine(40, 40)), objectIndex, 'the centre of the stroke');

            selectionStroke = zeros(40, 40, 1, 'uint8');
            selectionStroke(1:40, 1:20) = 1;
            labels.setData63(selectionStroke, 'selection', 3, [], struct('magFactor', 2, 'y', [1 80], 'x', [1 80], 'z', [1 1]));
            fineAfter = labels.getData63('labels', 3, [], struct('pyramidLevel', 1, 'y', [1 80], 'x', [1 80], 'z', [1 1]));
            testCase.verifyEqual(fineAfter, fine, 'the selection stroke left the labels as they were');
            selection = labels.getData63('selection', 3, [], struct('pyramidLevel', 1, 'y', [1 80], 'x', [1 80], 'z', [1 1]));
            testCase.verifyGreaterThan(nnz(selection), 0);
        end

        function createModelBigDataBuildsUint32Store(testCase)
            [mibModel, scratch] = testCase.buildBigDataDataset();
            storePath = fullfile(scratch, 'Labels_new.zarr3');
            BatchOpt = struct('ModelType', {{'1073741823'}}, 'ModelStorePath', storePath, 'showWaitbar', false);
            mibModel.createModel([], [], BatchOpt);
            labels = mibModel.I{1}.labels;
            testCase.addTeardown(@() MibBigDataLabelsUint32Test.closeQuietly(labels));
            testCase.verifyClass(labels, 'core.MibBigDataLabels');
            testCase.verifyEqual(labels.containerClass, 'uint32');
            testCase.verifyEqual(labels.maxMaterials, 1073741823);
            testCase.verifyEqual(char(labels.modelStorePath), storePath);
            testCase.verifyEqual(mibModel.I{1}.selectedMaterial, 3, 'instance models start at slot 3');
            testCase.verifyEqual(char(labels.modelArrays{1}.dataType()), 'uint32');
        end

        function convert63To1073741823(testCase)
            [mibModel, scratch] = testCase.buildBigDataDataset();
            source = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            sourcePath = fullfile(scratch, 'Labels_63.zarr3');
            source.createStore([600 640 3], sourcePath, mibModel.I{1}.image.pyramid);
            packed = zeros(600, 640, 3, 'uint8');
            packed(240:270, 20:60, :) = 7;
            packed(400:420, 100:120, 1) = 2 + 64;           % material 2 under the mask
            packed(500:520, 500:520, 3) = 128 + 63;         % selected material 63
            source.setData63(packed, 'everything', 3, [], struct('pyramidLevel', 1));
            source.setData63(zeros(10, 10, 1, 'uint8') + 5, 'labels', 3, [], ...
                struct('magFactor', 2, 'y', [21 40], 'x', [21 40], 'z', [1 1]));   % level 1 deferred there
            source.materialNames = {'a'; 'b'; 'c'};
            source.materialColors = lines(63);
            source.materialsCount = 3;
            mibModel.I{1}.labels = source;
            mibModel.I{1}.modelExist = true;
            testCase.addTeardown(@() MibBigDataLabelsUint32Test.closeQuietly(mibModel.I{1}.labels));

            levelCount = size(source.modelLevelSizes, 1);
            before = MibBigDataLabelsUint32Test.readAllLevels(source);
            matLevelBefore = source.matLevel;
            testCase.assertTrue(any(matLevelBefore(:) > 1), 'the fixture needs a deferred tile');

            targetPath = fullfile(scratch, 'Labels_1073741823.zarr3');
            converted = mibModel.convertModel([], struct('ModelType', {{'1073741823'}}, ...
                'ModelStorePath', targetPath, 'showWaitbar', false, 'mibBatchTooltip', struct()));
            testCase.assertTrue(converted);
            target = mibModel.I{1}.labels;
            testCase.assertEqual(target.maxMaterials, 1073741823);
            testCase.verifyEqual(target.matLevel, matLevelBefore, 'deferred levels stay deferred');
            after = MibBigDataLabelsUint32Test.readAllLevels(target);
            for level = 1:levelCount
                expected = uint32(bitand(before{level}, 63)) + uint32(bitget(before{level}, 7)) * uint32(2^30) + ...
                    uint32(bitget(before{level}, 8)) * uint32(2^31);
                testCase.verifyEqual(after{level}, expected, sprintf('level %d is the bit remap of the 63 level', level));
            end
            testCase.verifyEqual(target.maxIndexUsed, 63);
            testCase.verifyEqual(target.materialColors(1:63, :), lines(63), 'material k keeps its colour as object k');

            reopened = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            reopened.openStore(sourcePath);
            testCase.verifyEqual(reopened.containerClass, 'uint8', 'the 63 store is left on disk');
            reopened.closeStore();
        end

        function convert16383To1073741823(testCase)
            [mibModel, scratch] = testCase.buildBigDataDataset();
            source = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            source.setLayout('uint16');
            source.createStore([600 640 3], fullfile(scratch, 'Labels_16383.zarr3'), mibModel.I{1}.image.pyramid);
            packed = zeros(600, 640, 3, 'uint16');
            packed(240:270, 20:60, :) = 16383;                        % the top 16383 index
            packed(400:420, 100:120, 1) = 300 + 16384;                % object 300 under the mask
            packed(500:520, 500:520, 3) = 32768;                      % selection over background
            source.setData63(packed, 'everything', 3, [], struct('pyramidLevel', 1));
            source.materialNames = {'1'; '2'};
            colors = rand(65535, 3);
            source.materialColors = colors;
            source.objects3D = false;                                 % per-slice numbering must survive
            mibModel.I{1}.labels = source;
            mibModel.I{1}.modelExist = true;
            testCase.addTeardown(@() MibBigDataLabelsUint32Test.closeQuietly(mibModel.I{1}.labels));
            before = MibBigDataLabelsUint32Test.readAllLevels(source);

            targetPath = fullfile(scratch, 'Labels_32.zarr3');
            converted = mibModel.convertModel(1073741823, struct('ModelStorePath', targetPath, ...
                'showWaitbar', false, 'mibBatchTooltip', struct()));
            testCase.assertTrue(converted);
            target = mibModel.I{1}.labels;
            testCase.assertEqual(target.containerClass, 'uint32');
            after = MibBigDataLabelsUint32Test.readAllLevels(target);
            for level = 1:numel(before)
                expected = uint32(bitand(before{level}, 16383)) + uint32(bitget(before{level}, 15)) * uint32(2^30) + ...
                    uint32(bitget(before{level}, 16)) * uint32(2^31);
                testCase.verifyEqual(after{level}, expected, sprintf('level %d is the bit remap of the 16383 level', level));
            end
            testCase.verifyEqual(target.maxIndexUsed, 16383);
            testCase.verifyEqual(target.materialColors, colors, 'every object keeps its colour');
            testCase.verifyFalse(target.objects3D, 'the numbering keeps its meaning');
        end

        function convert1073741823To16383ClampsHighIndices(testCase)
            % To a smaller type every index above its top index becomes the top
            % index; mask and selection move down to bits 15/16.
            [mibModel, scratch] = testCase.buildBigDataDataset();
            source = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            source.setLayout('uint32');
            sourcePath = fullfile(scratch, 'Labels_32.zarr3');
            source.createStore([600 640 3], sourcePath, mibModel.I{1}.image.pyramid);
            packed = zeros(600, 640, 3, 'uint32');
            packed(240:270, 20:60, :) = 70000;                            % above 16383
            packed(400:420, 100:120, 1) = uint32(2^30) + 5;               % object 5 under the mask
            packed(500:520, 500:520, 3) = uint32(2^31) + 1073741000;      % selected, near the top
            packed(100:110, 300:310, 2) = 16383;                          % exactly the top index
            source.setData63(packed, 'everything', 3, [], struct('pyramidLevel', 1));
            source.materialNames = {'1'; '2'};
            colors = rand(65535, 3);
            source.materialColors = colors;
            mibModel.I{1}.labels = source;
            mibModel.I{1}.modelExist = true;
            testCase.addTeardown(@() MibBigDataLabelsUint32Test.closeQuietly(mibModel.I{1}.labels));
            before = MibBigDataLabelsUint32Test.readAllLevels(source);

            targetPath = fullfile(scratch, 'Labels_16383.zarr3');
            converted = mibModel.convertModel(16383, struct('ModelStorePath', targetPath, ...
                'showWaitbar', false, 'mibBatchTooltip', struct()));
            testCase.assertTrue(converted);
            target = mibModel.I{1}.labels;
            testCase.assertEqual(target.containerClass, 'uint16');
            after = MibBigDataLabelsUint32Test.readAllLevels(target);
            for level = 1:numel(before)
                materials = min(bitand(before{level}, uint32(2^30 - 1)), uint32(16383));
                expected = uint16(materials) + uint16(bitget(before{level}, 31)) * uint16(2^14) + ...
                    uint16(bitget(before{level}, 32)) * uint16(2^15);
                testCase.verifyEqual(after{level}, expected, sprintf('level %d is the clamped remap', level));
            end
            testCase.verifyEqual(target.maxIndexUsed, 16383);
            testCase.verifyEqual(target.materialColors, colors, 'every object keeps its colour');

            reopened = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            reopened.openStore(sourcePath);
            testCase.verifyEqual(reopened.containerClass, 'uint32', 'the 1073741823 store is left on disk');
            reopened.closeStore();
        end

        function convert16383To63ListsTheMaterials(testCase)
            [mibModel, scratch] = testCase.buildBigDataDataset();
            source = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            source.setLayout('uint16');
            source.createStore([600 640 3], fullfile(scratch, 'Labels_16383.zarr3'), mibModel.I{1}.image.pyramid);
            packed = zeros(600, 640, 3, 'uint16');
            packed(240:270, 20:60, :) = 300;                          % above 63
            packed(400:420, 100:120, 1) = 40 + 16384;                 % object 40 under the mask
            packed(500:520, 500:520, 3) = 32768;                      % selection over background
            source.setData63(packed, 'everything', 3, [], struct('pyramidLevel', 1));
            source.materialNames = {'1'; '2'};
            source.materialColors = rand(65535, 3);
            mibModel.I{1}.labels = source;
            mibModel.I{1}.modelExist = true;
            testCase.addTeardown(@() MibBigDataLabelsUint32Test.closeQuietly(mibModel.I{1}.labels));
            before = MibBigDataLabelsUint32Test.readAllLevels(source);

            converted = mibModel.convertModel(63, struct('ModelStorePath', fullfile(scratch, 'Labels_63.zarr3'), ...
                'showWaitbar', false, 'mibBatchTooltip', struct()));
            testCase.assertTrue(converted);
            target = mibModel.I{1}.labels;
            testCase.assertEqual(target.maxMaterials, 63);
            after = MibBigDataLabelsUint32Test.readAllLevels(target);
            for level = 1:numel(before)
                materials = min(bitand(before{level}, uint16(16383)), uint16(63));
                expected = uint8(materials) + uint8(bitget(before{level}, 15)) * uint8(64) + ...
                    uint8(bitget(before{level}, 16)) * uint8(128);
                testCase.verifyEqual(after{level}, expected, sprintf('level %d is the clamped remap', level));
            end
            testCase.verifyEqual(target.maxIndexUsed, 63);
            testCase.verifyNumElements(target.materialNames, 63, 'materials 1..63 are listed');
            testCase.verifyEqual(target.materialNames{63}, '63');
        end

        function cropToStandardGivesSeparateLayers(testCase)
            [mibModel, scratch] = testCase.buildBigDataDataset();
            labels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            labels.setLayout('uint32');
            labels.createStore([600 640 3], fullfile(scratch, 'Labels_32.zarr3'), mibModel.I{1}.image.pyramid);
            packed = zeros(600, 640, 3, 'uint32');
            packed(11:20, 11:20, 1) = 70000;
            packed(21:30, 11:20, 1) = uint32(2^31);              % selection
            packed(11:20, 21:30, 1) = uint32(2^30) + 5;          % object 5 under the mask
            labels.setData63(packed, 'everything', 3, [], struct('pyramidLevel', 1));
            labels.materialNames = {'1'; '2'};
            labels.materialColors = rand(65535, 3);
            mibModel.I{1}.labels = labels;
            mibModel.I{1}.modelExist = true;
            testCase.addTeardown(@() MibBigDataLabelsUint32Test.closeQuietly(labels));

            result = mibModel.I{1}.cropDataset([1 1 40 40 1 1], struct('showWaitbar', false));
            testCase.assertEqual(result, 1);
            dataset = mibModel.I{1};
            testCase.verifyEqual(dataset.datasetType, 'Standard');
            testCase.verifyEqual(dataset.labels.maxMaterials, 4294967295);
            testCase.verifyClass(dataset.labels.data, 'uint32');
            testCase.verifyEqual(dataset.labels.data(:, :, 1, 1, 1), bitand(packed(1:40, 1:40, 1), uint32(2^30 - 1)));
            testCase.verifyEqual(nnz(dataset.selection.data), 100);
            testCase.verifyEqual(nnz(dataset.mask.data), 100);
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
    end

    methods (Static, Access = private)
        function levels = readAllLevels(labels)
            levels = cell(1, size(labels.modelLevelSizes, 1));
            for level = 1:numel(levels)
                levelSize = labels.modelLevelSizes(level, :);
                levels{level} = labels.readPackedLevel(level, [1 levelSize(1)], [1 levelSize(2)], [1 levelSize(3)]);
            end
        end

        function closeQuietly(labels)
            % release the store handles before the temporary folder is removed
            if isvalid(labels) && isa(labels, 'core.MibBigDataLabels') && labels.exists
                try labels.closeStore(); catch; end %#ok<CTCH>
            end
        end
    end
end
