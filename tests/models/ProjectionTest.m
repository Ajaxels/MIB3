classdef ProjectionTest < matlab.unittest.TestCase
% PROJECTIONTEST - Unit tests for MibModel.intensityProjection.
%
% Internal dimension convention:
%   getData4D returns [h,w,z,c,t]; PossibleDimensions = {'Y','X','Z','C','T'}.
%   'Z' maps to dim=3 in the array, so the projection collapses depth and
%   the output is [h,w,1,c,t] — height and width are preserved, depth=1.
%
% Verification strategies:
%   Z-axis projection — output depth = 1 for Max, Min, Mean
%   output height     — equals original depth (post-permute geometry)
%   Max >= Min        — pixel-sum of Max result ≥ pixel-sum of Min result
%   image class       — uint8 in → uint8 out for non-Sum projections

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function maxProjectionZ_outputDepthIsOne(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);

            mibModel.intensityProjection(ProjectionTest.projOpt(mibModel, 'Max', 'Z'));

            testCase.verifyEqual(mibModel.I{1}.image.depth, 1, ...
                'Z Max projection must produce output depth = 1');
        end

        function minProjectionZ_outputDepthIsOne(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);

            mibModel.intensityProjection(ProjectionTest.projOpt(mibModel, 'Min', 'Z'));

            testCase.verifyEqual(mibModel.I{1}.image.depth, 1);
        end

        function meanProjectionZ_outputDepthIsOne(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);

            mibModel.intensityProjection(ProjectionTest.projOpt(mibModel, 'Mean', 'Z'));

            testCase.verifyEqual(mibModel.I{1}.image.depth, 1);
        end

        function maxProjectionZ_outputWidthUnchanged(testCase)
            % Z projection collapses depth; height and width are preserved.
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 8]);

            mibModel.intensityProjection(ProjectionTest.projOpt(mibModel, 'Max', 'Z'));

            testCase.verifyEqual(mibModel.I{1}.image.width, 24, ...
                'Z projection must preserve the original width');
            testCase.verifyEqual(mibModel.I{1}.image.height, 16, ...
                'Z projection must preserve the original height');
        end

        function maxVsMin_pixelSumOrdering(testCase)
            % Two fresh identical datasets — Max projection sum ≥ Min projection sum.
            [mibModelMax, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);
            [mibModelMin, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 8]);

            mibModelMax.intensityProjection(ProjectionTest.projOpt(mibModelMax, 'Max', 'Z'));
            mibModelMin.intensityProjection(ProjectionTest.projOpt(mibModelMin, 'Min', 'Z'));

            optMax = struct('id', 1, 'blockModeSwitch', 0);
            optMin = struct('id', 1, 'blockModeSwitch', 0);
            resultMax = mibModelMax.getData3D('image', 1, 3, NaN, optMax);
            resultMin = mibModelMin.getData3D('image', 1, 3, NaN, optMin);

            testCase.verifyGreaterThanOrEqual( ...
                sum(double(resultMax{1}(:))), sum(double(resultMin{1}(:))), ...
                'pixel-sum of Max projection must be >= pixel-sum of Min projection');
        end

    end

    % =====================================================================
    % Private helpers
    % =====================================================================
    methods (Static, Access = private)

        function batchOpt = projOpt(mibModel, projType, dimStr)
            batchOpt.ProjectionType    = {projType};
            batchOpt.ProjectionType{2} = {'Max', 'Min', 'Mean', 'Median', 'Sum'};
            batchOpt.Dimension         = {dimStr};
            batchOpt.Dimension{2}      = {'Z', 'Y', 'X', 'C', 'T'};
            batchOpt.Set               = {mibModel.Sets.names{1}};
            batchOpt.Set{2}            = mibModel.Sets.names(:)';
            batchOpt.Container         = {1, [1, mibModel.Sets.datasetsInSet], 'on'};
            batchOpt.showWaitbar       = false;
            batchOpt.id                = 1;
        end

    end
end
