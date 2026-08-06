classdef ResliceTransformTest < matlab.unittest.TestCase
% RESLICETRANSFORMTEST - Unit tests for MibModel.resliceDataset and MibModel.transformDataset.
%
% Verification strategies:
%   resliceDataset   - '1:2:end' of 8 slices yields depth = 4;
%                      '1:end' preserves depth; first surviving slice
%                      content matches original slice 1
%   transformDataset - double Flip horizontally is identity (round-trip);
%                      double Flip Z is identity; returns status = 1 on success

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % =================================================================
        % resliceDataset
        % =================================================================

        function reslice_stride2_depthHalved(testCase)
            % '1:2:end' on 8 slices → keep 1,3,5,7 → depth = 4
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);

            batchOpt.Dimension    = {'depth'};
            batchOpt.SliceNumbers = '1:2:end';
            batchOpt.showWaitbar  = false;
            batchOpt.id           = 1;
            mibModel.resliceDataset([], [], batchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.depth, 4, ...
                '1:2:end of 8 slices must yield depth = 4');
        end

        function reslice_keepAllSlices_depthUnchanged(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 6]);

            batchOpt.Dimension    = {'depth'};
            batchOpt.SliceNumbers = '1:end';
            batchOpt.showWaitbar  = false;
            batchOpt.id           = 1;
            mibModel.resliceDataset([], [], batchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.depth, 6, ...
                'keeping all slices must not change depth');
        end

        function reslice_stride2_firstSliceContentPreserved(testCase)
            % After stride-2 reslice, position 1 must hold the original slice 1.
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            slice1Before = squeeze(gt.image(:, :, 1));

            batchOpt.Dimension    = {'depth'};
            batchOpt.SliceNumbers = '1:2:end';
            batchOpt.showWaitbar  = false;
            batchOpt.id           = 1;
            mibModel.resliceDataset([], [], batchOpt);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}(:, :, 1)), slice1Before, ...
                'first kept slice must equal original slice 1');
        end

        % =================================================================
        % transformDataset - Flip horizontally
        % =================================================================

        function transformFlipH_doubleFlip_isIdentity(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            batchOpt.Transform   = {'Flip horizontally'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.transformDataset(batchOpt);
            mibModel.transformDataset(batchOpt);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.image), ...
                'two horizontal flips via transformDataset must recover the original');
        end

        function transformFlipZ_doubleFlip_isIdentity(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            batchOpt.Transform   = {'Flip Z'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.transformDataset(batchOpt);
            mibModel.transformDataset(batchOpt);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.image), ...
                'two Z flips via transformDataset must recover the original');
        end

        function transformFlipH_returnsSuccessStatus(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            batchOpt.Transform   = {'Flip horizontally'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            status = mibModel.transformDataset(batchOpt);

            testCase.verifyEqual(status, 1, ...
                'transformDataset must return status = 1 on success');
        end

    end
end
