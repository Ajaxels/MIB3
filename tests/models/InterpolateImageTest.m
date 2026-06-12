classdef InterpolateImageTest < matlab.unittest.TestCase
% INTERPOLATEIMAGETEST - Unit tests for MibModel.interpolateImage.
%
% The method fills in intermediate slices between two annotated slices using
% either shape interpolation (blobs) or line interpolation (membranes).
%
% Call pattern: mibModel.interpolateImage(imgType, intType, BatchOptIn)
% gives nargin=4, triggering the batch path (no dialogs).
%
% Verification strategies:
%   shape interpolation — annotate selection at z=1 and z=3; leave z=2
%                         empty; after interpolation z=2 must be non-zero
%   mask target         — same logic for the Mask layer
%   empty input         — all-zero selection stays all-zero (no-op)
%   image unchanged     — image pixels must not be modified

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function interpolate_shape_selection_middleSliceFilled(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 5]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            selVolume = zeros(32, 32, 5, 'uint8');
            selVolume(10:22, 10:22, 1) = 1;   % blob at z=1
            selVolume(10:22, 10:22, 3) = 1;   % identical blob at z=3; z=2 left empty
            mibModel.I{1}.clearLayer('selection');
            mibModel.setData3D(selVolume, 'selection', 1, 3, [], opt);

            mibModel.interpolateImage('selection', 'shape', ...
                InterpolateImageTest.interpOpt('selection'));

            result = cell2mat(mibModel.getData3D('selection', 1, 3, [], opt));
            testCase.verifyGreaterThan( ...
                sum(double(result(:, :, 2)), 'all'), 0, ...
                'shape interpolation must fill the empty middle slice');
        end

        function interpolate_shape_mask_middleSliceFilled(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 5]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            maskVolume = zeros(32, 32, 5, 'uint8');
            maskVolume(8:20, 8:20, 1) = 1;
            maskVolume(8:20, 8:20, 3) = 1;
            mibModel.I{1}.clearLayer('mask');
            mibModel.setData3D(maskVolume, 'mask', 1, 3, [], opt);

            mibModel.interpolateImage('mask', 'shape', ...
                InterpolateImageTest.interpOpt('mask'));

            result = cell2mat(mibModel.getData3D('mask', 1, 3, [], opt));
            testCase.verifyGreaterThan( ...
                sum(double(result(:, :, 2)), 'all'), 0, ...
                'shape interpolation on mask must fill the empty middle slice');
        end

        function interpolate_emptySelection_remainsZero(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 5]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.I{1}.clearLayer('selection');

            mibModel.interpolateImage('selection', 'shape', ...
                InterpolateImageTest.interpOpt('selection'));

            result = cell2mat(mibModel.getData3D('selection', 1, 3, [], opt));
            testCase.verifyEqual(sum(double(result(:))), 0, ...
                'interpolating an empty selection must leave it empty');
        end

        function interpolate_imageLayerUnchanged(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [32 32 5]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            selVolume = zeros(32, 32, 5, 'uint8');
            selVolume(10:20, 10:20, 1) = 1;
            selVolume(10:20, 10:20, 3) = 1;
            mibModel.I{1}.clearLayer('selection');
            mibModel.setData3D(selVolume, 'selection', 1, 3, [], opt);

            mibModel.interpolateImage('selection', 'shape', ...
                InterpolateImageTest.interpOpt('selection'));

            imgAfter = cell2mat(mibModel.getData3D('image', 1, 3, NaN, opt));
            testCase.verifyEqual(squeeze(imgAfter), squeeze(groundTruth.image), ...
                'image pixels must not change during interpolation');
        end

    end

    % =====================================================================
    % Private helpers
    % =====================================================================
    methods (Static, Access = private)

        function batchOpt = interpOpt(targetLayer)
            batchOpt.Target              = {targetLayer};
            batchOpt.InterpolationType   = {'shape'};
            batchOpt.MaterialIndex       = '1';
            batchOpt.showWaitbar         = false;
            batchOpt.id                  = 1;
        end

    end
end
