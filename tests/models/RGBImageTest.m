classdef RGBImageTest < matlab.unittest.TestCase
% RGBIMAGETEST - Unit tests for MibModel.getRGBimage.
%
% Phase 0 confirmed getRGBimage works headlessly. Tests use
%   options.resizeToMagnification = false  — magnificationFactor = 1, no resize
%   options.useLut = false                 — direct grayscale mapping, predictable pixels
%   options.sliceNo = 1                    — fix slice to avoid current-position dependency
%   options.blockModeSwitch = 0            — return full slice, not cropped viewport
%
% Verification strategies:
%   output size     — [h, w, 3] for a single-channel h×w image
%   output class    — uint8
%   all-white input — all-255 single-channel image produces all-255 RGB
%   all-black input — all-0 single-channel image produces all-0 RGB

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function getRGBimage_outputSizeIsHxWx3(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);

            [rgb, ~] = mibModel.getRGBimage(RGBImageTest.displayOpt(), 1);

            testCase.verifySize(rgb, [16 24 3], ...
                'RGB output must be [height × width × 3]');
        end

        function getRGBimage_outputClassIsUint8(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);

            [rgb, ~] = mibModel.getRGBimage(RGBImageTest.displayOpt(), 1);

            testCase.verifyClass(rgb, 'uint8', ...
                'RGB output must be uint8');
        end

        function getRGBimage_allWhiteInput_rgbIsAllWhite(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            whiteImg = uint8(255 * ones(16, 16, 4, 1));
            mibModel.setData3D(whiteImg, 'image', 1, 3, [], opt);
            mibModel.showModel = false;
            mibModel.showMask  = false;
            mibModel.I{1}.clearLayer('selection');

            [rgb, ~] = mibModel.getRGBimage(RGBImageTest.displayOpt(), 1);

            testCase.verifyEqual(min(rgb(:)), uint8(255), ...
                'all-white input must produce all-255 RGB output');
        end

        function getRGBimage_allBlackInput_rgbIsAllBlack(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            blackImg = zeros(16, 16, 4, 1, 'uint8');
            mibModel.setData3D(blackImg, 'image', 1, 3, [], opt);
            mibModel.showModel = false;
            mibModel.showMask  = false;
            mibModel.I{1}.clearLayer('selection');

            [rgb, ~] = mibModel.getRGBimage(RGBImageTest.displayOpt(), 1);

            testCase.verifyEqual(max(rgb(:)), uint8(0), ...
                'all-black input must produce all-0 RGB output');
        end

    end

    % =====================================================================
    % Private helpers
    % =====================================================================
    methods (Static, Access = private)

        function options = displayOpt()
            options.blockModeSwitch       = 0;
            options.resizeToMagnification = false;
            options.useLut                = false;
            options.sliceNo               = 1;
        end

    end
end
