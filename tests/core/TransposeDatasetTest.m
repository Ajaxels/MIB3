classdef TransposeDatasetTest < matlab.unittest.TestCase
% TRANSPOSEDATASETTEST - Unit tests for MibDataset.transposeDataset.
%
% Call pattern: mibModel.I{1}.transposeDataset(mode, [], false)
%   parentFigure = [] suppresses the progress dialog.
%
% Verification strategies:
%   Z<->T dim swap   — depth and time are exchanged
%   Z<->T round-trip — double transpose restores original dims and pixel data
%   YX->XY dim swap  — height and width are exchanged
%   YX->YZ dim swap  — width becomes old depth and depth becomes old width

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function transposeZT_depthAndTimeSwapped(testCase)
            % Dataset: [h=16, w=24, d=6, c=1, t=1]
            % After Z<->T: depth = old time = 1; time = old depth = 6
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 6]);

            mibModel.I{1}.transposeDataset('Transpose Z<->T', [], false);

            testCase.verifyEqual(mibModel.I{1}.image.depth, 1, ...
                'after Z<->T transpose depth must equal original time (1)');
            testCase.verifyEqual(mibModel.I{1}.image.time, 6, ...
                'after Z<->T transpose time must equal original depth (6)');
        end

        function transposeZT_roundTrip_dimsRestored(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 6]);

            mibModel.I{1}.transposeDataset('Transpose Z<->T', [], false);
            mibModel.I{1}.transposeDataset('Transpose Z<->T', [], false);

            testCase.verifyEqual(mibModel.I{1}.image.height, 16);
            testCase.verifyEqual(mibModel.I{1}.image.width,  24);
            testCase.verifyEqual(mibModel.I{1}.image.depth,   6);
            testCase.verifyEqual(mibModel.I{1}.image.time,    1);
        end

        function transposeZT_roundTrip_pixelsRestored(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 6]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.transposeDataset('Transpose Z<->T', [], false);
            mibModel.I{1}.transposeDataset('Transpose Z<->T', [], false);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(groundTruth.image), ...
                'double Z<->T transpose must restore every pixel value');
        end

        function transposeYXtoXY_heightAndWidthSwapped(testCase)
            % YX->XY swaps H and W: [16,24,6] → [24,16,6]
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 6]);

            mibModel.I{1}.transposeDataset('Transpose YX -> XY', [], false);

            testCase.verifyEqual(mibModel.I{1}.image.height, 24, ...
                'after YX->XY: new height = original width');
            testCase.verifyEqual(mibModel.I{1}.image.width,  16, ...
                'after YX->XY: new width = original height');
            testCase.verifyEqual(mibModel.I{1}.image.depth,   6, ...
                'after YX->XY: depth must not change');
        end

        function transposeYXtoYZ_widthAndDepthSwapped(testCase)
            % YX->YZ swaps W and D: [16,24,6] → [16,6,24]
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 6]);

            mibModel.I{1}.transposeDataset('Transpose YX -> YZ', [], false);

            testCase.verifyEqual(mibModel.I{1}.image.height, 16, ...
                'after YX->YZ: height must not change');
            testCase.verifyEqual(mibModel.I{1}.image.width,   6, ...
                'after YX->YZ: new width = original depth');
            testCase.verifyEqual(mibModel.I{1}.image.depth,  24, ...
                'after YX->YZ: new depth = original width');
        end

    end
end
