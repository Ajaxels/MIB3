classdef BackupUndoTest < matlab.unittest.TestCase
% BACKUPUNDOTEST - Unit tests for MibModel.backup + MibModel.undo roundtrips.
%
% Tests that backup() stores a snapshot and undo() restores it correctly.
% Verifies the enableSelection guard and the labels63 'everything' remapping.
% All tests build fresh models and do not rely on GUI state.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % 3D backup/undo - whole volume
        % -----------------------------------------------------------------

        function backup3DSelection_labels63_restored(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.backup('selection', 1, opt);

            % mutate: invert selection
            mutated = uint8(~logical(gt.selection));
            mibModel.setData3D(mutated, 'selection', 1, 3, NaN, opt);
            afterMutation = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyNotEqual(sum(double(afterMutation{1}(:))), ...
                sum(double(gt.selection(:))));

            mibModel.undo();

            restored = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(restored{1}), gt.selection);
        end

        function backup3DSelection_labels255_restored(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.backup('selection', 1, opt);

            mutated = uint8(~logical(gt.selection));
            mibModel.setData3D(mutated, 'selection', 1, 3, NaN, opt);

            mibModel.undo();

            restored = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(restored{1}), gt.selection);
        end

        function backup3DMask_labels255_leavesSelectionUntouched(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.backup('mask', 1, opt);

            mutatedMask = uint8(~logical(gt.mask));
            mibModel.setData3D(mutatedMask, 'mask', 1, 3, NaN, opt);

            mibModel.undo();

            restoredMask = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(restoredMask{1}), gt.mask);

            % selection must be unchanged (mask backup didn't touch it)
            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(selResult{1}), gt.selection);
        end

        function backup3DLabels_labels255_restored(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.backup('labels', 1, opt);

            % zero out labels
            mibModel.setData3D(zeros(size(gt.labels), 'uint8'), 'labels', 1, 3, [], opt);

            mibModel.undo();

            restored = mibModel.getData3D('labels', 1, 3, [], opt);
            testCase.verifyEqual(squeeze(restored{1}), gt.labels);
        end

        % -----------------------------------------------------------------
        % 2D backup/undo - single slice
        % -----------------------------------------------------------------

        function backup2DSelection_labels255_restored(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            % Force current slice to 1
            mibModel.I{1}.slices{3} = [1 1];
            mibModel.backup('selection', 0, opt);

            % Mutate only slice 1
            mutated = uint8(~logical(gt.selection(:,:,1)));
            mibModel.setData2D(mutated, 'selection', 1, 3, NaN, opt);

            mibModel.undo();

            restored = mibModel.getData2D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(restored{1}), squeeze(gt.selection(:,:,1)));
        end

        % -----------------------------------------------------------------
        % Guard conditions
        % -----------------------------------------------------------------

        function backupSkippedWhenEnableSelectionOff(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.enableSelection = 0;    % disable selection layer
            prevUndoBefore = mibModel.Backup.prevUndoIndex;

            mibModel.backup('selection', 1, opt);

            % backup should have been a no-op: prevUndoIndex unchanged
            testCase.verifyEqual(mibModel.Backup.prevUndoIndex, prevUndoBefore);
        end

        function imageBackupSkippedForABigDataDataset(testCase)
            % backup('image', 1) passes no coordinate ranges, so on a disk- or
            % network-resident dataset getData3D would read the ENTIRE volume to
            % take the snapshot - which is what made cropping a small region of a
            % remote S3 store appear to hang. The assertion pairs the no-op with
            % the size the snapshot would otherwise have been, so it cannot pass
            % merely because the dataset is small or the store is empty.
            storePath = testCase.buildLocalZarrPyramid();
            mibModel  = testCase.openAsBigData(storePath);

            prevUndoBefore = mibModel.Backup.prevUndoIndex;
            mibModel.backup('image', 1, struct('id', 1));

            testCase.verifyEqual(mibModel.Backup.prevUndoIndex, prevUndoBefore);
            testCase.verifyEmpty(mibModel.Backup.index3d, ...
                'a BigData image must never be snapshotted for undo');

            % what the call used to hand to getData3D
            wholeVolume = mibModel.I{1}.getData3D('image', NaN, 3, [], ...
                struct('blockModeSwitch', 0, 'roiId', -1, 'orient', 3, 't', [1 1]));
            testCase.verifyEqual(size(wholeVolume{1}), [64 64 16], ...
                'the skipped snapshot is the whole volume, not a slice');
        end

        function croppingABigDataDatasetReadsOnlyTheRegion(testCase)
            % The crop itself was never the problem - it asks for exactly the
            % requested box - so this pins that the region read survives the
            % backup guard above and still lands as a Standard buffer.
            storePath = testCase.buildLocalZarrPyramid();
            mibModel  = testCase.openAsBigData(storePath);

            % [x1 y1 dx dy z1 dz t1 dt]
            result = mibModel.I{1}.cropDataset([10 5 11 11 2 3 1 1], ...
                struct('showWaitbar', false, 'UIFigure', [], 'pyramidLevel', 1));

            testCase.verifyEqual(result, 1);
            testCase.verifyEqual(mibModel.I{1}.datasetType, 'Standard');
            testCase.verifyEqual(mibModel.I{1}.dim_yxzct, [11 11 3 1 1]);
        end

    end

    methods (Access = private)
        function storePath = buildLocalZarrPyramid(testCase)
            % A two-level OME-Zarr v2 pyramid in a temp folder - offline, native
            % backend, removed when the test method ends.
            originalLibrary = io.zarr.Config.library();
            io.zarr.Config.setLibrary('native');
            testCase.addTeardown(@() io.zarr.Config.setLibrary(originalLibrary));

            tempRoot = fullfile(tempdir, 'mib_backup_bigdata_test');
            if isfolder(tempRoot); rmdir(tempRoot, 's'); end
            mkdir(tempRoot);
            testCase.addTeardown(@() rmdir(tempRoot, 's'));

            storePath = fullfile(tempRoot, 'volume.zarr2');
            group  = io.zarr.Group.create(storePath, 'zarrFormat', 2);
            level0 = group.createArray('s0', [16 64 64], 'uint8', ...
                'chunkShape', [8 32 32], 'fillValue', 0);
            level1 = group.createArray('s1', [8 32 32], 'uint8', ...
                'chunkShape', [8 32 32], 'fillValue', 0);

            rng(0, 'twister');   % determinism - never remove
            level0.write(uint8(randi(255, [16 64 64])));
            level1.write(uint8(randi(255, [8 32 32])));

            axesDefinition = {struct('name','z','type','space','unit','nanometer'), ...
                              struct('name','y','type','space','unit','nanometer'), ...
                              struct('name','x','type','space','unit','nanometer')};
            datasets = { ...
                struct('path','s0','coordinateTransformations', ...
                    {{struct('type','scale','scale',[2 2 2])}}), ...
                struct('path','s1','coordinateTransformations', ...
                    {{struct('type','scale','scale',[4 4 4])}})};
            group.setAttributes(struct('multiscales', {{struct('version','0.4', ...
                'axes', {axesDefinition}, 'datasets', {datasets})}}));
        end

        function mibModel = openAsBigData(~, storePath)
            options = struct('datasetMode', 'BigData', 'ParentFigure', [], 'silentMode', true);
            loader  = io.loaders.Zarr2VirtualSetupLoader(options);
            [imginfo, files]    = loader.loadMetadata({storePath}, options);
            [imageData, imginfo] = loader.loadImages(files, imginfo, options);

            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            mibFolder   = fullfile(fileparts(testsFolder), 'mib');
            mibModel    = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            mibModel.I{1} = core.MibDataset(imageData, imginfo, 'BigData');
        end
    end
end
