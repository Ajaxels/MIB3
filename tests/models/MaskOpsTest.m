classdef MaskOpsTest < matlab.unittest.TestCase
% MASKOPSTEST - Unit tests for MibModel.invertMask.
%
% Verification strategies:
%   double-invert identity - two inversions recover the original data
%   complement            - result is bitwise complement of input
%   cross-layer isolation - image / labels must not change
%   labels63 packed path  - bit-flip on packed uint8 data

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % Mask inversion - labels255
        % -----------------------------------------------------------------

        function invertMask_mask_doubleInvert_isIdentity(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.mask(:))), 0);

            batchOpt.Target      = {'mask'};
            batchOpt.DatasetType = {'3D, Stack'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.invertMask('mask', '3D, Stack', batchOpt);
            mibModel.invertMask('mask', '3D, Stack', batchOpt);

            maskResult = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(maskResult{1}), gt.mask, ...
                'double invert of mask must recover the original');
        end

        function invertMask_mask_complement_labels255(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            batchOpt.Target      = {'mask'};
            batchOpt.DatasetType = {'3D, Stack'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.invertMask('mask', '3D, Stack', batchOpt);

            maskResult   = mibModel.getData3D('mask', 1, 3, NaN, opt);
            expectedMask = uint8(1) - gt.mask;
            testCase.verifyEqual(squeeze(maskResult{1}), expectedMask);
        end

        function invertMask_mask_leavesSelectionUntouched(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            selChecksumBefore = sum(double(gt.selection(:)));

            batchOpt.Target      = {'mask'};
            batchOpt.DatasetType = {'3D, Stack'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.invertMask('mask', '3D, Stack', batchOpt);

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(selResult{1}(:))), selChecksumBefore);
        end

        function invertMask_mask_leavesImageUntouched(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            imageChecksumBefore = sum(double(gt.image(:)));

            batchOpt.Target      = {'mask'};
            batchOpt.DatasetType = {'3D, Stack'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.invertMask('mask', '3D, Stack', batchOpt);

            imgResult = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(imgResult{1}(:))), imageChecksumBefore);
        end

        % -----------------------------------------------------------------
        % Selection inversion - labels255
        % -----------------------------------------------------------------

        function invertMask_selection_doubleInvert_isIdentity(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.selection(:))), 0);

            batchOpt.Target      = {'selection'};
            batchOpt.DatasetType = {'3D, Stack'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.invertMask('selection', '3D, Stack', batchOpt);
            mibModel.invertMask('selection', '3D, Stack', batchOpt);

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(selResult{1}), gt.selection);
        end

        function invertMask_selection_complement_labels255(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            batchOpt.Target      = {'selection'};
            batchOpt.DatasetType = {'3D, Stack'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.invertMask('selection', '3D, Stack', batchOpt);

            selResult    = mibModel.getData3D('selection', 1, 3, NaN, opt);
            expectedSel  = uint8(1) - gt.selection;
            testCase.verifyEqual(squeeze(selResult{1}), expectedSel);
        end

        % -----------------------------------------------------------------
        % Labels63 packed path
        % -----------------------------------------------------------------

        function invertMask_mask_labels63_doubleInvert_isIdentity(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.mask(:))), 0);

            batchOpt.Target      = {'mask'};
            batchOpt.DatasetType = {'3D, Stack'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.invertMask('mask', '3D, Stack', batchOpt);
            mibModel.invertMask('mask', '3D, Stack', batchOpt);

            maskResult = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(maskResult{1}), gt.mask);
        end

        function invertMask_selection_labels63_doubleInvert_isIdentity(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.selection(:))), 0);

            batchOpt.Target      = {'selection'};
            batchOpt.DatasetType = {'3D, Stack'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.invertMask('selection', '3D, Stack', batchOpt);
            mibModel.invertMask('selection', '3D, Stack', batchOpt);

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(selResult{1}), gt.selection);
        end

    end
end
