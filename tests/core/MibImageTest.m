classdef MibImageTest < matlab.unittest.TestCase
% MIBIAMGETEST - Unit tests for core.MibImage properties via MibDataset construction.
%
% MibImage is always created through MibDataset.  All tests build a minimal
% MibDataset and inspect the ds.image properties to verify dims, dataClass,
% and exists flag.

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function uint8VolumeConstructedCorrectly(testCase)
            volume = uint8(randi(255, [32 48 8 1]));   % [H W D C]
            ds = core.MibDataset(volume, dictionary(), 'Standard', 'labels63');

            testCase.verifyEqual(ds.image.height,    32);
            testCase.verifyEqual(ds.image.width,     48);
            testCase.verifyEqual(ds.image.depth,      8);
            testCase.verifyEqual(ds.image.colors,     1);
            testCase.verifyEqual(ds.image.dataClass, 'uint8');
            testCase.verifyTrue(ds.image.exists);
        end

        function uint16VolumePreservesDataClass(testCase)
            volume = uint16(randi(65535, [16 16 4 1]));
            ds = core.MibDataset(volume, dictionary(), 'Standard', 'labels63');

            testCase.verifyEqual(ds.image.dataClass, 'uint16');
            testCase.verifyEqual(class(ds.image.data), 'uint16');
        end

        function multiChannelVolumeHasCorrectColorCount(testCase)
            volume = uint8(randi(255, [24 24 6 3]));   % 3 color channels
            ds = core.MibDataset(volume, dictionary(), 'Standard', 'imageOnly');

            testCase.verifyEqual(ds.image.colors, 3);
            testCase.verifyEqual(ds.image.depth,   6);
        end

        function dim_yxzctMatchesDataSize(testCase)
            volume = uint8(zeros(20, 30, 5, 1));   % [H W D C]
            ds = core.MibDataset(volume, dictionary(), 'Standard', 'labels63');

            testCase.verifyEqual(ds.image.dim_yxzct, [20 30 5 1 1]);
            testCase.verifyEqual(size(ds.image.data), [20 30 5]);
        end

        function singleSliceVolumeHasDepthOne(testCase)
            volume = uint8(randi(255, [64 64 1]));
            ds = core.MibDataset(volume, dictionary(), 'Standard', 'imageOnly');

            testCase.verifyEqual(ds.image.depth, 1);
            testCase.verifyEqual(ds.image.height, 64);
            testCase.verifyEqual(ds.image.width, 64);
        end

    end
end
