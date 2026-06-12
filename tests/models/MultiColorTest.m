classdef MultiColorTest < matlab.unittest.TestCase
% Tests for multi-channel (multi-color) datasets using buildSyntheticModel('numColors', 2).
%
% Verifies that data accessors, channel-level operations, and getRGBimage all
% handle 2-channel images correctly — i.e. channels are stored and retrieved
% independently and operations on one channel do not bleed into the other.
%
% Verification strategies:
%   color count       — MibDataset.image.colors reports 2
%   channel isolation — getData3D with col=1/2 returns the expected channel
%   write isolation   — setData3D to col=1 does not change col=2
%   invert isolation  — colorChannelActions invert on ch1 does not change ch2
%   RGB output        — getRGBimage returns [h w 3] uint8 for a 2-channel input

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function twoChannelModel_correctColorCount(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4], 'numColors', 2);

            testCase.verifyEqual(mibModel.I{1}.image.colors, 2, ...
                'buildSyntheticModel with numColors=2 must produce a 2-channel MibDataset');
        end

        function getData3D_channel1_matchesGroundTruth(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4], 'numColors', 2);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            result = mibModel.getData3D('image', 1, 3, 1, opt);

            testCase.verifyEqual(squeeze(result{1}), squeeze(groundTruth.image(:,:,:,1)), ...
                'getData3D with col=1 must return the first channel verbatim');
        end

        function getData3D_channel2_matchesGroundTruth(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4], 'numColors', 2);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            result = mibModel.getData3D('image', 1, 3, 2, opt);

            testCase.verifyEqual(squeeze(result{1}), squeeze(groundTruth.image(:,:,:,2)), ...
                'getData3D with col=2 must return the second channel verbatim');
        end

        function setData3D_overwriteChannel1_channel2Unchanged(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4], 'numColors', 2);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            zeros3D = zeros(16, 24, 4, 1, 'uint8');
            mibModel.setData3D({zeros3D}, 'image', 1, 3, 1, opt);

            result2 = mibModel.getData3D('image', 1, 3, 2, opt);
            testCase.verifyEqual(squeeze(result2{1}), squeeze(groundTruth.image(:,:,:,2)), ...
                'overwriting channel 1 must not alter channel 2 pixels');
        end

        function invertChannel1_channel2Unchanged(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4], 'numColors', 2);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            batchOpt.Action      = {'Invert channel'};
            batchOpt.Channel1    = {1, [1, 2], 'on'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.colorChannelActions('Invert channel', [], batchOpt);

            result2 = mibModel.getData3D('image', 1, 3, 2, opt);
            testCase.verifyEqual(squeeze(result2{1}), squeeze(groundTruth.image(:,:,:,2)), ...
                'inverting channel 1 must leave channel 2 pixels unchanged');
        end

        function getRGBimage_twoChannels_outputSizeAndClass(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4], 'numColors', 2);
            mibModel.showModel = false;
            mibModel.showMask  = false;

            options.blockModeSwitch       = 0;
            options.resizeToMagnification = false;
            options.useLut                = false;
            options.sliceNo               = 1;
            rgb = mibModel.getRGBimage(options, 1);

            testCase.verifyEqual(size(rgb), [16 24 3], ...
                'getRGBimage on a 2-channel dataset must produce an [h w 3] output');
            testCase.verifyClass(rgb, 'uint8', ...
                'getRGBimage must return uint8 regardless of channel count');
        end

    end
end
