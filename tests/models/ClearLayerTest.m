classdef ClearLayerTest < matlab.unittest.TestCase
% CLEARLAYERTEST - Unit tests for MibDataset.clearLayer (and MibModel-level access).
%
% Verifies that clearing a layer:
%   1. Zeros the target layer completely.
%   2. Leaves all other layers intact (checksum-stable).
%   3. '2D' mode clears only the current slice; other slices are untouched.
%
% Uses the checksum-stable ground truth from buildSyntheticModel.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % Full-volume ('4D') clear — labels63
        % -----------------------------------------------------------------

        function clearSelection_labels63_zeros(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.selection(:))), 0);

            mibModel.I{1}.clearLayer('selection');

            result = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(result{1}(:))), 0.0);
        end

        function clearMask_labels63_zeros(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.mask(:))), 0);

            mibModel.I{1}.clearLayer('mask');

            result = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(result{1}(:))), 0.0);
        end

        function clearLabels_labels63_zeros(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels63');
            opt = struct('id', 1, 'blockModeSwitch', 0);
            testCase.assumeGreaterThan(sum(double(gt.labels(:))), 0);

            mibModel.I{1}.clearLayer('labels');

            result = mibModel.getData3D('labels', 1, 3, [], opt);
            testCase.verifyEqual(sum(double(result{1}(:))), 0.0);
        end

        % -----------------------------------------------------------------
        % Cross-layer isolation — labels255
        % -----------------------------------------------------------------

        function clearSelection_labels255_leavesImageIntact(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            imageChecksumBefore = sum(double(gt.image(:)));
            mibModel.I{1}.clearLayer('selection');

            imgResult = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(imgResult{1}(:))), imageChecksumBefore);
        end

        function clearSelection_labels255_leavesMaskIntact(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            maskChecksumBefore = sum(double(gt.mask(:)));
            mibModel.I{1}.clearLayer('selection');

            maskResult = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(maskResult{1}(:))), maskChecksumBefore);
        end

        function clearMask_labels255_leavesLabelsIntact(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            labelsChecksumBefore = sum(double(gt.labels(:)));
            mibModel.I{1}.clearLayer('mask');

            labResult = mibModel.getData3D('labels', 1, 3, [], opt);
            testCase.verifyEqual(sum(double(labResult{1}(:))), labelsChecksumBefore);
        end

        function clearLabels_labels255_leavesSelectionIntact(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            selectionChecksumBefore = sum(double(gt.selection(:)));
            mibModel.I{1}.clearLayer('labels');

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(selResult{1}(:))), selectionChecksumBefore);
        end

        % -----------------------------------------------------------------
        % 2D mode — only current slice cleared
        % -----------------------------------------------------------------

        function clearSelection2D_labels255_onlyCurrentSliceZeroed(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            depth = size(gt.selection, 3);

            % Set current slice to the middle slice and verify it is non-zero
            midSlice = ceil(depth / 2);
            mibModel.I{1}.slices{3} = [midSlice midSlice];
            testCase.assumeGreaterThan(sum(double(gt.selection(:,:,midSlice)), 'all'), 0);

            mibModel.I{1}.clearLayer('selection', '2D');

            % Cleared slice is zero
            sliceResult = mibModel.getData2D('selection', midSlice, 3, NaN, opt);
            testCase.verifyEqual(sum(double(sliceResult{1}(:))), 0.0);

            % All other slices are intact — check slice 1 (if different)
            if midSlice > 1
                otherResult = mibModel.getData2D('selection', 1, 3, NaN, opt);
                testCase.verifyEqual(squeeze(otherResult{1}), ...
                    squeeze(gt.selection(:, :, 1)));
            end
        end

        function clearMask2D_labels255_onlyCurrentSliceZeroed(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.slices{3} = [1 1];
            testCase.assumeGreaterThan(sum(double(gt.mask(:,:,1)), 'all'), 0);

            mibModel.I{1}.clearLayer('mask', '2D');

            sliceResult = mibModel.getData2D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(sliceResult{1}(:))), 0.0);

            % Slice 2 mask is untouched
            if size(gt.mask, 3) >= 2
                otherResult = mibModel.getData2D('mask', 2, 3, NaN, opt);
                testCase.verifyEqual(squeeze(otherResult{1}), ...
                    squeeze(gt.mask(:, :, 2)));
            end
        end

    end
end
