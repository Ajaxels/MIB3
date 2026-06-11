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
        % 3D backup/undo — whole volume
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
        % 2D backup/undo — single slice
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

    end
end
