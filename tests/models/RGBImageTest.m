classdef RGBImageTest < matlab.unittest.TestCase
% RGBIMAGETEST - Unit tests for MibModel.getRGBimage.
%
% Phase 0 confirmed getRGBimage works headlessly. Tests use
%   options.resizeToMagnification = false  - magnificationFactor = 1, no resize
%   options.useLut = false                 - direct grayscale mapping, predictable pixels
%   options.sliceNo = 1                    - fix slice to avoid current-position dependency
%   options.blockModeSwitch = 0            - return full slice, not cropped viewport
%
% Verification strategies:
%   output size     - [h, w, 3] for a single-channel h×w image
%   output class    - uint8
%   all-white input - all-255 single-channel image produces all-255 RGB
%   all-black input - all-0 single-channel image produces all-0 RGB

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

        function getRGBimage_overlayAnnotationsAreDrawnApartFromAnnotations(testCase)
            % MibDataset.overlayAnnotations: drawn whatever showAnnotations, near the shown
            % slice only, without touching the annotations of the dataset
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [64 64 12]);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            mibModel.setData3D(zeros(64, 64, 12, 1, 'uint8'), 'image', 1, 3, [], opt);
            mibModel.showModel = false;
            mibModel.showMask  = false;
            mibModel.showAnnotations = false;
            mibModel.I{1}.clearLayer('selection');

            places = core.Annotations();
            places.addLabels({'1'; '2'}, [1 10 12 1; 12 50 50 1]);    % [z x y t]: slice 1, and slice 12 far away
            mibModel.I{1}.overlayAnnotations = places;
            [rgb, ~] = mibModel.getRGBimage(RGBImageTest.displayOpt(), 1);

            testCase.verifyGreaterThan(max(rgb(11:13, 9:11, :), [], 'all'), uint8(0), ...
                'the point of slice 1 is drawn, with Show annotations off');
            testCase.verifyEqual(max(rgb(48:52, 48:52, :), [], 'all'), uint8(0), ...
                'the point of slice 12 is beyond the shown depth');
            testCase.verifyEqual(mibModel.I{1}.annotations.getLabelsNumber(), 0, ...
                'the annotations of the dataset are not touched');

            mibModel.I{1}.overlayAnnotations = [];
            [rgb, ~] = mibModel.getRGBimage(RGBImageTest.displayOpt(), 1);
            testCase.verifyEqual(max(rgb(:)), uint8(0), 'cleared: nothing is drawn');
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
