classdef ExpandSelectionTest < matlab.unittest.TestCase
% EXPANDSELECTIONTEST - Unit tests for MibModel.expandSelectionToMaskBorder.
%
% The method finds each connected component in the Selection layer, locates
% the Mask connected component whose first voxel overlaps it, and replaces
% the selection blob with the full extent of that mask region.
%
% Verification strategies:
%   expand inside mask  - small selection blob inside a mask blob grows to
%                         fill the entire mask blob
%   outside mask        - selection blob that does not touch any mask region
%                         is cleared (set to zero) after expansion
%   empty selection     - all-zero selection layer is unchanged
%   image unchanged     - image pixel data must not be modified

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function expand_selectionInsideMask_expandsToFullMaskBlob(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [40 40 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            % Mask: rows 5:30, cols 5:30, all slices - one 3D blob
            maskVolume = zeros(40, 40, 4, 'uint8');
            maskVolume(5:30, 5:30, :) = 1;
            mibModel.I{1}.clearLayer('mask');
            mibModel.setData3D(maskVolume, 'mask', 1, 3, [], opt);

            % Selection: rows 12:18, cols 12:18 - small blob strictly inside mask
            selVolume = zeros(40, 40, 4, 'uint8');
            selVolume(12:18, 12:18, :) = 1;
            mibModel.I{1}.clearLayer('selection');
            mibModel.setData3D(selVolume, 'selection', 1, 3, [], opt);

            mibModel.expandSelectionToMaskBorder(ExpandSelectionTest.batchOpt());

            result = cell2mat(mibModel.getData3D('selection', 1, 3, [], opt));
            testCase.verifyEqual(result, maskVolume, ...
                'selection must expand to exactly cover the enclosing mask blob');
        end

        function expand_selectionOutsideMask_isCleared(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [40 40 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            % Mask: top-left corner
            maskVolume = zeros(40, 40, 4, 'uint8');
            maskVolume(2:10, 2:10, :) = 1;
            mibModel.I{1}.clearLayer('mask');
            mibModel.setData3D(maskVolume, 'mask', 1, 3, [], opt);

            % Selection: bottom-right corner - does not overlap mask
            selVolume = zeros(40, 40, 4, 'uint8');
            selVolume(30:38, 30:38, :) = 1;
            mibModel.I{1}.clearLayer('selection');
            mibModel.setData3D(selVolume, 'selection', 1, 3, [], opt);

            mibModel.expandSelectionToMaskBorder(ExpandSelectionTest.batchOpt());

            result = cell2mat(mibModel.getData3D('selection', 1, 3, [], opt));
            testCase.verifyEqual(sum(double(result(:))), 0, ...
                'selection outside all mask regions must be cleared to zero');
        end

        function expand_emptySelection_remainsZero(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            maskVolume = zeros(32, 32, 4, 'uint8');
            maskVolume(5:20, 5:20, :) = 1;
            mibModel.I{1}.clearLayer('mask');
            mibModel.setData3D(maskVolume, 'mask', 1, 3, [], opt);
            mibModel.I{1}.clearLayer('selection');

            mibModel.expandSelectionToMaskBorder(ExpandSelectionTest.batchOpt());

            result = cell2mat(mibModel.getData3D('selection', 1, 3, [], opt));
            testCase.verifyEqual(sum(double(result(:))), 0, ...
                'empty selection must remain empty after expansion');
        end

        function expand_imageLayerUntouched(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            maskVolume = zeros(32, 32, 4, 'uint8');
            maskVolume(5:20, 5:20, :) = 1;
            mibModel.I{1}.clearLayer('mask');
            mibModel.setData3D(maskVolume, 'mask', 1, 3, [], opt);

            selVolume = zeros(32, 32, 4, 'uint8');
            selVolume(8:12, 8:12, :) = 1;
            mibModel.I{1}.clearLayer('selection');
            mibModel.setData3D(selVolume, 'selection', 1, 3, [], opt);

            mibModel.expandSelectionToMaskBorder(ExpandSelectionTest.batchOpt());

            imgAfter = cell2mat(mibModel.getData3D('image', 1, 3, NaN, opt));
            testCase.verifyEqual(squeeze(imgAfter), squeeze(groundTruth.image), ...
                'image pixels must not change during selection expansion');
        end

    end

    % =====================================================================
    % Private helpers
    % =====================================================================
    methods (Static, Access = private)

        function batchOpt = batchOpt()
            batchOpt.DatasetType = {'3D, Stack'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
        end

    end
end
