classdef MoveSelectionBigDataTest < matlab.unittest.TestCase
% MOVESELECTIONBIGDATATEST - Moving and clearing the selection of a BigData model.
%
% A synthetic 600 x 640 x 3 BigData dataset (3 levels, XY-only downsampling, so a
% coarsest-grid tile is 4 x 4 x 1 voxels) with a disk-backed uint8 model. Covers:
%
%   - models.MibModel.moveLayers for the whole stack (Shift+A/S/R) and the
%     current slice on BigData, through core.MibBigDataLabels.moveSelection: every
%     piece of the selection is moved, full-resolution labels under a selection
%     drawn zoomed out stay exact outside it, undo restores everything
%   - the level the move works at: the coarse level when every layer of the
%     selection tiles lives there, full resolution otherwise
%   - local replace (tiles holding selection) and whole-volume replace
%     (core.MibBigDataLabels.eraseEverywhere, each tile at its own level)
%   - models.MibModel.clearSelection on BigData through
%     core.MibBigDataLabels.clearSelectionTiles: a stroke drawn finer than the
%     coarsest level is cleared too, the labels are left alone, undo restores
%   - core.MibBigDataLabels.selectionTiles as setData63 keeps it
%
% Writes to disk and drives the zarr saver and loader, so tagged Integration.
%
% See also: core.MibBigDataLabels.moveSelection, core.MibBigDataLabels.clearSelectionTiles,
% core.MibBigDataLabels.eraseEverywhere, models.MibModel.moveLayers

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function shiftAMovesEveryPieceOfTheSelection(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            testCase.drawCoarseSelection(labels, 1);
            testCase.drawCoarseSelection(labels, 3);
            labels.setData63(uint8(1), 'selection', 3, [], struct('pyramidLevel', 1, 'y', [50 50], 'x', [50 50], 'z', [2 2]));
            selectionBefore = MoveSelectionBigDataTest.fullRes(mibModel, 'selection');
            testCase.assertGreaterThan(nnz(selectionBefore(:, :, [1 3])), 0);

            MoveSelectionBigDataTest.move(mibModel, '3D, Stack', 'add', 2);
            labelsAfter = MoveSelectionBigDataTest.fullRes(mibModel, 'labels');
            testCase.verifyEqual(labelsAfter(selectionBefore == 1), repmat(uint8(2), nnz(selectionBefore), 1), ...
                'every selected voxel of every slice gets the material');
            testCase.verifyEqual(nnz(labelsAfter), nnz(selectionBefore), 'nothing else gets it');
            testCase.verifyEqual(nnz(MoveSelectionBigDataTest.fullRes(mibModel, 'selection')), 0, 'the selection is consumed');
            testCase.verifyFalse(any(labels.selectionTiles, 'all'), 'no tile holds selection after the move');
        end

        function shiftAKeepsFineLabelsUnderACoarseSelection(testCase)
            % The selection is drawn at 25% zoom over labels drawn at full
            % resolution; the move works at full resolution there, so the labels
            % outside the selection keep their one-pixel pattern.
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            fineLabels = MoveSelectionBigDataTest.writeFineCheckerboard(labels);
            % a disk, so the tiles on its edge are partly selected
            [cols, rows] = meshgrid(1:16, 1:16);
            strokeDisk = uint8((rows - 8.5).^2 + (cols - 8.5).^2 <= 6^2);
            labels.setData63(strokeDisk, 'selection', 3, [], ...
                struct('magFactor', 4, 'y', [81 144], 'x', [81 144], 'z', [1 1]));
            selectionBefore = MoveSelectionBigDataTest.fullRes(mibModel, 'selection');
            testCase.assertGreaterThan(nnz(fineLabels(selectionBefore == 0 & fineLabels > 0 & ...
                repmat(imdilate(selectionBefore(:, :, 1), ones(9)), [1 1 3]))), 0, ...
                'the edge tiles hold labels outside the selection');

            MoveSelectionBigDataTest.move(mibModel, '3D, Stack', 'add', 3);
            expected = fineLabels;
            expected(selectionBefore == 1) = 3;
            testCase.verifyEqual(MoveSelectionBigDataTest.fullRes(mibModel, 'labels'), expected, ...
                'labels outside the selection stay exact at full resolution');

            mibModel.undo();
            testCase.verifyEqual(MoveSelectionBigDataTest.fullRes(mibModel, 'labels'), fineLabels, 'undo restores the labels');
            testCase.verifyEqual(MoveSelectionBigDataTest.fullRes(mibModel, 'selection'), selectionBefore, 'undo restores the selection');
        end

        function coarseSelectionIsMovedAtTheCoarseLevel(testCase)
            % Nothing finer than level 3 in the selection tiles: the move reads and
            % writes level 3 only, and the full-resolution labels elsewhere stay
            % authoritative at level 1.
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            fineLabels = MoveSelectionBigDataTest.writeFineCheckerboard(labels);
            labels.setData63(ones(8, 8, 1, 'uint8'), 'selection', 3, [], ...
                struct('magFactor', 4, 'y', [401 432], 'x', [401 432], 'z', [2 2]));

            status = labels.moveSelection('labels', 'add', struct('materialIndex', 2));
            testCase.verifyEqual(status.levels, 3, 'the move works at the level the selection was drawn at');
            labelsAfter = MoveSelectionBigDataTest.fullRes(mibModel, 'labels');
            testCase.verifyEqual(labelsAfter(:, :, 1), fineLabels(:, :, 1), 'labels away from the selection are untouched');
            testCase.verifyGreaterThan(nnz(labelsAfter(401:432, 401:432, 2) == 2), 0.9 * 32^2);
            testCase.verifyTrue(all(labels.matLevel(25:40, 25:40, 1, 1) == 1, 'all'), ...
                'the fine labels stay authoritative at full resolution');
        end

        function twoDMoveTouchesOnlyTheCurrentSlice(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            testCase.drawCoarseSelection(labels, 1);
            testCase.drawCoarseSelection(labels, 2);
            mibModel.I{1}.slices{3} = [2 2];

            MoveSelectionBigDataTest.move(mibModel, '2D, Slice', 'add', 1);
            labelsAfter = MoveSelectionBigDataTest.fullRes(mibModel, 'labels');
            selectionAfter = MoveSelectionBigDataTest.fullRes(mibModel, 'selection');
            testCase.verifyGreaterThan(nnz(labelsAfter(:, :, 2)), 0, 'the current slice is moved');
            testCase.verifyEqual(nnz(labelsAfter(:, :, 1)), 0, 'another slice is not');
            testCase.verifyGreaterThan(nnz(selectionAfter(:, :, 1)), 0, 'and keeps its selection');
            testCase.verifyEqual(nnz(selectionAfter(:, :, 2)), 0);
        end

        function localReplaceClearsTheMaterialAroundTheSelectionOnly(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            volume = zeros(600, 640, 3, 'uint8');
            volume(10:20, 10:20, 1) = 1;            % far from the selection
            volume(229:236, 49:56, 1) = 1;          % between two pieces of the selection
            labels.setData63(volume, 'labels', 3, [], struct('pyramidLevel', 1));
            selection = zeros(8, 40, 'uint8');
            selection(:, [1:8, 33:40]) = 1;         % cols 33:40 and 65:72
            labels.setData63(selection, 'selection', 3, [], ...
                struct('pyramidLevel', 1, 'y', [229 236], 'x', [33 72], 'z', [1 1]));

            labels.moveSelection('labels', 'replace', struct('materialIndex', 1));
            labelsAfter = MoveSelectionBigDataTest.fullRes(mibModel, 'labels');
            testCase.verifyEqual(labelsAfter(10:20, 10:20, 1), ones(11, 'uint8'), 'material far away is kept');
            testCase.verifyEqual(labelsAfter(229:236, 49:56, 1), ones(8, 'uint8'), ...
                'material in the box but not in a selection tile is kept');
            testCase.verifyEqual(labelsAfter(229:236, [33:40, 65:72], 1), ones(8, 16, 'uint8'), ...
                'the selection becomes the material');
        end

        function localReplaceInsideOneTileClearsTheRestOfIt(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            labels.setData63(uint8(1), 'labels', 3, [], struct('pyramidLevel', 1, 'y', [101 101], 'x', [101 101], 'z', [1 1]));
            labels.setData63(uint8(1), 'selection', 3, [], struct('pyramidLevel', 1, 'y', [104 104], 'x', [104 104], 'z', [1 1]));
            labels.moveSelection('labels', 'replace', struct('materialIndex', 1));
            labelsAfter = MoveSelectionBigDataTest.fullRes(mibModel, 'labels');
            testCase.verifyEqual(labelsAfter(101, 101, 1), uint8(0), 'the material of the selection tile is replaced');
            testCase.verifyEqual(labelsAfter(104, 104, 1), uint8(1));
        end

        function localReplaceWithAnUnknownTileMapClearsOnlyAroundTheSelection(testCase)
            % An old side-file leaves every tile a selection candidate; the
            % blocks to clear must still come from where the selection is
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            volume = zeros(600, 640, 3, 'uint8');
            volume(101:108, 101:108, :) = 1;        % under the selection, on every slice
            volume(301:310, 301:310, 2) = 1;        % same slice, far away
            labels.setData63(volume, 'labels', 3, [], struct('pyramidLevel', 1));
            labels.setData63(ones(2, 2, 'uint8'), 'selection', 3, [], ...
                struct('pyramidLevel', 1, 'y', [101 102], 'x', [101 102], 'z', [2 2]));
            labels.selectionTiles(:) = true;

            labels.moveSelection('labels', 'replace', struct('materialIndex', 1));
            labelsAfter = MoveSelectionBigDataTest.fullRes(mibModel, 'labels');
            testCase.verifyEqual(labelsAfter(101:108, 101:108, [1 3]), ones(8, 8, 2, 'uint8'), ...
                'the slices without selection keep their material');
            testCase.verifyEqual(labelsAfter(301:310, 301:310, 2), ones(10, 'uint8'), 'material far away is kept');
            expected = ones(8, 'uint8');   % the coarsest tiles are 4 px: one 4 x 4 block is cleared
            expected(1:4, 1:4) = 0;
            expected(1:2, 1:2) = 1;
            testCase.verifyEqual(labelsAfter(101:108, 101:108, 2), expected, ...
                'the block of the selection is replaced');
        end

        function localReplaceKeepsTheNeighbourSliceOfAZTile(testCase)
            % A pyramid that also halves z: a coarsest tile spans two slices
            mibModel = testCase.buildModel('Anisotropy-preserving', 4, 0.02);
            labels = mibModel.I{1}.labels;
            testCase.verifyEqual(labels.modelScaleFactors(end, 3), 2, 'the fixture halves z at the coarsest level');
            volume = zeros(600, 640, 4, 'uint8');
            volume(101:108, 101:108, :) = 1;
            labels.setData63(volume, 'labels', 3, [], struct('pyramidLevel', 1));
            labels.setData63(ones(2, 2, 'uint8'), 'selection', 3, [], ...
                struct('pyramidLevel', 1, 'y', [101 102], 'x', [101 102], 'z', [1 1]));

            labels.moveSelection('labels', 'replace', struct('materialIndex', 1));
            labelsAfter = MoveSelectionBigDataTest.fullRes(mibModel, 'labels');
            testCase.verifyEqual(labelsAfter(101:108, 101:108, 2:4), ones(8, 8, 3, 'uint8'), ...
                'slice 2, in the same tile as slice 1, keeps its material');
            expected = ones(8, 'uint8');
            expected(1:4, 1:4) = 0;
            expected(1:2, 1:2) = 1;
            testCase.verifyEqual(labelsAfter(101:108, 101:108, 1), expected, 'slice 1: the block of the selection is replaced');
        end

        function cancelledUndoLeavesTheMoveAndTheHistory(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            fineLabels = MoveSelectionBigDataTest.writeFineCheckerboard(labels);
            testCase.drawCoarseSelection(labels, 1);
            testCase.drawCoarseSelection(labels, 3);
            MoveSelectionBigDataTest.move(mibModel, '3D, Stack', 'add', 3);
            movedLabels = MoveSelectionBigDataTest.fullRes(mibModel, 'labels');
            testCase.verifyNotEqual(movedLabels, fineLabels);

            % write the entry back one slice at a time, cancel before the last slice
            entryIndex = mibModel.Backup.undoIndex - 1;
            testCase.verifyEqual(mibModel.Backup.undoList(entryIndex).type, 'everything');
            cancelCalls = 0;
            function cancel = cancelOnSecondCheck()
                cancelCalls = cancelCalls + 1;
                cancel = cancelCalls >= 2;
            end
            mibModel.Backup.undoList(entryIndex).options.undoSlabVoxels = 1;
            mibModel.Backup.undoList(entryIndex).options.undoCancelFcn = @cancelOnSecondCheck;
            undoIndexBefore = mibModel.Backup.undoIndex;
            mibModel.undo();
            testCase.verifyEqual(cancelCalls, 2, 'undo was cancelled part way');
            testCase.verifyEqual(MoveSelectionBigDataTest.fullRes(mibModel, 'labels'), movedLabels, ...
                'the slices already restored are put back');
            testCase.verifyEqual(mibModel.Backup.undoIndex, undoIndexBefore, 'the undo history is unchanged');

            mibModel.Backup.undoList(entryIndex).options = rmfield(mibModel.Backup.undoList(entryIndex).options, 'undoCancelFcn');
            mibModel.undo();
            testCase.verifyEqual(MoveSelectionBigDataTest.fullRes(mibModel, 'labels'), fineLabels, ...
                'a full undo in slabs brings the labels back');
        end

        function wholeVolumeReplaceRemovesTheMaterialEverywhere(testCase)
            % A batch run of replace takes the whole volume, with no dialog
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            volume = zeros(600, 640, 3, 'uint8');
            volume(10:20, 10:20, 1) = 1;
            volume(30:40, 30:40, 1) = 2;
            labels.setData63(volume, 'labels', 3, [], struct('pyramidLevel', 1));
            labels.setData63(ones(8, 8, 1, 'uint8'), 'labels', 3, 1, ...
                struct('magFactor', 4, 'y', [301 332], 'x', [301 332], 'z', [3 3]));   % drawn zoomed out
            labels.setData63(ones(8, 8, 1, 'uint8'), 'selection', 3, [], ...
                struct('pyramidLevel', 1, 'y', [501 508], 'x', [501 508], 'z', [2 2]));

            MoveSelectionBigDataTest.move(mibModel, '3D, Stack', 'replace', 1);
            for level = 1:3
                levelLabels = labels.getData63('labels', 3, [], struct('pyramidLevel', level));
                testCase.verifyEqual(nnz(levelLabels == 1), nnz(labels.getData63('labels', 3, 1, ...
                    struct('pyramidLevel', level, 'y', [501 508], 'x', [501 508], 'z', [2 2]))), ...
                    sprintf('at level %d material 1 is only where the selection was', level));
            end
            labelsAfter = MoveSelectionBigDataTest.fullRes(mibModel, 'labels');
            testCase.verifyEqual(labelsAfter(501:508, 501:508, 2), ones(8, 'uint8'));
            testCase.verifyEqual(labelsAfter(30:40, 30:40, 1), repmat(uint8(2), 11, 11), 'another material is untouched');
        end

        function eraseEverywhereKeepsEachTileAtItsLevel(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            fineLabels = MoveSelectionBigDataTest.writeFineCheckerboard(labels);   % materials 1 and 2
            labels.setData63(ones(8, 8, 1, 'uint8'), 'labels', 3, 1, ...
                struct('magFactor', 4, 'y', [301 332], 'x', [301 332], 'z', [1 1]));
            levelMapBefore = labels.matLevel;

            status = labels.eraseEverywhere(1, 1);
            testCase.verifyTrue(status.changed);
            testCase.verifyEqual(labels.matLevel, levelMapBefore, 'every tile keeps its level');
            labelsAfter = MoveSelectionBigDataTest.fullRes(mibModel, 'labels');
            testCase.verifyEqual(nnz(labelsAfter == 1), 0, 'material 1 is gone at full resolution');
            testCase.verifyEqual(labelsAfter == 2, fineLabels == 2, 'material 2 is exactly as it was');
            coarsest = labels.getData63('labels', 3, [], struct('pyramidLevel', 3));
            testCase.verifyEqual(nnz(coarsest == 1), 0, 'and at the coarsest level');
        end

        function shiftCClearsAFineStrokeAndKeepsTheLabels(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            fineLabels = MoveSelectionBigDataTest.writeFineCheckerboard(labels);
            testCase.drawCoarseSelection(labels, 1);
            % a one-pixel stroke at full resolution, missing from the coarser levels
            labels.setData63(uint8(1), 'selection', 3, [], struct('pyramidLevel', 1, 'y', [102 102], 'x', [103 103], 'z', [2 2]));
            selectionBefore = MoveSelectionBigDataTest.fullRes(mibModel, 'selection');

            mibModel.clearSelection('3D, Stack', struct('showWaitbar', false));
            testCase.verifyEqual(nnz(MoveSelectionBigDataTest.fullRes(mibModel, 'selection')), 0, ...
                'the selection is cleared at full resolution, a fine stroke included');
            testCase.verifyEqual(MoveSelectionBigDataTest.fullRes(mibModel, 'labels'), fineLabels, 'the labels are left alone');
            testCase.verifyFalse(any(labels.selectionTiles, 'all'));

            mibModel.undo();
            testCase.verifyEqual(MoveSelectionBigDataTest.fullRes(mibModel, 'selection'), selectionBefore, ...
                'undo brings the selection back at full resolution');
            testCase.verifyEqual(MoveSelectionBigDataTest.fullRes(mibModel, 'labels'), fineLabels);
        end

        function clearOfOneSliceKeepsTheOthers(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            testCase.drawCoarseSelection(labels, 1);
            testCase.drawCoarseSelection(labels, 2);
            mibModel.I{1}.slices{3} = [1 1];
            mibModel.clearSelection('2D, Slice', struct('showWaitbar', false));
            selectionAfter = MoveSelectionBigDataTest.fullRes(mibModel, 'selection');
            testCase.verifyEqual(nnz(selectionAfter(:, :, 1)), 0);
            testCase.verifyGreaterThan(nnz(selectionAfter(:, :, 2)), 0);
        end

        function selectionTilesFollowTheWrites(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            testCase.verifyFalse(any(labels.selectionTiles, 'all'), 'a new model has no selection');
            labels.setData63(uint8(1), 'selection', 3, [], struct('pyramidLevel', 1, 'y', [9 9], 'x', [13 13], 'z', [2 2]));
            testCase.verifyEqual(find(labels.selectionTiles), sub2ind(size(labels.selectionTiles), 3, 4, 2));
            labels.setData63(zeros(8, 8, 'uint8'), 'selection', 3, [], struct('pyramidLevel', 1, 'y', [5 12], 'x', [9 16], 'z', [2 2]));
            testCase.verifyFalse(any(labels.selectionTiles, 'all'), 'a write covering the tile settles it');

            % A pixel of tile (3, 4) drawn at full resolution that the coarsest level
            % does not show (its nearest sample is the cleared pixel 9, 13). A
            % coarse write over the tile cannot tell it is there, so the tile stays
            % a candidate; tile (1, 1), whose selection lives at that level, settles.
            fullResPixel = @(value, row, col) labels.setData63(uint8(value), 'selection', 3, [], ...
                struct('pyramidLevel', 1, 'y', [row row], 'x', [col col], 'z', [1 1]));
            fullResPixel(1, 12, 16);
            fullResPixel(1, 9, 13);
            fullResPixel(0, 9, 13);
            labels.setData63(uint8(1), 'selection', 3, [], struct('pyramidLevel', 3, 'y', [1 4], 'x', [1 4], 'z', [1 1]));
            labels.setData63(zeros(4, 4, 'uint8'), 'selection', 3, [], struct('pyramidLevel', 3, 'y', [1 16], 'x', [1 16], 'z', [1 1]));
            testCase.verifyTrue(labels.selectionTiles(3, 4, 1), 'a tile whose selection lives finer stays a candidate');
            testCase.verifyFalse(labels.selectionTiles(1, 1, 1), 'a tile whose selection lives at the written level settles');
            selection = MoveSelectionBigDataTest.fullRes(mibModel, 'selection');
            testCase.verifyEqual(selection(12, 16, 1), uint8(1), 'and the pixel is still there');
        end

        function cancelBeforeTheFirstWriteChangesNothing(testCase)
            mibModel = testCase.buildModel();
            labels = mibModel.I{1}.labels;
            testCase.drawCoarseSelection(labels, 1);
            status = labels.moveSelection('labels', 'add', struct('materialIndex', 1, 'progressFcn', @(~) true));
            testCase.verifyTrue(status.cancelled);
            testCase.verifyFalse(status.changed);
            testCase.verifyEqual(nnz(MoveSelectionBigDataTest.fullRes(mibModel, 'labels')), 0);
        end
    end

    methods (Access = private)
        function mibModel = buildModel(testCase, downsampleStrategy, depth, zPixelSize)
            % 600 x 640 x 3 BigData dataset, 3 levels XY only, with an empty uint8 model
            if nargin < 2; downsampleStrategy = 'XY only'; end
            if nargin < 3; depth = 3; end
            if nargin < 4; zPixelSize = 0.03; end
            folderFixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            scratch = folderFixture.Folder;
            sourceImage = fullfile(scratch, 'src.zarr3');
            rng(4);
            io.savers.Zarr3Saver(struct()).save(uint8(randi(255, 600, 640, depth)), ...
                struct('pixSize', struct('x', 0.01, 'y', 0.01, 'z', zPixelSize, 'units', 'um')), sourceImage, ...
                struct('silent', true, 'showWaitbar', false, 'ChunkSize', [64 64 1], ...
                'Levels', 3, 'DownsampleStrategy', downsampleStrategy));

            mibFolder = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'mib');
            mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            loaderOptions = struct('datasetMode', 'BigData');
            loader = io.loaders.Zarr3VirtualSetupLoader(loaderOptions);
            [imageInfo, files] = loader.loadMetadata({sourceImage}, loaderOptions);
            [image, imageInfo] = loader.loadImages(files, imageInfo, loaderOptions);
            mibModel.I{1}.initialize(image, imageInfo, 'BigData');
            mibModel.I{1}.enableSelection = true;

            labels = core.MibBigDataLabels([], core.MibImage.initializeImgInfo());
            labels.createStore([600 640 depth], fullfile(scratch, 'Labels_src.zarr3'), mibModel.I{1}.image.pyramid);
            labels.materialNames = {'1'; '2'; '3'};
            labels.materialColors = rand(3, 3);
            mibModel.I{1}.labels = labels;
            mibModel.I{1}.modelExist = true;
            testCase.addTeardown(@() MoveSelectionBigDataTest.closeQuietly(mibModel));
        end

        function drawCoarseSelection(~, labels, slice)
            % a 32 x 32 px stroke drawn at 25% zoom (level 3) on one slice
            labels.setData63(ones(8, 8, 1, 'uint8'), 'selection', 3, [], ...
                struct('magFactor', 4, 'y', [97 128], 'x', [97 128], 'z', [slice slice]));
        end
    end

    methods (Static, Access = private)
        function move(mibModel, datasetType, action, addToMaterial)
            % moveLayers as a batch run: no dialogs, no progress window
            BatchOpt = struct('showWaitbar', false, 'SelectedAddToMaterial', num2str(addToMaterial), ...
                'restrictSelectionToMaterial', false, 'restrictSelectionToMask', false, ...
                'blockModeSwitch', false, 'roiId', '-1');
            mibModel.moveLayers('selection', 'labels', datasetType, action, BatchOpt);
        end

        function volume = fullRes(mibModel, type)
            volume = mibModel.I{1}.labels.getData63(type, 3, [], struct('pyramidLevel', 1));
        end

        function fineLabels = writeFineCheckerboard(labels)
            % one-pixel checkerboard of materials 1 and 2 over rows/cols 81:160, all slices
            [cols, rows] = meshgrid(1:80, 1:80);
            board = uint8(1 + mod(rows + cols, 2));
            fineLabels = zeros(600, 640, 3, 'uint8');
            fineLabels(81:160, 81:160, :) = repmat(board, [1 1 3]);
            labels.setData63(fineLabels, 'labels', 3, [], struct('pyramidLevel', 1));
        end

        function closeQuietly(mibModel)
            try
                mibModel.I{1}.labels.closeStore();
            catch
            end
        end
    end
end
