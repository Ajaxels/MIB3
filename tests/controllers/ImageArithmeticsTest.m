classdef ImageArithmeticsTest < matlab.unittest.TestCase
% IMAGEARITHMETICSTEST - Image Arithmetics on Standard datasets, through the batch path of controllers.ImageArithmetics.
%
% Covers the variable parsing of ``runExpressionBtn_Callback``: the active
% buffer, a numbered buffer as input and output (a new dataset in another
% buffer), a repeated input, and a mask result.
%
% See also: controllers.ImageArithmetics, ImageArithmeticsBigDataTest

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function activeBufferInPlace(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel(dims = [32 40 3]);
            controllers.ImageArithmetics(mibModel, [], testCase.batchOpt('I', 'I', 'I = I + 7'));
            testCase.verifyEqual(mibModel.I{1}.image.data, groundTruth.image + 7);
        end

        function resultInAnotherBuffer(testCase)
            % "I2 = I1 * 2" creates a dataset in buffer 2 and leaves buffer 1 as it was.
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel(dims = [32 40 3], numColors = 2);
            controllers.ImageArithmetics(mibModel, [], testCase.batchOpt('I1, I1', 'I2', 'I2 = I1 * 2'));
            testCase.verifyEqual(mibModel.I{2}.image.data, groundTruth.image * 2);
            testCase.verifyEqual(mibModel.I{1}.image.data, groundTruth.image);
        end

        function channelIndexing(testCase)
            % The image is [H W Z C]: I(:,:,:,2) is the second channel.
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel(dims = [32 40 3], numColors = 2);
            controllers.ImageArithmetics(mibModel, [], testCase.batchOpt('I', 'I', 'I(:,:,:,2) = 0'));
            expected = groundTruth.image;
            expected(:,:,:,2) = 0;
            testCase.verifyEqual(mibModel.I{1}.image.data, expected);
        end

        function thresholdIntoTheMask(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel(dims = [32 40 3]);
            controllers.ImageArithmetics(mibModel, [], testCase.batchOpt('I', 'M', 'M = uint8(I > 100)'));
            options = struct('blockModeSwitch', 0, 'id', 1);
            mask = cell2mat(mibModel.getData4D('mask', 3, NaN, options));
            testCase.verifyEqual(mask, uint8(groundTruth.image > 100));
        end
    end

    methods (Static)
        function BatchOpt = batchOpt(inputVariables, outputVariables, expression)
            BatchOpt = struct('InputVariables', inputVariables, 'OutputVariables', outputVariables, ...
                'Expression', expression, 'showWaitbar', false);
        end
    end
end
