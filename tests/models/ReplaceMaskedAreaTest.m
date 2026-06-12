classdef ReplaceMaskedAreaTest < matlab.unittest.TestCase
% REPLACEMASKEDAREATEST - Unit tests for MibModel.replaceMaskedArea.
%
% Verification strategies:
%   masked pixels set    — foreground pixels in the mask/selection layer
%                          are overwritten with the specified fill value
%   unmasked unchanged   — boolean indexing confirms pixels outside the
%                          mask are byte-identical before and after
%   empty mask           — all-zero mask leaves the image untouched
%   full mask            — entire layer masked → entire image equals fill value
%   selection target     — same mechanics work when target = 'selection'

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function replaceMask_maskedPixelsSetToZero(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            ReplaceMaskedAreaTest.setBlockMask(mibModel, 'mask', [8 16 8 16]);

            imgBefore = cell2mat(mibModel.getData3D('image', 1, 3, NaN, opt));
            testCase.assumeGreaterThan( ...
                sum(double(imgBefore(8:16, 8:16, :, :, :)), 'all'), 0, ...
                'masked region must have non-zero pixels to be a meaningful test');

            mibModel.replaceMaskedArea('mask', ReplaceMaskedAreaTest.fillOpt('mask', 0));

            imgAfter = cell2mat(mibModel.getData3D('image', 1, 3, NaN, opt));
            testCase.verifyEqual( ...
                sum(double(imgAfter(8:16, 8:16, :, :, :)), 'all'), 0.0, ...
                'masked pixels must be 0 after black fill');
        end

        function replaceMask_unmaskedPixelsUntouched(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            maskLayer = zeros(32, 32, 4, 'uint8');
            maskLayer(8:16, 8:16, :) = 1;
            mibModel.I{1}.clearLayer('mask');
            mibModel.setData3D(maskLayer, 'mask', 1, 3, NaN, opt);

            imgBefore = cell2mat(mibModel.getData3D('image', 1, 3, NaN, opt));

            mibModel.replaceMaskedArea('mask', ReplaceMaskedAreaTest.fillOpt('mask', 0));

            imgAfter = cell2mat(mibModel.getData3D('image', 1, 3, NaN, opt));
            maskBool  = logical(maskLayer);
            testCase.verifyEqual(imgAfter(~maskBool), imgBefore(~maskBool), ...
                'pixels outside the mask must not change');
        end

        function replaceMask_emptyMask_imageUnchanged(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.clearLayer('mask');

            imgBefore = cell2mat(mibModel.getData3D('image', 1, 3, NaN, opt));
            checksumBefore = sum(double(imgBefore(:)));

            mibModel.replaceMaskedArea('mask', ReplaceMaskedAreaTest.fillOpt('mask', 0));

            imgAfter = cell2mat(mibModel.getData3D('image', 1, 3, NaN, opt));
            testCase.verifyEqual(sum(double(imgAfter(:))), checksumBefore, ...
                'empty mask must not change any image pixels');
        end

        function replaceSelection_maskedPixelsSetToValue(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            ReplaceMaskedAreaTest.setBlockMask(mibModel, 'selection', [5 12 5 12]);

            mibModel.replaceMaskedArea('selection', ReplaceMaskedAreaTest.fillOpt('selection', 0));

            imgAfter = cell2mat(mibModel.getData3D('image', 1, 3, NaN, opt));
            testCase.verifyEqual( ...
                sum(double(imgAfter(5:12, 5:12, :, :, :)), 'all'), 0.0, ...
                'selected pixels must be 0 after black fill via selection target');
        end

        function replaceMask_fullMask_allPixelsEqualFillValue(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            fullMask = ones(16, 16, 4, 'uint8');
            mibModel.I{1}.clearLayer('mask');
            mibModel.setData3D(fullMask, 'mask', 1, 3, NaN, opt);

            fillValue = 42;
            mibModel.replaceMaskedArea('mask', ReplaceMaskedAreaTest.fillOpt('mask', fillValue));

            imgAfter = cell2mat(mibModel.getData3D('image', 1, 3, NaN, opt));
            totalPixels = 16 * 16 * 4;
            testCase.verifyEqual( ...
                sum(double(imgAfter(:))), double(fillValue) * totalPixels, ...
                'full mask must set every pixel to the fill value');
        end

    end

    % =====================================================================
    % Private helpers
    % =====================================================================
    methods (Static, Access = private)

        function setBlockMask(mibModel, targetLayer, bounds)
            % Set a rectangular block in targetLayer to 1.
            % bounds = [rowMin rowMax colMin colMax]
            opt = struct('id', 1, 'blockModeSwitch', 0);
            depth = mibModel.I{1}.image.depth;
            mibModel.I{1}.clearLayer(targetLayer);
            layer = zeros(mibModel.I{1}.image.height, mibModel.I{1}.image.width, depth, 'uint8');
            layer(bounds(1):bounds(2), bounds(3):bounds(4), :) = 1;
            mibModel.setData3D(layer, targetLayer, 1, 3, NaN, opt);
        end

        function batchOpt = fillOpt(targetLayer, fillValue)
            batchOpt.Target          = {targetLayer};
            batchOpt.Target{2}       = {'mask', 'selection'};
            batchOpt.ColorChannel    = {'All'};
            batchOpt.ColorChannel{2} = {'All', 'Ch 1'};
            batchOpt.ColorIntensity  = {fillValue, [0, 255], 'on'};
            batchOpt.showWaitbar     = false;
            batchOpt.id              = 1;
            % mibBatchTooltip forces batchModeSwitch=1, skipping the interactive dialog.
            batchOpt.mibBatchTooltip = struct( ...
                'Target', '', 'ColorChannel', '', 'ColorIntensity', '', 'showWaitbar', '');
        end

    end
end
