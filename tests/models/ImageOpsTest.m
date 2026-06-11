classdef ImageOpsTest < matlab.unittest.TestCase
% IMAGEOPTEST - Unit tests for MibModel image-pixel operations.
%
% Covers: MibModel.invertImage
%
% Verification strategies:
%   pixel complement  — each inverted value must equal maxInt - original
%   round-trip        — two inversions must yield the original data
%   cross-layer       — selection/mask/labels must not change during inversion

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % -----------------------------------------------------------------
        % invertImage — pixel correctness
        % -----------------------------------------------------------------

        function invertImage_3DStack_pixelComplement(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            maxInt = mibModel.I{1}.image.maxInt;   % 255 for uint8

            batchOpt.showWaitbar    = false;
            batchOpt.id             = 1;
            batchOpt.ColorChannels  = {'All channels'};
            mibModel.invertImage('3D, Stack', batchOpt);

            result        = mibModel.getData3D('image', 1, 3, NaN, opt);
            expectedImage = maxInt - gt.image;     % uint8 complement
            testCase.verifyEqual(squeeze(result{1}), squeeze(expectedImage));
        end

        function invertImage_doubleInvert_isIdentity(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt = struct('id', 1, 'blockModeSwitch', 0);

            batchOpt.showWaitbar   = false;
            batchOpt.id            = 1;
            batchOpt.ColorChannels = {'All channels'};
            mibModel.invertImage('3D, Stack', batchOpt);
            mibModel.invertImage('3D, Stack', batchOpt);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.image));
        end

        % -----------------------------------------------------------------
        % Cross-layer isolation
        % -----------------------------------------------------------------

        function invertImage_leavesSelectionUntouched(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt                = struct('id', 1, 'blockModeSwitch', 0);
            selChecksumBefore  = sum(double(gt.selection(:)));

            batchOpt.showWaitbar   = false;
            batchOpt.id            = 1;
            batchOpt.ColorChannels = {'All channels'};
            mibModel.invertImage('3D, Stack', batchOpt);

            selResult = mibModel.getData3D('selection', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(selResult{1}(:))), selChecksumBefore);
        end

        function invertImage_leavesMaskUntouched(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel('modelType', 'labels255');
            opt               = struct('id', 1, 'blockModeSwitch', 0);
            maskChecksumBefore = sum(double(gt.mask(:)));

            batchOpt.showWaitbar   = false;
            batchOpt.id            = 1;
            batchOpt.ColorChannels = {'All channels'};
            mibModel.invertImage('3D, Stack', batchOpt);

            maskResult = mibModel.getData3D('mask', 1, 3, NaN, opt);
            testCase.verifyEqual(sum(double(maskResult{1}(:))), maskChecksumBefore);
        end

    end
end
