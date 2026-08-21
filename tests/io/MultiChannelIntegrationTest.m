classdef MultiChannelIntegrationTest < matlab.unittest.TestCase
% Integration tests for multi-channel operations on a real-data 2-channel dataset.
%
% The Huh7 SBEM grayscale image is combined with itself to form a 2-channel
% dataset, and the corresponding label volume is loaded alongside it.  This
% keeps the test self-contained (no new downloads beyond what RoundTripTest
% already needs) while exercising multi-channel behaviour on a realistic,
% non-trivial image size (372 × 521 × 75).
%
% Channel layout:
%   ch1 - original Huh7 uint8 grayscale (SBEM)
%   ch2 - same volume again (independent copy; mutating one must not affect the other)
%
% Verification strategies:
%   color count       - MibDataset.image.colors == 2
%   channel isolation - getData3D with col=1 matches the Huh7 volume; col=2 independent
%   model load        - labels round-trip through setData3D / getData3D with correct material count
%   write isolation   - overwriting ch1 with zeros leaves ch2 intact on a subregion

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration', 'RequiresNetwork'})

        function twoChannel_colorCountIsTwo(testCase)
            mibModel = MultiChannelIntegrationTest.buildTwoChannelHuh7Model(testCase);

            testCase.verifyEqual(mibModel.I{1}.image.colors, 2, ...
                'two-channel Huh7 model must report colors == 2');
        end

        function twoChannel_channel1MatchesHuh7(testCase)
            [mibModel, imageVol] = MultiChannelIntegrationTest.buildTwoChannelHuh7Model(testCase);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            result = mibModel.getData3D('image', 1, 3, 1, opt);

            testCase.verifyEqual(squeeze(result{1}), squeeze(imageVol), ...
                'getData3D col=1 must return the original Huh7 volume');
        end

        function twoChannel_overwriteChannel1_channel2Intact(testCase)
            [mibModel, imageVol] = MultiChannelIntegrationTest.buildTwoChannelHuh7Model(testCase);
            opt  = struct('id', 1, 'blockModeSwitch', 0);
            dims = size(imageVol);  % [H W D 1]

            zeros3D = zeros(dims(1), dims(2), dims(3), 1, 'uint8');
            mibModel.setData3D({zeros3D}, 'image', 1, 3, 1, opt);

            result2 = mibModel.getData3D('image', 1, 3, 2, opt);
            testCase.verifyEqual(squeeze(result2{1}), squeeze(imageVol), ...
                'overwriting channel 1 with zeros must leave channel 2 unchanged');
        end

        function twoChannel_labelsRoundTrip_materialCountCorrect(testCase)
            [mibModel, ~, labelVol, materialNames] = ...
                MultiChannelIntegrationTest.buildTwoChannelHuh7Model(testCase);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            result = mibModel.getData3D('labels', 1, 3, NaN, opt);

            testCase.verifyEqual(squeeze(result{1}), labelVol, ...
                'labels round-trip must return the original label volume');
            testCase.verifyEqual(numel(mibModel.I{1}.labels.materialNames), ...
                numel(materialNames), ...
                'material name count must match the Huh7 spec after loading');
        end

    end

    methods (Static, Access = private)

        function [mibModel, imageVol, labelVol, materialNames] = buildTwoChannelHuh7Model(testCase)
            spec = mibtest.helpers.datasetSpec('Huh7');
            testCase.assumeTrue(mibtest.helpers.hasTestData(spec), ...
                'Huh7 test data not cached and server is unreachable - skipping');

            dataFixture   = testCase.applyFixture(mibtest.fixtures.ExampleDataFixture('Huh7'));
            imageVol      = dataFixture.Image;    % [372 521 75 1] uint8
            labelVol      = dataFixture.Labels;   % [372 521 75]   uint8
            materialNames = dataFixture.MaterialNames;

            % Two channels: the same grayscale volume used for both
            twoChannelVol = cat(4, imageVol, imageVol);  % [372 521 75 2]

            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            mibFolder   = fullfile(fileparts(testsFolder), 'mib');

            mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
            mibModel.I{1} = core.MibDataset(twoChannelVol, dictionary(), 'Standard', 'labels63');
            mibModel.I{1}.updateBoundingBox([], [0 0 0]);
            mibModel.I{1}.createModel(255);

            % Set pixel size from spec
            pixSize = dataFixture.PixSize;
            newPix  = mibModel.I{1}.image.pixSize;
            newPix.x = pixSize.x;  newPix.y = pixSize.y;  newPix.z = pixSize.z;
            mibModel.I{1}.setPixSize(newPix);

            % Load labels and material names
            opt = struct('id', 1, 'blockModeSwitch', 0);
            mibModel.setData3D(labelVol, 'labels', 1, 3, NaN, opt);
            for k = 1:numel(materialNames)
                mibModel.I{1}.addMaterial(materialNames{k});
            end
        end

    end
end
