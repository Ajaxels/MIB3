classdef GetDatasetDimensionsTest < matlab.unittest.TestCase
% GETDATASETDIMENSIONSTEST - Unit tests for MibDataset.getDatasetDimensions.
%
% Verification strategies:
%   splitDims=true  — five individual outputs match buildSyntheticModel dims
%   splitDims=false — single vector [h w d c t] output
%   orient=3 (YX)   — dimensions reported in the default XY orientation
%   mask/labels     — type argument accepted for non-image layers

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function getDims_image_splitDims_matchesBuildArgs(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [12 20 6]);

            [height, width, depth, colors, time] = ...
                mibModel.I{1}.getDatasetDimensions('image', 3, struct('blockModeSwitch', 0));

            testCase.verifyEqual(height, 12);
            testCase.verifyEqual(width,  20);
            testCase.verifyEqual(depth,   6);
            testCase.verifyEqual(colors,  1);
            testCase.verifyEqual(time,    1);
        end

        function getDims_image_splitDimsFalse_returnsVector(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [8 16 4]);

            opts.blockModeSwitch = 0;
            opts.splitDims = false;
            dims = mibModel.I{1}.getDatasetDimensions('image', 3, opts);

            testCase.verifyEqual(dims, [8, 16, 4, 1, 1], ...
                'splitDims=false must return a single [h w d c t] vector');
        end

        function getDims_labels_returnsDepthNotColors(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [8 8 5]);

            [~, ~, depth, ~, ~] = ...
                mibModel.I{1}.getDatasetDimensions('labels', 3, struct('blockModeSwitch', 0));

            testCase.verifyEqual(depth, 5, ...
                'getDatasetDimensions for labels must return the correct depth');
        end

    end
end
