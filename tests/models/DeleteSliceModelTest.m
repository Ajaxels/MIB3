classdef DeleteSliceModelTest < matlab.unittest.TestCase
% DELETESLICEMODELTEST - Unit tests for MibModel.deleteSlice (BatchOpt wrapper).
%
% MibModel.deleteSlice is a batch-compatible dispatcher that delegates to
% MibDataset.deleteSlice. MibDataset.deleteSlice is tested separately in
% SpatialOpsTest; here we verify the MibModel-level BatchOpt path, including
% multi-slice deletion and the string-range DeletePosition field.
%
% Call pattern: mibModel.deleteSlice([], [], batchOpt) - nargin=4 triggers
% the batch path.
%
% Verification strategies:
%   single-slice delete   - depth decreases by 1
%   multi-slice range     - DeletePosition '2:4' removes 3 slices; depth − 3
%   content preserved     - a known slice that survives keeps its pixel data
%   width unchanged       - spatial dimensions other than depth are unaffected

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function deleteSlice_singleSlice_depthDecreasedByOne(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);

            batchOpt.Dimension      = {'depth'};
            batchOpt.DeletePosition = '3';
            batchOpt.showWaitbar    = false;
            batchOpt.id             = 1;
            mibModel.deleteSlice([], [], batchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.depth, 7, ...
                'deleting one slice must decrease depth by 1');
        end

        function deleteSlice_rangeOf3_depthDecreasedBy3(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);

            batchOpt.Dimension      = {'depth'};
            batchOpt.DeletePosition = '2:4';
            batchOpt.showWaitbar    = false;
            batchOpt.id             = 1;
            mibModel.deleteSlice([], [], batchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.depth, 5, ...
                '1:2:end-style deletion of 3 slices must leave depth = 5');
        end

        function deleteSlice_survivingSlice_contentPreserved(testCase)
            % After deleting slice 3, what was originally slice 5 is now at
            % position 4 - verify its pixel data matches the ground truth.
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            slice5Before = squeeze(groundTruth.image(:, :, 5));

            batchOpt.Dimension      = {'depth'};
            batchOpt.DeletePosition = '3';
            batchOpt.showWaitbar    = false;
            batchOpt.id             = 1;
            mibModel.deleteSlice([], [], batchOpt);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}(:, :, 4)), slice5Before, ...
                'original slice 5 must be at position 4 after deleting slice 3');
        end

        function deleteSlice_spatialDimsUnchanged(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 8]);

            batchOpt.Dimension      = {'depth'};
            batchOpt.DeletePosition = '1';
            batchOpt.showWaitbar    = false;
            batchOpt.id             = 1;
            mibModel.deleteSlice([], [], batchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.height, 16, ...
                'height must not change when deleting a z-slice');
            testCase.verifyEqual(mibModel.I{1}.image.width, 24, ...
                'width must not change when deleting a z-slice');
        end

    end
end
