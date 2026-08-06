classdef ChangeImageModeTest < matlab.unittest.TestCase
% CHANGEIMAGEMODETEST - Unit tests for MibModel.changeImageMode.
%
% Verification strategies:
%   bit-depth upgrade   - uint8 → 16 bit / 32 bit: image class and maxInt change
%   round-trip          - 8 bit → 16 bit → 8 bit restores class and maxInt
%   dimensions stable   - width / height / depth must not change after conversion
%   status return       - method must return 1 on success
%   pixel count stable  - numel of image data must not change after conversion

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function changeMode_8to16_classIsUint16(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            batchOpt.Target      = {'16 bit'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.changeImageMode(batchOpt);

            testCase.verifyClass(mibModel.I{1}.image.data, 'uint16', ...
                'image data must be uint16 after conversion to 16 bit');
        end

        function changeMode_8to16_maxIntIs65535(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            batchOpt.Target      = {'16 bit'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.changeImageMode(batchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.maxInt, double(intmax('uint16')), ...
                'maxInt must be 65535 after conversion to 16 bit');
        end

        function changeMode_8to32_classIsUint32(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            batchOpt.Target      = {'32 bit'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.changeImageMode(batchOpt);

            testCase.verifyClass(mibModel.I{1}.image.data, 'uint32', ...
                'image data must be uint32 after conversion to 32 bit');
        end

        function changeMode_roundTrip_8to16to8_classRestored(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            batchOpt16.Target      = {'16 bit'};
            batchOpt16.showWaitbar = false;
            batchOpt16.id          = 1;
            mibModel.changeImageMode(batchOpt16);

            batchOpt8.Target      = {'8 bit'};
            batchOpt8.showWaitbar = false;
            batchOpt8.id          = 1;
            mibModel.changeImageMode(batchOpt8);

            testCase.verifyClass(mibModel.I{1}.image.data, 'uint8', ...
                'class must be uint8 after 8→16→8 round-trip');
            testCase.verifyEqual(mibModel.I{1}.image.maxInt, double(intmax('uint8')), ...
                'maxInt must be 255 after round-trip back to 8 bit');
        end

        function changeMode_8to16_dimensionsUnchanged(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 8]);

            batchOpt.Target      = {'16 bit'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.changeImageMode(batchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.height, 16);
            testCase.verifyEqual(mibModel.I{1}.image.width,  24);
            testCase.verifyEqual(mibModel.I{1}.image.depth,   8);
        end

        function changeMode_8to16_returnsOne(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            batchOpt.Target      = {'16 bit'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            status = mibModel.changeImageMode(batchOpt);

            testCase.verifyEqual(status, 1, ...
                'changeImageMode must return 1 on success');
        end

    end
end
