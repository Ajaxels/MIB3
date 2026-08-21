classdef ColorChannelTest < matlab.unittest.TestCase
% COLORCHANNELTEST - Unit tests for MibModel.colorChannelActions.
%
% Call pattern: mibModel.colorChannelActions(mode, [], batchOpt)
% gives nargin=4 (obj + mode + channel1 + BatchOptIn) which triggers
% the batch path - no dialogs shown.
%
% Verification strategies:
%   invert round-trip   - double-invert of ch1 restores original pixels
%   invert complement   - single invert: pixel = 255 − original
%   insert channel      - Insert empty channel: colors + 1
%   delete channel      - Delete channel from 2-channel image: colors − 1
%   swap channels       - ch1/ch2 pixel values are exchanged

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function invertChannel_doubleInvert_isIdentity(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.colorChannelActions('Invert channel', [], ColorChannelTest.invertOpt(1));
            mibModel.colorChannelActions('Invert channel', [], ColorChannelTest.invertOpt(1));

            result = mibModel.getData3D('image', 1, 3, 1, opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(groundTruth.image), ...
                'two inverts of channel 1 must restore the original pixels');
        end

        function invertChannel_pixelComplement(testCase)
            [mibModel, groundTruth] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            mibModel.colorChannelActions('Invert channel', [], ColorChannelTest.invertOpt(1));

            result = mibModel.getData3D('image', 1, 3, 1, opt);
            expected = uint8(255) - squeeze(groundTruth.image);
            testCase.verifyEqual(squeeze(result{1}), expected, ...
                'inverted channel 1 must equal 255 minus original');
        end

        function insertEmptyChannel_colorCountIncreasedByOne(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4]);
            colorsBefore = mibModel.I{1}.image.colors;

            batchOpt.Action      = {'Insert empty channel'};
            batchOpt.Channel1    = {0, [0, colorsBefore + 1], 'on'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.colorChannelActions('Insert empty channel', [], batchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.colors, colorsBefore + 1, ...
                'inserting a channel must increase the color count by 1');
        end

        function deleteChannel_colorCountDecreasedByOne(testCase)
            [mibModel, ~, ~] = ColorChannelTest.buildTwoChannelModel(16, 16, 4);

            batchOpt.Action      = {'Delete channel'};
            batchOpt.Channel1    = {1, [1, 2], 'on'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.colorChannelActions('Delete channel', [], batchOpt);

            testCase.verifyEqual(mibModel.I{1}.image.colors, 1, ...
                'deleting one of two channels must leave a single channel');
        end

        function swapChannels_pixelValuesExchanged(testCase)
            [mibModel, ch1Before, ch2Before] = ColorChannelTest.buildTwoChannelModel(16, 16, 4);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            batchOpt.Action      = {'Swap channels'};
            batchOpt.Channel1    = {1, [1, 2], 'on'};
            batchOpt.Channel2    = {2, [1, 2], 'on'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
            mibModel.colorChannelActions('Swap channels', [], batchOpt);

            result1 = mibModel.getData3D('image', 1, 3, 1, opt);
            result2 = mibModel.getData3D('image', 1, 3, 2, opt);
            testCase.verifyEqual(squeeze(result1{1}), squeeze(ch2Before), ...
                'channel 1 after swap must contain the original channel 2 data');
            testCase.verifyEqual(squeeze(result2{1}), squeeze(ch1Before), ...
                'channel 2 after swap must contain the original channel 1 data');
        end

    end

    % =====================================================================
    % Private helpers
    % =====================================================================
    methods (Static, Access = private)

        function batchOpt = invertOpt(channelIndex)
            batchOpt.Action      = {'Invert channel'};
            batchOpt.Channel1    = {channelIndex, [1, channelIndex], 'on'};
            batchOpt.showWaitbar = false;
            batchOpt.id          = 1;
        end

        function [mibModel, ch1Data, ch2Data] = buildTwoChannelModel(height, width, depth)
            % Two-channel model: ch1 = random uint8 (seed 7), ch2 = all zeros.
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            mibFolder   = fullfile(fileparts(testsFolder), 'mib');
            rng(7, 'twister');
            ch1Data = uint8(randi(200, [height, width, depth, 1]));
            ch2Data = zeros([height, width, depth, 1], 'uint8');
            imgData = cat(4, ch1Data, ch2Data);
            mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            mibModel.I{1} = core.MibDataset(imgData, dictionary(), 'Standard', 'labels63');
            mibModel.I{1}.updateBoundingBox([], [0 0 0]);
            mibModel.I{1}.createModel(255);
        end

    end
end
