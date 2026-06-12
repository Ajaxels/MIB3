classdef FillOpsTest < matlab.unittest.TestCase
% FILLOPSTEST - Unit tests for MibModel.fillSelectionOrMask.
%
% Verification strategies:
%   ring fill      — a donut selection (outer box set, inner hole cleared)
%                    must have its hole filled by imfill('holes')
%   empty stays    — an all-zero layer must remain all-zero after fill
%   image untouched — pixel checksum of the image layer must not change
%   mask target    — same ring test applied to the mask layer
%   solid block    — a hole-free foreground block must not shrink after fill

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function fillSelection_ring_holeIsFilled(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            FillOpsTest.setRingLayer(mibModel, 'selection');

            mibModel.fillSelectionOrMask('selection', FillOpsTest.fillOpt('selection'));

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(double(selResult{1}(15, 15, 1)), 1, ...
                'interior pixel of ring selection must be filled');
        end

        function fillSelection_emptyLayer_remainsEmpty(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.clearLayer('selection');

            mibModel.fillSelectionOrMask('selection', FillOpsTest.fillOpt('selection'));

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(selResult{1}(:))), 0.0, ...
                'filling an empty layer must leave it all-zero');
        end

        function fillSelection_leavesImageUntouched(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            imageChecksumBefore = sum(double(gt.image(:)));

            FillOpsTest.setRingLayer(mibModel, 'selection');
            mibModel.fillSelectionOrMask('selection', FillOpsTest.fillOpt('selection'));

            imgResult = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(imgResult{1}(:))), imageChecksumBefore);
        end

        function fillMask_ring_holeIsFilled(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            FillOpsTest.setRingLayer(mibModel, 'mask');

            mibModel.fillSelectionOrMask('mask', FillOpsTest.fillOpt('mask'));

            maskResult = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(double(maskResult{1}(15, 15, 1)), 1, ...
                'interior pixel of ring mask must be filled');
        end

        function fillSelection_solidBlock_pixelCountNonDecreasing(testCase)
            % A solid block has no holes — fill must not reduce pixel count.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.clearLayer('selection');
            sel = zeros(32, 32, 4, 'uint8');
            sel(5:25, 5:25, :) = 1;
            mibModel.setData3D(sel, 'selection', 1, 3, NaN, opt);
            countBefore = double(sum(sel(:)));

            mibModel.fillSelectionOrMask('selection', FillOpsTest.fillOpt('selection'));

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyGreaterThanOrEqual(sum(double(selResult{1}(:))), countBefore, ...
                'fill on a hole-free block must not shrink the foreground');
        end

    end

    % =====================================================================
    % Private helpers
    % =====================================================================
    methods (Static, Access = private)

        function setRingLayer(mibModel, targetLayer)
            % Outer 21×21 square set to 1; inner 11×11 hole cleared to 0.
            opt = struct('id', 1, 'blockModeSwitch', 0);
            depth = mibModel.I{1}.image.depth;
            mibModel.I{1}.clearLayer(targetLayer);
            layer = zeros(mibModel.I{1}.image.height, mibModel.I{1}.image.width, depth, 'uint8');
            layer(5:25, 5:25, :)   = 1;  % outer filled square
            layer(10:20, 10:20, :) = 0;  % inner hole
            mibModel.setData3D(layer, targetLayer, 1, 3, NaN, opt);
        end

        function batchOpt = fillOpt(targetLayer)
            batchOpt.TargetLayer                  = {targetLayer};
            batchOpt.DatasetType                  = {'3D, Stack'};
            batchOpt.SelectedMaterial             = '-1';
            batchOpt.restrictSelectionToMaterial  = false;
            batchOpt.Use2DParallelComputing       = false;
            batchOpt.showWaitbar                  = false;
            batchOpt.id                           = 1;
        end

    end
end
